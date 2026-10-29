package com.rainif.doneat.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import android.os.SystemClock
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.collection.intSetOf
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.PreviewSizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.compose.ui.graphics.Color
import androidx.glance.color.ColorProvider
import com.rainif.doneat.MainActivity
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.widget.WidgetEntry
import com.rainif.doneat.core.domain.widget.WidgetCountdownKind
import com.rainif.doneat.core.domain.widget.WidgetPhase
import com.rainif.doneat.core.domain.widget.WidgetUpcomingItem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.math.roundToInt

private val SMALL = DpSize(110.dp, 110.dp)
private val MEDIUM = DpSize(220.dp, 110.dp)
private val LARGE = DpSize(220.dp, 250.dp)

/**
 * Light and dark pairs; the widget follows the system's look, as the iOS
 * widget does. `widget_colors.xml` repeats the two the hosted countdown and
 * the brand mark need.
 */
private object WidgetColors {
    private fun pair(day: Long, night: Long) = ColorProvider(day = Color(day), night = Color(night))
    val background = pair(0xFFFFFFFF, 0xFF1C1C1E)
    val primary = pair(0xFF1C1B1F, 0xFFF2F2F7)
    val secondary = pair(0xFF6E6A70, 0xFFA1A1A6)
    val track = pair(0x1A000000, 0x2EFFFFFF)
    /** iOS widget accent (1.0, 0.38, 0.08), in both looks. */
    val accent = pair(0xFFFF6114, 0xFFFF6114)
    val accentSoft = pair(0x1FFF6114, 0x38FF6114)
    val before = pair(0xFF5856D6, 0xFF5E5CE6)
    val breakTime = pair(0xFF32ADE6, 0xFF64D2FF)
    val done = pair(0xFF34C759, 0xFF30D158)
}

/**
 * The home-screen countdown (iOS `OffWorkCountdownWidget`): small, medium
 * and large. It only picks the snapshot's interval for the current moment;
 * all schedule rules ran in the app. With no snapshot, or one past its
 * expiry, it says so and asks for the app.
 */
class DoneAtWidget(private val previewSize: DpSize = SMALL, private val kind: DoneAtWidgetKind = DoneAtWidgetKind.CLASSIC) : GlanceAppWidget() {
    // Both artwork and hosted timer must use the actual host dimensions; responsive buckets would scale only the image.
    override val sizeMode = SizeMode.Exact
    override val previewSizeMode: PreviewSizeMode = SizeMode.Responsive(setOf(previewSize))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val first = withContext(Dispatchers.IO) { WidgetCoordinator.read(context) }
        provideContent {
            // A running session only recomposes on update, it never calls provideGlance again:
            // the snapshot and the clock are re-read whenever the app or the refresh alarm signals.
            val tick by WidgetSignals.tick.collectAsState()
            val snapshot by produceState(first, tick) { value = withContext(Dispatchers.IO) { WidgetCoordinator.read(context) } }
            val now = remember(tick, snapshot) { System.currentTimeMillis() }
            val entry = snapshot?.entry(now)
            LaunchedEffect(tick, snapshot) { WidgetRefresh.schedule(context, entry, now) }
            val localized = remember(snapshot?.locale) { snapshot?.locale?.let { localized(context, it) } ?: context }
            val suite by produceState<com.rainif.doneat.core.domain.widget.WidgetSuiteSnapshot?>(null, tick) {
                value = withContext(Dispatchers.IO) { WidgetSuiteCoordinator.read(context) }
            }
            Content(localized, snapshot?.upcoming.orEmpty(), entry, now, kind, suite?.countdownSegments.orEmpty(), suite?.countdownTimeZoneIdentifier)
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val now = System.currentTimeMillis()
        val entry = WidgetEntry(
            dateMs = now,
            validUntilMs = now + 4 * 60 * 60_000L,
            phase = WidgetPhase.WORKING,
            labelKey = "widgetWorking",
            countdownKind = WidgetCountdownKind.WORK_REMAINING,
            countdownValueAtDateMs = 4 * 60 * 60_000L,
            countdownTargetAtMs = null,
            remainingEffectiveMsAtDateMs = 4 * 60 * 60_000L,
            progressAtDate = 48.0,
            nextBoundaryAtMs = now + 4 * 60 * 60_000L,
        )
        val upcoming = listOf(WidgetUpcomingItem("lunch", "break", context.getString(R.string.lunchBreak), "", now + 60 * 60_000L))
        provideContent { Content(context, upcoming, entry, now, kind, emptyList()) }
    }

    private fun localized(context: Context, tag: String): Context {
        val configuration = Configuration(context.resources.configuration).apply { setLocales(LocaleList(Locale.forLanguageTag(tag))) }
        return context.createConfigurationContext(configuration)
    }
}

/** Bumped whenever the widget should look again: a new snapshot, or a refresh alarm. */
internal object WidgetSignals {
    val tick = MutableStateFlow(0L)

    private val widgets: List<Pair<Class<out GlanceAppWidgetReceiver>, GlanceAppWidget>> = listOf(
        DoneAtWidgetReceiver::class.java to DoneAtWidget(SMALL),
        DoneAtWidgetMediumReceiver::class.java to DoneAtWidget(MEDIUM),
        DoneAtWidgetLargeReceiver::class.java to DoneAtWidget(LARGE),
    ) + DoneAtWidgetKind.entries.filter { it != DoneAtWidgetKind.CLASSIC }.map { it.receiver to it.widget() }
    private val receivers get() = widgets.map { it.first }

    suspend fun redraw(context: Context) {
        tick.update { it + 1 }
        val manager = GlanceAppWidgetManager(context)
        val appWidgets = AppWidgetManager.getInstance(context)
        widgets.forEach { (receiver, widget) ->
            appWidgets.getAppWidgetIds(ComponentName(context, receiver)).forEach { widget.update(context, manager.getGlanceIdBy(it)) }
        }
    }

    fun hasWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return receivers.any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
    }

    fun hasCountdownWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        val countdowns = listOf(DoneAtWidgetReceiver::class.java, DoneAtWidgetMediumReceiver::class.java, DoneAtWidgetLargeReceiver::class.java) +
            DoneAtWidgetKind.entries.filter { it.countdown }.map { it.receiver }
        return countdowns.any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
    }

    fun installedSuiteKinds(context: Context): Set<DoneAtWidgetKind> {
        val manager = AppWidgetManager.getInstance(context)
        return DoneAtWidgetKind.entries.filter { !it.countdown && manager.getAppWidgetIds(ComponentName(context, it.receiver)).isNotEmpty() }.toSet()
    }

    fun hasSuiteWidgets(context: Context) = installedSuiteKinds(context).isNotEmpty()

    suspend fun publishMissingPreviews(context: Context) {
        if (Build.VERSION.SDK_INT < 35) return
        val retry = context.getSharedPreferences("widget_preview_publish", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - retry.getLong("rateLimitedAt", 0L) < 2 * 60 * 60_000L) return
        val appWidgets = AppWidgetManager.getInstance(context)
        val glance = GlanceAppWidgetManager(context)
        val category = AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN
        for (receiver in receivers) {
            val provider = appWidgets.installedProviders.firstOrNull { it.provider == ComponentName(context, receiver) } ?: continue
            if (provider.generatedPreviewCategories and category != 0) continue
            if (glance.setWidgetPreviews(receiver.kotlin, intSetOf(category)) == GlanceAppWidgetManager.SET_WIDGET_PREVIEWS_RESULT_RATE_LIMITED) {
                retry.edit().putLong("rateLimitedAt", now).apply()
                break
            }
        }
    }
}

/** Three picker entries share one renderer; the original receiver stays for existing 2×2 widgets. */
abstract class DoneAtWidgetBaseReceiver(private val previewSize: DpSize) : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DoneAtWidget(previewSize)

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        if (!WidgetSignals.hasWidgets(context)) WidgetRefresh.cancel(context)
    }
}

class DoneAtWidgetReceiver : DoneAtWidgetBaseReceiver(SMALL)
class DoneAtWidgetMediumReceiver : DoneAtWidgetBaseReceiver(MEDIUM)
class DoneAtWidgetLargeReceiver : DoneAtWidgetBaseReceiver(LARGE)

/** Redraws at the next interval boundary (and every 15 minutes while progress moves). Never wakes the phone. */
class WidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                val graph = (context.applicationContext as com.rainif.doneat.DoneAtApplication).graph
                graph.loaded.first { it }
                graph.plus.reviewAccess.awaitLoaded()
                graph.plus.revalidateLocalAccess()
                val now = System.currentTimeMillis()
                val suite = WidgetSuiteCoordinator.read(context)
                val force = intent.action == Intent.ACTION_LOCALE_CHANGED
                val civilDayChanged = suite?.let { snapshot ->
                    listOf(snapshot.timeZoneIdentifier, snapshot.lifeTimeZoneIdentifier).any { zoneID ->
                        val zone = ZoneId.of(zoneID)
                        Instant.ofEpochMilli(snapshot.generatedAtMs).atZone(zone).toLocalDate() != Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
                    }
                } == true
                if (force || civilDayChanged) graph.widgets.refresh()
                WidgetSignals.redraw(context)
            } finally {
                pending.finish()
            }
        }
    }
}

internal object WidgetRefresh {
    private fun intent(context: Context) = PendingIntent.getBroadcast(
        context, 0, Intent(context, WidgetRefreshReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /**
     * The next redraw: the end of the current interval, sooner while a bar is
     * filling. RTC, not RTC_WAKEUP: a sleeping phone shows nobody a widget,
     * and the alarm fires as soon as it wakes. Exact only when the user has
     * already allowed exact alarms for reminders.
     */
    fun schedule(context: Context, entry: WidgetEntry?, nowMs: Long) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val kinds = WidgetSignals.installedSuiteKinds(context)
        // The suite cache also exists for people who installed only legacy
        // countdowns. Its presence must not turn their 15-minute refresh into
        // a minute alarm, or add calendars they never placed on the launcher.
        val suite = if (kinds.isEmpty()) null else WidgetSuiteCoordinator.read(context)
        val ordinaryAt = widgetNextRefreshAt(entry.takeIf { WidgetSignals.hasCountdownWidgets(context) }, suite, kinds, nowMs) ?: return manager.cancel(intent(context))
        val plus = (context.applicationContext as com.rainif.doneat.DoneAtApplication).graph.plus
        val reviewUntil = if (!plus.state.value.authorized) plus.reviewAccess.verifiedExpiry(nowMs) else null
        val at = minOf(ordinaryAt, reviewUntil ?: ordinaryAt)
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        if (exact) manager.setExact(AlarmManager.RTC, at, intent(context))
        else manager.setWindow(AlarmManager.RTC, at, 60_000, intent(context))
    }

    fun scheduleSuite(context: Context, snapshot: com.rainif.doneat.core.domain.widget.WidgetSuiteSnapshot?, nowMs: Long) {
        // Use one earliest-boundary alarm, regardless of which widget composed last.
        if (snapshot != null && WidgetSignals.hasSuiteWidgets(context)) schedule(context, WidgetCoordinator.read(context)?.entry(nowMs), nowMs)
    }

    fun cancel(context: Context) = context.getSystemService(AlarmManager::class.java).cancel(intent(context))
}

/** Design geometry is shared with gallery previews; the actual digits remain a system Chronometer. */
@Composable
private fun Content(context: Context, upcoming: List<WidgetUpcomingItem>, entry: WidgetEntry?, nowMs: Long,
                    kind: DoneAtWidgetKind, segments: List<com.rainif.doneat.core.domain.widget.WidgetTimeSegment>, zoneID: String? = null) {
    val size = LocalSize.current
    val zone = remember(zoneID) { zoneID?.let(ZoneId::of) ?: ZoneId.systemDefault() }
    val visual = remember(context, kind, entry, upcoming, segments, nowMs, size, zone) {
        widgetCountdownVisual(context, kind, entry, upcoming, segments, nowMs, size, zone)
    }
    val open = Intent(LocalContext.current, MainActivity::class.java).putExtra(MainActivity.EXTRA_TAB, "timer")
    Box(GlanceModifier.fillMaxSize().appWidgetBackground().background(WidgetColors.background).cornerRadius(22.dp)
        .clickable(actionStartActivity(open))) {
        Image(ImageProvider(visual.bitmap), visual.description, GlanceModifier.fillMaxSize())
        val timer = visual.timer
        if (timer != null && entry != null && (entry.timerEndAtMs ?: 0) > nowMs) {
            // Row children follow reading direction; the shared drawing stores physical coordinates.
            val start = if (context.resources.configuration.layoutDirection == android.view.View.LAYOUT_DIRECTION_RTL)
                size.width.value - timer.left - timer.width else timer.left
            Column(GlanceModifier.fillMaxSize()) {
                Spacer(GlanceModifier.height(timer.top.coerceAtLeast(0f).dp))
                Row(GlanceModifier.fillMaxWidth()) {
                    Spacer(GlanceModifier.width(start.coerceAtLeast(0f).dp))
                    Box(GlanceModifier.width(timer.width.dp).height(timer.height.dp)) {
                        NativeCountdown(context, entry, nowMs, timer)
                    }
                }
            }
        }
    }
}

/** No polling: Android updates these digits while the widget process sleeps. */
@Composable
private fun NativeCountdown(context: Context, entry: WidgetEntry, nowMs: Long, placement: CountdownTimerPlacement) {
    val end = entry.timerEndAtMs?.takeIf { it > nowMs } ?: return
    val density = context.resources.displayMetrics.density
    val views = RemoteViews(context.packageName, R.layout.widget_countdown).apply {
        setTextViewTextSize(R.id.widget_countdown, TypedValue.COMPLEX_UNIT_SP, placement.fontSp)
        setTextColor(R.id.widget_countdown, placement.color)
        setViewPadding(R.id.widget_countdown, 0, 0, 0, 0)
        setInt(R.id.widget_countdown, "setGravity", placement.gravity)
        setInt(R.id.widget_countdown, "setWidth", (placement.width * density).roundToInt())
        setInt(R.id.widget_countdown, "setHeight", (placement.height * density).roundToInt())
        setChronometer(R.id.widget_countdown, SystemClock.elapsedRealtime() + (end - nowMs), null, true)
        setChronometerCountDown(R.id.widget_countdown, true)
    }
    AndroidRemoteViews(views, GlanceModifier.fillMaxSize())
}
