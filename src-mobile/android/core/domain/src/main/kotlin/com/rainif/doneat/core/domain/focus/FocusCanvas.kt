package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.FocusTemplate
import com.rainif.doneat.core.domain.records.FocusTemplateSlot

/**
 * Everything the focus canvas draws, resolved once so no view does
 * arithmetic on a shift (iOS `FocusDayCanvasModel`).
 */
data class FocusDayCanvas(
    val shiftStartAtMs: Long,
    val shiftEndAtMs: Long,
    val dayKey: String,
    /** True when no shift is running and the canvas shows the next one. */
    val isNextShift: Boolean,
    /** Null when the clock is outside the drawn shift. */
    val nowAtMs: Long?,
    val blocks: List<Block>,
    val gaps: List<Gap>,
    val tasks: List<TaskRow>,
    /** Tasks that do not fit the rest of the shift: a footnote, not a verdict. */
    val overflow: List<TaskRow>,
    val pointsPerHour: Double,
    /** Without Plus the canvas is a shape only: no assignment, task or session is read. */
    val isLocked: Boolean,
) {
    enum class State { PAST, CURRENT, FUTURE }

    data class Block(
        val index: Int,
        val startAtMs: Long,
        val endAtMs: Long,
        val kind: FocusPlanBlockKind,
        val state: State,
        val taskID: String? = null,
        val taskTitle: String? = null,
        val taskIcon: FocusTaskIcon? = null,
        /** A work block the user turned into a break; the grid's own kind stays so it can be undone. */
        val isUserBreak: Boolean = false,
    ) {
        val isAssigned get() = taskID != null
        val hasAssignment get() = taskID != null || isUserBreak
        val rendersAsBreak get() = kind == FocusPlanBlockKind.BREAK_TIME || isUserBreak
        /** Only a work block that has not passed accepts an edit. */
        val isEditable get() = kind == FocusPlanBlockKind.TASK && state != State.PAST
    }

    data class Gap(val startAtMs: Long, val endAtMs: Long, val kind: Kind) {
        enum class Kind { BETWEEN_SEGMENTS, TAIL }
        val durationMinutes get() = maxOf(0, ((endAtMs - startAtMs) / 60_000).toInt())
    }

    /** Progress reads "done of scheduled", not "done of estimated". */
    data class TaskRow(
        val id: String,
        val title: String,
        val icon: FocusTaskIcon,
        val completedBlocks: Int,
        val assignedBlocks: Int,
        val estimatedBlocks: Int,
        val isRunning: Boolean,
        val isDone: Boolean,
    ) {
        val isScheduled get() = assignedBlocks > 0
    }

    val isEmpty get() = blocks.isEmpty() && gaps.isEmpty()
    val nextEmptyBlock get() = blocks.firstOrNull { it.kind == FocusPlanBlockKind.TASK && it.state != State.PAST && !it.hasAssignment }
    val currentBlock get() = blocks.firstOrNull { it.state == State.CURRENT }

    fun offset(ms: Long) = (ms - shiftStartAtMs) / 3_600_000.0 * pointsPerHour
    fun height(ms: Long) = maxOf(0.0, ms / 3_600_000.0 * pointsPerHour)

    companion object {
        /** Dense enough that one focus block always clears a 44 pt target. */
        fun pointsPerHour(focusMinutes: Int) = maxOf(96.0, 44.0 * 60 / maxOf(1, focusMinutes))

        fun empty(focusMinutes: Int, isLocked: Boolean) =
            FocusDayCanvas(0, 0, "", false, null, emptyList(), emptyList(), emptyList(), emptyList(), pointsPerHour(focusMinutes), isLocked)
    }
}

/** A template's tasks, grouped from its slots in order (iOS `FocusTemplate.tasks`). */
data class FocusTemplateTask(val taskKey: String?, val legacyIndex: Int, val title: String, val icon: FocusTaskIcon, val pomodoros: Int) {
    val id get() = taskKey ?: "legacy-$legacyIndex"
}

object FocusTemplates {
    fun tasks(slots: List<FocusTemplateSlot>): List<FocusTemplateTask> {
        val result = ArrayList<FocusTemplateTask>()
        for (slot in slots.sortedBy { it.blockIndex }.filter { it.kind == FocusPlanBlockKind.TASK }) {
            val existing = slot.taskKey?.let { key -> result.indexOfFirst { it.taskKey == key } } ?: -1
            if (existing >= 0) {
                result[existing] = result[existing].copy(pomodoros = result[existing].pomodoros + 1)
            } else {
                result += FocusTemplateTask(slot.taskKey, slot.blockIndex, slot.taskTitle ?: "", slot.taskIcon ?: FocusTaskIcon.FOCUS, 1)
            }
        }
        return result
    }

    /** Normalises tasks back into consecutive task slots; a key-less task gets one. */
    fun slots(tasks: List<FocusTemplateTask>, newKey: () -> String): List<FocusTemplateSlot> {
        val result = ArrayList<FocusTemplateSlot>()
        for (task in tasks) {
            val key = task.taskKey ?: newKey()
            repeat(maxOf(1, task.pomodoros)) {
                result += FocusTemplateSlot(result.size, FocusPlanBlockKind.TASK, key, task.title, task.icon)
            }
        }
        return result
    }

    /** How many whole tasks fit the work blocks, in order; a task that does not fit ends the run. */
    fun fittingTaskCount(tasks: List<FocusTemplateTask>, blocks: List<FocusWorkBlock>): Int {
        var remaining = blocks.count { it.kind == FocusPlanBlockKind.TASK }
        var count = 0
        for (task in tasks) {
            if (task.pomodoros > remaining) break
            remaining -= task.pomodoros
            count++
        }
        return count
    }

    /** The template laid onto today's work blocks: whole tasks only, a complete prefix. */
    fun placedSlots(template: FocusTemplate, blocks: List<FocusWorkBlock>): List<FocusTemplateSlot> {
        val work = blocks.filter { it.kind == FocusPlanBlockKind.TASK }
        val tasks = tasks(template.slots)
        val result = ArrayList<FocusTemplateSlot>()
        var cursor = 0
        for (task in tasks.take(fittingTaskCount(tasks, blocks))) {
            for (block in work.subList(cursor, cursor + task.pomodoros)) {
                result += FocusTemplateSlot(block.index, FocusPlanBlockKind.TASK, task.taskKey, task.title, task.icon)
            }
            cursor += task.pomodoros
        }
        return result
    }
}

/** The pure arithmetic behind the running chain (iOS `FocusLiveChain`). */
object FocusChain {
    /**
     * Blocks a task will still occupy from [fromMs]: its own, plus free
     * blocks for an estimate never placed. Another task's block is skipped,
     * not the end of the walk.
     */
    fun projectedBlocks(taskID: String, remaining: Int, blocks: List<FocusDayCanvas.Block>, fromMs: Long): List<FocusDayCanvas.Block> {
        if (remaining <= 0) return emptyList()
        val result = ArrayList<FocusDayCanvas.Block>()
        for (block in blocks) {
            if (block.kind != FocusPlanBlockKind.TASK || block.isUserBreak || block.startAtMs < fromMs) continue
            if (result.size >= remaining) break
            if (block.taskID == taskID || !block.hasAssignment) result += block
        }
        return result
    }

    /** The next block the plan has a real task in, from [fromMs]. */
    fun nextPlannedBlock(blocks: List<FocusDayCanvas.Block>, fromMs: Long) =
        blocks.firstOrNull { it.kind == FocusPlanBlockKind.TASK && !it.isUserBreak && it.taskID != null && it.startAtMs >= fromMs }
}
