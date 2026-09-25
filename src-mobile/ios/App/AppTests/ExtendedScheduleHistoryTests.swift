import Foundation
import Testing
@testable import App

@MainActor
@Suite("Historical roster planning")
struct ExtendedScheduleHistoryTests {
    private static let zone = TimeZone(identifier: "Asia/Shanghai")!
    private static let shiftID = UUID(uuidString: "00000000-0000-0000-0000-00000000A101")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static var early: ShiftType {
        ShiftType(
            id: shiftID, name: "Early", kind: .work,
            startMinutes: 7 * 60, endMinutes: 15 * 60,
            breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
            colorHex: "#F28C28", isArchived: false
        )
    }

    private static func date(_ day: Int, hour: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour)))
    }

    private static func runtime() throws -> AppRuntime {
        let suite = "ExtendedScheduleHistoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("Asia/Shanghai", forKey: "ios.native.recordsTimeZone")
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        runtime.preferences.applyPreferences {
            $0.scheduleMode = .classic
            $0.workdays = [1, 2, 3, 4, 5]
            $0.startMinutes = 9 * 60
            $0.endMinutes = 17 * 60
            $0.lunchEnabled = false
            $0.salaryEnabled = true
            $0.salaryType = .daily
            $0.salaryAmount = "100"
        }
        runtime.records.ensureSeeded(
            hours: runtime.session.hoursConfiguration(at: try date(1)),
            at: try date(1), timeZone: zone
        )
        return runtime
    }

    private static func savePast(_ runtime: AppRuntime, edit: RosterDayEdit = .shift(shiftID)) throws -> Bool {
        let content = ExtendedScheduleContent(shiftTypes: [early], rule: nil)
        let change = ScheduleFieldChange(
            extendedScheduleEnabled: true,
            extendedContent: content,
            rosterEdits: ["2026-09-08": edit]
        )
        return runtime.shifts.applyScheduleChange(
            change, decision: .applyToToday, at: try date(20, hour: 12)
        ).synchronousResult == true
    }

    @Test("A month's batched previews match asking day by day, before and after an edit")
    func batchedPreviewsMatchSingleDays() throws {
        let runtime = try Self.runtime()
        let keys = (1...19).map { String(format: "2026-09-%02d", $0) }
        func check(ignoring ignored: Set<String>) {
            let batch = runtime.records.plannedRosterPreviews(
                dayKeys: keys, timeZoneIdentifier: Self.zone.identifier,
                fallbackTypes: [Self.early], ignoringRosterAssignment: { ignored.contains($0) }
            )
            for key in keys {
                #expect(batch[key] == runtime.records.plannedRosterPreview(
                    dayKey: key, timeZoneIdentifier: Self.zone.identifier,
                    fallbackTypes: [Self.early], ignoringRosterAssignment: ignored.contains(key)
                ), "\(key)")
            }
        }
        check(ignoring: [])
        #expect(runtime.records.frozenRosterShiftTypes.isEmpty)
        #expect(try Self.savePast(runtime))
        // The cached frozen types and overlay plan must follow the new roster row.
        #expect(runtime.records.frozenRosterShiftTypes["2026-09-08"]?.id == Self.shiftID)
        check(ignoring: [])
        check(ignoring: ["2026-09-08"])
    }

    @Test("A past assignment changes planned Records hours and income and stays frozen")
    func plannedHistoryAndIncomeStayFrozen() throws {
        let runtime = try Self.runtime()
        let original = runtime.records.plannedRosterPreview(
            dayKey: "2026-09-08", timeZoneIdentifier: Self.zone.identifier
        )
        guard case .shift(let originalType) = original else {
            Issue.record("Expected the fixed snapshot's planned shift")
            return
        }
        #expect(originalType.startMinutes == 9 * 60)
        #expect(try Self.savePast(runtime))
        #expect(runtime.records.plannedRosterPreview(
            dayKey: "2026-09-08", timeZoneIdentifier: Self.zone.identifier
        ) == .shift(Self.early))
        let restored = runtime.records.plannedRosterPreview(
            dayKey: "2026-09-08", timeZoneIdentifier: Self.zone.identifier,
            ignoringRosterAssignment: true
        )
        guard case .shift(let restoredType) = restored else {
            Issue.record("Expected follow-pattern preview to restore the saved snapshot")
            return
        }
        #expect(restoredType.startMinutes == 9 * 60)
        var day = try #require(runtime.queries.resolvedDays(from: Self.date(8), through: Self.date(8)).first)
        let frozenStart = try Self.date(8, hour: 7).timeIntervalSince1970 * 1_000
        #expect(day.isScheduledWorkday)
        #expect(day.segments.first?.startAtMs == frozenStart)
        let metrics = runtime.queries.recordsMetrics(for: [day])
        #expect(metrics.workDurationMs == 8 * 3_600_000)
        #expect(runtime.queries.recordsIncome(completedWorkdays: metrics.workdayCount, at: try Self.date(20)) == 100)

        var edited = Self.early
        edited.startMinutes = 11 * 60
        edited.endMinutes = 19 * 60
        #expect(runtime.records.updateExtendedSchedule(
            content: ExtendedScheduleContent(shiftTypes: [edited], rule: nil), enabled: nil,
            timeZoneIdentifier: Self.zone.identifier, at: try Self.date(21)
        ))
        day = try #require(runtime.queries.resolvedDays(from: Self.date(8), through: Self.date(8)).first)
        #expect(day.segments.first?.startAtMs == frozenStart)
    }

    @Test("Historical preview distinguishes rest from no saved plan")
    func historicalPreviewStates() throws {
        let runtime = try Self.runtime()
        #expect(runtime.records.plannedRosterPreview(
            dayKey: "2026-09-06", timeZoneIdentifier: Self.zone.identifier
        ) == .rest)
        #expect(runtime.records.plannedRosterPreview(
            dayKey: "2026-08-31", timeZoneIdentifier: Self.zone.identifier
        ) == .noPlan)
    }

    @Test("Clearing restores fixed history while actual and leave records keep priority")
    func clearAndPrecedence() throws {
        let runtime = try Self.runtime()
        #expect(try Self.savePast(runtime))
        let custom = [NativeShiftSegment(
            startAtMs: try Self.date(8, hour: 12).timeIntervalSince1970 * 1_000,
            endAtMs: try Self.date(8, hour: 13).timeIntervalSince1970 * 1_000
        )]
        runtime.records.upsertOverride(DayOverride(
            dayKey: "2026-09-08", shiftAnchorDate: try Self.date(8),
            kind: .customSegments, segments: custom,
            timeZoneIdentifier: Self.zone.identifier
        ))
        var day = try #require(runtime.queries.resolvedDays(from: Self.date(8), through: Self.date(8)).first)
        #expect(day.layer == .override && day.segments == custom)

        runtime.records.upsertOverride(DayOverride(
            dayKey: "2026-09-08", shiftAnchorDate: try Self.date(8),
            kind: .cleared, segments: [], timeZoneIdentifier: Self.zone.identifier
        ))
        runtime.records.upsertException(CalendarException(
            dayKey: CalendarException.dayKey(dateKey: "2026-09-08", origin: .user),
            date: try Self.date(8), effect: .rest, origin: .user, isCleared: false,
            regionIdentifier: nil, datasetVersion: nil, label: nil,
            editedAt: try Self.date(20), editCount: 0, editTieBreaker: UUID(),
            timeZoneIdentifier: Self.zone.identifier
        ))
        day = try #require(runtime.queries.resolvedDays(from: Self.date(8), through: Self.date(8)).first)
        #expect(day.layer == .calendarException && !day.isScheduledWorkday)

        #expect(try Self.savePast(runtime, edit: .followPattern))
        runtime.records.upsertException(CalendarException(
            dayKey: CalendarException.dayKey(dateKey: "2026-09-08", origin: .user),
            date: try Self.date(8), effect: .work, origin: .user, isCleared: true,
            regionIdentifier: nil, datasetVersion: nil, label: nil,
            editedAt: try Self.date(21), editCount: 0, editTieBreaker: UUID(),
            timeZoneIdentifier: Self.zone.identifier
        ))
        day = try #require(runtime.queries.resolvedDays(from: Self.date(8), through: Self.date(8)).first)
        let fixedStart = try Self.date(8, hour: 9).timeIntervalSince1970 * 1_000
        #expect(day.layer == .schedule)
        #expect(day.segments.first?.startAtMs == fixedStart)
    }

    @Test("An edit outside every career period is rejected without mutation")
    func outsideCareerIsRejected() throws {
        let runtime = try Self.runtime()
        let content = ExtendedScheduleContent(shiftTypes: [Self.early], rule: nil)
        let change = ScheduleFieldChange(
            extendedScheduleEnabled: true, extendedContent: content,
            rosterEdits: ["2026-08-31": .shift(Self.shiftID)]
        )
        #expect(runtime.shifts.applyScheduleChange(
            change, decision: .applyToToday, at: try Self.date(20)
        ).synchronousResult == false)
        #expect(runtime.records.state.rosterDays.isEmpty)
        #expect(runtime.records.state.extendedSchedule == nil)
    }

    @Test("A frozen plan resolves inside a career even before its first snapshot")
    func frozenPlanWithoutSnapshot() throws {
        var state = RecordState()
        state.periods = [CareerPeriod(
            id: UUID(), startsOn: try Self.date(1), endsBefore: nil, label: nil,
            timeZoneIdentifier: Self.zone.identifier, calendarIdentifier: "gregorian",
            createdAt: try Self.date(1), editedAt: try Self.date(1),
            editCount: 1, editTieBreaker: UUID()
        )]
        state.rosterDays = [RosterDay(
            dayKey: "2026-09-08", shiftTypeID: Self.shiftID, assignedShiftType: Self.early,
            timeZoneIdentifier: Self.zone.identifier, editedAt: try Self.date(20),
            editCount: 1, editTieBreaker: UUID()
        )]
        let suite = "ExtendedScheduleHistoryTests.noSnapshot.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("Asia/Shanghai", forKey: "ios.native.recordsTimeZone")
        let runtime = AppRuntime(defaults: defaults, records: .restoreCandidate(from: state))
        let day = try #require(runtime.queries.resolvedDays(from: Self.date(8), through: Self.date(8)).first)
        let frozenStart = try Self.date(8, hour: 7).timeIntervalSince1970 * 1_000
        #expect(day.layer == .schedule)
        #expect(day.snapshotID == nil)
        #expect(day.segments.first?.startAtMs == frozenStart)
    }

    @Test("An old roster DTO without a frozen type still decodes")
    func oldRosterDTODecodes() throws {
        let data = Data("""
        {"dayKey":"2026-09-08","shiftTypeID":"\(Self.shiftID.uuidString)","timeZoneIdentifier":"Asia/Shanghai","editedAtMs":0,"editCount":1,"editTieBreaker":"00000000-0000-0000-0000-000000000001"}
        """.utf8)
        let value = try #require(JSONDecoder().decode(RosterDayDTO.self, from: data).value())
        #expect(value.assignedShiftType == nil)
    }

    @Test("Upcoming schedule status labels only the current and next month")
    func upcomingScheduleMonthStatus() throws {
        let calendar = Self.calendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 20)))
        let current = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 28)))
        let next = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 2)))
        let later = try #require(calendar.date(from: DateComponents(year: 2027, month: 2, day: 2)))
        #expect(ShiftSessionStore.scheduleMonthStatusKey(for: current, relativeTo: now, calendar: calendar)
            == "scheduleCurrentMonthActive")
        #expect(ShiftSessionStore.scheduleMonthStatusKey(for: next, relativeTo: now, calendar: calendar)
            == "scheduleNextMonthPlanned")
        #expect(ShiftSessionStore.scheduleMonthStatusKey(for: later, relativeTo: now, calendar: calendar) == nil)
    }
    @Test("Legacy fixed history borrows an unambiguous shift name without changing old breaks")
    func legacyNamedPreview() throws {
        let runtime = try Self.runtime()
        var named = Self.early
        named.name = "Day"
        named.startMinutes = 540
        named.endMinutes = 1020
        named.breakEnabled = true
        named.breakStartMinutes = 720
        named.breakDurationMinutes = 60
        let preview = runtime.records.plannedRosterPreview(
            dayKey: "2026-09-08", timeZoneIdentifier: Self.zone.identifier, fallbackTypes: [named])
        guard case .shift(let historical) = preview else { Issue.record("Expected fixed history"); return }
        #expect(historical.name == "Day")
        #expect(historical.breakEnabled == false)
        #expect(historical.id != named.id)
        let day = try #require(runtime.queries.resolvedDays(from: Self.date(8), through: Self.date(8)).first)
        #expect(day.segments.reduce(0) { $0 + $1.endAtMs - $1.startAtMs } == 8 * 3_600_000)
    }

}
