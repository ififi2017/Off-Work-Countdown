package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.LeavePortion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek

/** iOS LeavePlanCalendarTests: full months include every leave item across month/year boundaries. */
class LeavePlanCalendarPageTest {
    private fun day(key: String) = ExtendedScheduleResolver.dayNumber(key)!!

    private fun proposal(from: String, through: String, early: String? = null): LeavePlanProposal {
        val first = day(from)
        val last = day(through)
        val items = early?.let { listOf(LeavePlanItem(day(it), it, LeavePortion.SECOND_HALF,
            emptyList(), emptyList(), LeavePlanItem.Role.EARLY_DEPARTURE)) }.orEmpty()
        return LeavePlanProposal(first, last, from, through, items, emptyList(), null, null,
            List(last - first + 1) { LeavePlanProposal.DayKind.REST }, emptySet())
    }

    @Test fun `every week start produces a full six-row month`() {
        for (firstWeekday in DayOfWeek.entries) {
            val page = LeavePlanCalendarPage(day("2026-10-24"), firstWeekday)
            assertEquals(day("2026-10-01"), page.firstDayNumber)
            assertEquals(42, page.days.size)
            assertEquals(firstWeekday, LeavePlannerSchedule.date(page.days.first()).dayOfWeek)
            assertEquals((day("2026-10-01")..day("2026-10-31")).toList(), page.days.filter(page::contains))
            assertEquals((page.days.first() until page.days.first() + 42).toList(), page.days)
        }
    }

    @Test fun `a cross-month option exposes both complete months`() {
        val option = proposal("2026-10-24", "2026-11-01")
        val months = LeavePlanCalendarPage.months(option)
        assertEquals(listOf(day("2026-10-01"), day("2026-11-01")), months)
        assertEquals(day("2026-10-24")..day("2026-11-01"), LeavePlanCalendarPage.coverage(option))
        for (date in LeavePlanCalendarPage.coverage(option)) {
            assertTrue(months.any { LeavePlanCalendarPage(it, DayOfWeek.MONDAY).contains(date) })
        }
    }

    @Test fun `early departure is included even in the preceding year`() {
        val option = proposal("2027-01-01", "2027-01-09", early = "2026-12-31")
        assertEquals(listOf(day("2026-12-01"), day("2027-01-01")), LeavePlanCalendarPage.months(option))
        assertEquals(day("2026-12-31"), LeavePlanCalendarPage.coverage(option).first)
    }

    @Test fun `leap February includes the 29th without leaking March into the month`() {
        val page = LeavePlanCalendarPage(day("2028-02-29"), DayOfWeek.MONDAY)
        assertEquals(29, page.days.count(page::contains))
        assertTrue(page.contains(day("2028-02-29")))
        assertFalse(page.contains(day("2028-03-01")))
    }
}
