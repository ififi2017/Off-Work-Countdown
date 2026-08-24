import ActivityKit
import Foundation

/// Salary-free payload shared verbatim by the app and Widget extension.
struct OffWorkActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let endAtMs: Int64
        let progress: Double
        let phase: String
        let locale: String
        let appTitle: String
        let caption: String
        let completedCaption: String
        /// Shown under the big "off work" line. Must differ from
        /// completedCaption or Control Center prints the same sentence twice.
        let completedNote: String
    }

    let shiftStartAtMs: Int64
    let plannedEndAtMs: Int64
}
