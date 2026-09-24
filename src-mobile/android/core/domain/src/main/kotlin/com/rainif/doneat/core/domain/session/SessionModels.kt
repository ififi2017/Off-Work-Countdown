package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * The hand-set shift one day had before a save, kept so "from the next shift
 * only" leaves the shift in progress alone. [shiftTypeID] is null when the day
 * was not set by hand.
 */
data class KeptRosterDay(val dayKey: String, val shiftTypeID: UUID?)

/**
 * Hours and calendar in force until the current shift's settlement seam
 * ([untilMs]); the committed settings already hold the future schedule.
 * iOS `TodayScheduleOverride`.
 */
data class TodayScheduleOverride(
    val startMinutes: Int,
    val endMinutes: Int,
    val workdays: List<Int>,
    val scheduleMode: String,
    val lunchEnabled: Boolean,
    val lunchStartMinutes: Int,
    val lunchDurationMinutes: Int,
    val alternatingWeekType: String,
    val alternatingWeekendWorkday: Int,
    val alternatingReferenceWeekStartMs: Double,
    val rotationWorkDays: Int,
    val rotationRestDays: Int,
    val rotationAnchorMs: Double,
    val untilMs: Double,
    /** Whether today still runs on the extended schedule; null follows the current setting. */
    val extendedScheduleEnabled: Boolean? = null,
    /** The shift types and rule today keeps; null follows the stored ones. */
    val extendedContent: ExtendedScheduleContent? = null,
    /** The current shift's day as the calendar had it. */
    val extendedKeptDay: KeptRosterDay? = null,
)

/**
 * The running countdown's device-local state (iOS `ShiftSession`'s
 * `UserDefaults` keys). None of it is synced: it describes what this device's
 * user did today, and [earlyOffSnapshot] carries the daily salary, so it never
 * leaves the app's private storage.
 */
data class SessionState(
    val countdownStarted: Boolean = false,
    /** A new manual start is a new run even with identical hours. Not persisted. */
    val sessionId: String = "",
    /** Zone of a manually started run; null while following the schedule. */
    val sessionTimeZone: String? = null,
    /** After this instant a locked session zone falls back to the records zone. */
    val sessionTimeZoneUntilMs: Double? = null,
    /**
     * When the user said they had finished. It ends the shift they were in
     * (`start <= earlyOffAtMs < end`), not the calendar day.
     */
    val earlyOffAtMs: Double? = null,
    /** The end of the shift on screen at that moment, since clocking off before a start is ordinary. */
    val earlyOffShiftEndAtMs: Double? = null,
    /** The rules snapshot as it stood then, so later settings edits do not rebuild it. */
    val earlyOffSnapshot: ShiftSnapshot? = null,
    /** Clocked in before the planned start, bound to that shift's settlement seam. */
    val earlyStartAtMs: Double? = null,
    val earlyStartUntilMs: Double? = null,
    val todayOverride: TodayScheduleOverride? = null,
    /** Rest-day manual timing, keyed on the day the shift starts. */
    val forcedWorkdayDate: String? = null,
    val overtimeEndAtMs: Double? = null,
    /** The end of the run being counted, so an unscheduled run resets after its end day. */
    val activeCountdownEndAtMs: Double? = null,
) {
    fun clearingEarlyClockOff() = copy(earlyOffAtMs = null, earlyOffShiftEndAtMs = null, earlyOffSnapshot = null)

    fun clearingEarlyClockIn() = copy(earlyStartAtMs = null, earlyStartUntilMs = null)

    fun clearingSessionTimeZone() = copy(sessionTimeZone = null, sessionTimeZoneUntilMs = null)
}

/** What the timer surface shows. iOS `TimerVisualPhase`. */
enum class TimerPhase {
    /** Manual mode and no session today. */
    UNSCHEDULED,
    /** Counting down to the shift's start. */
    CLOCK_IN,
    RUNNING,
    LUNCH,
    OVERTIME,
    COMPLETED,
    REST,
    RULES_ERROR;

    /** Lunch and overtime are interludes of the running surface; changing between them must not cross-fade. */
    val surfaceIdentity: String
        get() = when (this) {
            RUNNING, LUNCH, OVERTIME -> "active"
            else -> name
        }

    /** Unscheduled idle and the rules error have no seconds-level figure and need no ticking clock. */
    val usesLiveTimeline: Boolean get() = this != UNSCHEDULED && this != RULES_ERROR

    companion object {
        fun resolve(
            followsSchedule: Boolean,
            sessionActive: Boolean,
            snapshot: ShiftSnapshot?,
            forceToday: Boolean,
            endedEarly: Boolean,
            nowMs: Double,
        ): TimerPhase {
            if (!followsSchedule && !sessionActive) return UNSCHEDULED
            snapshot ?: return RULES_ERROR
            // A forced rest day ended by hand still lands on the finished day, not "today is off".
            if (endedEarly) return COMPLETED
            if (followsSchedule && !snapshot.isWorkday && !forceToday) return REST
            if (snapshot.remainingMs <= 0) return COMPLETED
            if (snapshot.isBeforeStart(nowMs)) return CLOCK_IN
            if (snapshot.activeBreakEndAtMs != null) return LUNCH
            if (snapshot.overtimeEndAtMs != null && snapshot.elapsedMs >= snapshot.plannedDurationMs) return OVERTIME
            return RUNNING
        }
    }
}

// iOS `NativeShiftSnapshot` helpers.

fun ShiftSnapshot.isBeforeStart(nowMs: Double) = nowMs < startAtMs

val ShiftSnapshot.isOnBreak get() = activeBreakEndAtMs != null

fun ShiftSnapshot.isOvertimeActive(nowMs: Double) = overtimeEndAtMs != null && nowMs >= plannedEndAtMs

/**
 * What the running surfaces count: time until the start before clock-in,
 * until the break ends during one, otherwise effective work remaining.
 */
fun ShiftSnapshot.heroRemainingMs(nowMs: Double): Double {
    if (nowMs < startAtMs) return maxOf(0.0, startAtMs - nowMs)
    activeBreakEndAtMs?.let { return maxOf(0.0, it - nowMs) }
    return remainingMs
}

/**
 * Next-shift and next-rest come from [source]; current-shift figures stay.
 * iOS resolves the "day after the end" in the device calendar, as [deviceZone] does here.
 */
fun ShiftSnapshot.withProjectedFuture(source: ShiftSnapshot, deviceZone: ZoneId): ShiftSnapshot {
    val countsToCurrentStart = countdownTargetAtMs == startAtMs
    val restAtMs = source.nextRestAtMs?.let { candidate ->
        val endDay = Instant.ofEpochMilli(endAtMs.toLong()).atZone(deviceZone).toLocalDate()
        val afterEndDay = endDay.plusDays(1).atStartOfDay(deviceZone).toInstant().toEpochMilli().toDouble()
        if (candidate >= afterEndDay) candidate else nextRestAtMs
    } ?: nextRestAtMs
    return copy(
        nextRestAtMs = restAtMs,
        nextShiftStartAtMs = source.nextShiftStartAtMs,
        nextShiftEndAtMs = source.nextShiftEndAtMs,
        countdownTargetAtMs = if (countsToCurrentStart) countdownTargetAtMs else source.countdownTargetAtMs,
        countdownAnchorAtMs = if (countsToCurrentStart) countdownAnchorAtMs else source.countdownAnchorAtMs,
        countdownProgress = if (countsToCurrentStart) countdownProgress else source.countdownProgress,
    )
}
