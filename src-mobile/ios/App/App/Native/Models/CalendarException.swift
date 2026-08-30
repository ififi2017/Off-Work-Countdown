import Foundation

/// Whether a calendar exception makes the day rest or work.
enum CalendarEffect: String, Codable, Sendable {
    case rest
    case work
}

enum CalendarExceptionOrigin: String, Codable, Sendable {
    case user
    case bundled
}

/// A holiday or makeup day. Answers "does this day count as a workday?"
/// — not how the hours look. Value type only — SwiftData lands later.
struct CalendarException: Equatable, Sendable {
    static let schemaVersion = 1

    /// Logical identity: `"<date>#<origin>"`, e.g. `2026-08-26#user`.
    var dayKey: String
    var date: Date
    var effect: CalendarEffect
    var origin: CalendarExceptionOrigin
    var isCleared: Bool
    var regionIdentifier: String?
    var datasetVersion: String?
    var label: String?
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID
    /// Civil day this row was recorded in. Travel does not rewrite it.
    var timeZoneIdentifier: String = TimeZone.current.identifier

    static func dayKey(dateKey: String, origin: CalendarExceptionOrigin) -> String {
        "\(dateKey)#\(origin.rawValue)"
    }

    func matches(dateKey: String) -> Bool {
        dayKey.hasPrefix(dateKey + "#")
    }
}
