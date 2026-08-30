import Foundation

enum FocusEndReason: String, Codable, Sendable {
    case completed
    case stoppedByUser
    case stoppedAtBoundary
    case abandoned
}

struct FocusTask: Equatable, Sendable, Identifiable {
    static let schemaVersion = 1

    var id: UUID
    var createdAt: Date
    var plannedForDate: Date?
    var title: String
    var estimatedPomodoros: Int
    var completedAt: Date?
    var sortIndex: Int
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID
}

struct FocusSession: Equatable, Sendable, Identifiable {
    static let schemaVersion = 1

    var id: UUID
    var taskID: UUID?
    var shiftAnchorDate: Date
    var startedAt: Date
    var plannedEndAt: Date
    var endedAt: Date?
    var endReason: FocusEndReason?
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID
}

enum FocusTaskOrder {
    static func sorted(_ tasks: [FocusTask]) -> [FocusTask] {
        tasks.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
