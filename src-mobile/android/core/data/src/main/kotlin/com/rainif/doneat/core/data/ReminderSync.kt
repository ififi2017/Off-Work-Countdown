package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.reminders.AlarmTiming
import com.rainif.doneat.core.domain.reminders.PlannedReminder
import com.rainif.doneat.core.domain.reminders.ReminderChannel
import com.rainif.doneat.core.domain.reminders.ReminderDiff
import com.rainif.doneat.core.domain.reminders.ReminderPlanner
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull
import java.nio.file.Files
import java.nio.file.Path

/** The system alarm service, behind an interface so the sync logic runs on the JVM. */
interface AlarmPort {
    /** Re-read on every sync: the user can revoke the grant while the app is running. */
    fun canScheduleExact(): Boolean

    /** Registers or replaces the alarm for [reminder]. Throws when the system refuses it. */
    fun schedule(reminder: PlannedReminder, timing: AlarmTiming)
    fun cancel(id: String)
}

/** How the last sync went, for the settings row and for retrying. */
data class ReminderSyncResult(val scheduled: Int, val cancelled: Int, val failed: Int, val exact: Boolean) {
    val isComplete get() = failed == 0
}

/**
 * Keeps the system's alarms equal to what the planner wants.
 *
 * AlarmManager cannot list what it holds, so the registered set is kept in a
 * local file. That file is written before the system is called: an alarm the
 * system accepted is never lost, and the worst a crash leaves behind is an
 * entry the next sync cancels. A refused registration is taken back out, so
 * the next sync retries it. The file lives outside backups, because a
 * restored device holds none of these alarms.
 */
class ReminderSync(private val file: Path, private val alarms: AlarmPort) {
    private val mutex = Mutex()

    /** What the system holds, and whether it was registered with the exact-alarm grant. */
    private data class Registry(val exact: Boolean?, val alarms: List<PlannedReminder>)

    suspend fun registered(): List<PlannedReminder> = mutex.withLock { read().alarms }

    /** Makes the alarms under [prefix] exactly [desired]; other prefixes are left alone. */
    suspend fun sync(desired: List<PlannedReminder>, prefix: String): ReminderSyncResult = mutex.withLock {
        val registry = read()
        val kept = registry.alarms.filter { !it.id.startsWith(prefix) } + desired
        apply(registry, kept, ReminderPlanner.diff(registry.alarms, desired, prefix))
    }

    /**
     * After a reboot, clock or zone change, app update or a change to the
     * exact-alarm grant: re-register what is still ahead, drop what fell due
     * while nobody was listening. Nothing missed is fired late.
     */
    suspend fun restore(nowMs: Long): ReminderSyncResult = mutex.withLock {
        val registry = read()
        val diff = ReminderPlanner.restore(registry.alarms, nowMs.toDouble())
        // Everything still ahead is registered again: a reboot has cleared the system's copy.
        apply(registry, diff.schedule, diff)
    }

    /**
     * On returning to the app. Revoking the exact-alarm grant sends no
     * broadcast; the system just drops the exact alarms. When the grant no
     * longer matches the one the alarms were registered under, restore them;
     * otherwise do nothing, so this never races an alarm that is firing.
     */
    suspend fun revalidate(nowMs: Long): ReminderSyncResult? {
        val stale = mutex.withLock { read().let { it.alarms.isNotEmpty() && it.exact != alarms.canScheduleExact() } }
        return if (stale) restore(nowMs) else null
    }

    /**
     * The receiver's question when an alarm fires: the reminder to post, or
     * null when it was cancelled, replaced or is past its freshness window.
     * Answering removes it, so a second delivery of the same alarm posts nothing.
     */
    suspend fun take(id: String, nowMs: Long): PlannedReminder? = mutex.withLock {
        val registry = read()
        val reminder = registry.alarms.firstOrNull { it.id == id } ?: return@withLock null
        if (nowMs < reminder.atMs) return@withLock null
        write(registry.copy(alarms = registry.alarms - reminder))
        reminder.takeIf { it.isDeliverable(nowMs) }
    }

    suspend fun clear(prefix: String) = sync(emptyList(), prefix)

    /**
     * Persists [kept], then asks the system. When the exact-alarm grant differs
     * from the one the alarms were registered under, every kept alarm is
     * registered again so none keeps a timing it is no longer allowed.
     */
    private fun apply(registry: Registry, kept: List<PlannedReminder>, diff: ReminderDiff): ReminderSyncResult {
        val exact = alarms.canScheduleExact()
        val schedule = if (registry.exact == exact) diff.schedule else kept
        write(Registry(exact, kept))
        for (id in diff.cancel) alarms.cancel(id)
        val failed = schedule.filter { reminder ->
            runCatching { alarms.schedule(reminder, ReminderPlanner.timing(reminder.channel, exact)) }.isFailure
        }
        // An alarm the system refused is not held; leaving it registered would stop the next sync retrying it.
        if (failed.isNotEmpty()) write(Registry(exact, kept - failed.toSet()))
        return ReminderSyncResult(schedule.size - failed.size, diff.cancel.size, failed.size, exact)
    }

    // The file: {"exact": bool, "alarms": [...]}. A damaged file reads as empty:
    // at worst an orphaned alarm fires, finds nothing registered and posts nothing.

    private fun read(): Registry {
        if (!Files.exists(file)) return Registry(null, emptyList())
        return runCatching {
            val root = Json.parseToJsonElement(Files.readString(file)).jsonObject
            Registry(root["exact"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull(), root.getValue("alarms").jsonArray.map { it.jsonObject.toReminder() })
        }.getOrElse { Registry(null, emptyList()) }
    }

    private fun write(registry: Registry) {
        Files.createDirectories(file.parent)
        val root = JsonObject(mapOf(
            "exact" to (registry.exact?.let(::JsonPrimitive) ?: JsonNull),
            "alarms" to JsonArray(registry.alarms.sortedBy { it.atMs }.map { it.toJson() }),
        ))
        RecordStore.writeAtomically(file, root.toString().toByteArray())
    }

    private fun PlannedReminder.toJson() = JsonObject(
        mapOf(
            "id" to JsonPrimitive(id), "atMs" to JsonPrimitive(atMs), "channel" to JsonPrimitive(channel.name),
            "title" to JsonPrimitive(title), "body" to JsonPrimitive(body), "expiresAtMs" to (expiresAtMs?.let(::JsonPrimitive) ?: JsonNull),
        ),
    )

    private fun JsonObject.toReminder() = PlannedReminder(
        id = getValue("id").jsonPrimitive.content,
        atMs = getValue("atMs").jsonPrimitive.long,
        channel = ReminderChannel.valueOf(getValue("channel").jsonPrimitive.content),
        title = getValue("title").jsonPrimitive.content,
        body = getValue("body").jsonPrimitive.content,
        expiresAtMs = get("expiresAtMs")?.jsonPrimitive?.longOrNull,
    )
}
