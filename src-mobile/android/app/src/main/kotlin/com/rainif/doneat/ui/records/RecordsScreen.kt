package com.rainif.doneat.ui.records

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MyLocation
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.records.LifeDates
import com.rainif.doneat.core.domain.records.LifeStageCalculator
import com.rainif.doneat.core.domain.records.LifeStageKind
import com.rainif.doneat.core.domain.records.LifeViewModel
import com.rainif.doneat.core.domain.records.RecordsDayAppearance
import com.rainif.doneat.core.domain.records.RecordsDayCell
import com.rainif.doneat.core.domain.records.RecordsHeadlineSummary
import com.rainif.doneat.core.domain.records.RecordsScale
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.timer.EarningsVisibilityButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

private val SCALES = RecordsScale.entries

/**
 * The Records tab (iOS `RecordsDesignView`): a scale, the chart for its
 * window, and the conclusion under it. On a wide window the chart and the
 * conclusion scroll side by side.
 */
@Composable
fun RecordsScreen(graph: AppGraph, open: (Route) -> Unit, openSettings: (Route?) -> Unit) {
    val context = rememberRecordsContext(graph)
    val text = context.text
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val snackbar = remember { SnackbarHostState() }
    val scale = RecordsScale.fromRaw(device.recordsScale)?.takeIf { it in SCALES } ?: RecordsScale.MONTH
    var anchorKey by rememberSaveable { mutableStateOf(context.today.toString()) }
    val anchor = LocalDate.parse(anchorKey)
    var selectedDayKey by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedMonth by rememberSaveable { mutableStateOf<Int?>(null) }
    var selectedStageID by rememberSaveable { mutableStateOf<String?>(null) }
    var page by remember { mutableStateOf<RecordsPage?>(null) }
    val locked = scale.requiresPlus && !context.queries.authorized
    val profile = context.queries.state.lifeProfile

    LaunchedEffect(context, scale, anchor, locked) {
        // A locked scale is never computed: there is nothing it may show. Life draws from the profile instead.
        if (locked || scale == RecordsScale.LIFE) return@LaunchedEffect
        val loaded = withContext(Dispatchers.Default) { loadPage(context, scale, anchor) }
        page = loaded
        if (selectedDayKey != null && loaded.cells.none { it.dayKey == selectedDayKey }) selectedDayKey = null
    }

    // Life's allocation walks a whole career, so it is built once per revision and only while Life is shown.
    var lifeModel by remember { mutableStateOf<Pair<RecordsContext, LifeViewModel?>?>(null) }
    LaunchedEffect(context, scale, locked) {
        if (scale != RecordsScale.LIFE || locked || context.queries.state.lifeProfile == null) return@LaunchedEffect
        if (lifeModel?.first?.queries?.state == context.queries.state && lifeModel?.first?.today == context.today) return@LaunchedEffect
        val monthly = configuredMonthlySalary(graph)
        lifeModel = context to withContext(Dispatchers.Default) { context.queries.lifeModel(context.nowMs, monthly) }
    }
    val lifeStages = remember(profile, context.today, context.queries.zone) {
        profile?.let {
            val now = LifeDates.ms(context.today, context.queries.zone)
            val all = LifeStageCalculator.stages(it, context.queries.zone, now)
            Triple(LifeStageCalculator.canvasStages(all, now), LifeStageCalculator.timelineBounds(all, now), now)
        }
    }
    // The present stage starts selected; retirement is never a selection.
    LaunchedEffect(lifeStages) {
        val (stages, _, now) = lifeStages ?: return@LaunchedEffect
        if (selectedStageID == null || stages.none { it.id == selectedStageID }) {
            selectedStageID = LifeStageCalculator.stageAt(now - 1, stages)?.takeIf { it.kind != LifeStageKind.RETIREMENT }?.id
        }
    }

    fun tick() = view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    fun editLife() = if (context.queries.authorized) beginLifeEdit(graph, context, open) else openSettings(Route.Plus)
    fun dismissLifeSetup() {
        scope.launch { graph.settings.updateDevice { it.copy(lifeSetupPromptDismissed = true) } }
    }
    fun setScale(next: RecordsScale) {
        if (next == scale) return
        selectedDayKey = null
        selectedMonth = if (next == RecordsScale.YEAR) context.today.monthValue else null
        scope.launch { graph.settings.updateDevice { it.copy(recordsScale = next.raw) } }
        tick()
    }
    fun shift(by: Long) {
        anchorKey = context.queries.shiftAnchor(anchor, scale, by).toString()
        selectedDayKey = null
    }
    fun openDay(cell: RecordsDayCell) {
        if (cell.appearance == RecordsDayAppearance.LOCKED) openSettings(Route.Plus) else open(Route.RecordsDay(cell.dayKey))
    }
    fun openMonth(month: Int) {
        anchorKey = LocalDate.of(anchor.year, month, 1).toString()
        setScale(RecordsScale.MONTH)
    }
    fun selectMonth(month: Int) {
        if (selectedMonth != month) tick()
        selectedMonth = month
    }
    fun returnToToday() {
        anchorKey = context.today.toString()
        if (scale == RecordsScale.YEAR) selectedMonth = context.today.monthValue
        tick()
    }
    fun select(cell: RecordsDayCell) {
        if (selectedDayKey == cell.dayKey) {
            openDay(cell)
        } else {
            selectedDayKey = cell.dayKey
            tick()
        }
    }

    val current = page?.takeIf { it.scale == scale && !locked }
    val month = selectedMonth ?: context.today.monthValue
    val life: @Composable () -> Unit = {
        val stages = lifeStages
        val bounds = stages?.second
        if (stages == null || bounds == null) {
            LifeSetupCard(text, ::editLife, ::dismissLifeSetup)
        } else {
            LifeCanvas(stages.first, bounds, stages.third, selectedStageID, text) { stage ->
                if (selectedStageID != stage.id) tick()
                selectedStageID = stage.id
            }
            if (profile?.retirementOn == null) {
                TextButton(onClick = ::editLife) { Text(text.string(R.string.lifeSetRetirement), fontWeight = FontWeight.SemiBold) }
            }
        }
    }
    val chart: @Composable () -> Unit = {
        ChartCard(
            context, scale, anchor, current, selectedDayKey, month, locked, ::shift, ::returnToToday, ::select, ::openDay,
            ::selectMonth, ::openMonth, onUnlock = { openSettings(Route.Plus) }, life = life,
        )
    }
    val conclusion: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // Life's conclusion is behind Plus too: a locked life never prints a projected number.
            if (scale == RecordsScale.LIFE && !locked && profile != null) {
                val loaded = lifeModel?.takeIf { it.first.queries.state == context.queries.state }
                LifeAllocationCard(loaded?.second, loading = loaded == null, decline = profile.futureIncomeDecline, text = text)
            }
            if (context.queries.authorized && profile == null && !device.lifeSetupPromptDismissed && scale == RecordsScale.MONTH) {
                LifeSetupCard(text, ::editLife, ::dismissLifeSetup)
            }
            // As on iOS, a period without a summary shows none: locked, or nothing recorded yet.
            val headline = current?.headline
            if (scale != RecordsScale.LIFE && current != null && headline != null) {
                val title = if (scale == RecordsScale.YEAR) {
                    Strings.recordsAnnualSummary(androidx.compose.ui.platform.LocalResources.current, current.first.year.toString())
                } else {
                    periodTitle(context, scale, current.first, current.last)
                }
                HeadlineCard(context, title, headline)
            }
            if (scale == RecordsScale.YEAR && !locked) {
                OpenMonthButton(text, LocalDate.of(anchor.year, month, 1)) { openMonth(month) }
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
            BoxWithConstraints(Modifier.safeDrawingPadding()) {
                val twoColumns = maxWidth >= 720.dp
                Column(Modifier.fillMaxSize()) {
                    Header(graph, text, onAllRecords = { open(Route.RecordsAll) }) { note -> scope.launch { snackbar.showSnackbar(note) } }
                    if (twoColumns) {
                        Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            ScalePicker(text, scale, ::setScale)
                            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = DoneAtSpacing.xl)) { chart() }
                                Column(Modifier.width(420.dp).verticalScroll(rememberScrollState()).padding(bottom = DoneAtSpacing.xl)) { conclusion() }
                            }
                        }
                    } else {
                        Column(
                            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = DoneAtSpacing.page).padding(bottom = DoneAtSpacing.xl),
                            verticalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            ScalePicker(text, scale, ::setScale)
                            chart()
                            conclusion()
                        }
                    }
                }
            }
        }
        SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).safeDrawingPadding())
    }
}

@Composable
private fun Header(graph: AppGraph, text: RecordsText, onAllRecords: () -> Unit, onShownWithoutLock: (String) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text.string(R.string.recordsTitle),
            Modifier.weight(1f).padding(start = DoneAtSpacing.page - DoneAtSpacing.xs).semantics { heading() },
            style = MaterialTheme.typography.headlineMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        EarningsVisibilityButton(graph, onShownWithoutLock)
        IconButton(onClick = onAllRecords) {
            Icon(Icons.AutoMirrored.Outlined.ListAlt, text.string(R.string.recordsAllRecords), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ScalePicker(text: RecordsText, scale: RecordsScale, onSelect: (RecordsScale) -> Unit) {
    CappedFontScale {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            SCALES.forEachIndexed { index, option ->
                SegmentedButton(option == scale, { onSelect(option) }, SegmentedButtonDefaults.itemShape(index, SCALES.size)) {
                    Text(
                        text.string(
                            when (option) {
                                RecordsScale.WEEK -> R.string.recordsScaleWeek
                                RecordsScale.MONTH -> R.string.recordsScaleMonth
                                RecordsScale.YEAR -> R.string.recordsScaleYear
                                RecordsScale.LIFE -> R.string.recordsScaleLife
                            },
                        ),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

fun periodTitle(context: RecordsContext, scale: RecordsScale, first: LocalDate, last: LocalDate): String = when (scale) {
    RecordsScale.WEEK -> "${context.text.monthDay(first)} – ${context.text.monthDay(last)}"
    RecordsScale.MONTH -> context.text.monthYear(first)
    RecordsScale.YEAR -> first.year.toString()
    RecordsScale.LIFE -> context.text.string(R.string.recordsScaleLife)
}

@Composable
private fun ChartCard(
    context: RecordsContext,
    scale: RecordsScale,
    anchor: LocalDate,
    page: RecordsPage?,
    selectedDayKey: String?,
    selectedMonth: Int,
    locked: Boolean,
    shift: (Long) -> Unit,
    returnToToday: () -> Unit,
    onSelect: (RecordsDayCell) -> Unit,
    onOpen: (RecordsDayCell) -> Unit,
    onSelectMonth: (Int) -> Unit,
    onOpenMonth: (Int) -> Unit,
    onUnlock: () -> Unit,
    life: @Composable () -> Unit,
) {
    val text = context.text
    val (first, last) = context.queries.window(scale, anchor)
    val title = periodTitle(context, scale, first, last)
    val isLife = scale == RecordsScale.LIFE
    val showsToday = !isLife && (context.today.isBefore(first) || context.today.isAfter(last))
    val scheme = MaterialTheme.colorScheme
    RecordsCard {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            CappedFontScale {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (!isLife) {
                        IconButton(onClick = { shift(-1) }) {
                            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, text.string(R.string.recordsPreviousPeriod), tint = scheme.onSurfaceVariant)
                        }
                    }
                    Row(
                        Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(12.dp))
                            .then(
                                if (showsToday) {
                                    Modifier.clickable(onClick = returnToToday).semantics {
                                        contentDescription = text.string(R.string.recordsToday)
                                        stateDescription = title
                                    }
                                } else {
                                    Modifier.semantics { heading() }
                                },
                            ),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (showsToday) Icon(Icons.Outlined.MyLocation, null, Modifier.padding(start = 6.dp).size(14.dp), tint = scheme.primary)
                    }
                    if (!isLife) {
                        IconButton(onClick = { shift(1) }) {
                            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, text.string(R.string.recordsNextPeriod), tint = scheme.onSurfaceVariant)
                        }
                    }
                }
            }
            HorizontalDivider(color = scheme.outlineVariant)
            val cells = page?.takeIf { it.first == first }?.cells
            if (locked) {
                LockedPlaceholder(LockedKind.SCALE, text, onUnlock)
                return@Column
            }
            if (isLife) {
                life()
                return@Column
            }
            if (cells == null) {
                // The first load of a window: keep its height so the page does not jump.
                Box(Modifier.fillMaxWidth().heightIn(min = if (scale == RecordsScale.WEEK) 188.dp else 280.dp))
                return@Column
            } else {
                when (scale) {
                    RecordsScale.WEEK -> WeekStrips(cells, selectedDayKey, text, onSelect, onOpen)
                    RecordsScale.YEAR -> {
                        YearCanvas(cells, first.year, selectedMonth, text, onSelectMonth, onOpenMonth)
                        return@Column
                    }
                    else -> MonthGrid(
                        cells, context.queries.gridLeadingBlanks(first),
                        weekdayLabels(text, context.queries.window(RecordsScale.WEEK, first).first),
                        selectedDayKey, text, onSelect, onOpen,
                    )
                }
                cells.firstOrNull { it.dayKey == selectedDayKey }?.let { SelectedDay(it, text) { onOpen(it) } }
            }
            MarkLegend(includesLock = !context.queries.authorized, text = text)
        }
    }
}

/** The selected day, and the way into its page (iOS `RecordsDayCellCallout`). */
@Composable
private fun SelectedDay(cell: RecordsDayCell, text: RecordsText, onOpen: () -> Unit) {
    val locked = cell.appearance == RecordsDayAppearance.LOCKED
    val scheme = MaterialTheme.colorScheme
    Surface(onClick = onOpen, shape = RoundedCornerShape(16.dp), color = scheme.surfaceContainerHighest) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(if (locked) Icons.Outlined.Lock else Icons.Outlined.CalendarToday, null, Modifier.size(18.dp), tint = scheme.onSurfaceVariant)
            Column(Modifier.weight(1f)) {
                Text(
                    if (locked) text.string(R.string.recordsLockedDay) else text.dayTitle(cell.date),
                    style = MaterialTheme.typography.labelLarge,
                )
                if (!locked) {
                    Text(
                        "${text.cellSource(cell)} · ${text.recordsDuration((cell.workMs + cell.overtimeMs).toDouble())}",
                        style = MaterialTheme.typography.bodySmall,
                        color = scheme.onSurfaceVariant,
                    )
                }
            }
            Text(
                text.string(if (locked) R.string.plusSeePlans else R.string.recordsSeeThisDay),
                style = MaterialTheme.typography.labelLarge,
                color = scheme.primary,
            )
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, Modifier.size(18.dp), tint = scheme.primary)
        }
    }
}

/**
 * The period's conclusion (iOS `RecordsHeadlineView`): work, overtime,
 * income, then the time breakdown. Without Plus no summary is built, so
 * there is no card for a figure to reach.
 */
@Composable
private fun HeadlineCard(context: RecordsContext, title: String, summary: RecordsHeadlineSummary) {
    RecordsCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleMedium)
                HelpButton(title, context.text.string(R.string.recordsSummaryHelp))
            }
            HeadlineContent(context.text, summary)
        }
    }
}

/** From the year to one of its months (iOS "Open the selected month"). */
@Composable
private fun OpenMonthButton(text: RecordsText, month: LocalDate, onOpen: () -> Unit) {
    val res = androidx.compose.ui.platform.LocalResources.current
    TextButton(onClick = onOpen, modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp)) {
        Text(Strings.recordsOpenSelectedMonth(res, text.month(month)))
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, Modifier.size(18.dp))
    }
}

@Composable
private fun HeadlineContent(text: RecordsText, summary: RecordsHeadlineSummary) {
    val res = androidx.compose.ui.platform.LocalResources.current
    val forecast = summary.actualForecast
    val forecastOnly = forecast?.let { it.actual.days == 0.0 && it.forecast.hours > 0 } ?: false
    val shown = forecast?.let { if (forecastOnly) it.forecast else it.actual }
    val workedMs = shown?.let { it.hours * 3_600_000 } ?: (summary.regularWorkMs + summary.overtimeMs).toDouble()
    val workdays = shown?.days ?: summary.workdays.toDouble()
    val income = forecast?.total?.earnings ?: summary.estimatedIncome
    val overtimeMs = forecast?.let { it.actualOvertimeHours * 3_600_000 } ?: summary.overtimeMs.toDouble()
    Metric(
        text.string(if (forecastOnly) R.string.recordsForecastHours else R.string.recordsWorkedTime),
        text.duration(workedMs), prominent = true,
        subtitle = Strings.recordsWorkdayCount(res, text.count(workdays.toInt())),
    )
    if (overtimeMs > 0) Metric(text.string(R.string.recordsOvertime), text.duration(overtimeMs))
    if (income != null) {
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        val progress = forecast?.actual?.earnings?.takeIf { income > 0 }?.let { earned ->
            Strings.recordsIncomeProgress(res, text.money(earned), text.percent((earned / income * 100).coerceIn(0.0, 100.0)))
        }
        Metric(text.string(R.string.recordsForecastIncome), text.money(income), subtitle = progress)
    }
    if (summary.allocationDays > 0) {
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text.string(R.string.recordsTimeBreakdown), Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
            HelpButton(
                text.string(R.string.recordsTimeBreakdown),
                listOf(
                    Strings.recordsAllocationBasis(res, text.count(summary.allocationDays)),
                    text.string(if (summary.sleepFromHealth) R.string.recordsSleepFromHealth else R.string.recordsSleepEstimated),
                ).joinToString("\n\n"),
            )
        }
        AllocationBar(summary.allocation, text)
    }
}

/** A label and its value on one line, or stacked when the text is large. */
@Composable
private fun Metric(title: String, value: String, prominent: Boolean = false, subtitle: String? = null) {
    val scheme = MaterialTheme.colorScheme
    val stacked = androidx.compose.ui.platform.LocalDensity.current.fontScale >= 1.5f
    val labels: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
        }
    }
    val number: @Composable () -> Unit = {
        Text(
            value,
            style = if (prominent) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.bodyLarge,
            fontWeight = if (prominent) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
    Box(Modifier.semantics(mergeDescendants = true) {}) {
        if (stacked) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                labels(Modifier)
                number()
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                labels(Modifier.weight(1f))
                number()
            }
        }
    }
}

/** A small "?" that explains how a figure was reached, in a dialog rather than beside it. */
@Composable
private fun HelpButton(title: String, message: String) {
    var shows by remember { mutableStateOf(false) }
    IconButton(onClick = { shows = true }) {
        Icon(Icons.AutoMirrored.Outlined.HelpOutline, title, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.outline)
    }
    if (shows) {
        AlertDialog(
            onDismissRequest = { shows = false },
            title = { Text(title) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { shows = false }) { Text(stringResource(R.string.close)) } },
        )
    }
}
