package com.rainif.doneat.core.domain.alarms

import com.rainif.doneat.core.domain.schedule.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

class ShiftAlarmPlannerTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val hours = ScheduleHours("09:00", "18:00", listOf(1, 2, 3, 4, 5), WorkSchedule(ScheduleMode.CLASSIC), "12:00", 60)
    private fun ms(value: String, inZone: ZoneId = zone) = LocalDateTime.parse(value).atZone(inZone).toInstant().toEpochMilli()
    private fun plan(input: ScheduleHours = hours, settings: ShiftAlarmSettings = ShiftAlarmSettings(enabled = true),
                     from: String = "2026-10-01T12:00", until: String = "2026-10-07T12:00") =
        ShiftAlarmPlanner.alarms(input, zone, settings, ms(from), ms(until))
    private fun type(id: Int, name: String, start: Int, end: Int, rest: Boolean = false) =
        ShiftType(UUID(0, id.toLong()), name, if (rest) ShiftType.Kind.REST else ShiftType.Kind.WORK,
            start, end, false, 0, 0, "#FF7A00", false)
    private val office = type(1, "Office", 540, 1080)
    private val rest = type(2, "Rest", 540, 1080, true)
    private val night = type(3, "Night", 1320, 360)
    private val dawn = type(4, "Dawn", 30, 510)
    private fun extended(days: List<UUID> = List(5) { office.id } + List(2) { rest.id }, hand: Map<String, UUID> = emptyMap(), region: String? = null) =
        ExtendedSchedulePlan(listOf(office, rest, night, dawn), ShiftCycleRule(ShiftCycleRule.Preset.WEEKLY, "2026-09-21", days), hand,
            holidayRegionIdentifier = region, holidays = HolidayCalendar.parse(File(System.getProperty("owc.holidayTemplates")).readText()))

    @Test fun `fixed hours skip weekends past and disabled alarms`() {
        val result = plan()
        assertEquals(listOf("2026-10-02", "2026-10-05", "2026-10-06", "2026-10-07"), result.map { it.dayKey })
        assertTrue(result.all { it.shiftStartAtMs - it.fireAtMs == 60 * 60_000L })
        assertTrue(plan(settings = ShiftAlarmSettings()).isEmpty())
    }

    @Test fun `types respect lead silence overnight and previous civil day`() {
        val input = hours.copy(extended = extended(listOf(office.id, night.id, dawn.id, office.id, office.id, rest.id, rest.id)))
        val settings = ShiftAlarmSettings(true, leadMinutesByShiftType = mapOf(night.id to 90))
        val result = plan(input, settings, "2026-09-27T12:00", "2026-10-01T23:00")
        assertEquals(listOf(ms("2026-09-28T08:00"), ms("2026-09-29T20:30"), ms("2026-09-29T23:30"), ms("2026-10-01T08:00")), result.map { it.fireAtMs })
        assertFalse(plan(input, settings.copy(silencedShiftTypeIDs = setOf(night.id)), "2026-09-27T12:00", "2026-10-01T23:00").any { it.shiftTypeID == night.id })
    }

    @Test fun `window excludes now and exact expiry`() {
        val fire = ms("2026-10-05T08:00")
        fun at(now: Long, end: Long) = ShiftAlarmPlanner.alarms(hours, zone, ShiftAlarmSettings(true), now, end)
        assertTrue(at(fire - 1, fire).isEmpty())
        assertEquals(listOf(fire), at(fire - 1, fire + 1).map { it.fireAtMs })
        assertTrue(at(fire, fire + 1).isEmpty())
    }

    @Test fun `holidays makeup days and hand assignments use final schedule`() {
        val holiday = plan(hours.copy(extended = extended(region = "CN")), from = "2026-09-28T00:00", until = "2026-10-12T00:00")
        assertFalse(holiday.any { it.dayKey in (1..7).map { day -> "2026-10-0$day" } })
        assertTrue(holiday.any { it.dayKey == "2026-10-10" })
        val swapped = plan(hours.copy(extended = extended(hand = mapOf("2026-10-03" to office.id, "2026-10-05" to rest.id))))
        assertTrue(swapped.any { it.dayKey == "2026-10-03" })
        assertFalse(swapped.any { it.dayKey == "2026-10-05" })
    }

    @Test fun `whole leave cancels and first half moves alarm beyond lunch`() {
        val leave = ExtendedSchedulePlan.applying(mapOf("2026-10-02" to LeavePortion.WHOLE, "2026-10-05" to LeavePortion.FIRST_HALF), null,
            ExtendedScheduleDayHours("09:00", "18:00", "12:00", 60))
        val result = plan(hours.copy(extended = leave))
        assertFalse(result.any { it.dayKey == "2026-10-02" })
        assertEquals(ms("2026-10-05T13:00"), result.single { it.dayKey == "2026-10-05" }.fireAtMs)
    }

    @Test fun `stable identities and diff replace changed lead and name`() {
        val initial = plan()
        assertEquals(initial, plan())
        assertEquals(initial.size, initial.map { it.id }.distinct().size)
        assertTrue(ShiftAlarmReconciliation.delta(initial, initial).schedule.isEmpty())
        val next = plan(settings = ShiftAlarmSettings(true, 90))
        val delta = ShiftAlarmReconciliation.delta(next, initial)
        assertEquals(initial.map { it.id }.toSet(), delta.cancel)
        assertEquals(next, delta.schedule)
        assertNotEquals(ShiftAlarmPlanner.stableID("2026-10-02", 1, 2, "A"), ShiftAlarmPlanner.stableID("2026-10-02", 1, 2, "B"))
    }

    @Test fun `unknown subscription expiry cannot authorize even with active Plus`() {
        val now = ms("2026-10-01T12:00")
        assertNull(ShiftAlarmPlanner.windowEnd(ShiftAlarmAuthorization.Unavailable, now, zone))
        assertNull(ShiftAlarmPlanner.windowEnd(ShiftAlarmAuthorization.VerifiedUntil(now), now, zone))
        val expiry = now + 9 * 86_400_000L + 3_723_000
        assertEquals(expiry, ShiftAlarmPlanner.windowEnd(ShiftAlarmAuthorization.VerifiedUntil(expiry), now, zone))
        // Auto-renewal is deliberately not an input: cancelling it cannot truncate a verified paid period.
    }

    @Test fun `lifetime uses calendar year across leap and DST`() {
        val ny = ZoneId.of("America/New_York")
        val now = ms("2028-02-29T12:00", ny)
        assertEquals(ms("2029-02-28T12:00", ny), ShiftAlarmPlanner.windowEnd(ShiftAlarmAuthorization.Lifetime, now, ny))
    }

    @Test fun `accepted coverage never bridges system rejection and refresh follows last success`() {
        val wanted = plan()
        val accepted = listOf(wanted[0], wanted[2])
        val coverage = ShiftAlarmReconciliation.coverage(wanted, accepted, ms("2026-10-01T12:00"), ms("2026-10-07T12:00"), false)
        assertEquals(accepted, coverage.accepted)
        assertEquals(wanted[0].fireAtMs, coverage.coveredThroughMs)
        assertEquals(wanted[2].fireAtMs + 600_000, coverage.refreshAtMs)
        assertNull(ShiftAlarmReconciliation.coverage(wanted, emptyList(), 0, Long.MAX_VALUE, true).refreshAtMs)
    }

    @Test fun `completed subscription has no refresh promise and disabled clears all`() {
        val wanted = plan()
        assertNull(ShiftAlarmReconciliation.coverage(wanted, wanted, 0, Long.MAX_VALUE, false).refreshAtMs)
        assertEquals(wanted.last().fireAtMs + 600_000, ShiftAlarmReconciliation.coverage(wanted, wanted, 0, Long.MAX_VALUE, true).refreshAtMs)
        assertEquals(wanted.map { it.id }.toSet(), ShiftAlarmReconciliation.delta(emptyList(), wanted).cancel)
        assertNull(ShiftAlarmReconciliation.coverage(emptyList(), wanted, 0, Long.MAX_VALUE, true).refreshAtMs)
    }

    @Test fun `nine minute snooze cannot reach or cross expiry`() {
        val now = ms("2026-10-01T08:00")
        assertEquals(now + 540_000, ShiftAlarmPlanner.snoozeAt(now, now + 540_001))
        assertNull(ShiftAlarmPlanner.snoozeAt(now, now + 540_000))
        assertNull(ShiftAlarmPlanner.snoozeAt(now, now - 1))
    }

    @Test fun `invalid lead cannot create a misleading appointment`() {
        assertTrue(plan(settings = ShiftAlarmSettings(true, -1)).isEmpty())
    }
}
