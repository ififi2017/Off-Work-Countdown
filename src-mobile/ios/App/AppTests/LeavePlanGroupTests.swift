import Foundation
import Testing
@testable import App

@Suite("Leave plan grouping")
struct LeavePlanGroupTests {
    @Test("Long-break searches can have an empty regular category without losing the holiday results", arguments: [12, 13])
    func emptyRegularCategory(target: Int) {
        let context = DebugLeavePlanner.searchContext(restDays: target)
        let proposals = DebugLeavePlanner.proposals(restDays: target)
        let groups = LeavePlanGroup.make(from: proposals)
        #expect(!groups.isEmpty)
        #expect(context.goal == .restAtLeast(days: target))
        #expect(context.availableHalfDays == 10)
        #expect(groups.allSatisfy { $0.category == .holiday })
        #expect(groups.flatMap(\.proposalIndices).sorted() == Array(proposals.indices))
        #expect(proposals.allSatisfy {
            $0.fullRestDays >= target && $0.costHalfDays <= context.availableHalfDays
            && $0.firstRestDayNumber >= context.fromDayNumber
            && $0.lastRestDayNumber <= context.throughDayNumber
        })
        // A shorter target brings regular dates back under the same balance.
        #expect(LeavePlanGroup.make(from: DebugLeavePlanner.proposals(restDays: 9))
            .contains { $0.category == .regular })
    }

    @Test("A rolling year keeps every date but consolidates ordinary weekends")
    func rollingYear() throws {
        let work = UUID()
        let rest = UUID()
        let types = [(work, ShiftType.Kind.work), (rest, ShiftType.Kind.rest)].map { id, kind in
            ShiftType(id: id, name: kind == .work ? "Office" : "Rest", kind: kind,
                      startMinutes: 540, endMinutes: 1020, breakEnabled: false,
                      breakStartMinutes: 720, breakDurationMinutes: 0, colorHex: "#FF7A00", isArchived: false)
        }
        let plan = ExtendedSchedulePlan(
            shiftTypes: types,
            rule: ShiftCycleRule(preset: .weekly, anchorDayKey: "2026-09-21",
                                 days: [work, work, work, work, work, rest, rest]),
            handSetDays: [:], holidayRegionIdentifier: "CN"
        )
        let configuration = ScheduleHoursConfiguration(
            startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: NativeWorkSchedule(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                                        singleWeekendWorkday: nil, rotationAnchorMs: nil,
                                        rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: nil, breakDurationMinutes: 0, extendedSchedule: plan
        )
        let first = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-09-21"))
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        // Keep mixed exact/predicted caveats independent of official bundle metadata.
        let days = LeavePlannerSchedule.days(
            configuration: configuration, range: first...(first + 364), timeZone: zone,
            holidayEstimation: { year, region in year == 2027 && region == "CN" }
        )
        let proposals = LeavePlanner.proposals(days: days, query: .init(
            goal: .leaveAtMost(halfDays: 10), fromDayNumber: first, throughDayNumber: first + 364,
            nowMs: CivilZone(timeZone: zone).utcMs(dayNumber: first, Clock(hour: 0, minute: 0)),
            budgets: [.init(id: UUID(), availableHalfDays: 10, validFromDayNumber: nil, validThroughDayNumber: nil)]
        ))
        let groups = LeavePlanGroup.make(from: proposals)
        #expect(proposals.count > 200)
        #expect(groups.count < proposals.count / 2)
        #expect(groups.flatMap(\.proposalIndices).sorted() == Array(proposals.indices))
        let regular = groups.filter { $0.category == .regular }
        let holidays = groups.filter { $0.category == .holiday }
        #expect(regular.count < regular.flatMap(\.proposalIndices).count / 2)
        #expect(!regular.isEmpty && !holidays.isEmpty)
        for group in groups {
            let first = proposals[try #require(group.proposalIndices.first)]
            let dates = group.proposalIndices.map { proposals[$0].firstRestDayNumber }
            #expect(dates == dates.sorted())
            for index in group.proposalIndices {
                #expect(proposals[index].dayKinds.contains(.holiday) == (group.category == .holiday))
                #expect(proposals[index].costHalfDays == first.costHalfDays)
                #expect(proposals[index].fullRestDays == first.fullRestDays)
            }
        }
        // Estimates remain date-specific even when exact and estimated dates
        // provide the same benefit. The original proposal is never replaced.
        #expect(regular.contains { group in
            let caveats = group.proposalIndices.map { proposals[$0].caveats.isEmpty }
            return caveats.contains(true) && caveats.contains(false)
        })
        for key in ["2026-10-17", "2026-10-24", "2026-11-07"] {
            let index = try #require(proposals.firstIndex { $0.firstRestDayKey == key && $0.fullRestDays == 9 })
            #expect(regular.contains { $0.proposalIndices.contains(index) })
        }
    }

    @Test("Early departure and late return remain distinct options")
    func edgeHalves() {
        func proposal(role: LeavePlanItem.Role, portion: LeavePortion = .secondHalf) -> LeavePlanProposal {
            LeavePlanProposal(firstRestDayNumber: 100, lastRestDayNumber: 106,
                              firstRestDayKey: "", lastRestDayKey: "",
                              items: [.init(dayNumber: role == .earlyDeparture ? 99 : 107, dayKey: "",
                                            portion: portion, segments: [], uses: [], role: role)],
                              uses: [], lastShiftEndAtMs: nil, nextShiftStartAtMs: nil,
                              dayKinds: Array(repeating: .rest, count: 7), caveats: [])
        }
        let groups = LeavePlanGroup.make(from: [proposal(role: .earlyDeparture), proposal(role: .lateReturn),
                                                proposal(role: .earlyDeparture), proposal(role: .bridge)])
        #expect(groups.map(\.proposalIndices) == [[0, 2], [1], [3]])
        #expect(LeavePlanGroup.make(from: []).isEmpty)
    }
}
