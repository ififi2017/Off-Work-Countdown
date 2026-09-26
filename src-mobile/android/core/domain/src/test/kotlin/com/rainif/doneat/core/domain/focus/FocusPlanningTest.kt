package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.FocusTask
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.FocusTemplateSlot
import com.rainif.doneat.core.domain.records.FocusTimerSettings
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.WallClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

/**
 * The planning behaviours named by iOS `FocusCanvasTests`,
 * `FocusTaskEditingTests` and the template cases in `FocusStoreTests`,
 * restated against [FocusPlanning] on the same 09:00–17:00 day with lunch.
 */
class FocusPlanningTest {
    private val zone = "Asia/Shanghai"
    private val civil = CivilZone(ZoneId.of(zone))
    private fun at(day: String, hour: Int, minute: Int = 0) = civil.utcMs(ExtendedScheduleResolver.dayNumber(day)!!, WallClock(hour, minute))
    private val monday = "2026-08-31"
    private val tuesday = "2026-09-01"
    private val nine05 = at(monday, 9, 5)

    /** Monday and Tuesday, 09:00–12:00 and 13:00–17:00. */
    private inner class Env : FocusEnvironment {
        var authorized = true
        var shortTuesday = false
        private var ids = 0
        private fun shiftOn(day: String): FocusShift {
            val short = shortTuesday && day == tuesday
            return FocusShift(
                if (short) listOf(ShiftSegment(at(day, 9), at(day, 11)))
                else listOf(ShiftSegment(at(day, 9), at(day, 12)), ShiftSegment(at(day, 13), at(day, 17))),
                at(day, 9), if (short) at(day, 11) else at(day, 17), 0.0,
                if (day == monday) at(tuesday, 9) else null, true,
            )
        }
        override fun shift(atMs: Double): FocusShift? {
            val day = listOf(monday, tuesday).firstOrNull { atMs >= at(it, 0) && atMs < at(it, 0) + 86_400_000 } ?: return null
            return shiftOn(day).let { it.copy(remainingMs = maxOf(0.0, it.endAtMs - atMs)) }
        }
        override fun scheduleEnabled(atMs: Double) = true
        override val overtimeEndAtMs: Double? = null
        override val isAuthorized get() = authorized
        override val recordsTimeZone = zone
        override val settings = DEFAULT_TIMER_SETTINGS
        override fun newId() = "00000000-0000-4000-8000-%012d".format(++ids)
    }

    private val env = Env()
    private val planning = FocusPlanning(env)
    private val engine = FocusEngine(env)

    private fun canvas(s: RecordState, now: Double = nine05) = planning.canvas(s, now)
    private fun shift(now: Double = nine05) = env.shift(now)!!
    private fun workBlocks(s: RecordState, now: Double = nine05) = planning.blocks(shift(now), s)
    private fun task(s: RecordState, id: String) = s.focusTasks.first { it.id == id }
    private fun assignmentAt(s: RecordState, startAtMs: Long, day: String = monday) =
        planning.planning(s).plans[day]?.assignments?.firstOrNull { it.blockStartAtMs == startAtMs }

    private fun make(s: RecordState, title: String, pomodoros: Int = 1, favorite: Boolean = false, now: Double = nine05) =
        planning.addTask(s, title, pomodoros, now, isFavorite = favorite)

    private fun completed(t: FocusTask, startMs: Double) = FocusSession(
        "00000000-0000-0000-0000-%012d".format(startMs.toLong() % 1_000_000_000_000), t.id, engine.dayKey(startMs), startMs, startMs + 25 * 60_000.0,
        startMs + 25 * 60_000.0, FocusEndReason.COMPLETED, startMs, 0, "T", FocusSessionKind.FOCUS, zone, engine.dayKey(startMs), null, FocusEndReason.COMPLETED,
    )

    private fun gridBreak() = workBlocks(RecordState()).first { it.kind == FocusPlanBlockKind.BREAK_TIME }

    private fun placedID(p: FocusPlacement) = (p as FocusPlacement.Placed).taskID

    /** A template of one "Original" task saved in the first work block, as the iOS fixture does. */
    private fun template(s: RecordState): Planned<com.rainif.doneat.core.domain.records.FocusTemplate> {
        val block = workBlocks(s).first { it.kind == FocusPlanBlockKind.TASK }
        val saved = planning.saveTemplate(s, "Daily", listOf(FocusTemplateSlot(block.index, FocusPlanBlockKind.TASK, env.newId(), "Original", FocusTaskIcon.WORK)), nine05)
        return Planned(saved.state, saved.value!!)
    }

    /**
     * One manual task in the first work block, captured as "Default" with the
     * grid's own first break (as iOS, whose break assignment there is a no-op).
     */
    private fun capturedTemplate(): Triple<RecordState, com.rainif.doneat.core.domain.records.FocusTemplate, List<FocusWorkBlock>> {
        var s = RecordState()
        val work = workBlocks(s).filter { it.kind == FocusPlanBlockKind.TASK }
        val source = make(s, "Deep work")
        s = planning.assignBlock(source.state, work[0].startAtMs, source.value.id, shift(), nine05)
        s = planning.assignBreak(s, gridBreak().startAtMs, shift(), nine05)
        val saved = planning.saveTemplateFromToday(s, "Default", nine05)
        return Triple(saved.state, saved.value!!, work)
    }

    // Canvas

    @Test fun theCanvasMarksPastCurrentAndFutureBlocksFromTheClockAlone() {
        val c = canvas(RecordState(), at(monday, 10, 5))
        val now = at(monday, 10, 5).toLong()
        val current = c.currentBlock!!
        assertTrue(current.startAtMs <= now && current.endAtMs > now)
        assertEquals(1, c.blocks.count { it.state == FocusDayCanvas.State.CURRENT })
        assertTrue(c.blocks.any { it.state == FocusDayCanvas.State.PAST })
        assertTrue(c.blocks.any { it.state == FocusDayCanvas.State.FUTURE })
        assertEquals(now, c.nowAtMs)
    }

    @Test fun breakAndPastBlocksAreNeverEditingTargets() {
        val c = canvas(RecordState())
        val breaks = c.blocks.filter { it.kind == FocusPlanBlockKind.BREAK_TIME }
        assertTrue(breaks.isNotEmpty())
        assertTrue(breaks.none { it.isEditable })
        assertTrue(c.blocks.filter { it.state == FocusDayCanvas.State.PAST }.none { it.isEditable })
    }

    @Test fun lunchAndTheLeftoverTailAreGapsThatNoBlockOverlaps() {
        val c = canvas(RecordState())
        assertTrue(c.gaps.any { it.kind == FocusDayCanvas.Gap.Kind.BETWEEN_SEGMENTS && it.startAtMs == at(monday, 12).toLong() && it.endAtMs == at(monday, 13).toLong() })
        assertTrue(c.gaps.any { it.kind == FocusDayCanvas.Gap.Kind.TAIL })
        for (gap in c.gaps) assertTrue(c.blocks.none { it.startAtMs < gap.endAtMs && it.endAtMs > gap.startAtMs })
    }

    @Test fun afterClockOffTheCanvasDrawsTheNextShiftAndWritesLandThere() {
        val evening = at(monday, 19)
        val c = canvas(RecordState(), evening)
        assertTrue(c.isNextShift)
        assertEquals(tuesday, c.dayKey)
        assertNull(c.nowAtMs)
        assertTrue(c.blocks.all { it.state == FocusDayCanvas.State.FUTURE })
        val placed = planning.createInNextEmptyBlock(RecordState(), "Tomorrow", evening)
        val block = (placed.value as FocusPlacement.Placed).blockStartAtMs
        assertEquals(at(tuesday, 9).toLong(), block)
        assertNotNull(assignmentAt(placed.state, block, tuesday))
        assertEquals(tuesday, task(placed.state, placedID(placed.value)).plannedForDate)
    }

    @Test fun densityKeepsAFocusBlockAboveTheHitTarget() {
        for (minutes in listOf(10, 15, 25, 45, 60)) {
            assertTrue(FocusDayCanvas.pointsPerHour(minutes) * minutes / 60 >= 44 - 1e-9)
        }
    }

    // Placement

    @Test fun oneTapOnAFavouriteLandsInTheNextEmptyBlockAsACopy() {
        val expected = canvas(RecordState()).nextEmptyBlock!!
        val favorite = planning.saveFavorite(RecordState(), "Weekly report", 3, FocusTaskIcon.FOCUS, nine05)
        val favID = planning.favorites(favorite).single().id
        assertNull(task(favorite, favID).plannedForDate)
        assertTrue(planning.tasksForPage(favorite, nine05).none { it.id == favID })
        val result = planning.placeFavoriteInNextEmptyBlock(favorite, favID, nine05)
        val id = placedID(result.value)
        assertEquals(expected.startAtMs, (result.value as FocusPlacement.Placed).blockStartAtMs)
        assertNotEquals(favID, id)
        assertEquals(3, task(result.state, id).estimatedPomodoros)
        assertEquals(favID, planning.savedFavorite(result.state, "Weekly report", FocusTaskIcon.FOCUS)?.id)
        val c = canvas(result.state)
        assertEquals("Weekly report", c.blocks.first { it.startAtMs == expected.startAtMs }.taskTitle)
        assertNotEquals(expected.startAtMs, c.nextEmptyBlock?.startAtMs)
    }

    @Test fun withNoEmptyBlockLeftTheTaskIsStillCreatedAndSaysSo() {
        var s = RecordState()
        var guard = 0
        while (canvas(s).nextEmptyBlock != null && guard < 40) s = planning.createInNextEmptyBlock(s, "Filler ${guard++}", nine05).state
        assertNull(canvas(s).nextEmptyBlock)
        s = planning.saveFavorite(s, "Extra", 1, FocusTaskIcon.FOCUS, nine05)
        val result = planning.placeFavoriteInNextEmptyBlock(s, planning.favorites(s).single().id, nine05)
        val id = (result.value as FocusPlacement.AddedUnscheduled).taskID
        assertFalse(canvas(result.state).tasks.first { it.id == id }.isScheduled)
    }

    @Test fun blockFirstCreationMakesTheTaskInsideTheBlock() {
        val target = canvas(RecordState()).nextEmptyBlock!!
        val result = planning.createInBlock(RecordState(), "Spec review", target.startAtMs, nine05)
        assertEquals(target.startAtMs, (result.value as FocusPlacement.Placed).blockStartAtMs)
        val c = canvas(result.state)
        assertEquals("Spec review", c.blocks.first { it.startAtMs == target.startAtMs }.taskTitle)
        assertTrue(c.tasks.any { it.title == "Spec review" && it.assignedBlocks == 1 })
    }

    @Test fun progressCountsScheduledBlocksAndLeavesTheManualEstimateAlone() {
        val made = make(RecordState(), "Deep work")
        val free = canvas(made.state).blocks.filter { it.isEditable && !it.isAssigned }
        var s = planning.assign(made.state, made.value.id, free[0].startAtMs, nine05).state
        s = planning.assign(s, made.value.id, free[1].startAtMs, nine05).state
        val row = canvas(s).tasks.first { it.id == made.value.id }
        assertEquals(2, row.assignedBlocks)
        assertEquals(1, row.estimatedBlocks)
        assertEquals(0, row.completedBlocks)
    }

    @Test fun aTaskForALaterDayIsOfferedAndFilesUnderTheShiftItLandsIn() {
        val made = planning.addTask(RecordState(), "Tomorrow's thing", 1, nine05, plannedForMs = at(tuesday, 9))
        assertTrue(planning.tasksForPage(made.state, nine05).any { it.id == made.value.id })
        val target = canvas(made.state).nextEmptyBlock!!
        val s = planning.assign(made.state, made.value.id, target.startAtMs, nine05).state
        assertEquals(monday, task(s, made.value.id).plannedForDate)
    }

    @Test fun quickAddSchedulesTheRequestedCountAroundAnOccupiedBlock() {
        for (duringBreak in listOf(false, true)) {
            val breakBlock = canvas(RecordState()).blocks.first { it.kind == FocusPlanBlockKind.BREAK_TIME }
            val now = if (duringBreak) breakBlock.startAtMs + 1_000.0 else nine05
            val c = canvas(RecordState(), now)
            val target = c.nextEmptyBlock!!
            val occupied = c.blocks.first { it.kind == FocusPlanBlockKind.TASK && it.startAtMs > target.startAtMs }
            var s = planning.createInBlock(RecordState(), "Keep this task", occupied.startAtMs, now).state
            val result = planning.createInNextEmptyBlock(s, "Three pomodoros", now, pomodoros = 3, scheduleAllPomodoros = true)
            s = result.state
            val id = placedID(result.value)
            val updated = canvas(s, now)
            assertEquals(target.startAtMs, (result.value as FocusPlacement.Placed).blockStartAtMs)
            assertEquals(3, updated.blocks.count { it.taskID == id })
            assertEquals("Keep this task", updated.blocks.first { it.startAtMs == occupied.startAtMs }.taskTitle)
            assertTrue(updated.blocks.filter { it.kind == FocusPlanBlockKind.BREAK_TIME }.all { it.taskID == null })
            assertEquals(3, task(s, id).estimatedPomodoros)
            assertNull(engine.activeSession(s))
            if (duringBreak) assertTrue(target.startAtMs >= breakBlock.endAtMs) else assertEquals(FocusDayCanvas.State.CURRENT, target.state)
        }
    }

    @Test fun creationBlocksSkipOccupiedBlocksAndCrossLunch() {
        val c = canvas(RecordState())
        val occupied = c.blocks.filter { it.kind == FocusPlanBlockKind.TASK }[1]
        val s = planning.createInBlock(RecordState(), "Other", occupied.startAtMs, nine05).state
        for (count in listOf(1, 3, 12)) {
            val projected = planning.creationBlocks(s, count, c.nextEmptyBlock!!.startAtMs, nine05)
            assertTrue(projected.none { it.startAtMs == occupied.startAtMs || it.kind != FocusPlanBlockKind.TASK })
            val placed = planning.createInNextEmptyBlock(s, "New", nine05, pomodoros = count, scheduleAllPomodoros = true)
            val id = placedID(placed.value)
            assertEquals(projected.map { it.startAtMs }, canvas(placed.state).blocks.filter { it.taskID == id }.map { it.startAtMs })
            if (count == 12) assertTrue("crosses lunch", projected.last().startAtMs >= at(monday, 13))
        }
    }

    @Test fun aBlockTurnedIntoABreakReadsAsABreakAndCanBeTurnedBack() {
        val target = canvas(RecordState()).nextEmptyBlock!!
        assertFalse(target.rendersAsBreak || target.hasAssignment)
        var s = planning.markBlockAsBreak(RecordState(), target.startAtMs, nine05)
        val converted = canvas(s).blocks.first { it.startAtMs == target.startAtMs }
        assertTrue(converted.isUserBreak && converted.rendersAsBreak && converted.hasAssignment && converted.isEditable)
        assertEquals(FocusPlanBlockKind.TASK, converted.kind)
        assertNotEquals(target.startAtMs, canvas(s).nextEmptyBlock?.startAtMs)
        s = planning.clearCanvasBlock(s, target.startAtMs, nine05)
        val cleared = canvas(s).blocks.first { it.startAtMs == target.startAtMs }
        assertFalse(cleared.isUserBreak || cleared.hasAssignment)
        assertEquals(target.startAtMs, canvas(s).nextEmptyBlock?.startAtMs)
    }

    @Test fun withoutAccessTheCanvasCarriesAShapeAndNoValues() {
        val target = canvas(RecordState()).nextEmptyBlock!!
        val s = planning.createInBlock(RecordState(), "Private", target.startAtMs, nine05).state
        env.authorized = false
        val locked = canvas(s)
        assertTrue(locked.isLocked)
        assertTrue(locked.blocks.isNotEmpty())
        assertTrue(locked.blocks.all { it.taskTitle == null && it.taskID == null })
        assertTrue(locked.tasks.isEmpty())
        assertEquals(FocusPlacement.Locked, planning.createInNextEmptyBlock(s, "Nope", nine05).value)
        assertSame(s, planning.markBlockAsBreak(s, target.startAtMs, nine05))
    }

    // Continuation

    @Test fun oneMoreRoundReopensTheSameTaskAndKeepsSessions() {
        val made = make(RecordState(), "Continue")
        val work = workBlocks(made.state).filter { it.kind == FocusPlanBlockKind.TASK }
        var s = planning.assign(made.state, made.value.id, work[0].startAtMs, nine05).state
        s = engine.upsertTask(s, task(s, made.value.id).copy(completedAtMs = nine05), nine05)
        val sessions = s.focusSessions
        val added = planning.addOneBlock(s, made.value.id, nine05)
        assertEquals(work[1].startAtMs, added.value.getOrThrow())
        val updated = task(added.state, made.value.id)
        assertNull(updated.completedAtMs)
        assertEquals(2, updated.estimatedPomodoros)
        assertEquals(sessions, added.state.focusSessions)
    }

    @Test fun oneMoreRoundCannotOverwriteAnotherTaskOrAUserBreak() {
        for (userBreak in listOf(false, true)) {
            val made = make(RecordState(), "Continue")
            val work = workBlocks(made.state).filter { it.kind == FocusPlanBlockKind.TASK }
            var s = planning.assign(made.state, made.value.id, work[0].startAtMs, nine05).state
            s = if (userBreak) planning.markBlockAsBreak(s, work[1].startAtMs, nine05) else planning.createInBlock(s, "Next task", work[1].startAtMs, nine05).state
            val result = planning.addOneBlock(s, made.value.id, nine05)
            assertEquals(FocusExtensionError.CONFLICT.name, result.value.exceptionOrNull()?.message)
            assertSame(s, result.state)
        }
    }

    @Test fun oneMoreRoundCannotJumpAcrossLunch() {
        val now = at(monday, 11, 35)
        val made = make(RecordState(), "Before lunch", now = now)
        val block = workBlocks(made.state, now).last { it.kind == FocusPlanBlockKind.TASK && it.startAtMs <= now }
        val s = planning.assign(made.state, made.value.id, block.startAtMs, now).state
        assertEquals(FocusExtensionError.NO_ROOM.name, planning.addOneBlock(s, made.value.id, now).value.exceptionOrNull()?.message)
    }

    // Templates

    @Test fun aSavedTemplateRecreatesTaskAndBreakAssignmentsAndLocksTheCadence() {
        val (s0, template, work) = capturedTemplate()
        // Every grid break is captured; only the one work block carries a task.
        assertEquals(1, template.slots.count { it.kind == FocusPlanBlockKind.TASK })
        assertEquals(workBlocks(RecordState()).count { it.kind == FocusPlanBlockKind.BREAK_TIME }, template.slots.count { it.kind == FocusPlanBlockKind.BREAK_TIME })
        var s = planning.clearBlock(s0, work[0].startAtMs, shift(), nine05)
        s = planning.clearBlock(s, gridBreak().startAtMs, shift(), nine05)
        val applied = planning.applyTemplate(s, template.id, nine05)
        assertTrue(applied.value)
        assertEquals(FocusPlanBlockKind.TASK, planning.assignment(applied.state, work[0], nine05)?.kind)
        assertEquals(FocusPlanBlockKind.BREAK_TIME, planning.assignment(applied.state, gridBreak(), nine05)?.kind)
        val refused = planning.updateTimerSettings(applied.state, FocusTimerSettings(40, 8, 20, 3), nine05)
        assertFalse(refused.value)
        assertSame(applied.state, refused.state)
    }

    @Test fun cadenceChangesAreAcceptedUntilATemplateExists() {
        val ok = planning.updateTimerSettings(RecordState(), FocusTimerSettings(30, 5, 15, 4), nine05)
        assertTrue(ok.value)
        assertEquals(30, planning.settings(ok.state).focusMinutes)
        val target = canvas(ok.state).nextEmptyBlock!!
        val s = planning.saveTemplateFromToday(planning.createInBlock(ok.state, "Anything", target.startAtMs, nine05).state, "Default", nine05).state
        assertFalse(planning.updateTimerSettings(s, FocusTimerSettings(45, 5, 15, 4), nine05).value)
    }

    @Test fun aManualBreakStaysOnTheDayInsteadOfBecomingATemplateTask() {
        // iOS FocusReviewRegressionTests.manualBreakStaysOnDayInsteadOfBecomingATemplateTask
        val target = planning.templateBlocks(RecordState(), nine05).first { it.kind == FocusPlanBlockKind.TASK }
        var s = planning.markBlockAsBreak(RecordState(), target.startAtMs, nine05)
        assertNull(planning.saveTemplate(s, "Only a break", planning.templateDraftFromToday(s, nine05), nine05).value)
        s = planning.createInNextEmptyBlock(s, "Writing", nine05).state
        val saved = planning.saveTemplate(s, "Tasks", planning.templateDraftFromToday(s, nine05), nine05)
        assertEquals(listOf("Writing"), FocusTemplates.tasks(saved.value!!.slots).map { it.title })
        assertTrue(canvas(saved.state).blocks.first().isUserBreak)
    }

    @Test fun theDraftFromTodayKeepsOrderAndRepeatsButNotClockTimes() {
        var s = planning.createInNextEmptyBlock(RecordState(), "Deep work", nine05, pomodoros = 2, scheduleAllPomodoros = true).state
        s = planning.createInNextEmptyBlock(s, "Email", nine05).state
        val tasks = FocusTemplates.tasks(planning.templateDraftFromToday(s, nine05))
        assertEquals(listOf("Deep work" to 2, "Email" to 1), tasks.map { it.title to it.pomodoros })
        // Keys are fresh: the template never points back at today's task rows.
        assertTrue(tasks.none { key -> s.focusTasks.any { it.id == key.taskKey } })
    }

    @Test fun remainingCapacityCountsAllTasksAndExcludesTheOneBeingEdited() {
        // iOS FocusTaskEditingTests.remainingCapacity
        val blocks = workBlocks(RecordState()).filter { it.kind == FocusPlanBlockKind.TASK }.take(3)
        val first = FocusTemplateTask("a", 0, "First", FocusTaskIcon.WORK, 2)
        val second = FocusTemplateTask("b", 1, "Second", FocusTaskIcon.STUDY, 1)
        assertEquals(1, FocusTemplates.remainingPomodoros(listOf(first), blocks))
        assertEquals(0, FocusTemplates.remainingPomodoros(listOf(first, second), blocks))
        assertEquals(2, FocusTemplates.remainingPomodoros(listOf(first, second), blocks, excluding = first.id))
        val oversized = first.copy(pomodoros = 10)
        assertEquals(0, FocusTemplates.remainingPomodoros(listOf(oversized, second), blocks))
        assertEquals(2, FocusTemplates.remainingPomodoros(listOf(oversized, second), blocks, excluding = oversized.id))
    }

    @Test fun reapplyingAnUnchangedTemplateIsATrueNoOp() {
        val (s0, template, _) = capturedTemplate()
        val applied = planning.applyTemplate(s0, template.id, nine05).state
        val again = planning.applyTemplate(applied, template.id, nine05)
        assertTrue(again.value)
        assertSame(applied, again.state)
    }

    @Test fun clearingAnOrphanTemplateTaskSoftDeletesItAndApplyRevivesTheSameRow() {
        val (s0, template, work) = capturedTemplate()
        var s = planning.applyTemplate(s0, template.id, nine05).state
        val materialized = assignmentAt(s, work[0].startAtMs)!!.taskID!!
        s = planning.clearBlock(s, work[0].startAtMs, shift(), nine05)
        val tombstone = task(s, materialized)
        assertNotNull(tombstone.deletedAtMs)
        assertEquals(template.id, tombstone.templateID)
        assertNotNull(tombstone.templateTaskKey)
        s = planning.applyTemplate(s, template.id, nine05).state
        assertEquals(materialized, assignmentAt(s, work[0].startAtMs)?.taskID)
        assertNull(task(s, materialized).deletedAtMs)
    }

    @Test fun clearingATemplateTaskWithHistoryOrAStarKeepsItAsAUserTask() {
        val (s0, template, work) = capturedTemplate()
        var s = planning.applyTemplate(s0, template.id, nine05).state
        val materialized = assignmentAt(s, work[0].startAtMs)!!.taskID!!
        s = planning.toggleFavorite(s, materialized, nine05)
        s = engine.upsertSession(s, completed(task(s, materialized), nine05), nine05)
        s = planning.clearBlock(s, work[0].startAtMs, shift(), nine05)
        val retained = task(s, materialized)
        assertNull(retained.deletedAtMs)
        assertTrue(retained.isFavorite)
        assertNull(retained.templateID)
        assertNull(retained.templateTaskKey)
        s = planning.applyTemplate(s, template.id, nine05).state
        assertNotEquals(materialized, assignmentAt(s, work[0].startAtMs)?.taskID)
    }

    @Test fun aTemplateTaskAnotherPlanStillUsesIsDetachedNotDeleted() {
        val (s0, template, work) = capturedTemplate()
        var s = planning.applyTemplate(s0, template.id, nine05).state
        val materialized = assignmentAt(s, work[0].startAtMs)!!.taskID!!
        val tuesdayShift = env.shift(at(tuesday, 10))!!
        val nextBlock = planning.blocks(tuesdayShift, s).first { it.kind == FocusPlanBlockKind.TASK }
        s = planning.assignBlock(s, nextBlock.startAtMs, materialized, tuesdayShift, nine05)
        s = planning.clearBlock(s, work[0].startAtMs, shift(), nine05)
        val retained = task(s, materialized)
        assertNull(retained.deletedAtMs)
        assertNull(retained.templateID)
        assertEquals(nextBlock.startAtMs.toDouble(), retained.scheduledStartAtMs)
    }

    @Test fun templateEstimatesNeverShrinkBelowCompletedRoundsAndManualEstimatesStayManual() {
        val (s0, template, work) = capturedTemplate()
        var s = planning.applyTemplate(s0, template.id, nine05).state
        val manual = s.focusTasks.first { it.templateID == null }.id
        val templateTask = assignmentAt(s, work[0].startAtMs)!!.taskID!!
        repeat(3) { s = engine.upsertSession(s, completed(task(s, templateTask), nine05 + it * 60_000), nine05) }
        s = planning.assignBlock(s, work[0].startAtMs, templateTask, shift(), nine05)
        assertEquals(3, task(s, templateTask).estimatedPomodoros)
        s = planning.assignBlock(s, work[0].startAtMs, manual, shift(), nine05)
        s = planning.assignBlock(s, work[1].startAtMs, manual, shift(), nine05)
        assertEquals(1, task(s, manual).estimatedPomodoros)
    }

    @Test fun renamingATemplateTaskLiftsItsEstimateToItsCompletedRounds() {
        val (s0, original) = template(RecordState())
        var s = planning.applyTemplate(s0, original.id, nine05).state
        val id = canvas(s).blocks.first { it.isAssigned }.taskID!!
        repeat(3) { s = engine.upsertSession(s, completed(task(s, id), nine05 + it * 60_000), nine05) }
        assertEquals(1, task(s, id).estimatedPomodoros)
        s = planning.editTask(s, id, "Renamed", FocusTaskIcon.WORK, 1, false, nine05).state
        assertEquals(3, task(s, id).estimatedPomodoros)
    }

    @Test fun shortShiftsTakeAWholeTaskPrefix() {
        val key1 = "K1"
        val key2 = "K2"
        val slots = List(3) { FocusTemplateSlot(it, FocusPlanBlockKind.TASK, key1, "A", FocusTaskIcon.FOCUS) } +
            List(40) { FocusTemplateSlot(3 + it, FocusPlanBlockKind.TASK, key2, "B", FocusTaskIcon.FOCUS) } +
            FocusTemplateSlot(43, FocusPlanBlockKind.TASK, "K3", "C", FocusTaskIcon.FOCUS)
        val saved = planning.saveTemplate(RecordState(), "Long", slots, nine05)
        val (fits, dropped) = planning.templateFit(saved.state, saved.value!!.id, nine05)
        assertEquals("C would fit, but never skips ahead of B", 3, fits)
        assertEquals(41, dropped)
        val s = planning.applyTemplate(saved.state, saved.value!!.id, nine05).state
        assertEquals(1, s.focusTasks.count { it.deletedAtMs == null })
        assertEquals("A", s.focusTasks.single().title)
    }

    @Test fun twoThreeOneTemplateKeepsItsSavedSixRoundsAcrossShortAndLongShifts() {
        val slots = listOf("A", "A", "B", "B", "B", "C").mapIndexed { index, key ->
            FocusTemplateSlot(index, FocusPlanBlockKind.TASK, key, key, FocusTaskIcon.FOCUS)
        }
        val template = com.rainif.doneat.core.domain.records.FocusTemplate("template", "Daily", slots, 0.0, 0.0)
        fun blocks(count: Int) = (0 until count).map { FocusWorkBlock(it, it * 30 * 60_000L, (it * 30 + 25) * 60_000L) }

        assertEquals(listOf("A", "A", "B", "B", "B", "C"), FocusTemplates.placedSlots(template, blocks(6)).map { it.taskKey })
        assertEquals(listOf("A", "A"), FocusTemplates.placedSlots(template, blocks(4)).map { it.taskKey })
        assertEquals("a shorter shift must not trim the saved template", slots, template.slots)
        assertEquals(6, FocusTemplates.placedSlots(template, blocks(6)).size)

        val saved = planning.saveTemplate(RecordState(), "Six", slots, nine05)
        val templateID = saved.value!!.id
        val longDay = planning.applyTemplate(saved.state, templateID, nine05).state
        assertEquals(6, planning.planning(longDay).plans[monday]!!.assignments.count { it.kind == FocusPlanBlockKind.TASK })
        env.shortTuesday = true
        val shortDay = planning.applyTemplate(longDay, templateID, at(tuesday, 9, 5)).state
        assertEquals(2, planning.planning(shortDay).plans[tuesday]!!.assignments.count { it.kind == FocusPlanBlockKind.TASK })
        assertEquals(slots, planning.planning(shortDay).templates.single { it.id == templateID }.slots)
        env.shortTuesday = false
        val restored = planning.applyTemplate(shortDay, templateID, at(tuesday, 9, 5)).state
        assertEquals(6, planning.planning(restored).plans[tuesday]!!.assignments.count { it.kind == FocusPlanBlockKind.TASK })
        assertEquals(slots, planning.planning(restored).templates.single { it.id == templateID }.slots)
    }

    @Test fun anAttachedPlanFollowsTemplateEditsAndAHandEditedOneDoesNot() {
        val (s0, original) = template(RecordState())
        var s = planning.applyTemplate(s0, original.id, nine05).state
        val id = canvas(s).blocks.first { it.isAssigned }.taskID!!
        val slots = original.slots.map { it.copy(taskTitle = "Updated template", taskIcon = FocusTaskIcon.STUDY) }
        s = planning.updateTemplate(s, original.id, "Renamed", slots, nine05).state
        assertEquals("Renamed", planning.appliedTemplate(s, nine05)?.name)
        assertEquals("Updated template", task(s, id).title)
        assertEquals(FocusTaskIcon.STUDY, task(s, id).icon)

        val edited = planning.editTask(s, id, "Only today", FocusTaskIcon.CODE, 2, true, nine05)
        assertTrue(edited.value)
        s = edited.state
        assertNull(planning.appliedTemplate(s, nine05))
        assertEquals(2, canvas(s).blocks.count { it.taskID == id })
        assertEquals(2, planning.savedFavorite(s, "Only today", FocusTaskIcon.CODE)?.estimatedPomodoros)
        s = planning.updateTemplate(s, original.id, "Renamed again", slots.map { it.copy(taskTitle = "Another") }, nine05).state
        assertTrue(canvas(s).blocks.filter { it.taskID == id }.all { it.taskTitle == "Only today" })
    }

    @Test fun editingATemplateAfterClockOffKeepsTomorrowsLinkedTasks() {
        val evening = at(monday, 19)
        val (s0, original) = template(RecordState())
        assertTrue(canvas(s0, evening).isNextShift)
        var s = planning.applyTemplate(s0, original.id, evening).state
        val id = canvas(s, evening).blocks.first { it.isAssigned }.taskID!!
        val tasks = FocusTemplates.tasks(original.slots).map { it.copy(pomodoros = 2, title = "Updated tomorrow", icon = FocusTaskIcon.STUDY) }
        s = planning.updateTemplate(s, original.id, "Tomorrow edited", FocusTemplates.slots(tasks, env::newId), evening).state
        val c = canvas(s, evening)
        assertEquals(tuesday, c.dayKey)
        assertEquals(2, c.blocks.count { it.taskID == id })
        assertTrue(c.blocks.filter { it.taskID == id }.all { it.taskTitle == "Updated tomorrow" })
        assertEquals(original.id, planning.appliedTemplate(s, evening)?.id)
        assertFalse(planning.applyDefaultTemplateIfNeeded(s, evening).value)
    }

    @Test fun templateRefreshKeepsPastAssignmentsAndUpdatesFutureOnes() {
        val (s0, original) = template(RecordState())
        var s = planning.applyTemplate(s0, original.id, nine05).state
        val before = canvas(s).blocks.first { it.isAssigned }
        val later = nine05 + 3_600_000
        val grid = workBlocks(s, later)
        val future = grid.first { it.kind == FocusPlanBlockKind.TASK && it.startAtMs > later }
        val slots = grid.filter { it.kind == FocusPlanBlockKind.TASK && it.index <= future.index }
            .map { FocusTemplateSlot(it.index, FocusPlanBlockKind.TASK, env.newId(), "Future", FocusTaskIcon.CODE) }
        s = planning.updateTemplate(s, original.id, "Future plan", slots, later).state
        val c = canvas(s, later)
        assertEquals(before.taskID, c.blocks.first { it.startAtMs == before.startAtMs }.taskID)
        assertEquals("Future", c.blocks.first { it.startAtMs == future.startAtMs }.taskTitle)
    }

    @Test fun deletingAnAssignedTaskDetachesTheDay() {
        val (s0, original) = template(RecordState())
        var s = planning.applyTemplate(s0, original.id, nine05).state
        val id = canvas(s).blocks.first { it.isAssigned }.taskID!!
        s = planning.deleteTask(s, id, nine05).state
        assertNull(planning.appliedTemplate(s, nine05))
        s = planning.updateTemplate(s, original.id, "Updated", original.slots, nine05).state
        assertTrue(canvas(s).blocks.none { it.isAssigned })
    }

    @Test fun manualCreationDetachesTheDayAndAFavouriteDoesNot() {
        val (s0, original) = template(RecordState())
        var s = planning.applyTemplate(s0, original.id, nine05).state
        s = planning.saveFavorite(s, "For later", 3, FocusTaskIcon.STUDY, nine05)
        assertEquals(original.id, planning.appliedTemplate(s, nine05)?.id)
        assertNull(planning.savedFavorite(s, "For later", FocusTaskIcon.STUDY)!!.plannedForDate)
        s = planning.createInNextEmptyBlock(s, "Extra", nine05).state
        assertNull(planning.appliedTemplate(s, nine05))
    }

    @Test fun clearingADayKeepsHistoryAndBlocksAutomaticReapplication() {
        val (s0, original) = template(RecordState())
        var s = planning.setDefaultTemplate(s0, original.id, nine05)
        s = planning.applyTemplate(s, original.id, nine05).state
        val block = canvas(s).blocks.first { it.isAssigned }
        s = engine.upsertSession(s, completed(task(s, block.taskID!!), block.startAtMs.toDouble()), nine05)
        val history = s.focusSessions
        val end = block.endAtMs.toDouble()
        s = planning.clearDay(s, end)
        assertEquals(history, s.focusSessions)
        assertTrue(canvas(s, end).blocks.none { it.isAssigned })
        assertFalse(planning.applyDefaultTemplateIfNeeded(s, end).value)
        assertTrue(planning.planning(s).templates.any { it.id == original.id })
    }

    @Test fun templateChangesKeepTheRunningRoundAndClearingStopsIt() {
        val (s0, original) = template(RecordState())
        var s = planning.applyTemplate(s0, original.id, nine05).state
        val block = canvas(s).blocks.first { it.isAssigned }
        val running = FocusSession(
            "00000000-0000-0000-0000-0000000000C1", block.taskID, monday, nine05, block.endAtMs.toDouble(), null, null, nine05, 0, "T",
            FocusSessionKind.FOCUS, zone, monday, null, FocusEndReason.COMPLETED,
        )
        s = engine.upsertSession(s, running, nine05)
        val next = workBlocks(s).first { it.kind == FocusPlanBlockKind.TASK && it.startAtMs >= block.endAtMs }
        val slots = original.slots + FocusTemplateSlot(next.index, FocusPlanBlockKind.TASK, original.slots[0].taskKey, "Updated", FocusTaskIcon.CODE)
        s = planning.updateTemplate(s, original.id, "Updated", slots, nine05).state
        assertEquals(running.id, engine.activeSession(s)?.id)
        assertEquals(block.taskID, canvas(s).blocks.first { it.startAtMs == block.startAtMs }.taskID)
        s = planning.clearDay(s, nine05 + 60_000)
        assertNull(engine.activeSession(s))
        assertEquals(FocusEndReason.STOPPED_BY_USER, s.focusSessions.first { it.id == running.id }.endReason)
        assertTrue(canvas(s).blocks.none { it.isAssigned })
    }

    @Test fun clearingTheDisplayedDayKeepsAnotherDaysTasks() {
        var s = planning.createInNextEmptyBlock(RecordState(), "Today", nine05).state
        val later = nine05 + 12 * 3_600_000
        val tomorrow = planning.createInNextEmptyBlock(s, "Tomorrow", later)
        val nextID = placedID(tomorrow.value)
        s = planning.clearDay(tomorrow.state, nine05)
        assertNull(task(s, nextID).deletedAtMs)
        assertTrue(canvas(s, later).blocks.any { it.taskID == nextID })
    }

    @Test fun resizingSkipsAnotherTaskAndShrinkingReleasesOnlyItsOwnSlots() {
        val first = planning.createInNextEmptyBlock(RecordState(), "First", nine05)
        val id = placedID(first.value)
        val other = planning.createInNextEmptyBlock(first.state, "Other", nine05)
        val (otherID, otherStart) = other.value as FocusPlacement.Placed
        var s = planning.editTask(other.state, id, "First", FocusTaskIcon.WORK, 2, false, nine05).state
        assertEquals(2, canvas(s).blocks.count { it.taskID == id })
        assertEquals(otherID, canvas(s).blocks.first { it.startAtMs == otherStart }.taskID)
        val shrunk = planning.editTask(s, id, "First", FocusTaskIcon.WORK, 1, false, nine05)
        assertTrue(shrunk.value)
        s = shrunk.state
        assertEquals(1, canvas(s).blocks.count { it.taskID == id })
        assertEquals(otherID, canvas(s).blocks.first { it.startAtMs == otherStart }.taskID)
    }

    @Test fun theDefaultTemplateAppliesOnceAndNeverOverAHandDrawnPlan() {
        val (s0, original) = template(RecordState())
        var s = planning.setDefaultTemplate(s0, original.id, nine05)
        val applied = planning.applyDefaultTemplateIfNeeded(s, nine05)
        assertTrue(applied.value)
        s = planning.clearCanvasBlock(applied.state, canvas(applied.state).blocks.first { it.isAssigned }.startAtMs, nine05)
        assertFalse(planning.applyDefaultTemplateIfNeeded(s, nine05).value)
        // Tuesday drawn by hand before any default existed.
        val evening = at(monday, 19)
        var drawn = planning.createInNextEmptyBlock(RecordState(), "Mine", evening).state
        val saved = planning.saveTemplate(drawn, "D", original.slots, nine05)
        drawn = planning.setDefaultTemplate(saved.state, saved.value!!.id, nine05)
        assertFalse(planning.applyDefaultTemplateIfNeeded(drawn, evening).value)
        assertEquals(listOf("Mine"), canvas(drawn, evening).blocks.mapNotNull { it.taskTitle })
    }

    // Tasks

    @Test fun savingAFavouriteAgainUpdatesItsEstimateAndUnstarringRemovesIt() {
        var s = planning.saveFavorite(RecordState(), "Reusable writing", 2, FocusTaskIcon.FOCUS, nine05)
        val original = planning.favorites(s).single()
        s = planning.saveFavorite(s, "Reusable writing", 4, FocusTaskIcon.FOCUS, nine05)
        assertEquals(listOf(original.id), planning.favorites(s).map { it.id })
        assertEquals(4, planning.favorites(s).single().estimatedPomodoros)
        s = planning.toggleFavorite(s, original.id, nine05)
        assertTrue(planning.favorites(s).isEmpty())
        assertTrue(engine.tasksForToday(s, nine05).none { it.id == original.id })
    }

    @Test fun unfinishedWorkFromAnEarlierDayCarriesToTodayWithoutItsSlot() {
        val yesterday = planning.addTask(RecordState(), "Left over", 1, at("2026-08-30", 10), scheduledStartAtMs = at("2026-08-30", 10))
        val s = planning.carryIncomplete(yesterday.state, nine05)
        val carried = task(s, yesterday.value.id)
        assertEquals(monday, carried.plannedForDate)
        assertNull(carried.scheduledStartAtMs)
        assertSame(s, planning.carryIncomplete(s, nine05))
    }

    @Test fun theRunningTaskCannotBeDeleted() {
        val made = planning.createInNextEmptyBlock(RecordState(), "Now", nine05)
        val id = placedID(made.value)
        val started = engine.startFocus(made.state, FocusNextAction.NONE, id, nine05)
        assertTrue(started.ok)
        assertFalse(planning.deleteTask(started.state, id, nine05).value)
    }

    // Plan-driven sessions

    @Test fun assignedBlocksQueueSessionsOnceAndRestoreAtTheirOwnStart() {
        val c = canvas(RecordState())
        val second = c.blocks.filter { it.kind == FocusPlanBlockKind.TASK }[1]
        val made = planning.createInBlock(RecordState(), "Planned", second.startAtMs, nine05)
        val id = placedID(made.value)
        val queue = planning.scheduledSessions(made.state, emptyList(), nine05)
        assertEquals(1, queue.size)
        assertEquals(second.startAtMs.toDouble(), queue.single().startedAtMs, 0.0)
        assertEquals(queue, planning.scheduledSessions(made.state, queue, nine05 + 60_000))

        val late = second.startAtMs + 3 * 60_000.0
        val (s, remaining, _) = planning.restoreScheduled(made.state, queue, FocusNextAction.NONE, late)
        assertTrue(remaining.isEmpty())
        val active = engine.activeSession(s)!!
        assertEquals(id, active.taskID)
        assertEquals("waking late does not restart the block", second.startAtMs.toDouble(), active.startedAtMs, 0.0)
        val (twice, _, _) = planning.restoreScheduled(s, queue, FocusNextAction.NONE, late + 60_000)
        assertEquals(s.focusSessions, twice.focusSessions)
    }

    @Test fun aBlockClearedBeforeItStartsIsNotRecorded() {
        val second = canvas(RecordState()).blocks.filter { it.kind == FocusPlanBlockKind.TASK }[1]
        val made = planning.createInBlock(RecordState(), "Planned", second.startAtMs, nine05)
        val queue = planning.scheduledSessions(made.state, emptyList(), nine05)
        val cleared = planning.clearCanvasBlock(made.state, second.startAtMs, nine05)
        val (s, _, _) = planning.restoreScheduled(cleared, queue, FocusNextAction.NONE, second.startAtMs + 60_000.0)
        assertTrue(s.focusSessions.isEmpty())
    }
}
