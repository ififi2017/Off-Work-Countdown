package com.rainif.doneat.core.domain.settings

import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.SessionEnvironment
import com.rainif.doneat.core.domain.session.TimelineKind
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.ZoneId
import java.time.ZonedDateTime

/** iOS OnboardingPreviewTests: no persistence, no invented shifts, identical draft calendar. */
class SetupProjectionTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val holidays = HolidayCalendar.parse(File(System.getProperty("owc.holidayTemplates")).readText())
    private fun now(day: Int, hour: Int) = ZonedDateTime.of(2026, 10, day, hour, 0, 0, 0, zone).toInstant().toEpochMilli().toDouble()
    private fun environment(at: Double) = SessionEnvironment(PreferencesRules.defaults(zone.id, at), false, null, emptyList(), holidays, zone.id)

    @Test fun `holiday draft follows its region without changing the archive`() {
        val at = now(5, 0)
        val state = RecordState()
        val env = environment(at)
        for (region in listOf("CN", "")) {
            val result = SetupProjection.resolve(env, at, region)!!
            val expected = now(if (region == "CN") 8 else 5, 9)
            assertEquals(expected, result.snapshot.startAtMs, 0.0)
            assertEquals(result.snapshot.startAtMs, result.upcoming.first { it.kind == TimelineKind.SHIFT_START }.atMs, 0.0)
            assertTrue(result.upcoming.all { it.atMs in result.snapshot.startAtMs..result.snapshot.endAtMs })
            assertNull(result.snapshot.dailySalary)
            assertNull(result.snapshot.earnedSoFar)
            assertEquals(RecordState(), state)
            assertFalse(env.onboardingComplete)
        }
    }

    @Test fun `completed shifts advance but a running overnight shift remains`() {
        val evening = now(5, 19)
        val env = environment(evening)
        val next = SetupProjection.resolve(env, evening, "")!!
        assertEquals(now(6, 9), next.snapshot.startAtMs, 0.0)
        val nightEnv = SessionEnvironment(env.preferences.copy(startMinutes = 22 * 60, endMinutes = 6 * 60), false,
            null, emptyList(), holidays, zone.id)
        val night = SetupProjection.resolve(nightEnv, now(6, 2), "")!!
        assertEquals(now(5, 22), night.snapshot.startAtMs, 0.0)
        assertEquals(now(6, 6), night.snapshot.endAtMs, 0.0)
    }

    @Test fun `replaying welcome keeps a restored holiday calendar`() {
        val at = now(5, 0)
        val env = environment(at)
        val content = SetupProjection.seedContent(env, at, "CN")
        val restored = SessionEnvironment(env.preferences, true, com.rainif.doneat.core.domain.schedule.ExtendedSchedule(true, content),
            emptyList(), holidays, zone.id)
        assertEquals(now(8, 9), SetupProjection.resolve(restored, at, "")!!.snapshot.startAtMs, 0.0)
    }

    @Test fun `manual timing does not invent an upcoming shift`() {
        val at = now(5, 0)
        val env = environment(at)
        assertNull(SetupProjection.resolve(SessionEnvironment(env.preferences.copy(scheduleMode = "off"), false,
            null, emptyList(), holidays, zone.id), at, "CN"))
    }

    @Test fun `preview micro break belongs to the next holiday-aware shift`() {
        val at = now(5, 0)
        val env = environment(at)
        val enabled = SessionEnvironment(env.preferences.copy(microBreakEnabled = true, microBreakIntervalMinutes = 60,
            lunchEnabled = true, lunchStartMinutes = 12 * 60, lunchDurationMinutes = 60), false,
            null, emptyList(), holidays, zone.id)
        val result = SetupProjection.resolve(enabled, at, "CN")!!
        assertEquals(now(8, 10), result.upcoming.first { it.kind == TimelineKind.HEALTH }.atMs, 0.0)
        assertEquals(now(8, 9) - at, result.remainingMs(at), 0.0)
    }
}
