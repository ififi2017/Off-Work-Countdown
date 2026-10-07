package com.rainif.doneat.core.designsystem

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Lifetime invitation motion and vector gift palette, matching iOS OWCMotion. */
object DoneAtOfferTokens {
    const val FLOAT_MS = 2600
    const val PEEK_MS = 900
    const val PEEK_PAUSE_MS = 1800L
    const val REVEAL_MS = 320
    const val FLOAT_FRACTION = .035f
    const val LID_FRACTION = .045f
    val revealDistance = 12.dp
    val toolbarGiftSize = 25.dp
    val invitationGiftSize = 64.dp
    val cardPadding = 20.dp
    val cardTint = .08f
    val cardStroke = .28f
    const val SHOWCASE_TOTAL_MS = 1500
    const val SHOWCASE_MAIN_MS = 900
    const val SHOWCASE_STEP_MS = 600
    val showcaseOffset = 10.dp
    val chartHeight = 96.dp
    val reportMinimumHeight = 236.dp
    val reportTotalSize = 40.sp
    val timelineHeight = 10.dp
    val lifeHeight = 18.dp
    val lifeMarkerWidth = 2.dp
    val timeOffCellHeight = 36.dp
    val timeOffIconSize = 12.dp
    val showcaseEasing = CubicBezierEasing(.23f, 1f, .32f, 1f)
    val orange = Color(0xFFFF7B23)
    val orangeDeep = Color(0xFFF45A1E)
    val seam = Color(0xFFCA3B0A)
    val satin = Color(0xFFFFDFA8)
    val satinBright = Color(0xFFFFF1D8)
    fun <T> reveal(reduced: Boolean) = tween<T>(if (reduced) DoneAtMotion.REDUCED_MS else REVEAL_MS)
    fun <T> float() = tween<T>(FLOAT_MS, easing = FastOutSlowInEasing)
    fun <T> peek() = tween<T>(PEEK_MS, easing = FastOutSlowInEasing)
    fun fraction(progress: Float, delayMs: Int, durationMs: Int = SHOWCASE_MAIN_MS): Float =
        showcaseEasing.transform(((progress * SHOWCASE_TOTAL_MS - delayMs) / durationMs).coerceIn(0f, 1f))
}
