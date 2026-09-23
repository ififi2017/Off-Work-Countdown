package com.rainif.doneat.ui.timer

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalView
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sin

/**
 * The clock-off celebration, a port of iOS `OWCConfettiOverlay` with the same
 * particles, physics and palette: two corner cannons open, a centre pop
 * follows, then a curtain falls across the whole width for five seconds.
 * Flakes shed their launch speed to drag, fall under gravity, flutter and
 * flip (narrowing edge-on, paler on the back). Sizes and speeds are iOS
 * points, drawn here in dp.
 *
 * A new [burst] starts it with the paced haptics iOS plays alongside; reduced
 * motion keeps the haptics and skips the fall. It never takes touches.
 */
@Composable
fun ConfettiBurst(burst: Int, modifier: Modifier = Modifier) {
    val view = LocalView.current
    val reduced = LocalDoneAtMotion.current.reduced
    var flakes by remember { mutableStateOf(emptyList<Flake>()) }
    var elapsedNanos by remember { mutableLongStateOf(0L) }

    LaunchedEffect(burst) {
        if (burst == 0) return@LaunchedEffect
        coroutineScope {
            launch { playCelebrationHaptics(view) }
            if (reduced) return@coroutineScope
            flakes = makeFlakes(burst)
            elapsedNanos = 0L
            val start = withFrameNanos { it }
            while (elapsedNanos / 1e9 <= LIFE + 0.2) {
                elapsedNanos = withFrameNanos { it } - start
            }
            flakes = emptyList()
        }
    }

    Canvas(modifier) {
        if (flakes.isEmpty()) return@Canvas
        val elapsed = elapsedNanos / 1e9
        val unit = density
        for (f in flakes) {
            val t = elapsed - f.delay
            if (t <= 0 || t >= f.life) continue
            // Drag bleeds the launch impulse away: outward, slowing, then falling.
            val drag = (1 - exp(-t * f.drag)) / f.drag
            val x = f.originX * size.width + (f.velocityX * drag + sin(t * f.flutterRate + f.tilt) * f.flutter) * unit
            val y = f.originY * size.height + (f.velocityY * drag + 0.5 * GRAVITY * t * t * f.weight) * unit
            if (y > size.height + 40 * unit) continue
            val progress = t / f.life
            // Full strength for most of the flight, then fade.
            val fade = if (progress < 0.72) 1.0 else max(0.0, 1 - (progress - 0.72) / 0.28)
            val flip = cos(f.spinPhase + t * f.spin)
            val width = (f.width * max(0.16, abs(flip)) * unit).toFloat()
            val height = (f.height * unit).toFloat()
            val face = if (flip < 0) 0.55f else 1f
            val color = PALETTE[f.color].copy(alpha = face * fade.toFloat())
            translate(x.toFloat(), y.toFloat()) {
                rotate(Math.toDegrees(f.tilt + t * f.spin * 0.35).toFloat(), pivot = Offset.Zero) {
                    val topLeft = Offset(-width / 2, -height / 2)
                    when (f.kind) {
                        Kind.STRIP -> drawRoundRect(color, topLeft, Size(width, height), CornerRadius(unit))
                        Kind.RIBBON -> drawRoundRect(color, topLeft, Size(width, height), CornerRadius(width / 2))
                        Kind.DOT -> drawOval(color, topLeft, Size(width, height))
                    }
                }
            }
        }
    }
}

/**
 * Paced against the fall rather than fired at once: the cannons land as a
 * firm hit, the centre pop follows, then two soft taps under the curtain.
 * Restrained on purpose; a buzz per beat reads as an alarm.
 */
private suspend fun playCelebrationHaptics(view: View) {
    Haptics.confirm(view)
    delay(90)
    view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    delay(160)
    Haptics.confirm(view)
    for (gap in longArrayOf(1_150, 1_500)) {
        delay(gap)
        view.performHapticFeedback(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) HapticFeedbackConstants.SEGMENT_FREQUENT_TICK else HapticFeedbackConstants.CLOCK_TICK,
        )
    }
}

private enum class Kind { STRIP, DOT, RIBBON }

private class Flake(
    val originX: Double, val originY: Double,
    val velocityX: Double, val velocityY: Double,
    val width: Double, val height: Double,
    val color: Int, val kind: Kind,
    val spin: Double, val spinPhase: Double, val tilt: Double,
    val flutter: Double, val flutterRate: Double,
    val drag: Double, val weight: Double,
    val delay: Double, val life: Double,
)

private const val LIFE = 5.0
private const val GRAVITY = 980.0

/** iOS's confetti palette: the brand orange, amber, white, coral, teal and lavender. */
private val PALETTE = listOf(
    Color(0.976f, 0.451f, 0.086f),
    Color(0.98f, 0.75f, 0.18f),
    Color.White,
    Color(0.99f, 0.42f, 0.44f),
    Color(0.30f, 0.78f, 0.78f),
    Color(0.62f, 0.55f, 0.98f),
)

private class Cannon(
    val originX: ClosedFloatingPointRange<Double>, val originY: Double,
    val aim: Double, val spread: Double, val count: Int,
    val delay: ClosedFloatingPointRange<Double>,
    val speed: ClosedFloatingPointRange<Double>,
    val weight: ClosedFloatingPointRange<Double>,
)

private val CANNONS = listOf(
    // Lower corners, firing inward and up.
    Cannon(-0.02..-0.02, 1.02, -PI / 3.1, 0.44, 44, 0.0..0.06, 950.0..1420.0, 0.75..1.1),
    Cannon(1.02..1.02, 1.02, -PI + PI / 3.1, 0.44, 44, 0.03..0.09, 950.0..1420.0, 0.75..1.1),
    // Centre pop, so the middle of the screen is not empty.
    Cannon(0.42..0.58, 0.44, -PI / 2, PI, 30, 0.22..0.34, 380.0..820.0, 0.7..1.0),
    // The curtain: staggered across the full width and most of the run, drifting.
    Cannon(0.0..1.0, -0.06, PI / 2, 0.5, 72, 0.15..2.9, 60.0..190.0, 0.5..0.9),
)

private fun makeFlakes(seed: Int): List<Flake> {
    val rng = SeededGenerator((seed.toLong() * 7919 + 13).toULong())
    val result = ArrayList<Flake>()
    for (c in CANNONS) {
        repeat(c.count) {
            val angle = c.aim + rng.double(-c.spread..c.spread)
            val speed = rng.double(c.speed)
            val roll = rng.double(0.0..1.0)
            val kind = when {
                roll < 0.62 -> Kind.STRIP
                roll < 0.84 -> Kind.RIBBON
                else -> Kind.DOT
            }
            val width = if (kind == Kind.DOT) rng.double(5.0..8.0) else rng.double(6.0..10.0)
            val height = when (kind) {
                Kind.STRIP -> rng.double(9.0..16.0)
                Kind.RIBBON -> rng.double(3.0..5.0)
                Kind.DOT -> width
            }
            val delay = rng.double(c.delay)
            result += Flake(
                originX = rng.double(c.originX), originY = c.originY,
                velocityX = cos(angle) * speed, velocityY = sin(angle) * speed,
                width = width, height = height,
                color = (rng.next() % PALETTE.size.toULong()).toInt(), kind = kind,
                spin = rng.double(5.0..15.0) * (if (rng.bool()) 1 else -1),
                spinPhase = rng.double(0.0..2 * PI), tilt = rng.double(0.0..2 * PI),
                flutter = rng.double(8.0..26.0), flutterRate = rng.double(3.0..8.0),
                drag = rng.double(2.4..3.6), weight = rng.double(c.weight),
                delay = delay,
                // Everything has time to cross the screen; nothing freezes mid-air.
                life = max(1.6, LIFE - delay - rng.double(0.0..0.4)),
            )
        }
    }
    return result
}

/** iOS `SeededGenerator` (xorshift): a replay of one burst looks identical, two bursts do not. */
private class SeededGenerator(seed: ULong) {
    private var state = seed * 6_364_136_223_846_793_005uL + 1uL

    fun next(): ULong {
        state = state xor (state shl 13)
        state = state xor (state shr 7)
        state = state xor (state shl 17)
        return state
    }

    fun double(range: ClosedFloatingPointRange<Double>): Double {
        val unit = (next() % 1_000_000uL).toDouble() / 1_000_000
        return range.start + unit * (range.endInclusive - range.start)
    }

    fun bool() = next() % 2uL == 0uL
}
