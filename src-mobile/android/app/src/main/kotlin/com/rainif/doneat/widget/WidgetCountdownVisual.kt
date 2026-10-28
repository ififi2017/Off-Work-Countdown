package com.rainif.doneat.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.text.format.DateFormat
import android.view.Gravity
import android.view.View
import androidx.compose.ui.unit.DpSize
import androidx.core.content.ContextCompat
import androidx.core.graphics.PathParser
import androidx.core.graphics.createBitmap
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.widget.*
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Host dp/sp bounds for the system Chronometer; the bitmap deliberately leaves these digits empty. */
internal data class CountdownTimerPlacement(val left: Float, val top: Float, val width: Float, val height: Float, val fontSp: Float, val gravity: Int, val color: Int)
internal data class CountdownVisual(val bitmap: Bitmap, val timer: CountdownTimerPlacement?, val description: String)

/** One layout for launcher and gallery. The launcher overlays a live timer; previews sample its value. */
internal fun widgetCountdownVisual(context: Context, kind: DoneAtWidgetKind, entry: WidgetEntry?, upcoming: List<WidgetUpcomingItem>,
    segments: List<WidgetTimeSegment>, nowMs: Long, size: DpSize, zone: ZoneId = ZoneId.systemDefault(), sampleTimer: Boolean = false): CountdownVisual =
    CountdownDrawing(context, kind, entry, upcoming, segments, nowMs, size, zone, sampleTimer).draw()

/** Static geometry over precomputed segments only; no shift is scheduled or resolved here. */
private class CountdownDrawing(private val context: Context, private val kind: DoneAtWidgetKind, private val entry: WidgetEntry?,
    upcoming: List<WidgetUpcomingItem>, private val segments: List<WidgetTimeSegment>, private val now: Long,
    size: DpSize, private val zone: ZoneId, private val sampleTimer: Boolean) {
    private val res = context.resources
    private val locale = res.configuration.locales[0]
    private val density = res.displayMetrics.density
    private val fontScale = res.displayMetrics.scaledDensity / density
    private val rtl = res.configuration.layoutDirection == View.LAYOUT_DIRECTION_RTL
    private val width = size.width.value.coerceAtLeast(1f)
    private val height = size.height.value.coerceAtLeast(1f)
    private val large = width >= 210 && height >= 250
    private val medium = !large && width >= 220
    private val compact = medium && height < 145
    private val wide = kind == DoneAtWidgetKind.CLASSIC || kind == DoneAtWidgetKind.DETAIL
    // The optional glance styles have real wide/tall layouts. Do not centre a
    // scaled 170-square inside a larger host: its timer and artwork both need
    // to use the complete allocated rectangle.
    private val expandedStyle = !wide && (width >= 220 || height >= 250)
    private val baseW = if (expandedStyle) width else if (wide && (medium || large)) 364f else 170f
    private val baseH = if (expandedStyle) height else if (wide && large) 382f else if (wide && compact) 118f else 170f
    private val scale = min(width / baseW, height / baseH)
    private val originX = (width - baseW * scale) / 2
    private val originY = (height - baseH * scale) / 2
    private val bitmap = createBitmap((width * density).roundToInt().coerceAtLeast(1), (height * density).roundToInt().coerceAtLeast(1))
    private val canvas = Canvas(bitmap)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val primary = ContextCompat.getColor(context, R.color.widget_primary)
    private val secondary = ContextCompat.getColor(context, R.color.widget_secondary)
    private val track = ContextCompat.getColor(context, R.color.widget_track)
    private val accent = ContextCompat.getColor(context, R.color.widget_accent)
    private val background = ContextCompat.getColor(context, R.color.widget_background)
    private val night = res.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES
    private val phaseColor = when (entry?.phase) {
        WidgetPhase.BEFORE -> if (night) 0xFF5E5CE6.toInt() else 0xFF5856D6.toInt()
        WidgetPhase.BREAK -> if (night) 0xFF64D2FF.toInt() else 0xFF32ADE6.toInt()
        WidgetPhase.DONE -> if (night) 0xFF30D158.toInt() else 0xFF34C759.toInt()
        else -> accent
    }
    private val progress = (entry?.progressAtDate ?: 0.0).coerceIn(0.0, 100.0) / 100
    private val items = upcoming.filter { it.dateMs > now }
    private val target = entry?.countdownTargetAtMs ?: entry?.nextBoundaryAtMs
    private val counting = entry?.timerEndAtMs?.let { it > now } == true
    private var timer: CountdownTimerPlacement? = null
    private val description = mutableListOf<String>()
    private fun t(key: Int) = res.getString(key)
    private val label = entry?.let { t(countdownLabel(it.labelKey)) } ?: t(R.string.countdownNotStarted)
    private val percent = NumberFormat.getPercentInstance(locale).format(progress)
    private fun x(left: Float, w: Float) = if (rtl) baseW - left - w else left
    private fun clock(ms: Long, day: Boolean = false): String {
        val skeleton = (if (day) "EEE" else "") + if (DateFormat.is24HourFormat(context)) "Hm" else "hm"
        return Instant.ofEpochMilli(ms).atZone(zone).format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, skeleton), locale))
    }
    private fun number(value: Long, two: Boolean = false) = NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = false; minimumIntegerDigits = if (two) 2 else 1 }.format(value)
    private val timerText: String get() {
        val s = ((entry?.timerEndAtMs?.minus(now) ?: 0) / 1_000).coerceAtLeast(0)
        return if (s >= 3_600) "${number(s / 3_600)}:${number(s / 60 % 60, true)}:${number(s % 60, true)}" else "${number(s / 60, true)}:${number(s % 60, true)}"
    }

    fun draw(): CountdownVisual {
        canvas.scale(density, density); paint.color = background
        canvas.drawRoundRect(0f, 0f, width, height, 22f, 22f, paint)
        canvas.save(); canvas.translate(originX, originY); canvas.scale(scale, scale)
        description += label; target?.let { description += clock(it) }
        if (entry == null) empty() else when (kind) {
            DoneAtWidgetKind.CLASSIC -> when { large -> classicLarge(); medium -> classicMedium(); else -> classicSmall() }
            DoneAtWidgetKind.BIG -> big(); DoneAtWidgetKind.RING -> ringStyle(); DoneAtWidgetKind.TIMELINE -> timeline()
            DoneAtWidgetKind.DETAIL -> if (large) detailLarge() else detailMedium(); else -> empty()
        }
        canvas.restore()
        return CountdownVisual(bitmap, if (sampleTimer) null else timer, description.joinToString(". "))
    }
    private fun text(value: String, left: Float, top: Float, w: Float, sp: Float, bold: Boolean = false, color: Int = primary, center: Boolean = false, maxLines: Int = 1) {
        if (value.isBlank() || w <= 0) return
        val p = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL); textSize = sp * fontScale }
        if (maxLines == 1 && p.measureText(value) > w) p.textSize = max(sp * fontScale * 0.7f, p.textSize * w / p.measureText(value))
        // Fixed widget slots fit text rather than allowing an accessibility font to overlap the next row.
        p.textSize = min(p.textSize, sp * 1.2f)
        val layout = StaticLayout.Builder.obtain(value, 0, value.length, p, w.roundToInt().coerceAtLeast(1)).setIncludePad(false).setMaxLines(maxLines)
            .setEllipsize(TextUtils.TruncateAt.END).setAlignment(if (center) Layout.Alignment.ALIGN_CENTER else Layout.Alignment.ALIGN_NORMAL)
            .setTextDirection(if (rtl) TextDirectionHeuristics.FIRSTSTRONG_RTL else TextDirectionHeuristics.FIRSTSTRONG_LTR).build()
        canvas.save(); canvas.translate(x(left, w), top); layout.draw(canvas); canvas.restore()
    }
    private fun timer(left: Float, top: Float, w: Float, sp: Float, center: Boolean = false) {
        if (!counting && kind != DoneAtWidgetKind.CLASSIC) { text(label, left, top + sp * 0.12f, w, sp * 0.57f, true, center = center, maxLines = 2); return }
        val value = if (counting) timerText else "0:00:00"
        val p = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = primary; typeface = Typeface.create("sans-serif", Typeface.BOLD); fontFeatureSettings = "tnum"; textSize = sp * fontScale }
        // Released iOS and Android keep system-ticked seconds; fit the real figure, never crop or fake minutes.
        p.textSize = min(sp * 1.2f, min(p.textSize, (w - 2).coerceAtLeast(1f) / p.measureText(value).coerceAtLeast(1f) * p.textSize))
        val h = p.fontMetrics.descent - p.fontMetrics.ascent + 2
        val gravity = (if (center) Gravity.CENTER_HORIZONTAL else if (rtl) Gravity.RIGHT else Gravity.LEFT) or Gravity.TOP
        timer = CountdownTimerPlacement(originX + x(left, w) * scale, originY + top * scale, w * scale, h * scale, p.textSize * scale / fontScale, gravity, primary)
        if (sampleTimer || !counting) {
            p.textAlign = if (center) Paint.Align.CENTER else if (rtl) Paint.Align.RIGHT else Paint.Align.LEFT
            canvas.drawText(value, x(left, w) + if (center) w / 2 else if (rtl) w else 0f, top - p.fontMetrics.ascent, p)
        }
    }
    private fun rect(left: Float, top: Float, w: Float, h: Float, color: Int, radius: Float = 0f) {
        paint.color = color; paint.style = Paint.Style.FILL
        canvas.drawRoundRect(x(left, w), top, x(left, w) + w, top + h, radius, radius, paint)
    }
    private fun brand(left: Float, top: Float, side: Float) {
        val drawable = ContextCompat.getDrawable(context, R.drawable.ic_launcher_monochrome)?.mutate() ?: return
        drawable.colorFilter = PorterDuffColorFilter(accent, PorterDuff.Mode.SRC_IN)
        canvas.save(); canvas.translate(x(left, side), top); canvas.clipRect(0f, 0f, side, side)
        val bleed = side * (108f / 72f - 1f) / 2
        drawable.setBounds((-bleed).roundToInt(), (-bleed).roundToInt(), (side + bleed).roundToInt(), (side + bleed).roundToInt()); drawable.draw(canvas); canvas.restore()
    }
    private fun header(top: Float = 16f, mark: Float = 22f, title: String = t(R.string.app_name)) {
        brand(16f, top, mark); text(title, 24 + mark, top + (mark - 14) / 2, baseW - mark - 56, 12f, true)
    }
    private fun badge(left: Float, top: Float) {
        val p = TextPaint().apply { textSize = 11 * fontScale }
        val w = min(baseW - left - 16, p.measureText(label) + 34)
        rect(left, top, w, 22f, (phaseColor and 0x00FFFFFF) or 0x20000000, 11f); rect(left + 9, top + 8, 6f, 6f, phaseColor, 3f)
        text(label, left + 21, top + 4, w - 28, 11f, true)
    }
    private fun targetLine(left: Float, top: Float, w: Float, color: Int = secondary, withPercent: Boolean = false) {
        val inset = if (target != null) 14f else 0f
        if (target != null) icon("clock", left, top + 1, 10f, color)
        text(listOfNotNull(target?.let { clock(it) }, percent.takeIf { withPercent }).joinToString(" · "), left + inset, top, w - inset, 11f, color = color)
    }
    private fun footer(top: Float) {
        text(percent, 16f, top, 58f, 11f, true, accent)
        target?.let { icon("clock", baseW - 70, top + 1, 10f, secondary); text(clock(it), baseW - 56, top, 40f, 11f, color = secondary) }
    }
    private fun simpleBar(left: Float, top: Float, w: Float, h: Float = 7f) {
        rect(left, top, w, h, track, h / 2); if (progress > 0) rect(left, top, (w * progress).toFloat().coerceAtLeast(h), h, accent, h / 2)
    }
    private fun weights() = if (entry?.phase == WidgetPhase.WORKING || entry?.phase == WidgetPhase.BREAK) segments.map { it.durationMs.toDouble() }.filter { it > 0 }.ifEmpty { listOf(1.0) } else listOf(1.0)
    private fun segmentBar(left: Float, top: Float, w: Float, h: Float = 6f) {
        val weights = weights(); val total = weights.sum(); val usable = w - 3 * (weights.size - 1)
        var cursor = left; var remaining = progress * total
        for (weight in weights) {
            val width = (usable * weight / total).toFloat(); rect(cursor, top, width, h, track, h / 2)
            val fill = min(weight, max(0.0, remaining)) / weight
            if (fill > 0) rect(cursor, top, max(h, (width * fill).toFloat()).coerceAtMost(width), h, accent, h / 2)
            remaining -= weight; cursor += width + 3
        }
    }
    private fun ring(left: Float, top: Float, diameter: Float, segmented: Boolean, stroke: Float, centerPercent: Boolean = false) {
        val weights = if (segmented) weights() else listOf(1.0); val total = weights.sum()
        val gap = if (weights.size > 1) min(0.2, (stroke + max(2.5f, stroke * 0.6f)) / (diameter * PI)) else 0.0
        val bounds = RectF(x(left, diameter) + stroke / 2, top + stroke / 2, x(left, diameter) + diameter - stroke / 2, top + diameter - stroke / 2)
        paint.style = Paint.Style.STROKE; paint.strokeWidth = stroke; paint.strokeCap = Paint.Cap.ROUND
        var cursor = 0.0; var remaining = progress * total
        for (weight in weights) {
            val share = weight / total; val start = cursor + gap / 2; val end = max(start, cursor + share - gap / 2)
            paint.color = track; canvas.drawArc(bounds, (-90 + start * 360).toFloat(), ((end - start) * 360).toFloat(), false, paint)
            val filled = min(weight, max(0.0, remaining)) / weight
            if (filled > 0) { paint.color = if (segmented) phaseColor else accent; canvas.drawArc(bounds, (-90 + start * 360).toFloat(), ((end - start) * filled * 360).toFloat(), false, paint) }
            remaining -= weight; cursor += share
        }
        paint.style = Paint.Style.FILL
        if (centerPercent) text(percent, left + 8, top + diameter / 2 - 10, diameter - 16, 16f, true, center = true)
    }
    private fun classicSmall() {
        header(mark = 20f); badge(16f, 45f); timer(16f, 74f, 138f, 33f); simpleBar(16f, 132f, 138f); footer(145f)
    }
    private fun classicMedium() {
        if (compact) {
            header(12f, 18f); text(label, 16f, 38f, 225f, 11f, true, phaseColor); timer(16f, 55f, 225f, 34f)
            targetLine(16f, 97f, 225f); ring(276f, 28f, 72f, false, 8f, true)
        } else {
            header(); badge(16f, 51f); timer(16f, 80f, 235f, 38f); targetLine(16f, 130f, 218f); ring(269f, 61f, 76f, false, 8f, true)
        }
    }
    private fun classicLarge() {
        header(); badge(16f, 48f); timer(16f, 77f, 332f, 40f); simpleBar(16f, 132f, 332f); footer(145f)
        text(t(R.string.comingUp), 16f, 171f, 332f, 11f, true, secondary); upcoming(16f, 192f, 332f, 4, false, true, 40f)
    }
    private fun big() {
        if (expandedStyle) { bigExpanded(); return }
        icon(phaseGlyph(), 16f, 38f, 13f, phaseColor)
        text(if (entry?.phase == WidgetPhase.WORKING) t(R.string.timeLeftCaption) else label, 34f, 37f, 120f, 13f, true, secondary)
        if (counting) timer(16f, 60f, 138f, 60f) else icon(if (entry?.phase == WidgetPhase.DONE) "check" else "sunrise", 16f, 62f, 40f, phaseColor)
        target?.takeIf { counting }?.let { text(clock(it), 16f, 119f, 138f, 13f, true, phaseColor) }
    }
    private fun bigExpanded() {
        val pad = min(baseW, baseH).times(0.095f).coerceIn(10f, 20f)
        val content = baseW - 2 * pad
        val tall = baseH >= 250
        val caption = if (entry?.phase == WidgetPhase.WORKING) t(R.string.timeLeftCaption) else label
        icon(phaseGlyph(), pad, pad + 1, if (tall) 17f else 13f, phaseColor)
        text(caption, pad + if (tall) 25f else 20f, pad, content - 25, if (tall) 15f else 13f, true, secondary)
        val top = if (tall) max(pad + 38, baseH * 0.24f) else pad + 24
        val font = if (tall) (baseW * 0.26f).coerceIn(48f, 96f)
            else min(72f, ((baseH - pad - 24 - top) / 1.2f).coerceAtLeast(24f))
        if (counting) timer(pad, top, content, font)
        else icon(if (entry?.phase == WidgetPhase.DONE) "check" else "sunrise", pad, top + 3, if (tall) 64f else 46f, phaseColor)
        if (tall) {
            val digitsBottom = timer?.let { (it.top + it.height - originY) / scale } ?: top + 64
            target?.takeIf { counting }?.let { text(clock(it), pad, digitsBottom + 12, content, 19f, true, phaseColor) }
            text(t(R.string.widgetSuiteToday), pad, baseH - pad - 56, content - 74, 12f, true, secondary)
            text(percent, baseW - pad - 66, baseH - pad - 59, 66f, 16f, true, phaseColor)
            shiftSummary(pad, baseH - pad - 28, content)
        } else {
            target?.takeIf { counting }?.let { text(clock(it), pad, baseH - pad - 16, content, 13f, true, phaseColor) }
        }
    }
    private fun ringStyle() {
        if (expandedStyle) { ringExpanded(); return }
        ring(21f, 21f, 128f, true, 9f); icon(phaseGlyph(), 78f, 52f, 14f, phaseColor)
        if (counting) timer(39f, 74f, 92f, 26f, true) else icon(if (entry?.phase == WidgetPhase.DONE) "check" else "play", 71f, 74f, 28f, phaseColor)
        target?.takeIf { counting }?.let { text(clock(it), 36f, 108f, 98f, 11f, color = secondary, center = true) }
    }
    private fun ringExpanded() {
        val pad = min(baseW, baseH).times(0.095f).coerceIn(10f, 20f)
        val tall = baseH >= 250
        val diameter = if (tall) min(baseW - pad * 2, baseH - 110).coerceAtLeast(90f)
            else min(baseH - 2 * pad, (baseW - 3 * pad) * 0.46f).coerceAtLeast(70f)
        val left = if (tall) (baseW - diameter) / 2 else pad
        val top = if (tall) pad + 27 + max(0f, (baseH - pad - 28 - (pad + 27) - diameter - 16) / 2) else (baseH - diameter) / 2
        val stroke = (diameter * 0.07f).coerceIn(7f, 12f)
        ring(left, top, diameter, true, stroke)
        icon(phaseGlyph(), left + diameter / 2 - 8, top + diameter * 0.24f, 16f, phaseColor)
        val timerWidth = diameter * 0.68f
        if (counting) timer(left + (diameter - timerWidth) / 2, top + diameter * 0.41f, timerWidth, if (tall) 46f else 27f, true)
        else icon(if (entry?.phase == WidgetPhase.DONE) "check" else "play", left + diameter / 2 - 15, top + diameter * 0.43f, 30f, phaseColor)
        target?.takeIf { counting }?.let { text(clock(it), left + diameter * 0.16f, top + diameter * 0.68f, diameter * 0.68f, if (tall) 14f else 11f, color = secondary, center = true) }
        if (tall) {
            brand(pad, pad, 18f); text(label, pad + 26, pad + 2, baseW - 2 * pad - 26, 13f, true, phaseColor)
            shiftSummary(pad, baseH - pad - 28, baseW - 2 * pad)
        } else {
            val side = left + diameter + 22
            val sideWidth = (baseW - side - pad).coerceAtLeast(1f)
            text(label, side, pad + 3, sideWidth, 13f, true, secondary)
            val percentFont = min(32f, ((baseH - pad - 28 - baseH * 0.36f - 8) / 1.45f).coerceAtLeast(16f))
            text(percent, side, baseH * 0.36f, sideWidth, percentFont, true, phaseColor)
            shiftSummary(side, baseH - pad - 28, sideWidth)
        }
    }
    /** A wider host can show both exact segment weights and their already-resolved clock boundaries. */
    private fun shiftSummary(left: Float, top: Float, w: Float) {
        segmentBar(left, top, w)
        val first = segments.firstOrNull()
        val last = segments.lastOrNull()
        if (first == null || last == null) { targetLine(left, top + 14, w); return }
        val edge = min(66f, w * 0.35f)
        text(clock(first.startMs), left, top + 14, edge, 11f, color = secondary)
        text(clock(last.endMs), left + w - edge, top + 14, edge, 11f, color = secondary)
        if (w >= 260) segments.zipWithNext().firstOrNull { it.second.startMs > it.first.endMs }?.let { (a, b) ->
            text("${clock(a.endMs)}–${clock(b.startMs)}", left + edge + 8, top + 14, w - 2 * edge - 16, 11f, color = secondary, center = true)
        }
    }
    private fun timeline() {
        if (expandedStyle) { timelineExpanded(); return }
        header(mark = 16f, title = t(R.string.widgetSuiteToday))
        dayAxis(16f, 44f, 138f, 109f, 12f)
    }
    private fun timelineExpanded() {
        val pad = min(baseW, baseH).times(0.095f).coerceIn(10f, 20f)
        val tall = baseH >= 250
        brand(pad, pad, 18f); text(t(R.string.widgetSuiteToday), pad + 26, pad + 2, baseW - 2 * pad - 26, 13f, true)
        val short = baseH < 145
        val top = pad + if (short) 28 else 36
        val split = if (tall) baseW >= 300 else baseW >= 250
        if (!split) { dayAxis(pad, top, baseW - 2 * pad, baseH - top - pad, if (tall) 14f else 12f); return }
        val axisWidth = (baseW - 2 * pad) * 0.47f
        val side = pad + axisWidth + 24
        val sideWidth = baseW - side - pad
        rect(side - 12, top, 0.6f, baseH - top - pad, track)
        dayAxis(pad, top, axisWidth, baseH - top - pad, 12f)
        text(label, side, top, sideWidth, 12f, true, secondary, maxLines = 2)
        val timerTop = top + if (short) 18 else 30
        val targetTop = if (short) baseH - pad - 13 else top + 76
        val timerFont = if (short) ((targetTop - timerTop - 6) / 1.45f).coerceAtLeast(14f) else if (tall) 34f else 31f
        timer(side, timerTop, sideWidth, timerFont)
        targetLine(side, targetTop, sideWidth)
        if (tall) {
            text(t(R.string.comingUp), side, top + 116, sideWidth, 11f, true, secondary)
            val available = baseH - pad - (top + 141)
            val limit = (available / 31f).toInt().coerceIn(1, 5)
            upcoming(side, top + 141, sideWidth, limit, true, false, 31f)
        } else if (!short) segmentBar(side, baseH - pad - 6, sideWidth)
    }
    private fun dayAxis(left: Float, top: Float, w: Float, axisH: Float, labelSp: Float) {
        val values = segments.filter { it.durationMs > 0 }; val first = values.firstOrNull(); val last = values.lastOrNull()
        if (first == null || last == null) { text(label, left, top + 18, w, labelSp, true, maxLines = 2); return }
        val span = (last.endMs - first.startMs).coerceAtLeast(1)
        fun y(ms: Long) = top + ((ms - first.startMs).toDouble() / span * axisH).toFloat()
        values.forEach { segment ->
            val y1 = y(segment.startMs); val h = (y(segment.endMs) - y1).coerceAtLeast(3f); rect(left, y1, 6f, h, track, 3f)
            val fill = ((now - segment.startMs).toDouble() / segment.durationMs.coerceAtLeast(1)).coerceIn(0.0, 1.0)
            if (fill > 0) rect(left, y1, 6f, (h * fill).toFloat().coerceAtLeast(3f), accent, 3f)
        }
        data class Mark(val ms: Long, val label: String, val isNow: Boolean = false)
        val marks = mutableListOf(Mark(first.startMs, "${clock(first.startMs)} ${t(R.string.startTime)}"), Mark(last.endMs, "${clock(last.endMs)} ${t(R.string.endTime)}"))
        values.zipWithNext().filter { it.second.startMs > it.first.endMs }.forEach { (a, b) ->
            val gap = if (w >= 200) "${clock(a.endMs)}–${clock(b.startMs)}" else clock(a.endMs)
            marks += Mark((a.endMs + b.startMs) / 2, "$gap ${t(R.string.lunchBreak)}")
        }
        if (now > first.startMs && now < last.endMs) {
            marks.removeAll { kotlin.math.abs(it.ms - now).toDouble() / span < 0.12 }; marks += Mark(now, "${t(R.string.focusBandStateCurrent)} ${clock(now)}", true)
        }
        marks.sortedBy { it.ms }.forEach { mark ->
            text(mark.label, left + 16, (y(mark.ms) - 7).coerceIn(top, max(top, top + axisH - 16)), w - 16, labelSp, mark.isNow, if (mark.isNow) primary else secondary)
            description += mark.label
        }
    }
    private fun detailMedium() {
        brand(16f, 16f, 18f); text(label, 40f, 18f, 132f, 12f, true, phaseColor)
        timer(16f, if (compact) 40f else 58f, 160f, if (compact) 28f else 34f)
        targetLine(16f, if (compact) 77f else 102f, 160f, withPercent = true); segmentBar(16f, baseH - 22, 160f)
        rect(190f, 16f, 0.6f, baseH - 32, track); text(t(R.string.comingUp), 205f, 16f, 143f, 12f, true, secondary)
        upcoming(205f, if (compact) 38f else 43f, 143f, 3, true, false, if (compact) 24f else 29f)
    }
    private fun detailLarge() {
        brand(16f, 16f, 18f); text(label, 40f, 18f, 155f, 12f, true, phaseColor)
        text(Instant.ofEpochMilli(now).atZone(zone).format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "MMM d EEE"), locale)), 218f, 19f, 130f, 11f, color = secondary)
        timer(16f, 55f, 270f, 44f); text(percent, 292f, 76f, 56f, 20f, true, phaseColor)
        text(listOfNotNull(t(R.string.timeLeftCaption), target?.let { clock(it) }).joinToString(" · "), 16f, 109f, 332f, 12f, color = secondary)
        segmentBar(16f, 137f, 332f)
        segments.firstOrNull()?.let { text(clock(it.startMs), 16f, 151f, 60f, 11f, color = secondary) }
        segments.zipWithNext().firstOrNull { it.second.startMs > it.first.endMs }?.let { (a, b) -> text("${clock(a.endMs)}–${clock(b.startMs)} ${t(R.string.lunchBreak)}", 83f, 151f, 198f, 11f, color = secondary, center = true) }
        segments.lastOrNull()?.let { text(clock(it.endMs), 288f, 151f, 60f, 11f, color = secondary) }
        rect(16f, 180f, 332f, 0.6f, track); upcoming(16f, 193f, 332f, 6, false, false, 28f)
    }
    private fun upcoming(left: Float, top: Float, w: Float, limit: Int, compact: Boolean, classic: Boolean, rowHeight: Float) {
        if (items.isEmpty()) { text(t(R.string.widgetOpenToRefresh), left, top, w, 11f, color = secondary, maxLines = 2); return }
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        items.take(limit).forEachIndexed { index, item ->
            val y = top + index * rowHeight; val otherDay = Instant.ofEpochMilli(item.dateMs).atZone(zone).toLocalDate() != today; val whenText = clock(item.dateMs, otherDay)
            icon(itemGlyph(item.kind), left, y + 3, if (classic) 16f else 14f, if (otherDay) secondary else accent)
            if (classic) {
                text(item.title, left + 24, y + 1, w - 93, 12f, true); text(item.detail, left + 24, y + 19, w - 93, 11f, color = secondary)
                text(whenText, left + w - 66, y + 10, 66f, 12f, color = secondary)
                if (index < min(items.size, limit) - 1) rect(left + 24, y + rowHeight - 1, w - 24, 0.5f, track)
            } else {
                val timeW = if (otherDay) min(72f, w * 0.46f) else if (compact) 40f else 42f
                text(whenText, left + 21, y + 3, timeW, if (compact) 12f else 13f, true, if (otherDay) secondary else primary)
                val titleLeft = left + 21 + timeW + 7; val detailW = if (!compact && item.detail.isNotBlank()) 92f else 0f
                text(item.title, titleLeft, y + 3, (w - (titleLeft - left) - detailW).coerceAtLeast(20f), if (compact) 12f else 13f, color = if (otherDay) secondary else primary)
                if (detailW > 0) text(item.detail, left + w - detailW, y + 4, detailW, 11f, color = secondary)
            }
            description += listOf(whenText, item.title, item.detail).filter { it.isNotBlank() }.joinToString(" ")
        }
    }
    private fun empty() {
        header(mark = 20f); text(t(R.string.countdownNotStarted), 16f, baseH / 2 - 12, baseW - 32, 15f, true, maxLines = 2)
        text(t(R.string.widgetOpenToRefresh), 16f, baseH / 2 + 29, baseW - 32, 11f, color = secondary, maxLines = 2)
    }
    private fun phaseGlyph() = when (entry?.phase) { WidgetPhase.BREAK -> "cup"; WidgetPhase.BEFORE -> "sunrise"; WidgetPhase.DONE -> "check"; WidgetPhase.IDLE -> "play"; else -> "briefcase" }
    private fun itemGlyph(kind: String) = when (kind) { "shiftStart" -> "sunrise"; "lunchStart", "focusBreak", "break" -> "cup"; "lunchEnd" -> "back"; "health", "microBreak" -> "walk"; "focus" -> "timer"; "milestone" -> "bell"; "shiftEnd" -> "flag"; else -> "clock" }
    private fun icon(name: String, left: Float, top: Float, size: Float, color: Int) {
        val data = when (name) {
            "briefcase" -> "M3 8H21V19H3ZM8 8V5H16V8M3 13H21"
            "sunrise" -> "M3 19H21M7 19A5 5 0 0 1 17 19M12 4V9M9 6.5L12 4L15 6.5M4.5 12L6 13.2M19.5 12L18 13.2"
            "cup" -> "M4 9H16V13A5 5 0 0 1 11 18H9A5 5 0 0 1 4 13ZM16 10H18A2 2 0 0 1 18 14H16M8 3V6M12 3V6"
            "back" -> "M12 21A9 9 0 1 0 12 3A9 9 0 0 0 12 21ZM8 12H16M13 9L16 12L13 15"
            "walk" -> "M13 3.5A1.5 1.5 0 1 1 13 6.5A1.5 1.5 0 0 1 13 3.5ZM10 21L12.2 15L15 17.6V21M12.2 15L13.2 9.8L10 11L8.2 13.8M13.2 9.8L15.5 12.4L18 12.8"
            "timer" -> "M12 21A8 8 0 1 0 12 5A8 8 0 0 0 12 21ZM12 9V13L14.5 15M9 2H15"
            "bell" -> "M6 16V11A6 6 0 0 1 18 11V16L20 18H4ZM10 21H14"
            "flag" -> "M5 21V4M5 4H18L15.5 8L18 12H5"
            "check" -> "M5 12L10 17L19 7"; "play" -> "M8 5L19 12L8 19Z"
            else -> "M12 21A9 9 0 1 0 12 3A9 9 0 0 0 12 21ZM12 7V12L15 15"
        }
        val path = PathParser.createPathFromPathData(data) ?: return
        canvas.save(); canvas.translate(x(left, size), top); canvas.scale(size / 24, size / 24)
        paint.color = color; paint.style = Paint.Style.STROKE; paint.strokeWidth = 2.2f; paint.strokeCap = Paint.Cap.ROUND; paint.strokeJoin = Paint.Join.ROUND
        canvas.drawPath(path, paint); paint.style = Paint.Style.FILL; canvas.restore()
    }
}

private fun countdownLabel(key: String) = when (key) {
    "widgetRestDay" -> R.string.widgetRestDay; "nextShiftLabelShort" -> R.string.nextShiftLabelShort
    "extendedBreak" -> R.string.extendedBreak; "lunchInProgress" -> R.string.lunchInProgress
    "widgetWorking" -> R.string.widgetWorking; "overtime" -> R.string.overtime
    "offWorkToday" -> R.string.offWorkToday; else -> R.string.countdownNotStarted
}
