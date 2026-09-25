package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusDayPlan
import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusPlanAssignment
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.FocusPlanningConfiguration
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.FocusTask
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.FocusTemplate
import com.rainif.doneat.core.domain.records.FocusTemplateSlot
import com.rainif.doneat.core.domain.records.FocusTimerSettings
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.RecordState

/** The planning half of the Focus configuration: day plans, templates and the default. */
data class PlanningState(
    val plans: Map<String, FocusDayPlan> = emptyMap(),
    val templates: List<FocusTemplate> = emptyList(),
    val defaultTemplateID: String? = null,
    val autoAppliedDayKeys: Set<String> = emptySet(),
)

/** Result of a planning edit: the next archive and what the edit answered. */
data class Planned<T>(val state: RecordState, val value: T)

/** What happened when the canvas tried to put something in a block. */
sealed interface FocusPlacement {
    data class Placed(val taskID: String, val blockStartAtMs: Long) : FocusPlacement
    /** The task exists but the shift had no empty block left. */
    data class AddedUnscheduled(val taskID: String) : FocusPlacement
    data object NoShift : FocusPlacement
    data object Locked : FocusPlacement
}

enum class FocusExtensionError { CONFLICT, NO_ROOM }

/**
 * Focus planning (iOS `FocusStore` plus its Canvas, Placement and Templates
 * extensions) as pure transitions over the archive. The plan lives in the
 * archive's `FocusPlanningConfiguration`; every change writes it back with a
 * fresh stamp, and an unchanged plan writes nothing.
 *
 * Blocks are addressed by `startAtMs` on the grid [FocusPlanner] draws from
 * the shift, so a plan survives the clock moving on. Only work blocks accept
 * a task; a work block can become a break; the grid's own breaks never change.
 */
class FocusPlanning(private val env: FocusEnvironment, private val defaultTaskTitle: String = "Focus") {
    private val engine = FocusEngine(env)

    fun planning(state: RecordState) = state.focusPlanningConfiguration?.let {
        PlanningState(it.plans, it.templates, it.defaultTemplateID, it.autoAppliedDayKeys)
    } ?: PlanningState()

    fun settings(state: RecordState): FocusTimerSettings = state.focusPlanningConfiguration?.timerSettings?.normalized ?: DEFAULT_TIMER_SETTINGS

    /** Writes the configuration back; identical planning and settings write nothing. */
    private fun persist(state: RecordState, planning: PlanningState, nowMs: Double, settings: FocusTimerSettings = settings(state)): RecordState {
        val current = state.focusPlanningConfiguration
        if (current != null && planning(state) == planning && current.timerSettings.normalized == settings.normalized) return state
        if (current == null && planning == PlanningState() && settings.normalized == DEFAULT_TIMER_SETTINGS) return state
        val next = FocusPlanningConfiguration(
            planning.plans, planning.templates, planning.defaultTemplateID, planning.autoAppliedDayKeys, settings.normalized,
            editedAtMs = nowMs, editCount = (current?.editCount ?: 0) + 1, editTieBreaker = env.newId(),
        )
        return state.copy(focusPlanningConfiguration = next)
    }

    /** Refuses a cadence change while templates exist: their slots are numbered against it. */
    fun updateTimerSettings(state: RecordState, settings: FocusTimerSettings, nowMs: Double): Planned<Boolean> {
        if (planning(state).templates.isNotEmpty()) return Planned(state, false)
        return Planned(persist(state, planning(state), nowMs, settings.normalized), true)
    }

    private fun dayKey(ms: Double) = engine.dayKey(ms)

    // The shift the canvas draws

    /** The current shift while it runs; after clock-off, the next one. */
    fun canvasShift(nowMs: Double): Pair<FocusShift, Boolean>? {
        if (!env.scheduleEnabled(nowMs)) return null
        val current = env.shift(nowMs) ?: return null
        if (nowMs < current.endAtMs && current.isWorkday) return current to false
        val next = current.nextShiftStartAtMs?.let { env.shift(it + 1_000) } ?: return null
        return next to true
    }

    fun blocks(shift: FocusShift, state: RecordState) = FocusPlanner.workBlocks(shift.segments, settings(state))

    /** A block's assignment on the shift at [nowMs]; the grid's own breaks always read as breaks, stored or not. */
    fun assignment(state: RecordState, block: FocusWorkBlock, nowMs: Double): FocusPlanAssignment? {
        val shift = env.shift(nowMs) ?: return null
        if (block.kind == FocusPlanBlockKind.BREAK_TIME) return FocusPlanAssignment(block.startAtMs, FocusPlanBlockKind.BREAK_TIME, null, null, null)
        return planning(state).plans[dayKey(shift.startAtMs)]?.assignments?.firstOrNull { it.blockStartAtMs == block.startAtMs }
    }

    fun canvas(state: RecordState, nowMs: Double): FocusDayCanvas {
        val settings = settings(state)
        val locked = !env.isAuthorized
        val empty = FocusDayCanvas.empty(settings.focusMinutes, locked)
        val (shift, isNext) = canvasShift(nowMs) ?: return empty
        val key = dayKey(shift.startAtMs)
        val segments = shift.segments.sortedBy { it.startAtMs }
        val lastSegmentEnd = (segments.lastOrNull()?.endAtMs ?: shift.startAtMs).toLong()
        // Overtime has no pre-drawn blocks, but it is still time at work.
        val shiftEnd = maxOf(lastSegmentEnd, env.overtimeEndAtMs?.toLong() ?: lastSegmentEnd)
        val shiftStart = shift.startAtMs.toLong()
        val now = nowMs.toLong()
        val nowAt = if (now in shiftStart..shiftEnd) now else null
        val assignments = if (locked) emptyList() else planning(state).plans[key]?.assignments.orEmpty()
        val grid = FocusPlanner.workBlocks(shift.segments, settings)
        val blocks = grid.map { block ->
            val assignment = if (block.kind == FocusPlanBlockKind.TASK) assignments.firstOrNull { it.blockStartAtMs == block.startAtMs } else null
            val blockState = when {
                nowAt == null -> if (isNext) FocusDayCanvas.State.FUTURE else if (block.startAtMs < now) FocusDayCanvas.State.PAST else FocusDayCanvas.State.FUTURE
                block.endAtMs <= now -> FocusDayCanvas.State.PAST
                block.startAtMs <= now -> FocusDayCanvas.State.CURRENT
                else -> FocusDayCanvas.State.FUTURE
            }
            FocusDayCanvas.Block(
                block.index, block.startAtMs, block.endAtMs, block.kind, blockState,
                assignment?.taskID, assignment?.taskTitle, assignment?.taskIcon, assignment?.kind == FocusPlanBlockKind.BREAK_TIME,
            )
        }
        val base = FocusDayCanvas(shiftStart, shiftEnd, key, isNext, nowAt, blocks, gaps(segments, grid, shiftEnd), emptyList(), emptyList(),
            FocusDayCanvas.pointsPerHour(settings.focusMinutes), locked)
        if (locked) return base
        val running = engine.activeSession(state)?.taskID
        val assigned = assignments.mapNotNull { it.taskID }.groupingBy { it }.eachCount()
        val completedToday = state.focusSessions
            .filter { it.startedAtMs >= shift.startAtMs && it.startedAtMs < shift.endAtMs && it.kind == FocusSessionKind.FOCUS && it.endReason == FocusEndReason.COMPLETED }
            .mapNotNull { it.taskID }.groupingBy { it }.eachCount()
        fun row(t: FocusTask) = FocusDayCanvas.TaskRow(t.id, t.title, t.icon, completedToday[t.id] ?: 0, assigned[t.id] ?: 0, t.estimatedPomodoros, running == t.id, t.completedAtMs != null)
        return base.copy(tasks = tasksForPage(state, nowMs).map(::row), overflow = overflow(state, nowMs).map(::row))
    }

    /** Lunch between segments, and the tail of a segment too short for another block. */
    private fun gaps(segments: List<com.rainif.doneat.core.domain.schedule.ShiftSegment>, blocks: List<FocusWorkBlock>, shiftEnd: Long): List<FocusDayCanvas.Gap> {
        val result = ArrayList<FocusDayCanvas.Gap>()
        var previousEnd: Long? = null
        for (segment in segments) {
            val start = FoundationCompat.roundedHalfAwayFromZero(segment.startAtMs).toLong()
            val end = FoundationCompat.roundedHalfAwayFromZero(segment.endAtMs).toLong()
            if (previousEnd != null && start > previousEnd) result += FocusDayCanvas.Gap(previousEnd, start, FocusDayCanvas.Gap.Kind.BETWEEN_SEGMENTS)
            val lastBlockEnd = blocks.filter { it.startAtMs in start until end }.maxOfOrNull { it.endAtMs } ?: start
            if (end > lastBlockEnd) result += FocusDayCanvas.Gap(lastBlockEnd, end, FocusDayCanvas.Gap.Kind.TAIL)
            previousEnd = end
        }
        if (previousEnd != null && shiftEnd > previousEnd) result += FocusDayCanvas.Gap(previousEnd, shiftEnd, FocusDayCanvas.Gap.Kind.TAIL)
        return result
    }

    // Task lists

    private fun taskDay(nowMs: Double) = dayKey(minOf(nowMs, canvasShift(nowMs)?.first?.startAtMs ?: nowMs))

    /** The Focus page: today's open work, later planned tasks, and what finished today. */
    fun tasksForPage(state: RecordState, nowMs: Double): List<FocusTask> {
        val today = taskDay(nowMs)
        val tomorrow = FoundationCompat.dayKey(java.time.LocalDate.parse(dayKey(nowMs)).plusDays(1))
        return state.focusTasks.filter { task ->
            if (task.deletedAtMs != null || (task.isFavorite && task.plannedForDate == null)) return@filter false
            val completed = task.completedAtMs
            if (completed == null) task.plannedForDate?.let { it >= today } ?: true
            else dayKey(completed).let { it >= today && it < tomorrow }
        }.sortedWith(
            compareBy<FocusTask> { it.scheduledStartAtMs ?: it.plannedForDate?.let(::startOfDay) ?: it.createdAtMs }.thenBy { it.sortIndex }.thenBy { it.id },
        )
    }

    fun overflow(state: RecordState, nowMs: Double): List<FocusTask> {
        val remaining = env.shift(nowMs)?.remainingMs?.toLong() ?: 0
        return FocusPlanner.remainingPomodoros(engine.tasksForToday(state, nowMs), remaining, { engine.completedBlocks(state, it) }, settings(state)).second
    }

    private fun startOfDay(dayKey: String) =
        java.time.LocalDate.parse(dayKey).atStartOfDay(FoundationCompat.javaZone(env.recordsTimeZone)).toInstant().toEpochMilli().toDouble()

    /** Unfinished tasks planned for an earlier day move to today and lose their slot. */
    fun carryIncomplete(state: RecordState, nowMs: Double): RecordState {
        val today = dayKey(nowMs)
        return state.focusTasks
            .filter { it.completedAtMs == null && it.deletedAtMs == null && (it.plannedForDate?.let { p -> p < today } == true) }
            .fold(state) { s, t -> engine.upsertTask(s, t.copy(plannedForDate = today, scheduledStartAtMs = null), nowMs) }
    }

    fun addTask(state: RecordState, title: String, pomodoros: Int, nowMs: Double, plannedForMs: Double? = null, scheduledStartAtMs: Double? = null, icon: FocusTaskIcon = FocusTaskIcon.FOCUS, isFavorite: Boolean = false): Planned<FocusTask> {
        val id = env.newId()
        val task = FocusTask(
            id, nowMs, dayKey(plannedForMs ?: nowMs), scheduledStartAtMs, title, maxOf(1, pomodoros), icon, isFavorite,
            completedAtMs = null, deletedAtMs = null, sortIndex = (state.focusTasks.maxOfOrNull { it.sortIndex } ?: -1) + 1,
            editedAtMs = nowMs, editCount = 0, editTieBreaker = id, templateID = null, templateTaskKey = null,
        )
        val next = engine.upsertTask(state, task, nowMs)
        return Planned(next, next.focusTasks.last { it.id == id })
    }

    // Block assignments

    private fun earliestAssignment(planning: PlanningState, taskID: String) =
        planning.plans.values.flatMap { it.assignments }.filter { it.taskID == taskID }.minOfOrNull { it.blockStartAtMs.toDouble() }

    /** A template task's estimate follows the plan, but never below its completed rounds or one. */
    private fun templateEstimate(state: RecordState, planning: PlanningState, taskID: String) = maxOf(
        1,
        state.focusSessions.count { it.taskID == taskID && it.kind == FocusSessionKind.FOCUS && it.endReason == FocusEndReason.COMPLETED },
        planning.plans.values.flatMap { it.assignments }.count { it.taskID == taskID },
    )

    private fun refreshTaskSchedule(state: RecordState, planning: PlanningState, taskID: String, nowMs: Double): RecordState {
        val task = state.focusTasks.firstOrNull { it.id == taskID } ?: return state
        var next = task.copy(scheduledStartAtMs = earliestAssignment(planning, taskID))
        if (task.templateID != null) next = next.copy(estimatedPomodoros = templateEstimate(state, planning, taskID))
        return engine.upsertTask(state, next, nowMs)
    }

    private fun withAssignment(planning: PlanningState, assignment: FocusPlanAssignment, key: String, shiftStartAtMs: Long): PlanningState {
        val plan = planning.plans[key] ?: FocusDayPlan(key, shiftStartAtMs, emptyList(), null)
        val assignments = (plan.assignments.filter { it.blockStartAtMs != assignment.blockStartAtMs } + assignment).sortedBy { it.blockStartAtMs }
        return planning.copy(plans = planning.plans + (key to plan.copy(assignments = assignments, appliedTemplateID = null)), autoAppliedDayKeys = planning.autoAppliedDayKeys + key)
    }

    /**
     * A removed template assignment either becomes a reversible soft delete or,
     * when the task has history, a favourite or another plan reference, an
     * ordinary user task. It never disappears with the template.
     */
    private fun releaseTemplateTasks(state: RecordState, planning: PlanningState, taskIDs: Set<String>, nowMs: Double, preserving: Set<String> = emptySet()): RecordState {
        var s = state
        for (taskID in taskIDs - preserving) {
            val task = s.focusTasks.firstOrNull { it.id == taskID }?.takeIf { it.templateID != null } ?: continue
            val hasHistory = s.focusSessions.any { it.taskID == taskID }
            val referenced = planning.plans.values.any { p -> p.assignments.any { it.taskID == taskID } }
            val next = when {
                hasHistory || task.isFavorite || referenced -> task.copy(templateID = null, templateTaskKey = null, scheduledStartAtMs = earliestAssignment(planning, taskID))
                task.deletedAtMs == null -> task.copy(deletedAtMs = nowMs)
                else -> continue
            }
            s = engine.upsertTask(s, next, nowMs)
        }
        return s
    }

    private fun gridBlock(state: RecordState, shift: FocusShift, startAtMs: Long, workOnly: Boolean = true) =
        blocks(shift, state).firstOrNull { it.startAtMs == startAtMs && (!workOnly || it.kind == FocusPlanBlockKind.TASK) }

    fun assignBlock(state: RecordState, blockStartAtMs: Long, taskID: String, shift: FocusShift, nowMs: Double): RecordState {
        val task = state.focusTasks.firstOrNull { it.id == taskID && it.deletedAtMs == null } ?: return state
        if (!env.isAuthorized) return state
        val block = gridBlock(state, shift, blockStartAtMs) ?: return state
        val key = dayKey(shift.startAtMs)
        val planning = planning(state)
        val replaced = planning.plans[key]?.assignments?.firstOrNull { it.blockStartAtMs == block.startAtMs }?.taskID
        val nextPlanning = withAssignment(planning, FocusPlanAssignment(block.startAtMs, FocusPlanBlockKind.TASK, task.id, task.title, task.icon), key, shift.startAtMs.toLong())
        var s = persist(state, nextPlanning, nowMs)
        var updated = task.copy(plannedForDate = key, scheduledStartAtMs = earliestAssignment(nextPlanning, task.id))
        if (updated.templateID != null) updated = updated.copy(estimatedPomodoros = templateEstimate(s, nextPlanning, task.id))
        s = engine.upsertTask(s, updated, nowMs)
        if (replaced != null && replaced != task.id) s = releaseTemplateTasks(s, nextPlanning, setOf(replaced), nowMs)
        return s
    }

    fun assignBreak(state: RecordState, blockStartAtMs: Long, shift: FocusShift, nowMs: Double): RecordState {
        if (!env.isAuthorized) return state
        val block = gridBlock(state, shift, blockStartAtMs) ?: return state
        val key = dayKey(shift.startAtMs)
        val planning = planning(state)
        val replaced = planning.plans[key]?.assignments?.firstOrNull { it.blockStartAtMs == block.startAtMs }?.taskID
        val nextPlanning = withAssignment(planning, FocusPlanAssignment(block.startAtMs, FocusPlanBlockKind.BREAK_TIME, null, null, null), key, shift.startAtMs.toLong())
        val s = persist(state, nextPlanning, nowMs)
        return if (replaced != null) releaseTemplateTasks(s, nextPlanning, setOf(replaced), nowMs) else s
    }

    /** Clearing even one slot detaches the day from its template, so a later Apply restores it. */
    fun clearBlock(state: RecordState, blockStartAtMs: Long, shift: FocusShift, nowMs: Double): RecordState {
        val block = gridBlock(state, shift, blockStartAtMs, workOnly = false) ?: return state
        val key = dayKey(shift.startAtMs)
        val planning = planning(state)
        val plan = planning.plans[key]
        val removed = plan?.assignments?.firstOrNull { it.blockStartAtMs == block.startAtMs }?.taskID
        val nextPlans = if (plan == null) planning.plans else planning.plans + (key to plan.copy(assignments = plan.assignments.filter { it.blockStartAtMs != block.startAtMs }, appliedTemplateID = null))
        val nextPlanning = planning.copy(plans = nextPlans, autoAppliedDayKeys = planning.autoAppliedDayKeys + key)
        val s = persist(state, nextPlanning, nowMs)
        return if (removed != null) releaseTemplateTasks(s, nextPlanning, setOf(removed), nowMs) else s
    }

    // Templates

    /** Captures today's plan as a template: task order and repeats, not clock times. */
    fun saveTemplateFromToday(state: RecordState, name: String, nowMs: Double): Planned<FocusTemplate?> {
        val trimmed = name.trim()
        val shift = env.shift(nowMs)
        if (!env.isAuthorized || trimmed.isEmpty() || shift == null) return Planned(state, null)
        val key = dayKey(shift.startAtMs)
        val assignments = planning(state).plans[key]?.assignments.orEmpty()
        val keys = HashMap<String, String>()
        val slots = blocks(shift, state).mapNotNull { block ->
            val assignment = assignments.firstOrNull { it.blockStartAtMs == block.startAtMs }
                ?: if (block.kind == FocusPlanBlockKind.BREAK_TIME) FocusPlanAssignment(block.startAtMs, FocusPlanBlockKind.BREAK_TIME, null, null, null) else null
            if (assignment == null || assignment.kind != block.kind) return@mapNotNull null
            FocusTemplateSlot(block.index, assignment.kind, assignment.taskID?.let { keys.getOrPut(it) { env.newId() } }, assignment.taskTitle, assignment.taskIcon)
        }
        if (slots.isEmpty()) return Planned(state, null)
        val template = FocusTemplate(env.newId(), trimmed, slots, nowMs, nowMs)
        val planning = planning(state)
        return Planned(persist(state, planning.copy(templates = planning.templates + template), nowMs), template)
    }

    /** The template editor's save: slots normalised into task order. */
    fun saveTemplate(state: RecordState, name: String, slots: List<FocusTemplateSlot>, nowMs: Double): Planned<FocusTemplate?> {
        val trimmed = name.trim()
        val tasks = FocusTemplates.tasks(slots)
        if (!env.isAuthorized || trimmed.isEmpty() || tasks.isEmpty()) return Planned(state, null)
        val template = FocusTemplate(env.newId(), trimmed, FocusTemplates.slots(tasks, env::newId), nowMs, nowMs)
        val planning = planning(state)
        return Planned(persist(state, planning.copy(templates = planning.templates + template), nowMs), template)
    }

    /** Edits a template and refills the days still linked to it; history and detached days stay. */
    fun updateTemplate(state: RecordState, templateID: String, name: String, slots: List<FocusTemplateSlot>, nowMs: Double): Planned<Boolean> {
        val trimmed = name.trim()
        if (!env.isAuthorized || trimmed.isEmpty()) return Planned(state, false)
        val planning = planning(state)
        val index = planning.templates.indexOfFirst { it.id == templateID }
        if (index < 0) return Planned(state, false)
        val normalized = FocusTemplates.slots(FocusTemplates.tasks(slots), env::newId)
        val old = planning.templates[index]
        if (old.name == trimmed && old.slots == normalized) return Planned(state, true)
        val templates = planning.templates.toMutableList().also { it[index] = old.copy(name = trimmed, slots = normalized, updatedAtMs = nowMs) }
        val s = reflowLinked(persist(state, planning.copy(templates = templates), nowMs), nowMs, templateID)
        return Planned(s, true)
    }

    fun setDefaultTemplate(state: RecordState, templateID: String?, nowMs: Double): RecordState {
        val planning = planning(state)
        return persist(state, planning.copy(defaultTemplateID = templateID?.takeIf { id -> planning.templates.any { it.id == id } }), nowMs)
    }

    fun deleteTemplate(state: RecordState, templateID: String, nowMs: Double): RecordState {
        val planning = planning(state)
        return persist(state, planning.copy(
            templates = planning.templates.filter { it.id != templateID },
            defaultTemplateID = planning.defaultTemplateID?.takeIf { it != templateID },
        ), nowMs)
    }

    /** Whether the day's plan is still exactly this template's placement, tasks and provenance included. */
    private fun templatePlanMatches(state: RecordState, planning: PlanningState, template: FocusTemplate, blocks: List<FocusWorkBlock>, key: String): Boolean {
        val plan = planning.plans[key]?.takeIf { it.appliedTemplateID == template.id } ?: return false
        val expected = FocusTemplates.placedSlots(template, blocks).mapNotNull { slot ->
            val block = blocks.getOrNull(slot.blockIndex) ?: return@mapNotNull null
            if (slot.kind == FocusPlanBlockKind.BREAK_TIME || block.kind == FocusPlanBlockKind.TASK) slot to block else null
        }
        if (plan.assignments.size != expected.size) return false
        for ((slot, block) in expected) {
            val assignment = plan.assignments.firstOrNull { it.blockStartAtMs == block.startAtMs }?.takeIf { it.kind == slot.kind } ?: return false
            if (slot.kind != FocusPlanBlockKind.TASK) {
                if (assignment.taskID != null) return false
                continue
            }
            val task = assignment.taskID?.let { id -> state.focusTasks.firstOrNull { it.id == id } } ?: return false
            if (task.deletedAtMs != null || task.templateID != template.id || task.templateTaskKey != slot.taskKey || task.plannedForDate != key) return false
            if (assignment.taskTitle != task.title || assignment.taskIcon != task.icon) return false
            if ((slot.taskTitle != null && slot.taskTitle != task.title) || (slot.taskIcon != null && slot.taskIcon != task.icon)) return false
        }
        return true
    }

    /** The task this template made for this shift, live rows first; a soft-deleted one is revived rather than duplicated. */
    private fun reusableTemplateTask(state: RecordState, template: FocusTemplate, slot: FocusTemplateSlot, key: String, block: FocusWorkBlock, includingCompleted: Boolean): FocusTask? =
        state.focusTasks.filter { task ->
            task.templateID == template.id && (includingCompleted || task.completedAtMs == null) && task.plannedForDate == key &&
                if (slot.taskKey != null) task.templateTaskKey == slot.taskKey
                else task.templateTaskKey == null && task.scheduledStartAtMs == block.startAtMs.toDouble()
        }.sortedWith(compareBy<FocusTask> { it.deletedAtMs != null }.thenBy { it.createdAtMs }.thenBy { it.id }).firstOrNull()

    /**
     * Lays a template onto a shift. Reapplying an unchanged template is a true
     * no-op. With [preservingStartedBlocks] (a reflow), blocks already past or
     * under a running session keep their assignments.
     */
    fun applyTemplate(state: RecordState, templateID: String, nowMs: Double, shift: FocusShift? = null, preservingStartedBlocks: Boolean = false): Planned<Boolean> {
        val planning0 = planning(state)
        val template = planning0.templates.firstOrNull { it.id == templateID } ?: return Planned(state, false)
        val current = shift?.let { env.shift(it.startAtMs) } ?: canvasShift(nowMs)?.first
        if (!env.isAuthorized || current == null) return Planned(state, false)
        val blocks = blocks(current, state)
        val key = dayKey(current.startAtMs)
        val placed = FocusTemplates.placedSlots(template, blocks)
        if (templatePlanMatches(state, planning0, template, blocks, key)) return Planned(state, true)

        val previous = planning0.plans[key]?.assignments.orEmpty()
        val previousTaskIDs = previous.mapNotNull { it.taskID }.toSet()
        val activeEnd = engine.activeSession(state)?.plannedEndAtMs?.toLong()
        val protected = blocks.filter { preservingStartedBlocks && (it.endAtMs <= nowMs || (activeEnd != null && it.startAtMs < activeEnd)) }.map { it.startAtMs }.toSet()
        val materialized = HashMap<String, FocusTask>()
        val assignments = previous.filter { it.blockStartAtMs in protected }.toMutableList()
        var s = state
        for (slot in placed) {
            val block = blocks.getOrNull(slot.blockIndex) ?: continue
            if (block.startAtMs in protected) continue
            // A task never replaces automatic recovery; a user break may occupy either kind.
            if (slot.kind != FocusPlanBlockKind.BREAK_TIME && block.kind != FocusPlanBlockKind.TASK) continue
            if (slot.kind == FocusPlanBlockKind.BREAK_TIME) {
                assignments += FocusPlanAssignment(block.startAtMs, FocusPlanBlockKind.BREAK_TIME, null, null, null)
                continue
            }
            val group = slot.taskKey ?: "legacy-slot-${slot.blockIndex}"
            val task = materialized[group] ?: run {
                val matching = slot.taskKey?.let { k -> placed.count { it.kind == FocusPlanBlockKind.TASK && it.taskKey == k } } ?: 1
                val reusable = reusableTemplateTask(s, template, slot, key, block, preservingStartedBlocks)
                val made = if (reusable != null) {
                    val upcoming = if (slot.taskKey == null) 1 else placed.count { c ->
                        c.kind == FocusPlanBlockKind.TASK && c.taskKey == slot.taskKey && blocks.getOrNull(c.blockIndex)?.let { it.startAtMs !in protected } == true
                    }
                    var revived = reusable.copy(
                        title = slot.taskTitle ?: defaultTaskTitle, icon = slot.taskIcon ?: FocusTaskIcon.FOCUS, deletedAtMs = null,
                        plannedForDate = key, scheduledStartAtMs = block.startAtMs.toDouble(),
                    )
                    revived = revived.copy(estimatedPomodoros = maxOf(1, matching, engine.completedBlocks(s, revived) + if (preservingStartedBlocks) upcoming else 0))
                    if (preservingStartedBlocks) revived = revived.copy(completedAtMs = null)
                    s = engine.upsertTask(s, revived, nowMs)
                    s.focusTasks.first { it.id == revived.id }
                } else {
                    val added = addTask(s, slot.taskTitle ?: defaultTaskTitle, maxOf(1, matching), nowMs, current.startAtMs, block.startAtMs.toDouble(), slot.taskIcon ?: FocusTaskIcon.FOCUS)
                    s = engine.upsertTask(added.state, added.value.copy(templateID = template.id, templateTaskKey = slot.taskKey), nowMs)
                    s.focusTasks.first { it.id == added.value.id }
                }
                materialized[group] = made
                made
            }
            assignments += FocusPlanAssignment(block.startAtMs, FocusPlanBlockKind.TASK, task.id, task.title, task.icon)
        }
        val planning1 = planning(s)
        val nextPlanning = planning1.copy(
            plans = planning1.plans + (key to FocusDayPlan(key, current.startAtMs.toLong(), assignments.sortedBy { it.blockStartAtMs }, template.id)),
            autoAppliedDayKeys = planning1.autoAppliedDayKeys + key,
        )
        val materializedIDs = assignments.mapNotNull { it.taskID }.toSet()
        s = persist(s, nextPlanning, nowMs)
        s = releaseTemplateTasks(s, nextPlanning, previousTaskIDs, nowMs, preserving = materializedIDs)
        for (taskID in previousTaskIDs + materializedIDs) {
            if (s.focusTasks.firstOrNull { it.id == taskID }?.deletedAtMs == null) s = refreshTaskSchedule(s, nextPlanning, taskID, nowMs)
        }
        return Planned(s, assignments.isNotEmpty())
    }

    /** Refills only attached days from today on; detached (hand-edited) days and history stay put. */
    fun reflowLinked(state: RecordState, nowMs: Double, templateID: String? = null): RecordState {
        val active = env.shift(nowMs)
        val firstDay = dayKey(active?.startAtMs ?: nowMs)
        var s = state
        val linked = planning(state).plans.values.filter { it.dayKey >= firstDay && it.appliedTemplateID != null && (templateID == null || it.appliedTemplateID == templateID) }
        for (plan in linked) {
            val template = planning(s).templates.firstOrNull { it.id == plan.appliedTemplateID } ?: continue
            val shift = if (active != null && dayKey(active.startAtMs) == plan.dayKey) active else env.shift(startOfDay(plan.dayKey) + (23 * 60 + 59) * 60_000.0)
            if (shift == null || dayKey(shift.startAtMs) != plan.dayKey) continue
            s = applyTemplate(s, template.id, nowMs, shift, preservingStartedBlocks = true).state
        }
        return s
    }

    /** Applies the default template once per shift, and never over a plan the user already drew. */
    fun applyDefaultTemplateIfNeeded(state: RecordState, nowMs: Double): Planned<Boolean> {
        if (!env.isAuthorized) return Planned(state, false)
        val current = canvasShift(nowMs)?.first ?: return Planned(state, false)
        val key = dayKey(current.startAtMs)
        val planning = planning(state)
        if (key in planning.autoAppliedDayKeys) return Planned(state, false)
        if (planning.plans[key]?.assignments?.isNotEmpty() == true) {
            return Planned(persist(state, planning.copy(autoAppliedDayKeys = planning.autoAppliedDayKeys + key), nowMs), false)
        }
        val template = planning.defaultTemplateID?.let { id -> planning.templates.firstOrNull { it.id == id } } ?: return Planned(state, false)
        return applyTemplate(state, template.id, nowMs)
    }

    fun detachTemplate(state: RecordState, nowMs: Double): RecordState {
        val shift = canvasShift(nowMs)?.first ?: return state
        val key = dayKey(shift.startAtMs)
        val planning = planning(state)
        val plan = planning.plans[key]?.takeIf { it.appliedTemplateID != null } ?: return state
        return persist(state, planning.copy(plans = planning.plans + (key to plan.copy(appliedTemplateID = null)), autoAppliedDayKeys = planning.autoAppliedDayKeys + key), nowMs)
    }

    fun appliedTemplate(state: RecordState, nowMs: Double): FocusTemplate? {
        val shift = canvasShift(nowMs)?.first ?: return null
        val planning = planning(state)
        val id = planning.plans[dayKey(shift.startAtMs)]?.appliedTemplateID ?: return null
        return planning.templates.firstOrNull { it.id == id }
    }

    /** The focus and recovery blocks of the shift the canvas draws (iOS `focusTemplateBlocks`). */
    fun templateBlocks(state: RecordState, nowMs: Double): List<FocusWorkBlock> =
        canvasShift(nowMs)?.first?.let { blocks(it, state) }.orEmpty()

    /**
     * Today's task order and estimates without the day's clock times (iOS
     * `focusTemplateDraftFromToday`): what the usual-day editor starts from.
     */
    fun templateDraftFromToday(state: RecordState, nowMs: Double): List<FocusTemplateSlot> {
        val shift = canvasShift(nowMs)?.first ?: return emptyList()
        val assignments = planning(state).plans[dayKey(shift.startAtMs)]?.assignments.orEmpty()
        val keys = HashMap<String, String>()
        return blocks(shift, state).mapNotNull { block ->
            if (block.kind != FocusPlanBlockKind.TASK) return@mapNotNull null
            val assignment = assignments.firstOrNull { it.blockStartAtMs == block.startAtMs } ?: return@mapNotNull null
            FocusTemplateSlot(block.index, assignment.kind, assignment.taskID?.let { keys.getOrPut(it) { env.newId() } }, assignment.taskTitle, assignment.taskIcon)
        }
    }

    /** Whole tasks that fit this shift, and the rounds dropped from the tail. */
    fun templateFit(state: RecordState, templateID: String, nowMs: Double): Pair<Int, Int> {
        val template = planning(state).templates.firstOrNull { it.id == templateID } ?: return 0 to 0
        val fits = FocusTemplates.placedSlots(template, templateBlocks(state, nowMs)).size
        return fits to (FocusTemplates.tasks(template.slots).sumOf { it.pomodoros } - fits)
    }

    // Favourites

    fun favorites(state: RecordState) = FocusPlanner.sortedTasks(state.focusTasks.filter { it.deletedAtMs == null && it.isFavorite })

    fun savedFavorite(state: RecordState, title: String, icon: FocusTaskIcon) = favorites(state).firstOrNull { it.title == title && it.icon == icon }

    /** A library-only task has no planned day: it appears in the picker, not in today's work. */
    fun saveFavorite(state: RecordState, title: String, pomodoros: Int, icon: FocusTaskIcon, nowMs: Double): RecordState {
        if (!env.isAuthorized) return state
        savedFavorite(state, title, icon)?.let { return engine.upsertTask(state, it.copy(estimatedPomodoros = maxOf(1, pomodoros)), nowMs) }
        val id = env.newId()
        return engine.upsertTask(state, FocusTask(id, nowMs, null, null, title, maxOf(1, pomodoros), icon, true, null, null, 0, nowMs, 0, id, null, null), nowMs)
    }

    /** Un-favouriting a library-only task deletes it; a planned task just loses the star. */
    fun toggleFavorite(state: RecordState, taskID: String, nowMs: Double): RecordState {
        val task = state.focusTasks.firstOrNull { it.id == taskID && it.deletedAtMs == null } ?: return state
        var next = task.copy(isFavorite = !task.isFavorite)
        if (!next.isFavorite && next.plannedForDate == null) next = next.copy(deletedAtMs = nowMs)
        return engine.upsertTask(state, next, nowMs)
    }

    // Editing tasks

    /** Completed and running rounds cannot be removed by lowering an estimate. */
    fun protectedPomodoros(state: RecordState, task: FocusTask, nowMs: Double): Int {
        val active = engine.activeSession(state)
        val running = active?.takeIf { it.taskID == task.id && it.kind == FocusSessionKind.FOCUS }
        val runningEnd = active?.plannedEndAtMs?.toLong()
        val fixed = canvas(state, nowMs).blocks.count { it.taskID == task.id && (it.state == FocusDayCanvas.State.PAST || (runningEnd != null && it.startAtMs < runningEnd)) }
        return maxOf(fixed, engine.completedBlocks(state, task) + if (running == null) 0 else 1)
    }

    /** The task's blocks after an estimate change, or null when the shift cannot hold them. */
    fun editedTaskBlocks(state: RecordState, task: FocusTask, pomodoros: Int, nowMs: Double): List<FocusDayCanvas.Block>? {
        val canvas = canvas(state, nowMs)
        val owned = canvas.blocks.filter { it.taskID == task.id }
        val consumed = protectedPomodoros(state, task, nowMs)
        if (pomodoros < maxOf(1, consumed)) return null
        if (owned.isEmpty()) return emptyList()
        val runningEnd = engine.activeSession(state)?.plannedEndAtMs?.toLong()
        val fixed = owned.filter { it.state == FocusDayCanvas.State.PAST || (runningEnd != null && it.startAtMs < runningEnd) }
        val editable = canvas.blocks.filter { it.isEditable && (runningEnd == null || it.startAtMs >= runningEnd) }
        val start = editable.firstOrNull { it.taskID == task.id }?.startAtMs ?: editable.firstOrNull { !it.hasAssignment }?.startAtMs
        val remaining = pomodoros - consumed
        val next = start?.let { FocusChain.projectedBlocks(task.id, remaining, editable, it) }.orEmpty()
        if (next.size != remaining) return null
        return fixed + next
    }

    fun editTask(state: RecordState, taskID: String, title: String, icon: FocusTaskIcon, pomodoros: Int, isFavorite: Boolean, nowMs: Double): Planned<Boolean> {
        val trimmed = title.trim()
        val task = state.focusTasks.firstOrNull { it.id == taskID && it.deletedAtMs == null }
        if (!env.isAuthorized || trimmed.isEmpty() || task == null) return Planned(state, false)
        val oldFavorite = savedFavorite(state, task.title, task.icon)
        val changed = task.title != trimmed || task.icon != icon || task.estimatedPomodoros != pomodoros
        var planning = planning(state)
        var next = task
        if (task.estimatedPomodoros != pomodoros) {
            val blocks = editedTaskBlocks(state, task, pomodoros, nowMs) ?: return Planned(state, false)
            val shift = canvasShift(nowMs)?.first ?: return Planned(state, false)
            val key = dayKey(shift.startAtMs)
            val plan = planning.plans[key]
            if (plan != null && plan.assignments.any { it.taskID == task.id }) {
                val assignments = plan.assignments.filter { it.taskID != task.id } +
                    blocks.map { FocusPlanAssignment(it.startAtMs, FocusPlanBlockKind.TASK, task.id, trimmed, icon) }
                planning = planning.copy(plans = planning.plans + (key to plan.copy(assignments = assignments)))
            }
            if (pomodoros > engine.completedBlocks(state, task)) next = next.copy(completedAtMs = null)
        }
        next = next.copy(title = trimmed, icon = icon, estimatedPomodoros = pomodoros, isFavorite = next.isFavorite && isFavorite)
        var s = engine.upsertTask(state, next, nowMs)
        if (changed) {
            planning = planning.copy(
                plans = planning.plans.mapValues { (key, plan) ->
                    if (plan.assignments.none { it.taskID == task.id }) plan
                    else plan.copy(
                        appliedTemplateID = null,
                        assignments = plan.assignments.map { if (it.taskID == task.id) it.copy(taskTitle = trimmed, taskIcon = icon) else it }.sortedBy { it.blockStartAtMs },
                    )
                },
                autoAppliedDayKeys = planning.autoAppliedDayKeys + planning.plans.filterValues { p -> p.assignments.any { it.taskID == task.id } }.keys,
            )
            s = persist(s, planning, nowMs)
            s = refreshTaskSchedule(s, planning, task.id, nowMs)
        } else {
            s = persist(s, planning, nowMs)
        }
        if (isFavorite) {
            s = when {
                oldFavorite != null && oldFavorite.id != task.id ->
                    engine.upsertTask(s, s.focusTasks.first { it.id == oldFavorite.id }.copy(title = trimmed, icon = icon, estimatedPomodoros = pomodoros), nowMs)
                oldFavorite == null -> saveFavorite(s, trimmed, pomodoros, icon, nowMs)
                else -> s
            }
        } else if (oldFavorite != null && oldFavorite.id != task.id) {
            s = toggleFavorite(s, oldFavorite.id, nowMs)
        }
        return Planned(s, true)
    }

    /** Clears the shift's plan: its tasks are deleted, favourites return to the library, a running block on that day stops. */
    fun clearDay(state: RecordState, nowMs: Double): RecordState {
        if (!env.isAuthorized) return state
        val shift = canvasShift(nowMs)?.first ?: return state
        val key = dayKey(shift.startAtMs)
        val planning = planning(state)
        val assigned = planning.plans[key]?.assignments?.mapNotNull { it.taskID }?.toSet().orEmpty()
        val tasks = state.focusTasks.filter { it.deletedAtMs == null && (it.id in assigned || it.plannedForDate == key) }
        var s = state
        engine.activeSession(s)?.takeIf { it.shiftAnchorDate == key }?.let { s = engine.stop(s, FocusEndReason.STOPPED_BY_USER, nowMs).state }
        s = persist(s, planning.copy(plans = planning.plans + (key to FocusDayPlan(key, shift.startAtMs.toLong(), emptyList(), null)), autoAppliedDayKeys = planning.autoAppliedDayKeys + key), nowMs)
        for (task in tasks) {
            s = engine.upsertTask(s, if (task.isFavorite) task.copy(plannedForDate = null, scheduledStartAtMs = null) else task.copy(deletedAtMs = nowMs), nowMs)
        }
        return s
    }

    /** Soft-deletes a task (never the running one) and removes it from every plan. */
    fun deleteTask(state: RecordState, taskID: String, nowMs: Double): Planned<Boolean> {
        val task = state.focusTasks.firstOrNull { it.id == taskID && it.deletedAtMs == null }
        if (task == null || engine.activeSession(state)?.taskID == taskID) return Planned(state, false)
        var s = engine.upsertTask(state, task.copy(deletedAtMs = nowMs), nowMs)
        val planning = planning(s)
        val touched = planning.plans.filterValues { p -> p.assignments.any { it.taskID == taskID } }
        s = persist(s, planning.copy(
            plans = planning.plans + touched.mapValues { (_, p) -> p.copy(assignments = p.assignments.filter { it.taskID != taskID }, appliedTemplateID = null) },
            autoAppliedDayKeys = planning.autoAppliedDayKeys + touched.keys,
        ), nowMs)
        return Planned(s, true)
    }

    // Placement

    /** Blocks a new or extended task would take from [startingAt]: the same projection for preview and save. */
    fun creationBlocks(state: RecordState, pomodoros: Int, startingAt: Long, nowMs: Double, taskID: String? = null): List<FocusDayCanvas.Block> {
        val canvas = canvas(state, nowMs)
        if (canvas.blocks.none { it.startAtMs == startingAt && it.isEditable }) return emptyList()
        return FocusChain.projectedBlocks(taskID ?: "", pomodoros, canvas.blocks, startingAt)
    }

    fun place(state: RecordState, taskID: String, pomodoros: Int, startingAt: Long, nowMs: Double, additionalPomodoros: Int? = null, makeFavorite: Boolean = false): Planned<FocusPlacement> {
        if (!env.isAuthorized) return Planned(state, FocusPlacement.Locked)
        var task = state.focusTasks.firstOrNull { it.id == taskID && it.deletedAtMs == null } ?: return Planned(state, FocusPlacement.NoShift)
        if (additionalPomodoros != null) task = task.copy(estimatedPomodoros = engine.completedBlocks(state, task) + maxOf(1, additionalPomodoros))
        if (makeFavorite) task = task.copy(isFavorite = true)
        var s = engine.upsertTask(state, task, nowMs)
        val blocks = creationBlocks(s, pomodoros, startingAt, nowMs, task.id)
        val first = blocks.firstOrNull() ?: return Planned(s, FocusPlacement.AddedUnscheduled(task.id))
        for (block in blocks) s = assign(s, task.id, block.startAtMs, nowMs).state
        return Planned(s, FocusPlacement.Placed(task.id, first.startAtMs))
    }

    /** One tap: make today's task and put it (or all its rounds) in the next empty block. */
    fun createInNextEmptyBlock(state: RecordState, title: String, nowMs: Double, pomodoros: Int = 1, icon: FocusTaskIcon = FocusTaskIcon.FOCUS, isFavorite: Boolean = false, scheduleAllPomodoros: Boolean = false): Planned<FocusPlacement> {
        val trimmed = title.trim()
        if (!env.isAuthorized) return Planned(state, FocusPlacement.Locked)
        if (trimmed.isEmpty()) return Planned(state, FocusPlacement.NoShift)
        val shift = canvasShift(nowMs)?.first ?: return Planned(state, FocusPlacement.NoShift)
        var s = detachTemplate(state, nowMs)
        val target = canvas(s, nowMs).nextEmptyBlock
        val added = addTask(s, trimmed, pomodoros, nowMs, shift.startAtMs, icon = icon, isFavorite = isFavorite)
        s = added.state
        if (target == null) return Planned(s, FocusPlacement.AddedUnscheduled(added.value.id))
        return place(s, added.value.id, if (scheduleAllPomodoros) added.value.estimatedPomodoros else 1, target.startAtMs, nowMs)
    }

    fun placeFavoriteInNextEmptyBlock(state: RecordState, favoriteID: String, nowMs: Double): Planned<FocusPlacement> {
        if (!env.isAuthorized) return Planned(state, FocusPlacement.Locked)
        val favorite = state.focusTasks.firstOrNull { it.id == favoriteID && it.deletedAtMs == null } ?: return Planned(state, FocusPlacement.NoShift)
        return createInNextEmptyBlock(state, favorite.title, nowMs, favorite.estimatedPomodoros, favorite.icon)
    }

    /** Block-first creation: the block is chosen, the task is made inside it. */
    fun createInBlock(state: RecordState, title: String, blockStartAtMs: Long, nowMs: Double, icon: FocusTaskIcon = FocusTaskIcon.FOCUS, pomodoros: Int = 1, isFavorite: Boolean = false, scheduleAllPomodoros: Boolean = false): Planned<FocusPlacement> {
        val trimmed = title.trim()
        if (!env.isAuthorized) return Planned(state, FocusPlacement.Locked)
        val shift = canvasShift(nowMs)?.first
        if (trimmed.isEmpty() || shift == null) return Planned(state, FocusPlacement.NoShift)
        val detached = detachTemplate(state, nowMs)
        val added = addTask(detached, trimmed, pomodoros, nowMs, shift.startAtMs, icon = icon, isFavorite = isFavorite)
        return place(added.state, added.value.id, if (scheduleAllPomodoros) added.value.estimatedPomodoros else 1, blockStartAtMs, nowMs)
    }

    /** Assigns by block key on the shift the canvas is drawing (after clock-off, the next one). */
    fun assign(state: RecordState, taskID: String, blockStartAtMs: Long, nowMs: Double): Planned<FocusPlacement> {
        if (!env.isAuthorized) return Planned(state, FocusPlacement.Locked)
        if (state.focusTasks.none { it.id == taskID && it.deletedAtMs == null }) return Planned(state, FocusPlacement.NoShift)
        val shift = canvasShift(nowMs)?.first ?: return Planned(state, FocusPlacement.NoShift)
        gridBlock(state, shift, blockStartAtMs) ?: return Planned(state, FocusPlacement.NoShift)
        return Planned(assignBlock(state, blockStartAtMs, taskID, shift, nowMs), FocusPlacement.Placed(taskID, blockStartAtMs))
    }

    fun markBlockAsBreak(state: RecordState, blockStartAtMs: Long, nowMs: Double): RecordState {
        if (!env.isAuthorized) return state
        val shift = canvasShift(nowMs)?.first ?: return state
        return assignBreak(state, blockStartAtMs, shift, nowMs)
    }

    fun clearCanvasBlock(state: RecordState, blockStartAtMs: Long, nowMs: Double): RecordState {
        if (!env.isAuthorized) return state
        val shift = canvasShift(nowMs)?.first ?: return state
        gridBlock(state, shift, blockStartAtMs) ?: return state
        return clearBlock(state, blockStartAtMs, shift, nowMs)
    }

    /** Where one more block for a task would go; the Lock Screen's plus and the write ask the same question. */
    fun continuationTarget(state: RecordState, taskID: String, nowMs: Double, afterMs: Double? = null): Result<Pair<FocusWorkBlock, FocusShift>> {
        fun fail(e: FocusExtensionError) = Result.failure<Pair<FocusWorkBlock, FocusShift>>(IllegalStateException(e.name))
        val shift = env.shift(nowMs)
        if (!env.isAuthorized || state.focusTasks.none { it.id == taskID && it.deletedAtMs == null } || shift == null || nowMs >= shift.endAtMs) return fail(FocusExtensionError.NO_ROOM)
        val blocks = blocks(shift, state)
        val assignments = planning(state).plans[dayKey(shift.startAtMs)]?.assignments.orEmpty()
        val lastAssignedEnd = blocks.filter { b -> assignments.any { it.taskID == taskID && it.blockStartAtMs == b.startAtMs } }.maxOfOrNull { it.endAtMs.toDouble() }
        val runningEnd = engine.activeSession(state)?.takeIf { it.taskID == taskID }?.plannedEndAtMs
        val boundary = maxOf(afterMs ?: nowMs, maxOf(nowMs, maxOf(lastAssignedEnd ?: nowMs, runningEnd ?: nowMs)))
        val target = blocks.firstOrNull { it.kind == FocusPlanBlockKind.TASK && it.startAtMs >= boundary }
        if (target == null || target.durationMinutes < settings(state).focusMinutes ||
            shift.segments.none { it.startAtMs <= boundary && target.endAtMs <= it.endAtMs }
        ) return fail(FocusExtensionError.NO_ROOM)
        if (assignments.any { it.blockStartAtMs == target.startAtMs } ||
            state.focusTasks.any { it.id != taskID && it.deletedAtMs == null && it.completedAtMs == null && it.scheduledStartAtMs?.let { s -> s >= target.startAtMs && s < target.endAtMs } == true }
        ) return fail(FocusExtensionError.CONFLICT)
        return Result.success(target to shift)
    }

    /** Continues the same task one block further without moving another task or touching a template. */
    fun addOneBlock(state: RecordState, taskID: String, nowMs: Double): Planned<Result<Long>> {
        val target = continuationTarget(state, taskID, nowMs)
        val (block, shift) = target.getOrElse { return Planned(state, Result.failure(it)) }
        val task = state.focusTasks.first { it.id == taskID }
        val estimate = maxOf(task.estimatedPomodoros, engine.completedBlocks(state, task)) + 1
        var s = assignBlock(state, block.startAtMs, taskID, shift, nowMs)
        s.focusTasks.firstOrNull { it.id == taskID }?.let { s = engine.upsertTask(s, it.copy(estimatedPomodoros = estimate, completedAtMs = null), nowMs) }
        return Planned(s, Result.success(block.startAtMs))
    }

    /** The task continuation is offered for: the running focus block's, else the shift's latest. */
    fun continuationTaskID(state: RecordState, nowMs: Double): String? {
        if (!env.isAuthorized) return null
        engine.activeSession(state)?.takeIf { it.kind == FocusSessionKind.FOCUS }?.let { return it.taskID }
        val shift = env.shift(nowMs)?.takeIf { nowMs < it.endAtMs } ?: return null
        return state.focusSessions.filter { it.kind == FocusSessionKind.FOCUS && it.startedAtMs >= shift.startAtMs && it.startedAtMs <= nowMs }
            .maxByOrNull { it.startedAtMs }?.taskID
    }

    // Plan-driven sessions

    /**
     * Assignment is authorisation: today's remaining assigned blocks become
     * queued sessions with identities derived from the block, so a device
     * that wakes late or twice records each block once. Returns the queue
     * (local state, never synced).
     */
    fun scheduledSessions(state: RecordState, previous: List<FocusSession>, nowMs: Double): List<FocusSession> {
        if (!env.isAuthorized) return emptyList()
        return canvas(state, nowMs).blocks.mapNotNull { block ->
            val taskID = block.taskID
            if (block.kind != FocusPlanBlockKind.TASK || block.isUserBreak || block.endAtMs <= nowMs || taskID == null) return@mapNotNull null
            val task = state.focusTasks.firstOrNull { it.id == taskID }
            if (task == null || task.completedAtMs != null || task.deletedAtMs != null) return@mapNotNull null
            val start = block.startAtMs.toDouble()
            val end = block.endAtMs.toDouble()
            if (state.focusSessions.any { it.kind == FocusSessionKind.FOCUS && it.startedAtMs < end && it.plannedEndAtMs > start }) return@mapNotNull null
            previous.firstOrNull { it.taskID == taskID && it.startedAtMs == start && it.plannedEndAtMs == end }?.let { return@mapNotNull it }
            val actualStart = maxOf(start, nowMs)
            if (end - actualStart < 60_000) return@mapNotNull null
            val day = dayKey(actualStart)
            FocusSession(
                FocusSessionIdentity.block(taskID, block.startAtMs, block.endAtMs), taskID, day, actualStart, end, null, null, nowMs, 0, env.newId(),
                FocusSessionKind.FOCUS, FoundationCompat.timeZoneIdentifier(env.recordsTimeZone) ?: env.recordsTimeZone, day, null, FocusEndReason.COMPLETED,
            )
        }
    }

    /**
     * Records queued starts that have arrived, at their own absolute times, so
     * waking late cannot restart a block. A block the user already started by
     * hand keeps its time. Returns the archive, the remaining queue and the
     * next action.
     */
    fun restoreScheduled(state: RecordState, queue: List<FocusSession>, next: FocusNextAction, nowMs: Double): Triple<RecordState, List<FocusSession>, FocusNextAction> {
        var s = state
        var action = next
        for (session in queue.filter { it.startedAtMs <= nowMs }) {
            val task = s.focusTasks.firstOrNull { it.id == session.taskID }
            if (!env.isAuthorized || task == null || task.deletedAtMs != null || task.completedAtMs != null) continue
            if (s.focusSessions.any { it.id == session.id }) continue
            val stillPlanned = canvas(s, session.startedAtMs).blocks.any {
                it.taskID == session.taskID && !it.isUserBreak && it.startAtMs <= session.startedAtMs && it.endAtMs.toDouble() == session.plannedEndAtMs
            }
            if (!stillPlanned) continue
            while (true) {
                val running = engine.activeSession(s)
                if (running == null || running.plannedEndAtMs > session.startedAtMs) break
                val step = engine.finishElapsed(s, action, session.startedAtMs)
                s = step.state
                action = step.nextAction
            }
            engine.activeSession(s)?.let { running ->
                if (running.kind == FocusSessionKind.FOCUS) return@let null
                val step = engine.stop(s, FocusEndReason.STOPPED_AT_BOUNDARY, session.startedAtMs)
                s = step.state
                action = step.nextAction
                Unit
            } ?: if (engine.activeSession(s)?.kind == FocusSessionKind.FOCUS) continue else Unit
            s = engine.upsertSession(s, session, session.startedAtMs)
            action = FocusNextAction.NONE
            if (session.plannedEndAtMs <= nowMs) {
                val step = engine.finishElapsed(s, action, nowMs)
                s = step.state
                action = step.nextAction
            }
        }
        return Triple(s, queue.filter { it.startedAtMs > nowMs }, action)
    }
}
