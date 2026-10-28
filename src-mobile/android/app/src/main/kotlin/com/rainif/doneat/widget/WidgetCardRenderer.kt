package com.rainif.doneat.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.text.format.DateFormat
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.core.content.ContextCompat
import java.time.DayOfWeek
import androidx.core.graphics.createBitmap
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.widget.*
import com.rainif.doneat.ui.timer.TimerText
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

internal data class WidgetSuiteRenderState(val kind: DoneAtWidgetKind, val snapshot: WidgetSuiteSnapshot?, val nowMs: Long)

internal data class WidgetCardDay(val label: String, val work: Boolean, val today: Boolean = false, val holiday: Boolean = false, val description: String = label)
internal data class WidgetCardBar(val label: String, val fraction: Float, val current: Boolean)
internal data class WidgetCard(
    val title: String, val headline: String, val caption: String = "", val facts: List<String> = emptyList(),
    val progress: Double? = null, val days: List<WidgetCardDay> = emptyList(), val bars: List<WidgetCardBar> = emptyList(),
    val ring: Boolean = false, val locked: Boolean = false,
    val suite: WidgetSuiteRenderState? = null, val nativeFocusTimer: Boolean = false,
) {
    val description get() = (listOf(title, headline, caption) + facts + days.map { it.description }).filter { it.isNotBlank() }.joinToString(". ")
}

/** Formats only the salary-free projection. Schedule resolution and paid-data redaction happen in the producer. */
internal fun widgetSuiteCard(context: Context, kind: DoneAtWidgetKind, raw: WidgetSuiteSnapshot?, nowMs: Long): WidgetCard {
    val snapshot = raw?.redacted(nowMs)
    val res = context.resources
    val locale = res.configuration.locales[0]
    val text = TimerText(res, locale, DateFormat.is24HourFormat(context), hideEarnings = true)
    fun t(id: Int, vararg args: Any) = res.getString(id, *args)
    fun count(n: Int) = text.count(n)
    fun hours(ms: Long) = text.hours(ms / 3_600_000.0)
    val title = t(kind.titleRes)
    val render = WidgetSuiteRenderState(kind, snapshot, nowMs)
    fun empty(message: Int = R.string.widgetSuiteOpenToRefresh) = WidgetCard(title, t(message), t(R.string.widgetSuiteOpenDoneAt), suite = render)
    fun lock(promise: Int) = WidgetCard(title, "Plus", t(promise), listOf(t(R.string.widgetSuiteLearnPlus)), locked = true, suite = render)
    if (snapshot == null && kind == DoneAtWidgetKind.YEAR) {
        val progress = WidgetCalendarProgress.at(nowMs, ZoneId.systemDefault(), java.time.temporal.WeekFields.of(locale).firstDayOfWeek)
        return WidgetCard(title, java.text.NumberFormat.getPercentInstance(locale).format(progress.year),
            count(Instant.ofEpochMilli(nowMs).atZone(ZoneId.systemDefault()).year), listOf(t(R.string.widgetSuiteDaysLeft, count(progress.daysLeftInYear))), suite = render)
    }
    if (snapshot == null) return if (kind.plus) lock(when (kind) {
        DoneAtWidgetKind.SUMMARY -> R.string.widgetSuiteSummaryPromise
        DoneAtWidgetKind.LIFE -> R.string.widgetSuiteLifePromise
        else -> R.string.widgetSuiteFocusPromise
    }) else empty()
    val zone = ZoneId.of(snapshot.timeZoneIdentifier)
    val today = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
    fun date(ms: Long) = Instant.ofEpochMilli(ms).atZone(zone).format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "MMMd"), locale))
    fun time(ms: Long) = Instant.ofEpochMilli(ms).atZone(zone).format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, if (DateFormat.is24HourFormat(context)) "Hm" else "hm"), locale))
    fun remainingDays(ms: Long) = ChronoUnit.DAYS.between(today, Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()).coerceAtLeast(0).toInt()
    fun days(days: List<WidgetCalendarDay>) = days.map { d ->
        val day = LocalDate.parse(d.dayKey)
        WidgetCardDay(count(day.dayOfMonth), d.isWork, day == today, d.kind == WidgetCalendarDayKind.HOLIDAY || d.kind == WidgetCalendarDayKind.LEAVE, date(d.startMs) + " · " + (d.title ?: t(if (d.isWork) R.string.widgetSuiteWork else R.string.widgetSuiteRest)))
    }
    val result = when (kind) {
        DoneAtWidgetKind.WEEK -> {
            val week = snapshot.calendar.week(nowMs)
            if (week.isEmpty()) empty(R.string.widgetSuiteNoScheduleMessage) else {
                val progress = WidgetWeekProgress.from(snapshot.calendar, nowMs)
                WidgetCard(title, hours(progress.remainingMs), t(R.string.widgetSuiteWorkdaysRemaining, java.text.NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 1 }.format(progress.remainingDays)),
                    progress = progress.progress, days = days(week))
            }
        }
        DoneAtWidgetKind.ROSTER -> {
            val todayDay = snapshot.calendar.day(nowMs) ?: return empty(R.string.widgetSuiteNoScheduleMessage)
            val current = if (todayDay.isWork && (todayDay.endAtMs ?: 0) > nowMs) todayDay else
                snapshot.calendar.days.firstOrNull { it.dayKey == today.plusDays(1).toString() } ?: todayDay
            val month = snapshot.calendar.days.filter { it.dayKey.startsWith(today.toString().take(7)) }
            val leading = month.firstOrNull()?.let { (LocalDate.parse(it.dayKey).dayOfWeek.value - snapshot.calendar.firstDayOfWeek + 7) % 7 } ?: 0
            val status = current.title ?: t(if (current.isWork) R.string.widgetSuiteWork else R.string.widgetSuiteRest)
            val shift = if (current.startAtMs != null && current.endAtMs != null) "${time(current.startAtMs!!)} – ${time(current.endAtMs!!)}" else t(R.string.widgetSuiteRestingToday)
            val tomorrow = snapshot.calendar.days.firstOrNull { it.dayKey == today.plusDays(1).toString() }
            WidgetCard(title, status, shift, listOfNotNull(tomorrow?.let { t(R.string.widgetSuiteTomorrow) + " · " + (it.title ?: t(if (it.isWork) R.string.widgetSuiteWork else R.string.widgetSuiteRest)) }), days = List(leading) { WidgetCardDay("", false) } + days(month))
        }
        DoneAtWidgetKind.YEAR -> {
            val progress = WidgetCalendarProgress.at(nowMs, ZoneId.of(snapshot.lifeTimeZoneIdentifier), DayOfWeek.of(snapshot.calendar.firstDayOfWeek))
            val share = progress.year
            WidgetCard(title, java.text.NumberFormat.getPercentInstance(locale).format(share), count(Instant.ofEpochMilli(nowMs).atZone(ZoneId.of(snapshot.lifeTimeZoneIdentifier)).year),
                listOf(t(R.string.widgetSuiteDaysLeft, count(progress.daysLeftInYear))), progress = share, ring = true)
        }
        DoneAtWidgetKind.WEEKEND -> {
            val start = snapshot.holiday.weekendStartMs
            if (start == null) empty(R.string.widgetSuiteNoScheduleMessage)
            else if (start <= nowMs && snapshot.calendar.day(nowMs)?.isWork == true) empty()
            else if (start <= nowMs) WidgetCard(title, t(R.string.widgetSuiteRestingToday), t(R.string.widgetSuiteRestingNow))
            else WidgetCard(title, text.hours((start - nowMs) / 3_600_000.0), t(R.string.widgetSuiteRestOn, date(start)))
        }
        DoneAtWidgetKind.HOLIDAY -> {
            val holiday = snapshot.holiday.nextHoliday ?: return empty(R.string.widgetSuiteHolidayRegionMissing)
            if (holiday.endDayKey < today.toString()) return empty()
            val facts = mutableListOf(t(R.string.widgetSuiteHolidayRun, date(holiday.startMs), count(holiday.days)))
            if (holiday.isEstimated) facts += t(R.string.widgetSuiteHolidayEstimated)
            snapshot.holiday.nextLeave?.let { facts += t(R.string.widgetSuiteNextLeave, count(remainingDays(it.startMs))) }
            snapshot.holiday.labels["requested"]?.let(facts::add)
            snapshot.holiday.labels["remaining"]?.let(facts::add)
            WidgetCard(title, t(R.string.widgetSuiteDaysCount, count(remainingDays(holiday.startMs))), holiday.name, facts)
        }
        DoneAtWidgetKind.SUMMARY -> {
            if (!snapshot.summary.access.isUnlocked(nowMs)) return lock(R.string.widgetSuiteSummaryPromise)
            val period = snapshot.summary.period(WidgetSummaryPeriodKind.WEEK) ?: return empty()
            if (today.toString() !in period.startDayKey..period.endDayKey) return empty()
            val maxBar = period.bars.maxOfOrNull { it.valueMs }?.coerceAtLeast(1) ?: 1
            val facts = snapshot.summary.periods.flatMap { item ->
                listOf(item.title + " · " + hours(item.workedMs(snapshot.summary.liveSegments, snapshot.generatedAtMs, nowMs)),
                    t(R.string.widgetSuiteWorkdayCount, count(item.workdays)), t(R.string.widgetSuiteOvertime) + " · " + hours(item.overtimeMs)) + listOfNotNull(item.comparison)
            }
            WidgetCard(title, hours(period.workedMs(snapshot.summary.liveSegments, snapshot.generatedAtMs, nowMs)), period.title, facts,
                period.progress, bars = period.bars.map { WidgetCardBar(it.label, (it.valueMs.toDouble() / maxBar).toFloat(), it.state == WidgetSummaryBarState.CURRENT) })
        }
        DoneAtWidgetKind.LIFE -> {
            val payload = snapshot.life
            if (!payload.access.isUnlocked(nowMs)) return lock(R.string.widgetSuiteLifePromise)
            val figures = WidgetLifeFigures.from(payload, nowMs, ZoneId.of(snapshot.lifeTimeZoneIdentifier)) ?: return empty(R.string.widgetSuiteLifeSetup)
            val lived = figures.daysLived
            val share = figures.lifeShare
            val value = t(R.string.widgetSuiteDaysCount, count(lived.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()))
            val headline = if (payload.bornIsApproximate) t(R.string.widgetSuiteApproximately, value) else value
            val facts = mutableListOf(t(R.string.widgetSuiteLifeShare, java.text.NumberFormat.getPercentInstance(locale).format(share), count(payload.lifeYears)))
            fun span(months: Int) = t(R.string.widgetSuiteYearsMonths, count(months / 12), count(months % 12))
            figures.monthsWorked?.let { facts += t(R.string.widgetSuiteWorked) + " · " + span(it) }
            figures.monthsToRetirement?.let { facts += t(R.string.widgetSuiteUntilRetirement) + " · " + span(it) }
            WidgetCard(title, headline, t(R.string.widgetSuiteLived), facts, progress = share)
        }
        DoneAtWidgetKind.FOCUS -> {
            val payload = snapshot.focus
            if (!payload.access.isUnlocked(nowMs)) return lock(R.string.widgetSuiteFocusPromise)
            val block = payload.current(nowMs)
            val next = payload.next(nowMs)
            if (block == null) WidgetCard(title, next?.title ?: t(R.string.widgetSuiteFocusEmpty), next?.let { t(R.string.widgetSuiteStartsAt, time(it.startMs)) } ?: t(R.string.widgetSuiteFocusPlan))
            else WidgetCard(title, t(R.string.minutesShort, count(((block.endMs - nowMs).coerceAtLeast(0) + 59_999).div(60_000).toInt())), block.title,
                listOf(t(if (block.isBreak) R.string.widgetSuiteFocusBreakNow else R.string.widgetSuiteFocusNow), t(R.string.widgetSuiteFocusRound, count(block.round), count(block.rounds))) + listOfNotNull(next?.let { t(R.string.widgetSuiteFocusNextAt, time(it.startMs), it.title) }),
                progress = ((nowMs - block.startMs).toDouble() / (block.endMs - block.startMs).coerceAtLeast(1)).coerceIn(0.0, 1.0))
        }
        else -> empty()
    }
    return result.copy(suite = render)
}

/** Shared rendered preview: launcher and gallery use the same data, typography and chart geometry. */
internal fun widgetCardBitmap(context: Context, card: WidgetCard, size: DpSize): Bitmap {
    if (card.suite != null) return WidgetSuitePainter(context, card, size).render()
    val density = context.resources.displayMetrics.density
    val width = (size.width.value * density).roundToInt().coerceAtLeast(1)
    val height = (size.height.value * density).roundToInt().coerceAtLeast(1)
    val image = createBitmap(width, height)
    val canvas = Canvas(image)
    canvas.scale(density, density)
    val w = size.width.value
    val h = size.height.value
    val foreground = ContextCompat.getColor(context, R.color.widget_primary)
    val secondary = ContextCompat.getColor(context, R.color.widget_secondary)
    val track = ContextCompat.getColor(context, R.color.widget_track)
    val accent = ContextCompat.getColor(context, R.color.widget_accent)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    paint.color = ContextCompat.getColor(context, R.color.widget_background)
    canvas.drawRoundRect(0f, 0f, w, h, 22f, 22f, paint)
    val inset = 16f
    val contentWidth = (w - inset * 2).coerceAtLeast(1f)
    var y = inset
    fun line(value: String, sp: Float, bold: Boolean = false, color: Int = foreground, maxLines: Int = 2) {
        if (value.isBlank() || y > h - inset) return
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textSize = sp * context.resources.configuration.fontScale
            typeface = if (bold) Typeface.create("sans-serif", Typeface.BOLD) else Typeface.create("sans-serif", Typeface.NORMAL)
        }
        val remainingLines = ((h - inset - y) / max(1f, tp.fontSpacing)).toInt().coerceAtLeast(1)
        val layout = StaticLayout.Builder.obtain(value, 0, value.length, tp, contentWidth.toInt())
            .setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(false).setMaxLines(minOf(maxLines, remainingLines))
            .setEllipsize(TextUtils.TruncateAt.END).build()
        canvas.save(); canvas.translate(inset, y); layout.draw(canvas); canvas.restore()
        y += layout.height + 5f
    }
    line(card.title, 12f, true, color = accent, maxLines = 1)
    y += 4f
    line(card.headline, if (w < 200) 24f else 30f, true)
    line(card.caption, 12f, color = secondary)
    val graphHeight = when { card.days.size > 7 -> if (h > 220) 100f else 34f; card.bars.isNotEmpty() -> 46f; card.ring -> 56f; else -> 0f }
    val factsBudget = ((h - y - inset - graphHeight - (if (card.progress != null) 14 else 0)) / 20).toInt().coerceAtLeast(0)
    card.facts.take(factsBudget).forEach { line(it, 11f, color = secondary, maxLines = 1) }
    if (card.days.isNotEmpty() && h - y > 30) {
        val days = if (card.days.size > 7 && h < 220) card.days.take(7) else card.days
        val columns = 7
        val cell = contentWidth / columns
        val rowHeight = if (days.size > 7) 20f else 26f
        // Month grid retains the calendar's configured first weekday; leading blanks are explicit.
        days.forEachIndexed { index, day ->
            if (day.label.isBlank()) return@forEachIndexed
            val x = inset + (index % columns) * cell + cell / 2
            val cy = y + (index / columns) * rowHeight + rowHeight / 2
            if (cy < h - inset) {
                paint.color = if (day.work) accent else if (day.holiday) secondary else track
                canvas.drawCircle(x, cy, minOf(9f, cell / 2 - 2f), paint)
                if (day.today) { paint.style = Paint.Style.STROKE; paint.strokeWidth = 1.5f; paint.color = foreground; canvas.drawCircle(x, cy, minOf(11f, cell / 2 - 1f), paint); paint.style = Paint.Style.FILL }
                paint.typeface = Typeface.create("sans-serif", Typeface.BOLD); paint.textSize = 9f; paint.color = if (day.work || day.holiday) Color.WHITE else foreground; paint.textAlign = Paint.Align.CENTER
                canvas.drawText(day.label, x, cy - (paint.ascent() + paint.descent()) / 2, paint)
            }
        }
        y += ((days.size + 6) / 7) * rowHeight + 6f
    }
    if (card.bars.isNotEmpty() && h - y > 35) {
        val cell = contentWidth / card.bars.size
        val graphBottom = minOf(h - inset - 14, y + 38)
        card.bars.forEachIndexed { i, bar ->
            paint.color = if (bar.current) accent else secondary
            val left = inset + i * cell + 2
            canvas.drawRoundRect(left, graphBottom - max(2f, 32 * bar.fraction), left + max(2f, cell - 4), graphBottom, 2f, 2f, paint)
            paint.textSize = 8f; paint.textAlign = Paint.Align.CENTER
            canvas.drawText(bar.label, left + (cell - 4) / 2, graphBottom + 11, paint)
        }
    }
    card.progress?.let { value ->
        val progress = value.coerceIn(0.0, 1.0).toFloat()
        paint.color = track
        if (card.ring && h - y > 42) {
            val diameter = minOf(60f, h - y - inset)
            val bounds = RectF(inset, y + 4, inset + diameter, y + 4 + diameter)
            paint.style = Paint.Style.STROKE; paint.strokeWidth = 6f; paint.strokeCap = Paint.Cap.ROUND
            canvas.drawOval(bounds, paint); paint.color = accent; canvas.drawArc(bounds, -90f, 360f * progress, false, paint)
            paint.style = Paint.Style.FILL
        } else if (h > 100) {
            val bottom = h - inset
            canvas.drawRoundRect(inset, bottom - 6, w - inset, bottom, 3f, 3f, paint)
            paint.color = accent
            canvas.drawRoundRect(inset, bottom - 6, inset + contentWidth * progress, bottom, 3f, 3f, paint)
        }
    }
    return image
}
