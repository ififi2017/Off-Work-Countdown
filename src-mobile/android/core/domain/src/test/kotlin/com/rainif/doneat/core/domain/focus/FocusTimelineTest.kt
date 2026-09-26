package com.rainif.doneat.core.domain.focus

import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.session.TimelineKind
import org.junit.Assert.*
import org.junit.Test

class FocusTimelineTest {
    private val day = 1_788_192_000_000.0
    private val nine = day + 9 * 3_600_000
    private val shift = FocusShift(listOf(ShiftSegment(nine, nine + 8 * 3_600_000)), nine, nine + 8 * 3_600_000, 8 * 3_600_000.0, null, true)
    private var authorized = true
    private var ids = 0
    private val env = object : FocusEnvironment {
        override fun shift(atMs: Double) = shift
        override fun scheduleEnabled(atMs: Double) = true
        override val overtimeEndAtMs: Double? = null
        override val isAuthorized get() = authorized
        override val recordsTimeZone = "UTC"
        override val settings = DEFAULT_TIMER_SETTINGS
        override fun newId() = "00000000-0000-4000-8000-%012d".format(++ids)
    }
    private val planning = FocusPlanning(env)
    private val timeline = FocusTimeline(env)

    @Test fun `a planned task and its recovery appear once and disappear without Plus`() {
        val created = planning.addTask(RecordState(), "Draft", 1, nine - 60_000, scheduledStartAtMs = nine)
        val state = planning.assignBlock(created.state, nine.toLong(), created.value.id, shift, nine - 60_000)
        val events = timeline.events(state, shift, nine - 60_000)
        assertEquals(2, events.size)
        assertEquals("Draft", events.first().focusTitle)
        assertEquals(TimelineKind.FOCUS_BREAK, events.last().kind)
        assertEquals(5, events.last().focusMinutes)
        assertFalse(events.any { it.id.startsWith("focus-task-") })
        authorized = false
        assertTrue(timeline.events(state, shift, nine - 60_000).isEmpty())
        assertTrue(timeline.plannedEvents(state, shift.segments, nine).isEmpty())
    }

    @Test fun `default templates project future shifts without adding archive plans`() {
        val saved = planning.saveTemplate(RecordState(), "Usual", listOf(FocusTemplateSlot(0, FocusPlanBlockKind.TASK, "key", "Draft", FocusTaskIcon.WORK)), nine - 60_000)
        val state = planning.setDefaultTemplate(saved.state, saved.value!!.id, nine - 60_000)
        val future = nine + 7 * 86_400_000
        val events = timeline.plannedEvents(state, listOf(ShiftSegment(future, future + 8 * 3_600_000)), future)
        assertEquals(listOf(TimelineKind.FOCUS, TimelineKind.FOCUS_BREAK), events.map { it.kind })
        assertEquals(future, events.first().atMs, 0.0)
        assertTrue(state.focusPlanningConfiguration!!.plans.isEmpty())
    }

    @Test fun `an explicitly empty day suppresses the default template`() {
        val saved = planning.saveTemplate(RecordState(), "Usual", listOf(FocusTemplateSlot(0, FocusPlanBlockKind.TASK, "key", "Draft", FocusTaskIcon.WORK)), nine - 60_000)
        var state = planning.setDefaultTemplate(saved.state, saved.value!!.id, nine - 60_000)
        val config = state.focusPlanningConfiguration!!
        val key = FocusEngine(env).dayKey(nine)
        state = state.copy(focusPlanningConfiguration = config.copy(plans = mapOf(key to FocusDayPlan(key, nine.toLong(), emptyList(), null))))
        assertTrue(timeline.events(state, shift, nine - 60_000).isEmpty())
    }

    @Test fun `appointments without a shift obey the two day horizon and ignore finished tasks`() {
        val near = planning.addTask(RecordState(), "Near", 2, nine, scheduledStartAtMs = nine + 3_600_000)
        val far = planning.addTask(near.state, "Far", 1, nine, scheduledStartAtMs = nine + 3 * 86_400_000)
        assertEquals(listOf("Near"), timeline.events(far.state, null, nine).map { it.focusTitle })
        val done = far.state.copy(focusTasks = far.state.focusTasks.map { it.copy(completedAtMs = nine) })
        assertTrue(timeline.events(done, null, nine).isEmpty())
    }

    @Test fun `a running block produces an end row without a schedule`() {
        val created = planning.addTask(RecordState(), "Work", 1, nine)
        val running = FocusEngine(env).startFocus(created.state, FocusNextAction.NONE, created.value.id, nine).state
        val event = timeline.events(running, null, nine + 1_000).single()
        assertTrue(event.runningFocus)
        assertEquals(nine + 25 * 60_000, event.atMs, 0.0)
    }
}
