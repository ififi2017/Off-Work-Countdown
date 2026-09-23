package com.rainif.doneat.ui.timer

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalView
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.designsystem.LocalDoneAtStateColors
import kotlin.math.sin
import kotlin.random.Random

private class Piece(val x: Float, val delay: Float, val drift: Float, val spin: Float, val size: Float, val color: Int)

/**
 * The clock-off celebration (iOS `OWCConfettiOverlay`): one short fall of
 * confetti each time [burst] increases, with a confirming haptic. Reduced
 * motion keeps the haptic and skips the fall. Draws nothing at rest and
 * never takes touches.
 */
@Composable
fun ConfettiBurst(burst: Int, modifier: Modifier = Modifier) {
    val view = LocalView.current
    val reduced = LocalDoneAtMotion.current.reduced
    val progress = remember { Animatable(1f) }
    val pieces = remember(burst) {
        val random = Random(burst)
        List(PIECES) { Piece(random.nextFloat(), random.nextFloat() * 0.35f, random.nextFloat() * 2 - 1, random.nextFloat() * 720 - 360, 6 + random.nextFloat() * 6, random.nextInt(4)) }
    }
    LaunchedEffect(burst) {
        if (burst == 0) return@LaunchedEffect
        Haptics.confirm(view)
        if (reduced) return@LaunchedEffect
        progress.snapTo(0f)
        progress.animateTo(1f, tween(DURATION_MS, easing = LinearEasing))
    }
    val palette = listOf(
        MaterialTheme.colorScheme.primary,
        LocalDoneAtStateColors.current.overtimeMeter,
        MaterialTheme.colorScheme.tertiary,
        Color(0xFFFFC34D),
    )
    Canvas(modifier) {
        val t = progress.value
        if (t >= 1f) return@Canvas
        pieces.forEach { p ->
            val local = ((t - p.delay) / (1 - p.delay)).coerceIn(0f, 1f)
            if (local <= 0f) return@forEach
            val y = -20f + local * (size.height + 40f)
            val x = p.x * size.width + sin(local * 6f + p.drift * 3f) * 24f * p.drift
            val alpha = if (local > 0.8f) (1 - local) / 0.2f else 1f
            rotate(p.spin * local, Offset(x, y)) {
                drawRect(palette[p.color].copy(alpha = alpha), Offset(x - p.size / 2, y - p.size / 4), Size(p.size, p.size / 2))
            }
        }
    }
}

private const val PIECES = 70
private const val DURATION_MS = 2_600
