package com.rainif.doneat.ui.records

import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.LayoutDirection
import com.rainif.doneat.core.designsystem.DoneAtMotion
import com.rainif.doneat.core.designsystem.DoneAtReportLayout
import com.rainif.doneat.core.designsystem.DoneAtReportPalette as Palette
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion

/** Static native colour field; no bitmap assets, blur layers or animation-driven recomposition. */
@Composable
internal fun ReportBackdrop(kind: ReportArtKind, energized: Boolean = false) {
    val calm = kind == ReportArtKind.REST || kind == ReportArtKind.AHEAD
    val center = when {
        calm -> Palette.calmField
        kind == ReportArtKind.OVERTIME || energized -> Palette.energy
        kind == ReportArtKind.PAY -> Palette.gold.copy(alpha = .48f)
        else -> Palette.warmField
    }
    Canvas(Modifier.fillMaxSize().clearAndSetSemantics { }) {
        drawRect(Brush.verticalGradient(listOf(Palette.deep, if (calm) Palette.night else Palette.plum, Palette.deep)))
        drawRect(Brush.radialGradient(listOf(center.copy(alpha = if (energized) .96f else .80f), Color.Transparent), center = Offset(size.width * .53f, size.height * .49f), radius = size.height * .49f))
        if (energized) drawRect(Brush.radialGradient(listOf(Palette.hot.copy(alpha = .24f), Color.Transparent), center = Offset(size.width * .52f, size.height * .69f), radius = size.height * .38f))
        drawRect(Brush.radialGradient(listOf((if (calm) Palette.night else Palette.orange).copy(alpha = .9f), Color.Transparent), center = Offset(-size.width * .1f, size.height * .94f), radius = size.height * .43f))
    }
}

/** Read the clock during draw, so frames never rebuild the page, strings or prepared charts. */
@Composable
internal fun ReportProgress(chapter: Int, count: Int, clock: () -> Long) {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    Canvas(Modifier.fillMaxWidth().height(DoneAtReportLayout.progressHeight).clearAndSetSemantics { }) {
        val gap = DoneAtSpacing.xs.toPx()
        val width = (size.width - gap * (count - 1)) / count
        repeat(count) { index ->
            val x = (if (rtl) count - 1 - index else index) * (width + gap)
            val radius = CornerRadius(size.height / 2)
            drawRoundRect(Palette.track, Offset(x, 0f), Size(width, size.height), radius)
            val fraction = when { index < chapter -> 1f; index > chapter -> 0f; else -> (clock().toFloat() / CycleReportPlayer.CHAPTER_MS).coerceIn(0f, 1f) }
            if (fraction > 0) drawRoundRect(Palette.ink, Offset(if (rtl) x + width * (1 - fraction) else x, 0f), Size(width * fraction, size.height), radius)
        }
    }
}

@Composable
internal fun ReportArtwork(chapter: ReportChapter, clock: () -> Long, index: Int, modifier: Modifier, teaser: Boolean = false) {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val motion = LocalDoneAtMotion.current
    val density = LocalDensity.current
    val labelSize = with(density) { DoneAtReportLayout.unitSize.toPx() * .54f }
    val paint = remember { Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER } }
    val peak = remember(chapter.bars) { chapter.bars.maxOfOrNull { it.second }?.coerceAtLeast(1L) ?: 1L }
    Canvas(modifier.clearAndSetSemantics { }) {
        val build = motion.emphasizedDecelerate.transform((clock().toFloat() / DoneAtMotion.REPORT_ART_ENTER_MS).coerceIn(0f, 1f))
        val values = chapter.bars
        if (chapter.artKind == ReportArtKind.PAY) {
            val diameter = minOf(size.width, size.height) * .84f
            val origin = Offset((size.width - diameter) / 2, (size.height - diameter) / 2)
            val width = DoneAtSpacing.m.toPx()
            drawArc(Palette.track, -90f, 360f, false, origin, Size(diameter, diameter), style = Stroke(width, cap = StrokeCap.Round))
            drawArc(Brush.sweepGradient(listOf(Palette.cream, Palette.gold, Palette.orange), center = center), -90f, 360 * build, false, origin, Size(diameter, diameter), style = Stroke(width, cap = StrokeCap.Round))
            paint.color = Palette.muted.toArgb()
            paint.textAlign = Paint.Align.CENTER
            paint.textSize = labelSize
            drawIntoCanvas { it.nativeCanvas.drawText(chapter.centerLabel.orEmpty(), center.x, center.y - labelSize, paint) }
            paint.color = Palette.ink.toArgb()
            paint.textSize = labelSize * 3
            val value = chapter.centerValue.orEmpty()
            if (paint.measureText(value) > diameter * .76f) paint.textSize *= diameter * .76f / paint.measureText(value)
            drawIntoCanvas { it.nativeCanvas.drawText(value, center.x, center.y + paint.textSize * .65f, paint) }
            return@Canvas
        }
        if (values.isEmpty()) return@Canvas
        val count = values.size
        val year = chapter.isYear
        val week = count == 7 && !year
        val isCalendar = chapter.artKind == ReportArtKind.TIME || chapter.artKind == ReportArtKind.REST
        val morph = when {
            year -> 1f
            !isCalendar -> 1f
            chapter.restCalendar || index == 0 -> 0f
            index == 1 -> build
            else -> 1f
        }
        val bottomLabel = if (year || week || !isCalendar) DoneAtSpacing.xl.toPx() else 0f
        val floor = size.height - bottomLabel - DoneAtSpacing.s.toPx()
        val top = DoneAtSpacing.l.toPx()
        val slot = size.width / count
        val barWidth = slot * if (year) .62f else if (week) .64f else .58f
        val cell = minOf(size.width / 7, (floor - top) / ((count + chapter.calendarLeading + 6) / 7))
        val gridWidth = cell * 7
        val gridHeight = cell * ((count + chapter.calendarLeading + 6) / 7)
        val gridX = (size.width - gridWidth) / 2
        val gridY = (floor - gridHeight) / 2
        fun label(value: String, x: Float, y: Float, color: Color, alpha: Float = 1f, available: Float = Float.MAX_VALUE) {
            paint.color = color.toArgb()
            paint.alpha = (alpha * 255).toInt().coerceIn(0, 255)
            paint.textSize = labelSize
            if (paint.measureText(value) > available) paint.textSize *= available / paint.measureText(value)
            drawIntoCanvas { it.nativeCanvas.drawText(value, x, y - (paint.fontMetrics.ascent + paint.fontMetrics.descent) / 2, paint) }
        }
        if (chapter.artKind == ReportArtKind.BASELINE) {
            values.forEachIndexed { i, (description, value) ->
                val y = size.height * (.32f + i * .35f)
                paint.color = Palette.muted.toArgb()
                paint.textAlign = if (rtl) Paint.Align.RIGHT else Paint.Align.LEFT
                paint.textSize = labelSize
                drawIntoCanvas { it.nativeCanvas.drawText(description, if (rtl) size.width else 0f, y - DoneAtSpacing.l.toPx(), paint) }
                val height = DoneAtSpacing.xl.toPx()
                val width = size.width * value.toFloat() / peak * build
                drawRoundRect(Palette.track, Offset(0f, y), Size(size.width, height), CornerRadius(height / 2))
                if (width > 0) drawRoundRect(if (i == 0) Brush.horizontalGradient(listOf(Palette.muted, Palette.muted)) else Brush.horizontalGradient(listOf(Palette.cream, Palette.orange)), Offset(if (rtl) size.width - width else 0f, y), Size(width, height), CornerRadius(height / 2))
            }
            return@Canvas
        }
        paint.textAlign = Paint.Align.CENTER
        values.forEachIndexed { i, (_, value) ->
            val barX = (if (rtl) count - 1 - i else i) * slot + (slot - barWidth) / 2
            val slotIndex = chapter.calendarLeading + i
            val col = slotIndex % 7
            val calendarX = if (week) barX else gridX + (if (rtl) 6 - col else col) * cell + cell * .11f
            val calendarWidth = if (week) barWidth else cell * .78f
            val calendarHeight = if (week) (floor - top) * .74f else calendarWidth
            val calendarY = if (week) floor - calendarHeight else gridY + (slotIndex / 7) * cell + cell * .11f
            val height = if (chapter.artKind == ReportArtKind.AHEAD) (floor - top) * (if (value > 0) .35f else .22f) * build
                else maxOf(barWidth, (floor - top) * value.toFloat() / peak * if (index <= 1 || teaser) 1f else build)
            val x = calendarX + (barX - calendarX) * morph
            val y = calendarY + (floor - height - calendarY) * morph
            val w = calendarWidth + (barWidth - calendarWidth) * morph
            val h = calendarHeight + (height - calendarHeight) * morph
            val longest = chapter.restRange?.contains(i) == true
            val rest = chapter.restIndices.contains(i)
            val accent = when (chapter.artKind) {
                ReportArtKind.REST -> if (longest) Palette.gold else Palette.moon
                ReportArtKind.OVERTIME -> Palette.hot
                ReportArtKind.FOCUS, ReportArtKind.PAY -> Palette.gold
                ReportArtKind.AHEAD -> if (longest) Palette.gold else Palette.moon
                else -> Palette.orange
            }
            val active = if (chapter.restCalendar) rest else value > 0
            val radius = CornerRadius(w / 2)
            when {
                teaser && year -> {
                    val yy = floor - DoneAtSpacing.xl.toPx()
                    drawRoundRect(if (active) Palette.orange else Palette.track, Offset(barX, yy), Size(barWidth, DoneAtSpacing.xxs.toPx()), CornerRadius(DoneAtSpacing.xxs.toPx()))
                }
                active -> {
                    drawRoundRect(Brush.verticalGradient(listOf(Palette.cream, accent), startY = y, endY = y + h), Offset(x, y), Size(w, h), radius)
                    if (chapter.artKind == ReportArtKind.TIME && chapter.overtimeIndices.contains(i)) {
                        val trueShare = chapter.overtimeShares.getOrElse(i) { 0f }
                        val capHeight = h * if (morph < .5f) maxOf(.14f, trueShare) else trueShare
                        drawRoundRect(Brush.verticalGradient(listOf(Palette.orange, Palette.hot), startY = y, endY = y + capHeight), Offset(x, y), Size(w, capHeight), radius)
                    }
                    // A restrained halo stays within the reserved top inset, never clipping a bar's cap.
                    if (longest && chapter.restCalendar) drawRoundRect(Palette.gold.copy(alpha = .22f), Offset(x - DoneAtSpacing.xxs.toPx(), y - DoneAtSpacing.xxs.toPx()), Size(w + DoneAtSpacing.xs.toPx(), h + DoneAtSpacing.xs.toPx()), CornerRadius((w + DoneAtSpacing.xs.toPx()) / 2), style = Stroke(DoneAtSpacing.xxs.toPx()))
                }
                morph < .95f -> drawRoundRect(Palette.ink.copy(alpha = .3f), Offset(x, y), Size(w, h), radius, style = Stroke(DoneAtSpacing.xxs.toPx()))
                chapter.artKind == ReportArtKind.TIME && !year -> drawCircle(Palette.ink.copy(alpha = .24f), barWidth / 2, Offset(barX + barWidth / 2, floor - barWidth / 2), style = Stroke(DoneAtSpacing.xxs.toPx()))
                else -> drawRoundRect(Palette.track, Offset(barX, floor - DoneAtSpacing.xxs.toPx()), Size(barWidth, DoneAtSpacing.xxs.toPx()), CornerRadius(DoneAtSpacing.xxs.toPx()))
            }
            if (!year && morph < .9f && i in chapter.cellLabels.indices) label(chapter.cellLabels[i], x + w / 2, y + h / 2, if (active) Palette.deep else Palette.ink, 1 - morph, w * .8f)
            if (chapter.artKind == ReportArtKind.AHEAD && longest) {
                drawLine(Palette.gold, Offset(barX, floor + DoneAtSpacing.s.toPx()), Offset(barX + barWidth, floor + DoneAtSpacing.s.toPx()), DoneAtSpacing.xxs.toPx(), StrokeCap.Round)
            }
            if (year || week) {
                val axis = chapter.axisLabels.getOrElse(i) { chapter.cellLabels.getOrElse(i) { "" } }
                label(axis, barX + barWidth / 2, size.height - DoneAtSpacing.s.toPx(), Palette.muted, available = slot * .92f)
            }
        }
    }
}
