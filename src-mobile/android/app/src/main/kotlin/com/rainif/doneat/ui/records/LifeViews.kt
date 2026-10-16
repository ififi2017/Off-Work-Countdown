package com.rainif.doneat.ui.records

import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.ChildCare
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.WbTwilight
import androidx.compose.material.icons.outlined.Work
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing as S
import com.rainif.doneat.core.designsystem.DoneAtRecords322 as T
import com.rainif.doneat.core.designsystem.LocalDoneAtRecordsColors
import com.rainif.doneat.core.domain.records.CivilDatePrecision
import com.rainif.doneat.core.domain.records.LifeIncomeDecline
import com.rainif.doneat.core.domain.records.LifeStageKind
import com.rainif.doneat.core.domain.records.LifeStageSpan
import com.rainif.doneat.core.domain.records.LifeViewModel
import com.rainif.doneat.core.domain.records.LifeWorkPeriod
import com.rainif.doneat.l10n.Strings
import java.time.Instant

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
 * One year per square, grouped by decade; the current year has an orange ring.
 * Selection is owned by RecordsScreen so changing scale or layout preserves it.
 */
@Composable
fun LifeCanvas(
    stages: List<LifeStageSpan>,
    bounds: Pair<Double, Double>,
    referenceMs: Double,
    selectedAge: Int?,
    text: RecordsText,
    onSelect: (com.rainif.doneat.core.domain.records.RecordsLifeYear) -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val years = remember(stages, bounds, referenceMs, text.zone) { com.rainif.doneat.core.domain.records.recordsLifeYears(stages, bounds, referenceMs, text.zone) }
    val selected = years.firstOrNull { it.age == selectedAge } ?: years.firstOrNull { it.isCurrent }
    val res = LocalResources.current
    Column(verticalArrangement = Arrangement.spacedBy(S.m)) {
        CappedFontScale {
            Column(verticalArrangement = Arrangement.spacedBy(S.xs + S.xxs)) {
                years.chunked(10).forEach { decade ->
                    Row(horizontalArrangement = Arrangement.spacedBy(S.xs), verticalAlignment = Alignment.CenterVertically) {
                        Text(text.count(decade.first().age), Modifier.width(S.xxl).clearAndSetSemantics {}, style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant)
                        decade.forEach { year ->
                            val tint = stageColor(year.stage?.kind ?: LifeStageKind.UNSET)
                            val shape = MaterialTheme.shapes.extraSmall
                            val label = Strings.lifeYearAgeTitle(res, year.year.toString(), text.count(year.age))
                            Box(Modifier.weight(1f).height(T.lifeYearHeight)
                                .clip(shape)
                                .then(if (year.isPast || year.isCurrent) Modifier.background(tint) else Modifier.border(T.outline, tint.copy(alpha = .6f), shape))
                                .then(if (year.isCurrent || selected?.age == year.age) Modifier.border(T.selectedOutline, if (year.isCurrent) scheme.primary else scheme.onSurface, shape) else Modifier)
                                .clickable {
                                    onSelect(year)
                                }.semantics {
                                    contentDescription = listOfNotNull(label, year.stage?.let { stageTitle(it, text) }).joinToString(", ")
                                    role = Role.Button
                                    this.selected = selected?.age == year.age
                                })
                        }
                    }
                }
            }
        }
        if (selected != null) {
            Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(S.xs)) {
                Text(Strings.lifeYearAgeTitle(res, selected.year.toString(), text.count(selected.age)), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                selected.stage?.let { stage -> Text(stageTitle(stage, text) + " · " + stageRange(stage, text, referenceMs), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant) }
            }
        }
        androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(S.m), verticalArrangement = Arrangement.spacedBy(S.xs)) {
            stages.distinctBy { it.kind }.forEach { stage -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(S.xs)) {
                Box(Modifier.size(S.s).clip(MaterialTheme.shapes.extraSmall).background(stageColor(stage.kind)))
                Text(stageTitle(stage, text), style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant)
            } }
        }
        if (stages.any { it.workPeriod != null }) Text(text.string(R.string.lifeWorkPeriodBasis), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
    }
}

/**
 * Where a working life's time goes (iOS `RecordsLifeAllocationCard`), and the
 * lifetime income under it. When a part is missing it says so rather than
 * building a percentage from the parts that exist.
 */
@Composable
fun LifeAllocationCard(model: LifeViewModel?, loading: Boolean, decline: LifeIncomeDecline?, text: RecordsText, graph: com.rainif.doneat.AppGraph) {
    val res = LocalResources.current
    val allocation = model?.allocation?.takeIf { it.dayLengthMs > 0 && it.workMs > 0 }
    if (loading || allocation == null) {
        RecordsCard { Column(Modifier.padding(S.l)) {
            Text(text.string(R.string.lifeWhereTimeGoes), style = MaterialTheme.typography.titleSmall)
            if (loading) androidx.compose.material3.CircularProgressIndicator(Modifier.padding(S.m))
            else Text(text.string(R.string.lifeAllocationMissing), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } }
    } else {
        fun years(ms: Long) = text.decimal(ms / (365.2425 * 86_400_000))
        InsightCard(Strings.lifeAboutYears(res, years(allocation.dayLengthMs)), Strings.lifeOwnYears(res, years(allocation.wakingFreeMs)),
            Strings.lifeOwnBody(res, years(allocation.workMs + allocation.overtimeMs), years(allocation.sleepMs)))
        RecordsAllocationCard(text, text.string(R.string.lifeWhereTimeGoes), allocation, years = true)
    }
    model?.income?.let { income ->
        RecordsCard {
            Column(Modifier.padding(S.l), verticalArrangement = Arrangement.spacedBy(S.s)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(text.string(R.string.lifeIncomeTitle), Modifier.weight(1f), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                    com.rainif.doneat.ui.timer.EarningsVisibilityButton(graph) {}
                }
                Text(text.money(income.totalGross), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                val total = maxOf(1.0, income.historicalGross + income.projectedGross)
                LinearProgressIndicator(progress = { (income.historicalGross / total).coerceIn(0.0, 1.0).toFloat() }, modifier = Modifier.fillMaxWidth().clearAndSetSemantics {})
                Text(Strings.lifeIncomeBeforeToday(res, text.money(income.historicalGross)), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(Strings.lifeIncomeUntilRetirement(res, text.money(income.projectedGross)), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(decline?.let { Strings.lifeIncomeMethodDecline(res, text.count(it.startsAtAge), text.percent(it.retirementRatio * 100, 0)) } ?: text.string(R.string.lifeIncomeMethod), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
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
