package com.rainif.doneat.alarms

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import com.rainif.doneat.core.data.RecordStore
import com.rainif.doneat.core.data.RecordPersistenceError
import com.rainif.doneat.core.data.SessionStore
import com.rainif.doneat.core.data.SettingsRepository
import com.rainif.doneat.core.data.ShiftAlarmEntry
import com.rainif.doneat.core.data.ShiftAlarmSync
import com.rainif.doneat.core.domain.alarms.ShiftAlarmAuthorization
import com.rainif.doneat.core.domain.alarms.ShiftAlarmPlanner
import com.rainif.doneat.core.domain.session.RulesSource
import com.rainif.doneat.core.domain.settings.AppLanguages
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.plus.PlusAccess
import com.rainif.doneat.plus.PlusStatus
import com.rainif.doneat.ui.AppLocale
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale

class ShiftAlarmCoordinator(
    private val context: Context, private val settings: SettingsRepository,
    private val sessions: SessionStore, private val records: RecordStore, private val plus: PlusAccess, private val scope: CoroutineScope,
) {
    private val mutex = Mutex()
    private var first = true
    private var expiryJob: Job? = null
    fun start() {
        scope.launch(Dispatchers.IO) {
            combine(settings.device, sessions.session, plus.state, plus.authorized, records.persistenceError) { _, _, _, _, _ -> Unit }
                .collect { reconcile() }
        }
    }

    suspend fun reconcile(rearm: Boolean = false): Unit = withContext(Dispatchers.IO) {
        mutex.withLock {
            val now = System.currentTimeMillis()
            val sync = ShiftAlarms.sync(context)
            if (records.persistenceError.value in setOf(RecordPersistenceError.INVALID_ARCHIVE, RecordPersistenceError.UNREADABLE_ARCHIVE)) {
                sync.clear()
                return@withLock
            }
            val alarmSettings = settings.device.value.shiftAlarms
            val authorization = plus.shiftAlarmAuthorization(now)
            val session = sessions.session.value
            val old = sync.state.value
            val unknown = plus.state.value.status in setOf(PlusStatus.LOADING, PlusStatus.OFFLINE, PlusStatus.ERROR, PlusStatus.PENDING)
            // A transport failure cannot extend a previously verified deadline or revoke it early.
            val until = ShiftAlarmPlanner.windowEnd(authorization, now, session.recordsZone)
                ?: old.untilMs?.takeIf { unknown && old.enabled && it > now }
            val lifetime = authorization == ShiftAlarmAuthorization.Lifetime || (unknown && old.lifetime)
            val locale = Locale.forLanguageTag(AppLocale.tag(AppLanguages.effective(settings.preferences.value.languageOverride, AppLocale.systemPreferred())))
            val resources = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocales(LocaleList(locale)) }).resources
            val clock = DateTimeFormatter.ofPattern(if (android.text.format.DateFormat.is24HourFormat(context)) "HH:mm" else "h:mm a", locale)
                .withZone(session.countdownZone)
            // Same base configuration as LeavePlanning, with live leave already applied.
            val hours = session.rulesInput(now.toDouble(), source = RulesSource.BASE).hours
            val wanted = if (until != null) ShiftAlarmPlanner.alarms(hours, session.countdownZone, alarmSettings,
                now - ShiftAlarmSync.DELIVERY_GRACE_MS, until).map { alarm ->
                val time = clock.format(Instant.ofEpochMilli(alarm.shiftStartAtMs))
                ShiftAlarmEntry(alarm, alarm.shiftName?.let { Strings.shiftAlarmTitle(resources, it, time) }
                    ?: Strings.shiftAlarmTitleFixed(resources, time), until)
            } else emptyList()
            ShiftAlarms.channels(context)
            sync.reconcile(alarmSettings.enabled, until, lifetime, wanted, now, rearm || first)
            first = false
            expiryJob?.cancel()
            // One deadline while the process lives; each receiver also checks the durable deadline.
            expiryJob = until?.takeIf { alarmSettings.enabled && it > now }?.let { end -> scope.launch {
                delay(end - now)
                reconcile()
            } }
        }
    }
}
