package com.rainif.doneat.ui.records

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtRecords322 as T
import com.rainif.doneat.core.designsystem.DoneAtSpacing as S
import com.rainif.doneat.core.designsystem.LocalDoneAtRecordsColors
import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.schedule.holidayDayAnnotation
import com.rainif.doneat.ui.timer.EarningsVisibilityButton
import java.time.LocalDate

@Composable
internal fun RecordsPeriodCards(graph: AppGraph, context: RecordsContext, page: RecordsPage, selectedMonth: Int,
    onOpenDay: (String) -> Unit, onPlanLeave: () -> Unit, onOpenMonth: (Int) -> Unit) {
    val summary = page.headline ?: return
    val text = context.text
    val res = LocalResources.current
    val m = recordsInsightMetrics(summary, page.cells, page.scale)
    val title = periodTitle(context, page.scale, page.first, page.last)
    val payPeriod = when (page.scale) { RecordsScale.WEEK -> title; RecordsScale.MONTH -> text.shortMonth(page.first); else -> Strings.recordsYearLabel(res, page.first.year.toString()) }
    val holidays = page.cells.filter { it.appearance != RecordsDayAppearance.LOCKED }.mapNotNull { cell ->
        holidayDayAnnotation(context.lifeInputs.holidays, context.lifeInputs.archive.extendedSchedule?.takeIf { it.isEnabled }?.content?.holidayRegionIdentifier, cell.date, text.locale)
            ?.takeUnless { it.isMakeupWorkday }?.name
    }.groupingBy { it }.eachCount()
    val eyebrow = when (page.scale) { RecordsScale.MONTH -> Strings.recordsInsightMonthWorked(res, payPeriod); RecordsScale.YEAR -> Strings.recordsInsightYearOvertime(res, payPeriod); else -> title }
    val hero = when (page.scale) { RecordsScale.MONTH -> text.duration(m.workedMs); else -> if (m.overtimeMs > 0) Strings.recordsOvertimeAmount(res, text.duration(m.overtimeMs)) else text.string(R.string.recordsNoOvertime) }
    val sentences = buildList {
        when (page.scale) {
            RecordsScale.WEEK -> {
                if (m.completedWorkdays > 0) add(Strings.recordsInsightWeekBody(res, text.count(m.completedWorkdays), text.count(m.recordedDays), text.duration(page.cells.map(::RecordsDayLook).filter { it.hasSolidHours }.sumOf { it.totalMs }.toDouble())))
                m.emptyDay?.let { add(Strings.recordsInsightEmptyDay(res, text.monthDay(it))) }
            }
            RecordsScale.MONTH -> {
                holidays.forEach { (name, count) -> add(Strings.recordsInsightHolidayOff(res, name, text.count(count))) }
                if (m.plannedDays > 0) add(Strings.recordsInsightPlannedAhead(res, text.count(m.plannedDays), text.duration(m.plannedMs)))
            }
            RecordsScale.YEAR -> {
                if (m.overtimeMs > 0) add(Strings.recordsInsightExtraDays(res, text.decimal(m.extraWorkdays)))
                add(Strings.recordsInsightYearWorked(res, text.duration(m.workedMs)))
            }
            else -> Unit
        }
    }
    val action = when (page.scale) { RecordsScale.WEEK -> m.emptyDay?.let { text.string(R.string.recordsInsightFillDay) }; RecordsScale.MONTH -> text.string(R.string.leavePlanAction); RecordsScale.YEAR -> Strings.recordsOpenSelectedMonth(res, text.month(LocalDate.of(page.first.year, selectedMonth, 1))); else -> null }
    InsightCard(eyebrow, hero, joinRecordsSentences(sentences), action, {
        when (page.scale) { RecordsScale.WEEK -> m.emptyDay?.let { onOpenDay(it.toString()) }; RecordsScale.MONTH -> onPlanLeave(); RecordsScale.YEAR -> onOpenMonth(selectedMonth); else -> Unit }
    }) {
        if (m.recordedDays > 0) RecordsChip(Strings.recordsWorkdayCount(res, text.count(m.recordedDays)))
        if (m.overtimeMs > 0) RecordsChip(Strings.recordsOvertimeAmount(res, text.duration(m.overtimeMs)), overtime = true)
        if (m.plannedDays > 0 && page.scale != RecordsScale.WEEK) RecordsChip(Strings.recordsPlannedWorkdays(res, text.count(m.plannedDays)), planned = true)
    }
    if (summary.allocationDays > 0) RecordsAllocationCard(text, text.string(R.string.recordsTimeBreakdown), summary.allocation,
        footnote = text.string(if (summary.sleepFromHealth) R.string.recordsAllocationFootnoteHealth else R.string.recordsAllocationFootnoteSettings))
    (summary.actualForecast?.total?.earnings ?: summary.estimatedIncome)?.let { total ->
        RecordsPayCard(graph, text, Strings.recordsPayTitle(res, payPeriod), total, summary.actualForecast?.actual?.earnings)
    }
}

internal fun joinRecordsSentences(sentences: List<String>): String = sentences.filter { it.isNotEmpty() }.fold("") { result, sentence ->
    result + if (result.isEmpty() || result.last() in "。！？") sentence else " $sentence"
}

@Composable
internal fun InsightCard(eyebrow: String, hero: String, body: String? = null, actionTitle: String? = null, onAction: () -> Unit = {}, chips: @Composable FlowRowScope.() -> Unit = {}) {
    RecordsCard {
        Column(Modifier.padding(S.l + S.xxs), verticalArrangement = Arrangement.spacedBy(S.s)) {
            Text(eyebrow, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            Text(hero, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = LocalDoneAtRecordsColors.current.work)
            if (!body.isNullOrEmpty()) Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (actionTitle != null) TextButton(onClick = onAction, contentPadding = PaddingValues(S.xxs)) { Text(actionTitle) }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(S.xs), verticalArrangement = Arrangement.spacedBy(S.xs), content = chips)
        }
    }
}

@Composable
private fun RecordsChip(label: String, overtime: Boolean = false, planned: Boolean = false) {
    val colors = LocalDoneAtRecordsColors.current
    val color = if (overtime) colors.overtime else colors.work
    Row(Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHighest).padding(horizontal = S.s + S.xxs, vertical = S.xs), horizontalArrangement = Arrangement.spacedBy(S.xs), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(T.yearDot).clip(CircleShape).then(if (planned) Modifier.border(T.outline, color, CircleShape) else Modifier.background(color)))
        Text(label, style = MaterialTheme.typography.labelMedium)
    }
}

/** A vertical allocation column with every category's value always visible. */
@Composable
internal fun RecordsAllocationCard(text: RecordsText, title: String, share: TimeAllocationShare, years: Boolean = false, footnote: String? = null) {
    val res = LocalResources.current
    val total = share.dayLengthMs.coerceAtLeast(1).toDouble()
    val order = listOf(TimeAllocationKind.WORK, TimeAllocationKind.WORK_BREAK, TimeAllocationKind.OVERTIME, TimeAllocationKind.UNCLASSIFIED, TimeAllocationKind.FREE, TimeAllocationKind.SLEEP)
    val rows = order.filter { share.duration(it) > (if (years) .05 * 365.2425 * 86_400_000 else 0.0) || (!years && it != TimeAllocationKind.UNCLASSIFIED && it != TimeAllocationKind.OVERTIME) }.reversed()
    fun value(ms: Long) = if (years) Strings.lifeApproxYearsShort(res, text.decimal(ms / (365.2425 * 86_400_000))) else text.duration(ms.toDouble())
    RecordsCard {
        Column(Modifier.padding(S.l + S.xxs), verticalArrangement = Arrangement.spacedBy(S.m)) {
            val totalLabel = if (years) value(share.dayLengthMs) else Strings.recordsAllocationTotal(res, value(share.dayLengthMs))
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val titleText: @Composable (Modifier) -> Unit = { modifier ->
                    Text(title, modifier.semantics { heading() }, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                }
                val totalText: @Composable (Modifier) -> Unit = { modifier ->
                    Text(totalLabel, modifier, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (recordsAllocationHeaderStacks(maxWidth.value, LocalDensity.current.fontScale)) {
                    Column(verticalArrangement = Arrangement.spacedBy(S.xs)) {
                        titleText(Modifier.fillMaxWidth())
                        totalText(Modifier.fillMaxWidth())
                    }
                } else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(S.s), verticalAlignment = Alignment.Bottom) {
                    titleText(Modifier.weight(1f))
                    totalText(Modifier.weight(1f))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(S.l), verticalAlignment = Alignment.Top) {
                Column(Modifier.width(T.allocationWidth).height(T.allocationHeight).clip(MaterialTheme.shapes.large).background(MaterialTheme.colorScheme.surfaceContainerHighest).clearAndSetSemantics {}, verticalArrangement = Arrangement.Bottom) {
                    rows.filter { share.duration(it) > 0 }.forEach { kind -> Box(Modifier.fillMaxWidth().weight((share.duration(kind) / total).toFloat().coerceAtLeast(.001f)).background(kindColor(kind))) }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(S.m)) {
                    rows.forEach { kind ->
                        Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(S.s)) {
                            Box(Modifier.size(S.s).clip(CircleShape).background(kindColor(kind)))
                            Column(Modifier.weight(1f)) {
                                Text(text.kindTitle(kind), style = MaterialTheme.typography.bodyMedium)
                                Text(value(share.duration(kind)) + " · " + text.percent(share.duration(kind) / total * 100), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
            if (footnote != null) Text(footnote, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
internal fun RecordsPayCard(graph: AppGraph, text: RecordsText, title: String, total: Double, earned: Double?) {
    RecordsCard {
        Column(Modifier.padding(S.l + S.xxs), verticalArrangement = Arrangement.spacedBy(S.s)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                EarningsVisibilityButton(graph) {}
            }
            Text(text.money(total), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
            if (earned != null && total > 0) {
                val fraction = (earned / total).coerceIn(0.0, 1.0)
                LinearProgressIndicator(progress = { fraction.toFloat() }, modifier = Modifier.fillMaxWidth().clearAndSetSemantics {})
                Text(Strings.recordsIncomeProgress(LocalResources.current, text.money(earned), text.percent(fraction * 100)), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
internal fun RecordsEmptyPeriod(text: RecordsText, title: String) {
    RecordsCard { Column(Modifier.padding(S.l), verticalArrangement = Arrangement.spacedBy(S.s)) {
        Text(title, style = MaterialTheme.typography.titleSmall)
        Text(text.string(R.string.recordsUnrecorded), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    } }
}

/** Decorative locked silhouettes are constants, never generated from the archive. */
@Composable
internal fun RecordsLockedCalendar(scale: RecordsScale, text: RecordsText) {
    Column(Modifier.fillMaxWidth().padding(vertical = S.m).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(S.m)) {
        Column(Modifier.fillMaxWidth().clearAndSetSemantics {}, verticalArrangement = Arrangement.spacedBy(S.s)) {
            repeat(if (scale == RecordsScale.LIFE) 8 else 4) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(S.s)) {
                    repeat(if (scale == RecordsScale.LIFE) 10 else 12) { Box(Modifier.weight(1f).height(T.lifeYearHeight).clip(MaterialTheme.shapes.extraSmall).background(MaterialTheme.colorScheme.surfaceContainerHighest)) }
                }
            }
        }
        Icon(Icons.Outlined.Lock, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text.string(R.string.recordsLockedScale), style = MaterialTheme.typography.titleSmall)
        Text(text.string(R.string.recordsLockedKeepsSaving), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Keep both labels readable before a long total can consume the title column. */
internal fun recordsAllocationHeaderStacks(widthDp: Float, fontScale: Float): Boolean = widthDp < 280f || fontScale >= 1.5f
