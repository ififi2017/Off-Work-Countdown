package com.rainif.doneat.ui.records

import com.rainif.doneat.core.designsystem.LocalDoneAtBottomBarPadding
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.outlined.Luggage
import androidx.compose.material.icons.outlined.PlayCircleOutline
import androidx.compose.material.icons.outlined.MyLocation
import androidx.compose.material.icons.outlined.OpenInFull
import androidx.compose.material.icons.outlined.CloseFullscreen
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
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.designsystem.DoneAtMotion
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Animatable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.ui.schedule.HolidayCoverageNotice
import com.rainif.doneat.ui.schedule.HolidayDayAnnotation
import com.rainif.doneat.ui.schedule.holidayDayAnnotation
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtRollingText
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.records.LifeDates
import com.rainif.doneat.core.domain.records.LifeStageCalculator
import com.rainif.doneat.core.domain.records.LifeStageKind
import com.rainif.doneat.core.domain.records.RecordsDayAppearance
import com.rainif.doneat.core.domain.records.RecordsDayCell
import com.rainif.doneat.core.domain.records.RecordsScale
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.adaptive.*
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
    // A tap changes the view immediately; the device file is only its saved preference.
    // Persist in the app scope so switching tabs cannot cancel the write.
    var scaleRaw by rememberSaveable { mutableStateOf(device.recordsScale) }
    val scale = RecordsScale.fromRaw(scaleRaw) ?: RecordsScale.MONTH
    var anchorKey by rememberSaveable { mutableStateOf(context.today.toString()) }
    val anchor = LocalDate.parse(anchorKey)
    var selectedDayKey by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedMonth by rememberSaveable { mutableStateOf<Int?>(null) }
    var selectedLifeAge by rememberSaveable { mutableStateOf<Int?>(null) }
    var expanded by rememberSaveable { mutableStateOf(false) }
    val regularScroll = rememberScrollState()
    val expandedScroll = rememberScrollState()
    val chartScroll = rememberScrollState()
    val conclusionScroll = rememberScrollState()
    val scrollRestoration = rememberRecordsScrollRestoration()
    var page by remember { mutableStateOf<RecordsPage?>(null) }
    val locked = scale.requiresPlus && !context.queries.authorized
    val profile = context.queries.state.lifeProfile

    LaunchedEffect(context.calculation, scale, anchor, locked) {
        // A locked scale is never computed: there is nothing it may show. Life draws from the profile instead.
        if (locked || scale == RecordsScale.LIFE) return@LaunchedEffect
        val loaded = withContext(Dispatchers.Default) { loadPage(context.calculation, scale, anchor) }
        page = loaded
        if (selectedDayKey != null && loaded.cells.none { it.dayKey == selectedDayKey }) selectedDayKey = null
    }

    // Plan 020 §5: recorded overtime is open to free users as one number. Plus
    // reads it inside its summary, so only Life and free periods load it here.
    var overtime by remember { mutableStateOf<RecordedOvertime?>(null) }
    LaunchedEffect(context.calculation, scale, anchor, page) {
        val q = context.queries
        if (scale != RecordsScale.LIFE && q.authorized) return@LaunchedEffect
        val first = q.window(scale, anchor).first
        // The page already resolved this window. Await its snapshot rather than expanding the same
        // schedule twice for free week/month views; the last total stays shown until it lands.
        val loaded = page?.takeIf { it.matches(context.calculation, scale, first) }
        if (scale != RecordsScale.LIFE && !locked && loaded == null) return@LaunchedEffect
        val ms = withContext(Dispatchers.Default) {
            if (scale == RecordsScale.LIFE) {
                q.lifetimeRecordedOvertimeMs(context.nowMs)
            } else if (loaded != null) {
                loaded.recordedOvertimeMs
            } else {
                val last = q.window(scale, anchor).second
                val days = q.displayDays(first.minusDays(1), last, context.nowMs)
                q.recordedOvertimeMs(days, days.map { it.dayKey }.filter { it >= first.toString() }.toSet(), context.nowMs)
            }
        }
        overtime = RecordedOvertime(context.calculation, scale, first, ms)
    }

    // Life's allocation walks a whole career, so it is built once per revision and only while Life is shown.
    var lifeModel by remember { mutableStateOf<RecordsLifeSnapshot?>(null) }
    LaunchedEffect(context.calculation, scale, locked) {
        if (scale != RecordsScale.LIFE || locked || context.queries.state.lifeProfile == null) return@LaunchedEffect
        if (lifeModel?.matches(context.lifeInputs, context.queries.authorized) == true) return@LaunchedEffect
        val monthly = configuredMonthlySalary(graph)
        lifeModel = RecordsLifeSnapshot(context.lifeInputs, withContext(Dispatchers.Default) { context.queries.lifeModel(context.nowMs, monthly) })
    }
    val lifeStages = remember(profile, context.today, context.queries.zone) {
        profile?.let {
            val now = LifeDates.ms(context.today, context.queries.zone)
            val all = LifeStageCalculator.stages(it, context.queries.zone, now)
            Triple(LifeStageCalculator.canvasStages(all, now), LifeStageCalculator.timelineBounds(all, now), now)
        }
    }
    fun tick() = view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    // iOS: the chart cross-fades when the question changes (to or from Year and Life) and when
    // it jumps back to today; Week and Month inspect the same days, so they swap in place.
    val motion = LocalDoneAtMotion.current
    val chartAlpha = remember { Animatable(1f) }
    var chartFade by remember { mutableStateOf<Int?>(null) }
    var chartFadeCount by remember { mutableIntStateOf(0) }
    LaunchedEffect(chartFadeCount) {
        val duration = chartFade ?: return@LaunchedEffect
        if (motion.reduced) return@LaunchedEffect
        chartAlpha.snapTo(0f)
        chartAlpha.animateTo(1f, tween(duration, easing = if (duration == DoneAtMotion.RECORDS_TODAY_MS) FastOutSlowInEasing else motion.emphasizedDecelerate))
    }
    fun fadeChart(duration: Int) { chartFade = duration; chartFadeCount++ }
    fun editLife() = if (context.queries.authorized) beginLifeEdit(graph, context, open)
        else openSettings(Route.PlusFor(com.rainif.doneat.ui.PlusPendingAction.RecordsLifeEdit))
    fun dismissLifeSetup() {
        scope.launch { graph.settings.updateDevice { it.copy(lifeSetupPromptDismissed = true) } }
    }
    fun setScale(next: RecordsScale) {
        if (next == scale) return
        if (scale == RecordsScale.YEAR || scale == RecordsScale.LIFE || next == RecordsScale.YEAR || next == RecordsScale.LIFE) fadeChart(DoneAtMotion.RECORDS_SCALE_CHANGE_MS)
        expanded = false
        selectedDayKey?.takeIf { next == RecordsScale.WEEK || next == RecordsScale.MONTH }?.let { key -> anchorKey = key }
        if (next == RecordsScale.YEAR && selectedMonth == null) selectedMonth = anchor.monthValue
        switchRecordsScale(next, { scaleRaw = it }, graph.scope) { selected ->
            graph.settings.updateDevice { it.copy(recordsScale = selected) }
        }
        tick()
    }
    fun shift(by: Long) {
        anchorKey = context.queries.shiftAnchor(anchor, scale, by).toString()
        selectedDayKey = null
    }
    fun openDay(cell: RecordsDayCell) {
        if (cell.appearance != RecordsDayAppearance.LOCKED) open(Route.RecordsDay(cell.dayKey))
    }
    fun openMonth(month: Int) {
        selectedDayKey = null
        anchorKey = LocalDate.of(anchor.year, month, 1).toString()
        setScale(RecordsScale.MONTH)
    }
    fun selectMonth(month: Int) {
        if (selectedMonth != month) tick()
        selectedMonth = month
    }
    fun returnToToday() {
        fadeChart(DoneAtMotion.RECORDS_TODAY_MS)
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

    // A page from the previous minute stays until this minute's lands, so the tab never blinks on the minute.
    val current = page?.takeIf { !locked && it.standsIn(context.calculation, scale, context.queries.window(scale, anchor).first) }
    // Stable across Activity recreation, but invalidated by navigation/business/access changes.
    // Only presentation coordinates are saved; the archive and amounts never enter saved UI state.
    val readingContentKey = remember(scale, anchor, context.lifeInputs.archive, context.lifeInputs.preferences,
        context.lifeInputs.session.state, context.lifeInputs.today, context.queries.authorized) {
        listOf(scale.raw, anchor.toString(), context.lifeInputs.archive.hashCode(), context.lifeInputs.preferences.hashCode(),
            context.lifeInputs.session.state.hashCode(), context.lifeInputs.today.toString(), context.queries.authorized).joinToString(":")
    }
    val readingContentReady = when {
        locked -> true
        scale == RecordsScale.LIFE -> profile == null || lifeModel?.matches(context.lifeInputs, context.queries.authorized) == true
        else -> current != null
    }
    val month = selectedMonth ?: context.today.monthValue
    val life: @Composable () -> Unit = {
        val stages = lifeStages
        val bounds = stages?.second
        if (stages == null || bounds == null) {
            LifeSetupCard(text, { editLife() }, { dismissLifeSetup() })
        } else {
            LifeCanvas(stages.first, bounds, stages.third, selectedLifeAge, text) { year ->
                val next = if (year.isCurrent) null else year.age
                if (selectedLifeAge != next) tick()
                selectedLifeAge = next
            }
            if (profile?.retirementOn == null) {
                TextButton(onClick = { editLife() }) { Text(text.string(R.string.lifeSetRetirement), fontWeight = FontWeight.SemiBold) }
            }
        }
    }
    val chart: @Composable () -> Unit = { Box(Modifier.graphicsLayer { alpha = chartAlpha.value }) {
        ChartCard(
            context, scale, anchor, current, selectedDayKey, month, locked, expanded,
            { shift(it) }, { returnToToday() }, { select(it) }, { openDay(it) },
            { selectMonth(it) }, { openMonth(it) },
            onUnlock = { openSettings(Route.PlusFor(com.rainif.doneat.ui.PlusPendingAction.RecordsCharts)) }, life = life,
            onExpand = { expanded = !expanded },
            onPlanLeave = {
                if (graph.records.state.value.leaveBalances.isEmpty()) open(Route.LeaveBalanceEdit(null, guided = true))
                else open(Route.Leave(fromRecords = true))
            },
            onOpenReport = {
                val kind = when (scale) {
                    RecordsScale.WEEK -> com.rainif.doneat.core.domain.records.CycleReportKind.WEEK
                    RecordsScale.YEAR -> com.rainif.doneat.core.domain.records.CycleReportKind.YEAR
                    else -> com.rainif.doneat.core.domain.records.CycleReportKind.MONTH
                }
                val period = context.queries.reportPeriod(kind, anchor)
                open(Route.CycleReport(kind.name, period.startDayKey, period.endDayKey, period.timeZoneIdentifier))
            },
            onPinch = { zoom ->
                if (zoom > 1.22f) {
                    if (scale == RecordsScale.YEAR) openMonth(month) else setScale(scale.zoomedIn)
                } else if (zoom < 0.82f) setScale(scale.zoomedOut)
            },
        )
    } }
    val conclusion: @Composable (Boolean) -> Unit = { showsLockedSummary ->
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // Life's conclusion is behind Plus too: a locked life never prints a projected number.
            if (scale == RecordsScale.LIFE && !locked && profile != null) {
                val loaded = lifeModel?.takeIf { it.matches(context.lifeInputs, context.queries.authorized) }
                LifeAllocationCard(loaded?.model, loading = loaded == null, decline = profile.futureIncomeDecline, text = text, graph = graph)
            }
            val overtimeMs = overtime?.takeIf {
                it.calculation.continues(context.calculation) && it.scale == scale && it.first == context.queries.window(scale, anchor).first
            }?.milliseconds
            // Life totals only overtime actually recorded, for everyone; the projected career never adds to it.
            if (scale == RecordsScale.LIFE && overtimeMs != null) OvertimeLine(text, overtimeMs)
            if (context.queries.authorized && profile == null && !device.lifeSetupPromptDismissed && scale == RecordsScale.MONTH) {
                LifeSetupCard(text, { editLife() }, { dismissLifeSetup() })
            }
            // A free user gets just this line, under the canvas or its locked placeholder.
            if (scale != RecordsScale.LIFE && scale != RecordsScale.WEEK && !context.queries.authorized && overtimeMs != null) OvertimeLine(text, overtimeMs)
            // As on iOS, a period without a summary shows none: locked, or nothing recorded yet.
            val headline = current?.headline
            if (scale != RecordsScale.LIFE && context.queries.authorized && current != null && headline != null) {
                RecordsPeriodCards(graph, context, current, selectedMonth ?: anchor.monthValue,
                    onOpenDay = { key -> open(Route.RecordsDay(key)) },
                    onPlanLeave = {
                        if (graph.records.state.value.leaveBalances.isEmpty()) open(Route.LeaveBalanceEdit(null, guided = true))
                        else open(Route.Leave(fromRecords = true))
                    }, onOpenMonth = { openMonth(it) })
            } else if (scale != RecordsScale.LIFE && context.queries.authorized && current != null) {
                RecordsEmptyPeriod(context.text, periodTitle(context, scale, current.first, current.last))
            }
            if (scale == RecordsScale.YEAR && !locked) {
                OpenMonthButton(text, LocalDate.of(anchor.year, month, 1)) { openMonth(month) }
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
            Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                if (!expanded) Header(graph, text, onAllRecords = { open(Route.RecordsAll) }) { note -> scope.launch { snackbar.showSnackbar(note) } }
                AdaptiveLayoutBox(Modifier.weight(1f).fillMaxWidth(), primaryFraction = .58f) { plan ->
                    val scrollLayout = when {
                        expanded -> RecordsScrollLayout.EXPANDED
                        plan.hasHorizontalFold -> RecordsScrollLayout.FOLD
                        plan.usesContentColumns -> RecordsScrollLayout.COLUMNS
                        else -> RecordsScrollLayout.SINGLE
                    }
                    val density = LocalDensity.current
                    RestoreRecordsScroll(scrollLayout, scrollRestoration, regularScroll, chartScroll, conclusionScroll, expandedScroll,
                        gap = with(density) { 14.dp.roundToPx() }, expandedInset = with(density) { DoneAtSpacing.page.roundToPx() },
                        contentKey = readingContentKey, contentReady = readingContentReady)
                    val measuredPicker: @Composable () -> Unit = {
                        Box(Modifier.fillMaxWidth().onSizeChanged { scrollRestoration.measure(scrollLayout, picker = it.height) }) {
                            ScalePicker(text, scale) { setScale(it) }
                        }
                    }
                    val measuredChart: @Composable () -> Unit = {
                        Box(Modifier.fillMaxWidth().onSizeChanged { scrollRestoration.measure(scrollLayout, chart = it.height) }) { chart() }
                    }
                    val measuredConclusion: @Composable () -> Unit = {
                        Box(Modifier.fillMaxWidth().onSizeChanged { scrollRestoration.measure(scrollLayout, conclusion = it.height) }) { conclusion(true) }
                    }
                    val padding = Modifier.padding(start = DoneAtSpacing.page, end = DoneAtSpacing.page,
                        bottom = DoneAtSpacing.xl + LocalDoneAtBottomBarPadding.current)
                    if (expanded) {
                        // A full chart remains one readable pane even when the physical display has a hinge.
                        val safe = if (plan.avoidedFold != null && plan.secondary != null) {
                            if (plan.primary.width * plan.primary.height >= plan.secondary.width * plan.secondary.height) plan.primary else plan.secondary
                        } else if (plan.avoidedFold != null) plan.primary else AdaptiveBounds(0f, 0f,
                            maxOf(plan.primary.right, plan.secondary?.right ?: 0f), plan.primary.bottom)
                        AdaptivePane(safe) {
                            Column(Modifier.fillMaxSize().verticalScroll(expandedScroll).then(padding).padding(top = DoneAtSpacing.page)) { measuredChart() }
                        }
                    } else if (plan.hasHorizontalFold) {
                        AdaptivePane(plan.primary) {
                            Column(Modifier.fillMaxSize().verticalScroll(chartScroll).then(padding), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                measuredPicker()
                                measuredChart()
                            }
                        }
                        AdaptivePane(plan.secondary!!, primary = false) {
                            Column(Modifier.fillMaxSize().verticalScroll(conclusionScroll).then(padding)) { measuredConclusion() }
                        }
                    } else if (plan.usesContentColumns) {
                        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Box(Modifier.padding(horizontal = DoneAtSpacing.page)) { measuredPicker() }
                            AdaptiveTwoPane(Modifier.weight(1f).fillMaxWidth(), primaryFraction = .58f,
                                primaryScroll = chartScroll, secondaryScroll = conclusionScroll,
                                primary = { Column(padding) { measuredChart() } },
                                secondary = { Column(padding) { measuredConclusion() } })
                        }
                    } else AdaptivePane(plan.primary) {
                        Column(Modifier.fillMaxSize().verticalScroll(regularScroll).then(padding), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            measuredPicker()
                            measuredChart()
                            measuredConclusion()
                        }
                    }
                }
            }
        }
        if (!expanded) SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).safeDrawingPadding().padding(bottom = LocalDoneAtBottomBarPadding.current))
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
            Icon(Icons.AutoMirrored.Outlined.ListAlt, text.string(R.string.recordsAllRecords), tint = MaterialTheme.colorScheme.primary)
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
    expanded: Boolean,
    shift: (Long) -> Unit,
    returnToToday: () -> Unit,
    onSelect: (RecordsDayCell) -> Unit,
    onOpen: (RecordsDayCell) -> Unit,
    onSelectMonth: (Int) -> Unit,
    onOpenMonth: (Int) -> Unit,
    onUnlock: () -> Unit,
    life: @Composable () -> Unit,
    onExpand: () -> Unit,
    onPinch: (Float) -> Unit,
    onPlanLeave: () -> Unit,
    onOpenReport: () -> Unit,
) {
    val text = context.text
    val (first, last) = context.queries.window(scale, anchor)
    val title = periodTitle(context, scale, first, last)
    val isLife = scale == RecordsScale.LIFE
    val showsToday = !isLife && (context.today.isBefore(first) || context.today.isAfter(last))
    val scheme = MaterialTheme.colorScheme
    RecordsCard {
        Column(Modifier.padding(18.dp).then(if (isLife) Modifier else Modifier.pointerInput(scale, selectedMonth, anchor) {
            awaitEachGesture {
                awaitFirstDown(requireUnconsumed = false)
                var zoom = 1f
                do {
                    val event = awaitPointerEvent()
                    if (event.changes.size >= 2) zoom *= event.calculateZoom()
                } while (event.changes.any { it.pressed })
                if (zoom > 1.22f || zoom < 0.82f) onPinch(zoom)
            }
        }), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // iOS 3.2.2: Life has no period to page through, so its card opens on the progress itself.
            if (!isLife) CappedFontScale {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (expanded) {
                        Text(title, Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleMedium)
                    } else {
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
                            DoneAtRollingText(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold))
                            if (showsToday) Icon(Icons.Outlined.MyLocation, null, Modifier.padding(start = 6.dp).size(14.dp), tint = scheme.primary)
                        }
                        if (!isLife) {
                            IconButton(onClick = { shift(1) }) {
                                Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, text.string(R.string.recordsNextPeriod), tint = scheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
            if (!isLife) HorizontalDivider(color = scheme.outlineVariant)
            val cells = page?.takeIf { it.first == first }?.cells
            if (locked) {
                RecordsLockedCalendar(scale, text)
                RecordsFreeWindowNote(text, onUnlock)
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
                val holidays = cells.filter { it.appearance != RecordsDayAppearance.LOCKED }.mapNotNull { cell ->
                    holidayDayAnnotation(context.lifeInputs.holidays, context.lifeInputs.archive.extendedSchedule?.takeIf { it.isEnabled }?.content?.holidayRegionIdentifier, cell.date, text.locale)?.let { cell.dayKey to it }
                }.toMap()
                if (scale == RecordsScale.YEAR) {
                    YearCanvas(cells, first.year, selectedMonth, false, text, onSelectMonth, onOpenMonth, holidays,
                        leadingBlanks = { context.queries.gridLeadingBlanks(it) })
                    // iOS 3.2.2: the selected month always reads out under the calendar.
                    RecordsSelectionRow(text.monthYear(LocalDate.of(first.year, selectedMonth, 1)),
                        recordsMonthDescription(cells.filter { it.date.monthValue == selectedMonth }, holidays, text)) { onOpenMonth(selectedMonth) }
                } else {
                    // iOS `selectedDayLook`: the tapped day, otherwise today when it is in view.
                    val selected = cells.firstOrNull { it.dayKey == selectedDayKey } ?: cells.firstOrNull { it.isToday }
                    if (scale == RecordsScale.WEEK) WeekStrips(cells, selected?.dayKey, text, onSelect, onOpen, holidays = holidays,
                        authorized = context.queries.authorized, overtimeMs = page?.recordedOvertimeMs)
                    else MonthGrid(cells, context.queries.gridLeadingBlanks(first),
                        weekdayLabels(text, context.queries.window(RecordsScale.WEEK, first).first), selected?.dayKey, text, onSelect, onOpen, holidays = holidays)
                }
                HolidayCoverageNotice(context.lifeInputs.holidays,
                    context.lifeInputs.archive.extendedSchedule?.takeIf { it.isEnabled }?.content?.holidayRegionIdentifier, first, last)
                if (scale != RecordsScale.YEAR) {
                    val selected = cells.firstOrNull { it.dayKey == selectedDayKey } ?: cells.firstOrNull { it.isToday }
                    // A locked day leads to the one Plus entry, as on iOS.
                    if (selected != null) RecordsSelectionRow(text.dayTitle(selected.date), recordsDayDescription(selected, holidays[selected.dayKey], text)) {
                        if (selected.appearance == RecordsDayAppearance.LOCKED) onUnlock() else onOpen(selected)
                    }
                }
                MarkLegend(includesLock = false, text = text, dots = scale == RecordsScale.YEAR,
                    showsHolidays = holidays.values.any { !it.isMakeupWorkday }, showsMakeup = holidays.values.any { it.isMakeupWorkday })
                if (!context.queries.authorized) RecordsFreeWindowNote(text, onUnlock)
            }
            if (scale == RecordsScale.MONTH) {
                Column {
                    RecordsActionEntry(text.string(R.string.leavePlanAction), Icons.Outlined.Luggage, onPlanLeave)
                    ReportEntry(scale, text, onOpenReport)
                }
            } else ReportEntry(scale, text, onOpenReport)
        }
    }
}

/**
 * Plan 020: actions belong to the chart window, alongside the leave planner.
 */
@Composable
private fun ReportEntry(scale: RecordsScale, text: RecordsText, onClick: () -> Unit) {
    RecordsActionEntry(text.string(when (scale) {
        RecordsScale.WEEK -> R.string.reportEntryWeek
        RecordsScale.YEAR -> R.string.reportEntryYear
        else -> R.string.reportEntryMonth
    }), Icons.Outlined.PlayCircleOutline, onClick)
}

@Composable
private fun RecordsActionEntry(title: String, icon: ImageVector, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Row(
        Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch).clip(MaterialTheme.shapes.small).clickable(role = Role.Button, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, null, Modifier.size(18.dp), tint = accent)
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = accent)
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** One loaded overtime total, kept with the revision and window it answers. */
private data class RecordedOvertime(val calculation: RecordsCalculationSnapshot, val scale: RecordsScale, val first: LocalDate, val milliseconds: Double?)

/**
 * Recorded overtime for the period as one line (iOS `RecordsOvertimeLine`).
 * Open to free users, so it is given the total alone and nothing it was made from.
 */
@Composable
internal fun OvertimeLine(text: RecordsText, milliseconds: Double) {
    RecordsCard {
        Box(Modifier.padding(horizontal = 16.dp, vertical = 14.dp)) {
            Metric(text.string(R.string.recordsOvertimeRecorded), text.duration(milliseconds))
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
