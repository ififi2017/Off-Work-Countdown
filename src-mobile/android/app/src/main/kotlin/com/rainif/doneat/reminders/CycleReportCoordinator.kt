package com.rainif.doneat.reminders

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import com.rainif.doneat.R
import com.rainif.doneat.core.data.SettingsRepository
import com.rainif.doneat.core.domain.records.CycleReportKind
import com.rainif.doneat.core.domain.records.CycleReportNotificationPlan
import com.rainif.doneat.core.domain.reminders.PlannedReminder
import com.rainif.doneat.core.domain.reminders.ReminderChannel
import com.rainif.doneat.ui.AppLocale
import com.rainif.doneat.plus.PlusStoreState
import com.rainif.doneat.plus.PlusStatus
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.util.Locale

/** Absolute morning-after report registrations, independent of shift reminder budgets. */
class CycleReportCoordinator(
    private val context: Context,
    private val settings: SettingsRepository,
    private val authorized: StateFlow<Boolean>,
    private val scope: CoroutineScope,
    private val nowMs: () -> Double,
    private val storeState: StateFlow<PlusStoreState>,
) {
    private val reconciliation = Mutex()
    private var rearmFutureOnFirstSync = true

    fun start() {
        scope.launch {
            // TimerCoordinator's initial diff replaces legacy summary clock-off IDs with ordinary
            // copy; the report migration never cancels freshly rebuilt shift alarms.
            settings.migrateCycleReportNotifications()
            combine(settings.preferences, settings.device, authorized, storeState) { _, _, _, _ -> Unit }
                .collectLatest { reconcile() }
        }
    }

    suspend fun reconcile() = reconciliation.withLock {
        // A temporary purchase-query failure is not evidence that previously scheduled
        // reports should be removed. The receiver still reads its one-shot registry token.
        val entitlement = reportNotificationAccess(authorized.value, storeState.value)
        val p = settings.preferences.value
        val d = settings.device.value
        val configuredKinds = buildSet {
            if (d.weeklyReportEnabled) add(CycleReportKind.WEEK)
            if (d.monthlyReportEnabled) add(CycleReportKind.MONTH)
            if (d.yearlyReportEnabled) add(CycleReportKind.YEAR)
        }
        if (entitlement == null) {
            // Turning a kind off still cancels its future alarm and due token while
            // Billing is unavailable. Keep other registrations without arming new ones.
            val sync = Reminders.sync(context)
            val retained = sync.registered().filter { reminder ->
                reminder.id.startsWith(com.rainif.doneat.core.domain.records.CycleReportPeriod.PREFIX) &&
                    reminder.atMs > nowMs() && reminder.reportUrl?.let(com.rainif.doneat.core.domain.records.CycleReportPeriod::fromUrl)?.kind in configuredKinds
            }
            sync.syncReports(retained, configuredKinds, nowMs().toLong(), rearmFuture = false, permitFutureRegistration = false)
            rearmFutureOnFirstSync = true
            return@withLock
        }
        val locale = p.languageOverride?.let { Locale.forLanguageTag(AppLocale.tag(it)) } ?: context.resources.configuration.locales[0]
        val resources = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocales(LocaleList(locale)) }).resources
        val zone = runCatching { ZoneId.of(p.recordsTimeZoneIdentifier) }.getOrElse { ZoneId.systemDefault() }
        val items = CycleReportNotificationPlan.items(d.weeklyReportEnabled && entitlement, d.monthlyReportEnabled && entitlement,
            d.yearlyReportEnabled && entitlement, nowMs(), zone, d.calendarFirstDay(locale))
        val desired = items.map { period ->
            val (title, body) = when (period.kind) {
                CycleReportKind.WEEK -> R.string.reportNotificationWeekTitle to R.string.reportNotificationWeekBody
                CycleReportKind.MONTH -> R.string.reportNotificationMonthTitle to R.string.reportNotificationMonthBody
                CycleReportKind.YEAR -> R.string.reportNotificationYearTitle to R.string.reportNotificationYearBody
            }
            PlannedReminder(period.notificationIdentifier, period.notificationAtMs, ReminderChannel.REPORT,
                resources.getString(title), resources.getString(body), reportUrl = period.url)
        }
        ReminderNotifier.ensureChannels(context, mapOf(ReminderChannel.REPORT to resources.getString(R.string.reportEntryTitle)))
        val enabled = if (!entitlement) emptySet() else configuredKinds
        val result = Reminders.sync(context).syncReports(desired, enabled, nowMs().toLong(), rearmFutureOnFirstSync)
        if (result.isComplete) rearmFutureOnFirstSync = false
    }
}

/** Unknown/offline purchases cannot revoke the previously verified notification registrations. */
internal fun reportNotificationAccess(authorized: Boolean, store: PlusStoreState): Boolean? = when {
    authorized || store.authorized -> true
    store.status == PlusStatus.FREE || store.status == PlusStatus.UNCONFIGURED -> false
    else -> null
}
