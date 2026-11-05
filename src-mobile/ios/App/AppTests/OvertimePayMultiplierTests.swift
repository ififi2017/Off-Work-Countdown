import Foundation
import Testing
@testable import App

/// Plan 024 phase 3: the overtime pay multiplier's preference, per-shift
/// override, declaration payload and Records/report pricing. The pay formula
/// itself is held to the TypeScript oracle by `ScheduleRuleFixtureTests`.
@Suite("Overtime pay multiplier")
struct OvertimePayMultiplierTests {
    @Test("Only 0 and 0.5 to 5 in tenths are valid; anything else is 1")
    func normalization() {
        for value in [0, 0.5, 1, 1.5, 2.7, 5] as [Double] { #expect(OvertimePay.normalized(value) == value) }
        for value in [-1, 0.3, 0.05, 5.1, 10, 1.55, .nan, .infinity] as [Double] { #expect(OvertimePay.normalized(value) == 1) }
        #expect(OvertimePay.normalized(nil) == 1)
    }

    @Test("A declaration without payMultiplier reads as 1, and old readers ignore the new key")
    func payloadCompatibility() throws {
        let legacy = Data(#"{"overtimeEndAtMs":1000,"plannedEndAtMs":500}"#.utf8)
        let decoded = try JSONDecoder().decode(OvertimeDeclarationPayload.self, from: legacy)
        #expect(decoded.payMultiplier == nil)

        let plain = try JSONEncoder().encode(OvertimeDeclarationPayload(overtimeEndAtMs: 1000, plannedEndAtMs: 500))
        let plainObject = try #require(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        #expect(plainObject["payMultiplier"] == nil)

        let priced = try JSONEncoder().encode(OvertimeDeclarationPayload(overtimeEndAtMs: 1000, plannedEndAtMs: 500, payMultiplier: 0))
        let pricedObject = try #require(JSONSerialization.jsonObject(with: priced) as? [String: Any])
        #expect(pricedObject["payMultiplier"] as? Double == 0)
        #expect(try JSONDecoder().decode(OvertimeDeclarationPayload.self, from: priced).payMultiplier == 0)

        // What a reader that predates the key sees.
        struct Previous: Codable { var overtimeEndAtMs: Double; var plannedEndAtMs: Double? }
        let previous = try JSONDecoder().decode(Previous.self, from: priced)
        #expect(previous.overtimeEndAtMs == 1000 && previous.plannedEndAtMs == 500)
    }

    @MainActor
    @Test("The default merges, persists, omits 1 and falls back to 1 when absent")
    func preferenceRoundTrip() throws {
        let suite = "OvertimePay.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let records = RecordCoordinator.inMemory()
        let store = AppRuntime(defaults: defaults, records: records)
        #expect(store.preferences.overtimePayMultiplier == 1)
        #expect(store.session.effectiveOvertimePayMultiplier == 1)

        store.preferences.applyPreferences { $0.overtimePayMultiplier = 1.5 }
        #expect(defaults.double(forKey: "ios.native.overtimePayMultiplier") == 1.5)
        #expect(records.state.syncedPreferences?.overtimePayMultiplier == 1.5)
        #expect(store.session.rulesInput(at: .now).overtimePayMultiplier == 1.5)
        #expect(AppRuntime(defaults: defaults, records: RecordCoordinator.inMemory()).preferences.overtimePayMultiplier == 1.5)

        let synced = try #require(records.state.syncedPreferences)
        let data = try JSONEncoder().encode(synced)
        #expect((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["overtimePayMultiplier"] as? Double == 1.5)
        var reset = synced
        reset.overtimePayMultiplier = 1
        let resetData = try JSONEncoder().encode(reset)
        var object = try #require(JSONSerialization.jsonObject(with: resetData) as? [String: Any])
        #expect(object["overtimePayMultiplier"] == nil)
        #expect(try JSONDecoder().decode(SyncedPreferences.self, from: resetData).overtimePayMultiplier == 1)
        object["overtimePayMultiplier"] = 7.3
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(SyncedPreferences.self, from: invalid).overtimePayMultiplier == 1)

        var local = synced
        local.overtimePayMultiplier = 2
        local.editCount = 3
        var server = synced
        server.editCount = 3
        server.monthlyWorkingDays = 20
        let merged = RecordsSyncConflict.mergeSyncedPreferences(local: local, server: server, baseline: synced)
        #expect(merged.overtimePayMultiplier == 2)
        #expect(merged.monthlyWorkingDays == 20)
    }

    @MainActor
    @Test("A declaration pins the shift's multiplier, Records price the day by it, and clearing drops it")
    func declarationAndOverride() throws {
        let suite = "OvertimePay.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = RecordCoordinator.inMemory()
        let store = AppRuntime(defaults: defaults, records: records)
        store.preferences.onboardingComplete = true
        store.preferences.applyPreferences { $0.scheduleMode = .classic }
        store.preferences.applyPreferences { $0.workdays = [1, 2, 3, 4, 5] }
        store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
        store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
        store.preferences.applyPreferences { $0.lunchEnabled = false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.preferences.recordsTimeZone
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 18)))
        let day = calendar.startOfDay(for: now)
        records.ensureSeeded(hours: store.session.hoursConfiguration(at: now), at: now, timeZone: store.preferences.recordsTimeZone)
        _ = store.shifts.reconcileRecordSchedule(at: now).synchronousResult
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 19)))
        let resolution = try #require(store.queries.resolvedDays(from: day, through: day, now: now).first)

        // Nothing declared yet: a plain day is priced at the usual rate.
        #expect(store.queries.overtimePayMultiplier(on: resolution) == 1)

        // The default applies when the sheet names none, and is pinned to the shift.
        store.preferences.applyPreferences { $0.overtimePayMultiplier = 2 }
        #expect(store.shifts.applyOvertime(date: end, declaredAt: now).synchronousResult)
        #expect(store.session.overtimePayMultiplier == 2)
        #expect(store.queries.overtimePayMultiplier(on: resolution) == 2)
        store.preferences.applyPreferences { $0.overtimePayMultiplier = 3 }
        #expect(store.session.effectiveOvertimePayMultiplier == 2)

        // A newer declaration for the same end replaces it; 0 is unpaid.
        let later = now.addingTimeInterval(60)
        #expect(store.shifts.applyOvertime(date: end, declaredAt: later, payMultiplier: 0).synchronousResult)
        #expect(store.session.overtimePayMultiplier == 0)
        #expect(store.session.rulesInput(at: now).overtimePayMultiplier == 0)
        #expect(store.queries.overtimePayMultiplier(on: resolution) == 0)

        // An invalid choice falls back to the usual rate.
        let invalid = later.addingTimeInterval(60)
        #expect(store.shifts.applyOvertime(date: end, declaredAt: invalid, payMultiplier: 9).synchronousResult)
        #expect(store.session.overtimePayMultiplier == 1)

        store.shifts.clearOvertime()
        #expect(store.session.overtimeEndAtMs == nil)
        #expect(store.session.overtimePayMultiplier == nil)
        #expect(defaults.object(forKey: "ios.native.sessionOvertimePayMultiplier") == nil)
    }

    @Test("Cycle reports price overtime extra by the declared multipliers")
    func reportOvertimeExtra() {
        let hour: Int64 = 3_600_000
        var figures = CycleReportFigures(workdays: 5, workedMs: 44 * hour, overtimeMs: 4 * hour, income: 4_800)
        // Unchanged where nothing was re-priced.
        #expect(CycleReportPay.make(figures: figures, overtimeIsPaid: true)?.overtimeExtra == 4_800.0 * 4 / 44)
        // 4 hours at 1.5x make 6 paid hours of a 46 hour pay-weighted period.
        figures.paidOvertimeMs = 6 * hour
        let extra = CycleReportPay.make(figures: figures, overtimeIsPaid: true)?.overtimeExtra
        #expect(extra != nil && abs(extra! - 4_800.0 * 6 / 46) < 1e-9)
        // Unpaid overtime adds nothing.
        figures.paidOvertimeMs = 0
        #expect(CycleReportPay.make(figures: figures, overtimeIsPaid: true)?.overtimeExtra == nil)
        #expect(CycleReportPay.make(figures: figures, overtimeIsPaid: true)?.perHour != nil)
    }

    @Test("Records weigh a day's overtime by its multiplier")
    func recordsPricing() {
        let hour = 3_600_000.0
        func summary(_ multiplier: Double?) -> Double? {
            SummaryRules.recordsActualForecast(input: .init(
                days: [NativeRecordsActualForecastDay(
                    actualKind: "scheduled",
                    resolvedSegments: [NativeShiftSegment(startAtMs: 9 * hour, endAtMs: 17 * hour)],
                    plannedSegments: [NativeShiftSegment(startAtMs: 9 * hour, endAtMs: 17 * hour)],
                    overtimeSegments: [NativeShiftSegment(startAtMs: 17 * hour, endAtMs: 19 * hour)],
                    overtimePayMultiplier: multiplier,
                    observations: [],
                    isActiveAnchor: false
                )],
                periodDayKeys: ["2026-11-04"],
                dailySalary: 800,
                asOfMs: 24 * hour
            )).actual.earnings
        }
        #expect(summary(nil) == 1_000)
        #expect(summary(1) == 1_000)
        #expect(summary(0) == 800)
        #expect(summary(1.5) == 1_100)
        #expect(summary(2) == 1_200)
        #expect(summary(0.3) == 1_000)
    }
}
