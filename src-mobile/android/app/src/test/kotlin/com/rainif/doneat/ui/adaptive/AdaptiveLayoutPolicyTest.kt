package com.rainif.doneat.ui.adaptive

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.roundToInt

class AdaptiveLayoutPolicyTest {
    private fun horizontal(top: Float = 380f, bottom: Float = 400f, half: Boolean = true) = DisplayFold(
        AdaptiveBounds(0f, top, 1000f, bottom), FoldAxis.HORIZONTAL, false, half, false)
    private fun vertical(left: Float = 390f, right: Float = 410f) = DisplayFold(
        AdaptiveBounds(left, 0f, right, 1000f), FoldAxis.VERTICAL, true, false, true)
    private fun resolve(w: Float, h: Float, font: Float = 1f, vararg folds: DisplayFold) =
        AdaptiveLayoutPolicy.resolve(AdaptiveViewport(w, h, font), WindowPosture(folds.toList()))

    @Test fun actualWidthAndHeightBothMustFitBeforeContentExpands() {
        assertEquals(AdaptiveLayoutKind.SINGLE_COLUMN, resolve(619f, 900f).kind)
        assertEquals(AdaptiveLayoutKind.SINGLE_COLUMN, resolve(900f, 619f).kind)
        val expanded = resolve(620f, 620f)
        assertTrue(expanded.usesContentColumns)
        assertTrue(expanded.independentScrolls)
        assertEquals(310f, expanded.primary.width, 0f)
        assertEquals(310f, expanded.secondary!!.left, 0f)
        assertFalse(expanded.clockOnlyAuto)
    }

    @Test fun accessibilityTextKeepsOneColumnAtTheExactBoundary() {
        assertTrue(resolve(1000f, 800f, 1.49f).usesContentColumns)
        assertEquals(AdaptiveLayoutKind.SINGLE_COLUMN, resolve(1000f, 800f, 1.5f).kind)
        assertEquals(AdaptiveLayoutKind.SINGLE_COLUMN, resolve(1000f, 800f, 2f).kind)
    }

    @Test fun reservingAHeaderDoesNotCollapseAnExpandedWindow() {
        val plan = AdaptiveLayoutPolicy.resolve(AdaptiveViewport(800f, 540f, heightForExpansionDp = 700f), primaryFraction = .58f)
        assertTrue(plan.usesContentColumns)
        assertEquals(464f, plan.primary.width, .001f)
        assertEquals(336f, plan.secondary!!.width, .001f)
        assertEquals(540f, plan.primary.height, 0f)
        assertFalse(plan.clockOnlyAuto)
    }

    @Test fun aShortContentPaneInsideATallWindowDoesNotBecomeAClock() {
        val plan = AdaptiveLayoutPolicy.resolve(AdaptiveViewport(600f, 350f, heightForExpansionDp = 800f))
        assertEquals(AdaptiveLayoutKind.SINGLE_COLUMN, plan.kind)
        assertFalse(plan.clockOnlyAuto)
    }

    @Test fun tabletopUsesTwoIndependentVerticalPanesAndNeverTheHinge() {
        val plan = resolve(1000f, 800f, 1.6f, horizontal())
        assertTrue(plan.hasHorizontalFold)
        assertFalse(plan.usesContentColumns)
        assertTrue(plan.independentScrolls)
        assertEquals(372f, plan.primary.bottom, 0f)
        assertEquals(408f, plan.secondary!!.top, 0f)
        assertFalse(plan.clockOnlyAuto)
    }

    @Test fun aZeroThicknessFoldStillHasAControlClearance() {
        val plan = resolve(800f, 800f, 1f, horizontal(400f, 400f))
        assertEquals(392f, plan.primary.bottom, 0f)
        assertEquals(408f, plan.secondary!!.top, 0f)
    }

    @Test fun aFlatUnoccludedCreaseDoesNotSplitTheContent() {
        val plan = resolve(800f, 800f, 1f, horizontal(400f, 400f, half = false))
        assertTrue(plan.usesContentColumns)
        assertNull(plan.avoidedFold)
    }

    @Test fun foldCoordinatesAreTranslatedAfterStatusBarsAndNavigationRail() {
        val viewport = AdaptiveViewport(800f, 700f, windowOriginXDp = 80f, windowOriginYDp = 40f)
        val plan = AdaptiveLayoutPolicy.resolve(viewport, WindowPosture(listOf(horizontal())))
        assertEquals(332f, plan.primary.bottom, 0f)
        assertEquals(368f, plan.secondary!!.top, 0f)
    }

    @Test fun aFoldOutsideTheDetailPaneCannotTriggerATabletopLayout() {
        val viewport = AdaptiveViewport(400f, 400f, windowOriginYDp = 450f)
        val plan = AdaptiveLayoutPolicy.resolve(viewport, WindowPosture(listOf(horizontal())))
        assertEquals(AdaptiveLayoutKind.SINGLE_COLUMN, plan.kind)
        assertNull(plan.avoidedFold)
    }

    @Test fun bookPostureAvoidsThePhysicalGapRatherThanSplittingAtTheCentre() {
        val plan = resolve(900f, 900f, 1f, vertical(400f, 430f))
        assertTrue(plan.usesContentColumns)
        assertEquals(392f, plan.primary.right, 0f)
        assertEquals(438f, plan.secondary!!.left, 0f)
    }

    @Test fun largeTextUsesOneSafeBookPane() {
        val plan = resolve(900f, 900f, 1.6f, vertical(400f, 430f))
        assertEquals(AdaptiveLayoutKind.SINGLE_COLUMN, plan.kind)
        assertEquals(438f, plan.primary.left, 0f)
        assertEquals(900f, plan.primary.right, 0f)
        assertNotNull(plan.avoidedFold)
    }

    @Test fun compactLandscapeAutoOnlyAppliesWithoutAnActiveFold() {
        assertTrue(resolve(844f, 390f).clockOnlyAuto)
        assertFalse(resolve(390f, 844f).clockOnlyAuto)
        assertFalse(resolve(900f, 600f).clockOnlyAuto)
        val hinge = DisplayFold(AdaptiveBounds(0f, 190f, 844f, 200f), FoldAxis.HORIZONTAL, true, false, true)
        assertFalse(resolve(844f, 390f, 1f, hinge).clockOnlyAuto)
    }

    @Test fun anOffCentreBookHingeCannotMakeAnUnusableSecondColumn() {
        val plan = resolve(900f, 900f, 1f, vertical(700f, 730f))
        assertEquals(AdaptiveLayoutKind.SINGLE_COLUMN, plan.kind)
        assertEquals(692f, plan.primary.width, 0f)
    }

    @Test fun aHingeAtTheViewportEdgeIsNotAnInteriorDivision() {
        assertNull(resolve(800f, 800f, 1f, horizontal(800f, 800f)).avoidedFold)
        assertNull(resolve(800f, 800f, 1f, vertical(0f, 0f)).avoidedFold)
    }

    @Test fun unboundedOrEmptyMeasurementsDegradeWithoutAPhantomPane() {
        val empty = resolve(Float.POSITIVE_INFINITY, 0f)
        assertEquals(AdaptiveLayoutKind.SINGLE_COLUMN, empty.kind)
        assertEquals(0f, empty.primary.width, 0f)
        assertFalse(empty.clockOnlyAuto)
    }

    @Test fun malformedFoldDataCannotHideContentOrAllocateANegativePane() {
        val reversed = DisplayFold(AdaptiveBounds(500f, 0f, 400f, 1000f), FoldAxis.VERTICAL, true, false, true)
        val invalid = DisplayFold(AdaptiveBounds(0f, Float.NaN, 1000f, 400f), FoldAxis.HORIZONTAL, true, true, true)
        val plan = resolve(800f, 800f, 1f, reversed, invalid)
        assertTrue(plan.usesContentColumns)
        assertNull(plan.avoidedFold)
        assertEquals(800f, plan.primary.width + plan.secondary!!.width, 0f)
    }

    @Test fun aFullWidthPixelFoldSurvivesIndependentDensityConversionAndRailSubtraction() {
        // Real 125 gallery geometry: 1280px / 864dp, 80dp rail becomes 119px.
        // The same full pixel span takes two float paths in WindowManager and Compose.
        val density = 1280f / 864f
        val railPx = (80f * density).roundToInt()
        val width = (1280 - railPx) / density
        val x = railPx / density
        assertEquals(119, railPx)
        assertTrue("strict coverage rejected this one-ULP difference", 864f - x < width)
        assertEquals(-.00006103515625f, (864f - x) - width, .000001f)
        val galleryY = 954f / density
        val viewportY = (954 + 71) / density // an independently pixel-rounded header
        val viewport = AdaptiveViewport(width, (948 - 71) / density, windowOriginXDp = x,
            windowOriginYDp = viewportY, heightForExpansionDp = 640f)
        val fold = DisplayFold(AdaptiveBounds(0f, galleryY + 316f, 864f, galleryY + 324f),
            FoldAxis.HORIZONTAL, true, true, true)
        val plan = AdaptiveLayoutPolicy.resolve(viewport, WindowPosture(listOf(fold)))
        assertTrue(plan.hasHorizontalFold)
        val secondary = requireNotNull(plan.secondary)
        assertEquals(width, plan.primary.width, 0f)
        assertEquals(width, secondary.width, 0f)
        assertTrue(plan.primary.bottom < fold.bounds.top - viewportY)
        assertTrue(secondary.top > fold.bounds.bottom - viewportY)
        assertFalse(plan.clockOnlyAuto)
    }

    @Test fun aFullHeightPixelFoldSurvivesIndependentDensityConversionAndHeaderSubtraction() {
        val density = 1280f / 864f
        val headerPx = (80f * density).roundToInt()
        val height = (1280 - headerPx) / density
        val y = headerPx / density
        assertTrue(864f - y < height)
        val viewport = AdaptiveViewport(900f, height, windowOriginYDp = y)
        val fold = DisplayFold(AdaptiveBounds(400f, 0f, 420f, 864f), FoldAxis.VERTICAL, true, false, true)
        val plan = AdaptiveLayoutPolicy.resolve(viewport, WindowPosture(listOf(fold)))
        assertNotNull(plan.avoidedFold)
        assertEquals(392f, plan.primary.right, 0f)
        assertEquals(428f, plan.secondary!!.left, 0f)
    }

    @Test fun aGenuinelyShorterFoldIsStillNotAFullPaneDivider() {
        val horizontal = DisplayFold(AdaptiveBounds(0f, 390f, 799.99f, 410f), FoldAxis.HORIZONTAL, true, true, true)
        val vertical = DisplayFold(AdaptiveBounds(390f, 0f, 410f, 799.99f), FoldAxis.VERTICAL, true, false, true)
        assertNull(resolve(800f, 800f, 1f, horizontal).avoidedFold)
        assertNull(resolve(800f, 800f, 1f, vertical).avoidedFold)
    }
}
