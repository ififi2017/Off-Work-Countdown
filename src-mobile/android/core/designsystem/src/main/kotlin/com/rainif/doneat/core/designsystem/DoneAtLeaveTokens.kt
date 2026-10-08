package com.rainif.doneat.core.designsystem

import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.ui.unit.dp

/** Pinned iOS 3.2.1 leave preview geometry and OWCMotion's bounded day cascade. */
object DoneAtLeaveTokens {
    val cellHeight = 44.dp
    val markSize = 12.dp
    val rangeCorner = 10.dp
    val selectionStroke = 1.5.dp
    val swipeThreshold = 44.dp
    val sheetDismissThreshold = 80.dp
    val monthTravel = 8.dp
    val arrivalTravel = 14.dp
    val sheetHandleWidth = 40.dp
    val sheetHandleHeight = 4.dp
    const val sheetMaxFraction = .9f
    const val rangeAlpha = .08f
    const val leaveAlpha = .18f
    const val borderAlpha = .65f
    const val inactiveAlpha = .35f
    const val iconStartScale = .72f
    const val tileStartScale = .86f
    const val horizontalDominance = 1.5f
    const val dayCommitMs = 30L
    const val revealLeadMs = 340L
    const val revealStaggerMs = 60L
    const val maxStaggerIndex = 10
    const val revealMs = 420
    const val navigationMs = 280

    fun delay(index: Int) = index.coerceIn(0, maxStaggerIndex) * revealStaggerMs
    fun <T> fade(reduced: Boolean): FiniteAnimationSpec<T> =
        tween(if (reduced) DoneAtMotion.REDUCED_MS else revealMs)
    fun <T> navigation(reduced: Boolean): FiniteAnimationSpec<T> =
        tween(if (reduced) DoneAtMotion.REDUCED_MS else navigationMs, easing = FastOutSlowInEasing)
    fun <T> reveal(reduced: Boolean): FiniteAnimationSpec<T> =
        if (reduced) snap() else spring(dampingRatio = .76f, stiffness = 220f)
}
