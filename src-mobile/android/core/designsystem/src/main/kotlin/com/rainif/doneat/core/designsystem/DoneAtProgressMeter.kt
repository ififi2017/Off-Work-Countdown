package com.rainif.doneat.core.designsystem

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import java.text.NumberFormat
import java.util.Locale

/**
 * Where the progress bubble sits (iOS `OWCProgressMeter`, and the Web
 * `ProgressBar`). The pointer is anchored to the progress position and never
 * moves; the bubble slides around it, hanging at most [allowedOverflow] past
 * the track, and never so far that the pointer leaves its flat edge.
 * Clamping the pointer instead is what once made it miss the mark at 0% and 100%.
 */
object ProgressMeterGeometry {
    data class Placement(val targetX: Float, val bubbleX: Float)

    fun place(trackWidth: Float, percent: Double, bubbleWidth: Float, bubbleHeight: Float, pointerWidth: Float, allowedOverflow: Float): Placement {
        val clamped = percent.coerceIn(0.0, 100.0).toFloat()
        val targetX = trackWidth * clamped / 100f
        val halfBubble = bubbleWidth / 2
        val pointerInset = pointerWidth / 2 + bubbleHeight / 2
        val clampedCentre = targetX.coerceIn(halfBubble - allowedOverflow, maxOf(halfBubble - allowedOverflow, trackWidth - halfBubble + allowedOverflow))
        val maxShift = maxOf(0f, halfBubble - pointerInset)
        val shift = (clampedCentre - targetX).coerceIn(-maxShift, maxShift)
        return Placement(targetX, targetX - halfBubble + shift)
    }

    /** One decimal, in the locale's percent format ("62.4%", "62,4 %", "٪٦٢٫٤"). */
    fun bubbleLabel(percent: Double, locale: Locale): String =
        NumberFormat.getPercentInstance(locale).apply {
            minimumFractionDigits = 1
            maximumFractionDigits = 1
        }.format(percent.coerceIn(0.0, 100.0) / 100)

    /** Whole percent, for the screen reader. */
    fun spokenValue(percent: Double, locale: Locale): String =
        NumberFormat.getPercentInstance(locale).apply { maximumFractionDigits = 0 }.format(percent.coerceIn(0.0, 100.0) / 100)
}

/**
 * The shift progress bar with its floating percentage (iOS `OWCProgressMeter`).
 *
 * - [percent] is 0–100. The fill is the accent; in [overtime] a deeper orange;
 *   while [paused] (lunch) a muted fill with a light sweep, which reduced
 *   motion removes.
 * - The bubble's text is a fixed 13 dp, not scaled with the font setting, as
 *   on iOS: it has to stay inside a bar whose height does not grow. The value
 *   is exposed to TalkBack instead, as a whole percent.
 * - Geometry never animates: the value is recomputed every second.
 * - In right-to-left layouts the bar fills from the right.
 */
@Composable
fun DoneAtProgressMeter(
    percent: Double,
    label: String,
    modifier: Modifier = Modifier,
    overtime: Boolean = false,
    paused: Boolean = false,
    /** Defaults to the app's current locale (its per-app language), not the system's. */
    locale: Locale? = null,
) {
    val numberLocale = locale ?: LocalConfiguration.current.locales[0]
    val scheme = MaterialTheme.colorScheme
    val states = LocalDoneAtStateColors.current
    val reduced = LocalDoneAtMotion.current.reduced
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val density = LocalDensity.current
    val measurer = rememberTextMeasurer()

    val (fill, onFill) = when {
        paused -> scheme.onSurfaceVariant to scheme.surface
        overtime -> states.overtimeMeter to states.onOvertimeMeter
        else -> scheme.primary to scheme.onPrimary
    }
    val track = scheme.surfaceContainerHighest
    val barFill = if (paused) fill.copy(alpha = 0.55f) else fill
    val sweepColor = scheme.surface.copy(alpha = 0.88f)
    val text = ProgressMeterGeometry.bubbleLabel(percent, numberLocale)
    val style = remember(density, onFill) {
        // Fixed size on purpose, like iOS: dp converted to sp so the font setting does not grow it.
        TextStyle(fontSize = with(density) { 13.dp.toSp() }, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum", color = onFill)
    }

    val sweep = if (paused && !reduced) {
        rememberInfiniteTransition(label = "meterSweep").animateFloat(
            initialValue = -1f, targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(1_350, easing = LinearEasing), RepeatMode.Restart),
            label = "meterSweepOffset",
        ).value
    } else {
        null
    }

    Canvas(
        modifier
            .fillMaxWidth()
            .height(BUBBLE_TOP + BAR_HEIGHT)
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = ProgressMeterGeometry.spokenValue(percent, numberLocale)
                progressBarRangeInfo = ProgressBarRangeInfo(percent.coerceIn(0.0, 100.0).toFloat(), 0f..100f)
            },
    ) {
        val barTop = BUBBLE_TOP.toPx()
        val barHeight = BAR_HEIGHT.toPx()
        val radius = CornerRadius(barHeight / 2)
        val measured = measurer.measure(text, style)
        val bubbleHeight = BUBBLE_HEIGHT.toPx()
        val bubbleWidth = maxOf(bubbleHeight + 12.dp.toPx(), measured.size.width + 18.dp.toPx())
        val pointerWidth = POINTER_WIDTH.toPx()
        val place = ProgressMeterGeometry.place(size.width, percent, bubbleWidth, bubbleHeight, pointerWidth, ALLOWED_OVERFLOW.toPx())
        // Mirror every x for right-to-left, so the bar fills from the start edge.
        fun x(value: Float) = if (rtl) size.width - value else value
        val fillWidth = maxOf(8.dp.toPx(), place.targetX)

        drawRoundRect(track, Offset(0f, barTop), Size(size.width, barHeight), radius)
        if (sweep != null) {
            clipRect(0f, barTop, size.width, barTop + barHeight) {
                val bandWidth = size.width * 0.42f
                val left = size.width * sweep + (size.width - bandWidth) / 2
                drawRect(
                    Brush.horizontalGradient(listOf(Color.Transparent, sweepColor, Color.Transparent), startX = left, endX = left + bandWidth),
                    Offset(left, barTop), Size(bandWidth, barHeight),
                )
            }
        }
        drawRoundRect(barFill, Offset(minOf(x(0f), x(fillWidth)), barTop), Size(fillWidth, barHeight), radius)

        // Bubble, then the pointer tucked 0.5 dp under it so the two read as one shape.
        val bubbleLeft = minOf(x(place.bubbleX), x(place.bubbleX + bubbleWidth))
        val bubbleTop = barTop - BUBBLE_GAP.toPx() - bubbleHeight - POINTER_HEIGHT.toPx()
        drawRoundRect(fill, Offset(bubbleLeft, bubbleTop), Size(bubbleWidth, bubbleHeight), CornerRadius(bubbleHeight / 2))
        val pointerTop = bubbleTop + bubbleHeight - 0.5.dp.toPx()
        val tip = x(place.targetX)
        drawPath(
            Path().apply {
                moveTo(tip - pointerWidth / 2, pointerTop)
                lineTo(tip + pointerWidth / 2, pointerTop)
                lineTo(tip, pointerTop + POINTER_HEIGHT.toPx() + 0.5.dp.toPx())
                close()
            },
            fill,
        )
        drawText(
            measured,
            topLeft = Offset(bubbleLeft + (bubbleWidth - measured.size.width) / 2, bubbleTop + (bubbleHeight - measured.size.height) / 2),
        )
    }
}

private val BAR_HEIGHT = 8.dp
private val BUBBLE_HEIGHT = 22.dp
private val POINTER_WIDTH = 12.dp
private val POINTER_HEIGHT = 6.dp
private val BUBBLE_GAP = 1.dp
/** Room above the bar for the bubble and pointer (iOS pads the meter by 27 pt). */
private val BUBBLE_TOP = 29.dp
/** How far the bubble may hang past the track, into the page margin. */
private val ALLOWED_OVERFLOW = 14.dp
