package com.rainif.doneat.ui.adaptive

/** All coordinates are dp. Folds are in window space; returned panes are local to the content. */
data class AdaptiveBounds(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    val width get() = (right - left).coerceAtLeast(0f)
    val height get() = (bottom - top).coerceAtLeast(0f)
}

enum class FoldAxis { HORIZONTAL, VERTICAL }

data class DisplayFold(
    val bounds: AdaptiveBounds,
    val axis: FoldAxis,
    val isSeparating: Boolean,
    val isHalfOpened: Boolean,
    val occludesContent: Boolean,
) {
    val needsAvoidance get() = isSeparating || isHalfOpened || occludesContent
}

data class WindowPosture(val folds: List<DisplayFold> = emptyList())

data class AdaptiveViewport(
    val widthDp: Float,
    val heightDp: Float,
    val fontScale: Float = 1f,
    val windowOriginXDp: Float = 0f,
    val windowOriginYDp: Float = 0f,
    /** WindowManager supplies the hinge, but not an ergonomic touch margin around it. */
    val foldClearanceDp: Float = AdaptiveLayoutPolicy.FOLD_CLEARANCE_DP,
    /** Root window height remains stable when a page reserves a title or Now band. */
    val heightForExpansionDp: Float = heightDp,
)

enum class AdaptiveLayoutKind { SINGLE_COLUMN, SIDE_BY_SIDE, HORIZONTAL_FOLD }

data class AdaptiveLayoutPlan(
    val kind: AdaptiveLayoutKind,
    val primary: AdaptiveBounds,
    val secondary: AdaptiveBounds? = null,
    val avoidedFold: AdaptiveBounds? = null,
    /** Only a regular phone's compact landscape chooses the clock-only Auto presentation. */
    val clockOnlyAuto: Boolean = false,
) {
    val usesContentColumns get() = kind == AdaptiveLayoutKind.SIDE_BY_SIDE
    val hasHorizontalFold get() = kind == AdaptiveLayoutKind.HORIZONTAL_FOLD
    val independentScrolls get() = secondary != null
}

/** Presentation policy only: changing window shape never changes a timer, selection or navigation stack. */
object AdaptiveLayoutPolicy {
    const val EXPANDED_MINIMUM_DP = 620f
    const val ACCESSIBILITY_FONT_SCALE = 1.5f
    const val COMPACT_HEIGHT_DP = 480f
    const val FOLD_CLEARANCE_DP = 8f
    private const val MINIMUM_PHYSICAL_PANE_DP = 240f

    fun resolve(viewport: AdaptiveViewport, posture: WindowPosture = WindowPosture(), primaryFraction: Float = .5f): AdaptiveLayoutPlan {
        val width = nonNegativeFinite(viewport.widthDp)
        val height = nonNegativeFinite(viewport.heightDp)
        val full = AdaptiveBounds(0f, 0f, width, height)
        val clearance = nonNegativeFinite(viewport.foldClearanceDp)
        val x = if (viewport.windowOriginXDp.isFinite()) viewport.windowOriginXDp else 0f
        val y = if (viewport.windowOriginYDp.isFinite()) viewport.windowOriginYDp else 0f
        var horizontal: AdaptiveBounds? = null
        var vertical: AdaptiveBounds? = null
        for (fold in posture.folds) {
            if (!fold.needsAvoidance) continue
            val b = fold.bounds
            if (!b.left.isFinite() || !b.top.isFinite() || !b.right.isFinite() || !b.bottom.isFinite() || b.right < b.left || b.bottom < b.top) continue
            val local = AdaptiveBounds(b.left - x, b.top - y, b.right - x, b.bottom - y)
            // (windowRightPx / density) - (originPx / density) can round one ULP
            // below (windowRightPx - originPx) / density. Both span the same pixels.
            // Tolerate only float arithmetic at the spanning edges, not the fold's
            // interior position: an outside or genuinely shorter fold stays ignored.
            val horizontalTolerance = coordinateTolerance(b.left, b.right, x, width)
            val verticalTolerance = coordinateTolerance(b.top, b.bottom, y, height)
            if (fold.axis == FoldAxis.HORIZONTAL && horizontal == null && local.left <= horizontalTolerance && local.right >= width - horizontalTolerance && local.top > 0f && local.bottom < height) {
                horizontal = local
            } else if (fold.axis == FoldAxis.VERTICAL && vertical == null && local.top <= verticalTolerance && local.bottom >= height - verticalTolerance && local.left > 0f && local.right < width) {
                vertical = local
            }
        }
        // A tabletop fold stays top/bottom even if the display is wide or text is enlarged.
        if (horizontal != null) {
            val avoided = AdaptiveBounds(0f, (horizontal.top - clearance).coerceAtLeast(0f), width, (horizontal.bottom + clearance).coerceAtMost(height))
            val top = AdaptiveBounds(0f, 0f, width, avoided.top)
            val bottom = AdaptiveBounds(0f, avoided.bottom, width, height)
            if (top.height > 0 && bottom.height > 0) return AdaptiveLayoutPlan(AdaptiveLayoutKind.HORIZONTAL_FOLD, top, bottom, avoided)
            return AdaptiveLayoutPlan(AdaptiveLayoutKind.SINGLE_COLUMN, if (top.height >= bottom.height) top else bottom, avoidedFold = avoided)
        }
        val expandedHeight = nonNegativeFinite(viewport.heightForExpansionDp)
        val expanded = width >= EXPANDED_MINIMUM_DP && expandedHeight >= EXPANDED_MINIMUM_DP &&
            viewport.fontScale.isFinite() && viewport.fontScale < ACCESSIBILITY_FONT_SCALE
        if (vertical != null) {
            val avoided = AdaptiveBounds((vertical.left - clearance).coerceAtLeast(0f), 0f, (vertical.right + clearance).coerceAtMost(width), height)
            val left = AdaptiveBounds(0f, 0f, avoided.left, height)
            val right = AdaptiveBounds(avoided.right, 0f, width, height)
            if (expanded && minOf(left.width, right.width) >= MINIMUM_PHYSICAL_PANE_DP) {
                return AdaptiveLayoutPlan(AdaptiveLayoutKind.SIDE_BY_SIDE, left, right, avoided)
            }
            // Large type must never cross an occluding hinge. Use one physical pane.
            return AdaptiveLayoutPlan(AdaptiveLayoutKind.SINGLE_COLUMN, if (left.width >= right.width) left else right, avoidedFold = avoided)
        }
        if (expanded) {
            val fraction = if (primaryFraction.isFinite()) primaryFraction.coerceIn(.25f, .75f) else .5f
            return AdaptiveLayoutPlan(AdaptiveLayoutKind.SIDE_BY_SIDE,
                AdaptiveBounds(0f, 0f, width * fraction, height), AdaptiveBounds(width * fraction, 0f, width, height))
        }
        return AdaptiveLayoutPlan(AdaptiveLayoutKind.SINGLE_COLUMN, full,
            clockOnlyAuto = width > expandedHeight && expandedHeight > 0f && expandedHeight < COMPACT_HEIGHT_DP)
    }

    private fun nonNegativeFinite(value: Float) = if (value.isFinite()) value.coerceAtLeast(0f) else 0f

    /** A few representable steps cover the division/subtraction path; no fixed physical gap. */
    private fun coordinateTolerance(start: Float, end: Float, origin: Float, extent: Float): Float =
        4f * maxOf(Math.ulp(start), Math.ulp(end), Math.ulp(origin), Math.ulp(extent))
}
