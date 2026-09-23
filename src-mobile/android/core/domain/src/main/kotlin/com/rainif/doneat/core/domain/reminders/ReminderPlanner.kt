package com.rainif.doneat.core.domain.reminders

import com.rainif.doneat.core.domain.focus.FocusAlert
import com.rainif.doneat.core.domain.schedule.Reminder
import com.rainif.doneat.core.domain.schedule.ReminderKind
import kotlin.math.ceil

/** Which system channel a reminder posts to, so the user can mute one kind without the others. */
enum class ReminderChannel { SHIFT, HEALTH, FOCUS }

/**
 * One system alarm: everything the receiver needs to post it without
 * recomputing any rule. [expiresAtMs] carries the rule's freshness window, so
 * a delayed (inexact) "lunch has started" is dropped once lunch is over.
 */
data class PlannedReminder(
    val id: String,
    val atMs: Long,
    val channel: ReminderChannel,
    val title: String,
    val body: String,
    val expiresAtMs: Long? = null,
) {
    fun isDeliverable(nowMs: Long) = expiresAtMs == null || nowMs < expiresAtMs
}

/** How an alarm is handed to the system. */
enum class AlarmTiming {
    /** On time even in Doze; only with the user's exact-alarm grant. */
    EXACT,
    /** Allowed in Doze but may be deferred by the system. */
    INEXACT,
    /** A delivery window, for reminders where a few minutes do not matter. */
    WINDOW,
}

data class ReminderDiff(val schedule: List<PlannedReminder>, val cancel: List<String>) {
    val isEmpty get() = schedule.isEmpty() && cancel.isEmpty()
}

/**
 * Turns rule output into the alarms the system should hold (iOS
 * `ShiftSessionStore.shiftReminders` and `NotificationService.performReschedule`).
 * Everything is absolute and precomputed: the platform only compares times.
 */
object ReminderPlanner {
    /** Matches the iOS pending-request budget, which also keeps a one-minute health interval off the alarm quota. */
    const val MAX_SHIFT_ALARMS = 60
    const val SHIFT_PREFIX = "owc.shift."
    const val FOCUS_PREFIX = "owc.focus."

    /**
     * The current shift's reminders only while the user is actually in it,
     * plus the next shift's. A rest day or a settled overnight still yields a
     * `current:` window from the rules; it is not a shift to remind about.
     */
    fun shiftReminders(current: List<Reminder>, next: List<Reminder>, includeCurrent: Boolean): List<Reminder> =
        (if (includeCurrent) current.filter { it.id.startsWith("current:") } else emptyList()) + next.filter { it.id.startsWith("next:") }

    /**
     * The future, audible reminders to hold, the essential ones first so
     * frequent health reminders can never crowd out clock-off or the cycle
     * summary. After an early clock-off only the next shift's reminders remain.
     *
     * @param endedEarlyNextShiftStartMs set when today ended early: the next
     *   shift's start, or [Double.POSITIVE_INFINITY] when there is none.
     */
    fun shiftAlarms(reminders: List<Reminder>, nowMs: Double, endedEarlyNextShiftStartMs: Double? = null): List<PlannedReminder> {
        val future = reminders.filter { r ->
            r.atMs > nowMs && r.isAudible && (endedEarlyNextShiftStartMs == null || r.atMs >= endedEarlyNextShiftStartMs)
        }
        val (health, essential) = future.partition { it.kind == ReminderKind.MICRO_BREAK }
        return (essential.sortedBy { it.atMs } + health.sortedBy { it.atMs })
            .take(MAX_SHIFT_ALARMS)
            .map {
                val channel = if (it.kind == ReminderKind.MICRO_BREAK) ReminderChannel.HEALTH else ReminderChannel.SHIFT
                PlannedReminder(SHIFT_PREFIX + it.id, alarmTime(it.atMs), channel, it.title!!, it.body!!, it.expiresAtMs?.let(::alarmTime))
            }
    }

    /** A phase's alerts that are still ahead; one that passed while waiting is never backfilled. */
    fun focusAlarms(sessionID: String, alerts: List<FocusAlert>, nowMs: Double): List<PlannedReminder> =
        alerts.filter { it.atMs > nowMs }.map { PlannedReminder(it.id(sessionID), alarmTime(it.atMs), ReminderChannel.FOCUS, it.title, it.body) }

    /**
     * What to change so the system holds exactly [desired] under [prefix]: an
     * unchanged alarm keeps its registration, a moved or reworded one is
     * replaced, and anything no longer wanted is cancelled.
     */
    fun diff(registered: Collection<PlannedReminder>, desired: List<PlannedReminder>, prefix: String): ReminderDiff {
        val mine = registered.filter { it.id.startsWith(prefix) }.associateBy { it.id }
        val wanted = desired.associateBy { it.id }
        return ReminderDiff(
            schedule = wanted.values.filter { mine[it.id] != it },
            cancel = mine.keys.filter { it !in wanted },
        )
    }

    /**
     * After a reboot, clock change or app update, before the app has run: the
     * registered alarms still ahead are re-registered, and the ones that fell
     * due while the device was off are dropped rather than fired in a burst.
     */
    fun restore(registered: Collection<PlannedReminder>, nowMs: Double): ReminderDiff {
        val (ahead, missed) = registered.partition { it.atMs > nowMs }
        return ReminderDiff(schedule = ahead.sortedBy { it.atMs }, cancel = missed.map { it.id })
    }

    /**
     * Health reminders never use exact alarms: they are frequent, and exact
     * wake-ups would spend the system's allowance on the least important kind.
     * Without the user's exact-alarm grant everything is inexact and the
     * settings row says reminders may be late.
     */
    fun timing(channel: ReminderChannel, exactAllowed: Boolean) = when {
        channel == ReminderChannel.HEALTH -> AlarmTiming.WINDOW
        exactAllowed -> AlarmTiming.EXACT
        else -> AlarmTiming.INEXACT
    }

    /** Whole milliseconds, never earlier than the rule's instant. */
    private fun alarmTime(atMs: Double) = ceil(atMs).toLong()
}
