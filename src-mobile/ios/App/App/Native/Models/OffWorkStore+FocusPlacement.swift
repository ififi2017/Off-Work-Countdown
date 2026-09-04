import Foundation

/// What happened when the canvas tried to put something in a block.
///
/// Every one of these used to be a silent `return`: the favourite chip
/// duplicated a task somewhere off-screen, and assigning without Plus did
/// nothing at all while still playing a selection haptic. A caller that can
/// tell the cases apart can say which one it is.
enum FocusPlacementResult: Equatable, Sendable {
    /// Landed in a block. Carries the key so the canvas can scroll to it and
    /// select it — the change should appear where it happened.
    case placed(taskID: UUID, blockStartAtMs: Int64)
    /// The shift had no empty block left, so the task exists but is unplaced.
    case addedUnscheduled(taskID: UUID)
    case noShift
    case locked
}

extension OffWorkStore {
    /// One tap on a favourite: make today's task from it and put it in the
    /// next empty block.
    ///
    /// Deliberately one action and one undo unit. Splitting it into "add" and
    /// "assign" is what made the old chip feel inert — it copied a task into a
    /// list further down the screen and stopped there.
    @discardableResult
    func placeFavoriteInNextEmptyBlock(_ favorite: FocusTask, at date: Date = .now) -> FocusPlacementResult {
        guard plus.isAuthorized else { return .locked }
        guard favorite.deletedAt == nil else { return .noShift }
        return createFocusTaskInNextEmptyBlock(
            title: favorite.title,
            pomodoros: favorite.estimatedPomodoros,
            icon: favorite.icon,
            at: date
        )
    }

    /// The quick-create landing, and the one a purchase resumes into.
    @discardableResult
    func createFocusTaskInNextEmptyBlock(
        title: String,
        pomodoros: Int = 1,
        icon: FocusTaskIcon = .focus,
        isFavorite: Bool = false,
        at date: Date = .now
    ) -> FocusPlacementResult {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plus.isAuthorized else { return .locked }
        guard !trimmed.isEmpty else { return .noShift }
        guard let shift = focusCanvasShift(at: date)?.snapshot else { return .noShift }

        let canvas = focusDayCanvas(at: date)
        guard let target = canvas.nextEmptyBlock else {
            // Not a no-op and not an error: the task is real, it just has no
            // room in this shift. The canvas lists it as unscheduled.
            let task = addFocusTaskAuthorized(
                title: trimmed,
                pomodoros: pomodoros,
                plannedFor: shift.startDate,
                icon: icon,
                isFavorite: isFavorite
            )
            return .addedUnscheduled(taskID: task.id)
        }
        let task = addFocusTaskAuthorized(
            title: trimmed,
            pomodoros: pomodoros,
            plannedFor: shift.startDate,
            icon: icon,
            isFavorite: isFavorite
        )
        return assign(task, toBlockStartingAt: target.startAtMs, at: date)
    }

    /// Block-first creation: the block is already chosen, the task is made
    /// inside it. This is the path that removes the old dead end, where the
    /// fourth screen told you to go back two levels and create the task first.
    @discardableResult
    func createFocusTask(
        title: String,
        icon: FocusTaskIcon = .focus,
        inBlockStartingAt blockStartAtMs: Int64,
        at date: Date = .now
    ) -> FocusPlacementResult {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plus.isAuthorized else { return .locked }
        guard !trimmed.isEmpty, let shift = focusCanvasShift(at: date)?.snapshot else { return .noShift }
        let task = addFocusTaskAuthorized(
            title: trimmed,
            pomodoros: 1,
            plannedFor: shift.startDate,
            icon: icon
        )
        return assign(task, toBlockStartingAt: blockStartAtMs, at: date)
    }

    /// Assigns by block key rather than by `FocusWorkBlock`, so a view can act
    /// on what the canvas model gave it without rebuilding the grid.
    @discardableResult
    func assign(
        _ task: FocusTask,
        toBlockStartingAt blockStartAtMs: Int64,
        at date: Date = .now
    ) -> FocusPlacementResult {
        guard plus.isAuthorized else { return .locked }
        guard let block = focusWorkBlocks(at: date).first(where: { $0.startAtMs == blockStartAtMs }),
              block.kind == .task
        else { return .noShift }
        assignFocusBlock(block, to: task, at: date)
        return .placed(taskID: task.id, blockStartAtMs: blockStartAtMs)
    }

    /// Turns a work block into a break. The only way to get one: the cadence's
    /// own break blocks are not editable.
    func markBlockAsBreak(startingAt blockStartAtMs: Int64, at date: Date = .now) {
        guard plus.isAuthorized,
              let block = focusWorkBlocks(at: date).first(where: { $0.startAtMs == blockStartAtMs }),
              block.kind == .task
        else { return }
        assignFocusBreak(block, at: date)
    }

    func clearBlock(startingAt blockStartAtMs: Int64, at date: Date = .now) {
        guard plus.isAuthorized,
              let block = focusWorkBlocks(at: date).first(where: { $0.startAtMs == blockStartAtMs }),
              block.kind == .task
        else { return }
        clearFocusBlock(block, at: date)
    }

    /// Why the cadence cannot be changed right now, or nil when it can.
    ///
    /// The settings sheet used to lock on "this day has a saved plan" while
    /// `updateFocusTimerSettings` rejects on "any template exists". With a
    /// template saved and no plan yet, every field was editable, Save was
    /// enabled, and the write was dropped without a word.
    var focusTimerSettingsLockReason: FocusTimerLockReason? {
        focusPlanning.templates.isEmpty ? nil : .hasTemplates
    }

    enum FocusTimerLockReason: Equatable, Sendable {
        /// Template slots are numbered against the current cadence, so
        /// changing it would silently re-point saved task slots.
        case hasTemplates
    }
}
