package com.rainif.doneat.ui.records

import androidx.compose.foundation.ScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.collect
import kotlin.math.roundToInt

internal enum class RecordsScrollLayout { SINGLE, COLUMNS, FOLD, EXPANDED }
internal enum class RecordsReadingSection { CHART, CONCLUSION }
internal data class RecordsReadingPosition(val section: RecordsReadingSection, val fraction: Float)

/** Heights come from the rendered sections, so wrapping text never changes which section is being read. */
internal data class RecordsScrollGeometry(val pickerHeight: Int = 0, val chartHeight: Int = 0, val conclusionHeight: Int = 0) {
    fun chartStart(layout: RecordsScrollLayout, gap: Int, expandedInset: Int): Int = when (layout) {
        RecordsScrollLayout.SINGLE, RecordsScrollLayout.FOLD -> pickerHeight + gap
        RecordsScrollLayout.EXPANDED -> expandedInset
        RecordsScrollLayout.COLUMNS -> 0
    }
    fun conclusionStart(gap: Int) = pickerHeight + gap + chartHeight + gap
}

internal fun recordsReadingPosition(layout: RecordsScrollLayout, geometry: RecordsScrollGeometry, singleOffset: Int,
    chartOffset: Int, conclusionOffset: Int, expandedOffset: Int, activePane: RecordsReadingSection, gap: Int, expandedInset: Int,
): RecordsReadingPosition {
    val section = when (layout) {
        RecordsScrollLayout.SINGLE -> if (singleOffset >= geometry.conclusionStart(gap)) RecordsReadingSection.CONCLUSION else RecordsReadingSection.CHART
        RecordsScrollLayout.EXPANDED -> RecordsReadingSection.CHART
        else -> activePane
    }
    val offset = if (section == RecordsReadingSection.CONCLUSION) {
        if (layout == RecordsScrollLayout.SINGLE) singleOffset - geometry.conclusionStart(gap) else conclusionOffset
    } else when (layout) {
        RecordsScrollLayout.SINGLE -> singleOffset - geometry.chartStart(layout, gap, expandedInset)
        RecordsScrollLayout.EXPANDED -> expandedOffset - expandedInset
        else -> chartOffset - geometry.chartStart(layout, gap, expandedInset)
    }
    val height = if (section == RecordsReadingSection.CHART) geometry.chartHeight else geometry.conclusionHeight
    return RecordsReadingPosition(section, if (height > 0) (offset.toFloat() / height).coerceIn(0f, 1f) else 0f)
}

/** Convert the same place within a section to its new, reflowed height. ScrollState supplies the final clamp. */
internal fun recordsRestoredOffset(position: RecordsReadingPosition, layout: RecordsScrollLayout, geometry: RecordsScrollGeometry,
    gap: Int, expandedInset: Int,
): Int {
    val section = if (layout == RecordsScrollLayout.EXPANDED) RecordsReadingSection.CHART else position.section
    val start = when {
        section == RecordsReadingSection.CONCLUSION && layout == RecordsScrollLayout.SINGLE -> geometry.conclusionStart(gap)
        section == RecordsReadingSection.CONCLUSION -> 0
        else -> geometry.chartStart(layout, gap, expandedInset)
    }
    val height = if (section == RecordsReadingSection.CHART) geometry.chartHeight else geometry.conclusionHeight
    val fraction = if (section != position.section) 0f else position.fraction
    return (start + height * fraction).roundToInt().coerceAtLeast(0)
}

internal class RecordsScrollRestoration {
    val geometries = mutableStateMapOf<RecordsScrollLayout, RecordsScrollGeometry>()
    var previousLayout: RecordsScrollLayout? = null
    var activePane = RecordsReadingSection.CHART
    var restoring = false
    // A temporary full-chart presentation returns to the section the reader left.
    var beforeExpansion: RecordsReadingPosition? = null
    var contentKey: String? = null
    var readingPosition: RecordsReadingPosition? = null
    var pendingPosition: RecordsReadingPosition? = null

    /** A pending restored position survives placeholder clamping, but never crosses a business/navigation change. */
    fun enter(layout: RecordsScrollLayout, key: String): RecordsReadingPosition? {
        val previous = previousLayout
        if (contentKey != null && contentKey != key) {
            readingPosition = null
            pendingPosition = null
            beforeExpansion = null
        } else if (previous != null && previous != layout) {
            var position = pendingPosition ?: readingPosition
            if (layout == RecordsScrollLayout.EXPANDED) beforeExpansion = position
            else if (previous == RecordsScrollLayout.EXPANDED) {
                position = beforeExpansion ?: position
                beforeExpansion = null
            }
            pendingPosition = position
        }
        previousLayout = layout
        contentKey = key
        return pendingPosition
    }

    fun observe(position: RecordsReadingPosition, ready: Boolean) {
        if (ready && !restoring && pendingPosition == null) readingPosition = position
    }

    fun measure(layout: RecordsScrollLayout, picker: Int? = null, chart: Int? = null, conclusion: Int? = null) {
        val previous = geometries[layout] ?: RecordsScrollGeometry()
        geometries[layout] = previous.copy(pickerHeight = picker ?: previous.pickerHeight,
            chartHeight = chart ?: previous.chartHeight, conclusionHeight = conclusion ?: previous.conclusionHeight)
    }
}

/** Rotation may recreate the Activity; these presentation measurements travel with the saved ScrollStates. */
internal val recordsScrollRestorationSaver = listSaver<RecordsScrollRestoration, Any>(
    save = { state ->
        listOf(state.previousLayout?.ordinal ?: -1, state.activePane.ordinal,
            state.beforeExpansion?.section?.ordinal ?: -1, state.beforeExpansion?.fraction ?: 0f) +
            RecordsScrollLayout.entries.flatMap { layout ->
                val geometry = state.geometries[layout] ?: RecordsScrollGeometry()
                listOf(geometry.pickerHeight, geometry.chartHeight, geometry.conclusionHeight)
            } + listOf(state.contentKey.orEmpty(),
                (state.pendingPosition ?: state.readingPosition)?.section?.ordinal ?: -1,
                (state.pendingPosition ?: state.readingPosition)?.fraction ?: 0f)
    },
    restore = { values ->
        RecordsScrollRestoration().apply {
            previousLayout = (values[0] as Int).takeIf { it >= 0 }?.let { RecordsScrollLayout.entries[it] }
            activePane = RecordsReadingSection.entries[values[1] as Int]
            beforeExpansion = (values[2] as Int).takeIf { it >= 0 }?.let {
                RecordsReadingPosition(RecordsReadingSection.entries[it], values[3] as Float)
            }
            RecordsScrollLayout.entries.forEachIndexed { index, layout ->
                val offset = 4 + index * 3
                geometries[layout] = RecordsScrollGeometry(values[offset] as Int, values[offset + 1] as Int, values[offset + 2] as Int)
            }
            val savedOffset = 4 + RecordsScrollLayout.entries.size * 3
            contentKey = (values.getOrNull(savedOffset) as? String)?.takeIf { it.isNotEmpty() }
            val section = (values.getOrNull(savedOffset + 1) as? Int)?.takeIf { it >= 0 }
            readingPosition = section?.let {
                RecordsReadingPosition(RecordsReadingSection.entries[it], values[savedOffset + 2] as Float)
            }
            // Even when layout is unchanged, Activity recreation has to wait for real content and replay this.
            pendingPosition = readingPosition
        }
    },
)

@Composable
internal fun rememberRecordsScrollRestoration(): RecordsScrollRestoration =
    rememberSaveable(saver = recordsScrollRestorationSaver) { RecordsScrollRestoration() }

/** Restore transitions/recreation once real content is laid out; ordinary data refreshes only update the saved position. */
@Composable
internal fun RestoreRecordsScroll(layout: RecordsScrollLayout, restoration: RecordsScrollRestoration,
    single: ScrollState, chart: ScrollState, conclusion: ScrollState, expanded: ScrollState, gap: Int, expandedInset: Int,
    contentKey: String, contentReady: Boolean,
) {
    val ready = rememberUpdatedState(contentReady)
    LaunchedEffect(chart.isScrollInProgress, conclusion.isScrollInProgress) {
        if (!restoration.restoring) {
            if (chart.isScrollInProgress) restoration.activePane = RecordsReadingSection.CHART
            if (conclusion.isScrollInProgress) restoration.activePane = RecordsReadingSection.CONCLUSION
        }
    }
    LaunchedEffect(layout, contentKey) {
        val position = restoration.enter(layout, contentKey)
        if (position != null) {
            restoration.restoring = true
            try {
                // Placeholder geometry/maxValue cannot satisfy this gate or overwrite the saved reading position.
                snapshotFlow { ready.value }.first { it }
                withFrameNanos { }
                withFrameNanos { }
                val geometry = snapshotFlow {
                    val measured = restoration.geometries[layout]
                    val viewportReady = when (layout) {
                        RecordsScrollLayout.SINGLE -> single.maxValue != Int.MAX_VALUE
                        RecordsScrollLayout.EXPANDED -> expanded.maxValue != Int.MAX_VALUE
                        else -> chart.maxValue != Int.MAX_VALUE && conclusion.maxValue != Int.MAX_VALUE
                    }
                    measured?.takeIf { ready.value && viewportReady && it.chartHeight > 0 }
                }.first { it != null }!!
                val offset = recordsRestoredOffset(position, layout, geometry, gap, expandedInset)
                when (layout) {
                    RecordsScrollLayout.SINGLE -> single.scrollTo(offset.coerceAtMost(single.maxValue))
                    RecordsScrollLayout.EXPANDED -> expanded.scrollTo(offset.coerceAtMost(expanded.maxValue))
                    else -> if (position.section == RecordsReadingSection.CONCLUSION) {
                        chart.scrollTo(chart.maxValue)
                        conclusion.scrollTo(offset.coerceAtMost(conclusion.maxValue))
                    } else {
                        chart.scrollTo(offset.coerceAtMost(chart.maxValue))
                        conclusion.scrollTo(0)
                    }
                }
                restoration.activePane = position.section
                restoration.pendingPosition = null
                restoration.readingPosition = position
            } finally {
                restoration.restoring = false
            }
        }
        snapshotFlow {
            val geometry = restoration.geometries[layout]
            if (!ready.value || geometry == null || geometry.chartHeight <= 0) null else
                recordsReadingPosition(layout, geometry, single.value, chart.value, conclusion.value, expanded.value,
                    restoration.activePane, gap, expandedInset)
        }.collect { current -> current?.let { restoration.observe(it, ready.value) } }
    }
}
