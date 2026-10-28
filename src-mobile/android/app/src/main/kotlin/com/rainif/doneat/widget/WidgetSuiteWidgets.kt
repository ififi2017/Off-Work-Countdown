package com.rainif.doneat.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.SystemClock
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.compose.ui.graphics.Color
import androidx.glance.unit.ColorProvider
import android.os.LocaleList
import androidx.compose.runtime.*
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.*
import androidx.glance.action.clickable
import androidx.glance.action.actionParametersOf
import androidx.glance.appwidget.action.actionRunCallback
import androidx.compose.ui.unit.sp
import androidx.glance.text.TextStyle
import androidx.glance.semantics.semantics
import androidx.glance.semantics.contentDescription
import androidx.glance.appwidget.*
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.layout.*
import com.rainif.doneat.MainActivity
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.widget.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

/** Each picker entry keeps its own stable receiver; the original countdown IDs remain intact. */
enum class DoneAtWidgetKind(val titleRes: Int, val plus: Boolean = false) {
    CLASSIC(R.string.widgetGalleryClassicName), BIG(R.string.widgetStyleBigName),
    RING(R.string.widgetStyleRingName), TIMELINE(R.string.widgetStyleTimelineName), DETAIL(R.string.widgetStyleDetailName),
    WEEK(R.string.widgetSuiteWeekName), ROSTER(R.string.widgetSuiteRosterName), YEAR(R.string.widgetSuiteYearName),
    WEEKEND(R.string.widgetSuiteWeekendName), HOLIDAY(R.string.widgetSuiteHolidayName),
    SUMMARY(R.string.widgetSuiteSummaryName, true), LIFE(R.string.widgetSuiteLifeName, true), FOCUS(R.string.widgetSuiteFocusName, true);

    val countdown get() = ordinal <= DETAIL.ordinal
    val defaultSize get() = when (this) {
        WEEK -> DpSize(364.dp, 170.dp)
        DETAIL, ROSTER -> DpSize(220.dp, 250.dp)
        SUMMARY, LIFE, FOCUS -> DpSize(220.dp, 150.dp)
        else -> DpSize(150.dp, 150.dp)
    }
    val tab get() = when (this) {
        FOCUS -> "focus"
        WEEK, ROSTER, YEAR, SUMMARY, LIFE, HOLIDAY, WEEKEND -> "records"
        else -> "timer"
    }
    val receiver: Class<out GlanceAppWidgetReceiver> get() = when (this) {
        CLASSIC -> DoneAtWidgetReceiver::class.java
        BIG -> DoneAtWidgetBigReceiver::class.java
        RING -> DoneAtWidgetRingReceiver::class.java
        TIMELINE -> DoneAtWidgetTimelineReceiver::class.java
        DETAIL -> DoneAtWidgetDetailReceiver::class.java
        WEEK -> DoneAtWeekWidgetReceiver::class.java
        ROSTER -> DoneAtRosterWidgetReceiver::class.java
        YEAR -> DoneAtYearWidgetReceiver::class.java
        WEEKEND -> DoneAtWeekendWidgetReceiver::class.java
        HOLIDAY -> DoneAtHolidayWidgetReceiver::class.java
        SUMMARY -> DoneAtSummaryWidgetReceiver::class.java
        LIFE -> DoneAtLifeWidgetReceiver::class.java
        FOCUS -> DoneAtFocusWidgetReceiver::class.java
    }
    fun widget(): GlanceAppWidget = if (countdown) DoneAtWidget(defaultSize, this) else DoneAtSuiteWidget(this)
    fun pin(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return manager.isRequestPinAppWidgetSupported && manager.requestPinAppWidget(ComponentName(context, receiver), null, null)
    }
}

class DoneAtSuiteWidget(private val kind: DoneAtWidgetKind) : GlanceAppWidget() {
    override val sizeMode = SizeMode.Exact
    override val previewSizeMode: PreviewSizeMode = SizeMode.Responsive(setOf(kind.defaultSize))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val first = withContext(Dispatchers.IO) { WidgetSuiteCoordinator.read(context) }
        provideContent {
            val tick by WidgetSignals.tick.collectAsState()
            val snapshot by produceState(first, tick) { value = withContext(Dispatchers.IO) { WidgetSuiteCoordinator.read(context) } }
            val now = remember(tick, snapshot) { System.currentTimeMillis() }
            val safe = snapshot?.redacted(now)
            val localized = remember(safe?.locale) { widgetLocalizedContext(context, safe?.locale) }
            val card = remember(kind, safe, now, localized) { widgetSuiteCard(localized, kind, safe, now) }
            LaunchedEffect(tick, snapshot) { WidgetRefresh.scheduleSuite(context, snapshot, now) }
            val size = LocalSize.current
            val current = safe?.focus?.current(now)
            val focusRunning = kind == DoneAtWidgetKind.FOCUS && current != null
            val controls = focusRunning && current?.isBreak == false && size.width >= 220.dp
            val paintCard = if (focusRunning) card.copy(nativeFocusTimer = true) else card
            val bitmap = remember(paintCard, size, localized) { widgetCardBitmap(localized, paintCard, size) }
            Box(GlanceModifier.fillMaxSize().appWidgetBackground().background(ImageProvider(R.drawable.widget_preview_background)).cornerRadius(22.dp)
                .clickable(actionStartActivity(Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_TAB, if (card.locked) "plus" else kind.tab)))) {
                Image(ImageProvider(bitmap), card.description, GlanceModifier.fillMaxSize())
                if (focusRunning && current != null) {
                    val timerWidth = WidgetFocusLayout.timerWidth(size.width.value, size.width < 220.dp || current.isBreak)
                    val views = RemoteViews(localized.packageName, R.layout.widget_countdown).apply {
                        setTextViewTextSize(R.id.widget_countdown, TypedValue.COMPLEX_UNIT_SP,
                            widgetFocusTimerFont(localized, widgetFocusClockText(localized, current.endMs - now), timerWidth, size.width < 220.dp))
                        setChronometer(R.id.widget_countdown, SystemClock.elapsedRealtime() + (current.endMs - now).coerceAtLeast(0), null, true)
                        setChronometerCountDown(R.id.widget_countdown, true)
                    }
                    Box(GlanceModifier.fillMaxSize().padding(start = WidgetFocusLayout.INSET.dp, top = WidgetFocusLayout.TIMER_TOP.dp)) {
                        AndroidRemoteViews(views, GlanceModifier.width(timerWidth.dp).height(44.dp))
                    }
                }
                if (controls && current != null) {
                    Column(GlanceModifier.fillMaxSize().padding(start = WidgetFocusLayout.buttonStart(size.width.value).dp, top = WidgetFocusLayout.BUTTON_TOP.dp, end = 16.dp)) {
                        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            val colors = ButtonDefaults.buttonColors(backgroundColor = ColorProvider(Color.Transparent),
                                contentColor = ColorProvider(Color(androidx.core.content.ContextCompat.getColor(localized, R.color.widget_primary))))
                            Button("+", actionRunCallback<WidgetFocusActionCallback>(
                                actionParametersOf(WidgetFocusActionCallback.ACTION to "add", WidgetFocusActionCallback.START to current.startMs)),
                                GlanceModifier.size(44.dp).cornerRadius(22.dp).semantics { contentDescription = localized.getString(R.string.widgetSuiteFocusAdd) },
                                style = TextStyle(fontSize = 20.sp), colors = colors, maxLines = 1)
                            Spacer(GlanceModifier.width(8.dp))
                            Button("■", actionRunCallback<WidgetFocusActionCallback>(
                                actionParametersOf(WidgetFocusActionCallback.ACTION to "stop", WidgetFocusActionCallback.START to current.startMs)),
                                GlanceModifier.size(44.dp).cornerRadius(22.dp).semantics { contentDescription = localized.getString(R.string.widgetSuiteFocusStop) },
                                style = TextStyle(fontSize = 18.sp), colors = colors, maxLines = 1)
                        }
                    }
                }
            }
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val card = widgetSuiteCard(context, kind, null, System.currentTimeMillis())
        provideContent {
            Image(ImageProvider(widgetCardBitmap(context, card, LocalSize.current)), card.description, GlanceModifier.fillMaxSize())
        }
    }
}

internal fun widgetLocalizedContext(context: Context, locale: String?): Context {
    locale ?: return context
    return context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocales(LocaleList(Locale.forLanguageTag(locale))) })
}

abstract class DoneAtSuiteReceiver(private val kind: DoneAtWidgetKind) : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = kind.widget()
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        if (!WidgetSignals.hasWidgets(context)) WidgetRefresh.cancel(context)
    }
}
class DoneAtWidgetBigReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.BIG)
class DoneAtWidgetRingReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.RING)
class DoneAtWidgetTimelineReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.TIMELINE)
class DoneAtWidgetDetailReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.DETAIL)
class DoneAtWeekWidgetReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.WEEK)
class DoneAtRosterWidgetReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.ROSTER)
class DoneAtYearWidgetReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.YEAR)
class DoneAtWeekendWidgetReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.WEEKEND)
class DoneAtHolidayWidgetReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.HOLIDAY)
class DoneAtSummaryWidgetReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.SUMMARY)
class DoneAtLifeWidgetReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.LIFE)
class DoneAtFocusWidgetReceiver : DoneAtSuiteReceiver(DoneAtWidgetKind.FOCUS)
