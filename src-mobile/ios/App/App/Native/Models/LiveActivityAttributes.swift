import ActivityKit
import Foundation

/// Salary-free payload shared verbatim by the app and Widget extension.
struct OffWorkActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        struct Segment: Codable, Hashable, Sendable {
            let startAtMs: Int64
            let endAtMs: Int64
        }

        let endAtMs: Int64
        let progress: Double
        /// Absolute effective-work intervals prepared by CountdownRules. The
        /// extension may project inside them, but never reinterprets lunch or
        /// overtime rules.
        let segments: [Segment]
        let phase: String
        let locale: String
        let appTitle: String
        let caption: String
        let completedCaption: String
        /// Shown under the big "off work" line. Must differ from
        /// completedCaption or Control Center prints the same sentence twice.
        let completedNote: String
        /// `nil` means the payload was written by a pre-focus release and is
        /// therefore a work countdown. Optional fields keep old activities
        /// decodable during an in-place app update.
        var surface: String? = nil
        /// Focus and break activities supply their own concise phase label.
        var timerLabel: String? = nil
        /// The deep link is data rather than an extension-side policy so work
        /// and focus can return users to their respective primary surface.
        var destination: String? = nil
        /// What the block is for. The Dynamic Island had no way to tell a
        /// focus activity from a work countdown — same mark, same countdown —
        /// and never said what was being worked on.
        var taskTitle: String? = nil
        /// SF Symbol name. In the minimal presentation this is the only glyph
        /// there is room for, so it is what distinguishes the two activities.
        var taskIcon: String? = nil
        /// What happens when this block ends. A pomodoro activity that cannot
        /// say "then a 15 minute break" is withholding the one thing the
        /// cadence knows and the user does not.
        var nextLabel: String? = nil
        /// Time left in the shift itself, phrased by the app.
        ///
        /// Only one activity may be live, so starting a block ends the work
        /// countdown. Carrying this line means the focus activity can answer
        /// both scales instead of displacing one of them.
        var shiftRemainingLabel: String? = nil

        func projectedProgress(atMs nowMs: Int64) -> Double {
            let duration = segments.reduce(Int64(0)) { total, segment in
                total + max(0, segment.endAtMs - segment.startAtMs)
            }
            guard duration > 0 else { return min(100, max(0, progress)) }
            let elapsed = segments.reduce(Int64(0)) { total, segment in
                let segmentDuration = max(0, segment.endAtMs - segment.startAtMs)
                let segmentElapsed = min(
                    segmentDuration,
                    max(0, nowMs - segment.startAtMs)
                )
                return total + segmentElapsed
            }
            let projected = Double(elapsed) / Double(duration) * 100
            return min(100, max(progress, projected))
        }
    }

    let shiftStartAtMs: Int64
    let plannedEndAtMs: Int64
}
