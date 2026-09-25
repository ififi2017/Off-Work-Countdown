package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.focus.FocusChain
import com.rainif.doneat.core.domain.focus.FocusEngine
import com.rainif.doneat.core.domain.focus.FocusNextAction
import com.rainif.doneat.core.domain.focus.FocusPlanner
import com.rainif.doneat.core.domain.focus.FocusPlanning
import com.rainif.doneat.core.domain.focus.FocusStep
import com.rainif.doneat.core.domain.focus.Planned
import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.session.SessionFocusEnvironment
import com.rainif.doneat.core.domain.session.ShiftSession
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.file.Files
import java.nio.file.Path

/**
 * The focus runtime (iOS `FocusStore`): the pure rules in `focus/` applied to
 * the archive, plus the little state that lives beside it.
 *
 * - [nextAction] is the call to action after a phase ends. It is in memory
 *   and read back from history on launch.
 * - The queue holds today's plan-driven sessions, with identities derived
 *   from their blocks. It is saved on the device (never synced or backed up
 *   with the archive), so a process that dies mid-block restores the block at
 *   its own start instead of starting it again.
 *
 * Every write is one archive write. Nothing here reads a clock.
 */
class FocusStore(
    private val records: RecordStore,
    private val session: StateFlow<ShiftSession>,
    private val authorized: StateFlow<Boolean>,
    private val queueFile: Path,
    private val newId: () -> String,
    private val defaultTaskTitle: () -> String = { "Focus" },
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val mutex = Mutex()
    private val _nextAction = MutableStateFlow(FocusNextAction.NONE)
    val nextAction: StateFlow<FocusNextAction> = _nextAction.asStateFlow()

    private val _queue = MutableStateFlow<List<FocusSession>>(emptyList())
    /** Today's queued plan-driven starts; the coordinator wakes for the first. */
    val queue: StateFlow<List<FocusSession>> = _queue.asStateFlow()
    private var queueLoaded = false

    /** Set when a start was refused for lack of room, so the page can say why. */
    @Volatile var rejectedNoRoom = false
        private set

    fun environment(state: RecordState = records.state.value) =
        SessionFocusEnvironment(session.value, state, authorized.value, _queue.value, newId)

    fun engine(state: RecordState = records.state.value) = FocusEngine(environment(state))
    fun planning(state: RecordState = records.state.value) = FocusPlanning(environment(state), defaultTaskTitle())

    // Reads

    fun activeSession(state: RecordState = records.state.value) = engine(state).activeSession(state)
    fun canvas(nowMs: Double, state: RecordState = records.state.value) = planning(state).canvas(state, nowMs)

    /** A day is complete when nothing runs and the last phase finished every planned task. */
    fun dayComplete(nowMs: Double, state: RecordState = records.state.value): Boolean {
        val engine = engine(state)
        if (engine.activeSession(state) != null) return false
        val last = engine.sessionsOnDay(state, engine.dayKey(nowMs)).filter { it.endedAtMs != null }.maxByOrNull { it.startedAtMs } ?: return false
        return engine.completesDay(state, last, nowMs)
    }

    // Writes

    /** One lifecycle step in one archive write; the step's next action is kept only when it was written. */
    suspend fun step(op: (RecordState, FocusNextAction, FocusEngine) -> FocusStep): Boolean = mutex.withLock { stepLocked(op) }

    private suspend fun stepLocked(op: (RecordState, FocusNextAction, FocusEngine) -> FocusStep): Boolean {
        var result: FocusStep? = null
        val write = records.update { state ->
            val step = op(state, _nextAction.value, engine(state))
            result = step
            step.state to Unit
        }
        val step = result ?: return false
        if (write !is WriteResult.Saved) return false
        _nextAction.value = step.nextAction
        return step.ok
    }

    /** A planning command in one archive write. Null when nothing was written. */
    suspend fun <T> plan(op: (RecordState, FocusPlanning) -> Planned<T>): T? = mutex.withLock {
        var value: T? = null
        val write = records.update { state ->
            val planned = op(state, planning(state))
            value = planned.value
            planned.state to Unit
        }
        if (write is WriteResult.Saved) value else null
    }

    /** A planning edit that returns only the next archive. */
    suspend fun edit(op: (RecordState, FocusPlanning) -> RecordState): Boolean = mutex.withLock {
        records.update { state -> op(state, planning(state)) to Unit } is WriteResult.Saved
    }

    // Starting and ending

    /**
     * Starts [taskID] now; [blockStartAtMs] names the current plan block it
     * fills, which then ends where that block ends. True only if a block
     * actually started: haptics follow this, not the tap.
     */
    suspend fun start(taskID: String, nowMs: Double, blockStartAtMs: Long? = null): Boolean = mutex.withLock {
        restoreScheduledLocked(nowMs)
        val blockEnd = blockStartAtMs?.let { start ->
            val block = canvas(nowMs).blocks.firstOrNull { it.startAtMs == start } ?: return@withLock false
            val fits = block.state == com.rainif.doneat.core.domain.focus.FocusDayCanvas.State.CURRENT &&
                block.kind == com.rainif.doneat.core.domain.records.FocusPlanBlockKind.TASK && !block.isUserBreak && block.taskID == taskID
            if (!fits) return@withLock false
            block.endAtMs.toDouble()
        }
        rejectedNoRoom = !engine().hasRoom(nowMs)
        stepLocked { state, next, engine -> engine.startFocus(state, next, taskID, nowMs, blockEnd) }
    }

    /** Creates a task and starts its first block in one write; nothing is written if it cannot start. */
    suspend fun addAndStart(title: String, pomodoros: Int, icon: FocusTaskIcon, isFavorite: Boolean, nowMs: Double): Boolean = mutex.withLock {
        restoreScheduledLocked(nowMs)
        rejectedNoRoom = !engine().hasRoom(nowMs)
        stepLocked { state, next, engine ->
            val added = planning(state).addTask(state, title.trim(), pomodoros, nowMs, icon = icon, isFavorite = isFavorite)
            val started = engine.startFocus(added.state, next, added.value.id, nowMs)
            if (started.ok) started else FocusStep(state, next, ok = false)
        }
    }

    /** Sets what is left of a task to [pomodoros] more blocks, then starts one; one write, or none. */
    suspend fun updateAndStart(taskID: String, pomodoros: Int, nowMs: Double): Boolean = mutex.withLock {
        restoreScheduledLocked(nowMs)
        stepLocked { state, next, engine ->
            val task = state.focusTasks.firstOrNull { it.id == taskID && it.deletedAtMs == null } ?: return@stepLocked FocusStep(state, next, ok = false)
            val updated = engine.upsertTask(state, task.copy(estimatedPomodoros = engine.completedBlocks(state, task) + maxOf(1, pomodoros)), nowMs)
            val started = engine.startFocus(updated, next, taskID, nowMs)
            if (started.ok) started else FocusStep(state, next, ok = false)
        }
    }

    /**
     * When the last requested block would end (iOS `focusCreationFinish`):
     * starting now, a first block then the rest in the plan's free blocks;
     * otherwise the blocks from [startingAt]. Null when they do not all fit.
     */
    fun creationFinish(pomodoros: Int, startingAt: Long?, startNow: Boolean, taskID: String?, nowMs: Double): Double? {
        if (pomodoros <= 0) return null
        val state = records.state.value
        val engine = engine(state)
        val planning = planning(state)
        if (startNow) {
            val shift = environment(state).shift(nowMs)
            if (engine.activeSession(state) != null || !engine.hasRoom(nowMs) || shift == null) return null
            val focusMinutes = planning.settings(state).focusMinutes
            val end = FocusPlanner.plannedEnd(nowMs, shift.segments, environment(state).overtimeEndAtMs, focusMinutes)
            if (FocusPlanner.endReason(nowMs, end, focusMinutes) != FocusEndReason.COMPLETED) return null
            if (pomodoros == 1) return end
            val probe = FocusSession(
                "probe", taskID, engine.dayKey(shift.startAtMs), nowMs, end, null, null, nowMs, 0, "probe",
                FocusSessionKind.FOCUS, environment(state).recordsTimeZone, engine.dayKey(nowMs), null, FocusEndReason.COMPLETED,
            )
            val breakEnd = engine.plannedBreakEnd(engine.nextBreakKind(state, probe), end) ?: return null
            val projected = FocusChain.projectedBlocks(taskID ?: "", pomodoros - 1, canvas(nowMs, state).blocks, breakEnd.toLong())
            return if (projected.size == pomodoros - 1) projected.last().endAtMs.toDouble() else null
        }
        startingAt ?: return null
        val blocks = planning.creationBlocks(state, pomodoros, startingAt, nowMs, taskID)
        return if (blocks.size == pomodoros) blocks.last().endAtMs.toDouble() else null
    }

    suspend fun stop(reason: FocusEndReason, nowMs: Double) = step { state, _, engine -> engine.stop(state, reason, nowMs) }

    suspend fun startBreak(kind: FocusSessionKind, nowMs: Double) = step { state, next, engine -> engine.startBreak(state, next, kind, nowMs) }

    suspend fun skipPhase(nowMs: Double) = step { state, next, engine -> engine.skipPhase(state, next, nowMs) }

    suspend fun skipSuggestedBreak() = step { state, next, engine -> engine.skipSuggestedBreak(state, next) }

    /** Ends a phase whose planned end has passed, at that end; true if one ended. */
    suspend fun finishElapsed(nowMs: Double) = step { state, next, engine -> engine.finishElapsed(state, next, nowMs) }

    // Lifecycle

    /**
     * Launch, foreground and day change (iOS `reconcileCountdownSession`'s
     * focus part): carry unfinished tasks forward, record queued starts that
     * have arrived, keep one open session, end an elapsed one.
     */
    suspend fun reconcile(nowMs: Double) = mutex.withLock {
        loadQueue()
        records.update { state -> planning(state).carryIncomplete(state, nowMs) to Unit }
        restoreScheduledLocked(nowMs)
        stepLocked { state, _, engine -> engine.reconcile(state, nowMs) }
        stepLocked { state, next, engine -> engine.finishElapsed(state, next, nowMs) }
        Unit
    }

    /** The default usual day, applied once per day before anything else is planned. */
    suspend fun applyDefaultTemplateIfNeeded(nowMs: Double) = plan { state, planning -> planning.applyDefaultTemplateIfNeeded(state, nowMs) }

    /**
     * Assignment is authorisation: today's remaining assigned blocks become the
     * queue, reusing entries already queued so their starts never move.
     */
    suspend fun refreshScheduled(nowMs: Double): List<FocusSession> = mutex.withLock {
        loadQueue()
        restoreScheduledLocked(nowMs)
        val next = planning().scheduledSessions(records.state.value, _queue.value, nowMs)
        setQueue(next)
        restoreScheduledLocked(nowMs)
        _queue.value
    }

    private suspend fun restoreScheduledLocked(nowMs: Double) {
        loadQueue()
        if (_queue.value.none { it.startedAtMs <= nowMs }) return
        var remaining = _queue.value
        var action = _nextAction.value
        val write = records.update { state ->
            val (next, queue, nextAction) = planning(state).restoreScheduled(state, _queue.value, _nextAction.value, nowMs)
            remaining = queue
            action = nextAction
            next to Unit
        }
        if (write is WriteResult.Saved) {
            _nextAction.value = action
            setQueue(remaining)
        }
    }

    // The queue file

    private suspend fun loadQueue() {
        if (queueLoaded) return
        queueLoaded = true
        _queue.value = withContext(io) { runCatching { decodeQueue(Files.readString(queueFile)) }.getOrDefault(emptyList()) }
    }

    private suspend fun setQueue(queue: List<FocusSession>) {
        if (queue == _queue.value) return
        _queue.value = queue
        withContext(io) {
            runCatching {
                Files.createDirectories(queueFile.parent)
                RecordStore.writeAtomically(queueFile, encodeQueue(queue).toByteArray())
            }
        }
    }

    companion object {
        fun encodeQueue(queue: List<FocusSession>) = JsonArray(
            queue.map { s ->
                JsonObject(
                    mapOf(
                        "id" to JsonPrimitive(s.id),
                        "taskID" to JsonPrimitive(s.taskID),
                        "shiftAnchorDate" to JsonPrimitive(s.shiftAnchorDate),
                        "startedAtMs" to JsonPrimitive(s.startedAtMs),
                        "plannedEndAtMs" to JsonPrimitive(s.plannedEndAtMs),
                        "editedAtMs" to JsonPrimitive(s.editedAtMs),
                        "editTieBreaker" to JsonPrimitive(s.editTieBreaker),
                        "timeZoneIdentifier" to JsonPrimitive(s.timeZoneIdentifier),
                        "anchorDayKey" to JsonPrimitive(s.anchorDayKey),
                    ),
                )
            },
        ).toString()

        /** Only plan-driven focus blocks are ever queued, so everything else is implied. */
        fun decodeQueue(text: String): List<FocusSession> = Json.parseToJsonElement(text).jsonArray.mapNotNull { element ->
            val o = element.jsonObject
            fun str(key: String) = o[key]?.jsonPrimitive?.contentOrNull
            fun num(key: String) = o[key]?.jsonPrimitive?.takeIf { !it.isString }?.doubleOrNull
            FocusSession(
                id = str("id") ?: return@mapNotNull null,
                taskID = str("taskID") ?: return@mapNotNull null,
                shiftAnchorDate = str("shiftAnchorDate") ?: return@mapNotNull null,
                startedAtMs = num("startedAtMs") ?: return@mapNotNull null,
                plannedEndAtMs = num("plannedEndAtMs") ?: return@mapNotNull null,
                endedAtMs = null,
                endReason = null,
                editedAtMs = num("editedAtMs") ?: 0.0,
                editCount = 0,
                editTieBreaker = str("editTieBreaker") ?: return@mapNotNull null,
                kind = FocusSessionKind.FOCUS,
                timeZoneIdentifier = str("timeZoneIdentifier") ?: return@mapNotNull null,
                anchorDayKey = str("anchorDayKey") ?: return@mapNotNull null,
                actualDurationSeconds = null,
                plannedEndReason = FocusEndReason.COMPLETED,
            )
        }
    }
}
