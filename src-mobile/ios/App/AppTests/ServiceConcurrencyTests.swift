import Foundation
import Testing
import UserNotifications
@testable import App

@MainActor
@Suite("Service operation ordering", .timeLimit(.minutes(1)))
struct ServiceConcurrencyTests {
    @Test("A failed archive save retains existing notifications; retry publishes the committed shift")
    func notificationsWaitForDurability() async throws {
        let suite = "owc.notification.persistence.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        let store = makeStore(defaults: defaults, fallback: false, records: records)
        var added = 0
        var removed: [String] = []
        let service = NotificationService(shiftCenter: .init(
            authorization: { .allowed },
            pendingIDs: { ["owc.shift.existing"] },
            deliveredIDs: { [] },
            add: { _ in added += 1 },
            removePending: { removed += $0 },
            removeDelivered: { _ in }
        ))
        await service.reschedule(shifts: store.shifts, now: now)
        #expect(records.persistenceError == .writeFailed)
        #expect(added == 0)
        #expect(removed.isEmpty)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await service.reschedule(shifts: store.shifts, now: now)
        #expect(records.persistenceError == nil)
        #expect(records.durableRevision == records.revision)
        #expect(added > 0)
        #expect(removed.contains("owc.shift.existing"))
    }

    @Test("A stopped shift drains an in-flight add before clearing", arguments: [false, true])
    func stopWhileAdding(fallback: Bool) async throws {
        let suite = "owc.notification.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults, fallback: fallback)
        let center = SuspendedNotificationCenter()
        let service = NotificationService(shiftCenter: center.adapter)
        let old = Task { await service.reschedule(shifts: store.shifts, now: now) }
        await center.entered.wait()
        // Immediate start ensures the stop is enqueued before releasing add.
        let stop = Task.immediate { await service.clearShiftNotifications() }
        stop.cancel() // Cleanup must survive cancellation of its view task.
        center.release.signal()
        await old.value
        await stop.value
        #expect(center.requests.isEmpty)
        #expect(center.delivered == ["owc.focus.keep"])
    }

    @Test("The newest reschedule wins even when it reuses notification IDs")
    func replaceWhileAdding() async throws {
        let suite = "owc.notification.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults, fallback: false)
        let center = SuspendedNotificationCenter()
        let service = NotificationService(shiftCenter: center.adapter)
        let old = Task { await service.reschedule(shifts: store.shifts, now: now) }
        await center.entered.wait()
        store.preferences.applyPreferences { $0.languageOverride = "zh-CN" }
        let replacement = Task.immediate { await service.reschedule(shifts: store.shifts, now: now) }
        center.release.signal()
        await old.value
        await replacement.value
        let expected = store.shifts.shiftReminders(at: now).filter {
            $0.atMs > now.timeIntervalSince1970 * 1_000 && $0.title != nil && $0.body != nil
        }
        #expect(!center.requests.isEmpty)
        #expect(Set(center.requests.keys) == Set(expected.map { "owc.shift.\($0.id)" }))
        for request in center.requests.values {
            let reminder = try #require(expected.first { "owc.shift.\($0.id)" == request.identifier })
            #expect(request.content.title == reminder.title)
            #expect(request.content.body == reminder.body)
        }
    }

    @Test("Late StoreKit evidence cannot replace newer authorization or its cache", arguments: [false, true])
    func newestEntitlementWins(newestAuthorized: Bool) async throws {
        let suite = "owc.entitlement.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let entered = TestSignal()
        let release = TestSignal()
        var calls = 0
        let entitlement = PlusEntitlement(defaults: defaults, fetchEvidence: {
            calls += 1
            let isOld = calls == 1
            if isOld {
                entered.signal()
                await release.wait()
            }
            return StoreKitEvidence(
                lifetime: .init(revoked: isOld ? newestAuthorized : !newestAuthorized),
                sawActiveSubscription: isOld ? !newestAuthorized : newestAuthorized
            )
        })
        let old = Task { await entitlement.refreshFromStore() }
        await entered.wait()
        await entitlement.refreshFromStore()
        release.signal()
        await old.value
        #expect(entitlement.isAuthorized == newestAuthorized)
        #expect(entitlement.hasActiveSubscription == newestAuthorized)
        #expect(PlusEntitlement(defaults: defaults).isAuthorized == newestAuthorized)
    }

    @Test("Setup polling coalesces without swallowing a newer StoreKit update")
    func setupPollingAllowsFreshEvidence() async throws {
        let suite = "owc.entitlement.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let entered = TestSignal()
        let release = TestSignal()
        var calls = 0
        let entitlement = PlusEntitlement(defaults: defaults, fetchEvidence: {
            calls += 1
            let isOld = calls == 1
            if isOld {
                entered.signal()
                await release.wait()
            }
            return StoreKitEvidence(lifetime: .init(revoked: !isOld))
        })
        let firstPoll = Task { await entitlement.checkCurrentEntitlements() }
        await entered.wait()
        let secondPoll = Task.immediate { await entitlement.checkCurrentEntitlements() }
        #expect(calls == 1)
        await entitlement.refreshFromStore()
        #expect(calls == 2)
        release.signal()
        await firstPoll.value
        await secondPoll.value
        #expect(!entitlement.isAuthorized)
        #expect(!PlusEntitlement(defaults: defaults).isAuthorized)
    }

    @Test("Stopping invalidates a StoreKit refresh already in flight")
    func stopInvalidatesRefresh() async throws {
        let suite = "owc.entitlement.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let entered = TestSignal()
        let release = TestSignal()
        let entitlement = PlusEntitlement(defaults: defaults, fetchEvidence: {
            entered.signal()
            await release.wait()
            return StoreKitEvidence(lifetime: .init(revoked: false))
        })
        let refresh = Task { await entitlement.refreshFromStore() }
        await entered.wait()
        entitlement.stop()
        release.signal()
        await refresh.value
        #expect(!entitlement.isAuthorized)
        #expect(defaults.data(forKey: "ios.native.plusCachedSnapshot") == nil)
    }

    private var now: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10))!
    }

    private func makeStore(defaults: UserDefaults, fallback: Bool, records: RecordCoordinator? = nil) -> AppRuntime {
        let store = AppRuntime(defaults: defaults, records: records ?? .inMemory())
        store.preferences.onboardingComplete = true
        store.preferences.applyPreferences { $0.scheduleMode = .off }
        store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
        store.preferences.applyPreferences { $0.endMinutes = 18 * 60 }
        store.preferences.applyPreferences { $0.lunchEnabled = false }
        store.preferences.applyPreferences { $0.lunchStartReminderEnabled = false }
        store.preferences.applyPreferences { $0.lunchEndReminderEnabled = false }
        store.preferences.applyPreferences { $0.microBreakEnabled = false }
        store.preferences.applyPreferences { $0.notificationMode = fallback ? .off : .simple }
        store.preferences.liveActivityEnabled = fallback
        store.preferences.applyPreferences { $0.languageOverride = "en" }
        store.shifts.startCountdown(at: now)
        return store
    }
}

/// Buffered, cancellation-aware handshake; no scheduler timing assumptions.
@MainActor
private final class TestSignal {
    private let channel = AsyncStream<Void>.makeStream()
    func signal() { channel.continuation.yield(()); channel.continuation.finish() }
    func wait() async {
        var iterator = channel.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
}

@MainActor
private final class SuspendedNotificationCenter {
    let entered = TestSignal()
    let release = TestSignal()
    var requests: [String: UNNotificationRequest] = [:]
    var delivered = ["owc.shift.delivered", "owc.focus.keep"]
    private var hasSuspended = false

    var adapter: NotificationService.ShiftCenter {
        .init(
            authorization: { .allowed },
            pendingIDs: { Array(self.requests.keys) },
            deliveredIDs: { self.delivered },
            add: { request in
                if !self.hasSuspended {
                    self.hasSuspended = true
                    self.entered.signal()
                    await self.release.wait()
                }
                self.requests[request.identifier] = request
            },
            removePending: { ids in for id in ids { self.requests[id] = nil } },
            removeDelivered: { ids in self.delivered.removeAll { ids.contains($0) } }
        )
    }
}
