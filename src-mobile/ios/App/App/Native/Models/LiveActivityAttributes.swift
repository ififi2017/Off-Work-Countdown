import ActivityKit
import Foundation

/// Salary-free payload shared verbatim by the app and Widget extension.
struct OffWorkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endAtMs: Int64
        let progress: Double
        let phase: String
        let locale: String
        let appTitle: String
        let caption: String
        let completedCaption: String
    }

    let shiftStartAtMs: Int64
    let plannedEndAtMs: Int64
}
