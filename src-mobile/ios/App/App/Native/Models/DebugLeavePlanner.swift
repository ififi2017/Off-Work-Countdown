#if DEBUG
import Foundation

/// Deterministic, read-only UI QA: real search over a year with weekends,
/// bundled 2026 holidays and explicit 2027 predictions. Never saves a roster
/// or balance. Launch with -ios.native.qaRoute leave -ios.native.qaLeavePlanner YES.
nonisolated enum DebugLeavePlanner {
    static func proposals(restDays: Int? = nil, region: String = "CN") -> [LeavePlanProposal] {
        let work = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let rest = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let types = [(work, ShiftType.Kind.work), (rest, ShiftType.Kind.rest)].map { id, kind in
            ShiftType(id: id, name: kind == .work ? "Office" : "Rest", kind: kind,
                      startMinutes: 540, endMinutes: 1020, breakEnabled: false,
                      breakStartMinutes: 720, breakDurationMinutes: 0, colorHex: "#FF7A00", isArchived: false)
        }
        let plan = ExtendedSchedulePlan(
            shiftTypes: types,
            rule: ShiftCycleRule(preset: .weekly, anchorDayKey: "2026-09-21",
                                 days: [work, work, work, work, work, rest, rest]),
            handSetDays: [:], holidayRegionIdentifier: region
        )
        let configuration = ScheduleHoursConfiguration(
            startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: NativeWorkSchedule(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                                        singleWeekendWorkday: nil, rotationAnchorMs: nil,
                                        rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: nil, breakDurationMinutes: 0, extendedSchedule: plan
        )
        let first = CivilZone.dayNumber(year: 2026, month: 9, day: 21)
        let last = first + 364
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let days = LeavePlannerSchedule.days(configuration: configuration, range: first...last, timeZone: zone)
        return LeavePlanner.proposals(days: days, query: .init(
            goal: restDays.map { .restAtLeast(days: $0) } ?? .leaveAtMost(halfDays: 10), fromDayNumber: first, throughDayNumber: last,
            nowMs: CivilZone(timeZone: zone).utcMs(dayNumber: first, Clock(hour: 0, minute: 0)),
            budgets: [.init(id: UUID(), availableHalfDays: 10, validFromDayNumber: nil, validThroughDayNumber: nil)]
        ))
    }
}
#endif
