import Foundation

enum FocusEndReason: String, Codable, Sendable {
    case completed
    case stoppedByUser
    case stoppedAtBoundary
    case abandoned
    /// A second device won the single active timer election.  Kept as history
    /// rather than deleting the losing session so CloudKit can converge.
    case supersededBySync
}

enum FocusSessionKind: String, Codable, Sendable {
    case focus
    case shortBreak
    case longBreak
}

/// Timer preferences. Sessions persist their planned end, so a synced change
/// only affects the next timer and never rewrites time already in flight.
struct FocusTimerSettings: Codable, Equatable, Sendable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var longBreakEvery = 4

    static let `default` = FocusTimerSettings()

    var normalized: FocusTimerSettings {
        .init(
            focusMinutes: min(60, max(10, focusMinutes)),
            shortBreakMinutes: min(15, max(1, shortBreakMinutes)),
            longBreakMinutes: min(30, max(5, longBreakMinutes)),
            longBreakEvery: min(6, max(2, longBreakEvery))
        )
    }
}

enum FocusNextAction: Equatable, Sendable {
    case startShortBreak
    case startLongBreak
    case startNextFocus
    case none
}

enum FocusNotificationIssue: Equatable, Sendable {
    case permissionDenied
    case schedulingFailed
}

/// Why a task's Start control is enabled, or what to show instead.
enum FocusStartAvailability: Equatable, Sendable {
    case ready
    case running
    case blockedByOther
    case completed
    case noRoom
    case notYetAvailable(Date)
}

enum FocusTaskIcon: String, CaseIterable, Codable, Identifiable, Sendable {
    case focus
    case work
    case code
    case study
    case writing
    case communication
    case meeting
    case idea

    var id: String { rawValue }

    var systemName: String {
        switch self {
        case .focus: "timer"
        case .work: "briefcase.fill"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .study: "book.fill"
        case .writing: "pencil.line"
        case .communication: "envelope.fill"
        case .meeting: "person.2.fill"
        case .idea: "lightbulb.fill"
        }
    }

    var titleKey: String { "focusIcon\(rawValue.capitalized)" }
}

struct FocusTask: Equatable, Sendable, Identifiable {
    static let schemaVersion = 2

    var id: UUID
    var createdAt: Date
    var plannedForDate: Date?
    /// Exact slot selected in the add sheet. Optional so archives written
    /// before this field existed remain valid.
    var scheduledStartAt: Date?
    var title: String
    var estimatedPomodoros: Int
    var icon: FocusTaskIcon = .focus
    var isFavorite = false
    var completedAt: Date?
    /// Soft deletion keeps old sessions intelligible and synchronizes the
    /// removal through the same CloudKit conflict rules as any other edit.
    var deletedAt: Date? = nil
    var sortIndex: Int
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID
    /// Present only for tasks materialized from a template. User-created tasks
    /// must keep their own estimate when plan blocks are changed.
    var templateID: UUID? = nil
    var templateTaskKey: UUID? = nil
}

enum FocusPlanBlockKind: String, Codable, Sendable {
    case task
    case breakTime
}

struct FocusWorkBlock: Equatable, Sendable, Identifiable {
    var id: Int64 { startAtMs }
    var index: Int
    var start: Date
    var end: Date
    /// A planning timeline contains both work and recovery phases. Defaulting
    /// to task keeps persisted v1 plan rows and existing call sites readable.
    var kind: FocusPlanBlockKind = .task
    var breakKind: FocusSessionKind? = nil
    var startAtMs: Int64 { Int64(start.timeIntervalSince1970 * 1_000) }
    var durationMinutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
}

struct FocusPlanAssignment: Codable, Equatable, Sendable, Identifiable {
    var id: Int64 { blockStartAtMs }
    var blockStartAtMs: Int64
    var kind: FocusPlanBlockKind
    var taskID: UUID?
    var taskTitle: String?
    var taskIcon: FocusTaskIcon?
}

struct FocusDayPlan: Codable, Equatable, Sendable {
    var dayKey: String
    var shiftStartAtMs: Int64
    var assignments: [FocusPlanAssignment]
    var appliedTemplateID: UUID?
}

struct FocusTemplateSlot: Codable, Equatable, Sendable, Identifiable {
    var id: Int { blockIndex }
    var blockIndex: Int
    var kind: FocusPlanBlockKind
    /// Slots with the same key become one task when a template is applied.
    var taskKey: UUID?
    var taskTitle: String?
    var taskIcon: FocusTaskIcon?
}

struct FocusTemplate: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var slots: [FocusTemplateSlot]
    var createdAt: Date
    var updatedAt: Date
}

struct FocusPlanningState: Codable, Equatable, Sendable {
    var plans: [String: FocusDayPlan] = [:]
    var templates: [FocusTemplate] = []
    var defaultTemplateID: UUID?
    var autoAppliedDayKeys: Set<String> = []
}

/// The single durable identity for planning preferences. Keeping the complete
/// planning graph atomic lets CloudKit merge templates by UUID and plans by
/// civil day without ever exposing implementation rows to the user.
struct FocusPlanningConfiguration: Equatable, Sendable {
    static let logicalKey = "focus-planning"

    var planning: FocusPlanningState
    var timerSettings: FocusTimerSettings
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID

    var hasUserContent: Bool {
        !planning.plans.isEmpty
            || !planning.templates.isEmpty
            || planning.defaultTemplateID != nil
            || !planning.autoAppliedDayKeys.isEmpty
            || timerSettings.normalized != .default
    }
}

struct FocusSession: Equatable, Sendable, Identifiable {
    static let schemaVersion = 2

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
    var kind: FocusSessionKind = .focus
    /// IANA zone retained with the session, not inferred from the viewer's
    /// current location after travel.
    var timeZoneIdentifier: String = TimeZone.current.identifier
    /// User-visible shift/day anchor derived from `startedAt` in that zone.
    var anchorDayKey: String? = nil
    var actualDurationSeconds: Int? = nil
    /// Persisted at start to make restoration independent of today's shift.
    var plannedEndReason: FocusEndReason? = nil
}

enum FocusTaskOrder {
    static func sorted(_ tasks: [FocusTask]) -> [FocusTask] {
        tasks.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
