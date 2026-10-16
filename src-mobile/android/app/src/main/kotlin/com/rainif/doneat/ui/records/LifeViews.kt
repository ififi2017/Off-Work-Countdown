package com.rainif.doneat.ui.records

import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.text.style.TextAlign
import com.rainif.doneat.core.domain.records.LifeStageCalculator
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

private fun stageKindTitle(kind: LifeStageKind): Int = when (kind) {
    LifeStageKind.CHILDHOOD -> R.string.lifeStageChildhood
    LifeStageKind.STUDY -> R.string.lifeStageStudy
    LifeStageKind.WORK -> R.string.lifeStageWork
    LifeStageKind.RETIREMENT -> R.string.lifeStageRetirement
    LifeStageKind.UNSET -> R.string.lifeStageUnset
}

/**
 * The iOS 3.2.2 Life card: progress to retirement, one year per square grouped by
 * decade (the current year ringed in orange), the selected year, then each stage once
 * with its years. Selection is owned by RecordsScreen so changing scale preserves it.
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
    val current = years.firstOrNull { it.isCurrent }
    val res = LocalResources.current
    fun date(ms: Double) = Instant.ofEpochMilli(ms.toLong()).atZone(text.zone).toLocalDate()
    fun wholeYears(fromMs: Double, toMs: Double) = maxOf(0, java.time.Period.between(date(fromMs), date(toMs)).years)
    Column {
        LifeProgress(stages, bounds, referenceMs, text, ::wholeYears)
        CappedFontScale {
            Column(verticalArrangement = Arrangement.spacedBy(S.xs + S.xxs)) {
                years.chunked(10).forEach { decade ->
                    Row(horizontalArrangement = Arrangement.spacedBy(S.xs + S.xxs), verticalAlignment = Alignment.CenterVertically) {
                        Text(text.count(decade.first().age), Modifier.width(28.dp).clearAndSetSemantics {}, style = MaterialTheme.typography.labelSmall,
                            color = scheme.onSurface.copy(alpha = .3f), textAlign = TextAlign.End)
                        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(S.xs)) { decade.forEach { year ->
                            val tint = stageColor(year.stage?.kind ?: LifeStageKind.UNSET)
                            val shape = RoundedCornerShape(5.dp)
                            val label = Strings.lifeYearAgeTitle(res, year.year.toString(), text.count(year.age))
                            val isSelected = selected?.age == year.age && !year.isCurrent
                            Box(Modifier.weight(1f).height(T.lifeYearHeight)
                                .then(if (isSelected) Modifier.border(T.selectedOutline, scheme.onSurface, shape) else Modifier)
                                .clickable { onSelect(year) }
                                .semantics {
                                    contentDescription = listOfNotNull(label, year.stage?.let { text.string(stageKindTitle(it.kind)) }).joinToString(", ")
                                    role = Role.Button
                                    this.selected = selected?.age == year.age
                                }
                                .padding(if (isSelected) T.selectedOutline else 0.dp)) {
                                when {
                                    year.isCurrent -> Box(Modifier.matchParentSize().border(1.5.dp, scheme.primary, shape).padding(2.dp).clip(shape).background(tint))
                                    year.isPast -> Box(Modifier.matchParentSize().clip(shape).background(tint))
                                    else -> Box(Modifier.matchParentSize().border(T.outline, tint.copy(alpha = .6f), shape))
                                }
                            }
                        } }
                    }
                }
            }
        }
        if (selected != null) {
            val stage = selected.stage
            val parts = buildList {
                add(text.string(stage?.let { stageKindTitle(it.kind) } ?: R.string.lifeStageUnset))
                val currentAge = current?.age ?: selected.age
                add(text.string(when {
                    selected.age == currentAge -> R.string.lifeStagePresent
                    selected.age < currentAge -> R.string.lifeYearPast
                    else -> R.string.lifeLegendProjected
                }))
                // The career's whole span, not the elapsed or future half the canvas splits it into.
                val careerStart = stages.filter { it.kind == LifeStageKind.WORK }.mapNotNull { it.startMs }.minOrNull()
                if (stage?.kind == LifeStageKind.WORK && careerStart != null) add(Strings.lifeWorkYearNumber(res, text.count(maxOf(1, wholeYears(careerStart, selected.middleMs) + 1))))
            }
            RecordsSelectionRow(Strings.lifeYearAgeTitle(res, selected.year.toString(), text.count(selected.age)), parts.joinToString(" · "), onClick = null)
        }
        LifeStageList(stages, text, Modifier.padding(top = S.m - S.xxs))
    }
}

/** iOS `lifeProgress`: how far from birth to retirement today is. Absent until retirement is set. */
@Composable
private fun LifeProgress(stages: List<LifeStageSpan>, bounds: Pair<Double, Double>, referenceMs: Double, text: RecordsText, wholeYears: (Double, Double) -> Int) {
    val retirement = stages.firstOrNull { it.kind == LifeStageKind.RETIREMENT }?.startMs ?: return
    val scheme = MaterialTheme.colorScheme
    val progress = LifeStageCalculator.progress(bounds.first, retirement, referenceMs)
    val workStart = stages.filter { it.kind == LifeStageKind.WORK }.mapNotNull { it.startMs }.minOrNull()
    Column(Modifier.fillMaxWidth().padding(bottom = S.m - S.xxs).semantics(mergeDescendants = true) {}) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(text.string(R.string.lifeProgressTitle), Modifier.weight(1f), style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold, color = scheme.onSurfaceVariant)
            Text(text.percent(progress * 100, 0), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = scheme.primary)
        }
        Box(Modifier.padding(top = 6.dp).fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)).background(scheme.surfaceContainerHighest)) {
            Box(Modifier.fillMaxWidth(progress.toFloat()).fillMaxHeight().clip(RoundedCornerShape(50)).background(scheme.primary))
        }
        if (workStart != null) Text(Strings.lifeCareerElapsed(LocalResources.current, text.count(wholeYears(workStart, referenceMs)), text.count(wholeYears(referenceMs, retirement))),
            Modifier.padding(top = S.xxs), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
    }
}

/** iOS `lifeStageList`: each stage once, with the years from its first start to its last end. */
@Composable
private fun LifeStageList(stages: List<LifeStageSpan>, text: RecordsText, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    Column(modifier) {
        stages.filter { it.kind != LifeStageKind.UNSET }.distinctBy { it.kind }.forEach { stage ->
            fun year(ms: Double?) = ms?.let { text.lifeYear(Instant.ofEpochMilli(it.toLong()).atZone(text.zone).year, false) }
            val start = year(stage.startMs)
            val end = year(stages.lastOrNull { it.kind == stage.kind }?.endMs)
            val range = when {
                start != null && end != null -> "\u2068$start\u2069 – \u2068$end\u2069"
                start != null -> "$start –"
                end != null -> "– $end"
                else -> text.string(R.string.lifeUnset)
            }
            HorizontalDivider(color = scheme.outlineVariant)
            Row(Modifier.fillMaxWidth().heightIn(min = 36.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(S.s + S.xxs)) {
                Box(Modifier.size(10.dp).clip(CircleShape).background(stageColor(stage.kind)))
                Text(text.string(stageKindTitle(stage.kind)), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                Text(range, style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
            }
        }
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
