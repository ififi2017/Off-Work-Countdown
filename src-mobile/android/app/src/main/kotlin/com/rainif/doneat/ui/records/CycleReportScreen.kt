package com.rainif.doneat.ui.records

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Replay
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtMotion
import com.rainif.doneat.core.designsystem.DoneAtReportLayout
import com.rainif.doneat.core.designsystem.DoneAtReportPalette
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.timer.EarningsGate
import com.rainif.doneat.ui.timer.TimerText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.ZoneId

/** The full-screen report owns one query revision, one reference instant and a draw-only display clock. */
@Composable
fun CycleReportScreen(graph: AppGraph, route: Route.CycleReport, back: () -> Unit) {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val records = rememberRecordsContext(graph)
    val period = remember(route) { CycleReportPeriod(CycleReportKind.valueOf(route.kind), route.startDayKey, route.endDayKey, route.timeZoneIdentifier) }
    val authorized by graph.plus.authorized.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val preferences by graph.settings.preferences.collectAsStateWithLifecycle()
    var snapshot by remember(route) { mutableStateOf<CycleReportSnapshot?>(null) }
    var loaded by remember(route) { mutableStateOf(false) }
    LaunchedEffect(route, authorized) {
        if (authorized && !loaded) {
            val source = records
            snapshot = withContext(Dispatchers.Default) { source.queries.cycleReportSnapshot(period, source.nowMs) }
            loaded = true
        }
    }
    var includeIncome by remember(route) { mutableStateOf(!device.hideEarnings) }
    val text = remember(context, configuration, includeIncome, period) {
        TimerText(context.resources, configuration.locales[0], android.text.format.DateFormat.is24HourFormat(context), !includeIncome, ZoneId.of(period.timeZoneIdentifier))
    }
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val reason = stringResource(R.string.unlockSalaryReason)
    val noLock = stringResource(R.string.earningsShownWithoutLock)
    val motion = LocalDoneAtMotion.current
    val talkBack = rememberTouchExploration()
    var mode by rememberSaveable(route) { mutableStateOf("setup") }
    val static = mode == "reading" || motion.reduced || talkBack
    var player by remember(route) { mutableStateOf(CycleReportPlayer()) }
    // Frames invalidate the artwork and progress strip only, not headings or the screen.
    val elapsed = remember(route) { mutableLongStateOf(0L) }
    val clock = remember(elapsed) { { elapsed.longValue } }
    fun current() = player.copy(elapsedMs = elapsed.longValue)
    fun setPlayer(next: CycleReportPlayer) { elapsed.longValue = next.elapsedMs; player = next }
    fun play() { setPlayer(player.replay()); mode = "playing" }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var foreground by remember(lifecycle) { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            foreground = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            if (event == Lifecycle.Event.ON_PAUSE) setPlayer(current().hold(false).copy(userPaused = true))
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val report = remember(snapshot, includeIncome) { snapshot?.let { if (includeIncome) it else it.withoutIncome() } }
    val chapters = remember(report, text, records.text, context) { report?.let { reportChapters(it, text, records.text, context, records.queries.firstDayOfWeek) }.orEmpty() }
    val count = chapters.size
    LaunchedEffect(player.paused, foreground, static, mode, count) {
        if (count == 0 || player.paused || !foreground || static || mode != "playing") return@LaunchedEffect
        var previous = withFrameNanos { it }
        var remainder = 0L
        while (true) {
            val frame = withFrameNanos { it }
            val nanos = frame - previous + remainder
            val delta = (nanos / 1_000_000).coerceIn(0L, DoneAtMotion.REPORT_MAX_FRAME_MS.toLong())
            remainder = nanos % 1_000_000
            previous = frame
            val next = current().advance(delta, count)
            elapsed.longValue = next.elapsedMs
            if (next.chapter != player.chapter || next.finished != player.finished) player = next
        }
    }
    val title = stringResource(when (period.kind) {
        CycleReportKind.WEEK -> R.string.reportWeekly
        CycleReportKind.MONTH -> R.string.reportMonthly
        CycleReportKind.YEAR -> R.string.reportYearly
    })
    val dateTitle = remember(period, records.text) { when (period.kind) {
        CycleReportKind.YEAR -> java.text.NumberFormat.getIntegerInstance(text.locale).apply { isGroupingUsed = false }.format(period.startDate.year)
        CycleReportKind.MONTH -> records.text.monthYear(period.startDate)
        CycleReportKind.WEEK -> records.text.monthDay(period.startDate) + " – " + records.text.monthDay(period.endDate)
    } }
    CompositionLocalProvider(LocalContentColor provides DoneAtReportPalette.ink) {
        Box(Modifier.fillMaxSize()) {
            ReportBackdrop(if (mode == "playing" && count > 0) chapters[player.chapter.coerceIn(0, count - 1)].artKind else ReportArtKind.TIME, energized = mode == "playing" && player.chapter == 1)
            Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = DoneAtReportLayout.page).padding(top = DoneAtSpacing.s, bottom = DoneAtSpacing.l)) {
                if (mode == "playing" && !static && report?.hasData == true && authorized) {
                    val index = player.chapter.coerceIn(0, count - 1)
                    ReportProgress(index, count, clock)
                    ReportHeader("$title · $dateTitle", back)
                    val direction = LocalLayoutDirection.current
                    val chapter = chapters[index]
                    BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().pointerInput(count, direction) {
                        detectTapGestures(
                            onPress = { try { tryAwaitRelease() } finally { setPlayer(current().hold(false)) } },
                            onLongPress = { setPlayer(current().hold(true)) },
                            onTap = { at ->
                                val forward = (at.x >= size.width / 2f) == (direction == LayoutDirection.Ltr)
                                setPlayer(current().navigate(if (forward) 1 else -1, count))
                            },
                        )
                    }) {
                        val scrollStage = configuration.fontScale >= 1.5f || maxHeight < 450.dp
                        val artHeight = if (scrollStage) DoneAtReportLayout.compactArtHeight else minOf(DoneAtReportLayout.artHeight, maxHeight * .62f)
                        Column((if (scrollStage) Modifier.verticalScroll(rememberScrollState()) else Modifier.fillMaxHeight()).fillMaxWidth().padding(top = DoneAtReportLayout.stageTop), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                            StoryHeading(chapter, index == 0)
                            if (scrollStage) Spacer(Modifier.height(DoneAtSpacing.l)) else Spacer(Modifier.weight(1f))
                            ReportArtwork(chapter, clock, index, Modifier.fillMaxWidth().height(artHeight))
                            if (index == 0 && !chapter.isYear) ReportLegend()
                            StoryCaption(chapter)
                            Spacer(Modifier.height(DoneAtSpacing.s))
                        }
                    }
                    FlowRow(Modifier.fillMaxWidth().padding(top = DoneAtSpacing.l), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                        ReportControl(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, stringResource(R.string.reportPrevious), index > 0) { setPlayer(current().navigate(-1, count)) }
                        ReportControl(if (player.finished) Icons.Outlined.Replay else if (player.paused) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                            stringResource(if (player.finished) R.string.reportReplay else if (player.paused) R.string.reportResume else R.string.reportPause)) {
                            setPlayer(if (player.finished) player.replay() else current().toggle())
                        }
                        ReportControl(Icons.AutoMirrored.Outlined.KeyboardArrowRight, stringResource(R.string.reportNext), index < count - 1) { setPlayer(current().navigate(1, count)) }
                        FilledTonalButton(onClick = { setPlayer(current().copy(userPaused = true)); mode = "reading" }, colors = ButtonDefaults.filledTonalButtonColors(containerColor = DoneAtReportPalette.control, contentColor = DoneAtReportPalette.ink)) {
                            Icon(Icons.AutoMirrored.Outlined.ListAlt, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(DoneAtSpacing.s))
                            Text(stringResource(R.string.reportRead))
                        }
                    }
                } else if (static && authorized && report?.hasData == true) {
                    ReportHeader(title, back)
                    Text(dateTitle, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = DoneAtReportPalette.cream)
                    if (!motion.reduced && !talkBack) TextButton(onClick = { play() }, colors = ButtonDefaults.textButtonColors(contentColor = DoneAtReportPalette.cream)) { Text(stringResource(R.string.reportPlay)) }
                    ReportReading(report, text, records.text, chapters, Modifier.weight(1f))
                } else {
                    val scrollSetup = configuration.fontScale >= 1.5f || configuration.screenHeightDp <= 650
                    Column(Modifier.weight(1f).fillMaxWidth().let { if (scrollSetup) it.verticalScroll(rememberScrollState()) else it }) {
                    ReportHeader(title, back)
                    Text(dateTitle, Modifier.padding(top = DoneAtReportLayout.stageTop).semantics { heading() }, fontSize = DoneAtReportLayout.setupHero, lineHeight = DoneAtReportLayout.setupHero, fontWeight = FontWeight.ExtraBold, color = DoneAtReportPalette.cream)
                    if (report?.isInProgress == true) Text(stringResource(R.string.reportSoFar), Modifier.padding(top = DoneAtSpacing.s), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.titleMedium)
                    Box((if (scrollSetup) Modifier.height(DoneAtReportLayout.teaserHeight).padding(vertical = DoneAtSpacing.l) else Modifier.weight(1f)).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        if (report?.hasData == true && authorized) ReportArtwork(chapters.first(), { CycleReportPlayer.CHAPTER_MS }, 0, Modifier.fillMaxWidth().height(DoneAtReportLayout.teaserHeight), teaser = true)
                        else if (!loaded && authorized) CircularProgressIndicator(color = DoneAtReportPalette.cream)
                    }
                    if (authorized && report?.hasData == true && preferences.salaryEnabled) {
                        Surface(color = DoneAtReportPalette.control, shape = RoundedCornerShape(DoneAtReportLayout.readingCardRadius)) {
                        Column(Modifier.padding(DoneAtSpacing.l)) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.reportIncludeIncome), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                            Switch(checked = includeIncome, onCheckedChange = { wanted ->
                                if (!wanted) includeIncome = false
                                else scope.launch {
                                    when (EarningsGate.confirmOwner(context, reason)) {
                                        EarningsGate.Result.CONFIRMED -> includeIncome = true
                                        EarningsGate.Result.NO_LOCK -> { includeIncome = true; snackbar.showSnackbar(noLock) }
                                        EarningsGate.Result.REFUSED -> Unit
                                    }
                                }
                            }, colors = SwitchDefaults.colors(checkedTrackColor = DoneAtReportPalette.orange, checkedThumbColor = DoneAtReportPalette.cream))
                        }
                        Text(stringResource(R.string.reportIncludeIncomeNote), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.bodySmall)
                        }
                        }
                        Spacer(Modifier.height(DoneAtSpacing.l))
                    }
                    val ready = authorized && report?.hasData == true
                    if (!ready && (loaded || !authorized)) Text(stringResource(if (!authorized) R.string.plusReportsLocked else if (report == null) R.string.reportUnavailable else R.string.reportEmpty), Modifier.padding(bottom = DoneAtSpacing.l), color = DoneAtReportPalette.muted)
                    Button(onClick = { play() }, enabled = ready, modifier = Modifier.fillMaxWidth().heightIn(min = DoneAtReportLayout.controlSize), colors = ButtonDefaults.buttonColors(containerColor = DoneAtReportPalette.orange, contentColor = DoneAtReportPalette.ink)) {
                        Icon(Icons.Outlined.PlayArrow, null)
                        Spacer(Modifier.width(DoneAtSpacing.s))
                        Text(stringResource(R.string.reportPlay), fontWeight = FontWeight.Bold)
                    }
                    FilledTonalButton(onClick = { mode = "reading" }, enabled = ready, modifier = Modifier.fillMaxWidth().padding(top = DoneAtSpacing.s).heightIn(min = DoneAtReportLayout.controlSize), colors = ButtonDefaults.filledTonalButtonColors(containerColor = DoneAtReportPalette.control, contentColor = DoneAtReportPalette.ink)) { Text(stringResource(R.string.reportRead), fontWeight = FontWeight.SemiBold) }
                    }
                }
            }
            SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).safeDrawingPadding())
        }
    }
}

@Composable
private fun ReportHeader(title: String, close: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = DoneAtSpacing.s), verticalAlignment = Alignment.CenterVertically) {
        Text(title.uppercase(), Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, color = DoneAtReportPalette.muted, fontWeight = FontWeight.Bold)
        ReportControl(Icons.Outlined.Close, stringResource(R.string.close), action = close)
    }
}

@Composable
private fun ReportControl(icon: ImageVector, label: String, enabled: Boolean = true, action: () -> Unit) {
    IconButton(onClick = action, enabled = enabled, modifier = Modifier.size(DoneAtReportLayout.controlSize).background(DoneAtReportPalette.control, CircleShape)) {
        Icon(icon, label, tint = if (enabled) DoneAtReportPalette.ink else DoneAtReportPalette.muted.copy(alpha = .3f))
    }
}

internal enum class ReportArtKind { TIME, OVERTIME, REST, FOCUS, BASELINE, PAY, AHEAD, SUMMARY }
internal data class ReportChapter(val title: String, val metric: String, val lines: List<String>, val bars: List<Pair<String, Long>> = emptyList(), val restRange: IntRange? = null, val restCalendar: Boolean = false, val calendarLeading: Int = 0, val cellLabels: List<String> = emptyList(), val artKind: ReportArtKind = ReportArtKind.TIME, val isYear: Boolean = false, val restIndices: Set<Int> = emptySet(), val overtimeIndices: Set<Int> = emptySet(), val axisLabels: List<String> = emptyList(), val centerLabel: String? = null, val centerValue: String? = null, val overtimeShares: List<Float> = emptyList())

@Composable
private fun StoryHeading(chapter: ReportChapter, opening: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        Text(chapter.title.uppercase(), Modifier.semantics { heading() }, color = DoneAtReportPalette.muted, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
        val metric = remember(chapter.metric, opening) {
            buildAnnotatedString {
                val parts = Regex("[\\p{N}.,]+|[^\\p{N}.,]+").findAll(chapter.metric)
                parts.forEach { part ->
                    val numeric = part.value.any { it.isDigit() }
                    withStyle(SpanStyle(fontSize = if (opening) DoneAtReportLayout.storyHeadline else if (numeric) DoneAtReportLayout.storyHero else DoneAtReportLayout.unitSize, fontWeight = FontWeight.ExtraBold)) { append(part.value) }
                }
            }
        }
        if (chapter.metric.isNotEmpty()) Text(metric, color = DoneAtReportPalette.ink, lineHeight = if (opening) DoneAtReportLayout.storyHeadline else DoneAtReportLayout.storyHero)
        if (chapter.lines.isNotEmpty()) Text(chapter.lines.first(), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun StoryCaption(chapter: ReportChapter) {
    chapter.lines.drop(1).forEach { Text(it, color = DoneAtReportPalette.cream, style = MaterialTheme.typography.bodyLarge) }
}
@Composable
private fun rememberTouchExploration(): Boolean {
    val context = LocalContext.current
    val manager = remember(context) { context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager }
    var enabled by remember(manager) { mutableStateOf(manager.isTouchExplorationEnabled) }
    DisposableEffect(manager) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { enabled = it }
        manager.addTouchExplorationStateChangeListener(listener)
        onDispose { manager.removeTouchExplorationStateChangeListener(listener) }
    }
    return enabled
}

/** Presentation formats facts already built by RecordsQueries; it never totals records. */
private fun reportChapters(report: CycleReportSnapshot, text: TimerText, dates: RecordsText, context: Context, firstDayOfWeek: java.time.DayOfWeek): List<ReportChapter> = buildList {
    val res = context.resources
    fun title(id: Int) = res.getString(id)
    fun formatted(id: Int, vararg values: String) = res.getString(id, *values)
    fun duration(ms: Long) = text.relativeDuration(ms.toDouble())
    val calendarLeading = (report.period.startDate.dayOfWeek.value - firstDayOfWeek.value + 7) % 7
    val cellLabels = if (report.period.kind == CycleReportKind.YEAR) report.months.map { dates.shortMonth(it.period.startDate) }
        else report.days.map { text.count(it.date.dayOfMonth) }
    val year = report.period.kind == CycleReportKind.YEAR
    val restIndices = report.days.mapIndexedNotNull { index, day -> index.takeIf { day.kind == CycleReportDayKind.REST } }.toSet()
    val overtimeShares = if (year) report.months.map { if (it.figures.workedMs > 0) (it.figures.overtimeMs.toFloat() / it.figures.workedMs).coerceIn(0f, 1f) else 0f }
        else report.days.map { val total = it.workMs + it.overtimeMs; if (total > 0) (it.overtimeMs.toFloat() / total).coerceIn(0f, 1f) else 0f }
    val overtimeIndices = report.days.mapIndexedNotNull { index, day -> index.takeIf { day.overtimeMs > 0 } }.toSet()
    val axisLabels = if (year) report.months.map { text.count(it.period.startDate.monthValue) } else if (report.period.kind == CycleReportKind.WEEK) report.days.map { dates.weekdayNarrow(it.date) } else emptyList()
    val daily = report.days.map { dates.dayTitle(it.dayKey) + " · " + duration(it.workMs + it.overtimeMs) to it.workMs + it.overtimeMs }
    val workBars = if (report.period.kind == CycleReportKind.YEAR) report.months.map { dates.shortMonth(it.period.startDate) + " · " + duration(it.figures.workedMs) to it.figures.workedMs } else daily
    val headline = when {
        report.isInProgress -> title(R.string.reportHeadlineInProgress)
        report.restDayCount > 0 -> formatted(R.string.reportHeadlineRoom, text.count(report.restDayCount))
        report.figures.overtimeMs > 0 -> formatted(R.string.reportHeadlineOvertime, duration(report.figures.overtimeMs))
        else -> title(R.string.reportHeadlinePlain)
    }
    add(ReportChapter(title(R.string.reportWorkdays) + " · " + text.count(report.figures.workdays), headline,
        if (report.isInProgress) listOf(title(R.string.reportSoFar)) else emptyList(), workBars,
        calendarLeading = calendarLeading, cellLabels = cellLabels, isYear = year, restIndices = restIndices, overtimeIndices = overtimeIndices, axisLabels = axisLabels, overtimeShares = overtimeShares))
    add(ReportChapter(title(R.string.recordsWorkedTime), duration(report.figures.workedMs), listOf(
        formatted(R.string.reportIncludingOvertime, duration(report.figures.overtimeMs)),
    ), workBars, calendarLeading = calendarLeading, cellLabels = cellLabels, isYear = year, restIndices = restIndices, overtimeIndices = overtimeIndices, axisLabels = axisLabels, overtimeShares = overtimeShares))
    report.baseline?.let { baseline ->
        val statement = when {
            baseline.deltaMs > 0 -> formatted(R.string.reportUsualMore, duration(baseline.deltaMs))
            baseline.deltaMs < 0 -> formatted(R.string.reportUsualLess, duration(-baseline.deltaMs))
            else -> title(R.string.reportUsualSame)
        }
        add(ReportChapter(title(if (report.period.kind == CycleReportKind.WEEK) R.string.reportUsualWeek else R.string.reportUsualMonth), duration(kotlin.math.abs(baseline.deltaMs)), listOf(
            statement,
            formatted(if (report.period.kind == CycleReportKind.WEEK) R.string.reportUsualBasisWeek else R.string.reportUsualBasisMonth, text.count(baseline.periods)),
        ), bars = listOf(title(if (report.period.kind == CycleReportKind.WEEK) R.string.reportUsualWeek else R.string.reportUsualMonth) + " · " + duration(baseline.baselineWorkedMs) to baseline.baselineWorkedMs, title(R.string.recordsWorkedTime) + " · " + duration(report.figures.workedMs) to report.figures.workedMs), artKind = ReportArtKind.BASELINE))
    }
    add(ReportChapter(title(R.string.overtime), duration(report.figures.overtimeMs), buildList {
        add(formatted(R.string.reportOvertimeDays, text.count(report.overtime?.dayCount ?: 0)))
        report.overtime?.longestDay?.let { add(formatted(R.string.reportOvertimePeak, dates.dayTitle(it.dayKey), duration(it.overtimeMs))) }
    }, if (year) report.months.map { dates.shortMonth(it.period.startDate) + " · " + duration(it.figures.overtimeMs) to it.figures.overtimeMs } else report.days.map { dates.dayTitle(it.dayKey) + " · " + duration(it.overtimeMs) to it.overtimeMs }, artKind = ReportArtKind.OVERTIME, isYear = year, axisLabels = axisLabels))
    val restStart = report.longestRestStart
    val restRange = restStart?.let { it until it + report.longestRestRun }
    add(ReportChapter(title(R.string.reportRestDays), text.days(report.restDayCount.toDouble()), buildList {
        add(title(R.string.reportLongestRest) + " · " + text.days(report.longestRestRun.toDouble()))
        if (restStart != null && report.longestRestRun > 0) {
            add(dates.dayTitle(report.days[restStart].dayKey) + " – " + dates.dayTitle(report.days[restStart + report.longestRestRun - 1].dayKey))
        }
        add(title(R.string.reportLeaveUsed) + " · " + text.days(report.leaveUsedHalfDays / 2.0))
    }, if (year) report.months.map { dates.shortMonth(it.period.startDate) + " · " + text.days(it.restDayCount.toDouble()) to it.restDayCount.toLong() } else daily, restRange, restCalendar = !year, calendarLeading = calendarLeading, cellLabels = cellLabels, artKind = ReportArtKind.REST, isYear = year, restIndices = restIndices, axisLabels = axisLabels))
    report.focus?.let { focus ->
        add(ReportChapter(title(R.string.reportFocusRounds), text.count(focus.rounds), buildList {
            if (focus.bestDayIndex in report.days.indices && focus.bestDayIndex in focus.perDay.indices) add(formatted(R.string.reportFocusBest, dates.dayTitle(report.days[focus.bestDayIndex].dayKey), text.count(focus.perDay[focus.bestDayIndex])))
            add(title(R.string.reportFocusDuration) + " · " + duration(focus.focusedMs))
        }, if (year) report.months.map { dates.shortMonth(it.period.startDate) + " · " + text.count(it.focusRounds) to it.focusRounds.toLong() } else report.days.mapIndexed { index, day -> dates.dayTitle(day.dayKey) + " · " + text.count(focus.perDay.getOrElse(index) { 0 }) to focus.perDay.getOrElse(index) { 0 }.toLong() }, artKind = ReportArtKind.FOCUS, isYear = year, axisLabels = axisLabels))
    }
    report.pay?.let { pay ->
        add(ReportChapter(title(R.string.reportIncomeTitle), "", buildList {
            add(title(R.string.reportIncomeTotal) + " · " + text.money(pay.total))
            pay.perHour?.let { add(title(R.string.reportPerHour) + " · " + text.money(it)) }
            pay.overtimeExtra?.let { add(title(R.string.reportIncomeExtra) + " · " + text.money(it)) }
            add(title(R.string.reportIncomeNote))
        }, artKind = ReportArtKind.PAY, centerLabel = title(if (pay.perHour != null) R.string.reportPerHour else R.string.reportIncomeTitle), centerValue = text.money(pay.perHour ?: pay.total)))
    }
    report.ahead?.let { ahead ->
        val next = ahead.nextBreak
        add(ReportChapter(title(if (ahead.isHistorical) R.string.reportAheadHistoricalTitle else R.string.reportAheadTitle), next?.let { text.days(it.length.toDouble()) } ?: title(R.string.reportLeaveUsed), buildList {
            if (next != null) add(dates.dayTitle(next.startDayKey) + " – " + dates.dayTitle(next.endDate))
            add(title(R.string.reportLeaveUsed) + " · " + text.days(ahead.leaveUsedHalfDays / 2.0))
            ahead.leaveRemainingHalfDays?.let { add(title(R.string.reportLeaveLeft) + " · " + text.days(it / 2.0)) }
        }, bars = ahead.horizon.mapIndexed { index, rest -> text.count(index + 1) to if (rest) 1L else 0L }, artKind = ReportArtKind.AHEAD, restRange = next?.let { (it.daysAway - 1) until (it.daysAway - 1 + it.length) }))
    }
    if (report.months.isNotEmpty()) {
        add(ReportChapter(title(R.string.reportMonthlyTrend), duration(report.figures.workedMs), emptyList(), report.months.map { month ->
            val date = month.period.startDate
            val label = buildList {
                add(dates.shortMonth(date))
                add(duration(month.figures.workedMs))
                add(title(R.string.overtime) + " " + duration(month.figures.overtimeMs))
                month.figures.income?.let { add(title(R.string.reportIncomeTitle) + " " + text.money(it)) }
            }.joinToString(" · ")
            label to month.figures.workedMs
        }, artKind = ReportArtKind.SUMMARY, isYear = true, axisLabels = axisLabels))
    }
}

@Composable
private fun ReportReading(report: CycleReportSnapshot, text: TimerText, dates: RecordsText, chapters: List<ReportChapter>, modifier: Modifier) {
    val context = LocalContext.current
    val rows = remember(report, text, dates, context) {
        val res = context.resources
        fun t(id: Int) = res.getString(id)
        buildList<Pair<String, String>> {
            add(t(R.string.reportWorkdays) to text.count(report.figures.workdays))
            add(t(R.string.recordsWorkedTime) to text.relativeDuration(report.figures.workedMs.toDouble()))
            add(t(R.string.overtime) to text.relativeDuration(report.figures.overtimeMs.toDouble()))
            add(t(R.string.reportRestDays) to text.days(report.restDayCount.toDouble()))
            add(t(R.string.reportLongestRest) to text.days(report.longestRestRun.toDouble()))
            add(t(R.string.reportLeaveUsed) to text.days(report.leaveUsedHalfDays / 2.0))
            report.baseline?.let { baseline ->
                add(t(if (report.period.kind == CycleReportKind.WEEK) R.string.reportUsualWeek else R.string.reportUsualMonth) to res.getString(
                    if (baseline.deltaMs < 0) R.string.reportUsualLess else if (baseline.deltaMs > 0) R.string.reportUsualMore else R.string.reportUsualSame,
                    text.relativeDuration(kotlin.math.abs(baseline.deltaMs).toDouble()),
                ))
            }
            report.ahead?.nextBreak?.let { next -> add(t(if (report.ahead?.isHistorical == true) R.string.reportAheadHistoricalTitle else R.string.reportAheadTitle) to "${text.days(next.length.toDouble())} · ${dates.monthDay(next.startDate)} – ${dates.monthDay(next.endDate)}") }
            report.focus?.let { focus ->
                add(t(R.string.reportFocusRounds) to text.count(focus.rounds))
                add(t(R.string.reportFocusDuration) to text.relativeDuration(focus.focusedMs.toDouble()))
            }
            report.pay?.let { add(t(R.string.reportIncomeTitle) to text.money(it.total)) }
        }
    }
    Column(modifier.verticalScroll(rememberScrollState()).padding(top = DoneAtSpacing.xl), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xl)) {
        if (report.isInProgress) Text(stringResource(R.string.reportSoFar), color = DoneAtReportPalette.muted)
        Surface(modifier = Modifier.fillMaxWidth(), color = DoneAtReportPalette.control, shape = RoundedCornerShape(DoneAtReportLayout.readingCardRadius)) {
            Column(Modifier.padding(horizontal = DoneAtSpacing.l)) {
                rows.forEachIndexed { index, (label, value) ->
                    Row(Modifier.fillMaxWidth().padding(vertical = DoneAtSpacing.l), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalAlignment = Alignment.Top) {
                        Text(label, Modifier.weight(1f), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.bodyLarge)
                        Text(value, Modifier.weight(1f), color = DoneAtReportPalette.ink, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, textAlign = androidx.compose.ui.text.style.TextAlign.End)
                    }
                    if (index != rows.lastIndex) HorizontalDivider(color = DoneAtReportPalette.track)
                }
            }
        }
        if (report.months.isNotEmpty()) {
            Surface(modifier = Modifier.fillMaxWidth(), color = DoneAtReportPalette.control, shape = RoundedCornerShape(DoneAtReportLayout.readingCardRadius)) {
                Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    Text(stringResource(R.string.reportMonthlyTrend), fontWeight = FontWeight.Bold, color = DoneAtReportPalette.ink)
                    report.months.forEach { month ->
                        Text(dates.monthYear(month.period.startDate), Modifier.padding(top = DoneAtSpacing.m).semantics { heading() }, fontWeight = FontWeight.SemiBold, color = DoneAtReportPalette.cream)
                        Text(stringResource(R.string.recordsWorkedTime) + " · " + text.relativeDuration(month.figures.workedMs.toDouble()), color = DoneAtReportPalette.muted)
                        Text(stringResource(R.string.overtime) + " · " + text.relativeDuration(month.figures.overtimeMs.toDouble()), color = DoneAtReportPalette.muted)
                        Text(stringResource(R.string.reportRestDays) + " · " + text.days(month.restDayCount.toDouble()), color = DoneAtReportPalette.muted)
                        if (month.focusRounds > 0) Text(stringResource(R.string.reportFocusRounds) + " · " + text.count(month.focusRounds), color = DoneAtReportPalette.muted)
                        month.figures.income?.let { Text(stringResource(R.string.reportIncomeTitle) + " · " + text.money(it), color = DoneAtReportPalette.muted) }
                    }
                }
            }
        } else {
            Surface(modifier = Modifier.fillMaxWidth(), color = DoneAtReportPalette.control, shape = RoundedCornerShape(DoneAtReportLayout.readingCardRadius)) {
                ReportArtwork(chapters.first(), { CycleReportPlayer.CHAPTER_MS }, 0, Modifier.fillMaxWidth().height(DoneAtReportLayout.artHeight).padding(DoneAtSpacing.l))
            }
        }
        // Detailed values keep all chart facts available to readers and TalkBack.
        chapters.filter { it.artKind == ReportArtKind.REST || it.artKind == ReportArtKind.OVERTIME || it.artKind == ReportArtKind.FOCUS || it.artKind == ReportArtKind.PAY || it.artKind == ReportArtKind.AHEAD }.forEach { chapter ->
            Surface(modifier = Modifier.fillMaxWidth(), color = DoneAtReportPalette.control, shape = RoundedCornerShape(DoneAtReportLayout.readingCardRadius)) {
                Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    Text(chapter.title, Modifier.semantics { heading() }, fontWeight = FontWeight.Bold, color = DoneAtReportPalette.ink)
                    chapter.lines.forEach { Text(it, color = DoneAtReportPalette.muted) }
                    if (report.months.isEmpty() && chapter.artKind != ReportArtKind.REST) chapter.bars.forEach { (label, _) -> Text(label, color = DoneAtReportPalette.muted) }
                }
            }
        }
        Text(stringResource(R.string.reportBasisNote), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun ReportLegend() {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
        listOf(DoneAtReportPalette.orange to R.string.recordsWorkRegular, DoneAtReportPalette.hot to R.string.overtime, DoneAtReportPalette.muted to R.string.recordsRestDay).forEach { (color, key) ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                Box(Modifier.size(DoneAtSpacing.s).background(color, CircleShape))
                Text(stringResource(key), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}
