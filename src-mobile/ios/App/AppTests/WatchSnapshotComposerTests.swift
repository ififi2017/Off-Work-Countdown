import Foundation
import Testing
@testable import App

@MainActor
@Suite("Watch snapshot composition")
struct WatchSnapshotComposerTests {
    @Test("Real manual session projects while automatic scheduling is unconfigured")
    func manualSessionProjection() throws {
        let fixture = try sessionFixture(onboardingComplete: false, scheduleMode: "off")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.session.countdownStarted = true

        let rules = fixture.session.watchProjection(at: fixture.date)
        #expect(rules.scheduleState == "scheduled")
        #expect(rules.shift?.isRunning == true)
    }

    @Test("Real early finish uses the persisted session snapshot and clock-off boundary")
    func frozenEarlyFinishProjection() throws {
        let fixture = try sessionFixture(onboardingComplete: true, scheduleMode: "classic")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.session.countdownStarted = true
        let shift = try #require(fixture.session.snapshot(at: fixture.date))
        fixture.session.earlyOffAtMs = fixture.date.timeIntervalSince1970 * 1_000
        fixture.session.earlyOffShiftEndAtMs = shift.endAtMs
        fixture.session.earlyOffSnapshot = shift
        _ = fixture.preferences.applyPreferences { $0.endMinutes = 18 * 60 }.synchronousResult

        let rules = fixture.session.watchProjection(at: fixture.date.addingTimeInterval(60))
        #expect(rules.shift?.plannedEndAtMs == shift.plannedEndAtMs)
        #expect(rules.shift?.finishedAtMs == fixture.session.earlyOffAtMs)
        #expect(rules.shift?.transitions.last?.state == "finished")
        #expect(rules.shift?.transitions.last?.atMs == fixture.session.earlyOffAtMs)
        #expect(rules.shift?.segments == shift.segments)
    }

    @Test("Configured empty calendar emits scheduled resting content")
    func configuredEmptyProjection() throws {
        let fixture = try sessionFixture(onboardingComplete: true, scheduleMode: "classic")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        _ = fixture.preferences.applyPreferences { $0.workdays = [] }.synchronousResult
        fixture.session.countdownStarted = true

        let rules = fixture.session.watchProjection(at: fixture.date)
        #expect(rules.scheduleState == "scheduled")
        #expect(rules.shift == nil)
        #expect(rules.nextShift == nil)
    }

    @Test("Maps TypeScript empty, stopped and rest-day projections")
    func emptyStates() throws {
        let notConfigured = try #require(compose(rules: projection(state: "notConfigured", shift: nil, next: nil)))
        #expect(notConfigured.content?.scheduleState == .notConfigured)
        #expect(notConfigured.content?.shift == nil)
        #expect(notConfigured.content?.nextShift == nil)

        let stopped = try #require(compose(rules: projection(state: "stopped")))
        #expect(stopped.content?.scheduleState == .stopped)
        #expect(stopped.content?.shift?.isRunning == false)

        let restDay = try #require(compose(rules: projection(
            shift: nil,
            next: .init(startAtMs: 4_000, validUntilMs: 4_000),
            expiresAtMs: 4_000
        )))
        #expect(restDay.content?.scheduleState == .scheduled)
        #expect(restDay.content?.shift == nil)
        #expect(restDay.content?.nextShift?.startAtMs == 4_000)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(restDay, nowMs: 4_000) == .contentExpired)
    }

    @Test("Preserves TypeScript working, lunch and overtime boundaries verbatim")
    func shiftBoundaries() throws {
        let transitions: [NativeWatchRulesProjection.Transition] = [
            .init(atMs: 200, state: "working"),
            .init(atMs: 500, state: "lunch"),
            .init(atMs: 600, state: "working"),
            .init(atMs: 800, state: "overtime"),
            .init(atMs: 900, state: "finished"),
        ]
        let package = try #require(compose(rules: projection(shift: .init(
            segments: [.init(startAtMs: 200, endAtMs: 500), .init(startAtMs: 600, endAtMs: 900)],
            plannedEndAtMs: 800,
            overtimeEndAtMs: 900,
            finishedAtMs: nil,
            isRunning: true,
            transitions: transitions
        ))))
        #expect(package.content?.shift?.transitions.map(\.state) == [
            .working, .lunch, .working, .overtime, .finished,
        ])
        #expect(WatchShiftEvaluator.evaluate(package.content!.shift!, nowMs: 550)?.phase == .resting)
        #expect(WatchShiftEvaluator.evaluate(package.content!.shift!, nowMs: 850)?.phase == .overtime)
    }

    @Test("Locked, unknown, pending and expired access never receive content")
    func accessLocking() throws {
        let locked = try #require(compose(authorization: .unauthorized))
        #expect(locked.access.status == .locked)
        #expect(locked.content == nil)

        let unknown = try #require(compose(authorization: nil))
        #expect(unknown.access.status == .unknown)
        #expect(unknown.content == nil)

        let pending = try #require(compose(authorization: .pendingAskToBuy))
        #expect(pending.access.status == .pending)
        #expect(pending.access.validUntilMs == 86_400_100)
        #expect(pending.content == nil)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(pending, nowMs: 86_400_099) == .pending)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(pending, nowMs: 86_400_100) == .confirmationRequired)

        let expired = try #require(compose(
            authorization: .authorized(.subscribed(expiresAt: date(150)))
        ))
        #expect(expired.access.status == .locked)
        #expect(expired.content == nil)
    }

    @Test("Access denial can publish when rules are unavailable")
    func accessDenialWithoutRules() throws {
        let package = try #require(WatchSnapshotComposer.compose(
            metadata: .init(sourceGeneration: "phone-install-a", revision: 9, accessRevision: 5,
                            generatedAt: date(200), accessVerifiedAt: date(100)),
            authorization: .unauthorized,
            rules: nil,
            presentation: .init(localeIdentifier: "en", timeZoneIdentifier: "UTC",
                                workingLabel: "Working", lunchLabel: "Lunch", restingLabel: "Resting",
                                overtimeLabel: "Overtime", finishedLabel: "Finished")
        ))
        #expect(package.access.status == .locked)
        #expect(package.content == nil)
        #expect(package.expiresAtMs == 201)
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(package, nowMs: 10_000) == .locked)
        #expect(WatchSnapshotComposer.compose(
            metadata: .init(sourceGeneration: "phone-install-a", revision: 9, accessRevision: 5,
                            generatedAt: date(200), accessVerifiedAt: date(100)),
            authorization: .authorized(.lifetime), rules: nil,
            presentation: .init(localeIdentifier: "en", timeZoneIdentifier: "UTC",
                                workingLabel: "Working", lunchLabel: "Lunch", restingLabel: "Resting",
                                overtimeLabel: "Overtime", finishedLabel: "Finished")
        ) == nil)
    }

    @Test("Content and entitlement expiry remain independent")
    func independentExpiry() throws {
        let contentFirst = try #require(compose(
            authorization: .authorized(.subscribed(expiresAt: date(1_500)))
        ))
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(contentFirst, nowMs: 1_000) == .contentExpired)

        let accessFirst = try #require(compose(
            authorization: .authorized(.inGracePeriod(graceExpiresAt: date(900))),
            rules: projection(expiresAtMs: 2_000)
        ))
        #expect(WatchSnapshotAvailabilityEvaluator.evaluate(accessFirst, nowMs: 900) == .accessExpired)
    }

    @Test("Encoded Watch packages contain no salary surface")
    func salaryPrivacy() throws {
        let package = try #require(compose())
        let data = try JSONEncoder().encode(package)
        let raw = String(decoding: data, as: UTF8.self)
        #expect(!raw.localizedCaseInsensitiveContains("salary"))
        #expect(!raw.contains("987654321.123456"))
        #expect(try WatchSnapshotDecoderV1.decode(data) == package)
    }

    private func compose(
        authorization: PlusAuthorization? = .authorized(.lifetime),
        rules: NativeWatchRulesProjection? = nil
    ) -> WatchSnapshotPackageV1? {
        WatchSnapshotComposer.compose(
            metadata: .init(
                sourceGeneration: "phone-install-a",
                revision: 8,
                accessRevision: 4,
                generatedAt: date(200),
                accessVerifiedAt: date(100)
            ),
            authorization: authorization,
            rules: rules ?? projection(),
            presentation: .init(
                localeIdentifier: "en", timeZoneIdentifier: "UTC",
                workingLabel: "Working", lunchLabel: "Lunch", restingLabel: "Resting",
                overtimeLabel: "Overtime", finishedLabel: "Finished"
            )
        )
    }

    private func projection(
        state: String = "scheduled",
        shift: NativeWatchRulesProjection.Shift? = .init(
            segments: [.init(startAtMs: 200, endAtMs: 500), .init(startAtMs: 600, endAtMs: 800)],
            plannedEndAtMs: 800,
            overtimeEndAtMs: nil,
            finishedAtMs: nil,
            isRunning: true,
            transitions: [
                .init(atMs: 200, state: "working"), .init(atMs: 500, state: "lunch"),
                .init(atMs: 600, state: "working"), .init(atMs: 800, state: "finished"),
            ]
        ),
        next: NativeWatchRulesProjection.NextShift? = nil,
        expiresAtMs: Double = 1_000
    ) -> NativeWatchRulesProjection {
        var shift = shift
        if state == "stopped", let current = shift {
            shift = .init(
                segments: current.segments, plannedEndAtMs: current.plannedEndAtMs,
                overtimeEndAtMs: current.overtimeEndAtMs,
                finishedAtMs: current.finishedAtMs, isRunning: false,
                transitions: current.transitions
            )
        }
        return .init(
            scheduleState: state,
            shift: shift,
            nextShift: next,
            contentExpiresAtMs: expiresAtMs
        )
    }

    private func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private func sessionFixture(
        onboardingComplete: Bool,
        scheduleMode: String
    ) throws -> (suite: String, defaults: UserDefaults, preferences: PreferencesStore, session: ShiftSession, date: Date) {
        let suite = "WatchProjection.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        defaults.set(onboardingComplete, forKey: "ios.native.onboardingComplete")
        defaults.set(scheduleMode, forKey: "ios.native.scheduleMode")
        let preferences = PreferencesStore(defaults: defaults, records: .inMemory())
        let session = ShiftSession(defaults: defaults, preferences: preferences, text: AppText(preferences: preferences))
        let date = try #require(preferences.recordsCalendar.date(from: DateComponents(
            year: 2026, month: 9, day: 7, hour: 14
        )))
        return (suite, defaults, preferences, session, date)
    }
}
