package com.rainif.doneat.ui.records

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ChildCare
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.WbTwilight
import androidx.compose.material.icons.outlined.Work
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.LocalDoneAtRecordsColors
import com.rainif.doneat.core.domain.records.CivilDatePrecision
import com.rainif.doneat.core.domain.records.LifeIncomeDecline
import com.rainif.doneat.core.domain.records.LifeStageCalculator
import com.rainif.doneat.core.domain.records.LifeStageKind
import com.rainif.doneat.core.domain.records.LifeStageSpan
import com.rainif.doneat.core.domain.records.LifeViewModel
import com.rainif.doneat.core.domain.records.LifeWorkPeriod
import com.rainif.doneat.core.domain.records.RecordsCanvasGrid
import com.rainif.doneat.l10n.Strings
import java.time.Instant
import kotlin.math.min

@Composable
fun stageColor(kind: LifeStageKind): Color {
    val colors = LocalDoneAtRecordsColors.current
    return when (kind) {
        LifeStageKind.CHILDHOOD -> colors.childhood
        LifeStageKind.STUDY -> colors.study
        LifeStageKind.WORK -> colors.lifeWork
        LifeStageKind.RETIREMENT -> colors.retirement
        LifeStageKind.UNSET -> colors.lifeUnset
    }
}

private val LifeStageKind.icon: ImageVector
    get() = when (this) {
        LifeStageKind.CHILDHOOD -> Icons.Outlined.ChildCare
        LifeStageKind.STUDY -> Icons.Outlined.School
        LifeStageKind.WORK -> Icons.Outlined.Work
        LifeStageKind.RETIREMENT -> Icons.Outlined.WbTwilight
        LifeStageKind.UNSET -> Icons.AutoMirrored.Outlined.HelpOutline
    }

fun stageTitle(stage: LifeStageSpan, text: RecordsText): String = text.string(
    when (stage.workPeriod) {
        LifeWorkPeriod.ELAPSED -> R.string.lifeStageWorkElapsed
        LifeWorkPeriod.FUTURE -> R.string.lifeStageWorkFuture
        null -> when (stage.kind) {
            LifeStageKind.CHILDHOOD -> R.string.lifeStageChildhood
            LifeStageKind.STUDY -> R.string.lifeStageStudy
            LifeStageKind.WORK -> R.string.lifeStageWork
            LifeStageKind.RETIREMENT -> R.string.lifeStageRetirement
            LifeStageKind.UNSET -> R.string.lifeStageUnset
        }
    },
)

/** "1990 – about 2050"; the live career split says "present" where it meets now. */
fun stageRange(stage: LifeStageSpan, text: RecordsText, referenceMs: Double): String {
    fun label(ms: Double, precision: CivilDatePrecision?) =
        text.lifeYear(Instant.ofEpochMilli(ms.toLong()).atZone(text.zone).year, precision == CivilDatePrecision.YEAR)
    val start = stage.startMs
    val end = stage.endMs
    return when {
        start == null && end == null -> text.string(R.string.lifeUnset)
        start != null && end != null -> {
            val from = if (stage.workPeriod == LifeWorkPeriod.FUTURE && start == referenceMs) text.string(R.string.lifeStagePresent) else label(start, stage.startPrecision)
            val to = if (stage.workPeriod == LifeWorkPeriod.ELAPSED && end == referenceMs) text.string(R.string.lifeStagePresent) else label(end, stage.endPrecision)
            "$from – $to"
        }
        start != null -> label(start, stage.startPrecision)
        else -> label(end!!, stage.endPrecision)
    }
}

/**
 * A life, birth to retirement (iOS `RecordsLifeCanvas`): progress toward
 * retirement, a grid in which every cell is a slice of the span, and the
 * stages as a list, which is also what the screen reader walks.
 */
@Composable
fun LifeCanvas(
    stages: List<LifeStageSpan>,
    bounds: Pair<Double, Double>,
    referenceMs: Double,
    selectedStageID: String?,
    text: RecordsText,
    onSelect: (LifeStageSpan) -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val density = LocalDensity.current
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        stages.firstOrNull { it.kind == LifeStageKind.RETIREMENT }?.startMs?.let { retirement ->
            val progress = LifeStageCalculator.progress(bounds.first, retirement, referenceMs)
            Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(text.string(R.string.lifeProgressTitle), Modifier.weight(1f), style = MaterialTheme.typography.labelLarge, color = scheme.onSurfaceVariant)
                    Text(text.percent(progress * 100), style = MaterialTheme.typography.titleSmall, color = scheme.primary)
                }
                LinearProgressIndicator(progress = { progress.toFloat() }, Modifier.fillMaxWidth())
            }
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(240.dp).clearAndSetSemantics {}) {
            val grid = with(density) {
                RecordsCanvasGrid(maxWidth.toPx(), maxHeight.toPx(), 11.dp.toPx(), 3.dp.toPx(), minimumColumns = 18, minimumRows = 10)
            }
            val buckets = remember(stages, bounds, grid.count, referenceMs) {
                LifeStageCalculator.buckets(stages, bounds.first, bounds.second, grid.count, referenceMs)
            }
            val palette = LifeStageKind.entries.associateWith { stageColor(it) }
            val corner = with(density) { min(3.dp.toPx(), grid.cell / 3) }
            val line = with(density) { 0.9.dp.toPx() }
            val current = scheme.primary
            val card = scheme.surfaceContainerLow
            Canvas(
                Modifier.fillMaxSize().pointerInput(buckets, stages) {
                    detectTapGestures { point ->
                        val bucket = grid.index(point.x, point.y)?.let(buckets::getOrNull) ?: return@detectTapGestures
                        val stage = LifeStageCalculator.stageAt(bucket.startMs + (bucket.endMs - bucket.startMs) / 2, stages)
                        if (stage != null && stage.kind != LifeStageKind.RETIREMENT) onSelect(stage)
                    }
                },
            ) {
                buckets.forEach { bucket ->
                    val (x, y) = grid.origin(bucket.index)
                    val size = Size(grid.cell, grid.cell)
                    val base = palette.getValue(bucket.kind)
                    val dimmed = selectedStageID != null && bucket.stageID != selectedStageID
                    val futureWork = bucket.kind == LifeStageKind.WORK && bucket.isFuture
                    val alpha = if (bucket.isFuture) (if (dimmed) 0.14f else if (futureWork) 0.20f else 0.28f) else (if (dimmed) 0.42f else 0.82f)
                    drawRoundRect(base.copy(alpha = base.alpha * alpha), Offset(x, y), size, CornerRadius(corner))
                    if (bucket.isFuture) {
                        drawRoundRect(
                            base.copy(alpha = base.alpha * if (futureWork) 0.62f else 0.42f),
                            Offset(x + 0.75.dp.toPx(), y + 0.75.dp.toPx()), Size(grid.cell - 1.5.dp.toPx(), grid.cell - 1.5.dp.toPx()),
                            CornerRadius(corner), style = Stroke(line),
                        )
                        if (futureWork) {
                            drawLine(base.copy(alpha = base.alpha * 0.42f), Offset(x + 2.dp.toPx(), y + grid.cell - 2.dp.toPx()), Offset(x + grid.cell - 2.dp.toPx(), y + 2.dp.toPx()), 0.75.dp.toPx())
                        }
                    }
                    if (bucket.isCurrent) {
                        // A light overlay marks the present while its category stays readable.
                        drawRoundRect(current.copy(alpha = 0.18f), Offset(x, y), size, CornerRadius(corner))
                        drawRoundRect(scheme.onSurface, Offset(x - 1.dp.toPx(), y - 1.dp.toPx()), Size(grid.cell + 2.dp.toPx(), grid.cell + 2.dp.toPx()), CornerRadius(corner + 1.dp.toPx()), style = Stroke(1.8.dp.toPx()))
                        drawRoundRect(card, Offset(x + 1.5.dp.toPx(), y + 1.5.dp.toPx()), Size(grid.cell - 3.dp.toPx(), grid.cell - 3.dp.toPx()), CornerRadius(maxOf(1f, corner - 1.dp.toPx())), style = Stroke(1.2.dp.toPx()))
                    }
                }
            }
        }
        Column {
            stages.forEachIndexed { index, stage ->
                if (index > 0) HorizontalDivider(Modifier.padding(start = 44.dp), color = scheme.outlineVariant)
                StageRow(stage, stage.id == selectedStageID, text, referenceMs) { onSelect(stage) }
            }
        }
        if (stages.any { it.workPeriod != null }) {
            Text(text.string(R.string.lifeWorkPeriodBasis), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun StageRow(stage: LifeStageSpan, selected: Boolean, text: RecordsText, referenceMs: Double, onSelect: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val retired = stage.kind == LifeStageKind.RETIREMENT
    val title = stageTitle(stage, text)
    val range = stageRange(stage, text, referenceMs)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(if (selected) scheme.primary.copy(alpha = 0.08f) else Color.Transparent)
            .then(if (retired) Modifier.alpha(0.58f) else Modifier.clickable(role = Role.Button, onClick = onSelect))
            .semantics(mergeDescendants = true) {
                contentDescription = "$title, $range"
                if (!retired) this.selected = selected
            }
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(stage.kind.icon, null, Modifier.size(22.dp), tint = scheme.onSurfaceVariant)
        Column(Modifier.weight(1f).clearAndSetSemantics {}) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(range, style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
        }
        if (!retired) {
            Icon(
                if (selected) Icons.Outlined.CheckCircle else Icons.Outlined.Circle, null,
                Modifier.width(24.dp).clearAndSetSemantics {},
                tint = if (selected) scheme.primary else stageColor(stage.kind),
            )
        }
    }
}

/**
 * Where a working life's time goes (iOS `RecordsLifeAllocationCard`), and the
 * lifetime income under it. When a part is missing it says so rather than
 * building a percentage from the parts that exist.
 */
@Composable
fun LifeAllocationCard(model: LifeViewModel?, loading: Boolean, decline: LifeIncomeDecline?, text: RecordsText) {
    val scheme = MaterialTheme.colorScheme
    val res = LocalResources.current
    RecordsCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(text.string(R.string.lifeWhereTimeGoes), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(text.string(R.string.recordsSourceProjection), style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant)
            }
            val allocation = model?.allocation?.takeIf { it.dayLengthMs > 0 && it.workMs > 0 }
            when {
                loading -> Column(Modifier.heightIn(min = 100.dp).clearAndSetSemantics {}, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    listOf(18.dp to 1f, 10.dp to 1f, 14.dp to 0.5f).forEach { (height, width) ->
                        Box(Modifier.fillMaxWidth(width).height(height).clip(RoundedCornerShape(4.dp)).background(scheme.surfaceContainerHighest))
                    }
                }
                allocation != null -> AllocationBar(allocation, text, showsApproximateYears = true)
                else -> Text(text.string(R.string.lifeAllocationMissing), style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
            }
            val income = model?.income
            if (!loading && income != null) {
                HorizontalDivider(color = scheme.outlineVariant)
                Text(text.string(R.string.lifeIncomeTitle), style = MaterialTheme.typography.titleSmall)
                IncomeRow(text.string(R.string.lifeIncomeHistory), text.money(income.historicalGross))
                IncomeRow(text.string(R.string.lifeIncomeFuture), text.money(income.projectedGross))
                IncomeRow(text.string(R.string.lifeIncomeTotal), text.money(income.totalGross))
                Text(
                    decline?.let { Strings.lifeIncomeMethodDecline(res, text.count(it.startsAtAge), text.percent(it.retirementRatio * 100, 0)) }
                        ?: text.string(R.string.lifeIncomeMethod),
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun IncomeRow(title: String, value: String) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
    }
}

/** The invitation to describe a life, skippable (iOS `lifeSetupCard`). */
@Composable
fun LifeSetupCard(text: RecordsText, onSetUp: () -> Unit, onLater: (() -> Unit)?) {
    RecordsCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(text.string(R.string.recordsLifeSetupTitle), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text(text.string(R.string.recordsLifeSetupBody), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TextButton(onClick = onSetUp) { Text(text.string(R.string.recordsLifeSetupNow), fontWeight = FontWeight.SemiBold) }
                if (onLater != null) {
                    TextButton(onClick = onLater) { Text(text.string(R.string.recordsLifeSetupLater), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }
        }
    }
}
