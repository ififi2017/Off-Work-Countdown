package com.rainif.doneat.widget

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.text.format.DateFormat
import android.view.View
import androidx.compose.ui.unit.DpSize
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.widget.*
import com.rainif.doneat.ui.timer.TimerText
import java.text.NumberFormat
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.ceil
import kotlin.math.min
import kotlin.math.roundToInt

/** Shared coordinates for the bitmap's reserved Focus text and real Glance controls. */
internal object WidgetFocusLayout {
    const val INSET = 16f
    const val TITLE_TOP = 40f
    const val TIMER_TOP = 59f
    const val BUTTON_TOP = 48f
    const val BUTTON_SIZE = 44f
    const val BUTTON_GAP = 8f
    fun timerWidth(width: Float, small: Boolean) = (width - INSET * 2 - if (small) 0f else 108f).coerceAtLeast(44f)
    fun buttonStart(width: Float) = width - INSET - BUTTON_SIZE * 2 - BUTTON_GAP
    fun expanded(width: Float, height: Float) = width >= 220f && height >= 220f
    fun titleTop(width: Float, height: Float) = if (expanded(width, height)) 48f else TITLE_TOP
    fun timerTop(width: Float, height: Float) = if (expanded(width, height)) 76f else TIMER_TOP
    fun buttonTop(width: Float, height: Float) = if (expanded(width, height)) 91f else BUTTON_TOP
    fun timerHeight(width: Float, height: Float) = if (expanded(width, height)) 80f else 44f
    fun panelHeight(width: Float, height: Float, queuedCount: Int, running: Boolean): Float = when {
        height < 220f -> height
        width < 220f -> min(height, 210f)
        running -> min(height, 250f + 32f * queuedCount.coerceIn(0, 4))
        else -> min(height, 250f)
    }
    fun offset(width: Float, height: Float, queuedCount: Int, running: Boolean) =
        (height - panelHeight(width, height, queuedCount, running)) / 2
}

/** A sampled gallery value; installed widgets use the system Chronometer in this exact slot. */
internal fun widgetFocusClockText(context: Context, remainingMs: Long): String {
    val formatter = NumberFormat.getIntegerInstance(context.resources.configuration.locales[0]).apply { isGroupingUsed = false }
    val seconds = remainingMs.coerceAtLeast(0) / 1000
    val zero = formatter.format(0).first()
    fun two(value: Long) = formatter.format(value).padStart(2, zero)
    return if (seconds >= 3600) formatter.format(seconds / 3600) + ":" + two(seconds / 60 % 60) + ":" + two(seconds % 60)
        else formatter.format(seconds / 60) + ":" + two(seconds % 60)
}

internal fun widgetFocusTimerFont(context: Context, clock: String, width: Float, small: Boolean, expanded: Boolean = false): Float {
    val requested = if (expanded) 56f else if (small) 30f else 34f
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = requested * context.resources.configuration.fontScale
        typeface = Typeface.DEFAULT_BOLD
        fontFeatureSettings = "tnum"
    }
    // At 200% text size the old 0.6 floor could still exceed a small
    // widget's slot. Fit the complete clock, with a rounding inset, and
    // share this exact SP value with the installed system Chronometer.
    val widthFit = (width - 2f).coerceAtLeast(1f) / paint.measureText(clock).coerceAtLeast(1f)
    val lineHeight = paint.fontMetrics.descent - paint.fontMetrics.ascent
    val heightFit = (if (expanded) 76f else 40f) / lineHeight.coerceAtLeast(1f)
    return requested * min(widthFit, heightFit).coerceAtMost(1f)
}

/** HTML boards 1/2/4/6/7: each widget has its own family layout, never a generic metrics card. */
internal class WidgetSuitePainter(private val context: Context, private val card: WidgetCard, size: DpSize) {
    private val state = requireNotNull(card.suite)
    private val snapshot = state.snapshot?.redacted(state.nowMs)
    private val now = state.nowMs
    private val res = context.resources
    private val locale = res.configuration.locales[0]
    private val density = res.displayMetrics.density
    private val fontScale = res.configuration.fontScale
    private val rtl = res.configuration.layoutDirection == View.LAYOUT_DIRECTION_RTL
    private val w = size.width.value.coerceAtLeast(1f)
    private var h = size.height.value.coerceAtLeast(1f)
    private val hostHeight = h
    private val small = w < 220f
    private val large = !small && h >= 220f
    private val tall = h >= 220f
    private val inset = 16f
    private val cw = (w - inset * 2).coerceAtLeast(1f)
    private val image = createBitmap((w * density).roundToInt().coerceAtLeast(1), (h * density).roundToInt().coerceAtLeast(1))
    private val canvas = Canvas(image).apply { scale(this@WidgetSuitePainter.density, this@WidgetSuitePainter.density) }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val night = res.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    private val bg = ContextCompat.getColor(context, R.color.widget_background)
    private val ink = ContextCompat.getColor(context, R.color.widget_primary)
    private val muted = ContextCompat.getColor(context, R.color.widget_secondary)
    private val accent = ContextCompat.getColor(context, R.color.widget_accent)
    private val track = blend(ink, .10f)
    private val rest = blend(ink, .045f)
    private val softOrange = blend(accent, if (night) .38f else .30f)
    private val accentText = if (night) Color.rgb(255, 158, 97) else Color.rgb(194, 64, 13)
    private val holiday = if (night) Color.rgb(48, 209, 88) else Color.rgb(52, 199, 89)
    private val blue = if (night) Color.rgb(100, 210, 255) else Color.rgb(50, 173, 230)
    private val formatter = TimerText(res, locale, DateFormat.is24HourFormat(context), hideEarnings = true)
    private val zone = ZoneId.of(snapshot?.timeZoneIdentifier ?: ZoneId.systemDefault().id)
    private val lifeZone = ZoneId.of(snapshot?.lifeTimeZoneIdentifier ?: ZoneId.systemDefault().id)
    private val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()

    private fun t(id: Int, vararg args: Any) = res.getString(id, *args)
    private fun count(value: Int) = formatter.count(value)
    private fun yearNumber(value: Int) = NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = false }.format(value)
    private fun hoursUnit() = hours(0).filterNot { it.isDigit() }.trim()
    private fun decimal(value: Double, digits: Int = 1) = NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = digits }.format(value)
    private fun percent(value: Double) = NumberFormat.getPercentInstance(locale).format(value.coerceIn(0.0, 1.0))
    private fun hours(value: Long) = formatter.hours(value / 3_600_000.0)
    private fun date(ms: Long, skeleton: String = "MMMd", tz: ZoneId = zone) = Instant.ofEpochMilli(ms).atZone(tz)
        .format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, skeleton), locale))
    private fun time(ms: Long) = date(ms, if (DateFormat.is24HourFormat(context)) "Hm" else "hm")
    private fun weekday(ms: Long) = date(ms, "EEEEE")
    private fun x(start: Float, width: Float) = if (rtl) w - start - width else start
    private fun blend(color: Int, alpha: Float): Int {
        val a = alpha.coerceIn(0f, 1f)
        fun c(fg: Int, back: Int) = (fg * a + back * (1 - a)).roundToInt()
        return Color.rgb(c(Color.red(color), Color.red(bg)), c(Color.green(color), Color.green(bg)), c(Color.blue(color), Color.blue(bg)))
    }
    private fun box(start: Float, top: Float, width: Float, height: Float, color: Int, radius: Float = 0f) {
        if (width <= 0 || height <= 0) return
        paint.color = color; paint.style = Paint.Style.FILL
        val left = x(start, width)
        canvas.drawRoundRect(left, top, left + width, top + height, radius, radius, paint)
    }
    /** Keep a complete content group together when the launcher supplies excess height. */
    private fun centeredPanel(height: Float, draw: () -> Unit) {
        val previous = h
        val panel = height.coerceIn(1f, previous)
        canvas.save()
        canvas.translate(0f, (previous - panel) / 2)
        h = panel
        try { draw() } finally { h = previous; canvas.restore() }
    }
    private fun rule(y: Float) = box(inset, y, cw, .6f, track)
    private fun text(value: String, start: Float, top: Float, width: Float, size: Float, bold: Boolean = false,
                     color: Int = ink, lines: Int = 1, center: Boolean = false, fit: Boolean = true): Float {
        if (value.isBlank() || width <= 0f || top >= h) return 0f
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color; textSize = size * fontScale
            typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
            fontFeatureSettings = "tnum"
        }
        if (fit && lines == 1) {
            tp.textSize *= (width / tp.measureText(value).coerceAtLeast(1f)).coerceIn(.7f, 1f)
        }
        fun layout() = StaticLayout.Builder.obtain(value, 0, value.length, tp, width.roundToInt().coerceAtLeast(1))
            .setAlignment(if (center) Layout.Alignment.ALIGN_CENTER else Layout.Alignment.ALIGN_NORMAL)
            .setTextDirection(if (rtl) TextDirectionHeuristics.RTL else TextDirectionHeuristics.LTR)
            .setIncludePad(false).setMaxLines(lines).setEllipsize(if (fit) TextUtils.TruncateAt.END else null).build()
        var rendered = layout()
        if (fit) {
            // Fixed widget families cannot grow with fontScale. Keep each
            // allocated line slot readable instead of painting into the next row.
            val budget = min(h - top - inset, size * 1.45f * lines).coerceAtLeast(1f)
            if (rendered.height > budget) {
                tp.textSize *= budget / rendered.height
                rendered = layout()
            }
        }
        canvas.save(); canvas.translate(x(start, width), top); rendered.draw(canvas); canvas.restore()
        return rendered.height.toFloat()
    }

    /** Key figures use measured value + small suffix on one baseline; never ellipsize a figure. */
    private fun numberSuffix(value: String, suffix: String, start: Float, top: Float, width: Float,
                             valueSize: Float, suffixSize: Float = 11f, color: Int = ink) {
        fun style(size: Float, bold: Boolean, tint: Int) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size * fontScale
            typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
            this.color = tint; fontFeatureSettings = "tnum"
            val line = fontMetrics.descent - fontMetrics.ascent
            if (line > size * 1.35f) textSize *= size * 1.35f / line
        }
        val main = style(valueSize, true, color)
        val secondary = style(suffixSize, false, muted)
        val gap = if (suffix.isEmpty()) 0f else 3f
        val totalWidth = main.measureText(value) + secondary.measureText(suffix) + gap
        val fit = (width / totalWidth.coerceAtLeast(1f)).coerceAtMost(1f)
        main.textSize *= fit
        secondary.textSize *= fit
        val suffixBudget = secondary.measureText(suffix)
        val mainWidth = main.measureText(value)
        val baseline = top - main.fontMetrics.ascent
        fun draw(string: String, logicalStart: Float, paint: TextPaint, allocated: Float) {
            if (string.isEmpty()) return
            val layout = StaticLayout.Builder.obtain(string, 0, string.length, paint, (allocated + 1).roundToInt().coerceAtLeast(1))
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setTextDirection(if (rtl) TextDirectionHeuristics.RTL else TextDirectionHeuristics.LTR)
                .setIncludePad(false).setMaxLines(1).build()
            canvas.save(); canvas.translate(x(logicalStart, allocated), baseline + paint.fontMetrics.ascent); layout.draw(canvas); canvas.restore()
        }
        draw(value, start, main, mainWidth)
        draw(suffix, start + mainWidth + gap, secondary, suffixBudget)
    }
    private fun header(title: String, trailing: String? = null, tint: Int = ink) {
        val trailingWidth = if (trailing.isNullOrBlank()) 0f else min(cw * .5f, if (small) 78f else 160f)
        text(title, inset, inset, cw - trailingWidth - if (trailingWidth > 0) 5 else 0, 13f, true, tint)
        if (trailingWidth > 0) text(trailing.orEmpty(), w - inset - trailingWidth, inset + 1, trailingWidth, 11f, color = muted)
    }
    private fun bar(start: Float, y: Float, width: Float, height: Float, progress: Double, color: Int = accent) {
        box(start, y, width, height, track, height / 2)
        box(start, y, width * progress.coerceIn(0.0, 1.0).toFloat(), height, color, height / 2)
    }
    private fun segmentBar(y: Float, values: List<Double>, height: Float = 6f, start: Float = inset, width: Float = cw) {
        if (values.isEmpty()) return
        val gap = 3f
        val cell = (width - (values.size - 1) * gap) / values.size
        values.forEachIndexed { i, progress -> bar(start + i * (cell + gap), y, cell, height, progress) }
    }
    private fun badge(label: String, start: Float, y: Float, color: Int, maxWidth: Float = cw, font: Float = 20f): Float {
        val tp = TextPaint().apply { textSize = font * fontScale; typeface = Typeface.DEFAULT_BOLD }
        val width = min(maxWidth, tp.measureText(label) + 20)
        val height = font * fontScale * 1.2f + 8
        box(start, y, width, height, blend(color, .18f), 8f)
        text(label, start + 10, y + 4, width - 20, font, true, if (color == accent) accentText else ink)
        return height
    }
    private fun valueUnit(value: String, unit: String, top: Float, numberSize: Float, unitSize: Float = 14f) {
        numberSuffix(value, unit, inset, top, cw, numberSize, unitSize)
    }
    private fun monthTitle(date: LocalDate = today) = date.format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "yMMM"), locale))
    private fun dayTitle(day: WidgetCalendarDay): String = day.title?.takeIf { it.isNotBlank() } ?: t(when (day.kind) {
        WidgetCalendarDayKind.MAKEUP_WORK -> R.string.widgetSuiteMakeupWork
        WidgetCalendarDayKind.LEAVE -> R.string.widgetSuiteLeave
        WidgetCalendarDayKind.WORK -> R.string.widgetSuiteWork
        else -> R.string.widgetSuiteRest
    })
    private fun dayColor(day: WidgetCalendarDay): Int = when (day.kind) {
        WidgetCalendarDayKind.WORK, WidgetCalendarDayKind.MAKEUP_WORK -> day.colorHex?.let { runCatching { Color.parseColor(it) }.getOrNull() } ?: accent
        WidgetCalendarDayKind.HOLIDAY -> holiday
        WidgetCalendarDayKind.LEAVE -> accent
        else -> muted
    }

    fun render(): Bitmap {
        box(0f, 0f, w, h, bg, 22f)
        if (card.locked) { locked(); return image }
        if (state.kind == DoneAtWidgetKind.YEAR) { year(); return image }
        if (snapshot == null) { empty(); return image }
        when (state.kind) {
            DoneAtWidgetKind.WEEK -> centeredPanel(if (large) min(h, 292f) else if (tall) min(h, 210f) else h) { week(snapshot.calendar) }
            DoneAtWidgetKind.ROSTER -> roster(snapshot.calendar)
            DoneAtWidgetKind.YEAR -> year()
            DoneAtWidgetKind.WEEKEND -> centeredPanel(if (large) min(h, 286f) else if (tall) min(h, 210f) else h) { weekend(snapshot) }
            DoneAtWidgetKind.HOLIDAY -> centeredPanel(if (large) min(h, 286f) else if (tall) min(h, 210f) else h) { holiday(snapshot.holiday) }
            DoneAtWidgetKind.SUMMARY -> summary(snapshot.summary)
            DoneAtWidgetKind.LIFE -> life(snapshot.life)
            DoneAtWidgetKind.FOCUS -> {
                val queueCount = snapshot.focus.blocks.count { it.startMs > now }.coerceAtMost(4)
                centeredPanel(WidgetFocusLayout.panelHeight(w, h, queueCount, snapshot.focus.current(now) != null)) { focus(snapshot.focus) }
            }
            else -> empty()
        }
        return image
    }

    private fun empty(message: String = card.headline, action: String = card.caption) {
        centeredPanel(if (large) min(h, 246f) else if (tall) min(h, 210f) else h) {
            header(card.title)
            text(message, inset, if (large) 56f else 43f, cw, if (large) 22f else 15f, true, lines = 3)
            text(action, inset, h - inset - if (large) 34 else 28, cw, if (large) 14f else 12f, true, accentText, lines = 2)
        }
    }
    private fun locked() {
        centeredPanel(if (large) min(h, 286f) else if (tall) min(h, 210f) else h) {
            val spacious = large && h >= 270f
            header(card.title)
            box(w - inset - 32, inset - 1, 32f, 16f, blend(accent, .14f), 5f)
            text("Plus", w - inset - 29, inset + 1, 26f, 10f, true, accentText, center = true)
            text(card.caption, inset, if (spacious) 58f else 43f, cw, if (spacious) 22f else if (small) 15f else 17f, true, lines = if (spacious) 3 else 2)
            val chartHeight = if (spacious) 44f else 20f
            val y = h - inset - if (spacious) 100 else 42
            if (state.kind == DoneAtWidgetKind.SUMMARY) {
                val ratios = listOf(.6f, .85f, .7f, .45f, .2f)
                val cell = (cw - 8 * 4) / 5
                ratios.forEachIndexed { i, value -> box(inset + i * (cell + 8), y + chartHeight * (1 - value), cell, chartHeight * value, track, 4f) }
            } else segmentBar(y + chartHeight / 2, List(4) { 0.0 }, if (spacious) 10f else 6f)
            text(t(R.string.widgetSuiteLearnPlus), inset, h - inset - if (spacious) 30 else 14, cw, if (spacious) 14f else 12f, true, accentText)
        }
    }

    private fun week(payload: WidgetCalendarPayload) {
        if (payload.scheduleKind == WidgetCalendarScheduleKind.NONE || payload.days.isEmpty()) { empty(t(R.string.widgetSuiteNoScheduleMessage), t(R.string.widgetSuiteOpenSettings)); return }
        if (payload.scheduleKind == WidgetCalendarScheduleKind.ROTATION) { rotation(payload); return }
        val week = WidgetWeekProgress.from(payload, now)
        val alternating = if (payload.scheduleKind == WidgetCalendarScheduleKind.ALTERNATING_WEEKS) payload.labels[if (week.isBigWeek) "bigWeek" else "smallWeek"] else null
        header(listOfNotNull(t(R.string.widgetSuiteThisWeek), alternating).joinToString(" · "), if (small) null else date(now, "MMMdEEE"))
        val finish = week.finishMs?.takeIf { it > now }?.let { t(R.string.widgetSuiteFinishAt, date(it, "EEE") + " " + time(it)) }
        if (small) {
            text(t(R.string.widgetSuiteWorkdaysLeft), inset, 41f, cw, 11f, true, muted)
            valueUnit(decimal(week.remainingDays), t(R.string.widgetSuiteDaysUnit), 56f, 28f)
            text(finish.orEmpty(), inset, 91f, cw, 11f, color = muted)
            segmentBar(h - inset - 6, week.days.filter { it.isWork }.map { week.fill(it, now) })
        } else {
            val headline = t(R.string.widgetSuiteDaysLeft, decimal(week.remainingDays))
            val headlineWidth = TextPaint().apply { textSize = 26f * fontScale; typeface = Typeface.DEFAULT_BOLD }.measureText(headline).coerceAtMost(cw)
            text(headline, inset, 42f, headlineWidth + 1, 26f, true)
            val remainingWidth = cw - headlineWidth - 8
            if (remainingWidth > 65) text(finish.orEmpty(), inset + headlineWidth + 8, 55f, remainingWidth, 11f, color = muted)
            val gap = 6f
            val cell = (cw - gap * 6) / 7
            val chartHeight = if (large) min((h - 126 - inset - 22).coerceAtLeast(24f), cell * 3f) else if (h >= 164) 30f else 24f
            val columnsY = if (large) h - inset - chartHeight - 22 else h - inset - chartHeight - 18
            week.days.take(7).forEachIndexed { i, day ->
                val start = inset + i * (cell + gap)
                box(start, columnsY, cell, chartHeight, if (day.isWork) track else rest, 6f)
                val fill = week.fill(day, now).coerceIn(0.0, 1.0).toFloat()
                if (fill > 0) box(start, columnsY + chartHeight * (1 - fill), cell, chartHeight * fill, accent, min(6f, chartHeight * fill / 2))
                if (day.kind == WidgetCalendarDayKind.HOLIDAY || day.kind == WidgetCalendarDayKind.LEAVE) box(start + cell / 2 - 2, columnsY + chartHeight / 2 - 2, 4f, 4f, if (day.kind == WidgetCalendarDayKind.HOLIDAY) holiday else accent, 2f)
                text(weekday(day.startMs), start, columnsY + chartHeight + 5, cell, 11f, day.dayKey == today.toString(), if (day.dayKey == today.toString()) ink else muted, center = true)
            }
        }
    }

    private fun rotation(payload: WidgetCalendarPayload) {
        val outlook = WidgetRotationOutlook.from(payload, now)
        val note = outlook.today?.let { day ->
            val cycleDay = day.cycleDay
            val length = day.cycleLength
            if (cycleDay != null && length != null) t(R.string.widgetSuiteCycleDay, count(cycleDay), count(length)) else null
        }
        header(note ?: t(R.string.widgetSuiteThisWeek))
        val headline = if (outlook.workdaysBeforeRest > 0) t(R.string.widgetSuiteRestAfter, count(outlook.workdaysBeforeRest)) else t(R.string.widgetSuiteRestingToday)
        text(headline, inset, 44f, cw, if (large) 30f else if (small) 22f else 24f, true, lines = 2)
        text(outlook.nextRest?.let { t(R.string.widgetSuiteRestOn, date(it.startMs, "EEE")) }.orEmpty(), inset, 88f, cw, 11f, color = muted)
        val list = outlook.days.take(if (small) 7 else 14)
        val gap = if (small) 2f else 3f
        val cell = (cw - gap * (list.size - 1)) / list.size.coerceAtLeast(1)
        val y = h - inset - if (large) 72 else if (small) 17 else 37
        list.forEachIndexed { i, day ->
            val start = inset + i * (cell + gap)
            box(start, y, cell, if (large) 48f else if (small) 14f else 22f, if (day.isWork) blend(accent, .16f) else rest, 4f)
            text(if (day.isWork) t(R.string.widgetSuiteWork) else t(R.string.widgetSuiteRest), start + 1, y + 2, cell - 2, if (small) 8f else 10f, true, if (day.isWork) accentText else muted, center = true)
            if (!small) text(weekday(day.startMs), start, y + (if (large) 53 else 27), cell, 9f, color = muted, center = true)
        }
    }

    private fun roster(payload: WidgetCalendarPayload) {
        if (payload.scheduleKind == WidgetCalendarScheduleKind.NONE || payload.days.isEmpty()) { empty(t(R.string.widgetSuiteNoScheduleMessage), t(R.string.widgetSuiteOpenSettings)); return }
        val todayIndex = payload.days.indexOfFirst { it.dayKey == today.toString() }
        val current = payload.days.getOrNull(todayIndex)
        val focusIndex = if (current?.isWork == true && (current.endAtMs ?: 0) > now) todayIndex else todayIndex + 1
        val day = payload.days.getOrNull(focusIndex)
        if (small) {
            if (day == null) { empty(t(R.string.widgetSuiteOpenToRefresh)); return }
            val heading = t(if (focusIndex == todayIndex) R.string.widgetSuiteToday else R.string.widgetSuiteTomorrow) + " · " + date(day.startMs, "EEE")
            header(heading)
            val chipHeight = badge(dayTitle(day), inset, 44f, dayColor(day))
            val range = if (day.startAtMs != null && day.endAtMs != null) time(day.startAtMs!!) + " – " + time(day.endAtMs!!) else null
            numberSuffix(range.orEmpty(), "", inset, 44 + chipHeight + 8, cw, 18f)
            val following = payload.days.drop(focusIndex + 1).take(7)
            val restStart = following.indexOfFirst { !it.isWork }
            val restRun = if (restStart >= 0) following.drop(restStart).takeWhile { !it.isWork }.take(4) else emptyList()
            val restNote = restRun.takeIf { it.isNotEmpty() }?.joinToString(" · ") { date(it.startMs, "EEE") }?.let { t(R.string.widgetSuiteRestOn, it) }
            text(restNote.orEmpty(), inset, h - inset - 28, cw, 11f, color = muted, lines = 2)
            return
        }
        val month = payload.days.filter { it.dayKey.startsWith(today.toString().take(7)) }
        header(monthTitle(), if (large) t(R.string.widgetSuiteWorkdayCount, count(month.count { it.isWork })) else null)
        val first = month.firstOrNull()?.let { LocalDate.parse(it.dayKey) } ?: return
        val leading = (first.dayOfWeek.value - payload.firstDayOfWeek + 7) % 7
        val rows = ceil((leading + month.size) / 7.0).toInt()
        val gap = if (large) 4f else 3f
        val cell = (cw - gap * 6) / 7
        val top = 43f
        if (large) for (col in 0..6) {
            val weekday = DayOfWeek.of((payload.firstDayOfWeek - 1 + col) % 7 + 1).getDisplayName(java.time.format.TextStyle.NARROW, locale)
            text(weekday, inset + col * (cell + gap), top, cell, 10f, color = muted, center = true)
        }
        val gridTop = top + if (large) 18 else 0
        val cellHeight = ((h - inset - gridTop - gap * (rows - 1)) / rows.coerceAtLeast(1)).coerceAtMost(if (large) 52f else 24f)
        month.forEachIndexed { i, item ->
            val index = leading + i
            val start = inset + (index % 7) * (cell + gap)
            val y = gridTop + (index / 7) * (cellHeight + gap)
            val isToday = item.dayKey == today.toString()
            val color = dayColor(item)
            val fill = if (isToday && !large) ink else if (large) { if (isToday) blend(accent, .08f) else bg } else if (item.isWork) blend(color, .12f) else rest
            box(start, y, cell, cellHeight, fill, if (large) 8f else 5f)
            text(count(LocalDate.parse(item.dayKey).dayOfMonth), start, y + if (large) 3f else (cellHeight - 12) / 2, cell, if (large) 12f else 10f, isToday, if (isToday && !large) bg else if (item.isWork && !large) accentText else ink, center = true)
            if (large && cellHeight > 30) {
                box(start + 2, y + 21, cell - 4, min(18f, cellHeight - 23), blend(color, if (item.isWork) .18f else .07f), 5f)
                text(dayTitle(item), start + 4, y + 23, cell - 8, 10f, true, if (item.isWork && item.colorHex == null) accentText else ink, center = true)
            }
        }
    }

    private fun calendarRows() {
        val progress = WidgetCalendarProgress.at(now, lifeZone, DayOfWeek.of(snapshot?.calendar?.firstDayOfWeek ?: 1))
        header(t(R.string.widgetSuiteProgress), if (small) null else date(now, "MMMdEEE", lifeZone))
        val rows = listOf(t(R.string.widgetSuiteToday) to progress.today, t(R.string.widgetSuiteThisWeek) to progress.week,
            t(R.string.widgetSuiteThisMonth) to progress.month, t(R.string.widgetSuiteThisYear) to progress.year)
        val rowHeight = ((h - 52 - inset) / rows.size).coerceAtMost(28f)
        val labelWidth = min(cw * .32f, 90f)
        val valueWidth = 42f
        rows.forEachIndexed { index, (label, value) ->
            val y = 46f + index * rowHeight
            text(label, inset, y, labelWidth, 12f)
            val barStart = inset + labelWidth + 8
            bar(barStart, y + 5, (cw - labelWidth - valueWidth - 16).coerceAtLeast(8f), 6f, value)
            text(percent(value), w - inset - valueWidth, y, valueWidth, 12f, true, center = true)
        }
    }
    private fun year() {
        if (!small) { calendarRows(); return }
        val progress = WidgetCalendarProgress.at(now, lifeZone, DayOfWeek.of(snapshot?.calendar?.firstDayOfWeek ?: 1))
        val year = Instant.ofEpochMilli(now).atZone(lifeZone).year
        header(yearNumber(year), t(R.string.widgetSuiteDaysLeft, count(progress.daysLeftInYear)))
        val diameter = min(cw - 8, h - 59).coerceAtLeast(28f)
        val left = (w - diameter) / 2
        val top = 43f + (h - 43 - inset - diameter) / 2
        paint.style = Paint.Style.STROKE; paint.strokeWidth = 9f; paint.strokeCap = Paint.Cap.ROUND; paint.color = track
        val bounds = RectF(left + 5, top + 5, left + diameter - 5, top + diameter - 5)
        canvas.drawOval(bounds, paint); paint.color = accent
        canvas.drawArc(bounds, -90f, 360f * progress.year.toFloat(), false, paint)
        paint.style = Paint.Style.FILL
        text(percent(progress.year), left, top + diameter / 2 - 16, diameter, 22f, true, center = true)
        text(t(R.string.widgetSuitePassed), left, top + diameter / 2 + 10, diameter, 10f, color = muted, center = true)
    }

    private fun weekend(suite: WidgetSuiteSnapshot) {
        val spacious = large && h >= 270f
        val start = suite.holiday.weekendStartMs
        if (start == null) { empty(t(R.string.widgetSuiteNoScheduleMessage), t(R.string.widgetSuiteOpenSettings)); return }
        if (start <= now && suite.calendar.day(now)?.isWork == true) { empty(t(R.string.widgetSuiteOpenToRefresh)); return }
        header(t(R.string.widgetSuiteWeekendName))
        if (start <= now) {
            text(t(R.string.widgetSuiteRestingToday), inset, if (spacious) 55f else 48f, cw, if (spacious) 34f else 23f, true, lines = 2)
            text(t(R.string.widgetSuiteRestingNow), inset, if (spacious) 130f else 105f, cw, if (spacious) 15f else 12f, color = muted, lines = 2)
        } else {
            val minutes = (start - now).coerceAtLeast(0) / 60_000
            val days = minutes / (24 * 60)
            val number = NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = false }
            val zero = number.format(0).first()
            val clock = number.format(minutes / 60 % 24) + ":" + number.format(minutes % 60).padStart(2, zero)
            val parts = listOf(Triple(number.format(days), if (spacious) 68f else 40f, true), Triple(t(R.string.widgetSuiteDaysUnit), if (spacious) 22f else 15f, true), Triple(clock, if (spacious) 38f else 22f, true))
            val styles = parts.map { (_, size, bold) -> TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = size * fontScale; typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
                color = ink; fontFeatureSettings = "tnum"
            } }
            val total = parts.indices.sumOf { styles[it].measureText(parts[it].first).toDouble() }.toFloat() + 8
            val lineHeight = styles.first().fontMetrics.descent - styles.first().fontMetrics.ascent
            val factor = min(min(1f, cw / total), (if (spacious) 82f else 48f) / lineHeight.coerceAtLeast(1f))
            styles.forEach { it.textSize *= factor }
            val baseline = (if (spacious) 50f else 48f) - styles.first().fontMetrics.ascent
            var logicalStart = inset
            parts.forEachIndexed { index, (value, _, _) ->
                val style = styles[index]
                val partWidth = style.measureText(value)
                val layout = StaticLayout.Builder.obtain(value, 0, value.length, style, (partWidth + 1).roundToInt().coerceAtLeast(1))
                    .setTextDirection(if (rtl) TextDirectionHeuristics.RTL else TextDirectionHeuristics.LTR).setIncludePad(false).setMaxLines(1).build()
                canvas.save(); canvas.translate(x(logicalStart, partWidth), baseline + style.fontMetrics.ascent); layout.draw(canvas); canvas.restore()
                logicalStart += partWidth + if (index == 1) 5 else 3
            }
            text(t(R.string.widgetSuiteRestOn, date(start, "EEE") + " " + time(start)), inset, if (spacious) 142f else 102f, cw, if (spacious) 15f else 12f, color = muted)
        }
        val progress = WidgetWeekProgress.from(suite.calendar, now)
        if (spacious) {
            val gap = 6f
            val cell = (cw - gap * 6) / 7
            val height = min(cell * 1.35f, 62f)
            val top = h - inset - height - 22
            progress.days.take(7).forEachIndexed { index, day ->
                val start = inset + index * (cell + gap)
                box(start, top, cell, height, if (day.isWork) track else rest, 6f)
                val fill = progress.fill(day, now).coerceIn(0.0, 1.0).toFloat()
                if (fill > 0) box(start, top + height * (1 - fill), cell, height * fill, accent, min(6f, height * fill / 2))
                text(weekday(day.startMs), start, top + height + 5, cell, 11f, day.dayKey == today.toString(), color = muted, center = true)
            }
        } else segmentBar(h - inset - 6, progress.days.filter { it.isWork }.map { progress.fill(it, now) })
    }

    private fun holiday(payload: WidgetHolidayPayload) {
        val spacious = large && h >= 270f
        val leave = payload.nextLeave
        if (!small && payload.access.isUnlocked(now) && leave != null) {
            header(t(R.string.widgetSuiteNextLeave, count(daysUntil(leave.startMs))), payload.labels["remaining"])
            text(payload.labels["requested"].orEmpty(), inset, if (spacious) 56f else 43f, cw, if (spacious) 28f else if (h < 170) 16f else 20f, true, lines = 2)
            leaveStrip(leave.days, if (spacious) 150f else (h - inset - 56).coerceAtLeast(88f), if (spacious) 70f else if (h < 170) 18f else 22f)
            return
        }
        val holiday = payload.nextHoliday
        if (holiday == null) { empty(t(R.string.widgetSuiteHolidayRegionMissing), t(R.string.widgetSuiteOpenSettings)); return }
        if (holiday.endDayKey < today.toString()) { empty(t(R.string.widgetSuiteOpenToRefresh)); return }
        val mainWidth = if (!small) (cw - 16) / 2 else cw
        header(t(R.string.widgetSuiteNextHoliday), if (small) holiday.name else null)
        if (small) valueUnit(count(daysUntil(holiday.startMs)), t(R.string.widgetSuiteDaysUnit), 49f, 40f)
        else numberSuffix(count(daysUntil(holiday.startMs)), t(R.string.widgetSuiteDaysUnit), inset, if (spacious) 53f else 49f, mainWidth, if (spacious) 52f else 28f, if (spacious) 16f else 14f)
        if (!small) text(holiday.name, inset, if (spacious) 131f else 95f, mainWidth, if (spacious) 18f else 13f, true, lines = if (spacious) 2 else 1)
        text(t(R.string.widgetSuiteHolidayRun, date(holiday.startMs), count(holiday.days)), inset, if (spacious) 186f else if (small) 98f else 115f, mainWidth, if (spacious) 13f else if (small) 10f else 11f, color = muted, lines = if (small) 1 else 2)
        if (small) {
            if (holiday.isEstimated) text(t(R.string.widgetSuiteHolidayEstimated), inset, h - inset - 22, cw, 9f, color = muted, lines = 2)
        } else {
            val right = inset + mainWidth + 16
            box(right - 8, 44f, .6f, h - 60, track)
            text(t(R.string.widgetSuiteLeaveTitle), right, if (spacious) 53f else 45f, mainWidth, if (spacious) 16f else 13f, true)
            val allowed = payload.access.isUnlocked(now)
            text(t(if (allowed) R.string.widgetSuiteLeaveEmpty else R.string.widgetSuiteLeavePromise), right, if (spacious) 85f else 68f, mainWidth, if (spacious) 16f else 12f, color = muted, lines = if (spacious) 3 else 2)
            text(if (allowed) payload.labels["remaining"].orEmpty() else t(R.string.widgetSuiteLearnPlus), right, if (spacious) 202f else h - inset - 28, mainWidth, if (spacious) 13f else 11f, true, if (allowed) muted else accentText, lines = 2)
        }
    }
    private fun daysUntil(start: Long) = ChronoUnit.DAYS.between(today, Instant.ofEpochMilli(start).atZone(zone).toLocalDate()).coerceAtLeast(0).toInt()
    private fun leaveStrip(days: List<WidgetLeaveDay>, y: Float, height: Float) {
        val list = days.take(14)
        val gap = 3f
        val cell = (cw - gap * (list.size - 1)) / list.size.coerceAtLeast(1)
        list.forEachIndexed { index, day ->
            val start = inset + index * (cell + gap)
            val color = when (day.kind) { WidgetLeaveDayKind.HOLIDAY -> holiday; WidgetLeaveDayKind.LEAVE -> accent; else -> blend(muted, .35f) }
            box(start, y, cell, height, color, 5f)
            text(count(LocalDate.parse(day.dayKey).dayOfMonth), start, y + height + 4, cell, 9f, color = muted, center = true)
        }
        val labels = listOf(t(R.string.widgetSuiteLegendHoliday) to holiday, t(R.string.widgetSuiteLeave) to accent, t(R.string.widgetSuiteRest) to muted)
        var start = inset
        labels.forEach { (label, color) ->
            box(start, y + height + 24, 6f, 6f, color, 2f)
            val width = (cw - 24) / 3
            text(label, start + 10, y + height + 20, width - 10, 10f, color = muted)
            start += width + 8
        }
    }

    private fun summary(payload: WidgetSummaryPayload) {
        val kind = if (small) WidgetSummaryPeriodKind.WEEK else if (large) WidgetSummaryPeriodKind.YEAR else WidgetSummaryPeriodKind.MONTH
        val period = payload.period(kind)
        if (!payload.access.isUnlocked(now) || period == null) { empty(); return }
        if (today.toString() !in period.startDayKey..period.endDayKey) { empty(t(R.string.widgetSuiteOpenToRefresh)); return }
        val worked = period.workedMs(payload.liveSegments, snapshot!!.generatedAtMs, now)
        header(listOfNotNull(period.title, period.subtitle).joinToString(" · "), if (small) null else t(R.string.widgetSuiteWorkdaysRemaining, count(period.remainingWorkdays)))
        if (small) {
            val week = snapshot.calendar.week(now)
            val plannedMs = if (week.size == 7) week.sumOf { it.workMs } else 0L
            if (plannedMs > 0) {
                numberSuffix(decimal(worked / 3_600_000.0), "/ " + hours(plannedMs), inset, 43f, cw, 32f)
            } else numberSuffix(decimal(worked / 3_600_000.0), hoursUnit(), inset, 43f, cw, 32f)
            summaryBars(period, payload, 86f, (h - inset - 102).coerceAtLeast(22f))
        } else {
            val gap = 12f
            val column = (cw - gap * 2) / 3
            val stats = listOf(
                Triple(t(R.string.widgetSuiteTimeWorked), decimal(worked / 3_600_000.0), hoursUnit()),
                Triple(t(R.string.widgetSuiteWorkdays), count(period.workdays), "/ " + count(period.plannedWorkdays)),
                Triple(t(R.string.widgetSuiteOvertime), decimal(period.overtimeMs / 3_600_000.0), hoursUnit()))
            stats.forEachIndexed { index, (label, value, suffix) ->
                val start = inset + index * (column + gap)
                text(label, start, 44f, column, 11f, color = muted)
                numberSuffix(value, suffix, start, 61f, column, if (w < 300) 20f else 24f, 11f,
                    if (index == 2 && period.overtimeMs > 0) accentText else ink)
            }
            if (large) {
                text(t(R.string.widgetSuiteMonthlyHours), inset, 108f, cw, 12f, color = muted)
                val chartBottom = h - inset - if (period.comparison != null) 56 else 18
                summaryBars(period, payload, 132f, (chartBottom - 132).coerceAtLeast(35f))
                period.comparison?.let { rule(h - inset - 30); text(it, inset, h - inset - 19, cw, 12f, color = muted) }
            } else {
                bar(inset, h - inset - 24, cw, 6f, period.progress)
                text(period.comparison.orEmpty(), inset, h - inset - 12, cw - 44, 10f, color = muted)
                text(percent(period.progress), w - inset - 40, h - inset - 12, 40f, 10f, color = muted, center = true)
            }
        }
    }
    private fun summaryBars(period: WidgetSummaryPeriod, payload: WidgetSummaryPayload, top: Float, height: Float) {
        val added = (period.workedMs(payload.liveSegments, snapshot!!.generatedAtMs, now) - period.workedMs).coerceAtLeast(0)
        val values = period.bars.map { bar -> bar.valueMs + if (bar.state == WidgetSummaryBarState.CURRENT && period.kind == WidgetSummaryPeriodKind.WEEK) added else 0 }
        val maximum = values.maxOrNull()?.coerceAtLeast(1) ?: 1
        val gap = if (values.size > 7) 5f else 8f
        val cell = (cw - gap * (values.size - 1)) / values.size.coerceAtLeast(1)
        period.bars.forEachIndexed { index, item ->
            val barHeight = (height * values[index].toDouble() / maximum).toFloat().coerceAtLeast(4f)
            val color = when (item.state) { WidgetSummaryBarState.CURRENT -> accent; WidgetSummaryBarState.PAST -> softOrange; else -> track }
            val start = inset + index * (cell + gap)
            box(start, top + height - barHeight, cell, barHeight, color, 4f)
            text(item.label, start, top + height + 5, cell, 10f, color = muted, center = true)
        }
    }

    private fun life(payload: WidgetLifePayload) {
        val figures = WidgetLifeFigures.from(payload, now, lifeZone)
        if (figures == null) { empty(t(R.string.widgetSuiteLifeSetup), t(R.string.widgetSuiteOpenDoneAt)); return }
        if (!small && !large) { calendarRows(); return }
        fun span(months: Int) = t(R.string.widgetSuiteYearsMonths, count(months / 12), count(months % 12))
        if (small) {
            header(t(R.string.widgetSuiteLifeName), if (payload.hidesExactAges) null else span(figures.ageMonths))
            text(t(R.string.widgetSuiteLived), inset, 43f, cw, 12f, color = muted)
            val value = count(figures.daysLived.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
            if (payload.bornIsApproximate) text(t(R.string.widgetSuiteApproximately, value), inset, 60f, cw, 24f, true)
            else valueUnit(value, t(R.string.widgetSuiteDaysUnit), 60f, 27f, 12f)
            text(t(R.string.widgetSuiteLifeShare, percent(figures.lifeShare), count(payload.lifeYears)), inset, 94f, cw, 11f, color = muted)
            lifeBar(payload, figures, h - inset - 18)
            return
        }
        header(t(R.string.widgetSuiteLifeYears, count(payload.lifeYears)), if (payload.hidesExactAges) percent(figures.lifeShare) else span(figures.ageMonths))
        val rows = ceil(payload.lifeYears / 10.0).toInt().coerceAtLeast(1)
        val gridTop = 46f
        val bottom = h - inset - 60
        val rowHeight = (bottom - gridTop) / rows
        val yearWidth = (cw - 19) / 10
        val born = payload.bornDay
        // Scalar view geometry from iOS LifeGrid, using the already-projected civil ordinals.
        fun monthIndex(day: Long?) = if (day != null && born != null) ((day - born) / 30.436875).toInt() else null
        val careerStart = monthIndex(payload.careerStartDay)
        val careerEnd = monthIndex(payload.retirementDay)
        for (year in 0 until payload.lifeYears) {
            val row = year / 10
            if (year % 10 == 0) text(count(year), inset, gridTop + row * rowHeight + rowHeight / 2 - 5, 14f, 9f, color = muted, center = true)
            val start = inset + 19 + year % 10 * yearWidth
            val cellGap = min(2f, yearWidth / 14)
            val dot = min((yearWidth - 4 - cellGap * 3) / 4, (rowHeight - cellGap * 2 - 6) / 3).coerceAtLeast(1f)
            for (month in 0..11) {
                val index = year * 12 + month
                val inCareer = careerStart != null && careerEnd != null && index in careerStart until careerEnd
                val color = when {
                    index == figures.ageMonths -> ink
                    index < figures.ageMonths -> if (inCareer) accent else blend(muted, .70f)
                    inCareer -> softOrange
                    else -> track
                }
                box(start + month % 4 * (dot + cellGap), gridTop + row * rowHeight + month / 4 * (dot + cellGap) + 3, dot, dot, color, 1.5f)
            }
        }
        rule(bottom + 8)
        val stats = listOfNotNull(figures.monthsWorked?.let { t(R.string.widgetSuiteWorked) to span(it) }, figures.monthsToRetirement?.let { t(R.string.widgetSuiteUntilRetirement) to span(it) })
        stats.forEachIndexed { index, (label, value) ->
            val start = inset + index * (cw / 2 + 5)
            text(label, start, bottom + 20, cw / 2 - 5, 11f, color = muted)
            numberSuffix(value, "", start, bottom + 36, cw / 2 - 5, 18f)
        }
    }
    private fun lifeBar(payload: WidgetLifePayload, figures: WidgetLifeFigures, y: Float) {
        box(inset, y, cw, 8f, track, 4f)
        val born = payload.bornDay
        val end = payload.retirementDay
        val start = payload.careerStartDay
        val lifeDays = payload.lifeYears * 365.2425
        if (born != null && start != null && end != null && end > start) {
            val lower = ((start - born) / lifeDays).coerceIn(0.0, 1.0)
            val upper = ((end - born) / lifeDays).coerceIn(lower, 1.0)
            box(inset + cw * lower.toFloat(), y, cw * (upper - lower).toFloat(), 8f, softOrange)
            val completed = (figures.lifeShare - lower).coerceIn(0.0, upper - lower)
            box(inset + cw * lower.toFloat(), y, cw * completed.toFloat(), 8f, accent)
            box(inset, y, cw * min(figures.lifeShare, lower).toFloat(), 8f, blend(muted, .70f), 4f)
        } else box(inset, y, cw * figures.lifeShare.toFloat(), 8f, blend(muted, .70f), 4f)
        text(count(0), inset, y + 12, 20f, 9f, color = muted)
        text(count(payload.lifeYears), w - inset - 30, y + 12, 30f, 9f, color = muted, center = true)
    }

    private fun focus(payload: WidgetFocusPayload) {
        val block = payload.current(now)
        val next = payload.next(now)
        val titleTop = WidgetFocusLayout.titleTop(w, hostHeight)
        val timerTop = WidgetFocusLayout.timerTop(w, hostHeight)
        val buttonTop = WidgetFocusLayout.buttonTop(w, hostHeight)
        if (block == null) {
            if (next == null) { empty(t(R.string.widgetSuiteFocusEmpty), t(R.string.widgetSuiteFocusPlan)); return }
            header(t(R.string.widgetSuiteFocusNext))
            text(time(next.startMs), inset, if (large) 57f else 46f, cw, if (large) 48f else 30f, true)
            text(t(R.string.widgetSuiteFocusBlockDetail, count(((next.endMs - next.startMs) / 60_000).toInt()), next.title), inset, if (large) 129f else 85f, cw, if (large) 16f else 12f, color = muted, lines = 2)
            text(t(R.string.widgetSuiteFocusOpen), inset, h - inset - 15, cw, 12f, true, accentText)
            return
        }
        header(t(if (block.isBreak) R.string.widgetSuiteFocusBreakNow else R.string.widgetSuiteFocusNow),
            if (small || block.isBreak) null else t(R.string.widgetSuiteFocusRound, count(block.round), count(block.rounds)), if (block.isBreak) blue else accentText)
        val titleWidth = if (small || block.isBreak) cw else WidgetFocusLayout.timerWidth(w, false)
        if (!small && !block.isBreak) {
            for (index in 0..1) {
                val start = WidgetFocusLayout.buttonStart(w) + index * (WidgetFocusLayout.BUTTON_SIZE + WidgetFocusLayout.BUTTON_GAP)
                box(start, buttonTop, 44f, 44f, rest, 22f)
                if (!card.nativeFocusTimer) {
                    if (index == 0) {
                        box(start + 13, buttonTop + 21, 18f, 2f, ink, 1f)
                        box(start + 21, buttonTop + 13, 2f, 18f, ink, 1f)
                    } else box(start + 16, buttonTop + 16, 12f, 12f, ink, 2f)
                }
            }
        }
        text(block.title, inset, titleTop, titleWidth, if (large) 20f else 15f, true)
        if (!card.nativeFocusTimer) {
            val clock = widgetFocusClockText(context, block.endMs - now)
            text(clock, inset, timerTop, titleWidth, widgetFocusTimerFont(context, clock, titleWidth, small, large), true, fit = false)
        }
        val progress = ((now - block.startMs).toDouble() / (block.endMs - block.startMs).coerceAtLeast(1)).coerceIn(0.0, 1.0)
        val rounds = block.rounds.coerceAtLeast(block.round).coerceAtLeast(1)
        val visibleSegments = rounds.coerceAtMost(16)
        val overall = ((block.round - 1) + progress) / rounds
        val values = (0 until visibleSegments).map { (overall * visibleSegments - it).coerceIn(0.0, 1.0) }
        val nextBlock = payload.blocks.firstOrNull { it.startMs >= block.endMs && it.startMs > now }
        val nextCaption = nextBlock?.let { t(R.string.widgetSuiteFocusNextAt, time(it.startMs), it.title) }
        val y = h - inset - if (nextCaption != null && !small) (if (large) 42 else 26) else (if (large) 12 else 6)
        segmentBar(y, values, if (large) 12f else 6f)
        if (nextCaption != null && !small) text(nextCaption, inset, y + (if (large) 22 else 12), cw, if (large) 13f else 11f, color = muted)
        if (large) {
            val queue = payload.blocks.filter { it.startMs > now }.take(4)
            var top = 166f
            queue.forEach { item ->
                if (top + 28 < y) {
                    text(time(item.startMs), inset, top, 72f, 14f, true)
                    text(item.title, inset + 80, top, cw - 80, 14f, color = muted)
                    top += 32
                }
            }
        }
    }
}
