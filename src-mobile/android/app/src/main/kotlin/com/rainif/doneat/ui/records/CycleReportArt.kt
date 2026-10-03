package com.rainif.doneat.ui.records

import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.rainif.doneat.core.designsystem.DoneAtMotion
import com.rainif.doneat.core.designsystem.DoneAtReportLayout
import com.rainif.doneat.core.designsystem.DoneAtReportPalette as Palette
import com.rainif.doneat.core.designsystem.DoneAtReportMotion as Ease
import kotlin.math.*

/** Colour handover and drift use the playback clock, so pause freezes the entire stage. */
@Composable
internal fun ReportBackdrop(stage: ReportStage, previous: ReportStage? = null, elapsed: () -> Long = { Long.MAX_VALUE }, clock: () -> Long = { 0 }) {
    Canvas(Modifier.fillMaxSize().clearAndSetSemantics { }) {
        val time = clock() / 1_000f
        fun field(kind: ReportStage, opacity: Float) {
            val calm = kind == ReportStage.REST || kind == ReportStage.AHEAD
            val energy = kind == ReportStage.HOURS
            val gold = kind == ReportStage.INCOME
            val middle = when {
                calm -> Palette.calmField
                energy -> Palette.energy
                gold -> Palette.gold.copy(alpha = .48f)
                else -> Palette.warmField
            }
            drawRect(Brush.verticalGradient(listOf(Palette.deep, if (calm) Palette.night else Palette.plum, Palette.deep)), alpha = opacity)
            val driftX = sin(time * .35f + 2) * .10f
            val driftY = sin(time * .35f + 3) * .10f
            drawRect(Brush.radialGradient(listOf(middle.copy(alpha = if (energy) .96f else .80f), Color.Transparent), Offset(size.width * (.5f + driftX), size.height * (.5f + driftY)), size.height * .49f), alpha = opacity)
            drawRect(Brush.radialGradient(listOf((if (calm) Palette.night else if (gold) Palette.gold else Palette.orange).copy(alpha = .9f), Color.Transparent), Offset(-size.width * .1f, size.height * .94f), size.height * .43f), alpha = opacity)
        }
        field(stage, 1f)
        if (previous != null) field(previous, 1 - Ease.outCubic(elapsed().toFloat() / DoneAtMotion.REPORT_BACKDROP_MS))
    }
}

@Composable
internal fun ReportProgress(chapter: Int, timelines: List<ReportTimeline>, clock: () -> Long) {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    Canvas(Modifier.fillMaxWidth().height(DoneAtReportLayout.progressHeight).clearAndSetSemantics { }) {
        val gap = 4.dp.toPx()
        val width = (size.width - gap * (timelines.size - 1)) / timelines.size
        timelines.forEachIndexed { index, timeline ->
            val x = (if (rtl) timelines.lastIndex - index else index) * (width + gap)
            val radius = CornerRadius(size.height / 2)
            drawRoundRect(Palette.track, Offset(x, 0f), Size(width, size.height), radius)
            val p = when { index < chapter -> 1f; index > chapter -> 0f; else -> timeline.progress(clock()) }
            if (p > 0) drawRoundRect(Palette.ink, Offset(if (rtl) x + width * (1 - p) else x, 0f), Size(width * p, size.height), radius)
        }
    }
}

/** Fixed layout, native Canvas. Only drawing reads the frame clock. */
@Composable
internal fun ReportArtwork(chapter: ReportChapter, clock: () -> Long, modifier: Modifier, teaser: Boolean = false, drift: () -> Long = clock) {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val density = LocalDensity.current
    val labelSize = with(density) { 12.dp.toPx() * fontScale.coerceAtMost(1.3f) }
    val paint = remember { Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; typeface = Typeface.create("sans-serif", Typeface.BOLD) } }
    val peak = remember(chapter.bars) { (chapter.bars.maxOfOrNull { it.second } ?: 1L).coerceAtLeast(1L).toFloat() }
    val ranks = remember(chapter.bars.size, chapter.calendarLeading, chapter.isWeek) { chapter.bars.indices.map { if (chapter.isWeek) it else (chapter.calendarLeading + it) % 7 + (chapter.calendarLeading + it) / 7 } }
    val maxRank = remember(ranks) { (ranks.maxOrNull() ?: 1).coerceAtLeast(1) }
    val restOrder = remember(chapter.restIndices) { chapter.restIndices.sorted().withIndex().associate { it.value to it.index } }
    Canvas(modifier.clearAndSetSemantics { }) {
        val b = if (teaser) (clock().toFloat() / DoneAtMotion.REPORT_TEASER_BUILD_MS).coerceIn(0f, 1f) else chapter.timeline.build(clock())
        val time = drift() / 1_000f
        val values = chapter.bars
        fun label(value: String, x: Float, y: Float, color: Color = Palette.muted, alpha: Float = 1f, available: Float = size.width, fontSize: Float = labelSize, align: Paint.Align = Paint.Align.CENTER) {
            paint.textAlign = align
            paint.color = color.toArgb(); paint.alpha = (color.alpha * alpha * 255).toInt().coerceIn(0, 255)
            paint.textSize = fontSize
            if (paint.measureText(value) > available) paint.textSize *= available / paint.measureText(value)
            drawIntoCanvas { it.nativeCanvas.drawText(value, x, y - (paint.fontMetrics.ascent + paint.fontMetrics.descent) / 2, paint) }
        }
        fun pill(rect: ReportRect, colors: List<Color>, alpha: Float = 1f) {
            if (rect.width <= 0 || rect.height <= 0) return
            drawRoundRect(Brush.verticalGradient(colors, rect.y, rect.y + rect.height), Offset(rect.x, rect.y), Size(rect.width, rect.height), CornerRadius(min(rect.width, rect.height) / 2), alpha = alpha.coerceIn(0f, 1f))
        }
        fun glow(rect: ReportRect, color: Color, strength: Float) {
            if (strength <= 0) return
            val radius = max(rect.width, rect.height) * .5f + 16.dp.toPx()
            drawCircle(Brush.radialGradient(listOf(color.copy(alpha = .24f * strength), Color.Transparent), Offset(rect.centerX, rect.centerY), radius), radius, Offset(rect.centerX, rect.centerY))
        }
        if (chapter.stage == ReportStage.INCOME) {
            val diameter = min(size.width, size.height) * .90f
            val origin = Offset((size.width - diameter) / 2, (size.height - diameter) / 2)
            val width = 12.dp.toPx()
            val grow = Ease.outCubic(Ease.window(b, .05f, .9f))
            val sweep = 324 * grow
            val regular = sweep * (1 - chapter.incomeShare)
            drawArc(Palette.track.copy(alpha = .08f), -108f, 360f, false, origin, Size(diameter, diameter), style = Stroke(width, cap = StrokeCap.Round))
            if (regular > 0) drawArc(Brush.sweepGradient(listOf(Palette.gold.copy(alpha = .4f), Palette.cream, Palette.gold), center), -94f, regular, false, origin, Size(diameter, diameter), style = Stroke(width, cap = StrokeCap.Round))
            if (chapter.incomeShare > .001f) drawArc(Brush.verticalGradient(listOf(Palette.orange, Palette.hot)), -94f + regular, sweep - regular, false, origin, Size(diameter, diameter), style = Stroke(width, cap = StrokeCap.Round))
            label(chapter.centerLabel.orEmpty(), center.x, center.y - labelSize * 1.7f, available = diameter * .70f)
            label(chapter.countedMetric?.invoke(grow) ?: chapter.centerValue.orEmpty(), center.x, center.y + labelSize * 1.5f, Palette.ink, available = diameter * .70f, fontSize = labelSize * 4)
            return@Canvas
        }
        if (chapter.stage == ReportStage.AHEAD && values.isEmpty()) {
            chapter.leaveShare?.let { share ->
                val height = 26.dp.toPx()
                val width = size.width * share.coerceIn(0f, 1f) * Ease.outCubic(Ease.window(b, .1f, .8f))
                pill(ReportRect(0f, center.y, size.width, height), listOf(Palette.control, Palette.control))
                pill(ReportRect(if (rtl) size.width - width else 0f, center.y, width, height), listOf(Palette.cream, Palette.moon))
            }
            return@Canvas
        }
        if (values.isEmpty()) return@Canvas
        val count = values.size
        if (chapter.stage == ReportStage.BASELINE) {
            val grow = Ease.outCubic(Ease.window(b, .12f, .78f))
            values.forEachIndexed { i, (description, value) ->
                val y = size.height * (.32f + i * .35f)
                label(description, if (rtl) size.width else 0f, y - 22.dp.toPx(), available = size.width, align = if (rtl) Paint.Align.RIGHT else Paint.Align.LEFT)
                val width = size.width * value / peak * grow
                pill(ReportRect(0f, y, size.width, 22.dp.toPx()), listOf(Palette.control, Palette.control))
                pill(ReportRect(if (rtl) size.width - width else 0f, y, width, 22.dp.toPx()), if (i == 0) listOf(Palette.muted, Palette.muted) else listOf(Palette.cream, Palette.orange))
            }
            return@Canvas
        }
        if (chapter.stage == ReportStage.SUMMARY && !chapter.isWeek && !chapter.isYear) {
            val outer = min(size.width, size.height) / 2 - 8.dp.toPx()
            val inner = outer * .58f
            val spoke = min(14.dp.toPx(), 2 * PI.toFloat() * inner / count * .56f).coerceAtLeast(3.dp.toPx())
            val reach = outer - inner - 6.dp.toPx() - spoke / 2
            drawCircle(Palette.track, inner - 2.dp.toPx(), center, style = Stroke(1.dp.toPx()))
            values.forEachIndexed { i, (_, value) ->
                val grow = Ease.outBack(Ease.stagger(Ease.window(b, 0f, .9f), i, count, .45f), 1.2f).coerceAtLeast(0f)
                val angle = -PI / 2 + (i + .5) / count * 2 * PI
                fun point(r: Float) = center + Offset(cos(angle).toFloat() * r, sin(angle).toFloat() * r)
                if (grow <= 0) return@forEachIndexed
                drawLine(Palette.control, point(inner), point(inner + reach), spoke, StrokeCap.Round, alpha = grow.coerceAtMost(1f))
                when {
                    i in chapter.upcomingIndices -> drawCircle(Palette.track, spoke / 2, point(inner + spoke / 2), style = Stroke(1.dp.toPx()))
                    i in chapter.restIndices -> drawCircle(Palette.moon.copy(alpha = .75f), spoke / 2, point(inner + spoke / 2))
                    value > 0 -> {
                        val length = max(spoke, value / peak * reach) * grow
                        val regular = length * (1 - chapter.overtimeShares.getOrElse(i) { 0f })
                        drawLine(Brush.linearGradient(listOf(Palette.cream, Palette.orange), point(inner), point(inner + length)), point(inner), point(inner + regular), spoke, StrokeCap.Round)
                        if (length > regular) drawLine(Palette.hot, point(inner + regular), point(inner + length), spoke, StrokeCap.Round)
                    }
                }
            }
            val reveal = Ease.window(b, .3f, .7f)
            label(chapter.centerValue.orEmpty(), center.x, center.y - labelSize * .5f, Palette.ink, reveal, inner * 1.5f, labelSize * 2.5f)
            label(chapter.centerLabel.orEmpty(), center.x, center.y + labelSize * 1.7f, alpha = reveal, available = inner * 1.5f)
            return@Canvas
        }
        val strip = !chapter.isYear && (chapter.stage in listOf(ReportStage.CALENDAR, ReportStage.HOURS, ReportStage.REST) || chapter.stage == ReportStage.SUMMARY && chapter.isWeek)
        val slot = size.width / count
        val labelBand = if (chapter.isWeek && strip) 44.dp.toPx() else if (chapter.axisLabels.isNotEmpty()) 26.dp.toPx() else 0f
        val floor = size.height - labelBand - 4.dp.toPx()
        val top = 24.dp.toPx()
        val barWidth = if (strip) { if (chapter.isWeek) min(slot * .66f, 46.dp.toPx()) else max(4.dp.toPx(), slot * .58f) }
            else min(if (chapter.stage == ReportStage.FOCUS) 40.dp.toPx() else 24.dp.toPx(), slot * .62f)
        val cell = size.width / 7
        val rows = (count + chapter.calendarLeading + 6) / 7
        val gridY = max(0f, (size.height - rows * cell) / 2)
        values.forEachIndexed { i, (_, value) ->
            val barX = (if (rtl) count - 1 - i else i) * slot + (slot - barWidth) / 2
            val s = chapter.calendarLeading + i
            val calendarWidth = if (chapter.isWeek) barWidth else min(cell * .78f, 42.dp.toPx())
            val calendarHeight = if (chapter.isWeek) min(floor, max(168.dp.toPx(), floor * .74f)) else calendarWidth
            val calendar = ReportRect(if (chapter.isWeek) barX else (if (rtl) 6 - s % 7 else s % 7) * cell + (cell - calendarWidth) / 2,
                if (chapter.isWeek) floor - calendarHeight else gridY + s / 7 * cell + (cell - calendarWidth) / 2, calendarWidth, calendarHeight)
            val rest = i in chapter.restIndices
            val future = i in chapter.upcomingIndices
            val bar = ReportRect(barX, floor - max(barWidth, (floor - top) * value / peak), barWidth, max(barWidth, (floor - top) * value / peak))
            val reveal = when {
                teaser || chapter.stage == ReportStage.CALENDAR -> Ease.stagger(b, ranks[i], maxRank + 1, .42f)
                chapter.stage == ReportStage.SUMMARY && strip -> Ease.stagger(Ease.window(b, 0f, .9f), i, count, .7f)
                else -> 1f
            }
            val morph = when (chapter.stage) {
                ReportStage.CALENDAR -> 0f
                ReportStage.HOURS -> if (chapter.isWeek) Ease.inOutCubic(Ease.stagger(Ease.window(b, .05f, 1f), i, count, .88f)) else Ease.window(b, .04f, 1f)
                ReportStage.REST -> 1 - Ease.inOutCubic(Ease.window(b, 0f, .32f))
                else -> 1f
            }
            val lit = if (chapter.stage == ReportStage.REST && rest) Ease.outCubic(Ease.stagger(Ease.window(b, .34f, .86f), restOrder[i] ?: 0, restOrder.size, .5f)) else 0f
            val emphasis = if (chapter.stage == ReportStage.REST && chapter.restRange?.contains(i) == true && chapter.restRange.count() > 1) Ease.stagger(Ease.outCubic(Ease.window(b, .84f, 1f)), i - chapter.restRange.first, chapter.restRange.count(), .8f) else 0f
            val dim = if (chapter.stage == ReportStage.REST) Ease.inOutCubic(Ease.window(b, .28f, .55f)) else 0f
            val alpha = min(1f, reveal * 1.8f) * if (!rest && !future) 1 - .8f * dim else 1f
            val grow = Ease.outCubic(Ease.window(b, i.toFloat() / max(1, count - 1) * .18f, .82f + i.toFloat() / max(1, count - 1) * .18f))
            val rect = if (strip) reportStripFrame(calendar, bar, floor, morph, reveal, i, count, chapter.isWeek, 26.dp.toPx())
                else {
                    val h = if (chapter.stage == ReportStage.AHEAD) size.height * (if (value > 0) .46f else .3f) * Ease.outBack(Ease.stagger(Ease.window(b, 0f, .8f), i, count, .35f), 1.2f).coerceAtLeast(0f)
                        else max(3.dp.toPx(), (floor - top) * value / peak * grow)
                    ReportRect(barX, floor - h, barWidth, h)
                }
            if (alpha <= 0 || rect.height <= 0) return@forEachIndexed
            val accent = when (chapter.stage) {
                ReportStage.OVERTIME -> Palette.hot
                ReportStage.FOCUS -> if (chapter.isYear || i == chapter.highlightedIndex) Palette.gold else Palette.muted
                ReportStage.REST -> Palette.moon
                ReportStage.AHEAD -> if (chapter.restRange?.contains(i) == true) Palette.gold else Palette.moon.copy(alpha = .55f)
                else -> Palette.orange
            }
            if (strip) {
                when {
                    future -> drawRoundRect(Palette.ink.copy(alpha = .28f * alpha), Offset(rect.x, rect.y), Size(rect.width, rect.height), CornerRadius(rect.width / 2), style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 4.dp.toPx()))))
                    rest -> {
                        glow(rect, Palette.moon, lit * (1 + .06f * sin(time * 2.2f + i)))
                        pill(rect, listOf(Palette.control, Palette.control), alpha)
                        if (lit > 0) pill(rect, listOf(Palette.cream, Palette.moon), alpha * lit)
                        if (emphasis > 0) pill(rect, listOf(Palette.cream, Palette.restWarm), alpha * emphasis)
                        drawRoundRect(Palette.ink.copy(alpha = .3f * alpha * (1 - lit)), Offset(rect.x, rect.y), Size(rect.width, rect.height), CornerRadius(rect.width / 2), style = Stroke(1.5.dp.toPx()))
                    }
                    value > 0 -> {
                        pill(rect, listOf(Palette.cream, Palette.orange), alpha)
                        val share = chapter.overtimeShares.getOrElse(i) { 0f }
                        if (share > 0) {
                            val path = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height, CornerRadius(rect.width / 2))) }
                            clipPath(path) { drawRect(Brush.verticalGradient(listOf(Palette.orange, Palette.hot), rect.y, rect.y + rect.height * share), Offset(rect.x, rect.y), Size(rect.width, rect.height * share), alpha = alpha) }
                        }
                    }
                }
                if (!chapter.isWeek && morph < .12f) label(chapter.cellLabels.getOrElse(i) { "" }, rect.centerX, rect.centerY,
                    if (!rest && !future) Palette.deep else lerp(Palette.ink, Palette.deep, lit), alpha * (1 - Ease.window(morph, 0f, .12f)), rect.width * .85f)
                if (chapter.isWeek) {
                    label(chapter.axisLabels.getOrElse(i) { "" }, barX + barWidth / 2, floor + 16.dp.toPx(), alpha = alpha, available = slot * .92f)
                    label(chapter.cellLabels.getOrElse(i) { "" }, barX + barWidth / 2, floor + 34.dp.toPx(), Palette.ink, alpha, slot * .92f)
                    if (chapter.stage == ReportStage.HOURS && value > 0) label(chapter.valueLabels.getOrElse(i) { "" }, rect.centerX, rect.y - 12.dp.toPx(), Palette.ink, Ease.window(b, .86f, 1f), slot * .92f)
                }
            } else {
                val selected = chapter.stage == ReportStage.AHEAD && chapter.restRange?.contains(i) == true
                val light = if (selected) Ease.outCubic(Ease.window(b, .72f, 1f)) else 0f
                if (chapter.highlightedIndex == i || selected) glow(rect, Palette.gold, if (selected) light else grow)
                pill(rect, if (value > 0) listOf(Palette.cream, accent) else listOf(Palette.track, Palette.track))
                if (selected) pill(rect, listOf(Palette.cream, Palette.gold), light)
                label(chapter.axisLabels.getOrElse(i) { "" }, barX + barWidth / 2, size.height - 8.dp.toPx(), available = slot * .92f)
                if (chapter.stage == ReportStage.FOCUS && !chapter.isYear && value > 0 && slot > 18.dp.toPx()) label(chapter.valueLabels.getOrElse(i) { "" }, rect.centerX, rect.y - 12.dp.toPx(), Palette.ink, grow, slot * .92f)
            }
        }
    }
}
