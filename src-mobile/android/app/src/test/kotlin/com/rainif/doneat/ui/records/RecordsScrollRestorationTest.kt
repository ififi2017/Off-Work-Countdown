package com.rainif.doneat.ui.records

import androidx.compose.runtime.saveable.SaverScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordsScrollRestorationTest {
    private val gap = 14
    private val inset = 16
    private val single = RecordsScrollGeometry(pickerHeight = 50, chartHeight = 500, conclusionHeight = 800)
    private val columns = RecordsScrollGeometry(chartHeight = 300, conclusionHeight = 400)

    @Test fun movingFromNarrowChartToColumnsAndFoldPreservesThePlaceInTheChart() {
        val position = recordsReadingPosition(RecordsScrollLayout.SINGLE, single,
            singleOffset = 314, chartOffset = 0, conclusionOffset = 0, expandedOffset = 0,
            activePane = RecordsReadingSection.CONCLUSION, gap = gap, expandedInset = inset)
        assertEquals(RecordsReadingSection.CHART, position.section)
        assertEquals(.5f, position.fraction, 0f)
        assertEquals(150, recordsRestoredOffset(position, RecordsScrollLayout.COLUMNS, columns, gap, inset))
        assertEquals(224, recordsRestoredOffset(position, RecordsScrollLayout.FOLD, columns.copy(pickerHeight = 60), gap, inset))
    }

    @Test fun conclusionReadingSurvivesNarrowWideAndBackWithDifferentTextWrapping() {
        val position = recordsReadingPosition(RecordsScrollLayout.SINGLE, single,
            singleOffset = 778, chartOffset = 0, conclusionOffset = 0, expandedOffset = 0,
            activePane = RecordsReadingSection.CHART, gap = gap, expandedInset = inset)
        assertEquals(RecordsReadingSection.CONCLUSION, position.section)
        assertEquals(.25f, position.fraction, 0f)
        val wideOffset = recordsRestoredOffset(position, RecordsScrollLayout.COLUMNS, columns, gap, inset)
        assertEquals(100, wideOffset)
        val back = recordsReadingPosition(RecordsScrollLayout.COLUMNS, columns,
            singleOffset = 0, chartOffset = 80, conclusionOffset = wideOffset, expandedOffset = 0,
            activePane = RecordsReadingSection.CONCLUSION, gap = gap, expandedInset = inset)
        assertEquals(778, recordsRestoredOffset(back, RecordsScrollLayout.SINGLE, single, gap, inset))
        assertEquals(1002, recordsRestoredOffset(back, RecordsScrollLayout.SINGLE,
            single.copy(chartHeight = 600, conclusionHeight = 1296), gap, inset))
    }

    @Test fun lastReadWidePaneDecidesWhereTheSingleColumnResumes() {
        val common = recordsReadingPosition(RecordsScrollLayout.COLUMNS, columns,
            singleOffset = 0, chartOffset = 150, conclusionOffset = 300, expandedOffset = 0,
            activePane = RecordsReadingSection.CHART, gap = gap, expandedInset = inset)
        assertEquals(314, recordsRestoredOffset(common, RecordsScrollLayout.SINGLE, single, gap, inset))
        val summary = recordsReadingPosition(RecordsScrollLayout.COLUMNS, columns,
            singleOffset = 0, chartOffset = 150, conclusionOffset = 300, expandedOffset = 0,
            activePane = RecordsReadingSection.CONCLUSION, gap = gap, expandedInset = inset)
        assertEquals(1178, recordsRestoredOffset(summary, RecordsScrollLayout.SINGLE, single, gap, inset))
    }

    @Test fun topAndTemporaryEmptySectionsNeverProduceNegativeOffsets() {
        val top = recordsReadingPosition(RecordsScrollLayout.SINGLE, RecordsScrollGeometry(),
            0, 0, 0, 0, RecordsReadingSection.CHART, gap, inset)
        assertEquals(0f, top.fraction, 0f)
        assertEquals(0, recordsRestoredOffset(top, RecordsScrollLayout.COLUMNS, RecordsScrollGeometry(), gap, inset))
        val expanded = RecordsReadingPosition(RecordsReadingSection.CHART, .5f)
        assertEquals(166, recordsRestoredOffset(expanded, RecordsScrollLayout.EXPANDED, columns, gap, inset))
    }

    @Test fun activityRecreationRetainsTheSourceLayoutAndReadingGeometry() {
        val original = RecordsScrollRestoration().apply {
            previousLayout = RecordsScrollLayout.COLUMNS
            activePane = RecordsReadingSection.CONCLUSION
            beforeExpansion = RecordsReadingPosition(RecordsReadingSection.CONCLUSION, .25f)
            geometries[RecordsScrollLayout.COLUMNS] = columns
        }
        val scope = object : SaverScope { override fun canBeSaved(value: Any) = true }
        val saved = recordsScrollRestorationSaver.run { scope.save(original) }!!
        val restored = recordsScrollRestorationSaver.restore(saved)!!
        assertEquals(RecordsScrollLayout.COLUMNS, restored.previousLayout)
        assertEquals(RecordsReadingSection.CONCLUSION, restored.activePane)
        assertEquals(RecordsReadingPosition(RecordsReadingSection.CONCLUSION, .25f), restored.beforeExpansion)
        assertEquals(columns, restored.geometries[RecordsScrollLayout.COLUMNS])
        val position = recordsReadingPosition(restored.previousLayout!!, restored.geometries[restored.previousLayout!!]!!,
            0, 0, 100, 0, restored.activePane, gap, inset)
        assertEquals(778, recordsRestoredOffset(position, RecordsScrollLayout.SINGLE, single, gap, inset))
    }

    @Test fun allocationLabelsStackBeforeLargeTextOrNarrowWidthCanRemoveTheTitle() {
        assertTrue(recordsAllocationHeaderStacks(400f, 2f))
        assertTrue(recordsAllocationHeaderStacks(279f, 1f))
        assertTrue(recordsAllocationHeaderStacks(280f, 1.5f))
        assertFalse(recordsAllocationHeaderStacks(320f, 1f))
    }
}
