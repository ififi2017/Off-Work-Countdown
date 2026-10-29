package com.rainif.doneat.widget

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import android.text.format.DateFormat
import android.util.AtomicFile
import com.rainif.doneat.AppGraph
import com.rainif.doneat.DoneAtApplication
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.alarms.ShiftAlarmAuthorization
import com.rainif.doneat.core.domain.records.RecordsQueries
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.settings.AppLanguages
import com.rainif.doneat.core.domain.widget.WidgetAccess
import com.rainif.doneat.core.domain.widget.WidgetFocusBlock
import com.rainif.doneat.core.domain.widget.WidgetSuiteComposer
import com.rainif.doneat.core.domain.widget.WidgetSuiteSnapshot
import com.rainif.doneat.ui.AppLocale
import com.rainif.doneat.ui.timer.TimerText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale
import java.util.Date
import java.time.DayOfWeek
import java.time.Instant

/** Device-only, salary-free projections. No purchase receipt or business archive is written here. */
object WidgetSuiteCoordinator {
    private fun file(context: Context) = File(context.noBackupFilesDir, "widget/suite.json")

    fun access(context: Context, graph: AppGraph, nowMs: Long): WidgetAccess {
        // The existing debug-only purchase stand-in is absent in release builds.
        if (!com.rainif.doneat.BuildConfig.CN_CHANNEL && com.rainif.doneat.plus.PlusDebugOverride.AVAILABLE && com.rainif.doneat.plus.PlusDebugOverride.read(context)) return WidgetAccess(true)
        return when (val proof = graph.plus.shiftAlarmAuthorization(nowMs)) {
        ShiftAlarmAuthorization.Lifetime -> WidgetAccess(true)
        is ShiftAlarmAuthorization.VerifiedUntil -> WidgetAccess(true, proof.expiresAtMs)
        ShiftAlarmAuthorization.Unavailable -> WidgetAccess.LOCKED
        }
    }

    suspend fun publish(context: Context): Boolean {
        val graph = (context.applicationContext as DoneAtApplication).graph
        val now = graph.nowMs().toLong()
        val snapshot = withContext(Dispatchers.Default) { compose(context, graph, now) }
        val encoded = snapshot.redacted(now).encode()
        return withContext(Dispatchers.IO) {
            val target = file(context)
            if (target.exists() && runCatching { target.readText() }.getOrNull() == encoded) return@withContext false
            target.parentFile?.mkdirs()
            val atomic = AtomicFile(target)
            val output = atomic.startWrite()
            try {
                output.write(encoded.toByteArray(Charsets.UTF_8))
                atomic.finishWrite(output)
            } catch (failure: Throwable) {
                atomic.failWrite(output)
                throw failure
            }
            true
        }
    }

    fun read(context: Context): WidgetSuiteSnapshot? = runCatching {
        val now = System.currentTimeMillis()
        val graph = (context.applicationContext as DoneAtApplication).graph
        val snapshot = WidgetSuiteSnapshot.decode(AtomicFile(file(context)).openRead().bufferedReader().use { it.readText() }) ?: return null
        // A cached lifetime snapshot must also disappear after revocation, not only at a stored expiry.
        val current = access(context, graph, now)
        snapshot.copy(
            summary = snapshot.summary.copy(access = boundedAccess(snapshot.summary.access, current)),
            life = snapshot.life.copy(access = boundedAccess(snapshot.life.access, current)),
            focus = snapshot.focus.copy(access = boundedAccess(snapshot.focus.access, current)),
            holiday = snapshot.holiday.copy(access = boundedAccess(snapshot.holiday.access, current)),
        ).redacted(now)
    }.getOrNull()

    private fun boundedAccess(saved: WidgetAccess, current: WidgetAccess): WidgetAccess {
        if (!saved.plus || !current.plus) return WidgetAccess.LOCKED
        return WidgetAccess(true, listOfNotNull(saved.validUntilMs, current.validUntilMs).minOrNull())
    }

    fun compose(context: Context, graph: AppGraph, now: Long): WidgetSuiteSnapshot {
        val session = graph.sessions.session.value
        val records = graph.records.state.value
        val prefs = session.env.preferences
        val locale = Locale.forLanguageTag(AppLocale.tag(AppLanguages.effective(prefs.languageOverride, AppLocale.systemPreferred())))
        val resources = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
            setLocales(LocaleList(locale))
        }).resources
        val text = TimerText(resources, locale, DateFormat.is24HourFormat(context), hideEarnings = true)
        val entitlement = access(context, graph, now)
        val queries = RecordsQueries(records, session.env.holidays, session.recordsZone, entitlement.isUnlocked(now),
            activeAnchorDayKey = session.snapshot(now.toDouble())?.takeIf { session.state.countdownStarted }
                ?.let { ShiftSession.dayKey(it.startAtMs, session.recordsZone) },
            currentHours = runCatching { session.hoursConfiguration(now.toDouble()) }.getOrNull(),
            firstDayOfWeek = graph.settings.device.value.calendarFirstDay(locale))
        val blocks = if (entitlement.isUnlocked(now)) focusBlocks(graph, now,
            resources.getString(R.string.focusTitle), resources.getString(R.string.focusBreak)) else emptyList()
        // Use the platform locale's weekend, matching Calendar.isDateInWeekend on iOS.
        val civilCalendar = android.icu.util.Calendar.getInstance(
            android.icu.util.TimeZone.getTimeZone(session.recordsZone.id), locale)
        val referenceDay = Instant.ofEpochMilli(now).atZone(session.recordsZone).toLocalDate()
        val weekendDays = (0L..6L).map { referenceDay.plusDays(it) }.filter { day ->
            civilCalendar.isWeekend(Date.from(day.atTime(12, 0).atZone(session.recordsZone).toInstant()))
        }.mapTo(mutableSetOf<DayOfWeek>()) { it.dayOfWeek }
        return WidgetSuiteComposer.compose(session, queries, now, locale.toLanguageTag(), entitlement, blocks,
            copy = { key -> resources.getString(copyKeys.getValue(key)) }, formatHours = text::hours,
            weekendDays = weekendDays)
    }

    private fun focusBlocks(graph: AppGraph, now: Long, focusTitle: String, breakTitle: String): List<WidgetFocusBlock> {
        val records = graph.records.state.value
        return com.rainif.doneat.core.domain.widget.WidgetFocusComposer.compose(
            records, graph.focus.environment(records), graph.focus.canvas(now.toDouble(), records), now, focusTitle, breakTitle)
    }

    // Explicit resources keep R8/resource shrinking and all generated locale variants aligned.
    private val copyKeys = mapOf(
        "widgetSuiteWork" to R.string.widgetSuiteWork, "widgetSuiteRest" to R.string.widgetSuiteRest,
        "widgetSuiteLeave" to R.string.widgetSuiteLeave, "widgetSuiteMakeupWork" to R.string.widgetSuiteMakeupWork,
        "widgetSuiteBigWeek" to R.string.widgetSuiteBigWeek, "widgetSuiteSmallWeek" to R.string.widgetSuiteSmallWeek,
        "widgetSuiteUntilWeekend" to R.string.widgetSuiteUntilWeekend, "widgetSuiteUntilRestDay" to R.string.widgetSuiteUntilRestDay,
        "widgetSuiteLeaveRemaining" to R.string.widgetSuiteLeaveRemaining, "widgetSuiteLeavePlan" to R.string.widgetSuiteLeavePlan,
        "widgetSuiteThisWeek" to R.string.widgetSuiteThisWeek, "widgetSuiteThisMonth" to R.string.widgetSuiteThisMonth,
        "widgetSuiteThisYear" to R.string.widgetSuiteThisYear, "widgetSuiteWeekNumber" to R.string.widgetSuiteWeekNumber,
        "widgetSuiteLastWeekTotal" to R.string.widgetSuiteLastWeekTotal, "widgetSuiteLastMonthTotal" to R.string.widgetSuiteLastMonthTotal,
        "widgetSuiteLastYearTotal" to R.string.widgetSuiteLastYearTotal, "daysShort" to R.string.daysShort,
    )
}
