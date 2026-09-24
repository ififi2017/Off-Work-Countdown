package com.rainif.doneat.ui.records

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import com.rainif.doneat.core.domain.records.RecordsCanvasGrid
import com.rainif.doneat.core.domain.records.RecordsYearSampler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtRecordsColors
import com.rainif.doneat.core.domain.records.RecordsDayAppearance
import com.rainif.doneat.core.domain.records.RecordsDayCell
import com.rainif.doneat.core.domain.records.RecordsDayMarks
import com.rainif.doneat.core.domain.records.RecordsWeekAxis
import com.rainif.doneat.core.domain.records.RecordsWorkIntensity
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
                drawLine(tint.copy(alpha = tint.alpha * 0.55f), Offset(x, 0f), Offset(x + size.height, size.height), lineWidth.toPx())
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

private fun Modifier.daySemantics(cell: RecordsDayCell, text: RecordsText, selected: Boolean, onSelect: () -> Unit, onOpen: () -> Unit) =
    clearAndSetSemantics {
        contentDescription = text.cellDescription(cell)
        role = Role.Button
        this.selected = selected
        onClick { onSelect(); true }
        customActions = listOf(CustomAccessibilityAction(text.string(R.string.recordsSeeThisDay)) { onOpen(); true })
    }

/**
 * The month (iOS `RecordsMonthGrid`). Fill depth is overtime, the small bar is
 * duration and proportion; selection is a ring, today only tints its number.
 */
@Composable
fun MonthGrid(
    cells: List<RecordsDayCell>,
    leadingBlanks: Int,
    weekdayLabels: List<String>,
    selectedDayKey: String?,
    text: RecordsText,
    onSelect: (RecordsDayCell) -> Unit,
    onOpen: (RecordsDayCell) -> Unit,
) {
    val colors = LocalDoneAtRecordsColors.current
    val scheme = MaterialTheme.colorScheme
    CappedFontScale {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(Modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                weekdayLabels.forEach {
                    Text(it, Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, color = scheme.outline, textAlign = TextAlign.Center)
                }
            }
            val slots: List<RecordsDayCell?> = List(leadingBlanks) { null } + cells
            slots.chunked(7).forEach { week ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    for (index in 0 until 7) {
                        val cell = week.getOrNull(index)
                        if (cell == null) {
                            Spacer(Modifier.weight(1f).aspectRatio(1f))
                            continue
                        }
                        val selected = cell.dayKey == selectedDayKey
                        val estimated = cell.isFuture || RecordsDayMarks.isEstimated(cell)
                        val fill = when (cell.appearance) {
                            RecordsDayAppearance.LOCKED -> scheme.surfaceContainerHighest.copy(alpha = 0.45f)
                            RecordsDayAppearance.UNRECORDED, RecordsDayAppearance.PLANNED -> Color.Transparent
                            RecordsDayAppearance.REST -> scheme.surfaceContainerHighest.copy(alpha = 0.6f)
                            RecordsDayAppearance.RECORDED, RecordsDayAppearance.CORRECTED ->
                                colors.work.copy(alpha = (0.4 * RecordsWorkIntensity.opacity(cell.overtimeMs, estimated)).toFloat())
                        }
                        val shape = RoundedCornerShape(8.dp)
                        Box(
                            Modifier
                                .weight(1f)
                                .aspectRatio(1f)
                                .clip(shape)
                                .background(fill)
                                .estimatedHatch(RecordsDayMarks.isEstimated(cell), scheme.onSurfaceVariant, spacing = 6.dp)
                                .border(2.dp, if (selected) scheme.primary else Color.Transparent, shape)
                                .clickable { onSelect(cell) }
                                .daySemantics(cell, text, selected, { onSelect(cell) }, { onOpen(cell) }),
                        ) {
                            Text(
                                text.count(cell.date.dayOfMonth),
                                Modifier.align(Alignment.Center),
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = if (cell.isToday || selected) FontWeight.SemiBold else FontWeight.Normal,
                                color = when {
                                    cell.appearance == RecordsDayAppearance.LOCKED -> scheme.outline
                                    cell.isToday || selected -> scheme.primary
                                    else -> scheme.onSurface
                                },
                            )
                            MiniWorkBar(
                                cell.workMs, cell.overtimeMs,
                                Modifier.align(Alignment.BottomCenter).padding(bottom = 4.dp)
                                    .graphicsLayer { alpha = RecordsWorkIntensity.opacity(cell.overtimeMs, estimated).toFloat() },
                            )
                            StateMarker(cell, Modifier.align(Alignment.TopEnd).padding(4.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StateMarker(cell: RecordsDayCell, modifier: Modifier) {
    when (cell.appearance) {
        RecordsDayAppearance.CORRECTED -> Icon(Icons.Filled.Edit, null, modifier.size(9.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        RecordsDayAppearance.LOCKED -> Icon(Icons.Filled.Lock, null, modifier.size(8.dp), tint = MaterialTheme.colorScheme.outline)
        else -> Unit
    }
}

/**
 * The week (iOS `RecordsWeekStrips`): one shared axis so days compare, overtime
 * stacked on the end of regular work rather than recolouring the column.
 */
@Composable
fun WeekStrips(
    cells: List<RecordsDayCell>,
    selectedDayKey: String?,
    text: RecordsText,
    onSelect: (RecordsDayCell) -> Unit,
    onOpen: (RecordsDayCell) -> Unit,
) {
    val colors = LocalDoneAtRecordsColors.current
    val scheme = MaterialTheme.colorScheme
    val ceiling = RecordsWeekAxis.ceiling(cells).toDouble()
    val track = 116.dp
    CappedFontScale {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.Bottom) {
            cells.forEach { cell ->
                val selected = cell.dayKey == selectedDayKey
                val estimated = cell.isFuture || RecordsDayMarks.isEstimated(cell)
                Column(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .clickable { onSelect(cell) }
                        .daySemantics(cell, text, selected, { onSelect(cell) }, { onOpen(cell) }),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    Box(Modifier.height(track + 8.dp), contentAlignment = Alignment.BottomCenter) {
                        if (cell.appearance == RecordsDayAppearance.LOCKED) {
                            Box(Modifier.size(18.dp, track).clip(CircleShape).background(scheme.surfaceContainerHighest.copy(alpha = 0.6f)), contentAlignment = Alignment.Center) {
                                Icon(Icons.Filled.Lock, null, Modifier.size(11.dp), tint = scheme.outline)
                            }
                        } else {
                            val work = min(1.0, cell.workMs / ceiling)
                            val overtime = min(1 - work, cell.overtimeMs / ceiling)
                            Box(Modifier.size(18.dp, track).clip(CircleShape).background(scheme.surfaceContainerHighest), contentAlignment = Alignment.BottomCenter) {
                                // The minimum height only makes a real short interval visible; zero stays empty.
                                Column(
                                    Modifier.fillMaxWidth().clip(CircleShape)
                                        .estimatedHatch(RecordsDayMarks.isEstimated(cell), Color.White, spacing = 4.dp)
                                        .graphicsLayer { alpha = RecordsWorkIntensity.opacity(cell.overtimeMs, estimated).toFloat() },
                                ) {
                                    if (overtime > 0) Box(Modifier.fillMaxWidth().height(max(4.0, track.value * overtime).dp).background(colors.overtime))
                                    if (work > 0) Box(Modifier.fillMaxWidth().height(max(4.0, track.value * work).dp).background(colors.work))
                                }
                            }
                            if (cell.observationCount > 0) {
                                Box(Modifier.offset(y = 4.dp).size(9.dp).clip(CircleShape).background(scheme.surfaceContainerLow).padding(2.dp).clip(CircleShape).background(scheme.onSurfaceVariant))
                            }
                            if (cell.appearance == RecordsDayAppearance.CORRECTED) {
                                Icon(Icons.Filled.Edit, null, Modifier.align(Alignment.TopCenter).size(10.dp), tint = scheme.onSurfaceVariant)
                            }
                        }
                    }
                    Column(
                        Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp))
                            .background(if (selected) scheme.primary else Color.Transparent).padding(vertical = 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        val tint = when {
                            selected -> scheme.onPrimary
                            cell.isToday -> scheme.primary
                            else -> scheme.onSurfaceVariant
                        }
                        Text(
                            text.count(cell.date.dayOfMonth), style = MaterialTheme.typography.bodyMedium, color = tint,
                            fontWeight = if (selected || cell.isToday) FontWeight.SemiBold else FontWeight.Normal,
                        )
                        Text(text.weekdayNarrow(cell.date), style = MaterialTheme.typography.labelSmall, color = tint)
                    }
                }
            }
        }
    }
}

/** The small legend swatches: solid, hatched, corrected, locked. */
@Composable
private fun LegendSwatch(hatched: Boolean) {
    val color = MaterialTheme.colorScheme.onSurfaceVariant
    Box(
        Modifier.size(9.dp).clip(RoundedCornerShape(2.dp))
            .background(if (hatched) Color.Transparent else color)
            .border(1.dp, color, RoundedCornerShape(2.dp))
            .estimatedHatch(hatched, color, spacing = 3.dp),
    )
}

/**
 * What solid, hatched, pencil and lock mean, beside the grid that uses them
 * (iOS `RecordsMarkLegend`). It wraps rather than truncates.
 */
@Composable
fun MarkLegend(includesLock: Boolean, text: RecordsText) {
    val color = MaterialTheme.colorScheme.onSurfaceVariant
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        FlowRow(
            Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
            horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            @Composable
            fun item(label: Int, mark: @Composable () -> Unit) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    mark()
                    Text(text.string(label), style = MaterialTheme.typography.labelSmall, color = color)
                }
            }
            item(R.string.recordsLegendRecorded) { LegendSwatch(hatched = false) }
            item(R.string.recordsLegendEstimated) { LegendSwatch(hatched = true) }
            item(R.string.recordsLegendCorrected) { Icon(Icons.Filled.Edit, null, Modifier.size(10.dp), tint = color) }
            if (includesLock) item(R.string.recordsLegendLocked) { Icon(Icons.Filled.Lock, null, Modifier.size(10.dp), tint = color) }
        }
        Text(text.string(R.string.recordsHeatScale), style = MaterialTheme.typography.labelSmall, color = color, textAlign = TextAlign.Center)
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

/**
 * The collapsed year (iOS `RecordsYearCanvas`): depth says when it was heavy,
 * hatching marks estimated work, and the selected month is one outline. The
 * month buttons under it carry the same choices for the screen reader.
 */
@Composable
fun YearCanvas(
    cells: List<RecordsDayCell>,
    year: Int,
    selectedMonth: Int?,
    text: RecordsText,
    onSelectMonth: (Int) -> Unit,
    onOpenMonth: (Int) -> Unit,
) {
    val colors = LocalDoneAtRecordsColors.current
    val scheme = MaterialTheme.colorScheme
    val density = LocalDensity.current
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(220.dp).clearAndSetSemantics {}) {
            val first = cells.firstOrNull()?.date ?: return@BoxWithConstraints
            val end = (cells.lastOrNull()?.date ?: first).plusDays(1)
            val grid = with(density) {
                RecordsCanvasGrid(maxWidth.toPx(), maxHeight.toPx(), 12.dp.toPx(), 3.dp.toPx(), minimumColumns = 16, minimumRows = 8)
            }
            val buckets = remember(cells, grid.count) { RecordsYearSampler.buckets(first, end, grid.count, cells) }
            val corner = with(density) { min(3.dp.toPx(), grid.cell / 3) }
            val line = with(density) { 1.dp.toPx() }
            Canvas(
                Modifier.fillMaxSize().pointerInput(buckets, grid) {
                    detectTapGestures(
                        onTap = { point -> grid.index(point.x, point.y)?.let(buckets::getOrNull)?.let { onSelectMonth(it.month) } },
                        onDoubleTap = { point -> grid.index(point.x, point.y)?.let(buckets::getOrNull)?.let { onOpenMonth(it.month) } },
                    )
                },
            ) {
                buckets.forEach { bucket ->
                    val (x, y) = grid.origin(bucket.index)
                    val fill = when (bucket.kind) {
                        RecordsDayAppearance.LOCKED -> scheme.surfaceContainerHighest.copy(alpha = 0.86f)
                        RecordsDayAppearance.UNRECORDED, RecordsDayAppearance.REST -> scheme.surfaceContainerHighest.copy(alpha = 0.65f)
                        RecordsDayAppearance.PLANNED -> colors.work.copy(alpha = RecordsWorkIntensity.opacity(0, estimated = true).toFloat())
                        RecordsDayAppearance.RECORDED, RecordsDayAppearance.CORRECTED ->
                            colors.work.copy(alpha = RecordsWorkIntensity.opacity(bucket.peakOvertimeMs, bucket.isFuture).toFloat())
                    }
                    val size = Size(grid.cell, grid.cell)
                    drawRoundRect(fill, Offset(x, y), size, CornerRadius(corner))
                    if (bucket.hasEstimatedWork) {
                        clipRect(x, y, x + grid.cell, y + grid.cell) {
                            var lineX = x - grid.cell
                            while (lineX <= x + grid.cell) {
                                drawLine(colors.work.copy(alpha = 0.28f), Offset(lineX, y), Offset(lineX + grid.cell, y + grid.cell), line)
                                lineX += 4.dp.toPx()
                            }
                        }
                    }
                    if (bucket.kind == RecordsDayAppearance.CORRECTED) {
                        drawRoundRect(scheme.onSurface.copy(alpha = 0.72f), Offset(x + line / 2, y + line / 2), Size(grid.cell - line, grid.cell - line), CornerRadius(corner), style = Stroke(line))
                    }
                }
                if (selectedMonth != null) {
                    grid.selectionRows(buckets.filter { it.month == selectedMonth }.map { it.index }).forEach { (from, to) ->
                        val (left, top) = grid.origin(from)
                        val (right, _) = grid.origin(to)
                        drawRoundRect(
                            scheme.primary.copy(alpha = 0.8f),
                            Offset(left - grid.gap / 2, top - grid.gap / 2),
                            Size(right + grid.cell - left + grid.gap, grid.cell + grid.gap),
                            CornerRadius(corner),
                            style = Stroke(1.25.dp.toPx()),
                        )
                    }
                }
            }
        }
        CappedFontScale {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                (1..12).chunked(4).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { month ->
                            val selected = month == selectedMonth
                            val date = LocalDate.of(year, month, 1)
                            Box(
                                Modifier
                                    .weight(1f)
                                    .heightIn(min = 44.dp)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(if (selected) scheme.primary.copy(alpha = 0.16f) else scheme.surfaceContainerHighest)
                                    .border(if (selected) 1.25.dp else 0.dp, if (selected) scheme.primary else Color.Transparent, RoundedCornerShape(10.dp))
                                    .pointerInput(month) { detectTapGestures(onTap = { onSelectMonth(month) }, onDoubleTap = { onOpenMonth(month) }) }
                                    .semantics {
                                        contentDescription = text.monthYear(date)
                                        role = Role.Button
                                        this.selected = selected
                                        onClick { onSelectMonth(month); true }
                                        customActions = listOf(CustomAccessibilityAction(text.string(R.string.recordsSeeThisMonth)) { onOpenMonth(month); true })
                                    },
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    text.month(date),
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                                    color = if (selected) scheme.primary else scheme.onSurfaceVariant,
                                    maxLines = 1,
                                    softWrap = false,
                                    modifier = Modifier.padding(horizontal = 4.dp).clearAndSetSemantics {},
                                )
                            }
                        }
                    }
                }
            }
        }
        Text(
            text.string(R.string.recordsHeatScale),
            Modifier.fillMaxWidth(),
            style = MaterialTheme.typography.labelSmall,
            color = scheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}
