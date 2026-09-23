package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordEditContext
import com.rainif.doneat.core.domain.records.ScheduleHoursCodec
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.session.KeptRosterDay
import com.rainif.doneat.core.domain.session.ScheduleDecision
import com.rainif.doneat.core.domain.session.ScheduleFieldChange
import com.rainif.doneat.core.domain.session.ScheduleSave
import com.rainif.doneat.core.domain.session.SessionCommands
import com.rainif.doneat.core.domain.session.SessionEnvironment
import com.rainif.doneat.core.domain.session.SessionRecords
import com.rainif.doneat.core.domain.session.SessionResult
import com.rainif.doneat.core.domain.session.SessionState
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.TodayScheduleOverride
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID

/**
 * The running countdown (iOS `ShiftSession` + `ShiftSessionStore`): its
 * device-local state, the environment it reads from settings and the
 * archive, and one lock for every command.
 *
 * A command's session change and its archive writes land together: a
 * rejected command, or one the archive refuses (damaged or unreadable), leaves
 * both as they were. When only the disk write fails, the session keeps the
 * user's action, as iOS keeps its accepted edit in memory, and the archive
 * retries on its next write.
 *
 * The state file lives beside the device settings and never in the archive:
 * the frozen clock-off snapshot carries the daily salary.
 */
class SessionStore(
    private val file: Path,
    private val records: RecordStore,
    private val settings: SettingsRepository,
    scope: CoroutineScope,
    /** The bundled holiday dataset, empty until it has been read off the main thread. */
    private val holidays: StateFlow<HolidayCalendar>,
    private val deviceZone: () -> String,
    private val newId: () -> String,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val mutex = Mutex()
    private val _state = MutableStateFlow(SessionState())
    val state: StateFlow<SessionState> = _state.asStateFlow()

    /** Rebuilt whenever settings, setup or the archive's schedule changes; plans inside it are built once. */
    val environment: StateFlow<SessionEnvironment> = combine(settings.preferences, settings.isSetUp, records.state, holidays) { prefs, setUp, archive, days ->
        SessionEnvironment(prefs, setUp, archive.extendedSchedule, archive.rosterDays, days, deviceZone())
    }.stateIn(scope, SharingStarted.Eagerly, currentEnvironment())

    val session: StateFlow<ShiftSession> = combine(state, environment, ::ShiftSession)
        .stateIn(scope, SharingStarted.Eagerly, ShiftSession(_state.value, environment.value))

    private fun currentEnvironment() = SessionEnvironment(
        settings.preferences.value, settings.isSetUp.value, records.state.value.extendedSchedule, records.state.value.rosterDays,
        holidays.value, deviceZone(),
    )

    /**
     * Reads the state file. The first launch on a device that is already set
     * up with a schedule (restored, or transferred) arms the countdown, as
     * iOS's one-time automatic-countdown migration does.
     */
    suspend fun load() = mutex.withLock {
        val stored = withContext(io) { read() }
        _state.value = stored ?: SessionState(
            countdownStarted = settings.isSetUp.value &&
                ScheduleMode.fromRaw(settings.preferences.value.scheduleMode) != ScheduleMode.OFF,
        )
        if (stored == null && _state.value.countdownStarted) write(_state.value)
    }

    /**
     * Runs one session command against the current state at [nowMs]. Returns
     * whether it was accepted and kept.
     */
    suspend fun run(nowMs: Double, command: SessionCommands.(SessionState) -> SessionResult): Boolean = mutex.withLock {
        if (records.blocksWrites) return@withLock false
        val env = currentEnvironment()
        val result = SessionCommands(env, newId).command(_state.value)
        if (!result.accepted) return@withLock false
        if (result.effects.isNotEmpty()) {
            val context = RecordEditContext(
                nowMs = nowMs,
                recordsTimeZone = env.preferences.recordsTimeZoneIdentifier,
                canEdit = true,
                holidays = env.holidays,
                currentHours = { ShiftSession(result.state, env).hoursConfiguration(nowMs) },
                newId = newId,
            )
            val write = records.update { archive -> SessionRecords.apply(archive, result.effects, context) to Unit }
            if (write is WriteResult.Blocked) return@withLock false
        }
        if (result.state != _state.value) {
            write(result.state)
            _state.value = result.state
        }
        true
    }

    /**
     * Saves the schedule page (preferences, extended schedule, calendar and
     * Records snapshot in one archive write) and moves today's marks as
     * [decision] says. False when refused, unchanged or not written.
     */
    suspend fun applyScheduleChange(change: ScheduleFieldChange, decision: ScheduleDecision, nowMs: Double): Boolean = mutex.withLock {
        if (records.blocksWrites) return@withLock false
        val env = currentEnvironment()
        var saved: ScheduleSave.Result? = null
        val write = records.update { archive ->
            val result = ScheduleSave.apply(archive, _state.value, env.with(archive), change, decision, nowMs, newId)
            saved = result
            (result?.records ?: archive) to Unit
        }
        val result = saved ?: return@withLock false
        if (write !is WriteResult.Saved) return@withLock false
        if (result.state != _state.value) {
            write(result.state)
            _state.value = result.state
        }
        true
    }

    private suspend fun write(state: SessionState) = withContext(io) {
        runCatching {
            Files.createDirectories(file.parent)
            RecordStore.writeAtomically(file, SessionStateJson.encode(state).toByteArray())
        }
    }

    private fun read(): SessionState? = runCatching {
        if (!Files.exists(file)) return null
        SessionStateJson.decode(Json.parseToJsonElement(Files.readString(file)).jsonObject)
    }.getOrElse { SessionState() }
}

/** The session file's codec. Unknown or damaged fields read as absent: a lost mark never blocks the timer. */
internal object SessionStateJson {
    fun encode(s: SessionState): String = JsonObject(
        mapOf(
            "countdownStarted" to JsonPrimitive(s.countdownStarted),
            "sessionTimeZone" to s.sessionTimeZone.json(),
            "sessionTimeZoneUntilMs" to s.sessionTimeZoneUntilMs.json(),
            "earlyOffAtMs" to s.earlyOffAtMs.json(),
            "earlyOffShiftEndAtMs" to s.earlyOffShiftEndAtMs.json(),
            "earlyOffSnapshot" to (s.earlyOffSnapshot?.let(::snapshot) ?: JsonNull),
            "earlyStartAtMs" to s.earlyStartAtMs.json(),
            "earlyStartUntilMs" to s.earlyStartUntilMs.json(),
            "todayOverride" to (s.todayOverride?.let(::kept) ?: JsonNull),
            "forcedWorkdayDate" to s.forcedWorkdayDate.json(),
            "overtimeEndAtMs" to s.overtimeEndAtMs.json(),
            "activeCountdownEndAtMs" to s.activeCountdownEndAtMs.json(),
        ),
    ).toString()

    fun decode(o: JsonObject) = SessionState(
        countdownStarted = o.bool("countdownStarted") ?: false,
        // A relaunch is a new run identity, as iOS generates one per launch.
        sessionId = UUID.randomUUID().toString(),
        sessionTimeZone = o.str("sessionTimeZone"),
        sessionTimeZoneUntilMs = o.num("sessionTimeZoneUntilMs"),
        earlyOffAtMs = o.num("earlyOffAtMs"),
        earlyOffShiftEndAtMs = o.num("earlyOffShiftEndAtMs"),
        earlyOffSnapshot = (o["earlyOffSnapshot"] as? JsonObject)?.let { runCatching { snapshot(it) }.getOrNull() },
        earlyStartAtMs = o.num("earlyStartAtMs"),
        earlyStartUntilMs = o.num("earlyStartUntilMs"),
        todayOverride = (o["todayOverride"] as? JsonObject)?.let { runCatching { kept(it) }.getOrNull() },
        forcedWorkdayDate = o.str("forcedWorkdayDate"),
        overtimeEndAtMs = o.num("overtimeEndAtMs"),
        activeCountdownEndAtMs = o.num("activeCountdownEndAtMs"),
    )

    private fun snapshot(s: ShiftSnapshot) = JsonObject(
        mapOf(
            "segments" to JsonArray(s.segments.map { JsonArray(listOf(JsonPrimitive(it.startAtMs), JsonPrimitive(it.endAtMs))) }),
            "startAtMs" to JsonPrimitive(s.startAtMs), "endAtMs" to JsonPrimitive(s.endAtMs),
            "plannedEndAtMs" to JsonPrimitive(s.plannedEndAtMs), "overtimeEndAtMs" to s.overtimeEndAtMs.json(),
            "durationMs" to JsonPrimitive(s.durationMs), "plannedDurationMs" to JsonPrimitive(s.plannedDurationMs),
            "elapsedMs" to JsonPrimitive(s.elapsedMs), "remainingMs" to JsonPrimitive(s.remainingMs),
            "progress" to JsonPrimitive(s.progress), "payRatio" to JsonPrimitive(s.payRatio),
            "activeBreakEndAtMs" to s.activeBreakEndAtMs.json(), "isWorkday" to JsonPrimitive(s.isWorkday),
            "nextRestAtMs" to s.nextRestAtMs.json(), "dailySalary" to s.dailySalary.json(), "earnedSoFar" to s.earnedSoFar.json(),
            "nextShiftStartAtMs" to s.nextShiftStartAtMs.json(), "nextShiftEndAtMs" to s.nextShiftEndAtMs.json(),
            "countdownTargetAtMs" to s.countdownTargetAtMs.json(), "countdownAnchorAtMs" to s.countdownAnchorAtMs.json(),
            "countdownProgress" to JsonPrimitive(s.countdownProgress),
        ),
    )

    private fun snapshot(o: JsonObject) = ShiftSnapshot(
        segments = o.getValue("segments").jsonArray.map { ShiftSegment(it.jsonArray[0].jsonPrimitive.content.toDouble(), it.jsonArray[1].jsonPrimitive.content.toDouble()) },
        startAtMs = o.req("startAtMs"), endAtMs = o.req("endAtMs"), plannedEndAtMs = o.req("plannedEndAtMs"),
        overtimeEndAtMs = o.num("overtimeEndAtMs"), durationMs = o.req("durationMs"), plannedDurationMs = o.req("plannedDurationMs"),
        elapsedMs = o.req("elapsedMs"), remainingMs = o.req("remainingMs"), progress = o.req("progress"), payRatio = o.req("payRatio"),
        activeBreakEndAtMs = o.num("activeBreakEndAtMs"), isWorkday = o.bool("isWorkday") ?: error("isWorkday"),
        nextRestAtMs = o.num("nextRestAtMs"), dailySalary = o.num("dailySalary"), earnedSoFar = o.num("earnedSoFar"),
        nextShiftStartAtMs = o.num("nextShiftStartAtMs"), nextShiftEndAtMs = o.num("nextShiftEndAtMs"),
        countdownTargetAtMs = o.num("countdownTargetAtMs"), countdownAnchorAtMs = o.num("countdownAnchorAtMs"),
        countdownProgress = o.req("countdownProgress"),
    )

    private fun kept(k: TodayScheduleOverride) = JsonObject(
        mapOf(
            "startMinutes" to JsonPrimitive(k.startMinutes), "endMinutes" to JsonPrimitive(k.endMinutes),
            "workdays" to JsonArray(k.workdays.map(::JsonPrimitive)), "scheduleMode" to JsonPrimitive(k.scheduleMode),
            "lunchEnabled" to JsonPrimitive(k.lunchEnabled), "lunchStartMinutes" to JsonPrimitive(k.lunchStartMinutes),
            "lunchDurationMinutes" to JsonPrimitive(k.lunchDurationMinutes), "alternatingWeekType" to JsonPrimitive(k.alternatingWeekType),
            "alternatingWeekendWorkday" to JsonPrimitive(k.alternatingWeekendWorkday),
            "alternatingReferenceWeekStartMs" to JsonPrimitive(k.alternatingReferenceWeekStartMs),
            "rotationWorkDays" to JsonPrimitive(k.rotationWorkDays), "rotationRestDays" to JsonPrimitive(k.rotationRestDays),
            "rotationAnchorMs" to JsonPrimitive(k.rotationAnchorMs), "untilMs" to JsonPrimitive(k.untilMs),
            "extendedScheduleEnabled" to (k.extendedScheduleEnabled?.let(::JsonPrimitive) ?: JsonNull),
            "extendedContent" to (k.extendedContent?.let(ScheduleHoursCodec::contentJson) ?: JsonNull),
            "extendedKeptDay" to (
                k.extendedKeptDay?.let { JsonObject(mapOf("dayKey" to JsonPrimitive(it.dayKey), "shiftTypeID" to it.shiftTypeID?.toString().json())) }
                    ?: JsonNull
                ),
        ),
    )

    private fun kept(o: JsonObject) = TodayScheduleOverride(
        startMinutes = o.int("startMinutes"), endMinutes = o.int("endMinutes"),
        workdays = o.getValue("workdays").jsonArray.map { it.jsonPrimitive.content.toInt() },
        scheduleMode = o.str("scheduleMode") ?: error("scheduleMode"), lunchEnabled = o.bool("lunchEnabled") ?: error("lunchEnabled"),
        lunchStartMinutes = o.int("lunchStartMinutes"), lunchDurationMinutes = o.int("lunchDurationMinutes"),
        alternatingWeekType = o.str("alternatingWeekType") ?: error("alternatingWeekType"),
        alternatingWeekendWorkday = o.int("alternatingWeekendWorkday"),
        alternatingReferenceWeekStartMs = o.req("alternatingReferenceWeekStartMs"),
        rotationWorkDays = o.int("rotationWorkDays"), rotationRestDays = o.int("rotationRestDays"),
        rotationAnchorMs = o.req("rotationAnchorMs"), untilMs = o.req("untilMs"),
        extendedScheduleEnabled = o.bool("extendedScheduleEnabled"),
        extendedContent = (o["extendedContent"] as? JsonObject)?.let(ScheduleHoursCodec::decodeContent),
        extendedKeptDay = (o["extendedKeptDay"] as? JsonObject)?.let { d ->
            KeptRosterDay(d.str("dayKey") ?: error("dayKey"), d.str("shiftTypeID")?.let(UUID::fromString))
        },
    )

    private fun Double?.json(): JsonElement = this?.let(::JsonPrimitive) ?: JsonNull
    private fun String?.json(): JsonElement = this?.let(::JsonPrimitive) ?: JsonNull
    private fun JsonObject.num(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
    private fun JsonObject.req(key: String) = num(key) ?: error(key)
    private fun JsonObject.int(key: String) = (this[key] as? JsonPrimitive)?.intOrNull ?: error(key)
    private fun JsonObject.str(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
    private fun JsonObject.bool(key: String) = (this[key] as? JsonPrimitive)?.booleanOrNull
}
