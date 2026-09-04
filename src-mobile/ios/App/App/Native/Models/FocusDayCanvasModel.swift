import Foundation

/// Everything the focus canvas draws, resolved once so no view has to do
/// arithmetic on a shift.
///
/// 013 established the rule for the records day canvas and it holds here:
/// crossing intervals, clamping to boundaries and turning milliseconds into
/// points are model work. A view that computes its own geometry ends up
/// disagreeing with the numbers printed beside it.
struct FocusDayCanvasModel: Equatable, Sendable {
    /// Where the shift's own clock starts and stops. A shift that crosses
    /// midnight stays one continuous range — the canvas asks "does this shift
    /// hold what I want to do", which is not a question about a civil day.
    var shiftStartAtMs: Int64
    var shiftEndAtMs: Int64
    /// The day the plan is filed under, so a caller never re-derives it.
    var dayKey: String
    /// True when no shift is running and the canvas is showing the next one.
    /// The question survives clock-off; the answer just moves to another day.
    var isNextShift: Bool
    /// Absent when the clock sits outside the drawn shift, which is exactly
    /// when a "now" line would be a lie.
    var nowAtMs: Int64?
    var blocks: [Block]
    /// Stretches inside the shift that hold no block: a lunch gap between
    /// segments, or the leftover at the end of one that cannot fit a block.
    var gaps: [Gap]
    var tasks: [TaskRow]
    /// Tasks that do not fit the rest of the shift. A footnote, not a verdict.
    var overflow: [TaskRow]
    /// Points per hour for a proportional band, derived from the cadence.
    var pointsPerHour: Double
    /// Rendered without any real value behind it when Plus is not active.
    var isLocked: Bool

    struct Block: Equatable, Sendable, Identifiable {
        enum State: Equatable, Sendable {
            case past
            /// The clock is inside this block, whether or not a session runs.
            case current
            case future
        }

        var id: Int64 { startAtMs }
        var index: Int
        var startAtMs: Int64
        var endAtMs: Int64
        var kind: FocusPlanBlockKind
        var state: State
        var taskID: UUID?
        var taskTitle: String?
        var taskIcon: FocusTaskIcon?

        var durationMs: Int64 { max(0, endAtMs - startAtMs) }
        var isAssigned: Bool { taskID != nil }

        /// Only a future work block accepts an edit.
        ///
        /// Break blocks are not editable and never were: both `assignFocusBlock`
        /// and `assignFocusBreak` reject anything that is not a task block. The
        /// planning grid used to draw them as buttons anyway, so tapping one
        /// played a selection haptic, dismissed the sheet and changed nothing —
        /// and its "clear this slot" row still detached the day from its
        /// template. Not offering the target is the fix.
        var isEditable: Bool { kind == .task && state != .past }
    }

    struct Gap: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            /// Lunch, or any stretch between two work segments.
            case betweenSegments
            /// The end of a segment that cannot hold one more block.
            case tail
        }

        var id: Int64 { startAtMs }
        var startAtMs: Int64
        var endAtMs: Int64
        var kind: Kind
        var durationMinutes: Int { max(0, Int((endAtMs - startAtMs) / 60_000)) }
    }

    /// One line of the explanation under the band.
    ///
    /// Progress reads "done of scheduled", not "done of estimated". Under
    /// block-first the schedule is what the user just drew, while
    /// `estimatedPomodoros` stays what they intended — and for a manual task
    /// the two are deliberately allowed to differ.
    struct TaskRow: Equatable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var icon: FocusTaskIcon
        var completedBlocks: Int
        var assignedBlocks: Int
        var estimatedBlocks: Int
        var isRunning: Bool
        var isDone: Bool
        var isScheduled: Bool { assignedBlocks > 0 }
    }

    static let empty = FocusDayCanvasModel(
        shiftStartAtMs: 0,
        shiftEndAtMs: 0,
        dayKey: "",
        isNextShift: false,
        nowAtMs: nil,
        blocks: [],
        gaps: [],
        tasks: [],
        overflow: [],
        pointsPerHour: FocusDayCanvasModel.pointsPerHour(focusMinutes: 25),
        isLocked: false
    )

    var isEmpty: Bool { blocks.isEmpty && gaps.isEmpty }
    var durationMs: Int64 { max(0, shiftEndAtMs - shiftStartAtMs) }

    /// The band's density, chosen so one focus block always clears the 44 pt
    /// minimum hit target.
    ///
    /// The cadence is configurable from 10 to 60 minutes, so a fixed
    /// points-per-hour fails at both ends: short blocks become untappable,
    /// long ones flatten the hour ruler. The floor keeps the ruler legible
    /// once blocks are long enough to clear the target on their own.
    static func pointsPerHour(focusMinutes: Int) -> Double {
        max(96, 44 * 60 / Double(max(1, focusMinutes)))
    }

    /// Offset in points from the top of the band.
    func offset(ofMs ms: Int64) -> Double {
        Double(ms - shiftStartAtMs) / 3_600_000 * pointsPerHour
    }

    /// Height in points of a stretch, drawn strictly to proportion.
    ///
    /// Deliberately without a minimum: a five-minute break really is a fifth
    /// of a focus block, and a one-minute one really is a hairline. Callers
    /// decide whether a label fits, they do not inflate the shape to make
    /// room for one.
    func height(ofMs ms: Int64) -> Double {
        max(0, Double(ms) / 3_600_000 * pointsPerHour)
    }

    var totalHeight: Double { height(ofMs: durationMs) }

    /// The first future work block with nothing in it — where "put it in the
    /// next empty block" lands.
    var nextEmptyBlock: Block? {
        blocks.first { $0.kind == .task && $0.state != .past && !$0.isAssigned }
    }

    var currentBlock: Block? {
        blocks.first { $0.state == .current }
    }
}
