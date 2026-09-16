import Foundation
import Testing
@testable import App

/// Plan 018 P8-c1a: the extended schedule reaches the countdown, the Watch,
/// weekly summaries and Records history — switched through the same schedule
/// draft as everything else — and today keeps what an early clock-in or a
/// "from the next shift" save fixed.
///
/// Instants are built from civil dates in one pinned zone: the simulator
/// follows the Mac's zone, so a raw epoch would land on a different hour on
/// another machine.
@MainActor
@Suite("Extended schedule wiring")
struct ExtendedScheduleWiringTests {
    private static let zoneIdentifier = "Asia/Shanghai"
    private static let early = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
    private static let night = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
    private static let rest = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!

    /// Monday 2026-10-05 is early, Tuesday night, Wednesday rest.
    private static let roster = [
        "2026-10-05": early,
        "2026-10-06": night,
        "2026-10-07": rest,
        "2026-10-08": early,
    ]

    // MARK: Fixtures

    /// Classic Monday–Friday, 09:00–17:00, no lunch, in one pinned zone.
    private static func runtime() throws -> AppRuntime {
        let suite = "ExtendedScheduleWiringTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(zoneIdentifier, forKey: "ios.native.recordsTimeZone")
        let runtime = AppRuntime(defaults: defaults)
        runtime.preferences.applyPreferences {
            $0.scheduleMode = .classic
            $0.workdays = [1, 2, 3, 4, 5]
            $0.startMinutes = 9 * 60
            $0.endMinutes = 17 * 60
            $0.lunchEnabled = false
        }
        return runtime
    }

    private static func install(
        _ runtime: AppRuntime,
        enabled: Bool,
        days: [String: UUID] = roster,
        rule: ShiftCycleRule? = nil
    ) {
        runtime.records.upsertExtendedSchedule(ExtendedSchedule(
            isEnabled: enabled,
            shiftTypes: [
                ShiftType(
                    id: early, name: "Early", kind: .work,
                    startMinutes: 8 * 60, endMinutes: 16 * 60,
                    breakEnabled: true, breakStartMinutes: 12 * 60, breakDurationMinutes: 30,
                    colorHex: "#F28C28", isArchived: false
                ),
                ShiftType(
                    id: night, name: "Night", kind: .work,
                    startMinutes: 20 * 60, endMinutes: 6 * 60,
                    breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
                    colorHex: "#3A6EA5", isArchived: false
                ),
                ShiftType(
                    id: rest, name: "Rest", kind: .rest,
                    startMinutes: 0, endMinutes: 0,
                    breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
                    colorHex: "#9E9E9E", isArchived: false
                ),
            ],
            rule: rule,
            timeZoneIdentifier: zoneIdentifier,
            editedAt: .now,
            editCount: 0,
            editTieBreaker: UUID()
        ))
        for (dayKey, typeID) in days {
            setDay(runtime, dayKey, typeID)
        }
    }

    private static func setDay(_ runtime: AppRuntime, _ dayKey: String, _ typeID: UUID) {
        runtime.records.upsertRosterDay(RosterDay(
            dayKey: dayKey, shiftTypeID: typeID, timeZoneIdentifier: zoneIdentifier,
            editedAt: .now, editCount: 0, editTieBreaker: UUID()
        ))
    }

    private static func at(
        _ runtime: AppRuntime,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0
    ) throws -> Date {
        try #require(runtime.preferences.recordsCalendar.date(from: DateComponents(
            year: 2026, month: 10, day: day, hour: hour, minute: minute
        )))
    }

    private static func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1_000 }

    private static func switchExtended(
        _ runtime: AppRuntime,
        _ enabled: Bool,
        _ decision: ScheduleChangeDecision,
        at date: Date
    ) -> Bool {
        var change = ScheduleFieldChange()
        change.extendedScheduleEnabled = enabled
        return runtime.shifts.applyScheduleChange(change, decision: decision, at: date).synchronousResult == true
    }

    // MARK: Switching

    @Test("Switching it on through the schedule draft moves the countdown onto the roster")
    func switchingOnFollowsTheRoster() throws {
        let runtime = try Self.runtime()
        Self.install(runtime, enabled: false)
        let monday = try Self.at(runtime, 5, 10)
        #expect(try #require(runtime.session.snapshot(at: monday)).startAtMs == Self.ms(try Self.at(runtime, 5, 9)))

        // "Start by hand" is not a schedule; a roster is.
        runtime.preferences.applyPreferences { $0.scheduleMode = .off }
        #expect(Self.switchExtended(runtime, true, .applyToToday, at: monday))
        #expect(runtime.preferences.isExtendedScheduleEnabled)
        #expect(runtime.preferences.scheduleMode == .classic)

        let shift = try #require(runtime.session.snapshot(at: monday))
        #expect(shift.startAtMs == Self.ms(try Self.at(runtime, 5, 8)))
        #expect(shift.plannedEndAtMs == Self.ms(try Self.at(runtime, 5, 16)))
        #expect(shift.segments.count == 2)
        #expect(shift.nextShiftStartAtMs == Self.ms(try Self.at(runtime, 6, 20)))

        #expect(Self.switchExtended(runtime, false, .applyToToday, at: monday))
        #expect(try #require(runtime.session.snapshot(at: monday)).startAtMs == Self.ms(try Self.at(runtime, 5, 9)))
    }

    @Test("There is nothing to switch on before a schedule exists")
    func switchingNeedsASchedule() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        #expect(!Self.switchExtended(runtime, true, .applyToToday, at: monday))
        #expect(!runtime.preferences.isExtendedScheduleEnabled)
        #expect(try #require(runtime.session.snapshot(at: monday)).startAtMs == Self.ms(try Self.at(runtime, 5, 9)))
    }

    @Test("Switching it on from the next shift keeps today on the fixed hours")
    func nextShiftOnlyKeepsToday() throws {
        let runtime = try Self.runtime()
        Self.install(runtime, enabled: false)
        let monday = try Self.at(runtime, 5, 10)
        #expect(Self.switchExtended(runtime, true, .nextShiftOnly, at: monday))

        let today = try #require(runtime.session.snapshot(at: monday))
        #expect(today.startAtMs == Self.ms(try Self.at(runtime, 5, 9)))
        #expect(today.plannedEndAtMs == Self.ms(try Self.at(runtime, 5, 17)))
        // Tomorrow already follows the roster: a night shift, not 09:00.
        #expect(today.nextShiftStartAtMs == Self.ms(try Self.at(runtime, 6, 20)))
    }

    // MARK: Fixed clock readings

    @Test("An early clock-in keeps its start on an assigned day")
    func earlyClockInSurvivesTheRoster() throws {
        let runtime = try Self.runtime()
        Self.install(runtime, enabled: true)
        let beforeStart = try Self.at(runtime, 5, 7, 40)
        #expect(runtime.shifts.clockInEarly(at: beforeStart).synchronousResult == true)

        let later = try Self.at(runtime, 5, 7, 45)
        let shift = try #require(runtime.session.snapshot(at: later))
        #expect(shift.startAtMs == Self.ms(beforeStart))
        #expect(shift.plannedEndAtMs == Self.ms(try Self.at(runtime, 5, 16)))
        // The type's own break still splits the day.
        #expect(shift.segments.count == 2)
        // The planned start is the roster's, not the fixed 09:00 it replaces.
        #expect(runtime.session.scheduleStartMinutes(at: later) == 8 * 60)
    }

    // MARK: Other surfaces

    @Test("The Watch counts down to the roster's next shift")
    func watchReadsTheRoster() throws {
        let runtime = try Self.runtime()
        Self.install(runtime, enabled: true)
        let projection = runtime.session.watchProjection(at: try Self.at(runtime, 5, 18))
        #expect(projection.nextShift?.startAtMs == Self.ms(try Self.at(runtime, 6, 20)))
    }

    @Test("The weekly summary adds up the hours the roster assigned")
    func weeklySummaryUsesTheRoster() throws {
        let runtime = try Self.runtime()
        Self.install(runtime, enabled: true)
        let wednesday = try Self.at(runtime, 7, 12)
        let snapshot = try #require(runtime.session.snapshot(at: wednesday))
        let summary = try #require(runtime.session.periodSummary(
            "week",
            asOf: wednesday,
            snapshot: snapshot,
            periodStartMs: Self.ms(try Self.at(runtime, 5, 0))
        ))
        #expect(summary.days == 2)
        // 7.5 hours early with its break, then 10 hours overnight.
        #expect(abs(summary.hours - 17.5) < 0.000_1)
    }

    // MARK: Records

    @Test("Records history follows a roster edit without a new snapshot")
    func historyFollowsTheRoster() throws {
        let runtime = try Self.runtime()
        Self.install(runtime, enabled: true)
        let monday = try Self.at(runtime, 5, 10)
        let hours = runtime.session.hoursConfiguration(at: monday)
        #expect(hours.usesExtendedSchedule == true)
        runtime.records.ensureSeeded(hours: hours, at: monday, timeZone: runtime.preferences.recordsTimeZone)

        let snapshot = try #require(runtime.records.state.snapshots.last)
        let stored = try #require(String(data: snapshot.configurationData, encoding: .utf8))
        #expect(stored.contains("\"usesExtendedSchedule\":true"))
        #expect(!stored.contains("shiftTypes"))
        let snapshotCount = runtime.records.state.snapshots.count

        func expansion() throws -> [NativeScheduleDayExpansion] {
            let configuration = try #require(runtime.records.expandableHours(from: snapshot.configurationData))
            return ScheduleRules.expandScheduleRange(
                configuration: configuration,
                from: try Self.at(runtime, 5, 0),
                through: try Self.at(runtime, 6, 0),
                timeZone: runtime.preferences.recordsTimeZone
            )
        }
        #expect(try expansion().map(\.isWorkday) == [true, true])

        Self.setDay(runtime, "2026-10-06", Self.rest)
        #expect(try expansion().map(\.isWorkday) == [true, false])
        #expect(runtime.records.state.snapshots.count == snapshotCount)
    }

    @Test("Hours carry the plan at run time but store only the marker")
    func hoursStoreOnlyTheMarker() throws {
        let runtime = try Self.runtime()
        Self.install(runtime, enabled: true)
        let hours = runtime.session.hoursConfiguration(at: try Self.at(runtime, 5, 10))
        #expect(hours.extendedSchedule != nil)
        let encoded = try ScheduleHoursCodec.encode(hours)
        let decoded = try JSONDecoder().decode(ScheduleHoursConfiguration.self, from: encoded.data)
        #expect(decoded.usesExtendedSchedule == true)
        #expect(decoded.extendedSchedule == nil)
    }

    @Test("The plan is rebuilt only when the schedule or a day changes")
    func planIsCachedUntilItChanges() throws {
        let runtime = try Self.runtime()
        Self.install(runtime, enabled: true)
        let first = try #require(runtime.records.extendedSchedulePlan)
        #expect(runtime.records.extendedSchedulePlan?.revision == first.revision)

        Self.setDay(runtime, "2026-10-09", Self.night)
        let afterDay = try #require(runtime.records.extendedSchedulePlan)
        #expect(afterDay.revision > first.revision)
        #expect(afterDay.handSetDays["2026-10-09"] == Self.night)

        #expect(runtime.records.setExtendedScheduleEnabled(false))
        // Still there for history, with a new revision for the new schedule.
        #expect((runtime.records.extendedSchedulePlan?.revision ?? 0) > afterDay.revision)
        #expect(runtime.session.extendedSchedulePlan(at: try Self.at(runtime, 5, 10)) == nil)
    }

    /// A few years of hand-set days: the countdown asks every second, so the
    /// cost of reading the plan and resolving a shift must not grow with the
    /// archive. The ceiling only catches something pathological; the printed
    /// figure is the one to compare, measured serially.
    @Test("A large roster keeps the countdown cheap")
    func largeRosterStaysCheap() throws {
        let runtime = try Self.runtime()
        var days: [String: UUID] = [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: Self.zoneIdentifier))
        let start = try #require(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        for offset in 0..<1_000 {
            let day = try #require(calendar.date(byAdding: .day, value: offset, to: start))
            days[RecordJSON.dayKey(day, calendar: calendar)] = offset % 3 == 0 ? Self.rest : (offset % 3 == 1 ? Self.early : Self.night)
        }
        Self.install(runtime, enabled: true, days: days)
        let now = try Self.at(runtime, 5, 10)
        _ = runtime.session.snapshot(at: now)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<20 { _ = runtime.session.snapshot(at: now) }
        }
        let perCallMs = Double(elapsed.components.attoseconds) / 1e15 / 20 + Double(elapsed.components.seconds) * 1_000 / 20
        print("[perf] snapshot with 1000 roster days: \(String(format: "%.2f", perCallMs)) ms")
        #expect(perCallMs < 250)
    }
}
