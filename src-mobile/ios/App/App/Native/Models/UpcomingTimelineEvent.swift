import Foundation

struct UpcomingTimelineEvent: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case shiftStart
        case lunchStart
        case lunchEnd
        case health
        case milestone
        case shiftEnd
    }

    let id: String
    let kind: Kind
    let date: Date
    let title: String
    let detail: String
}
