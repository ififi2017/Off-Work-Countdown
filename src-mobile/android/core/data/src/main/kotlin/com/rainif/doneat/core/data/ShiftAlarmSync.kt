package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.alarms.PlannedShiftAlarm
import com.rainif.doneat.core.domain.alarms.ShiftAlarmPlanner
import com.rainif.doneat.core.domain.alarms.ShiftAlarmReconciliation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID

/** No salary, purchase token or records. This journal belongs to this installation only. */
data class ShiftAlarmEntry(
    val alarm: PlannedShiftAlarm,
    val title: String,
    val untilMs: Long,
    val phase: Phase = Phase.WAITING,
    val ringingSinceMs: Long? = null,
) {
    enum class Phase { REGISTERING, WAITING, RINGING, SNOOZED }
}

data class ShiftAlarmRegistry(
    val enabled: Boolean = false,
    val untilMs: Long? = null,
    val lifetime: Boolean = false,
    val entries: List<ShiftAlarmEntry> = emptyList(),
    val refreshAtMs: Long? = null,
    val refreshAccepted: Boolean = false,
    val failed: Int = 0,
    val coveredThroughMs: Long? = null,
) {
    fun waiting(nowMs: Long) = entries.filter {
        it.phase in setOf(ShiftAlarmEntry.Phase.WAITING, ShiftAlarmEntry.Phase.SNOOZED) && it.alarm.fireAtMs > nowMs
    }.sortedBy { it.alarm.fireAtMs }
}

/** A successful return means AlarmManager accepted the call, not that the OS guarantees delivery. */
interface ShiftAlarmPort {
    fun permitted(): Boolean
    fun schedule(entry: ShiftAlarmEntry)
    fun cancel(id: UUID)
    fun scheduleRefresh(atMs: Long)
    fun cancelRefresh()
}

/**
 * Atomic journal plus differential system registration. A REGISTERING entry is
 * written first, but never claimed as accepted. A restart retries it. Deliveries
 * consume a waiting entry once; stale intents cannot start or snooze another alarm.
 */
class ShiftAlarmSync(private val file: Path, private val port: ShiftAlarmPort) {
    private val mutex = Mutex()
    private val _state = MutableStateFlow(read())
    val state = _state.asStateFlow()

    suspend fun reconcile(
        enabled: Boolean, untilMs: Long?, lifetime: Boolean,
        wanted: List<ShiftAlarmEntry>, nowMs: Long, rearm: Boolean = false,
    ): ShiftAlarmRegistry = mutex.withLock {
        val old = _state.value
        if (!enabled || untilMs == null || untilMs <= nowMs || !port.permitted()) {
            clearLocked()
            return@withLock _state.value
        }
        val desired = wanted.filter { it.alarm.fireAtMs < untilMs }.associateBy { it.alarm.id }
        val retained = old.entries.mapNotNull { entry ->
            when {
                entry.phase == ShiftAlarmEntry.Phase.RINGING &&
                    entry.ringingSinceMs != null && nowMs < entry.ringingSinceMs + RING_TIMEOUT_MS -> entry.copy(untilMs = untilMs)
                entry.phase == ShiftAlarmEntry.Phase.SNOOZED && entry.alarm.fireAtMs > nowMs && entry.alarm.fireAtMs < untilMs -> entry.copy(untilMs = untilMs)
                entry.phase == ShiftAlarmEntry.Phase.WAITING && entry.alarm.fireAtMs <= nowMs &&
                    nowMs < entry.alarm.fireAtMs + DELIVERY_GRACE_MS && desired[entry.alarm.id]?.alarm == entry.alarm -> entry.copy(untilMs = untilMs)
                else -> null
            }
        }
        val future = desired.values.filter { it.alarm.fireAtMs > nowMs }.map { it.copy(untilMs = untilMs) }
        val held = old.entries.associateBy { it.alarm.id }
        val next = (retained + future).distinctBy { it.alarm.id }
        val schedule = next.sortedBy { it.alarm.fireAtMs }.filter { entry ->
            entry.phase != ShiftAlarmEntry.Phase.RINGING && entry.alarm.fireAtMs > nowMs &&
                (rearm || held[entry.alarm.id]?.let { it.alarm == entry.alarm && it.phase == entry.phase } != true)
        }
        if (!rearm && schedule.isEmpty() && next == old.entries && old.enabled &&
            old.untilMs == untilMs && old.lifetime == lifetime && old.failed == 0) return@withLock old
        val schedulingIDs = schedule.map { it.alarm.id }.toSet()
        val journal = next.map { if (it.alarm.id in schedulingIDs) it.copy(phase = ShiftAlarmEntry.Phase.REGISTERING) else it }
        // Revoke delivery tokens before canceling system alarms; a racing receiver sees the new plan.
        save(ShiftAlarmRegistry(true, untilMs, lifetime, journal))
        val wantedIDs = next.map { it.alarm.id }.toSet()
        old.entries.filter { it.alarm.id !in wantedIDs }.forEach { runCatching { port.cancel(it.alarm.id) } }
        runCatching { port.cancelRefresh() }
        val failed = schedule.filter { runCatching { port.schedule(it) }.isFailure }.map { it.alarm.id }.toSet()
        failed.forEach { runCatching { port.cancel(it) } }
        val accepted = next.filter { it.alarm.id !in failed }
        val coverage = ShiftAlarmReconciliation.coverage(
            future.map { it.alarm }, accepted.filter { it.phase == ShiftAlarmEntry.Phase.WAITING }.map { it.alarm },
            nowMs, untilMs, lifetime,
        )
        val refresh = refreshAfterAccepted(accepted, nowMs, untilMs, lifetime)
        val refreshAccepted = refresh != null && runCatching { port.scheduleRefresh(refresh) }.isSuccess
        save(ShiftAlarmRegistry(true, untilMs, lifetime, accepted, refresh, refreshAccepted, failed.size, coverage.coveredThroughMs))
        _state.value
    }

    /** Reboot loses system registrations. Missed and formerly ringing alarms are discarded. */
    suspend fun restore(nowMs: Long, afterReboot: Boolean = true): ShiftAlarmRegistry = mutex.withLock {
        val old = _state.value
        if (!old.enabled || (old.untilMs ?: 0) <= nowMs || !port.permitted()) {
            clearLocked()
            return@withLock _state.value
        }
        val future = old.entries.filter { it.phase != ShiftAlarmEntry.Phase.RINGING && it.alarm.fireAtMs > nowMs && it.alarm.fireAtMs < (old.untilMs ?: 0) }
        val ringing = if (afterReboot) emptyList() else old.entries.filter {
            it.phase == ShiftAlarmEntry.Phase.RINGING && nowMs < minOf(it.untilMs, (it.ringingSinceMs ?: 0) + RING_TIMEOUT_MS)
        }
        save(old.copy(entries = ringing + future.map { it.copy(phase = ShiftAlarmEntry.Phase.REGISTERING) }, refreshAccepted = false))
        old.entries.filter { it !in future && it !in ringing }.forEach { runCatching { port.cancel(it.alarm.id) } }
        val accepted = future.sortedBy { it.alarm.fireAtMs }.filter {
            runCatching { port.schedule(it) }.onFailure { _ -> runCatching { port.cancel(it.alarm.id) } }.isSuccess
        }.map {
            if (it.phase == ShiftAlarmEntry.Phase.REGISTERING) it.copy(phase = ShiftAlarmEntry.Phase.WAITING) else it
        }
        runCatching { port.cancelRefresh() }
        val refresh = (accepted.maxOfOrNull { it.alarm.fireAtMs }?.plus(ShiftAlarmReconciliation.REFRESH_DELAY_MS)
            ?: old.refreshAtMs?.takeIf { future.isEmpty() })
            ?.takeIf { it > nowMs && (old.lifetime || it < (old.untilMs ?: 0)) }
        val refreshAccepted = refresh != null && runCatching { port.scheduleRefresh(refresh) }.isSuccess
        val coverage = ShiftAlarmReconciliation.coverage(future.map { it.alarm }, accepted.map { it.alarm }, nowMs, old.untilMs!!, old.lifetime)
        save(old.copy(entries = ringing + accepted, refreshAtMs = refresh, refreshAccepted = refreshAccepted,
            failed = old.failed + future.size - accepted.size,
            coveredThroughMs = old.coveredThroughMs?.let { previous -> coverage.coveredThroughMs?.let { minOf(previous, it) } }?.takeIf { it > nowMs }))
        _state.value
    }

    suspend fun take(id: UUID, nowMs: Long): ShiftAlarmEntry? = mutex.withLock {
        val old = _state.value
        val entry = old.entries.firstOrNull { it.alarm.id == id } ?: return@withLock null
        if (!old.enabled || entry.phase !in setOf(ShiftAlarmEntry.Phase.WAITING, ShiftAlarmEntry.Phase.SNOOZED) ||
            nowMs < entry.alarm.fireAtMs) return@withLock null
        if (!port.permitted() || nowMs >= entry.untilMs || nowMs >= entry.alarm.fireAtMs + DELIVERY_GRACE_MS) {
            save(old.copy(entries = old.entries - entry))
            return@withLock null
        }
        val ringing = entry.copy(phase = ShiftAlarmEntry.Phase.RINGING, ringingSinceMs = nowMs)
        save(old.copy(entries = old.entries.map { if (it.alarm.id == id) ringing else it }))
        ringing
    }

    suspend fun stop(id: UUID) = mutex.withLock {
        val old = _state.value
        save(old.copy(entries = old.entries.filterNot { it.alarm.id == id }))
        runCatching { port.cancel(id) }
    }

    suspend fun snooze(id: UUID, nowMs: Long): Boolean = mutex.withLock {
        val old = _state.value
        val entry = old.entries.firstOrNull { it.alarm.id == id && it.phase == ShiftAlarmEntry.Phase.RINGING } ?: return@withLock false
        val at = ShiftAlarmPlanner.snoozeAt(nowMs, entry.untilMs)
        if (!old.enabled || !port.permitted() || at == null) return@withLock false
        val snoozed = entry.copy(alarm = entry.alarm.copy(fireAtMs = at), phase = ShiftAlarmEntry.Phase.SNOOZED, ringingSinceMs = null)
        save(old.copy(entries = old.entries.map { if (it.alarm.id == id) snoozed.copy(phase = ShiftAlarmEntry.Phase.REGISTERING) else it }))
        val accepted = runCatching { port.schedule(snoozed) }.isSuccess
        val entries = old.entries.mapNotNull { if (it.alarm.id == id) snoozed.takeIf { accepted } else it }
        runCatching { port.cancelRefresh() }
        val refresh = refreshAfterAccepted(entries, nowMs, entry.untilMs, old.lifetime)
        val refreshed = refresh != null && runCatching { port.scheduleRefresh(refresh) }.isSuccess
        save(old.copy(entries = entries, failed = if (accepted) old.failed else old.failed + 1,
            refreshAtMs = refresh, refreshAccepted = refreshed))
        accepted
    }

    suspend fun takeRefresh(nowMs: Long): Boolean = mutex.withLock {
        val old = _state.value
        val at = old.refreshAtMs ?: return@withLock false
        if (!old.enabled || !old.refreshAccepted || nowMs < at) return@withLock false
        save(old.copy(refreshAtMs = null, refreshAccepted = false))
        nowMs - at < 24 * 60 * 60_000L
    }

    suspend fun clear() = mutex.withLock { clearLocked() }

    private fun refreshAfterAccepted(entries: List<ShiftAlarmEntry>, nowMs: Long, untilMs: Long, lifetime: Boolean): Long? {
        val scheduled = entries.filter { it.phase in setOf(ShiftAlarmEntry.Phase.WAITING, ShiftAlarmEntry.Phase.SNOOZED) }.map { it.alarm }
        return ShiftAlarmReconciliation.coverage(scheduled, scheduled, nowMs, untilMs, lifetime).refreshAtMs
    }

    private fun clearLocked() {
        val old = _state.value
        save(ShiftAlarmRegistry())
        old.entries.forEach { runCatching { port.cancel(it.alarm.id) } }
        runCatching { port.cancelRefresh() }
    }

    private fun save(next: ShiftAlarmRegistry) {
        if (next == _state.value) return
        val data = buildJsonObject {
            put("enabled", next.enabled); put("untilMs", next.untilMs?.let(::JsonPrimitive) ?: JsonNull)
            put("lifetime", next.lifetime); put("refreshAtMs", next.refreshAtMs?.let(::JsonPrimitive) ?: JsonNull)
            put("refreshAccepted", next.refreshAccepted); put("failed", next.failed)
            put("coveredThroughMs", next.coveredThroughMs?.let(::JsonPrimitive) ?: JsonNull)
            put("entries", JsonArray(next.entries.map { e -> buildJsonObject {
                put("id", e.alarm.id.toString()); put("fireAtMs", e.alarm.fireAtMs); put("shiftStartAtMs", e.alarm.shiftStartAtMs)
                put("dayKey", e.alarm.dayKey); put("shiftTypeID", e.alarm.shiftTypeID?.toString()?.let(::JsonPrimitive) ?: JsonNull)
                put("shiftName", e.alarm.shiftName?.let(::JsonPrimitive) ?: JsonNull); put("title", e.title)
                put("untilMs", e.untilMs); put("phase", e.phase.name)
                put("ringingSinceMs", e.ringingSinceMs?.let(::JsonPrimitive) ?: JsonNull)
            } }))
        }
        Files.createDirectories(file.parent)
        RecordStore.writeAtomically(file, data.toString().toByteArray())
        _state.value = next
    }

    private fun read(): ShiftAlarmRegistry = runCatching {
        if (!Files.exists(file)) return ShiftAlarmRegistry()
        val o = Json.parseToJsonElement(Files.readString(file)).jsonObject
        fun JsonObject.long(key: String) = getValue(key).jsonPrimitive.long
        fun JsonObject.text(key: String) = getValue(key).jsonPrimitive.content
        ShiftAlarmRegistry(o.getValue("enabled").jsonPrimitive.boolean, o["untilMs"]?.jsonPrimitive?.longOrNull,
            o.getValue("lifetime").jsonPrimitive.boolean, o.getValue("entries").jsonArray.map { value ->
                val e = value.jsonObject
                ShiftAlarmEntry(PlannedShiftAlarm(UUID.fromString(e.text("id")), e.long("fireAtMs"), e.long("shiftStartAtMs"), e.text("dayKey"),
                    e["shiftTypeID"]?.jsonPrimitive?.contentOrNull?.let(UUID::fromString), e["shiftName"]?.jsonPrimitive?.contentOrNull),
                    e.text("title"), e.long("untilMs"), ShiftAlarmEntry.Phase.valueOf(e.text("phase")), e["ringingSinceMs"]?.jsonPrimitive?.longOrNull)
            }, o["refreshAtMs"]?.jsonPrimitive?.longOrNull, o.getValue("refreshAccepted").jsonPrimitive.boolean, o["failed"]?.jsonPrimitive?.intOrNull ?: 0, o["coveredThroughMs"]?.jsonPrimitive?.longOrNull)
    }.getOrElse { ShiftAlarmRegistry() }

    companion object {
        const val DELIVERY_GRACE_MS = 60_000L
        const val RING_TIMEOUT_MS = 10 * 60_000L
    }
}
