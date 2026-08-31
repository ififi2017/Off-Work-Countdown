import Foundation

struct UpcomingTimelineEvent: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case shiftStart
        case lunchStart
        case lunchEnd
        case health
        case focus
        case focusBreak
        case milestone
        case shiftEnd
    }

    let id: String
    let kind: Kind
    let date: Date
    let title: String
    let detail: String
    let symbolName: String?

    init(
        id: String,
        kind: Kind,
        date: Date,
        title: String,
        detail: String,
        symbolName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
    }
}
