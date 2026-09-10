import ActivityKit
import Foundation

/// Salary-free payload shared verbatim by the app and Widget extension.
nonisolated struct OffWorkActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        struct Segment: Codable, Hashable, Sendable {
            let startAtMs: Int64
            let endAtMs: Int64
        }

        /// One stretch of the chain the activity walks on its own.
        ///
        /// A phone is asleep for almost all of a pomodoro, so nothing can tell
        /// the activity that the block ended at the moment it ends. The whole
        /// chain therefore travels with the payload as absolute times and
        /// finished text, and the extension picks the leg the clock is in.
        struct Leg: Codable, Hashable, Sendable {
            let startAtMs: Int64
            let endAtMs: Int64
            /// `LiveActivitySurface` raw value, so the leg carries its own tint
            /// and glyph rather than inheriting the one the payload opened with.
            let surface: String
            /// Concise phase name: "Focus", "Short break", "Up next".
            let label: String
            let title: String?
            let icon: String
            /// "Pomodoro 2 of 4", already localized and pluralized.
            let detail: String?
            /// "Done by 11:30" — when this task's last block is expected to end.
            let finishNote: String?
            /// What follows this leg. Written per leg because the extension
            /// cannot compose a sentence in the user's language.
            let nextNote: String?
            /// A block the plan holds that nobody has started. Shown as a
            /// heading and a start time, never as a running countdown.
            let isPreview: Bool
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
        /// Retained for decoding activities from older app versions; new
        /// views deliberately omit this frozen duration.
        var shiftRemainingLabel: String? = nil
        /// Absolute clock-off from the shared rules snapshot, with no salary.
        var shiftEndAtMs: Int64? = nil
        var shiftEndLabel: String? = nil
        /// The running phase and everything the plan already knows follows it.
        /// `nil` means a payload written before the chain existed; the views
        /// fall back to the single `endAtMs` countdown those carry.
        var legs: [Leg]? = nil
        /// Shown once the last leg has passed, in place of the countdown.
        var chainDoneCaption: String? = nil
        /// Accessibility label for the add-a-pomodoro button. `nil` hides it,
        /// which is every activity that is not a running focus block.
        var addPomodoroLabel: String? = nil
        /// False when every block left in the shift already belongs to another
        /// task, so the button is offered but visibly cannot act.
        var addPomodoroEnabled = false
        var stopFocusLabel: String? = nil
        var scheduledSessionID: String? = nil
        /// When this activity was scheduled to appear. The work countdown is
        /// published only for the last 5, 15 or 30 minutes of a shift, so its
        /// meters measure that stretch rather than the whole day — see
        /// `activityWindowSegments`. `nil` on a focus payload, which is
        /// already its own block, and on payloads written before the field
        /// existed, which keep measuring the whole shift.
        var displayStartAtMs: Int64? = nil

        /// End of the chain, which is what "this activity is finished" means
        /// once a focus block is followed by its break and the next block.
        var chainEndAtMs: Int64 { legs?.last?.endAtMs ?? endAtMs }

        /// The leg the clock is in, or `nil` past the end of the chain.
        func leg(atMs nowMs: Int64) -> Leg? {
            legs?.first { nowMs < $0.endAtMs }
        }

        /// A cached focus payload may redraw as a break or an unstarted preview.
        func showsAddPomodoro(atMs nowMs: Int64) -> Bool {
            guard addPomodoroLabel != nil, phase != "complete", nowMs < endAtMs else { return false }
            if let leg = leg(atMs: nowMs) {
                return leg.surface == "focus" && !leg.isPreview && nowMs >= leg.startAtMs
            }
            return surface == "focus"
        }

        /// The stretch this activity is actually on screen for.
        ///
        /// The work countdown is published only for the last 5, 15 or 30
        /// minutes of a shift, so a meter measured against the whole day
        /// arrives 97% full and crawls the last three points. It looks broken,
        /// and it spends the card's only bar saying something the digits above
        /// it already said better. The meters therefore span the activity's
        /// own life: from the moment it was scheduled to appear to the end it
        /// is counting to. Overtime needs no special case — the rules bundle
        /// already extends the last segment when it is added.
        ///
        /// Lunch still does not count, because these are the same effective
        /// segments, only clipped. A payload with no window keeps the whole
        /// shift, which is what focus legs and older payloads want.
        var windowSegments: [Segment] {
            guard let displayStartAtMs else { return segments }
            let clipped = segments.compactMap { segment -> Segment? in
                let start = max(segment.startAtMs, displayStartAtMs)
                guard start < segment.endAtMs else { return nil }
                return Segment(startAtMs: start, endAtMs: segment.endAtMs)
            }
            return clipped.isEmpty ? segments : clipped
        }

        /// Elapsed effective time across `windowSegments`, as a percentage.
        ///
        /// Unlike `projectedProgress` this does not take the payload's own
        /// `progress` as a floor: that number is the whole shift's, and inside
        /// a fifteen-minute window it would pin the bar at full from the first
        /// frame. Without a window the two agree, so the floor is kept there.
        func windowProgress(atMs nowMs: Int64) -> Double {
            guard displayStartAtMs != nil else { return projectedProgress(atMs: nowMs) }
            let window = windowSegments
            let duration = window.reduce(Int64(0)) { $0 + max(0, $1.endAtMs - $1.startAtMs) }
            guard duration > 0 else { return min(100, max(0, progress)) }
            let elapsed = window.reduce(Int64(0)) { total, segment in
                total + min(
                    max(0, segment.endAtMs - segment.startAtMs),
                    max(0, nowMs - segment.startAtMs)
                )
            }
            return min(100, max(0, Double(elapsed) / Double(duration) * 100))
        }

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
