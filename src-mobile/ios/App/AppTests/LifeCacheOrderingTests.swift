import Foundation
import Testing
@testable import App

private actor LifeCacheWriteGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pauseFirst() async {
        guard !entered else { return }
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor LifeCacheDisk {
    private(set) var value: LifeSummaryCache?
    private(set) var writes = 0
    private(set) var removals = 0

    func write(_ value: LifeSummaryCache) {
        writes += 1
        self.value = value
    }

    func remove() {
        removals += 1
        value = nil
    }
}

@MainActor
struct LifeCacheOrderingTests {
    private func hours() -> ScheduleHoursConfiguration {
        .init(startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil,
                rotationRestDays: nil), breakStartTime: nil, breakDurationMinutes: 0)
    }

    private func life(
        records: RecordCoordinator,
        cache: LifeSummaryCacheStore,
        seedProfile: Bool = true
    ) throws -> LifeSummaryModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let configuration = hours()
        let suite = "LifeCacheOrdering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let plus = PlusEntitlement(defaults: defaults)
        plus.debugSetAuthorized(true)
        let queries = RecordsQueries(records: records, plus: plus, localizer: NativeLocalizer(), sources: .init(
            calendar: { calendar }, hours: { _ in configuration }, rules: { _, _ in nil },
            snapshot: { _ in nil }, isCounting: { false }, salaryIsVisible: { false },
            salaryType: { nil }, language: { "en" }))
        let life = LifeSummaryModel(queries: queries, readPreferences: { _ in
            LifeSummaryPreferences(hours: configuration, salary: .init(
                amount: "", enabled: false, type: "monthly", workingDays: 22, bonusMonths: 0
            ))
        }, lifeSummaryCache: cache)
        if seedProfile {
            life.saveLifeProfileV2(bornOn: .yearOnly(1990), schoolStartedOn: nil,
                workStartedOn: .yearOnly(2025), retirementOn: .yearOnly(2028), sleepHours: 8)
        }
        return life
    }

    private func cache(workShare: Double) -> LifeSummaryCache {
        LifeSummaryCache(
            key: LifeViewModelCacheKey(
                profile: nil,
                periods: [],
                snapshots: [],
                exceptions: [],
                overrides: [],
                observations: [],
                dayKey: "2026-09-12",
                timeZoneIdentifier: "UTC",
                hours: nil,
                salary: LifeSalaryPreferences(
                    amount: "", enabled: false, type: "monthly", workingDays: 0, bonusMonths: 0
                )
            ),
            model: LifeViewModel(cells: [], workShare: workShare, ownAwakeShare: 0)
        )
    }

    @Test("A removal requested while an older write is suspended wins")
    func removalFollowsPendingWrite() async {
        let gate = LifeCacheWriteGate()
        let disk = LifeCacheDisk()
        let store = LifeSummaryCacheStore(
            write: { value, _ in
                await gate.pauseFirst()
                await disk.write(value)
            },
            remove: { _ in await disk.remove() }
        )
        let url = URL(filePath: "/unused-life-cache")
        let write = Task.immediate { @MainActor in await store.write(cache(workShare: 1), to: url) }
        await gate.waitUntilEntered()
        let remove = Task.immediate { @MainActor in await store.remove(at: url) }
        await gate.release()
        await write.value
        await remove.value

        #expect(await disk.value == nil)
    }

    @Test("A newer write requested while an older write is suspended wins")
    func newerWriteFollowsPendingWrite() async {
        let gate = LifeCacheWriteGate()
        let disk = LifeCacheDisk()
        let store = LifeSummaryCacheStore(write: { value, _ in
            await gate.pauseFirst()
            await disk.write(value)
        })
        let url = URL(filePath: "/unused-life-cache")
        let oldWrite = Task.immediate { @MainActor in await store.write(cache(workShare: 1), to: url) }
        await gate.waitUntilEntered()
        let newWrite = Task.immediate { @MainActor in await store.write(cache(workShare: 2), to: url) }
        await gate.release()
        await oldWrite.value
        await newWrite.value

        #expect(await disk.value?.model.workShare == 2)
    }

    @Test("Clearing a profile while cache restore is suspended cannot enqueue a stale model write")
    func profileRemovalSupersedesPendingRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "life-cache-order-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LifeCacheWriteGate()
        let disk = LifeCacheDisk()
        let cache = LifeSummaryCacheStore(
            read: { _ in await gate.pauseFirst(); return nil },
            write: { value, _ in await disk.write(value) },
            remove: { _ in await disk.remove() }
        )
        let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        let life = try life(records: records, cache: cache)
        let now = Date(timeIntervalSince1970: 1_788_739_200)

        let staleRefresh = Task.immediate { @MainActor in await life.refreshLifeSummary(now: now) }
        await gate.waitUntilEntered()
        records.erase(.lifeProfile, key: LifeProfile.profileID.uuidString)
        let clearingRefresh = Task.immediate { @MainActor in await life.refreshLifeSummary(now: now) }
        await gate.release()
        await staleRefresh.value
        await clearingRefresh.value

        #expect(life.cachedLifeViewModel == nil)
        #expect(await disk.writes == 0)
        #expect(await disk.removals == 1)
        #expect(await disk.value == nil)
    }

    @Test("External clearing removes the cache without an active Life view")
    func externalClearRemovesCacheDirectly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "life-cache-clear-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = LifeCacheDisk()
        await disk.write(cache(workShare: 1))
        let cache = LifeSummaryCacheStore(
            read: { _ in await disk.value },
            write: { value, _ in await disk.write(value) },
            remove: { _ in await disk.remove() }
        )
        let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        let life = try life(records: records, cache: cache)

        records.erase(.lifeProfile, key: LifeProfile.profileID.uuidString)
        let removal = try #require(life.reconcileExternalState())
        await removal.value

        #expect(life.cachedLifeViewModel == nil)
        #expect(await disk.value == nil)
        #expect(await disk.removals == 1)
    }

    @Test("A replacement profile cache queued after external clearing survives removal")
    func replacementProfileFollowsReservedRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "life-cache-replace-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LifeCacheWriteGate()
        let disk = LifeCacheDisk()
        await disk.write(cache(workShare: 1))
        let cache = LifeSummaryCacheStore(
            read: { _ in await disk.value },
            write: { value, _ in await disk.write(value) },
            remove: { _ in await gate.pauseFirst(); await disk.remove() }
        )
        let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        let life = try life(records: records, cache: cache)
        let now = Date(timeIntervalSince1970: 1_788_739_200)

        records.erase(.lifeProfile, key: LifeProfile.profileID.uuidString)
        let removal = try #require(life.reconcileExternalState())
        life.saveLifeProfileV2(bornOn: .yearOnly(1991), schoolStartedOn: nil,
            workStartedOn: .yearOnly(2024), retirementOn: .yearOnly(2029), sleepHours: 8)
        let refresh = Task.immediate { @MainActor in await life.refreshLifeSummary(now: now) }
        await gate.waitUntilEntered()
        await gate.release()
        await removal.value
        await refresh.value

        #expect(await disk.removals == 1)
        #expect(await disk.writes == 2)
        #expect(await disk.value != nil)
        let persistedModel = await disk.value?.model
        #expect(life.cachedLifeViewModel == persistedModel)
    }

    @Test("Metadata-only external reconciliation preserves the prepared Life cache")
    func metadataOnlyReconciliationIsANoOp() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "life-cache-metadata-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = LifeCacheDisk()
        let cache = LifeSummaryCacheStore(
            read: { _ in await disk.value },
            write: { value, _ in await disk.write(value) },
            remove: { _ in await disk.remove() }
        )
        let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        let life = try life(records: records, cache: cache)
        let now = Date(timeIntervalSince1970: 1_788_739_200)
        await life.refreshLifeSummary(now: now)
        let prepared = try #require(life.cachedLifeViewModel)
        let writes = await disk.writes

        let operation = life.reconcileExternalState(at: now)

        if case .some = operation {
            Issue.record("Metadata-only reconciliation unexpectedly scheduled cache work")
        }
        #expect(life.cachedLifeViewModel == prepared)
        #expect(await disk.writes == writes)
        #expect(await disk.removals == 0)
    }

    @Test("A Life owner created after external clearing removes stale disk cache on its first hook")
    func lazyOwnerClearsStaleCache() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "life-cache-lazy-clear-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = LifeCacheDisk()
        await disk.write(cache(workShare: 1))
        let cache = LifeSummaryCacheStore(
            read: { _ in await disk.value },
            write: { value, _ in await disk.write(value) },
            remove: { _ in await disk.remove() }
        )
        let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
        let life = try life(records: records, cache: cache, seedProfile: false)
        let now = Date(timeIntervalSince1970: 1_788_739_200)

        let removal = try #require(life.reconcileExternalState(at: now))
        await removal.value
        let repeated = life.reconcileExternalState(at: now)

        #expect(life.cachedLifeViewModel == nil)
        #expect(await disk.value == nil)
        #expect(await disk.removals == 1)
        if case .some = repeated {
            Issue.record("An identical metadata callback scheduled a second removal")
        }
    }
}
