import Foundation
import Testing
@testable import App

@Suite("Leave plan grouping")
struct LeavePlanGroupTests {
    @Test("A rolling year keeps every date but consolidates ordinary weekends")
    func rollingYear() throws {
        let proposals = DebugLeavePlanner.proposals()
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
