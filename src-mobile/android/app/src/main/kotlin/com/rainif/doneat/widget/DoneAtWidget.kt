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
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.LocaleList
import android.os.SystemClock
import android.text.format.DateFormat
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.collection.intSetOf
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap
import androidx.core.graphics.withClip
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
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.PreviewSizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.layout.wrapContentHeight
import androidx.glance.layout.wrapContentWidth
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
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
class DoneAtWidget(private val previewSize: DpSize = SMALL) : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM, LARGE))
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
            Content(localized, snapshot?.upcoming.orEmpty(), entry, now)
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
        provideContent { Content(context, upcoming, entry, now) }
    }

    private fun localized(context: Context, tag: String): Context {
        val configuration = Configuration(context.resources.configuration).apply { setLocales(LocaleList(Locale.forLanguageTag(tag))) }
        return context.createConfigurationContext(configuration)
    }
}

/** Bumped whenever the widget should look again: a new snapshot, or a refresh alarm. */
internal object WidgetSignals {
    val tick = MutableStateFlow(0L)

    private val receivers = listOf(
        DoneAtWidgetReceiver::class.java,
        DoneAtWidgetMediumReceiver::class.java,
        DoneAtWidgetLargeReceiver::class.java,
    )

    suspend fun redraw(context: Context) {
        tick.update { it + 1 }
        val manager = GlanceAppWidgetManager(context)
        val appWidgets = AppWidgetManager.getInstance(context)
        val widget = DoneAtWidget()
        receivers.flatMap { appWidgets.getAppWidgetIds(ComponentName(context, it)).asList() }
            .forEach { widget.update(context, manager.getGlanceIdBy(it)) }
    }

    fun hasWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return receivers.any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
    }

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
                WidgetSignals.redraw(context)
            } finally {
                pending.finish()
            }
        }
    }
}

internal object WidgetRefresh {
    private const val PROGRESS_STEP_MS = 15 * 60_000L

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
        entry ?: return manager.cancel(intent(context))
        val moving = entry.phase == WidgetPhase.WORKING || entry.phase == WidgetPhase.BEFORE
        val at = if (moving) minOf(entry.validUntilMs, nowMs + PROGRESS_STEP_MS) else entry.validUntilMs
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        if (exact) manager.setExact(AlarmManager.RTC, at, intent(context))
        else manager.setWindow(AlarmManager.RTC, at, 60_000, intent(context))
    }

    fun cancel(context: Context) = context.getSystemService(AlarmManager::class.java).cancel(intent(context))
}

private fun labelRes(key: String) = when (key) {
    "widgetRestDay" -> R.string.widgetRestDay
    "nextShiftLabelShort" -> R.string.nextShiftLabelShort
    "extendedBreak" -> R.string.extendedBreak
    "lunchInProgress" -> R.string.lunchInProgress
    "widgetWorking" -> R.string.widgetWorking
    "overtime" -> R.string.overtime
    "offWorkToday" -> R.string.offWorkToday
    else -> R.string.countdownNotStarted
}

private fun phaseColor(phase: WidgetPhase) = when (phase) {
    WidgetPhase.BEFORE -> WidgetColors.before
    WidgetPhase.WORKING -> WidgetColors.accent
    WidgetPhase.BREAK -> WidgetColors.breakTime
    WidgetPhase.DONE -> WidgetColors.done
    WidgetPhase.IDLE -> WidgetColors.secondary
}

private fun time(context: Context, atMs: Long, withDay: Boolean = false): String {
    val locale = context.resources.configuration.locales[0]
    val clock = if (DateFormat.is24HourFormat(context)) "Hm" else "hm"
    val pattern = DateFormat.getBestDateTimePattern(locale, if (withDay) "EEE$clock" else clock)
    return DateTimeFormatter.ofPattern(pattern, locale).format(Instant.ofEpochMilli(atMs).atZone(ZoneId.systemDefault()))
}

private fun isNight(context: Context) =
    (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

/** The bare mark (the themed-icon shapes in the accent), cropped to the icon's visible 72 of 108 units. */
private fun brandMark(context: Context, sizeDp: Dp): Bitmap {
    val px = (sizeDp.value * context.resources.displayMetrics.density).roundToInt()
    val bitmap = createBitmap(px, px)
    val canvas = Canvas(bitmap)
    val bleed = px * (108f / 72f - 1f) / 2
    ContextCompat.getDrawable(context, R.drawable.ic_launcher_monochrome)?.mutate()?.let {
        it.colorFilter = PorterDuffColorFilter(ContextCompat.getColor(context, R.color.widget_accent), PorterDuff.Mode.SRC_IN)
        it.setBounds(-bleed.toInt(), -bleed.toInt(), (px + bleed).toInt(), (px + bleed).toInt())
        canvas.withClip(0f, 0f, px.toFloat(), px.toFloat()) { it.draw(this) }
    }
    return bitmap
}

/** The medium widget's ring (iOS `progressRing`): a faint track and the accent gradient arc. */
private fun ring(context: Context, sizeDp: Dp, progress: Double): Bitmap {
    val density = context.resources.displayMetrics.density
    val px = (sizeDp.value * density).roundToInt()
    val stroke = 8 * density
    val bitmap = createBitmap(px, px)
    val canvas = Canvas(bitmap)
    val bounds = RectF(stroke / 2, stroke / 2, px - stroke / 2, px - stroke / 2)
    val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        color = if (isNight(context)) 0x26FFFFFF else 0x14000000
    }
    canvas.drawOval(bounds, track)
    val sweep = 360f * (progress / 100).coerceIn(0.0, 1.0).toFloat()
    if (sweep > 0) {
        val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            shader = LinearGradient(0f, 0f, px.toFloat(), 0f, 0xFFFF6114.toInt(), 0xFFFFAD29.toInt(), Shader.TileMode.CLAMP)
        }
        canvas.drawArc(bounds, -90f, sweep, false, arc)
    }
    return bitmap
}

@Composable
private fun Content(context: Context, upcoming: List<WidgetUpcomingItem>, entry: WidgetEntry?, nowMs: Long) {
    val size = LocalSize.current
    val open = Intent(LocalContext.current, MainActivity::class.java).putExtra(MainActivity.EXTRA_TAB, "timer")
    Box(
        GlanceModifier.fillMaxSize().appWidgetBackground().background(WidgetColors.background).cornerRadius(22.dp)
            .clickable(actionStartActivity(open)).padding(16.dp),
    ) {
        when {
            entry == null -> Empty(context, size)
            size.width >= LARGE.width && size.height >= LARGE.height -> Large(context, entry, upcoming.filter { it.dateMs > nowMs }, nowMs)
            size.width >= MEDIUM.width -> Medium(context, entry, nowMs)
            else -> Small(context, entry, nowMs)
        }
    }
}

@Composable
private fun Header(context: Context, compact: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        val mark = if (compact) 20.dp else 22.dp
        Image(ImageProvider(brandMark(context, mark)), null, GlanceModifier.size(mark))
        Spacer(GlanceModifier.width(8.dp))
        Text(context.getString(R.string.app_name), style = TextStyle(color = WidgetColors.primary, fontSize = 12.sp, fontWeight = FontWeight.Bold), maxLines = 1)
    }
}

@Composable
private fun Badge(context: Context, entry: WidgetEntry) {
    // The capsule is a Box of its own: a background on the Row itself spread to the Row around it.
    Box(GlanceModifier.wrapContentWidth().background(WidgetColors.accentSoft).cornerRadius(12.dp)) {
        Row(GlanceModifier.padding(horizontal = 9.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(GlanceModifier.size(6.dp).background(phaseColor(entry.phase)).cornerRadius(3.dp)) {}
            Spacer(GlanceModifier.width(6.dp))
            Text(context.getString(labelRes(entry.labelKey)), style = TextStyle(color = WidgetColors.primary, fontSize = 11.sp, fontWeight = FontWeight.Medium), maxLines = 1)
        }
    }
}

/** The ticking figure; a still "0:00:00" when there is nothing to count toward. */
@Composable
private fun Countdown(context: Context, entry: WidgetEntry, nowMs: Long, sizeSp: Float) {
    val end = entry.timerEndAtMs?.takeIf { it > nowMs }
    if (end == null) {
        Text("0:00:00", style = TextStyle(color = WidgetColors.primary, fontSize = sizeSp.sp, fontWeight = FontWeight.Bold), maxLines = 1)
        return
    }
    val views = RemoteViews(context.packageName, R.layout.widget_countdown).apply {
        setTextViewTextSize(R.id.widget_countdown, TypedValue.COMPLEX_UNIT_SP, sizeSp)
        setChronometer(R.id.widget_countdown, SystemClock.elapsedRealtime() + (end - nowMs), null, true)
        setChronometerCountDown(R.id.widget_countdown, true)
    }
    // Wrapped explicitly: a hosted view otherwise takes every spare pixel of its column.
    AndroidRemoteViews(
        views,
        GlanceModifier.wrapContentWidth().wrapContentHeight().semantics { contentDescription = context.getString(labelRes(entry.labelKey)) },
    )
}

@Composable
private fun Boundary(context: Context, entry: WidgetEntry) {
    val at = entry.nextBoundaryAtMs ?: return
    Text(time(context, at), style = TextStyle(color = WidgetColors.secondary, fontSize = 11.sp, fontWeight = FontWeight.Medium), maxLines = 1)
}

/** One container: a widget container holds at most ten children, so the bar and its caption travel together. */
@Composable
private fun Progress(context: Context, entry: WidgetEntry) = Column(GlanceModifier.fillMaxWidth()) {
    LinearProgressIndicator(
        progress = (entry.progressAtDate / 100).toFloat().coerceIn(0f, 1f),
        modifier = GlanceModifier.fillMaxWidth().height(7.dp).cornerRadius(4.dp),
        color = WidgetColors.accent,
        backgroundColor = WidgetColors.track,
    )
    Spacer(GlanceModifier.height(5.dp))
    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("${entry.progressAtDate.coerceIn(0.0, 100.0).roundToInt()}%", style = TextStyle(color = WidgetColors.accent, fontSize = 11.sp, fontWeight = FontWeight.Bold))
        Spacer(GlanceModifier.defaultWeight())
        Boundary(context, entry)
    }
}

@Composable
private fun Small(context: Context, entry: WidgetEntry, nowMs: Long) {
    Column(GlanceModifier.fillMaxSize()) {
        Header(context, compact = true)
        Spacer(GlanceModifier.defaultWeight())
        Badge(context, entry)
        Spacer(GlanceModifier.height(6.dp))
        Countdown(context, entry, nowMs, 24f)
        Spacer(GlanceModifier.defaultWeight())
        Progress(context, entry)
    }
}

@Composable
private fun Medium(context: Context, entry: WidgetEntry, nowMs: Long) {
    Column(GlanceModifier.fillMaxSize()) {
        Header(context, compact = false)
        Spacer(GlanceModifier.defaultWeight())
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(GlanceModifier.defaultWeight()) {
                Badge(context, entry)
                Spacer(GlanceModifier.height(7.dp))
                Countdown(context, entry, nowMs, 36f)
                Spacer(GlanceModifier.height(7.dp))
                Boundary(context, entry)
            }
            Spacer(GlanceModifier.width(18.dp))
            Box(GlanceModifier.size(76.dp), contentAlignment = Alignment.Center) {
                Image(ImageProvider(ring(context, 76.dp, entry.progressAtDate)), null, GlanceModifier.size(76.dp))
                Text("${entry.progressAtDate.coerceIn(0.0, 100.0).roundToInt()}%", style = TextStyle(color = WidgetColors.primary, fontSize = 15.sp, fontWeight = FontWeight.Bold))
            }
        }
        Spacer(GlanceModifier.defaultWeight())
    }
}

@Composable
private fun Large(context: Context, entry: WidgetEntry, upcoming: List<WidgetUpcomingItem>, nowMs: Long) {
    Column(GlanceModifier.fillMaxSize()) {
        Header(context, compact = false)
        Spacer(GlanceModifier.height(10.dp))
        Badge(context, entry)
        Spacer(GlanceModifier.height(6.dp))
        Countdown(context, entry, nowMs, 38f)
        Spacer(GlanceModifier.height(8.dp))
        Progress(context, entry)
        if (upcoming.isNotEmpty()) {
            Spacer(GlanceModifier.height(14.dp))
            Upcoming(context, upcoming, nowMs)
        }
    }
}

@Composable
private fun Upcoming(context: Context, upcoming: List<WidgetUpcomingItem>, nowMs: Long) {
    Column(GlanceModifier.fillMaxWidth()) {
        Text(context.getString(R.string.comingUp), style = TextStyle(color = WidgetColors.secondary, fontSize = 11.sp, fontWeight = FontWeight.Medium))
        Spacer(GlanceModifier.height(6.dp))
        val today = Instant.ofEpochMilli(nowMs).atZone(ZoneId.systemDefault()).toLocalDate()
        upcoming.take(4).forEach { item ->
            val otherDay = Instant.ofEpochMilli(item.dateMs).atZone(ZoneId.systemDefault()).toLocalDate() != today
            Row(GlanceModifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(GlanceModifier.size(6.dp).background(WidgetColors.accent).cornerRadius(3.dp)) {}
                Spacer(GlanceModifier.width(8.dp))
                Column(GlanceModifier.defaultWeight()) {
                    Text(item.title, style = TextStyle(color = WidgetColors.primary, fontSize = 12.sp, fontWeight = FontWeight.Medium), maxLines = 1)
                    if (item.detail.isNotEmpty()) {
                        Text(item.detail, style = TextStyle(color = WidgetColors.secondary, fontSize = 11.sp), maxLines = 1)
                    }
                }
                Text(time(context, item.dateMs, withDay = otherDay), style = TextStyle(color = WidgetColors.secondary, fontSize = 11.sp, fontWeight = FontWeight.Medium), maxLines = 1)
            }
        }
    }
}

/** No snapshot, or one past its expiry: say so and point at the app (iOS `emptyContent`). */
@Composable
private fun Empty(context: Context, size: DpSize) {
    Column(GlanceModifier.fillMaxSize()) {
        Header(context, compact = size.width < MEDIUM.width)
        Spacer(GlanceModifier.defaultWeight())
        Text(context.getString(R.string.countdownNotStarted), style = TextStyle(color = WidgetColors.primary, fontSize = 15.sp, fontWeight = FontWeight.Bold), maxLines = 2)
        Spacer(GlanceModifier.height(3.dp))
        Text(context.getString(R.string.widgetOpenToRefresh), style = TextStyle(color = WidgetColors.secondary, fontSize = 11.sp), maxLines = 2)
        Spacer(GlanceModifier.defaultWeight())
    }
}
