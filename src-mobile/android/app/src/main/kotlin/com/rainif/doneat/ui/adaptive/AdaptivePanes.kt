package com.rainif.doneat.ui.adaptive

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp

/** Measures content, including the rail/status-bar offset, against the window-space hinge. */
@Composable
fun AdaptiveLayoutBox(modifier: Modifier = Modifier, primaryFraction: Float = .5f,
                      content: @Composable BoxScope.(AdaptiveLayoutPlan) -> Unit) {
    val density = LocalDensity.current
    val posture = LocalDoneAtWindowPosture.current
    val windowHeight = LocalWindowInfo.current.containerSize.height / density.density
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val physicalFraction = if (rtl) 1f - primaryFraction else primaryFraction
    var origin by remember { mutableStateOf(Offset.Zero) }
    BoxWithConstraints(modifier.onGloballyPositioned { origin = it.positionInWindow() }.semantics { isTraversalGroup = true }) {
        val viewport = AdaptiveViewport(maxWidth.value, maxHeight.value, density.fontScale,
            heightForExpansionDp = windowHeight, windowOriginXDp = origin.x / density.density,
            windowOriginYDp = origin.y / density.density)
        val plan = remember(viewport, posture, physicalFraction) { AdaptiveLayoutPolicy.resolve(viewport, posture, physicalFraction) }
        content(plan)
    }
}

/** Logical primary is at the reading edge. Bounds stay absolute for the physical hinge. */
@Composable
fun AdaptiveLayoutPlan.readingPane(primary: Boolean): AdaptiveBounds {
    val swaps = kind == AdaptiveLayoutKind.SIDE_BY_SIDE && LocalLayoutDirection.current == LayoutDirection.Rtl
    return if (primary != swaps) this.primary else secondary ?: this.primary
}

@Composable
fun AdaptivePane(bounds: AdaptiveBounds, modifier: Modifier = Modifier, primary: Boolean = true,
                 content: @Composable BoxScope.() -> Unit) {
    Box(modifier.absoluteOffset(bounds.left.dp, bounds.top.dp).width(bounds.width.dp).height(bounds.height.dp)
        .semantics { isTraversalGroup = true; traversalIndex = if (primary) 0f else 1f }, content = content)
}

/** Both panes own a scroll state; the single-column branch can retain its own content and state. */
@Composable
fun AdaptiveTwoPane(
    modifier: Modifier = Modifier,
    primaryFraction: Float = .5f,
    primaryScroll: ScrollState = rememberScrollState(),
    secondaryScroll: ScrollState = rememberScrollState(),
    singleScroll: ScrollState = rememberScrollState(),
    primaryModifier: Modifier = Modifier,
    secondaryModifier: Modifier = Modifier,
    primary: @Composable ColumnScope.() -> Unit,
    secondary: @Composable ColumnScope.() -> Unit,
    single: (@Composable ColumnScope.() -> Unit)? = null,
) {
    AdaptiveLayoutBox(modifier, primaryFraction) { plan ->
        if (plan.secondary != null) {
            AdaptivePane(plan.readingPane(true)) {
                Column(Modifier.fillMaxSize().then(primaryModifier).verticalScroll(primaryScroll), content = primary)
            }
            AdaptivePane(plan.readingPane(false), primary = false) {
                Column(Modifier.fillMaxSize().then(secondaryModifier).verticalScroll(secondaryScroll), content = secondary)
            }
        } else AdaptivePane(plan.primary) {
            Column(Modifier.fillMaxSize().verticalScroll(singleScroll)) {
                if (single != null) single() else { primary(); secondary() }
            }
        }
    }
}
