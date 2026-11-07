package com.rainif.doneat.core.domain.summary

import com.rainif.doneat.core.domain.salary.DailySalaryBasis
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** The "Daily pay by month" figures read the same rules as the timer and Records. */
class MonthlyDailyPayTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val now = ZonedDateTime.of(2026, 11, 7, 10, 0, 0, 0, zone).toInstant().toEpochMilli().toDouble()
    private val input = ScheduleRuleInput(
        hours = ScheduleHours("09:00", "18:00", listOf(1, 2, 3, 4, 5), WorkSchedule(ScheduleMode.CLASSIC), null, 0),
        nowMs = now,
        zone = zone,
    )
    private val salary = SalarySettings("21000", SalaryType.MONTHLY, 21.75, 0.0, DailySalaryBasis.SCHEDULED_MONTH)

    @Test fun dividesEachMonthByItsOwnScheduledWorkdays() {
        val pay = MonthlyDailyPay.make(input, salary, firstWeekday = 1)!!
        assertEquals("2026-11", pay.current.id)
        assertEquals(21, pay.current.workdayCount)
        assertEquals(1_000.0, pay.current.dailyPay!!, 1e-9)
        assertEquals(21_000.0, pay.monthlyAmount!!, 1e-9)
        assertEquals(listOf("2026-12", "2027-01", "2027-02"), pay.upcoming.map { it.id })
        assertEquals(listOf(23, 21, 20), pay.upcoming.map { it.workdayCount })
        assertEquals(21_000.0 / 23, pay.upcoming.first().dailyPay!!, 1e-9)
        assertEquals(21, MonthlyDailyPay.scheduledWorkdaysThisMonth(input))
    }

    @Test fun laysOutTheMonthFromTheFirstWeekday() {
        val monday = MonthlyDailyPay.make(input, salary, firstWeekday = 1)!!
        assertEquals(30, monday.days.size)
        // 1 November 2026 is a Sunday.
        assertEquals(6, monday.leadingBlanks)
        assertEquals(0, MonthlyDailyPay.make(input, salary, firstWeekday = 0)!!.leadingBlanks)
        val seventh = monday.days[6]
        assertTrue(seventh.isToday)
        assertFalse(seventh.isWorkday)
        assertTrue(monday.days[1].isWorkday)
        assertEquals(21, monday.days.count { it.isWorkday })
    }

    @Test fun onlyTheScheduledMonthBasisHasAPage() {
        assertNull(MonthlyDailyPay.make(input, salary.copy(dailySalaryBasis = DailySalaryBasis.FIXED), firstWeekday = 1))
        assertNull(MonthlyDailyPay.make(input, salary.copy(type = SalaryType.DAILY), firstWeekday = 1))
        // The menu still offers this month's count under the fixed basis.
        assertEquals(21, MonthlyDailyPay.scheduledWorkdaysThisMonth(input))
    }
}
