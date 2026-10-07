package com.rainif.doneat.core.designsystem

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.FiniteAnimationSpec

/** iOS OWCMotion's new journey timings, with a bounded cascade for long calendars. */
object DoneAtOnboardingTokens {
    const val PAGE_MS = 320
    const val CONTINUITY_MS = 500
    const val DISCLOSURE_MS = 300
    const val WELCOME_HAND_MS = 900
    const val WELCOME_STAGGER_MS = 70
    const val DEMO_MS = 2600
    const val STAGE_MS = 4200
    const val DAY_STAGGER_MS = 45
    val welcomeEasing = CubicBezierEasing(.16f, 1f, .3f, 1f)
    fun <T> continuity(reduced: Boolean): FiniteAnimationSpec<T> = if (reduced) snap() else tween(CONTINUITY_MS)
    fun dayDelay(index: Int) = minOf(index, 10) * DAY_STAGGER_MS
}
