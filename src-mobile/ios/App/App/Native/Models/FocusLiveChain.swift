import Foundation

/// One stretch of what the Live Activity will show, resolved up front.
struct FocusChainLeg: Equatable, Sendable {
    /// Time the user is already spending, or a block the plan holds that
    /// nobody has started. The second kind must not be drawn as a countdown —
    /// nothing is running, and a ticking timer would be a claim that it is.
    enum Role: Equatable, Sendable {
        case running
        case upNext
    }

    var kind: FocusSessionKind
    var role: Role
    var start: Date
    var end: Date
    var taskTitle: String?
    var icon: FocusTaskIcon?
    /// Position of this block inside its own task, 1-based.
    var pomodoroIndex: Int?
    var pomodoroTotal: Int?
    /// When the task's last remaining block is expected to end, or `nil` when
    /// the rest of the shift cannot hold it.
    var taskFinishAt: Date?
}

/// The grid arithmetic behind the chain, kept out of `OffWorkStore` so both
/// answers can be exercised against a plain list of blocks.
enum FocusLiveChain {
    /// Blocks a task will still occupy: the ones the plan already gives it,
    /// plus free blocks for an estimate that was never placed anywhere.
    ///
    /// Free blocks count because an unplaced estimate is still work the user
    /// intends to do, and the next thing that starts will land in one. Blocks
    /// belonging to another task are skipped rather than ending the walk — a
    /// task can legitimately resume after someone else's block.
    static func projectedBlocks(
        taskID: UUID,
        remaining: Int,
        blocks: [FocusDayCanvasModel.Block],
        fromMs: Int64
    ) -> [FocusDayCanvasModel.Block] {
        guard remaining > 0 else { return [] }
        var result: [FocusDayCanvasModel.Block] = []
        for block in blocks where block.kind == .task && !block.isUserBreak && block.startAtMs >= fromMs {
            guard result.count < remaining else { break }
            if block.taskID == taskID || !block.hasAssignment { result.append(block) }
        }
        return result
    }

    /// The next block the plan has a real task in, after the phase running now.
    static func nextPlannedBlock(
        blocks: [FocusDayCanvasModel.Block],
        fromMs: Int64
    ) -> FocusDayCanvasModel.Block? {
        blocks.first {
            $0.kind == .task && !$0.isUserBreak && $0.taskID != nil && $0.startAtMs >= fromMs
        }
    }
}

extension OffWorkStore {
    /// Everything the Live Activity should walk through on its own: the phase
    /// that is running, the recovery it earns, and the block queued behind it.
    ///
    /// The chain stops at the first thing the plan does not know about, which
    /// is exactly when the activity should retire rather than sit on the Lock
    /// Screen repeating that a block finished half an hour ago.
    func focusChain(for session: FocusSession, at date: Date = .now) -> [FocusChainLeg] {
        let canvas = focusDayCanvas(at: date)
        let task = session.taskID.flatMap { id in
            records.state.focusTasks.first(where: { $0.id == id })
        }
        var cursor = session.plannedEndAt
        var legs = [runningLeg(session, task: task, blocks: canvas.blocks)]

        if session.kind == .focus, session.taskID != nil, session.plannedEndReason == .completed {
            let breakKind = nextFocusBreakKind(after: session)
            if let breakEnd = plannedFocusBreakEnd(kind: breakKind, at: session.plannedEndAt) {
                legs.append(FocusChainLeg(
                    kind: breakKind,
                    role: .running,
                    start: session.plannedEndAt,
                    end: breakEnd
                ))
                cursor = breakEnd
            }
        }

        let cursorMs = Int64(cursor.timeIntervalSince1970 * 1_000)
        if let next = FocusLiveChain.nextPlannedBlock(blocks: canvas.blocks, fromMs: cursorMs),
           let nextTask = next.taskID.flatMap({ id in
               records.state.focusTasks.first(where: { $0.id == id })
           }),
           nextTask.completedAt == nil {
            // The running block has not been recorded yet, so a task that
            // continues into this one has to count it here or the queued block
            // would repeat the number the running one is already showing.
            let done = completedFocusBlocks(for: nextTask)
                + (session.kind == .focus && nextTask.id == session.taskID ? 1 : 0)
            legs.append(FocusChainLeg(
                kind: .focus,
                role: .upNext,
                start: Date(timeIntervalSince1970: Double(next.startAtMs) / 1_000),
                end: Date(timeIntervalSince1970: Double(next.endAtMs) / 1_000),
                taskTitle: next.taskTitle ?? nextTask.title,
                icon: next.taskIcon ?? nextTask.icon,
                pomodoroIndex: done + 1,
                pomodoroTotal: max(done + 1, max(1, nextTask.estimatedPomodoros))
            ))
        }
        return legs
    }

    /// Whether the Lock Screen's plus may act right now.
    ///
    /// Where an extra block *goes* is the planner's answer, not a second one:
    /// this asks `focusContinuationTarget`, the same resolver the in-app
    /// continuation writes through. Two rules would let the greyed-out state
    /// and the write disagree about the same tap.
    func canAddFocusPomodoro(at date: Date = .now) -> Bool {
        guard let taskID = lockScreenContinuationTaskID(at: date) else { return false }
        guard case .success = focusContinuationTarget(taskID: taskID, at: date) else { return false }
        return true
    }

    /// Gives the running task one more block in today's plan.
    @discardableResult
    func addFocusPomodoroToRunningTask(at date: Date = .now) -> Bool {
        guard let taskID = lockScreenContinuationTaskID(at: date) else { return false }
        guard case .success = addOneFocusBlock(taskID: taskID, at: date) else { return false }
        return true
    }

    /// The task the Lock Screen button is offered for.
    ///
    /// Narrower than `focusContinuationTaskID`, which the in-app control uses
    /// and which deliberately stays available through the break. A card is a
    /// cached image: it can still show a focus block minutes after that block
    /// ended, and a button that acts from a picture of a finished block is the
    /// one the review caught adding a pomodoro to an expired session.
    private func lockScreenContinuationTaskID(at date: Date) -> UUID? {
        guard plus.isAuthorized, let session = activeFocusSession(), session.kind == .focus,
              session.startedAt <= date, date < session.plannedEndAt
        else { return nil }
        return session.taskID
    }

    private func runningLeg(
        _ session: FocusSession,
        task: FocusTask?,
        blocks: [FocusDayCanvasModel.Block]
    ) -> FocusChainLeg {
        guard session.kind == .focus, let task else {
            return FocusChainLeg(
                kind: session.kind,
                role: .running,
                start: session.startedAt,
                end: session.plannedEndAt
            )
        }
        let completed = completedFocusBlocks(for: task)
        let index = completed + 1
        let total = max(index, max(1, task.estimatedPomodoros))
        let remaining = total - index
        let projected = FocusLiveChain.projectedBlocks(
            taskID: task.id,
            remaining: remaining,
            blocks: blocks,
            fromMs: Int64(session.plannedEndAt.timeIntervalSince1970 * 1_000)
        )
        // Only a projection that placed every remaining block can name a time.
        // Anything shorter means the shift runs out first, and the honest
        // answer there is to say nothing rather than print an early hour.
        let finish: Date? = remaining == 0
            ? session.plannedEndAt
            : (projected.count == remaining
                ? projected.last.map { Date(timeIntervalSince1970: Double($0.endAtMs) / 1_000) }
                : nil)
        return FocusChainLeg(
            kind: .focus,
            role: .running,
            start: session.startedAt,
            end: session.plannedEndAt,
            taskTitle: task.title,
            icon: task.icon,
            pomodoroIndex: index,
            pomodoroTotal: total,
            taskFinishAt: finish
        )
    }
}
