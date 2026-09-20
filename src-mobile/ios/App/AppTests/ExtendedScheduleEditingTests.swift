import Foundation
import Testing
@testable import App

/// Plan 018 P8-c1b: what the schedule page does with an extended schedule —
/// seeding one from the current schedule, saving shift types, a pattern and
/// calendar days with the rest of the page, and keeping today and earlier days
/// on what they were worked under.
///
/// Instants are built from civil dates in one pinned zone, as in
/// `ExtendedScheduleWiringTests`.
@MainActor
@Suite("Extended schedule editing")
struct ExtendedScheduleEditingTests {
    private static let zoneIdentifier = "Asia/Shanghai"
    private static let early = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
    private static let night = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
    private static let rest = UUID(uuidString: "00000000-0000-0000-0000-0000000000D3")!

    // MARK: Fixtures

    /// Classic Monday–Friday, 09:00–17:00 with a 12:00 hour-long lunch.
    private static func runtime() throws -> AppRuntime {
        let suite = "ExtendedScheduleEditingTests.\(UUID().uuidString)"
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
            $0.lunchEnabled = true
            $0.lunchStartMinutes = 12 * 60
            $0.lunchDurationMinutes = 60
        }
        return runtime
    }

    private static var earlyType: ShiftType {
        ShiftType(
            id: early, name: "Early", kind: .work,
            startMinutes: 8 * 60, endMinutes: 16 * 60,
            breakEnabled: false, breakStartMinutes: 12 * 60, breakDurationMinutes: 30,
            colorHex: "#FF9500", isArchived: false
        )
    }

    private static var nightType: ShiftType {
        ShiftType(
            id: night, name: "Night", kind: .work,
            startMinutes: 20 * 60, endMinutes: 6 * 60,
            breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
            colorHex: "#007AFF", isArchived: false
        )
    }

    private static var restType: ShiftType {
        ShiftType(
            id: rest, name: "Rest", kind: .rest,
            startMinutes: 9 * 60, endMinutes: 17 * 60,
            breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
            colorHex: ExtendedScheduleEditing.restColor, isArchived: false
        )
    }

    /// Every day early, from Monday 2026-10-05.
    private static var everyDayEarly: ExtendedScheduleContent {
        ExtendedScheduleContent(
            shiftTypes: [earlyType, nightType, restType],
            rule: ShiftCycleRule(preset: .rotation, anchorDayKey: "2026-10-05", days: [early])
        )
    }

    private static func at(_ runtime: AppRuntime, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try on(runtime, month: 10, day, hour, minute)
    }

    private static func on(_ runtime: AppRuntime, month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try #require(runtime.preferences.recordsCalendar.date(from: DateComponents(
            year: 2026, month: month, day: day, hour: hour, minute: minute
        )))
    }

    private static func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1_000 }

    private static func save(
        _ runtime: AppRuntime,
        _ decision: ScheduleChangeDecision,
        at date: Date,
        _ edit: (inout ScheduleFieldChange) -> Void
    ) -> Bool {
        var change = ScheduleFieldChange()
        edit(&change)
        return runtime.shifts.applyScheduleChange(change, decision: decision, at: date).synchronousResult == true
    }

    /// Whether each day from `day` on is a workday under the stored snapshot
    /// in force on it, and when it starts.
    private static func recorded(
        _ runtime: AppRuntime,
        month: Int = 10,
        day: Int
    ) throws -> NativeScheduleDayExpansion {
        let date = try on(runtime, month: month, day, 12)
        let snapshot = try #require(runtime.records.state.snapshots
            .filter { $0.effectiveFrom <= date }
            .max { $0.effectiveFrom < $1.effectiveFrom })
        let hours = try #require(runtime.records.expandableHours(for: snapshot))
        return try #require(ScheduleRules.expandScheduleRange(
            configuration: hours,
            from: date,
            through: date,
            timeZone: runtime.preferences.recordsTimeZone
        ).first)
    }

    // MARK: Seeding

    @Test("A seeded schedule works the same days as the schedule it replaces", arguments: [
        WorkScheduleMode.classic, .alternating, .rotation,
    ])
    func seedingKeepsTheWorkdays(mode: WorkScheduleMode) throws {
        let runtime = try Self.runtime()
        runtime.preferences.applyPreferences {
            $0.scheduleMode = mode
            $0.workdays = [1, 2, 4, 6]
            $0.alternatingWeekType = .double
            $0.alternatingWeekendWorkday = 0
            $0.rotationWorkDays = 3
            $0.rotationRestDays = 2
        }
        let wednesday = try Self.at(runtime, 7, 10)
        if mode == .rotation {
            // Today is day 2 of the rotation, so the copy has to keep the phase.
            _ = Self.save(runtime, .applyToToday, at: wednesday) { $0.rotationCycleDay = 2 }
            #expect(runtime.preferences.rotationCycleDay(at: wednesday) == 2)
        }
        let content = runtime.session.seededExtendedContent(applying: ScheduleFieldChange(), at: wednesday)
        let expected: ShiftCycleRule.Preset = switch mode {
        case .alternating: .alternatingWeeks
        case .rotation: .rotation
        default: .weekly
        }
        #expect(content.rule?.preset == expected)
        #expect(content.shiftTypes.count == 2)
        let work = try #require(content.shiftTypes.first)
        #expect(work.kind == .work && work.startMinutes == 9 * 60 && work.endMinutes == 17 * 60)
        #expect(work.breakEnabled && work.breakStartMinutes == 12 * 60 && work.breakDurationMinutes == 60)
        #expect(content.isValid(in: runtime.preferences.recordsTimeZone))

        let from = try Self.at(runtime, 1, 0)
        let through = try Self.at(runtime, 31, 0)
        let fixed = runtime.session.hoursConfiguration(at: wednesday)
        var extended = fixed
        extended.extendedContent = content
        extended.extendedSchedule = runtime.preferences.extendedSchedulePlan(for: content)
        let zone = runtime.preferences.recordsTimeZone
        let before = ScheduleRules.expandScheduleRange(configuration: fixed, from: from, through: through, timeZone: zone)
        let after = ScheduleRules.expandScheduleRange(configuration: extended, from: from, through: through, timeZone: zone)
        #expect(before.map(\.isWorkday) == after.map(\.isWorkday))
        #expect(before.contains(where: \.isWorkday) && before.contains(where: { !$0.isWorkday }))
        #expect(after.map(\.segments) == before.map(\.segments))
    }

    @Test("Choosing the extended schedule creates it and switches it on in one save")
    func firstSaveCreatesTheSchedule() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        #expect(runtime.preferences.extendedScheduleContent == nil)
        #expect(Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
        })
        #expect(runtime.preferences.isExtendedScheduleEnabled)
        #expect(runtime.preferences.extendedScheduleContent == Self.everyDayEarly)
        #expect(runtime.records.state.extendedSchedule?.timeZoneIdentifier == Self.zoneIdentifier)
        let shift = try #require(runtime.session.snapshot(at: monday))
        #expect(shift.startAtMs == Self.ms(try Self.at(runtime, 5, 8)))

        // An invalid rule is refused, and nothing else changes with it.
        var broken = Self.everyDayEarly
        broken.rule?.days = [UUID()]
        #expect(!Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedContent = broken
            $0.startMinutes = 7 * 60
        })
        #expect(runtime.preferences.extendedScheduleContent == Self.everyDayEarly)
        #expect(runtime.preferences.startMinutes == 9 * 60)
    }

    @Test("A draft matching the stored schedule is not a change")
    func settledDraftIsEmpty() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        #expect(Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
        })
        var draft = ScheduleFieldChange()
        draft.extendedContent = Self.everyDayEarly
        draft.extendedScheduleEnabled = true
        #expect(draft.settled(against: runtime.preferences).isEmpty)
    }

    // MARK: Today and history

    @Test("New shift hours saved from the next shift leave today's shift alone")
    func nextShiftOnlyKeepsTodaysShift() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        #expect(Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
        })

        var earlier = Self.everyDayEarly
        earlier.shiftTypes[0].startMinutes = 7 * 60
        earlier.shiftTypes[0].endMinutes = 15 * 60
        var draft = ScheduleFieldChange()
        draft.extendedContent = earlier
        #expect(runtime.session.shouldPromptApplyingToToday(draft, scope: .schedule, at: monday))
        #expect(runtime.shifts.applyScheduleChange(draft, decision: .nextShiftOnly, at: monday).synchronousResult == true)

        let today = try #require(runtime.session.snapshot(at: monday))
        #expect(today.startAtMs == Self.ms(try Self.at(runtime, 5, 8)))
        #expect(today.plannedEndAtMs == Self.ms(try Self.at(runtime, 5, 16)))
        #expect(today.nextShiftStartAtMs == Self.ms(try Self.at(runtime, 6, 7)))

        // Tomorrow the kept schedule has expired.
        let tuesday = try #require(runtime.session.snapshot(at: try Self.at(runtime, 6, 10)))
        #expect(tuesday.startAtMs == Self.ms(try Self.at(runtime, 6, 7)))
    }

    @Test("A new rule leaves earlier days on the rule they were worked under")
    func ruleChangeKeepsHistory() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        #expect(Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
        })
        // The save seeded Records with the schedule it switched on.
        #expect(try Self.recorded(runtime, day: 5).shiftAnchorStartAtMs == Self.ms(try Self.at(runtime, 5, 8)))

        var nights = Self.everyDayEarly
        nights.rule?.days = [Self.night]
        let wednesday = try Self.at(runtime, 7, 12)
        #expect(Self.save(runtime, .applyToToday, at: wednesday) { $0.extendedContent = nights })

        #expect(try Self.recorded(runtime, day: 5).shiftAnchorStartAtMs == Self.ms(try Self.at(runtime, 5, 8)))
        #expect(try Self.recorded(runtime, day: 6).shiftAnchorStartAtMs == Self.ms(try Self.at(runtime, 6, 8)))
        #expect(try Self.recorded(runtime, day: 7).shiftAnchorStartAtMs == Self.ms(try Self.at(runtime, 7, 20)))
    }

    @Test("A day filled in with a newer type resolves under an older snapshot")
    func newerTypesResolveInHistory() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        let older = ExtendedScheduleContent(
            shiftTypes: [Self.earlyType, Self.restType],
            rule: ShiftCycleRule(preset: .rotation, anchorDayKey: "2026-10-05", days: [Self.early])
        )
        #expect(Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = older
        })

        let wednesday = try Self.at(runtime, 7, 12)
        #expect(Self.save(runtime, .applyToToday, at: wednesday) {
            $0.extendedContent = ExtendedScheduleEditing.upserting(Self.nightType, in: older)
        })
        runtime.records.upsertRosterDay(RosterDay(
            dayKey: "2026-10-06", shiftTypeID: Self.night, timeZoneIdentifier: Self.zoneIdentifier,
            editedAt: .now, editCount: 0, editTieBreaker: UUID()
        ))
        let tuesday = try Self.recorded(runtime, day: 6)
        #expect(tuesday.isWorkday)
        #expect(tuesday.shiftAnchorStartAtMs == Self.ms(try Self.at(runtime, 6, 20)))
    }

    @Test("A snapshot's plan is built once until a day or a type changes")
    func contentPlansAreCached() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        #expect(Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
        })
        let live = try #require(runtime.records.extendedSchedulePlan)
        #expect(runtime.records.extendedSchedulePlan(for: Self.everyDayEarly).revision == live.revision)

        var other = Self.everyDayEarly
        other.rule?.days = [Self.night]
        let first = runtime.records.extendedSchedulePlan(for: other)
        #expect(runtime.records.extendedSchedulePlan(for: other).revision == first.revision)
        runtime.records.upsertRosterDay(RosterDay(
            dayKey: "2026-10-09", shiftTypeID: Self.rest, timeZoneIdentifier: Self.zoneIdentifier,
            editedAt: .now, editCount: 0, editTieBreaker: UUID()
        ))
        let rebuilt = runtime.records.extendedSchedulePlan(for: other)
        #expect(rebuilt.revision > first.revision)
        #expect(rebuilt.handSetDays["2026-10-09"] == Self.rest)
    }

    // MARK: Calendar

    private static func handSet(_ runtime: AppRuntime, _ day: Int) -> UUID? {
        runtime.preferences.handSetDays[String(format: "2026-10-%02d", day)]
    }

    @Test("Days set on the calendar are saved with the page, and a restated day is no change")
    func calendarEditsSave() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        #expect(Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
            $0.rosterEdits = ["2026-10-08": .shift(Self.night), "2026-10-09": .shift(Self.rest)]
        })
        #expect(Self.handSet(runtime, 8) == Self.night)
        #expect(Self.handSet(runtime, 9) == Self.rest)
        let thursday = try #require(runtime.session.snapshot(at: try Self.at(runtime, 8, 21)))
        #expect(thursday.startAtMs == Self.ms(try Self.at(runtime, 8, 20)))

        var draft = ScheduleFieldChange()
        draft.rosterEdits = ["2026-10-08": .shift(Self.night), "2026-10-12": .followPattern]
        #expect(draft.settled(against: runtime.preferences).isEmpty)
        #expect(ExtendedScheduleEditing.editing(nil, dayKey: "2026-10-08", to: .shift(Self.night), stored: runtime.preferences.handSetDays) == nil)

        // Putting a day back on the pattern erases it.
        #expect(Self.save(runtime, .applyToToday, at: monday) { $0.rosterEdits = ["2026-10-09": .followPattern] })
        #expect(Self.handSet(runtime, 9) == nil)
        #expect(runtime.records.state.isErased(.rosterDay, key: "2026-10-09"))
    }

    @Test("A day naming a shift the schedule does not have is refused")
    func calendarEditNeedsAKnownType() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        #expect(!Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
            $0.rosterEdits = ["2026-10-08": .shift(UUID())]
            $0.startMinutes = 7 * 60
        })
        #expect(runtime.preferences.extendedScheduleContent == nil)
        #expect(runtime.preferences.startMinutes == 9 * 60)
    }

    @Test("Changing today's day from the next shift leaves the shift in progress alone")
    func nextShiftOnlyKeepsTodaysDay() throws {
        let runtime = try Self.runtime()
        let monday = try Self.at(runtime, 5, 10)
        #expect(Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
        })
        var draft = ScheduleFieldChange()
        draft.rosterEdits = ["2026-10-05": .shift(Self.night)]
        #expect(runtime.session.shouldPromptApplyingToToday(draft, scope: .schedule, at: monday))
        #expect(runtime.shifts.applyScheduleChange(draft, decision: .nextShiftOnly, at: monday).synchronousResult == true)
        #expect(Self.handSet(runtime, 5) == Self.night)

        let today = try #require(runtime.session.snapshot(at: monday))
        #expect(today.startAtMs == Self.ms(try Self.at(runtime, 5, 8)))
        #expect(today.plannedEndAtMs == Self.ms(try Self.at(runtime, 5, 16)))
        // The day itself now works nights; from tomorrow the kept day is gone.
        let base = try #require(runtime.preferences.extendedSchedulePlan)
        #expect(base.hours(onDayKey: "2026-10-05")?.startTime == "20:00")
        #expect(runtime.session.todayOverride?.extendedKeptDay == KeptRosterDay(dayKey: "2026-10-05", shiftTypeID: nil))

        // Asked again, the kept plan is the same one.
        let kept = try #require(runtime.session.extendedSchedulePlan(at: monday))
        #expect(runtime.session.extendedSchedulePlan(at: monday)?.revision == kept.revision)
        #expect(kept.handSetDays["2026-10-05"] == nil)
    }

    @Test("Dropping the pattern writes it into this month and next")
    func droppingThePatternKeepsTwoMonths() throws {
        let plan = ExtendedSchedulePlan(
            shiftTypes: Self.everyDayEarly.shiftTypes,
            rule: Self.everyDayEarly.rule,
            handSetDays: ["2026-10-10": Self.night]
        )
        let months = try [0, 1].map { try #require(ExtendedScheduleEditing.month(of: "2026-10-17", plus: $0)) }
        #expect(ExtendedScheduleEditing.keepingPattern(plan, months: months, from: "2026-10-01", edits: nil)?.count == 31 - 1 + 30)
        // Days before the pattern took effect stay on the fixed hours they had.
        let edits = try #require(ExtendedScheduleEditing.keepingPattern(plan, months: months, from: "2026-10-05", edits: nil))
        #expect(edits.count == 31 - 4 - 1 + 30)
        #expect(edits["2026-10-04"] == nil)
        #expect(edits["2026-10-05"] == .shift(Self.early))
        #expect(edits["2026-10-10"] == nil)
        #expect(edits["2026-11-30"] == .shift(Self.early))

        let unpatterned = ExtendedSchedulePlan(
            shiftTypes: plan.shiftTypes,
            rule: nil,
            handSetDays: ExtendedScheduleEditing.handSetDays(plan.handSetDays, applying: edits)
        )
        let resolver = ExtendedScheduleResolver(plan: unpatterned)
        func day(_ key: String) throws -> ExtendedScheduleDay {
            resolver.day(dayNumber: try #require(ExtendedScheduleResolver.dayNumber(dayKey: key)))
        }
        #expect(try day("2026-10-10").shiftTypeID == Self.night)
        #expect(try day("2026-10-11").shiftTypeID == Self.early)
        #expect(try day("2026-10-04").source == .unassigned)
        // December repeats November by date.
        #expect(try day("2026-12-31").source == .unassigned)
        #expect(try day("2026-12-10").source == .carriedOver)
        #expect(try day("2026-12-10").shiftTypeID == Self.early)
    }

    @Test("Month arithmetic for the calendar")
    func calendarMonths() throws {
        #expect(ExtendedScheduleEditing.daysIn(year: 2026, month: 2) == 28)
        #expect(ExtendedScheduleEditing.daysIn(year: 2028, month: 2) == 29)
        #expect(ExtendedScheduleEditing.daysIn(year: 2026, month: 12) == 31)
        let next = try #require(ExtendedScheduleEditing.month(of: "2026-12-15", plus: 1))
        #expect(next.year == 2027 && next.month == 1)
        let back = try #require(ExtendedScheduleEditing.month(of: "2026-12-15", plus: -12))
        #expect(back.year == 2025 && back.month == 12)
        #expect(ExtendedScheduleEditing.editing(nil, dayKey: "2026-10-01", to: .followPattern, stored: [:]) == nil)
        #expect(ExtendedScheduleEditing.editing(nil, dayKey: "2026-10-01", to: .shift(Self.night), stored: [:])
            == ["2026-10-01": .shift(Self.night)])
    }

    // MARK: Filling in earlier days

    @Test("A day filled in before the roster began counts in Records, and later fixed hours ignore the calendar")
    func backfilledDaysCount() throws {
        let runtime = try Self.runtime()
        // Records begin on Monday 3 August, on fixed weekdays.
        #expect(runtime.shifts.reconcileRecordSchedule(at: try Self.on(runtime, month: 8, 3, 10)).synchronousResult == true)
        let monday = try Self.at(runtime, 5, 10)
        #expect(Self.save(runtime, .applyToToday, at: monday) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
        })
        #expect(runtime.records.extendedScheduleStart == runtime.preferences.recordsCalendar.startOfDay(for: monday))

        // Saturday 8 August was a rest day; it was really an early shift.
        #expect(Self.save(runtime, .applyToToday, at: monday) { $0.rosterEdits = ["2026-08-08": .shift(Self.early)] })
        let saturday = try Self.recorded(runtime, month: 8, day: 8)
        #expect(saturday.isWorkday)
        #expect(saturday.shiftAnchorStartAtMs == Self.ms(try Self.on(runtime, month: 8, 8, 8)))
        // The rest of that month keeps its fixed weekdays.
        #expect(try Self.recorded(runtime, month: 8, day: 9).isWorkday == false)
        let weekday = try Self.recorded(runtime, month: 8, day: 10)
        #expect(weekday.isWorkday)
        #expect(weekday.shiftAnchorStartAtMs == Self.ms(try Self.on(runtime, month: 8, 10, 9)))

        // The calendar's view of the fixed schedule leaves the hand-set day out.
        let fixed = runtime.queries.fixedPlannedWorkdays(
            from: try Self.on(runtime, month: 8, 8, 0),
            through: try Self.on(runtime, month: 8, 10, 0)
        )
        #expect(fixed == ["2026-08-08": false, "2026-08-09": false, "2026-08-10": true])
        #expect(runtime.queries.fixedPlannedWorkdays(
            from: try Self.on(runtime, month: 7, 31, 0),
            through: try Self.on(runtime, month: 8, 1, 0)
        ).isEmpty)

        // Back on fixed hours from 12 October: the countdown ignores the
        // calendar there, and so does Records.
        let later = try Self.at(runtime, 12, 10)
        #expect(Self.save(runtime, .applyToToday, at: later) { $0.extendedScheduleEnabled = false })
        #expect(Self.save(runtime, .applyToToday, at: later) { $0.rosterEdits = ["2026-10-17": .shift(Self.early)] })
        #expect(try Self.recorded(runtime, day: 17).isWorkday == false)
        #expect(try Self.recorded(runtime, month: 8, day: 8).isWorkday)
    }

    @Test("Fixed hours are expanded exactly as before while no day is set by hand")
    func fixedHoursWithoutBackfill() throws {
        let runtime = try Self.runtime()
        #expect(runtime.shifts.reconcileRecordSchedule(at: try Self.on(runtime, month: 8, 3, 10)).synchronousResult == true)
        #expect(Self.save(runtime, .applyToToday, at: try Self.at(runtime, 5, 10)) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
        })
        let fixed = try #require(runtime.records.state.snapshots.min { $0.effectiveFrom < $1.effectiveFrom })
        let hours = try #require(runtime.records.expandableHours(for: fixed))
        #expect(hours.extendedContent == nil)
        #expect(hours.extendedSchedule == nil)
    }

    @Test("Legacy rows keep the old fixed boundary while frozen rows can repair later fixed history")
    func legacyAndFrozenFixedHistory() throws {
        let runtime = try Self.runtime()
        #expect(runtime.shifts.reconcileRecordSchedule(
            at: try Self.on(runtime, month: 8, 3, 10)
        ).synchronousResult == true)
        let extendedStart = try Self.at(runtime, 5, 10)
        #expect(Self.save(runtime, .applyToToday, at: extendedStart) {
            $0.extendedScheduleEnabled = true
            $0.extendedContent = Self.everyDayEarly
        })
        let fixedAgain = try Self.at(runtime, 12, 10)
        #expect(Self.save(runtime, .applyToToday, at: fixedAgain) { $0.extendedScheduleEnabled = false })

        // Rows written by older builds have only the type id. Preserve their
        // original compatibility boundary: pre-extended fixed history sees
        // them, later fixed schedules do not.
        runtime.records.upsertRosterDay(RosterDay(
            dayKey: "2026-08-08", shiftTypeID: Self.early,
            timeZoneIdentifier: Self.zoneIdentifier, editedAt: fixedAgain,
            editCount: 0, editTieBreaker: UUID()
        ))
        runtime.records.upsertRosterDay(RosterDay(
            dayKey: "2026-10-17", shiftTypeID: Self.early,
            timeZoneIdentifier: Self.zoneIdentifier, editedAt: fixedAgain,
            editCount: 0, editTieBreaker: UUID()
        ))
        #expect(try Self.recorded(runtime, month: 8, day: 8).isWorkday)
        #expect(try Self.recorded(runtime, day: 17).isWorkday == false)

        // Re-saving the later day as historical freezes the selected type and
        // intentionally repairs that later fixed snapshot too.
        #expect(Self.save(runtime, .applyToToday, at: try Self.at(runtime, 20, 10)) {
            $0.rosterEdits = ["2026-10-17": .shift(Self.night)]
        })
        #expect(runtime.records.state.rosterDays.first(where: { $0.dayKey == "2026-10-17" })?.assignedShiftType
            == Self.nightType)
        let repaired = try Self.recorded(runtime, day: 17)
        #expect(repaired.isWorkday)
        #expect(repaired.shiftAnchorStartAtMs == Self.ms(try Self.at(runtime, 17, 20)))
    }

    @Test("An overlay decides only the days set by hand")
    func overlayDecidesHandSetDaysOnly() throws {
        let overlay = ExtendedSchedulePlan(
            shiftTypes: Self.everyDayEarly.shiftTypes,
            rule: Self.everyDayEarly.rule,
            handSetDays: ["2026-08-08": Self.night],
            fallsBackToBaseSchedule: true
        )
        let resolver = ExtendedScheduleResolver(plan: overlay)
        let saturday = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-08-08"))
        #expect(resolver.day(dayNumber: saturday).shiftTypeID == Self.night)
        // Neither the rule nor the month being filled in decides another day.
        #expect(resolver.day(dayNumber: saturday + 1).source == .unassigned)
        #expect(resolver.day(dayNumber: saturday + 31).source == .unassigned)

        let classic = ScheduleHoursConfiguration(
            startTime: "09:00",
            endTime: "17:00",
            workdays: [1, 2, 3, 4, 5],
            schedule: NativeWorkSchedule(
                mode: "classic",
                referenceWeekStartMs: nil,
                referenceWeekType: nil,
                singleWeekendWorkday: nil,
                rotationAnchorMs: nil,
                rotationWorkDays: nil,
                rotationRestDays: nil
            ),
            breakStartTime: nil,
            breakDurationMinutes: 0,
            extendedSchedule: overlay
        )
        let zone = try #require(TimeZone(identifier: Self.zoneIdentifier))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let days = ScheduleRules.expandScheduleRange(
            configuration: classic,
            from: try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7))),
            through: try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))),
            timeZone: zone
        )
        #expect(days.map(\.isWorkday) == [true, true, false])
        let friday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 9)))
        let saturdayNight = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 20)))
        #expect(days[0].shiftAnchorStartAtMs == Self.ms(friday))
        #expect(days[1].shiftAnchorStartAtMs == Self.ms(saturdayNight))
    }

    // MARK: Pinning

    @Test("A pinned day does not make a carried-over month authored")
    func pinnedDayKeepsCarryOver() throws {
        let plan = ExtendedSchedulePlan(
            shiftTypes: [Self.earlyType, Self.nightType, Self.restType],
            rule: nil,
            handSetDays: ["2026-09-20": Self.night, "2026-09-21": Self.early]
        )
        let pinned = plan.pinning(dayKey: "2026-10-21", to: ExtendedScheduleDayHours(
            startTime: "07:00", endTime: "15:00", breakStartTime: nil, breakDurationMinutes: 0
        ))
        let resolver = ExtendedScheduleResolver(plan: pinned)
        let october20 = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-10-20"))
        let october21 = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-10-21"))
        #expect(resolver.day(dayNumber: october20).shiftTypeID == Self.night)
        #expect(resolver.day(dayNumber: october20).source == .carriedOver)
        #expect(resolver.day(dayNumber: october21).hours?.startTime == "07:00")

        // Pinning a hand-set day leaves what later months copy from it.
        let pinnedSource = plan.pinning(dayKey: "2026-09-21", to: ExtendedScheduleDayHours(
            startTime: "07:00", endTime: "15:00", breakStartTime: nil, breakDurationMinutes: 0
        ))
        #expect(ExtendedScheduleResolver(plan: pinnedSource).day(dayNumber: october21).shiftTypeID == Self.early)

        let decoded = try JSONDecoder().decode(ExtendedSchedulePlan.self, from: JSONEncoder().encode(pinned))
        #expect(decoded == pinned)
    }

    // MARK: Editing helpers

    @Test("A type the rule hands out stays; a saved one is archived, a new one dropped")
    func removingTypes() {
        let saved = Self.everyDayEarly
        #expect(ExtendedScheduleEditing.ruleUses(Self.early, in: saved))
        #expect(!ExtendedScheduleEditing.ruleUses(Self.night, in: saved))

        let archived = ExtendedScheduleEditing.removing(Self.night, from: saved, saved: saved)
        #expect(archived.shiftTypes.count == 3)
        #expect(archived.shiftTypes.first { $0.id == Self.night }?.isArchived == true)
        #expect(!ExtendedScheduleEditing.activeTypes(in: archived).contains { $0.id == Self.night })

        var fresh = Self.nightType
        fresh.id = UUID()
        let added = ExtendedScheduleEditing.upserting(fresh, in: saved)
        let dropped = ExtendedScheduleEditing.removing(fresh.id, from: added, saved: saved)
        #expect(dropped == saved)
    }

    @Test("The cycle can be resized and moved without changing what its days work")
    func resizingAndAnchoring() throws {
        var content = Self.everyDayEarly
        content.shiftTypes.removeAll { $0.id == Self.rest }
        let longer = ExtendedScheduleEditing.resizing(content, to: 3, restName: "Rest")
        let rule = try #require(longer.rule)
        #expect(rule.days.count == 3)
        #expect(rule.days[0] == Self.early)
        // With no rest type left, lengthening adds one.
        let addedRest = try #require(longer.shiftTypes.first { $0.kind == .rest })
        #expect(rule.days[1] == addedRest.id && rule.days[2] == addedRest.id)
        #expect(ExtendedScheduleEditing.resizing(longer, to: 1, restName: "Rest").rule?.days == [Self.early])
        #expect(ExtendedScheduleEditing.resizing(longer, to: 500, restName: "Rest").rule?.days.count
            == ExtendedScheduleEditing.maximumCycleLength)

        #expect(ExtendedScheduleEditing.cycleDay(of: rule, todayKey: "2026-10-05") == 1)
        #expect(ExtendedScheduleEditing.cycleDay(of: rule, todayKey: "2026-10-09") == 2)
        #expect(ExtendedScheduleEditing.cycleDay(of: rule, todayKey: "2026-10-01") == 3)
        let moved = ExtendedScheduleEditing.anchoring(longer, todayKey: "2026-10-09", atCycleDay: 3)
        #expect(moved.rule?.anchorDayKey == "2026-10-07")
        #expect(moved.rule?.days == rule.days)
        #expect(ExtendedScheduleEditing.dayKey("2026-10-30", plus: 3) == "2026-11-02")

        let assigned = ExtendedScheduleEditing.assigning(Self.night, at: 2, in: longer)
        #expect(assigned.rule?.days == [Self.early, addedRest.id, Self.night])
        #expect(ExtendedScheduleEditing.primaryWorkType(in: assigned) == Self.early)
    }

    @Test("A template keeps the work type the rule already uses")
    func templateKeepsTheWorkType() throws {
        let runtime = try Self.runtime()
        var content = Self.everyDayEarly
        content.rule?.days = [Self.night, Self.rest]
        let weekly = runtime.session.applyingTemplate(.weekly, to: content, at: try Self.at(runtime, 7, 10))
        let rule = try #require(weekly.rule)
        #expect(rule.preset == .weekly)
        #expect(rule.anchorDayKey == "2026-10-05")
        #expect(rule.days == [Self.night, Self.night, Self.night, Self.night, Self.night, Self.rest, Self.rest])
        #expect(weekly.shiftTypes == content.shiftTypes)
    }

    @Test("A preset from a newer build reads as custom")
    func unknownPresetDecodes() throws {
        let json = #"{"preset":"lunar","anchorDayKey":"2026-10-05","days":["00000000-0000-0000-0000-0000000000D1"]}"#
        let rule = try JSONDecoder().decode(ShiftCycleRule.self, from: Data(json.utf8))
        #expect(rule.preset == .custom)
        #expect(rule.days == [Self.early])
        let weekly = try JSONEncoder().encode(ShiftCycleRule(preset: .weekly, anchorDayKey: "2026-10-05", days: []))
        #expect(String(decoding: weekly, as: UTF8.self).contains("\"weekly\""))
    }
    @Test("Leaving an unsaved free preview discards generated days but keeps deliberate changes")
    func freePreviewRestoresPattern() {
        var draft = ScheduleFieldChange(
            rosterEdits: ["2026-09-21": .shift(Self.early), "2026-09-22": .shift(Self.night)],
            materializedRosterDays: ["2026-09-21"]
        )
        draft.restorePatternAfterFreePreview()
        #expect(draft.rosterEdits == ["2026-09-22": .shift(Self.night)])
        #expect(draft.materializedRosterDays.isEmpty)
        let days = ExtendedScheduleEditing.handSetDays(["2026-09-23": Self.rest], applying: draft.rosterEdits)
        #expect(days == ["2026-09-22": Self.night, "2026-09-23": Self.rest])
    }

    @Test("First-run holidays use final hours and breaks, while replay preserves a saved plan")
    func firstRunHolidayPlan() throws {
        let defaults = try #require(UserDefaults(suiteName: "FirstRunHoliday.\(UUID())"))
        defaults.set(Self.zoneIdentifier, forKey: "ios.native.recordsTimeZone")
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        runtime.preferences.applyPreferences {
            $0.startMinutes = 600
            $0.endMinutes = 1140
            $0.lunchEnabled = true
            $0.lunchStartMinutes = 780
            $0.lunchDurationMinutes = 90
        }
        _ = runtime.shifts.completeSetup(holidayRegionIdentifier: "CN", at: try Self.at(runtime, 7, 10)).synchronousResult
        let saved = try #require(runtime.preferences.extendedScheduleContent)
        #expect(saved.holidayRegionIdentifier == "CN")
        let work = try #require(saved.shiftTypes.first { $0.kind == .work })
        #expect(work.startMinutes == 600 && work.endMinutes == 1140)
        #expect(work.breakStartMinutes == 780 && work.breakDurationMinutes == 90)
        #expect(runtime.preferences.onboardingComplete)
        _ = runtime.shifts.completeSetup(holidayRegionIdentifier: "US").synchronousResult
        #expect(runtime.preferences.extendedScheduleContent == saved)
    }

}
