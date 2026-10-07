package com.rainif.doneat.alarms

import com.rainif.doneat.core.domain.alarms.*
import java.util.UUID

/** A random delivery token belongs to one actual registration, never an incoming Intent's title/time. */
internal data class AlarmRegistration(
    val alarm: PlannedShiftAlarm,
    val title: String,
    val scheduledAtMs: Long = alarm.fireAtMs,
    val token: String = UUID.randomUUID().toString(),
    val accepted: Boolean = false,
    val ringing: Boolean = false,
    val snoozed: Boolean = false,
)

internal enum class AlarmScheduleOutcome { ACCEPTED, LIMIT, FAILED }
internal interface ShiftAlarmPlatform {
    fun exactAllowed(): Boolean
    fun notificationsAllowed(): Boolean
    fun registrations(): List<AlarmRegistration>
    fun schedule(registration: AlarmRegistration): AlarmScheduleOutcome
    fun markRinging(registration: AlarmRegistration): Boolean
    fun cancel(id: UUID)
    fun invalidateRegistrations()
    fun refreshReminder(atMs: Long?, title: String, body: String): Boolean
}

data class ShiftAlarmStatus(
    val exactAllowed: Boolean = false,
    val notificationsAllowed: Boolean = false,
    val entitlementAllowed: Boolean = false,
    val accepted: List<PlannedShiftAlarm> = emptyList(),
    val coveredThroughMs: Long? = null,
    val windowEndMs: Long? = null,
    val lifetime: Boolean = false,
    val reachedSystemLimit: Boolean = false,
    val failedCount: Int = 0,
    val refreshReminderAtMs: Long? = null,
    val refreshReminderUnavailable: Boolean = false,
)

internal data class AlarmPlan(
    val enabled: Boolean,
    val untilMs: Long?,
    val lifetime: Boolean,
    /** Contains the recent delivery grace window too, so cold process startup cannot erase a due alarm. */
    val alarms: List<PlannedShiftAlarm>,
    val title: (PlannedShiftAlarm) -> String,
    val refreshTitle: String = "",
    val refreshBody: String = "",
)

/** Pure reconciliation seam: tests never instantiate AlarmManager, a Service, or a ringtone. */
internal class ShiftAlarmEngine(private val platform: ShiftAlarmPlatform) {
    @Synchronized fun reconcile(plan: AlarmPlan, nowMs: Long): ShiftAlarmStatus {
        val exact = platform.exactAllowed()
        val notifications = platform.notificationsAllowed()
        val entitlement = plan.untilMs?.let { it > nowMs } == true
        val enabled = plan.enabled && exact && notifications && entitlement
        val end = plan.untilMs ?: nowMs
        val existing = platform.registrations()
        if (!enabled) {
            existing.forEach { platform.cancel(it.alarm.id) }
            platform.refreshReminder(null, "", "")
            return ShiftAlarmStatus(exact, notifications, entitlement, windowEndMs = plan.untilMs, lifetime = plan.lifetime)
        }
        val wanted = plan.alarms.filter { it.fireAtMs < end }.associateBy { it.id }
        val future = wanted.values.filter { it.fireAtMs > nowMs }.sortedBy { it.fireAtMs }
        val held = mutableMapOf<UUID, AlarmRegistration>()
        existing.forEach { item ->
            val same = wanted[item.alarm.id] == item.alarm && plan.title(item.alarm) == item.title
            val recentlyDue = nowMs >= item.scheduledAtMs && nowMs - item.scheduledAtMs <= DELIVERY_GRACE_MS
            val inFlight = item.accepted && same && (item.ringing || item.snoozed && item.scheduledAtMs < end)
            if (inFlight || same && (item.scheduledAtMs > nowMs || recentlyDue)) held[item.alarm.id] = item
            else platform.cancel(item.alarm.id)
        }
        var limit = false
        var failed = 0
        val requests = (future.map { AlarmRegistration(it, plan.title(it)) } +
            held.values.filter { !it.accepted && it.snoozed && it.scheduledAtMs > nowMs && it.scheduledAtMs < end }
                .map { it.copy(token = UUID.randomUUID().toString()) })
            .distinctBy { it.alarm.id }.sortedBy { it.scheduledAtMs }
        for (request in requests) {
            val alarm = request.alarm
            if (held[alarm.id]?.accepted == true) continue
            var result = platform.schedule(request)
            if (result == AlarmScheduleOutcome.LIMIT) {
                val latest = held.values.filter { !it.ringing && !it.snoozed }.maxByOrNull { it.scheduledAtMs }
                if (latest != null && latest.scheduledAtMs > request.scheduledAtMs) {
                    platform.cancel(latest.alarm.id)
                    held.remove(latest.alarm.id)
                    result = platform.schedule(request)
                }
            }
            when (result) {
                AlarmScheduleOutcome.ACCEPTED -> held[alarm.id] = request.copy(accepted = true)
                AlarmScheduleOutcome.LIMIT -> { limit = true; break }
                AlarmScheduleOutcome.FAILED -> failed++
            }
        }
        // A failed durable commit poisons the ledger; previously accepted entries must not remain UI coverage.
        if (!platform.exactAllowed()) {
            platform.registrations().forEach { platform.cancel(it.alarm.id) }
            platform.refreshReminder(null, "", "")
            return ShiftAlarmStatus(false, notifications, entitlement, windowEndMs = end, lifetime = plan.lifetime,
                reachedSystemLimit = limit, failedCount = failed)
        }
        val accepted = future.filter { held[it.id]?.accepted == true }
        val coverage = ShiftAlarmReconciliation.coverage(future, accepted, nowMs, end, plan.lifetime)
        val reminderAt = coverage.refreshAtMs
        val delivered = platform.refreshReminder(reminderAt, plan.refreshTitle, plan.refreshBody)
        return ShiftAlarmStatus(exact, notifications, entitlement, accepted, coverage.coveredThroughMs, end,
            plan.lifetime, limit, failed, reminderAt.takeIf { delivered }, reminderAt != null && !delivered)
    }

    @Synchronized fun receive(id: UUID, token: String, plan: AlarmPlan, nowMs: Long): AlarmRegistration? {
        val item = platform.registrations().firstOrNull { it.alarm.id == id } ?: return null
        if (!isAuthorized(plan, nowMs) || !item.accepted || item.ringing || item.token != token ||
            nowMs < item.scheduledAtMs || nowMs - item.scheduledAtMs > DELIVERY_GRACE_MS) return null
        if (plan.alarms.none { it == item.alarm }) { platform.cancel(id); return null }
        val ringing = item.copy(ringing = true)
        return ringing.takeIf { platform.markRinging(it) }
    }

    @Synchronized fun snooze(id: UUID, token: String, plan: AlarmPlan, nowMs: Long): Boolean {
        val current = platform.registrations().firstOrNull { it.alarm.id == id && it.token == token && it.ringing } ?: return false
        if (!isAuthorized(plan, nowMs) || plan.alarms.none { it == current.alarm }) { platform.cancel(id); return false }
        val fire = ShiftAlarmPlanner.snoozeAt(nowMs, plan.untilMs!!) ?: run { platform.cancel(id); return false }
        // A new token rejects any replay of the original alarm's pending intent or old notification.
        val request = current.copy(scheduledAtMs = fire, token = UUID.randomUUID().toString(), accepted = false, ringing = false, snoozed = true)
        platform.cancel(id)
        return platform.schedule(request) == AlarmScheduleOutcome.ACCEPTED
    }

    @Synchronized fun stop(id: UUID, token: String): Boolean {
        val item = platform.registrations().firstOrNull { it.alarm.id == id && it.token == token } ?: return false
        platform.cancel(item.alarm.id)
        return true
    }

    @Synchronized fun current(id: UUID, token: String, plan: AlarmPlan, nowMs: Long): AlarmRegistration? =
        platform.registrations().firstOrNull { it.alarm.id == id && it.token == token && it.ringing }
            ?.takeIf { isAuthorized(plan, nowMs) && plan.alarms.any { alarm -> alarm == it.alarm } }

    private fun isAuthorized(plan: AlarmPlan, nowMs: Long) = plan.enabled &&
        plan.untilMs?.let { it > nowMs } == true && platform.exactAllowed() && platform.notificationsAllowed()

    companion object { const val DELIVERY_GRACE_MS = 5 * 60_000L }
}
