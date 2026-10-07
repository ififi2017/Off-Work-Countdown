package com.rainif.doneat.alarms

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.LocaleList
import com.rainif.doneat.core.domain.settings.AppLanguages
import com.rainif.doneat.ui.AppLocale
import java.util.Locale
import android.text.format.DateFormat
import androidx.core.content.ContextCompat
import com.rainif.doneat.R
import com.rainif.doneat.core.data.AlarmSettingsStore
import com.rainif.doneat.core.data.SessionStore
import com.rainif.doneat.core.domain.alarms.*
import com.rainif.doneat.core.domain.session.RulesSource
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.plus.PlusAccess
import com.rainif.doneat.ui.timer.TimerText
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.ZoneId
import java.util.UUID

class ShiftAlarmCoordinator(
    private val context: Context,
    private val sessions: SessionStore,
    private val plus: PlusAccess,
    private val alarmSettings: AlarmSettingsStore,
    private val scope: CoroutineScope,
    private val ready: StateFlow<Boolean>,
    private val nowMs: () -> Double,
    /** Fresh committed archive/settings snapshot; avoids asynchronous stateIn projection lag at delivery. */
    private val sessionProvider: () -> ShiftSession = { sessions.session.value },
) {
    private val platform = AndroidShiftAlarmPlatform(context)
    private val engine = ShiftAlarmEngine(platform)
    private val mutex = Mutex()
    private var started = false
    private val _status = MutableStateFlow(ShiftAlarmStatus())
    val status = _status.asStateFlow()
    val settings = alarmSettings.settings
    init { current = this }

    fun start() {
        if (started) return
        started = true
        scope.launch {
            ready.first { it }
            combine(sessions.session, settings, plus.state) { _, _, _ -> Unit }.collectLatest { reconcile() }
        }
    }

    fun refresh() { scope.launch { ready.first { it }; reconcile() } }
    fun setEnabled(enabled: Boolean) { scope.launch {
        if (enabled && authorization() == ShiftAlarmAuthorization.Unavailable) return@launch
        alarmSettings.update { it.copy(enabled = enabled) }
        reconcile()
    } }
    fun setLead(typeID: UUID?, minutes: Int?) { scope.launch {
        alarmSettings.update { old -> when {
            typeID == null && minutes != null -> old.copy(defaultLeadMinutes = minutes)
            typeID != null && minutes == null -> old.copy(silencedShiftTypeIDs = old.silencedShiftTypeIDs + typeID)
            typeID != null && minutes != null -> old.copy(leadMinutesByShiftType = old.leadMinutesByShiftType + (typeID to minutes),
                silencedShiftTypeIDs = old.silencedShiftTypeIDs - typeID)
            else -> old
        } }
        reconcile()
    } }
    fun authorization(): ShiftAlarmAuthorization = plus.state.value.shiftAlarmAuthorization(nowMs().toLong())

    suspend fun onSystemEvent(rebuildRegistrations: Boolean) {
        ready.first { it }
        mutex.withLock { if (rebuildRegistrations) platform.invalidateRegistrations(); _status.value = engine.reconcile(plan(), nowMs().toLong()) }
    }
    private suspend fun reconcile() = mutex.withLock { _status.value = engine.reconcile(plan(), nowMs().toLong()) }

    /** Called only by our non-exported exact alarm receiver; this never opens an Activity or a display. */
    internal suspend fun deliver(id: UUID, token: String) {
        ready.first { it }
        mutex.withLock {
            val registration = engine.receive(id, token, plan(), nowMs().toLong()) ?: return@withLock
            try { ContextCompat.startForegroundService(context,
                Intent(context, ShiftAlarmRingingService::class.java).putExtra("id", registration.alarm.id.toString())
                    .putExtra(AndroidShiftAlarmPlatform.EXTRA_TOKEN, registration.token)) }
            catch (_: Exception) { engine.stop(id, token) }
        }
    }
    internal fun ringingRemainingMs(): Long? = when (val auth = authorization()) {
        ShiftAlarmAuthorization.Unavailable -> 0L
        ShiftAlarmAuthorization.Lifetime -> null
        is ShiftAlarmAuthorization.VerifiedUntil -> (auth.expiresAtMs - nowMs().toLong()).coerceAtLeast(0)
    }
    internal fun currentRinging(id: UUID, token: String): AlarmRegistration? = engine.current(id, token, plan(recentOnly = true), nowMs().toLong())
    internal fun stop(id: UUID, token: String) { scope.launch { stopAndReconcile(id, token) } }
    internal suspend fun stopAndReconcile(id: UUID, token: String) {
        ready.first { it }
        mutex.withLock { engine.stop(id, token); _status.value = engine.reconcile(plan(), nowMs().toLong()) }
    }
    internal fun snooze(id: UUID, token: String) { scope.launch { snoozeAndReconcile(id, token) } }
    internal suspend fun snoozeAndReconcile(id: UUID, token: String) {
        ready.first { it }
        mutex.withLock { engine.snooze(id, token, plan(), nowMs().toLong()); _status.value = engine.reconcile(plan(), nowMs().toLong()) }
    }

    internal fun languageOverride() = sessionProvider().env.preferences.languageOverride
    internal fun resources(): android.content.res.Resources {
        val code = AppLanguages.effective(languageOverride(), AppLocale.systemPreferred())
        val locale = Locale.forLanguageTag(AppLocale.tag(code))
        return context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocales(LocaleList(locale)) }).resources
    }
    private fun plan(recentOnly: Boolean = false): AlarmPlan {
        val now = nowMs().toLong()
        val session = sessionProvider()
        val auth = authorization()
        val zone: ZoneId = session.recordsZone
        val until = ShiftAlarmPlanner.windowEnd(auth, now, zone)
        val enabled = settings.value.enabled && session.env.onboardingComplete
        // BASE contains committed future schedule and adopted leave, never today's early start/overtime.
        val hours = session.rulesInput(now.toDouble(), source = RulesSource.BASE, pinsEarlyStart = false).hours
        val alarms = if (until != null && enabled) ShiftAlarmPlanner.alarms(hours, zone, settings.value,
            now - RECENT_SHIFT_MS, if (recentOnly) minOf(until, now + 24 * 60 * 60_000L) else until) else emptyList()
        val res = resources()
        val text = TimerText(res, res.configuration.locales[0], DateFormat.is24HourFormat(context), true, zone)
        return AlarmPlan(enabled, until, auth == ShiftAlarmAuthorization.Lifetime, alarms, title = { alarm ->
            val clock = text.time(alarm.shiftStartAtMs.toDouble())
            alarm.shiftName?.let { Strings.shiftAlarmTitle(res, it, clock) } ?: Strings.shiftAlarmTitleFixed(res, clock)
        }, refreshTitle = res.getString(R.string.shiftAlarmRefreshTitle), refreshBody = res.getString(R.string.shiftAlarmRefreshBody))
    }

    companion object { private const val RECENT_SHIFT_MS = 36 * 60 * 60_000L
        @Volatile internal var current: ShiftAlarmCoordinator? = null }
}
