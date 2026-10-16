package com.rainif.doneat.ui.records

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.DoneAtRecordsStyle
import com.rainif.doneat.core.designsystem.LocalDoneAtRecordsColors
import com.rainif.doneat.core.domain.records.TimeAllocationKind
import com.rainif.doneat.core.domain.records.TimeAllocationShare
import java.time.LocalDate
import kotlin.math.max
import kotlin.math.min

/**
 * Marks a filled shape as an estimate with 135° hatching (iOS `owcEstimated`).
 * An estimate is not less important, so it is never just drawn fainter. The
 * caller clips, since only it knows the shape.
 */
fun Modifier.estimatedHatch(enabled: Boolean, tint: Color, spacing: Dp = 5.dp, lineWidth: Dp = 1.dp): Modifier =
    if (!enabled) this else drawWithContent {
        drawContent()
        val step = spacing.toPx()
        if (step <= 0f || size.height <= 0f) return@drawWithContent
        clipRect {
            var x = -size.height
            while (x <= size.width) {
                drawLine(tint.copy(alpha = tint.alpha * DoneAtRecordsStyle.estimateStrokeOpacity), Offset(x, 0f), Offset(x + size.height, size.height), lineWidth.toPx())
                x += step
            }
        }
    }

@Composable
fun kindColor(kind: TimeAllocationKind): Color {
    val colors = LocalDoneAtRecordsColors.current
    return when (kind) {
        TimeAllocationKind.WORK -> colors.work
        TimeAllocationKind.OVERTIME -> colors.overtime
        TimeAllocationKind.WORK_BREAK -> colors.workBreak
        TimeAllocationKind.SLEEP -> colors.sleep
        TimeAllocationKind.FREE -> colors.free
        TimeAllocationKind.UNCLASSIFIED -> colors.unclassified
    }
}

/**
 * Dense charts cannot reflow without ceasing to be charts: their labels stop
 * growing at [max] while the screen reader keeps every full description.
 */
@Composable
fun CappedFontScale(max: Float = 1.3f, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, min(density.fontScale, max)), content = content)
}

/** A tonal card, as the settings groups use. */
@Composable
fun RecordsCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Surface(modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow, content = content)
}

/** One bar in every grid: regular work first, declared overtime told apart by position. */
@Composable
fun MiniWorkBar(workMs: Long, overtimeMs: Long, modifier: Modifier = Modifier, maxWidth: Dp = 24.dp, height: Dp = 3.dp) {
    val total = (max(0L, workMs) + max(0L, overtimeMs)).toDouble()
    if (total <= 0) return
    val colors = LocalDoneAtRecordsColors.current
    val width = min(maxWidth.value.toDouble(), max(8.0, 6 + total / 3_600_000 * 1.8))
    val overtimeWidth = if (overtimeMs > 0) max(2.0, width * overtimeMs / total) else 0.0
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(if (overtimeWidth > 0) 1.dp else 0.dp)) {
        if (workMs > 0) Box(Modifier.size(max(2.0, width - overtimeWidth).dp, height).clip(CircleShape).background(colors.work))
        if (overtimeWidth > 0) Box(Modifier.size(overtimeWidth.dp, height).clip(CircleShape).background(colors.overtime))
    }
}

/**
 * The 100% allocation bar and its legend (iOS `RecordsAllocationBar`). One
 * implementation, so every surface divides time into the same six colours.
 */
@Composable
fun AllocationBar(share: TimeAllocationShare, text: RecordsText, showsApproximateYears: Boolean = false) {
    val visible = TimeAllocationKind.entries.filter { share.duration(it) > 0 }
    var selectedKind by remember { mutableStateOf(TimeAllocationKind.WORK) }
    val active = visible.firstOrNull { it == selectedKind } ?: visible.firstOrNull() ?: return
    val total = max(1L, share.dayLengthMs).toDouble()
    fun exact(kind: TimeAllocationKind) = "${text.recordsDuration(share.duration(kind).toDouble())}, ${text.percent(share.duration(kind) / total * 100)}"
    fun years(kind: TimeAllocationKind) = if (showsApproximateYears) text.approximateLifeYears(share.duration(kind).toDouble()) else null
    val scheme = MaterialTheme.colorScheme
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Column(Modifier.clearAndSetSemantics {}) {
            Text(listOfNotNull(text.kindTitle(active), years(active)).joinToString(" · "), style = MaterialTheme.typography.labelLarge)
            Text(exact(active), style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant)
        }
        Row(
            Modifier.fillMaxWidth().height(44.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            visible.forEachIndexed { index, kind ->
                val first = index == 0
                val last = index == visible.lastIndex
                val shape = RoundedCornerShape(
                    topStart = if (first) 5.dp else 0.dp, bottomStart = if (first) 5.dp else 0.dp,
                    topEnd = if (last) 5.dp else 0.dp, bottomEnd = if (last) 5.dp else 0.dp,
                )
                Box(
                    Modifier
                        .weight(max(0.001f, (share.duration(kind) / total).toFloat()))
                        .fillMaxHeight()
                        .clickable { selectedKind = kind }
                        .semantics {
                            contentDescription = listOfNotNull(text.kindTitle(kind), years(kind), exact(kind)).joinToString(", ")
                            selected = kind == active
                            role = Role.Button
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.fillMaxWidth().height(10.dp).clip(shape).background(kindColor(kind))
                            .border(2.dp, if (kind == active) scheme.onSurface else Color.Transparent, shape),
                    )
                }
            }
        }
        FlowRow(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
        ) {
            visible.forEach { kind ->
                Row(
                    Modifier.heightIn(min = 32.dp).clip(RoundedCornerShape(8.dp)).clickable { selectedKind = kind }.padding(horizontal = 2.dp)
                        .clearAndSetSemantics {},
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Box(Modifier.size(6.dp).clip(CircleShape).background(kindColor(kind)))
                    Text(text.kindTitle(kind), style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant)
                }
            }
        }
    }
}

enum class LockedKind { DAY, SCALE, SUMMARY }

/**
 * A lock, in the order someone who hits it needs: what it is, that nothing is
 * being lost, and only then the way in (iOS `RecordsLockedPlaceholder`).
 */
@Composable
fun LockedPlaceholder(kind: LockedKind, text: RecordsText, onUnlock: () -> Unit) {
    val title = text.string(
        when (kind) {
            LockedKind.DAY -> R.string.recordsLockedDay
            LockedKind.SCALE -> R.string.recordsLockedScale
            LockedKind.SUMMARY -> R.string.recordsLockedSummary
        },
    )
    val scheme = MaterialTheme.colorScheme
    Surface(
        onClick = onUnlock,
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = scheme.surfaceContainerLow,
    ) {
        Column(
            Modifier.fillMaxWidth().heightIn(min = 148.dp).padding(DoneAtSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
        ) {
            Icon(Icons.Outlined.Lock, null, Modifier.size(28.dp).padding(bottom = 2.dp), tint = scheme.primary)
            Text(title, style = MaterialTheme.typography.titleSmall, textAlign = TextAlign.Center)
            Text(text.string(R.string.recordsLockedKeepsSaving), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant, textAlign = TextAlign.Center)
            Text(text.string(R.string.plusSeePlans), style = MaterialTheme.typography.labelLarge, color = scheme.primary, textAlign = TextAlign.Center)
        }
    }
}

/** A narrow weekday label per grid column, in the week's order. */
fun weekdayLabels(text: RecordsText, weekStart: LocalDate) = (0L until 7L).map { text.weekdayNarrow(weekStart.plusDays(it)) }
