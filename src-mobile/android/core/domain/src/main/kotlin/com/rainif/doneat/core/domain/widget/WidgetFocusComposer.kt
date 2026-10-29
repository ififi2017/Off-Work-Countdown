package com.rainif.doneat.core.domain.widget

import com.rainif.doneat.core.domain.focus.FocusDayCanvas
import com.rainif.doneat.core.domain.focus.FocusEngine
import com.rainif.doneat.core.domain.focus.FocusEnvironment
import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.RecordState

/** FocusLiveChain's running phase, earned recovery and planned queue, using the existing lifecycle engine. */
object WidgetFocusComposer {
    fun compose(
        state: RecordState, env: FocusEnvironment, canvas: FocusDayCanvas, nowMs: Long,
        focusTitle: String, breakTitle: String,
    ): List<WidgetFocusBlock> {
        if (!env.isAuthorized || canvas.isLocked) return emptyList()
        val engine = FocusEngine(env)
        val result = mutableListOf<WidgetFocusBlock>()
        val current = engine.activeSession(state)
        if (current != null) {
            val task = state.focusTasks.firstOrNull { it.id == current.taskID }
            val isBreak = current.kind != FocusSessionKind.FOCUS
            val completed = if (task == null || isBreak) 0 else engine.completedBlocks(state, task) +
                env.pendingScheduled().count { it.taskID == task.id && it.plannedEndAtMs <= current.startedAtMs } +
                state.focusSessions.count { it.taskID == task.id && it.endedAtMs == null && it.plannedEndAtMs <= current.startedAtMs }
            val round = completed + 1
            result += WidgetFocusBlock(if (isBreak) breakTitle else task?.title ?: focusTitle,
                if (isBreak) "break" else task?.icon?.raw, current.startedAtMs.toLong(), current.plannedEndAtMs.toLong(),
                round, maxOf(round, task?.estimatedPomodoros ?: 1), isBreak, isRunning = true)
            var cursor = current.plannedEndAtMs
            if (!isBreak && current.taskID != null && current.plannedEndReason == FocusEndReason.COMPLETED &&
                !engine.completesDay(state, current, nowMs.toDouble())) {
                engine.plannedBreakEnd(engine.nextBreakKind(state, current), current.plannedEndAtMs)?.let { end ->
                    result += WidgetFocusBlock(breakTitle, "break", current.plannedEndAtMs.toLong(), end.toLong(), isBreak = true, isRunning = true)
                    cursor = end
                }
            }
            val next = canvas.blocks.firstOrNull {
                it.kind == FocusPlanBlockKind.TASK && !it.isUserBreak && it.taskID != null && it.startAtMs >= cursor
            }
            val nextTask = next?.taskID?.let { id -> state.focusTasks.firstOrNull { it.id == id && it.completedAtMs == null && it.deletedAtMs == null } }
            if (next != null && nextTask != null) {
                val done = engine.completedBlocks(state, nextTask) + if (!isBreak && nextTask.id == current.taskID) 1 else 0
                result += WidgetFocusBlock(next.taskTitle ?: nextTask.title, next.taskIcon?.raw ?: nextTask.icon.raw,
                    next.startAtMs, next.endAtMs, done + 1, maxOf(done + 1, nextTask.estimatedPomodoros))
            }
        }
        val after = result.lastOrNull()?.endMs ?: nowMs
        for (block in canvas.blocks) {
            if (result.size >= 6) break
            if (block.startAtMs < after || block.kind != FocusPlanBlockKind.TASK || block.isUserBreak || block.taskID == null) continue
            val task = state.focusTasks.firstOrNull { it.id == block.taskID && it.completedAtMs == null && it.deletedAtMs == null } ?: continue
            result += WidgetFocusBlock(block.taskTitle ?: task.title, block.taskIcon?.raw ?: task.icon.raw, block.startAtMs, block.endAtMs)
        }
        return result.filter { it.endMs > nowMs }.take(6)
    }
}
