import Foundation

/// Presentation only: every original proposal remains selectable and opens
/// its own details/budget allocation. No search results are discarded here.
nonisolated struct LeavePlanGroup: Identifiable, Equatable, Sendable {
    nonisolated enum Category: String, CaseIterable, Sendable {
        case holiday, regular
        var titleKey: String {
            switch self {
            case .holiday: "leaveHolidayPlans"
            case .regular: "leaveRegularPlans"
            }
        }
    }

    let id: Int
    let category: Category
    var proposalIndices: [Int]

    private struct Pattern: Hashable {
        let restDays: Int
        let halfDays: Int
        let earlyHalfDays: Int
        let lateHalfDays: Int
    }

    static func make(from proposals: [LeavePlanProposal]) -> [Self] {
        var groups: [Self] = []
        var regular: [Pattern: Int] = [:]
        for (index, proposal) in proposals.enumerated() {
            // Only a holiday which actually provides rest counts; a public
            // holiday the user works is not a free day in the planner either.
            if proposal.dayKinds.contains(.holiday) {
                groups.append(Self(id: index, category: .holiday, proposalIndices: [index]))
                continue
            }
            let pattern = Pattern(
                restDays: proposal.fullRestDays, halfDays: proposal.costHalfDays,
                earlyHalfDays: proposal.items.filter { $0.role == .earlyDeparture }.reduce(0) { $0 + $1.portion.halfDays },
                lateHalfDays: proposal.items.filter { $0.role == .lateReturn }.reduce(0) { $0 + $1.portion.halfDays }
            )
            if let group = regular[pattern] {
                groups[group].proposalIndices.append(index)
            } else {
                regular[pattern] = groups.count
                groups.append(Self(id: index, category: .regular, proposalIndices: [index]))
            }
        }
        // Keep groups in recommendation order, dates within each group chronological.
        for index in groups.indices {
            groups[index].proposalIndices.sort {
                let lhs = proposals[$0], rhs = proposals[$1]
                return lhs.firstRestDayNumber == rhs.firstRestDayNumber
                    ? $0 < $1 : lhs.firstRestDayNumber < rhs.firstRestDayNumber
            }
        }
        return groups
    }
}
