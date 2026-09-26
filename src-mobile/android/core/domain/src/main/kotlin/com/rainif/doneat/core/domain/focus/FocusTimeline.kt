package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusPlanAssignment
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.session.TimelineEvent
import com.rainif.doneat.core.domain.session.TimelineKind

/** iOS focusUpcomingTimelineEvents / focusPlanAssignments, shared by the timer and widget. */
class FocusTimeline(private val env: FocusEnvironment) {
    private val engine = FocusEngine(env)
    private val planning = FocusPlanning(env)

    fun events(state: RecordState, shift: FocusShift?, nowMs: Double): List<TimelineEvent> {
        if (!env.isAuthorized) return emptyList()
        val events = ArrayList<TimelineEvent>()
        engine.activeSession(state)?.takeIf { it.plannedEndAtMs > nowMs }?.let {
            events += TimelineEvent("focus-session-${it.id}", TimelineKind.FOCUS, it.plannedEndAtMs, runningFocus = true)
        }
        val horizon = nowMs + 2 * 86_400_000.0
        val planned = shift?.let { assignments(state, it.segments, it.startAtMs) }.orEmpty()
            .filter { (block, _) -> block.startAtMs > nowMs && block.startAtMs <= horizon }
        planned.forEach { (block, assignment) -> events += event(block, assignment) }
        val plannedIds = planned.mapNotNull { it.second.taskID }.toSet()
        state.focusTasks.forEach { task ->
            val start = task.scheduledStartAtMs
            if (task.completedAtMs == null && task.deletedAtMs == null && task.id !in plannedIds &&
                start != null && start > nowMs && start <= horizon) {
                events += TimelineEvent("focus-task-${task.id}", TimelineKind.FOCUS, start,
                    focusTitle = task.title, focusMinutes = planning.settings(state).focusMinutes,
                    focusPomodoros = maxOf(1, task.estimatedPomodoros))
            }
        }
        return events.sortedBy { it.atMs }
    }

    /** Future widget shifts use the same planner without writing projected templates into the archive. */
    fun plannedEvents(state: RecordState, segments: List<ShiftSegment>, startAtMs: Double): List<TimelineEvent> =
        if (!env.isAuthorized) emptyList() else assignments(state, segments, startAtMs).map { (block, assignment) -> event(block, assignment) }

    private fun assignments(state: RecordState, segments: List<ShiftSegment>, startAtMs: Double): List<Pair<FocusWorkBlock, FocusPlanAssignment>> {
        val blocks = FocusPlanner.workBlocks(segments, planning.settings(state))
        val configuration = planning.planning(state)
        val day = configuration.plans[engine.dayKey(startAtMs)]
        val assignments = if (day != null) day.assignments else {
            val template = configuration.templates.firstOrNull { it.id == configuration.defaultTemplateID } ?: return emptyList()
            FocusTemplates.placedSlots(template, blocks).mapNotNull { slot ->
                blocks.getOrNull(slot.blockIndex)?.takeIf { it.kind == FocusPlanBlockKind.TASK }?.let { block ->
                    FocusPlanAssignment(block.startAtMs, slot.kind, null, slot.taskTitle, slot.taskIcon)
                }
            }
        }
        return blocks.mapIndexedNotNull { index, block ->
            if (block.kind == FocusPlanBlockKind.BREAK_TIME) {
                val previous = blocks.getOrNull(index - 1)
                if (previous == null || previous.kind != FocusPlanBlockKind.TASK || previous.endAtMs != block.startAtMs ||
                    assignments.none { it.blockStartAtMs == previous.startAtMs && it.kind == FocusPlanBlockKind.TASK &&
                        (it.taskID != null || !it.taskTitle.isNullOrEmpty()) }) null
                else block to FocusPlanAssignment(block.startAtMs, FocusPlanBlockKind.BREAK_TIME, null, null, null)
            } else assignments.firstOrNull { it.blockStartAtMs == block.startAtMs }?.let { block to it }
        }
    }

    private fun event(block: FocusWorkBlock, assignment: FocusPlanAssignment) = TimelineEvent(
        "focus-plan-${block.startAtMs}",
        if (assignment.kind == FocusPlanBlockKind.BREAK_TIME) TimelineKind.FOCUS_BREAK else TimelineKind.FOCUS,
        block.startAtMs.toDouble(), focusTitle = assignment.taskTitle, focusMinutes = block.durationMinutes,
    )
}
