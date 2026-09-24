package com.rainif.doneat.core.designsystem

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The brand's own colours (`assets/brand`, iOS `OWCDesign`); the mark only, never general UI. */
object DoneAtBrand {
    val orange = Color(0xFFF97316)
    val orangeDeep = Color(0xFFEA580C)
    val plum = Color(0xFF2B1935)
    val cream = Color(0xFFFFF1D8)
}

/**
 * The Open Day mark (`assets/brand/off-work-countdown-mark.svg`, iOS
 * `OWCBrandMark`), drawn from the same 1024-unit geometry: a ring broken open
 * at five o'clock, hands at 17:00, and the dot that has left through the
 * break. Only the hands swap colour between light and dark.
 *
 * [handRotation] turns the hands about the centre (the celebration);
 * [showsDepth] adds the quiet halo iOS draws behind the mark on large surfaces.
 */
@Composable
fun DoneAtBrandMark(modifier: Modifier = Modifier, handRotation: Float = 0f, showsDepth: Boolean = false, pressed: Boolean = false) {
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val hands = if (dark) DoneAtBrand.cream else DoneAtBrand.plum
    val halo by animateFloatAsState(if (pressed) 0.20f else if (showsDepth) 0.08f else 0f, LocalDoneAtMotion.current.press(), label = "brandHalo")
    Box(modifier.aspectRatio(1f).clearAndSetSemantics { }) {
        if (halo > 0f) {
            // Geometry fixed; interaction changes only its strength. Blur needs Android 12, and simply sharpens before.
            Canvas(Modifier.fillMaxSize().alpha(halo).blur(12.dp)) { drawRing(this) }
        }
        Canvas(Modifier.fillMaxSize()) {
            drawRing(this)
            val unit = size.minDimension / 1024f
            rotate(handRotation, pivot = center) {
                val path = Path().apply {
                    moveTo(point(512f, 347f, unit).x, point(512f, 347f, unit).y)
                    lineTo(point(512f, 512f, unit).x, point(512f, 512f, unit).y)
                    lineTo(point(573f, 617.7f, unit).x, point(573f, 617.7f, unit).y)
                }
                drawPath(path, hands, style = Stroke(88f * unit, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
            drawCircle(orangeBrush(size), radius = 86f * unit, center = point(664.5f, 776.1f, unit))
        }
    }
}

private fun DrawScope.point(x: Float, y: Float, unit: Float) =
    Offset(center.x + (x - 512f) * unit, center.y + (y - 512f) * unit)

private fun orangeBrush(size: Size) = Brush.linearGradient(listOf(DoneAtBrand.orange, DoneAtBrand.orangeDeep), Offset.Zero, Offset(size.width, size.height))

/** Radius 298 about the centre, a 262° sweep from 109°: the break sits at five o'clock. */
private fun drawRing(scope: DrawScope) = with(scope) {
    val unit = size.minDimension / 1024f
    val radius = 298f * unit
    drawArc(
        orangeBrush(size), startAngle = 109f, sweepAngle = 262f, useCenter = false,
        topLeft = Offset(center.x - radius, center.y - radius), size = Size(radius * 2, radius * 2),
        style = Stroke(110f * unit, cap = StrokeCap.Round),
    )
}

/**
 * One interaction for the brand wherever it appears (iOS
 * `CelebratingBrandMark`): five taps in quick succession, or one with
 * [replaysOnTap], spin the hands twice round over 1.8 s with a detent tick
 * at each sixteenth, then settle with a firmer tap. Reduced motion dims and
 * restores the mark instead. Leaving the screen cancels a turn in progress.
 */
@Composable
fun CelebratingBrandMark(
    label: String,
    modifier: Modifier = Modifier,
    showsDepth: Boolean = false,
    replaysOnTap: Boolean = false,
) {
    val view = LocalView.current
    val reduced = LocalDoneAtMotion.current.reduced
    val scope = rememberCoroutineScope()
    val rotation = remember { Animatable(0f) }
    var pulse by remember { mutableFloatStateOf(1f) }
    var taps by remember { mutableIntStateOf(0) }
    var lastTapMs by remember { mutableLongStateOf(0L) }
    var playing by remember { mutableStateOf<Job?>(null) }
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val pressScale by animateFloatAsState(if (pressed && !reduced) 0.97f else 1f, LocalDoneAtMotion.current.press(), label = "brandPress")

    fun play() {
        if (playing?.isActive == true) return
        playing = scope.launch {
            if (reduced) {
                pulse = 0.8f
                delay(DoneAtMotion.REDUCED_MS.toLong())
                pulse = 1f
            } else {
                val ticks = launch {
                    var elapsed = 0L
                    for (at in BrandCelebration.tickTimesMs) {
                        delay(at - elapsed)
                        elapsed = at
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    }
                }
                rotation.animateTo(rotation.value + BrandCelebration.DEGREES, tween(BrandCelebration.DURATION_MS, easing = BrandCelebration.easing))
                ticks.cancel()
                rotation.snapTo(rotation.value % 360f)
            }
            view.performHapticFeedback(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY,
            )
        }
    }

    DoneAtBrandMark(
        modifier
            .scale(pressScale)
            .alpha(pulse)
            .clip(CircleShape)
            .clickable(interaction, indication = null) {
                if (playing?.isActive == true) return@clickable
                view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                val now = System.currentTimeMillis()
                taps = if (now - lastTapMs > BrandCelebration.TAP_GAP_MS) 1 else taps + 1
                lastTapMs = now
                if (replaysOnTap || taps >= BrandCelebration.TAPS) {
                    taps = 0
                    play()
                }
            }
            .semantics(mergeDescendants = true) {
                contentDescription = label
                role = Role.Image
            },
        handRotation = rotation.value,
        showsDepth = showsDepth,
        pressed = playing?.isActive == true,
    )
}

/** iOS `OWCMotion.brandCelebration*` and `BrandTapSequence`. */
internal object BrandCelebration {
    const val DURATION_MS = 1_800
    const val DEGREES = 720f
    const val TAPS = 5
    const val TAP_GAP_MS = 1_200L

    /** SwiftUI `UnitCurve.easeOut`. */
    val easing = CubicBezierEasing(0f, 0f, 0.58f, 1f)

    /** A tick each time the hands pass a sixteenth of the turn: the curve inverted at 1/16…15/16. */
    val tickTimesMs: List<Long> = (1 until 16).map { step ->
        val target = step / 16f
        var low = 0f
        var high = 1f
        repeat(30) {
            val mid = (low + high) / 2
            if (easing.transform(mid) < target) low = mid else high = mid
        }
        (low * DURATION_MS).toLong()
    }
}
