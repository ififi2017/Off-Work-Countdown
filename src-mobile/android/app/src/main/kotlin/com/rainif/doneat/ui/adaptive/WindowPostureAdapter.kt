package com.rainif.doneat.ui.adaptive

import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import androidx.window.layout.WindowLayoutInfo
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

val LocalDoneAtWindowPosture = staticCompositionLocalOf { WindowPosture() }

/** A lifecycle-aware observer. UI callers provide their actual positionInWindow to the pure policy. */
@Composable
fun rememberWindowPosture(): WindowPosture {
    val activity = LocalActivity.current
    val density = LocalDensity.current.density
    val updates = remember(activity, density) {
        if (activity == null) flowOf(WindowPosture()) else WindowInfoTracker.getOrCreate(activity)
            .windowLayoutInfo(activity)
            .map { it.toDoneAtPosture(density) }
            .catch { emit(WindowPosture()) }
    }
    val posture by updates.collectAsStateWithLifecycle(initialValue = WindowPosture())
    return posture
}

@Composable
fun rememberAdaptiveLayout(viewport: AdaptiveViewport, posture: WindowPosture = LocalDoneAtWindowPosture.current): AdaptiveLayoutPlan =
    remember(viewport, posture) { AdaptiveLayoutPolicy.resolve(viewport, posture) }

/** WindowManager reports px in window coordinates, not the app content's dp or screen coordinates. */
internal fun WindowLayoutInfo.toDoneAtPosture(density: Float): WindowPosture {
    if (!density.isFinite() || density <= 0f) return WindowPosture()
    return WindowPosture(displayFeatures.filterIsInstance<FoldingFeature>().map { feature ->
        val bounds = feature.bounds
        DisplayFold(
            bounds = AdaptiveBounds(bounds.left / density, bounds.top / density, bounds.right / density, bounds.bottom / density),
            axis = if (feature.orientation == FoldingFeature.Orientation.HORIZONTAL) FoldAxis.HORIZONTAL else FoldAxis.VERTICAL,
            isSeparating = feature.isSeparating,
            isHalfOpened = feature.state == FoldingFeature.State.HALF_OPENED,
            occludesContent = feature.occlusionType == FoldingFeature.OcclusionType.FULL,
        )
    })
}
