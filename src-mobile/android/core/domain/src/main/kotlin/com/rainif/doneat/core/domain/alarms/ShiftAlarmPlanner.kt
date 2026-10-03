package com.rainif.doneat.core.domain.alarms

import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.WallClock
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** Device-local preferences. This rule model does not grant platform permission. */
data class ShiftAlarmSettings(
    val enabled: Boolean = false,
    val defaultLeadMinutes: Int = 60,
    val leadMinutesByShiftType: Map<UUID, Int> = emptyMap(),
    val silencedShiftTypeIDs: Set<UUID> = emptySet(),
) {
    fun leadMinutes(type: UUID?): Int? {
        if (type in silencedShiftTypeIDs) return null
        return (leadMinutesByShiftType[type] ?: defaultLeadMinutes).takeIf { it in LEAD_CHOICES }
    }

    companion object {
        val LEAD_CHOICES = setOf(15, 30, 45, 60, 75, 90, 105, 120, 150, 180)
        const val SNOOZE_MINUTES = 9
    }
}

/** Only a verified exact expiry can authorize subscription alarms. Billing Purchase has none. */
sealed interface ShiftAlarmAuthorization {
    data object Unavailable : ShiftAlarmAuthorization
    data object Lifetime : ShiftAlarmAuthorization
    data class VerifiedUntil(val expiresAtMs: Long) : ShiftAlarmAuthorization
}

data class PlannedShiftAlarm(
    val id: UUID,
    val fireAtMs: Long,
    val shiftStartAtMs: Long,
    val dayKey: String,
    val shiftTypeID: UUID?,
    val shiftName: String?,
)

/** Plan 020, pinned to iOS 18129168. Uses the final schedule, including adopted leave. */
object ShiftAlarmPlanner {
    fun windowEnd(authorization: ShiftAlarmAuthorization, nowMs: Long, zone: ZoneId): Long? =
        when (authorization) {
            ShiftAlarmAuthorization.Unavailable -> null
            ShiftAlarmAuthorization.Lifetime -> Instant.ofEpochMilli(nowMs).atZone(zone).plusYears(1).toInstant().toEpochMilli()
            is ShiftAlarmAuthorization.VerifiedUntil -> authorization.expiresAtMs.takeIf { it > nowMs }
        }

    fun alarms(
        hours: ScheduleHours,
        zone: ZoneId,
        settings: ShiftAlarmSettings,
        nowMs: Long,
        untilMs: Long,
    ): List<PlannedShiftAlarm> {
        if (!settings.enabled || untilMs <= nowMs) return emptyList()
        val civil = CivilZone(zone)
        val first = civil.civil(nowMs.toDouble()).dayNumber - 1
        val last = civil.civil(untilMs.toDouble()).dayNumber + 1
        val expanded = ScheduleRules.expandScheduleRange(
            hours, civil.utcMs(first, WallClock.NOON), civil.utcMs(last, WallClock.NOON), zone,
        )
        if (expanded.size != last - first + 1) return emptyList()
        val resolver = hours.extended?.let(::ExtendedScheduleResolver)
        return expanded.mapIndexedNotNull { offset, day ->
            if (!day.isWorkday) return@mapIndexedNotNull null
            val start = day.segments.firstOrNull()?.startAtMs?.toLong() ?: return@mapIndexedNotNull null
            val type = resolver?.day(first + offset)?.shiftTypeID
            val lead = settings.leadMinutes(type) ?: return@mapIndexedNotNull null
            val fire = start - lead * 60_000L
            if (fire <= nowMs || fire >= untilMs) return@mapIndexedNotNull null
            val name = hours.extended?.shiftTypes?.firstOrNull { it.id == type }?.name
            PlannedShiftAlarm(stableID(day.dayKey, fire, start, name), fire, start, day.dayKey, type, name)
        }.distinctBy { it.id }.sortedBy { it.fireAtMs }
    }

    /** Same SHA-256 name-based UUID layout as the iOS planner. */
    fun stableID(dayKey: String, fireAtMs: Long, shiftStartAtMs: Long, shiftName: String?): UUID {
        val content = "owc.shiftAlarm|$dayKey|$fireAtMs|$shiftStartAtMs|${shiftName.orEmpty()}"
        val bytes = MessageDigest.getInstance("SHA-256").digest(content.toByteArray(Charsets.UTF_8)).copyOf(16)
        bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x50).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
        val buffer = ByteBuffer.wrap(bytes)
        return UUID(buffer.long, buffer.long)
    }

    /** Snooze also obeys the precise paid boundary; it never extends entitlement. */
    fun snoozeAt(nowMs: Long, untilMs: Long): Long? =
        (nowMs + ShiftAlarmSettings.SNOOZE_MINUTES * 60_000L).takeIf { it > nowMs && it < untilMs }
}

/** Pure reconciliation inputs. `accepted` must contain successful system registrations only. */
object ShiftAlarmReconciliation {
    const val REFRESH_DELAY_MS = 10 * 60_000L
    data class Delta(val cancel: Set<UUID>, val schedule: List<PlannedShiftAlarm>)
    data class Coverage(val accepted: List<PlannedShiftAlarm>, val coveredThroughMs: Long?, val refreshAtMs: Long?)

    fun delta(wanted: List<PlannedShiftAlarm>, accepted: List<PlannedShiftAlarm>): Delta {
        val next = wanted.associateBy { it.id }
        val held = accepted.associateBy { it.id }
        return Delta(
            held.filter { (id, alarm) -> next[id] != alarm }.keys,
            next.values.filter { held[it.id] != it }.sortedBy { it.fireAtMs },
        )
    }

    fun coverage(
        wanted: List<PlannedShiftAlarm>,
        accepted: List<PlannedShiftAlarm>,
        nowMs: Long,
        untilMs: Long,
        lifetime: Boolean,
    ): Coverage {
        val desired = wanted.filter { it.fireAtMs > nowMs && it.fireAtMs < untilMs }.distinctBy { it.id }.sortedBy { it.fireAtMs }
        val held = accepted.associateBy { it.id }
        val actual = desired.filter { held[it.id] == it }
        val through = desired.takeWhile { held[it.id] == it }.lastOrNull()?.fireAtMs
        // No accepted alarm means no claim of coverage and no fictional exhaustion event.
        val last = actual.lastOrNull()?.fireAtMs
        val refresh = last?.plus(REFRESH_DELAY_MS)?.takeIf {
            (lifetime || actual.size < desired.size) && (lifetime || it < untilMs)
        }
        return Coverage(actual, through, refresh)
    }
}
