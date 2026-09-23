package com.rainif.doneat.core.designsystem

import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** A 4 dp grid (plan 01 §7.2). Page margins stay compact; touch targets never shrink below 48 dp. */
object DoneAtSpacing {
    val xxs = 2.dp
    val xs = 4.dp
    val s = 8.dp
    val m = 12.dp
    val l = 16.dp
    val xl = 24.dp
    val xxl = 32.dp
    val page = 16.dp
    val section = 24.dp
    val minTouch = 48.dp
}

/**
 * Corner tokens. Medium matches iOS `OWCDesign.controlRadius` (14) and large its
 * `cardRadius` (22), so a control or a card reads the same on both platforms.
 */
object DoneAtShapes {
    val material = Shapes(
        extraSmall = RoundedCornerShape(4.dp),
        small = RoundedCornerShape(8.dp),
        medium = RoundedCornerShape(14.dp),
        large = RoundedCornerShape(22.dp),
        extraLarge = RoundedCornerShape(28.dp),
    )

    /** The main action at rest is a pill; pressed, it squares toward this radius (the Expressive shape morph). */
    val pressedActionCorner: Dp = 12.dp
    val actionHeight: Dp = 56.dp
}

/**
 * Motion tokens, mirroring iOS `OWCMotion` so the two apps move alike. Spatial
 * changes (position, size, shape) may use a spring with a hint of bounce;
 * effects (colour, opacity) never bounce. Every spec collapses to a short fade
 * or a snap when the system asks for reduced motion.
 */
@Immutable
class DoneAtMotion(val reduced: Boolean) {
    /** `OWCMotion` state panels and records expansion: cubic-bezier(0.23, 1, 0.32, 1). */
    val emphasizedDecelerate = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)

    fun <T> press(): AnimationSpec<T> = if (reduced) snap() else tween(PRESS_MS, easing = FastOutSlowInEasing)
    fun <T> selection(): AnimationSpec<T> = if (reduced) snap() else tween(SELECTION_MS, easing = FastOutSlowInEasing)
    fun <T> stateEnter(): AnimationSpec<T> = if (reduced) tween(REDUCED_MS) else tween(STATE_ENTER_MS, easing = emphasizedDecelerate)
    fun <T> stateExit(): AnimationSpec<T> = if (reduced) tween(REDUCED_MS) else tween(STATE_EXIT_MS, easing = emphasizedDecelerate)
    fun <T> phase(): AnimationSpec<T> = if (reduced) tween(REDUCED_MS) else tween(PHASE_MS, easing = FastOutSlowInEasing)

    /** Shape and position changes; a little bounce, never on colour or opacity. */
    fun <T> spatial(): AnimationSpec<T> =
        if (reduced) snap() else spring(dampingRatio = SPATIAL_DAMPING, stiffness = Spring.StiffnessMediumLow)

    companion object {
        const val REDUCED_MS = 160
        const val PRESS_MS = 140
        const val SELECTION_MS = 180
        const val STATE_EXIT_MS = 100
        const val STATE_ENTER_MS = 180
        const val PHASE_MS = 280
        const val SPATIAL_DAMPING = 0.8f
    }
}

val LocalDoneAtMotion = staticCompositionLocalOf { DoneAtMotion(reduced = false) }

object DoneAtType {
    /** Material's type scale unchanged: sizes scale with the user's font setting. */
    val material = Typography()

    /**
     * The main countdown: tabular figures so the width holds still as digits
     * change, and only the numerals re-lay out each second. 64 sp sits in the
     * 56–72 sp range plan 01 §7.2 asks to test; it scales with the font setting.
     */
    val countdown = TextStyle(
        fontSize = 64.sp,
        lineHeight = 72.sp,
        fontWeight = FontWeight.Medium,
        fontFeatureSettings = "tnum",
        letterSpacing = (-0.5).sp,
    )
}
