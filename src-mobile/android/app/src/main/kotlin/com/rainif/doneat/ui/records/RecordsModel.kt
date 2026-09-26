package com.rainif.doneat.ui.records

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.core.domain.records.DayResolution
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.RecordsDayCell
import com.rainif.doneat.core.domain.records.RecordsHeadlineSummary
import com.rainif.doneat.core.domain.records.RecordsQueries
import com.rainif.doneat.core.domain.records.RecordsScale
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.ui.timer.TimerText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.temporal.WeekFields

/**
 * What every records page reads: one archive revision's queries, its
 * formatters and the minute they were built for. A retrospective page is not
 * a countdown, so "now" advances on the minute, and only while it is visible.
 */
@Immutable
class RecordsContext(val queries: RecordsQueries, val text: RecordsText, val nowMs: Double, val lifeInputs: LifeInputs) {
    val today: LocalDate get() = queries.today(nowMs)
}

/** Inputs that can change Life's income or schedule without changing the archive. */
data class LifeInputs(
    val archive: RecordState,
    val preferences: SyncedPreferences,
    val holidays: HolidayCalendar,
    val session: ShiftSession,
    val hideEarnings: Boolean,
    val today: LocalDate,
)

@Composable
fun rememberRecordsContext(graph: AppGraph): RecordsContext {
    val context = LocalContext.current
    val resources = LocalResources.current
    val locale = LocalConfiguration.current.locales[0]
    val archive by graph.records.state.collectAsStateWithLifecycle()
    val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val plus by graph.plus.authorized.collectAsStateWithLifecycle()
    val holidays by graph.holidays.collectAsStateWithLifecycle()
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val nowMs = rememberMinute(graph)
    val use24Hour = android.text.format.DateFormat.is24HourFormat(context)
    val zone = FoundationCompat.javaZone(prefs.recordsTimeZoneIdentifier)
    val queries = remember(archive, prefs, plus, holidays, session, nowMs, locale) {
        RecordsQueries(
            state = archive,
            holidays = holidays,
            zone = zone,
            authorized = plus,
            salary = if (prefs.salaryEnabled) session.salary else null,
            dailySalary = if (prefs.salaryEnabled) currentShift(session, nowMs)?.dailySalary else null,
            activeAnchorDayKey = if (session.state.countdownStarted) {
                currentShift(session, nowMs)?.let { ShiftSession.dayKey(it.startAtMs, zone) }
            } else {
                null
            },
            currentHours = runCatching { session.hoursConfiguration(nowMs) }.getOrNull(),
            firstDayOfWeek = WeekFields.of(locale).firstDayOfWeek,
        )
    }
    val text = remember(resources, locale, zone, use24Hour, device.hideEarnings) {
        RecordsText(resources, locale, zone, use24Hour, TimerText(resources, locale, use24Hour, device.hideEarnings))
    }
    val lifeInputs = LifeInputs(archive, prefs, holidays, session, device.hideEarnings, queries.today(nowMs))
    return remember(queries, text, nowMs, lifeInputs) { RecordsContext(queries, text, nowMs, lifeInputs) }
}

private fun currentShift(session: ShiftSession, nowMs: Double) =
    if (session.shouldQuerySnapshot(nowMs)) session.snapshot(nowMs) else null

/** The current minute, advancing while the page is at least started. */
@Composable
private fun rememberMinute(graph: AppGraph): Double {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var minute by remember { mutableDoubleStateOf(floorMinute(graph.nowMs())) }
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                minute = floorMinute(graph.nowMs())
                delay((minute + 60_000 - graph.nowMs()).toLong().coerceAtLeast(1_000))
            }
        }
    }
    return minute
}

private fun floorMinute(ms: Double) = kotlin.math.floor(ms / 60_000) * 60_000

/** Show a scale before saving it; the caller passes the app scope so tab changes do not drop the write. */
internal fun switchRecordsScale(next: RecordsScale, show: (String) -> Unit, appScope: CoroutineScope, save: suspend (String) -> Unit) {
    show(next.raw)
    appScope.launch { save(next.raw) }
}

/** One loaded window: its days (with one lead-in day), cells and summary. */
@Immutable
data class RecordsPage(
    val scale: RecordsScale,
    val first: LocalDate,
    val last: LocalDate,
    val days: List<DayResolution>,
    val cells: List<RecordsDayCell>,
    val headline: RecordsHeadlineSummary?,
)

/**
 * The window around [anchor]. One lead-in day is resolved because a shift
 * ending at 06:00 on the first began the night before; it is never drawn.
 */
fun loadPage(context: RecordsContext, scale: RecordsScale, anchor: LocalDate): RecordsPage {
    val q = context.queries
    val (first, last) = q.window(scale, anchor)
    val days = q.displayDays(first.minusDays(1), last, context.nowMs)
    val cells = q.cells(days, first, context.nowMs)
    return RecordsPage(scale, first, last, days, cells, q.headline(cells, days, context.nowMs))
}
