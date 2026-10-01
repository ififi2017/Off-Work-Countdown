import Foundation
import Testing
@testable import App

/// Plan 020 §3: which alarms the schedule asks for, before AlarmKit is
/// involved.
@Suite("Shift alarm planner")
struct ShiftAlarmPlannerTests {
    private static let shanghai = "Asia/Shanghai"
    private static let office = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private static let rest = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
    private static let night = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
    private static let dawn = UUID(uuidString: "00000000-0000-0000-0000-000000000304")!

    private static func type(_ id: UUID, _ name: String, _ kind: ShiftType.Kind, start: Int, end: Int) -> ShiftType {
        ShiftType(
            id: id, name: name, kind: kind, startMinutes: start, endMinutes: end,
            breakEnabled: false, breakStartMinutes: 0, breakDurationMinutes: 0,
            colorHex: "#FF7A00", isArchived: false
        )
    }

    private static let officeType = type(office, "Office", .work, start: 9 * 60, end: 18 * 60)
    private static let restType = type(rest, "Rest", .rest, start: 9 * 60, end: 18 * 60)
    private static let nightType = type(night, "Night", .work, start: 22 * 60, end: 6 * 60)
    private static let dawnType = type(dawn, "Dawn", .work, start: 30, end: 8 * 60 + 30)

    private static let classicSchedule = NativeWorkSchedule(
        mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
        singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil
    )

    private static func ms(_ key: String, hour: Int, minute: Int = 0) throws -> Double {
        let parts = try key.split(separator: "-").map { try #require(Int($0)) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: shanghai))
        return try #require(calendar.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute
        ))).timeIntervalSince1970 * 1_000
    }

    private static func configuration(plan: ExtendedSchedulePlan? = nil) -> ScheduleHoursConfiguration {
        ScheduleHoursConfiguration(
            startTime: "09:00", endTime: "18:00", workdays: [1, 2, 3, 4, 5],
            schedule: classicSchedule, breakStartTime: nil, breakDurationMinutes: 0,
            extendedSchedule: plan
        )
    }

    /// A week starting Monday 2026-09-21 that repeats `days`.
    private static func weeklyPlan(
        _ days: [UUID],
        types: [ShiftType] = [officeType, restType, nightType, dawnType],
        region: String? = nil,
        handSet: [String: UUID] = [:]
    ) -> ExtendedSchedulePlan {
        ExtendedSchedulePlan(
            shiftTypes: types,
            rule: ShiftCycleRule(preset: .weekly, anchorDayKey: "2026-09-21", days: days),
            handSetDays: handSet,
            holidayRegionIdentifier: region
        )
    }

    private static func alarms(
        _ configuration: ScheduleHoursConfiguration,
        settings: ShiftAlarmSettings = ShiftAlarmSettings(isEnabled: true),
        now: Double,
        until: Double
    ) throws -> [PlannedShiftAlarm] {
        ShiftAlarmPlanner.alarms(
            configuration: configuration,
            timeZone: try #require(TimeZone(identifier: shanghai)),
            settings: settings,
            nowMs: now,
            untilMs: until
        )
    }

    @Test("Fixed hours ring an hour before each workday's shift, skipping weekends and anything already past")
    func fixedHours() throws {
        // Thursday 2026-10-01 at noon: today's 08:00 alarm has gone.
        let result = try Self.alarms(Self.configuration(), now: Self.ms("2026-10-01", hour: 12),
                                     until: Self.ms("2026-10-07", hour: 12))
        #expect(result.map(\.dayKey) == ["2026-10-02", "2026-10-05", "2026-10-06", "2026-10-07"])
        #expect(try result.map(\.fireAtMs) == [
            Self.ms("2026-10-02", hour: 8), Self.ms("2026-10-05", hour: 8),
            Self.ms("2026-10-06", hour: 8), Self.ms("2026-10-07", hour: 8),
        ])
        #expect(result.allSatisfy { $0.shiftTypeID == nil && $0.shiftName == nil })
        #expect(result.allSatisfy { $0.shiftStartAtMs - $0.fireAtMs == 60 * 60_000 })

        let off = try Self.alarms(Self.configuration(), settings: ShiftAlarmSettings(isEnabled: false),
                                  now: Self.ms("2026-10-01", hour: 12), until: Self.ms("2026-10-07", hour: 12))
        #expect(off.isEmpty)
    }

    @Test("Each shift type keeps its own lead; a silenced type gets none; an early lead reaches into the previous day")
    func perShiftType() throws {
        // Mon office, Tue night, Wed dawn (00:30), Thu office, Fri office, weekend rest.
        let plan = Self.weeklyPlan([Self.office, Self.night, Self.dawn, Self.office, Self.office, Self.rest, Self.rest])
        var settings = ShiftAlarmSettings(isEnabled: true)
        settings.leadMinutesByShiftType = [Self.night: 90, Self.dawn: 60]
        let result = try Self.alarms(Self.configuration(plan: plan), settings: settings,
                                     now: Self.ms("2026-09-27", hour: 12), until: Self.ms("2026-10-01", hour: 23))
        #expect(result.map(\.dayKey) == ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"])
        #expect(result.map(\.shiftName) == ["Office", "Night", "Dawn", "Office"])
        #expect(try result.map(\.fireAtMs) == [
            Self.ms("2026-09-28", hour: 8),
            Self.ms("2026-09-29", hour: 20, minute: 30),
            // Wednesday's 00:30 shift rings at 23:30 on Tuesday.
            Self.ms("2026-09-29", hour: 23, minute: 30),
            Self.ms("2026-10-01", hour: 8),
        ])

        settings.silencedShiftTypeIDs = [Self.night]
        let silenced = try Self.alarms(Self.configuration(plan: plan), settings: settings,
                                       now: Self.ms("2026-09-27", hour: 12), until: Self.ms("2026-10-01", hour: 23))
        #expect(silenced.map(\.dayKey) == ["2026-09-28", "2026-09-30", "2026-10-01"])
    }

    @Test("Nothing rings at or after the end of the window, or at or before now")
    func windowBounds() throws {
        let configuration = Self.configuration()
        let fire = try Self.ms("2026-10-05", hour: 8)
        #expect(try Self.alarms(configuration, now: Self.ms("2026-10-03", hour: 0), until: fire).isEmpty)
        #expect(try Self.alarms(configuration, now: Self.ms("2026-10-03", hour: 0), until: fire + 1).map(\.fireAtMs) == [fire])
        #expect(try Self.alarms(configuration, now: fire, until: Self.ms("2026-10-05", hour: 23)).isEmpty)
        #expect(try Self.alarms(configuration, now: fire - 1, until: Self.ms("2026-10-05", hour: 23)).count == 1)
    }

    @Test("Holidays, hand-set days and a mainland makeup workday follow the resolved schedule")
    func resolvedSchedule() throws {
        let week = [Self.office, Self.office, Self.office, Self.office, Self.office, Self.rest, Self.rest]
        let now = try Self.ms("2026-09-28", hour: 0)
        let until = try Self.ms("2026-10-12", hour: 0)

        let holidays = try Self.alarms(Self.configuration(plan: Self.weeklyPlan(week, region: "CN")), now: now, until: until)
        let holidayKeys = Set(holidays.map(\.dayKey))
        // The National Day break rests through the 7th.
        #expect(holidayKeys.isDisjoint(with: (1...7).map { String(format: "2026-10-%02d", $0) }))
        // Every day that rings is a workday on the resolved plan.
        let resolver = ExtendedScheduleResolver(plan: Self.weeklyPlan(week, region: "CN"))
        for key in holidayKeys {
            let day = try #require(ExtendedScheduleResolver.dayNumber(dayKey: key))
            #expect(resolver.day(dayNumber: day).isWorkday)
        }

        // A Saturday set to the office by hand rings; a Monday set to rest does not.
        let swapped = Self.weeklyPlan(week, handSet: ["2026-10-03": Self.office, "2026-10-05": Self.rest])
        let swappedKeys = try Self.alarms(Self.configuration(plan: swapped), now: now, until: until).map(\.dayKey)
        #expect(swappedKeys.contains("2026-10-03"))
        #expect(!swappedKeys.contains("2026-10-05"))
    }

    @Test("Ids are stable for the same alarm and change with anything it says or when it rings")
    func stableIDs() throws {
        let now = try Self.ms("2026-10-01", hour: 12)
        let until = try Self.ms("2026-10-07", hour: 12)
        let first = try Self.alarms(Self.configuration(), now: now, until: until)
        let again = try Self.alarms(Self.configuration(), now: now + 60_000, until: until)
        #expect(first.map(\.id) == again.map(\.id))
        #expect(Set(first.map(\.id)).count == first.count)

        var earlier = ShiftAlarmSettings(isEnabled: true)
        earlier.defaultLeadMinutes = 90
        let moved = try Self.alarms(Self.configuration(), settings: earlier, now: now, until: until)
        #expect(Set(moved.map(\.id)).isDisjoint(with: first.map(\.id)))

        let renamed = ShiftAlarmPlanner.stableID(dayKey: "2026-10-02", fireAtMs: 1, shiftStartAtMs: 2, shiftName: "A")
        #expect(renamed != ShiftAlarmPlanner.stableID(dayKey: "2026-10-02", fireAtMs: 1, shiftStartAtMs: 2, shiftName: "B"))
    }

    @Test("The window follows the entitlement: exact subscription or grace expiry, a year for lifetime, none otherwise")
    func entitlementWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: Self.shanghai))
        let now = Date(timeIntervalSince1970: try Self.ms("2026-10-01", hour: 12) / 1_000)
        let expiry = now.addingTimeInterval(9 * 86_400 + 3_723)
        #expect(ShiftAlarmPlanner.windowEnd(for: .authorized(.subscribed(expiresAt: expiry)), now: now, calendar: calendar) == expiry)
        #expect(ShiftAlarmPlanner.windowEnd(for: .authorized(.inGracePeriod(graceExpiresAt: expiry)), now: now, calendar: calendar) == expiry)
        #expect(ShiftAlarmPlanner.windowEnd(for: .authorized(.subscribed(expiresAt: now)), now: now, calendar: calendar) == nil)
        #expect(ShiftAlarmPlanner.windowEnd(for: .authorized(.lifetime), now: now, calendar: calendar)
            == Date(timeIntervalSince1970: try Self.ms("2027-10-01", hour: 12) / 1_000))
        #expect(ShiftAlarmPlanner.windowEnd(for: .unauthorized, now: now, calendar: calendar) == nil)
        #expect(ShiftAlarmPlanner.windowEnd(for: .pendingAskToBuy, now: now, calendar: calendar) == nil)
    }

    @Test("Alarm settings stay on this device: switching them on never touches synced preferences or the archive")
    @MainActor
    func settingsStayLocal() throws {
        let suite = "ShiftAlarmPlannerTests.local.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let records = RecordCoordinator.inMemory()
        let preferences = PreferencesStore(defaults: defaults, records: records)
        let synced = preferences.currentSyncedPreferences()
        let archive = records.state

        var settings = ShiftAlarmSettings(isEnabled: true)
        settings.leadMinutesByShiftType = [Self.night: 90]
        preferences.shiftAlarmSettings = settings

        #expect(preferences.currentSyncedPreferences() == synced)
        #expect(records.state == archive)
        // Another launch on this device reads them back from local defaults.
        #expect(PreferencesStore(defaults: defaults, records: records).shiftAlarmSettings == settings)
    }
}
