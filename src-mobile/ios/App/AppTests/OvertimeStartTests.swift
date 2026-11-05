import Foundation
import Testing
@testable import App

/// Plan 024 phase 4: overtime that starts after a rest, and counted hours. The
/// shared rules are held to the TypeScript oracle by `ScheduleRuleFixtureTests`;
/// these cover the session, the declaration payload, Records and the sheet.
@Suite("Overtime start and counted hours")
struct OvertimeStartTests {
    @Test("A payload without the new keys decodes as before, and older readers ignore them")
    func payloadCompatibility() throws {
        let legacy = Data(#"{"overtimeEndAtMs":1000,"plannedEndAtMs":500,"payMultiplier":2}"#.utf8)
        let decoded = try JSONDecoder().decode(OvertimeDeclarationPayload.self, from: legacy)
        #expect(decoded.overtimeStartAtMs == nil && decoded.countedMs == nil && decoded.payMultiplier == 2)

        let plain = try JSONEncoder().encode(OvertimeDeclarationPayload(overtimeEndAtMs: 1000, plannedEndAtMs: 500))
        let plainObject = try #require(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        #expect(plainObject["overtimeStartAtMs"] == nil && plainObject["countedMs"] == nil)

        let full = try JSONEncoder().encode(OvertimeDeclarationPayload(
            overtimeEndAtMs: 1000, plannedEndAtMs: 500, payMultiplier: 1.5, overtimeStartAtMs: 700, countedMs: 120_000
        ))
        let object = try #require(JSONSerialization.jsonObject(with: full) as? [String: Any])
        #expect(object["overtimeStartAtMs"] as? Double == 700 && object["countedMs"] as? Double == 120_000)

        // What a reader that predates the keys sees.
        struct Previous: Codable { var overtimeEndAtMs: Double; var plannedEndAtMs: Double?; var payMultiplier: Double? }
        let previous = try JSONDecoder().decode(Previous.self, from: full)
        #expect(previous.overtimeEndAtMs == 1000 && previous.plannedEndAtMs == 500 && previous.payMultiplier == 1.5)
    }

    @Test("Counted hours are 0 to 24 hours, anything else counts the period")
    func countedValidation() {
        let hour = 3_600_000.0
        for value in [0, 1, 1.5 * hour, 24 * hour] as [Double] { #expect(CountedOvertime.normalized(value) == value) }
        for value in [-1, 24 * hour + 1, .nan, .infinity] as [Double] { #expect(CountedOvertime.normalized(value) == nil) }
        #expect(CountedOvertime.normalized(nil) == nil)
        #expect(CountedOvertime.scale(fullMeasuredMs: 3 * hour, countedMs: 1.5 * hour) == 0.5)
        #expect(CountedOvertime.scale(fullMeasuredMs: 0, countedMs: hour) == 1)
        #expect(CountedOvertime.scale(fullMeasuredMs: 3 * hour, countedMs: nil) == 1)
    }

    @Test("A planned end inside the second-to-last segment is a valid timeline")
    func appendedSegmentIsValid() {
        let hour = 3_600_000.0
        let timeline = ShiftTimeline(
            segments: [
                NativeShiftSegment(startAtMs: 9 * hour, endAtMs: 17 * hour),
                NativeShiftSegment(startAtMs: 18 * hour, endAtMs: 20 * hour),
            ],
            plannedEndAtMs: 17 * hour,
            overtimeEndAtMs: 20 * hour
        )
        #expect(timeline.isValid)
        #expect(timeline.durationMs == 10 * hour)
        #expect(timeline.plannedDurationMs == 8 * hour)
        #expect(timeline.overtimeElapsedMs(at: 19 * hour) == 1 * hour)
        #expect(timeline.activeBreakEndAtMs(at: 17.5 * hour) == 18 * hour)
        // No overtime end: the extra segment is not a valid shape.
        var plain = timeline
        plain.overtimeEndAtMs = nil
        #expect(!plain.isValid)
        // The segment must start after the planned end.
        var overlapping = timeline
        overlapping.plannedEndAtMs = 16 * hour
        #expect(!overlapping.isValid)
    }

    @Test("The sheet starts overtime after the rest and counts from there")
    func sheetPlan() throws {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        var plan = OvertimeSheetPlan(plannedEnd: planned, now: planned.addingTimeInterval(-3_600), untilDate: planned.addingTimeInterval(3_600))
        #expect(plan.overtimeStart == nil)
        #expect(plan.startDate == planned)
        #expect(plan.countedMs == 3_600_000)
        #expect(plan.isValid)

        plan.restMinutes = 30
        #expect(plan.overtimeStart == planned.addingTimeInterval(1_800))
        #expect(plan.countedMs == 1_800_000)

        // Switching to a duration keeps the end; the end follows the rest.
        plan.select(.duration)
        #expect(plan.durationMinutes == 30)
        #expect(plan.endDate == planned.addingTimeInterval(3_600))
        plan.durationMinutes = 150
        plan.restMinutes = 60
        #expect(plan.endDate == planned.addingTimeInterval(3_600 + 9_000))
        #expect(plan.countedMs == 9_000_000)

        // Back to a clock time keeps the end it showed.
        plan.select(.until)
        #expect(plan.untilDate == planned.addingTimeInterval(12_600))

        // A rest that swallows the whole overtime is not savable.
        var short = OvertimeSheetPlan(plannedEnd: planned, now: planned.addingTimeInterval(-60), untilDate: planned.addingTimeInterval(600))
        short.restMinutes = 15
        #expect(!short.isValid)
        short.settle()
        #expect(short.isValid)
    }

    @Test("Durations offered still end now or later")
    func durationChoices() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let retrospective = OvertimeSheetPlan(plannedEnd: planned, now: planned.addingTimeInterval(50 * 60), untilDate: planned)
        #expect(retrospective.durationChoices.first == 60)
        #expect(retrospective.durationChoices.last == 720)
        let early = OvertimeSheetPlan(plannedEnd: planned, now: planned.addingTimeInterval(-600), untilDate: planned)
        #expect(early.durationChoices.first == 15)
        #expect(OvertimeRestChoices.nearest(to: 28) == 30)
        #expect(OvertimeRestChoices.nearest(to: 0) == 0)
    }

    @MainActor
    @Test("Applying overtime after a rest stores the start, writes it, and clearing drops it")
    func startThroughTheSession() throws {
        let suite = "OvertimeStart.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = RecordCoordinator.inMemory()
        let store = AppRuntime(defaults: defaults, records: records)
        store.plus.debugSetAuthorized(true)
        store.preferences.onboardingComplete = true
        store.preferences.applyPreferences { $0.scheduleMode = .classic }
        store.preferences.applyPreferences { $0.workdays = [1, 2, 3, 4, 5] }
        store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
        store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
        store.preferences.applyPreferences { $0.lunchEnabled = false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.preferences.recordsTimeZone
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 16)))
        let day = calendar.startOfDay(for: now)
        records.ensureSeeded(hours: store.session.hoursConfiguration(at: now), at: now, timeZone: store.preferences.recordsTimeZone)
        _ = store.shifts.reconcileRecordSchedule(at: now).synchronousResult
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 17, minute: 30)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 20)))
        let planned = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 17)))

        #expect(store.shifts.applyOvertime(date: end, declaredAt: now, startDate: start).synchronousResult)
        #expect(store.session.overtimeStartAtMs == start.timeIntervalSince1970 * 1_000)
        let snapshot = try #require(store.session.snapshot(at: now))
        #expect(snapshot.segments.count == 2)
        #expect(snapshot.plannedEndAtMs == planned.timeIntervalSince1970 * 1_000)
        #expect(snapshot.segments[1] == NativeShiftSegment(startAtMs: start.timeIntervalSince1970 * 1_000, endAtMs: end.timeIntervalSince1970 * 1_000))
        // The rest is a break: the countdown pauses, then runs to the end.
        #expect(store.session.snapshot(at: planned.addingTimeInterval(600))?.activeBreakEndAtMs == start.timeIntervalSince1970 * 1_000)

        // The declaration carries the start; Records draw the same segment.
        let resolution = try #require(store.queries.resolvedDays(from: day, through: day, now: now).first)
        let segment = try #require(store.queries.overtimeSegments(on: resolution).first)
        #expect(segment.startAtMs == start.timeIntervalSince1970 * 1_000 && segment.endAtMs == end.timeIntervalSince1970 * 1_000)
        #expect(store.queries.overtimeCountedMs(on: resolution) == nil)
        #expect(store.queries.overtimeCountScale(on: resolution) == 1)

        // A start at or before the planned end is no rest at all.
        let later = now.addingTimeInterval(60)
        #expect(store.shifts.applyOvertime(date: end, declaredAt: later, startDate: planned).synchronousResult)
        #expect(store.session.overtimeStartAtMs == nil)
        #expect(store.session.snapshot(at: now)?.segments.count == 1)

        #expect(store.shifts.applyOvertime(date: end, declaredAt: later.addingTimeInterval(60), startDate: start).synchronousResult)
        store.shifts.clearOvertime()
        #expect(store.session.overtimeStartAtMs == nil)
        #expect(defaults.object(forKey: "ios.native.overtimeStartAtMs") == nil)
    }

    @MainActor
    @Test("A Records declaration replaces the day's period, counted hours and pay, and statistics follow it")
    func recordsDeclaration() async throws {
        let suite = "OvertimeStart.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = RecordCoordinator.inMemory()
        let store = AppRuntime(defaults: defaults, records: records)
        store.plus.debugSetAuthorized(true)
        store.preferences.onboardingComplete = true
        store.preferences.applyPreferences { $0.scheduleMode = .classic }
        store.preferences.applyPreferences { $0.workdays = [1, 2, 3, 4, 5] }
        store.preferences.applyPreferences { $0.startMinutes = 9 * 60 }
        store.preferences.applyPreferences { $0.endMinutes = 17 * 60 }
        store.preferences.applyPreferences { $0.lunchEnabled = false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.preferences.recordsTimeZone
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 23)))
        let day = calendar.startOfDay(for: now)
        let dayKey = RecordJSON.dayKey(day, calendar: calendar)
        records.ensureSeeded(hours: store.session.hoursConfiguration(at: now), at: now, timeZone: store.preferences.recordsTimeZone)
        _ = store.shifts.reconcileRecordSchedule(at: now).synchronousResult

        var state = RecordOvertimeState.load(dayKey: dayKey, queries: store.queries)
        #expect(!state.hasDeclaration)
        let planned = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 17)))
        #expect(state.startAtMs == planned.timeIntervalSince1970 * 1_000)

        // 18:00 to 21:00 is three hours; the person counts two and a half.
        state.setStart(timeOf: try #require(calendar.date(from: DateComponents(hour: 18))), calendar: calendar)
        state.setEnd(timeOf: try #require(calendar.date(from: DateComponents(hour: 21))), calendar: calendar)
        #expect(state.measuredMs == 3 * 3_600_000)
        state.countedMs = 2.5 * 3_600_000
        state.payMultiplier = 1.5
        let command = store.recordActions.declareOvertime(dayKey: dayKey, state: state, declaredAt: now)
        #expect(await command.value)

        let reloaded = RecordOvertimeState.load(dayKey: dayKey, queries: store.queries)
        #expect(reloaded.hasDeclaration)
        #expect(reloaded.startAtMs == state.startAtMs && reloaded.endAtMs == state.endAtMs)
        #expect(reloaded.countedMs == 2.5 * 3_600_000 && reloaded.payMultiplier == 1.5)

        let resolution = try #require(store.queries.resolvedDay(dayKey: dayKey))
        #expect(store.queries.overtimeCountScale(on: resolution) == 2.5 / 3)
        let cell = store.queries.recordsDayCell(for: resolution, now: now.addingTimeInterval(3_600), revealingAll: true)
        #expect(cell.overtimeMs == Int64(2.5 * 3_600_000))

        // The next declaration for the day wins; the canvas still draws its period.
        var again = reloaded
        again.countedMs = nil
        again.setEnd(timeOf: try #require(calendar.date(from: DateComponents(hour: 20))), calendar: calendar)
        let second = store.recordActions.declareOvertime(dayKey: dayKey, state: again, declaredAt: now.addingTimeInterval(60))
        #expect(await second.value)
        let last = RecordOvertimeState.load(dayKey: dayKey, queries: store.queries)
        #expect(last.countedMs == nil && last.measuredMs == 2 * 3_600_000)
        let segment = try #require(store.queries.overtimeSegments(on: resolution).first)
        #expect(segment.endAtMs - segment.startAtMs == 2 * 3_600_000)
        #expect(records.state.observations.filter { $0.kind == .overtimeDeclared }.count == 2)
    }

    @Test("Counted hours replace the measured overtime in the Records summary")
    func recordsSummary() {
        let hour = 3_600_000.0
        func summary(counted: Double?, multiplier: Double? = nil) -> NativeRecordsActualForecastSummary {
            SummaryRules.recordsActualForecast(input: .init(
                days: [NativeRecordsActualForecastDay(
                    actualKind: "scheduled",
                    resolvedSegments: [NativeShiftSegment(startAtMs: 9 * hour, endAtMs: 17 * hour)],
                    plannedSegments: [NativeShiftSegment(startAtMs: 9 * hour, endAtMs: 17 * hour)],
                    overtimeSegments: [NativeShiftSegment(startAtMs: 18 * hour, endAtMs: 21 * hour)],
                    overtimePayMultiplier: multiplier,
                    overtimeCountedMs: counted,
                    observations: [],
                    isActiveAnchor: false
                )],
                periodDayKeys: ["2026-11-04"],
                dailySalary: 800,
                asOfMs: 24 * hour
            ))
        }
        #expect(summary(counted: nil).actualOvertimeHours == 3)
        #expect(summary(counted: 2.5 * hour).actualOvertimeHours == 2.5)
        #expect(summary(counted: 2.5 * hour).actual.hours == 10.5)
        #expect(summary(counted: 2.5 * hour).actual.earnings == 800 * 10.5 / 8)
        // The scale is counted / measured, so pay agrees to rounding.
        #expect(abs((summary(counted: 2.5 * hour, multiplier: 2).actual.earnings ?? 0) - 1_300) < 1e-6)
        #expect(summary(counted: 0).actual.earnings == 800)
        #expect(summary(counted: -1).actualOvertimeHours == 3)
        #expect(summary(counted: 25 * hour).actualOvertimeHours == 3)
    }

    @Test("Counted hours step in quarter hours and the period keeps its end after midnight")
    func recordsEditing() throws {
        var state = RecordOvertimeState(
            hasDeclaration: false, startAtMs: 1_000_000, endAtMs: 1_000_000 + 3_600_000, countedMs: nil,
            payMultiplier: 1, regularEndAtMs: nil, plannedEndAtMs: nil
        )
        #expect(state.steppedCountedMs(by: 1) == 4_500_000)
        #expect(state.steppedCountedMs(by: -1) == 2_700_000)
        state.countedMs = 0
        #expect(state.steppedCountedMs(by: -1) == 0)
        state.countedMs = CountedOvertime.maximumMs
        #expect(state.steppedCountedMs(by: 1) == CountedOvertime.maximumMs)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 22)))
        var late = RecordOvertimeState(
            hasDeclaration: false, startAtMs: evening.timeIntervalSince1970 * 1_000, endAtMs: evening.timeIntervalSince1970 * 1_000 + 3_600_000,
            countedMs: nil, payMultiplier: 1, regularEndAtMs: nil, plannedEndAtMs: nil
        )
        late.setEnd(timeOf: try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 1))), calendar: calendar)
        #expect(late.measuredMs == 3 * 3_600_000)
        late.setEnd(timeOf: try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))), calendar: calendar)
        #expect(late.measuredMs == 3_600_000)
    }
}
