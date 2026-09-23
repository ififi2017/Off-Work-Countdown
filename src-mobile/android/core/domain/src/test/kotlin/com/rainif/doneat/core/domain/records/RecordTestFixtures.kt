package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.WallClock
import java.time.ZoneId

/** Builders shared by the record tests, mirroring the Swift tests' helpers. */
object RecordTestFixtures {
    const val ZONE = "Asia/Shanghai"
    private val civil = CivilZone(ZoneId.of(ZONE))

    fun id(value: Int) = "00000000-0000-0000-0000-%012d".format(value)

    fun ms(dayKey: String, hour: Int, minute: Int = 0) =
        civil.utcMs(ExtendedScheduleResolver.dayNumber(dayKey)!!, WallClock(hour, minute))

    fun segment(dayKey: String, fromHour: Int, toHour: Int) = ShiftSegment(ms(dayKey, fromHour), ms(dayKey, toHour))

    fun period(id: String, startsOn: String, endsBefore: String? = null, createdOn: String = startsOn) = CareerPeriod(
        id, startsOn, endsBefore, null, ZONE, "gregorian", ms(createdOn, 0), ms(createdOn, 0), 1, id,
    )

    fun snapshot(id: String, periodID: String, from: String, fingerprint: String, editCount: Int = 1, tie: String = id, data: String = "") =
        ScheduleSnapshot(id, periodID, from, data, fingerprint, ms(from, 0), editCount, tie)

    fun holiday(dayKey: String, effect: CalendarEffect, origin: CalendarExceptionOrigin, version: String? = null) = CalendarException(
        "$dayKey#${origin.raw}", dayKey, effect, origin, false, if (origin == CalendarExceptionOrigin.BUNDLED) "CN" else null,
        version, null, ms(dayKey, 0), 1, id(1), ZONE,
    )

    fun override(dayKey: String, kind: DayOverrideKind, segments: List<ShiftSegment> = emptyList()) =
        DayOverride(dayKey, kind, segments, null, 0.0, 0, DayOverrideProjection.ZERO_UUID, ZONE)
}
