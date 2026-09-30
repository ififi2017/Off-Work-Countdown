import Foundation
import Testing
@testable import App

@Suite("Shift type date coverage")
struct ShiftTypeDateCoverageTests {
    @Test func boundsCountScheduledDaysAndKeepGaps() {
        let work = ShiftType(id: UUID(), name: "Work", kind: .work,
                             startMinutes: 540, endMinutes: 1_020,
                             breakEnabled: false, breakStartMinutes: 720,
                             breakDurationMinutes: 60, colorHex: "#FF9500", isArchived: false)
        let rest = ShiftType(id: UUID(), name: "Rest", kind: .rest,
                             startMinutes: 540, endMinutes: 1_020,
                             breakEnabled: false, breakStartMinutes: 720,
                             breakDurationMinutes: 60, colorHex: "#8E8E93", isArchived: false)
        let plan = ExtendedSchedulePlan(shiftTypes: [work, rest],
                                       rule: ShiftCycleRule(preset: .rotation, anchorDayKey: "2026-10-01", days: [work.id, rest.id]),
                                       handSetDays: [:], holidayRegionIdentifier: "")
        let coverage = ShiftTypeScheduleOverview.coverage(plan: plan, fromDayKey: "2026-10-01")
        #expect(coverage[work.id] == ShiftTypeDateCoverage(firstDayKey: "2026-10-01", lastDayKey: "2027-09-30", dayCount: 183))
        #expect(coverage[rest.id]?.dayCount == 182)
        #expect(coverage[rest.id]?.firstDayKey == "2026-10-02")
    }

    @Test func emptyPlanAndInvalidDatesHaveNoCoverage() {
        let plan = ExtendedSchedulePlan(shiftTypes: [], rule: nil, handSetDays: [:], holidayRegionIdentifier: "")
        #expect(ShiftTypeScheduleOverview.coverage(plan: plan, fromDayKey: "2026-10-01").isEmpty)
        #expect(ShiftTypeScheduleOverview.coverage(plan: plan, fromDayKey: "2026-02-30").isEmpty)
    }
}
