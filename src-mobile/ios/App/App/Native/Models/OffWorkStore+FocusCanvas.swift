import Foundation

extension OffWorkStore {
    /// The one query behind everything the canvas shows a task in.
    ///
    /// The page list and the block-assignment sheet used to ask two different
    /// questions — `focusTasksForFocusPage` included tasks planned for a later
    /// day, `focusTasksForToday` did not — so a task created for tomorrow was
    /// visible on the page and unselectable in the planner. Overflow keeps its
    /// own today-only query on purpose: that one is arithmetic about this
    /// shift's remaining time, not a list of what you can pick.
    func focusTasksForCanvas(at date: Date = .now) -> [FocusTask] {
        focusTasksForFocusPage(at: date)
    }

    /// Resolves the shift the canvas draws.
    ///
    /// "Today" outlives clock-off: the question is still whether a shift holds
    /// what you want to do, so once the current one has ended the canvas moves
    /// to the next one and says so, rather than going blank.
    func focusCanvasShift(at date: Date = .now) -> (snapshot: NativeShiftSnapshot, isNext: Bool)? {
        guard let current = snapshot(at: date) else { return nil }
        if date < current.endDate { return (current, false) }
        guard let nextStart = current.nextShiftStartDate,
              let next = snapshot(at: nextStart.addingTimeInterval(1))
        else { return nil }
        return (next, true)
    }

    /// The lock state on its own, for callers that only need to know whether
    /// a control should be offered. Building the whole canvas for that answer
    /// costs two rule-bundle round trips.
    var focusDayCanvasIsLocked: Bool { !plus.isAuthorized }

    /// The next placeable block without assembling task rows or overflow.
    func nextEmptyFocusBlock(at date: Date = .now) -> FocusWorkBlock? {
        guard plus.isAuthorized, let shift = focusCanvasShift(at: date)?.snapshot else { return nil }
        let dayKey = RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar)
        let assignments = focusPlanning.plans[dayKey]?.assignments ?? []
        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        return FocusPlanner.workBlocks(segments: shift.segments, settings: focusTimerSettings)
            .first { block in
                block.kind == .task
                    && Int64(block.end.timeIntervalSince1970 * 1_000) > nowMs
                    && !assignments.contains { $0.blockStartAtMs == block.startAtMs }
            }
    }

    func focusDayCanvas(at date: Date = .now) -> FocusDayCanvasModel {
        let settings = focusTimerSettings.normalized
        var model = FocusDayCanvasModel.empty
        model.pointsPerHour = FocusDayCanvasModel.pointsPerHour(focusMinutes: settings.focusMinutes)
        model.isLocked = !plus.isAuthorized

        guard let (shift, isNext) = focusCanvasShift(at: date) else { return model }
        let dayKey = RecordJSON.dayKey(shift.startDate, calendar: recordsCalendar)
        model.dayKey = dayKey
        model.isNextShift = isNext
        model.shiftStartAtMs = Int64(shift.startAtMs)

        let segments = shift.segments.sorted { $0.startAtMs < $1.startAtMs }
        let lastSegmentEnd = Int64(segments.last?.endAtMs ?? shift.startAtMs)
        // Overtime carries no pre-drawn blocks — the cadence only fills
        // segments — but it is still time the user is at work and can start a
        // block in, so the band covers it rather than ending at clock-off.
        let overtimeEnd = overtimeEndAtMs.map { Int64($0) } ?? lastSegmentEnd
        model.shiftEndAtMs = max(lastSegmentEnd, overtimeEnd)

        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        model.nowAtMs = (nowMs >= model.shiftStartAtMs && nowMs <= model.shiftEndAtMs) ? nowMs : nil

        // Locked users get a shape, never values: the placeholder is rendered
        // from the grid alone and no assignment, task or session is read.
        let assignments = model.isLocked ? [] : (focusPlanning.plans[dayKey]?.assignments ?? [])
        let blocks = FocusPlanner.workBlocks(segments: shift.segments, settings: settings)

        model.blocks = blocks.map { block in
            let assignment = block.kind == .task
                ? assignments.first(where: { $0.blockStartAtMs == block.startAtMs })
                : nil
            let state: FocusDayCanvasModel.Block.State
            if model.nowAtMs == nil {
                state = isNext ? .future : (block.startAtMs < nowMs ? .past : .future)
            } else if block.end.timeIntervalSince1970 * 1_000 <= Double(nowMs) {
                state = .past
            } else if Double(block.startAtMs) <= Double(nowMs) {
                state = .current
            } else {
                state = .future
            }
            return FocusDayCanvasModel.Block(
                index: block.index,
                startAtMs: block.startAtMs,
                endAtMs: Int64(block.end.timeIntervalSince1970 * 1_000),
                kind: block.kind,
                state: state,
                taskID: assignment?.taskID,
                taskTitle: assignment?.taskTitle,
                taskIcon: assignment?.taskIcon
            )
        }
        model.gaps = Self.canvasGaps(segments: segments, blocks: blocks, shiftEndAtMs: model.shiftEndAtMs)

        guard !model.isLocked else { return model }

        let runningTaskID = activeFocusSession()?.taskID
        let assignedCounts = assignments.reduce(into: [UUID: Int]()) { counts, assignment in
            guard let taskID = assignment.taskID else { return }
            counts[taskID, default: 0] += 1
        }
        let completedToday = focusSessions(forDayKey: dayKey).reduce(into: [UUID: Int]()) { counts, session in
            guard session.kind == .focus, session.endReason == .completed, let taskID = session.taskID
            else { return }
            counts[taskID, default: 0] += 1
        }
        func row(_ task: FocusTask) -> FocusDayCanvasModel.TaskRow {
            FocusDayCanvasModel.TaskRow(
                id: task.id,
                title: task.title,
                icon: task.icon,
                completedBlocks: completedToday[task.id] ?? 0,
                assignedBlocks: assignedCounts[task.id] ?? 0,
                estimatedBlocks: task.estimatedPomodoros,
                isRunning: runningTaskID == task.id,
                isDone: task.completedAt != nil
            )
        }
        model.tasks = focusTasksForCanvas(at: date).map(row)
        model.overflow = focusOverflow().map(row)
        return model
    }

    /// Stretches of the shift that hold no block.
    ///
    /// Two kinds, and they read differently on the band: the gap between two
    /// segments is lunch and belongs to the schedule, while the leftover at
    /// the end of a segment is simply too short for another block and should
    /// say so instead of pretending to be one.
    static func canvasGaps(
        segments: [NativeShiftSegment],
        blocks: [FocusWorkBlock],
        shiftEndAtMs: Int64
    ) -> [FocusDayCanvasModel.Gap] {
        var gaps: [FocusDayCanvasModel.Gap] = []
        var previousEnd: Int64?
        for segment in segments {
            let start = Int64(segment.startAtMs.rounded())
            let end = Int64(segment.endAtMs.rounded())
            if let previousEnd, start > previousEnd {
                gaps.append(.init(startAtMs: previousEnd, endAtMs: start, kind: .betweenSegments))
            }
            let inside = blocks.filter { $0.startAtMs >= start && $0.startAtMs < end }
            let lastBlockEnd = inside.map { Int64($0.end.timeIntervalSince1970 * 1_000) }.max() ?? start
            if end > lastBlockEnd {
                gaps.append(.init(startAtMs: lastBlockEnd, endAtMs: end, kind: .tail))
            }
            previousEnd = end
        }
        if let previousEnd, shiftEndAtMs > previousEnd {
            gaps.append(.init(startAtMs: previousEnd, endAtMs: shiftEndAtMs, kind: .tail))
        }
        return gaps
    }
}
