package com.rainif.doneat.ui.records

import android.content.Context
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import com.rainif.doneat.core.designsystem.DoneAtReportMotion as ReportEase
import kotlinx.coroutines.delay
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
fun CycleReportScreen(graph: AppGraph, route: Route.CycleReport, back: () -> Unit, unlock: () -> Unit) {
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
    var mode by remember(route) { mutableStateOf("setup") }
    val static = mode == "reading"
    var player by remember(route) { mutableStateOf(CycleReportPlayer()) }
    // Only drawing and counted text consume frames; the screen and statistics do not.
    val elapsed = remember(route) { mutableLongStateOf(0L) }
    val clock = remember(elapsed) { { elapsed.longValue } }
    val totalElapsed = remember(route) { mutableLongStateOf(0L) }
    val drift = remember(totalElapsed) { { totalElapsed.longValue } }
    var previousChapter by remember(route) { mutableStateOf<Int?>(null) }
    val teaserElapsed = remember(route) { mutableLongStateOf(0L) }
    val teaserClock = remember(teaserElapsed) { { teaserElapsed.longValue } }
    val haptic = LocalHapticFeedback.current
    fun current() = player.copy(elapsedMs = elapsed.longValue, clockMs = totalElapsed.longValue)
    fun setPlayer(next: CycleReportPlayer) {
        if (next.chapter != player.chapter) {
            previousChapter = if (next.userPaused) null else player.chapter
            haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
        }
        elapsed.longValue = next.elapsedMs
        totalElapsed.longValue = next.clockMs
        player = next
    }
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
    val timelines = remember(chapters) { chapters.map { it.timeline } }
    LaunchedEffect(motion.reduced, talkBack) {
        if ((motion.reduced || talkBack) && mode == "playing") { setPlayer(current().copy(userPaused = true, held = false)); mode = "reading" }
    }
    LaunchedEffect(report, mode, motion.reduced, talkBack, foreground) {
        if (mode != "setup" || report?.hasData != true || !foreground) return@LaunchedEffect
        if (motion.reduced || talkBack) { teaserElapsed.longValue = DoneAtMotion.REPORT_TEASER_BUILD_MS; return@LaunchedEffect }
        delay(DoneAtMotion.REPORT_TEASER_DELAY_MS)
        var previous = withFrameNanos { it }
        while (teaserElapsed.longValue < DoneAtMotion.REPORT_TEASER_BUILD_MS) {
            val next = withFrameNanos { it }
            teaserElapsed.longValue += ((next - previous) / 1_000_000).coerceIn(0, DoneAtMotion.REPORT_MAX_FRAME_MS.toLong())
            previous = next
        }
    }
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
            val next = current().advance(delta, timelines)
            elapsed.longValue = next.elapsedMs
            totalElapsed.longValue = next.clockMs
            if (next.chapter != player.chapter || next.finished != player.finished) setPlayer(next)
            if (next.finished) break
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
            ReportBackdrop(if (mode == "playing" && count > 0 && !static) chapters[player.chapter.coerceIn(0, count - 1)].stage else if (static) ReportStage.SUMMARY else ReportStage.CALENDAR,
                previousChapter?.let { chapters.getOrNull(it)?.stage }.takeIf { mode == "playing" && !static }, clock, if (mode == "playing") drift else { { 0L } })
            AnimatedContent(targetState = if (static) "reading" else mode, transitionSpec = {
                fadeIn(tween(if (motion.reduced) 0 else DoneAtMotion.STATE_ENTER_MS,
                    delayMillis = if (motion.reduced) 0 else DoneAtMotion.STATE_EXIT_MS, easing = motion.emphasizedDecelerate)) togetherWith
                    fadeOut(tween(if (motion.reduced) 0 else DoneAtMotion.STATE_EXIT_MS, easing = motion.emphasizedDecelerate))
            }, label = "report mode") { displayMode ->
            Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = DoneAtReportLayout.page).padding(top = DoneAtSpacing.s, bottom = DoneAtSpacing.l)) {
                if (displayMode == "playing" && report?.hasData == true && authorized) {
                    val index = player.chapter.coerceIn(0, count - 1)
                    ReportProgress(index, timelines, clock)
                    ReportHeader("$title · $dateTitle", back)
                    val direction = LocalLayoutDirection.current
                    val chapter = chapters[index]
                    BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().pointerInput(count, direction) {
                        detectTapGestures(
                            onPress = { setPlayer(current().hold(true)); try { tryAwaitRelease() } finally { setPlayer(current().hold(false)) } },
                            onLongPress = { setPlayer(current().hold(true)) },
                            onTap = { at ->
                                val forward = (at.x >= size.width / 2f) == (direction == LayoutDirection.Ltr)
                                setPlayer(current().navigate(if (forward) 1 else -1, timelines))
                            },
                        )
                    }) {
                        val scrollStage = configuration.fontScale >= 1.5f || maxHeight < 450.dp
                        val finale = chapter.stage == ReportStage.SUMMARY
                        val artHeight = if (scrollStage) DoneAtReportLayout.compactArtHeight else minOf(DoneAtReportLayout.artHeight, maxHeight * if (finale) .43f else .55f)
                        Column((if (scrollStage) Modifier.verticalScroll(rememberScrollState()) else Modifier.fillMaxHeight()).fillMaxWidth().padding(top = DoneAtReportLayout.stageTop), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                            StoryHeading(chapter, clock)
                            if (scrollStage) Spacer(Modifier.height(DoneAtSpacing.l)) else Spacer(Modifier.weight(1f))
                            if (finale && (chapter.isYear || chapter.isWeek)) {
                                Text(chapter.centerValue.orEmpty(), color = DoneAtReportPalette.ink, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                                Text(chapter.centerLabel.orEmpty(), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.labelLarge)
                            }
                            ReportArtwork(chapter, clock, Modifier.fillMaxWidth().height(artHeight), drift = drift)
                            if (index <= 1 && !chapter.isYear) {
                                Box(Modifier.height(30.dp).graphicsLayer { alpha = if (index == 0) ReportEase.window(chapter.timeline.build(clock()), .7f, 1f) else 0f }) {
                                    ReportLegend(report.figures.overtimeMs > 0)
                                }
                            }
                            if (finale) {
                                SummaryFacts(chapter, clock)
                                Row(Modifier.fillMaxWidth().reportReveal(chapter, clock, .55f, 1f), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                                    FilledTonalButton(onClick = { play() }, modifier = Modifier.weight(1f), colors = ButtonDefaults.filledTonalButtonColors(containerColor = DoneAtReportPalette.control, contentColor = DoneAtReportPalette.ink)) { Text(stringResource(R.string.reportReplay)) }
                                    Button(onClick = back, modifier = Modifier.weight(1f), colors = ButtonDefaults.buttonColors(containerColor = DoneAtReportPalette.cream, contentColor = DoneAtReportPalette.plum)) { Text(stringResource(R.string.done)) }
                                }
                            }
                            Spacer(Modifier.height(DoneAtSpacing.s))
                        }
                    }
                    val finaleBuilt by remember(chapters, player.chapter) { derivedStateOf { chapters[player.chapter].stage == ReportStage.SUMMARY && chapters[player.chapter].timeline.build(clock()) >= 1f } }
                    if (finaleBuilt) Spacer(Modifier.fillMaxWidth().height(DoneAtReportLayout.controlSize + DoneAtSpacing.l))
                    else FlowRow(Modifier.fillMaxWidth().padding(top = DoneAtSpacing.l), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                        ReportControl(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, stringResource(R.string.reportPrevious), index > 0) { setPlayer(current().navigate(-1, timelines)) }
                        ReportControl(if (player.finished) Icons.Outlined.Replay else if (player.paused) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                            stringResource(if (player.finished) R.string.reportReplay else if (player.paused) R.string.reportResume else R.string.reportPause)) {
                            setPlayer(if (player.finished || chapter.stage == ReportStage.SUMMARY && chapter.timeline.build(clock()) >= 1f) player.replay() else current().toggle())
                        }
                        ReportControl(Icons.AutoMirrored.Outlined.KeyboardArrowRight, stringResource(R.string.reportNext), index < count - 1) { setPlayer(current().navigate(1, timelines)) }
                        FilledTonalButton(onClick = { setPlayer(current().copy(userPaused = true)); mode = "reading" }, colors = ButtonDefaults.filledTonalButtonColors(containerColor = DoneAtReportPalette.control, contentColor = DoneAtReportPalette.ink)) {
                            Icon(Icons.AutoMirrored.Outlined.ListAlt, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(DoneAtSpacing.s))
                            Text(stringResource(R.string.reportRead))
                        }
                    }
                } else if (displayMode == "reading" && authorized && report?.hasData == true) {
                    ReportHeader(title, back)
                    Text(dateTitle, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = DoneAtReportPalette.cream)
                    if (!motion.reduced && !talkBack) TextButton(onClick = { play() }, colors = ButtonDefaults.textButtonColors(contentColor = DoneAtReportPalette.cream)) { Text(stringResource(R.string.reportPlay)) }
                    ReportReading(report, text, records.text, chapters, Modifier.weight(1f), back)
                } else {
                    val scrollSetup = configuration.fontScale >= 1.5f || configuration.screenHeightDp <= 650
                    Column(Modifier.weight(1f).fillMaxWidth().let { if (scrollSetup) it.verticalScroll(rememberScrollState()) else it }) {
                    ReportHeader(title, back)
                    Text(dateTitle, Modifier.padding(top = DoneAtReportLayout.stageTop).semantics { heading() }, fontSize = DoneAtReportLayout.setupHero, lineHeight = DoneAtReportLayout.setupHero, fontWeight = FontWeight.ExtraBold, color = DoneAtReportPalette.cream)
                    if (report?.isInProgress == true) Text(stringResource(R.string.reportSoFar), Modifier.padding(top = DoneAtSpacing.s), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.titleMedium)
                    Box((if (scrollSetup) Modifier.height(DoneAtReportLayout.teaserHeight).padding(vertical = DoneAtSpacing.l) else Modifier.weight(1f)).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        if (report?.hasData == true && authorized) ReportArtwork(chapters.first(), teaserClock, Modifier.fillMaxWidth().height(DoneAtReportLayout.teaserHeight), teaser = true)
                        else if (!loaded && authorized) CircularProgressIndicator(color = DoneAtReportPalette.cream)
                    }
                    if (authorized && report?.hasData == true && preferences.salaryEnabled) {
                        Surface(color = DoneAtReportPalette.control, shape = RoundedCornerShape(DoneAtReportLayout.readingCardRadius)) {
                        Column(Modifier.padding(DoneAtSpacing.l)) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.reportIncludeIncome), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                            Switch(checked = includeIncome, onCheckedChange = { wanted ->
                                if (!wanted) includeIncome = false
                                else if (!device.hideEarnings) includeIncome = true
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
                    if (!authorized) Button(onClick = unlock, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.plusSeePlans)) }
                    if (!motion.reduced && !talkBack) Button(onClick = { play() }, enabled = ready, modifier = Modifier.fillMaxWidth().heightIn(min = DoneAtReportLayout.controlSize), colors = ButtonDefaults.buttonColors(containerColor = DoneAtReportPalette.orange, contentColor = DoneAtReportPalette.ink)) {
                        Icon(Icons.Outlined.PlayArrow, null)
                        Spacer(Modifier.width(DoneAtSpacing.s))
                        Text(stringResource(R.string.reportPlay), fontWeight = FontWeight.Bold)
                    }
                    FilledTonalButton(onClick = { mode = "reading" }, enabled = ready, modifier = Modifier.fillMaxWidth().padding(top = DoneAtSpacing.s).heightIn(min = DoneAtReportLayout.controlSize), colors = ButtonDefaults.filledTonalButtonColors(containerColor = DoneAtReportPalette.control, contentColor = DoneAtReportPalette.ink)) { Text(stringResource(R.string.reportRead), fontWeight = FontWeight.SemiBold) }
                    }
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

/** Opacity/translation are read in the layer phase; no page layout follows the frame clock. */
private fun Modifier.reportReveal(chapter: ReportChapter, clock: () -> Long, from: Float = 0f, to: Float = .2f): Modifier = graphicsLayer {
    val p = ReportEase.outCubic(ReportEase.window(chapter.timeline.build(clock()), from, to))
    alpha = p
    translationY = 18.dp.toPx() * (1 - p)
}

@Composable
private fun StoryHeading(chapter: ReportChapter, clock: () -> Long) {
    val opening = chapter.stage == ReportStage.CALENDAR || chapter.stage == ReportStage.SUMMARY
    Column(Modifier.reportReveal(chapter, clock).clearAndSetSemantics {
        contentDescription = (listOf(chapter.title, chapter.metric) + chapter.lines).joinToString(". ")
        heading()
    }, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        Text(chapter.title.uppercase(), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
        if (chapter.metric.isNotEmpty()) {
            val metric by remember(chapter, clock) { derivedStateOf {
                val b = chapter.timeline.build(clock())
                val fraction = when (chapter.stage) {
                    ReportStage.REST -> ReportEase.window(b, .34f, .86f)
                    ReportStage.OVERTIME, ReportStage.FOCUS -> ReportEase.outCubic(ReportEase.window(b, .08f, .85f))
                    else -> ReportEase.outCubic(ReportEase.window(b, .08f, 1f))
                }
                chapter.countedMetric?.invoke(fraction) ?: chapter.metric
            } }
            val styled = remember(metric, opening) { buildAnnotatedString {
                Regex("[\\p{N}.,]+|[^\\p{N}.,]+").findAll(metric).forEach { part ->
                    withStyle(SpanStyle(fontSize = if (opening) DoneAtReportLayout.storyHeadline else if (part.value.any { it.isDigit() }) DoneAtReportLayout.storyHero else DoneAtReportLayout.unitSize, fontWeight = FontWeight.ExtraBold)) { append(part.value) }
                }
            } }
            Text(styled, color = DoneAtReportPalette.ink, lineHeight = if (opening) DoneAtReportLayout.storyHeadline else DoneAtReportLayout.storyHero)
        }
        chapter.lines.forEachIndexed { index, line ->
            val delayed = when (chapter.stage) {
                ReportStage.HOURS -> .82f
                ReportStage.REST -> .86f
                ReportStage.OVERTIME -> if (index == 0) 0f else .7f
                ReportStage.INCOME -> .55f
                else -> if (index == 0) 0f else .6f
            }
            Text(line, Modifier.reportReveal(chapter, clock, delayed, if (delayed == 0f) .22f else 1f), color = if (index == 0) DoneAtReportPalette.muted else DoneAtReportPalette.cream, style = MaterialTheme.typography.titleMedium)
        }
    }
}

@Composable
private fun SummaryFacts(chapter: ReportChapter, clock: () -> Long) {
    val large = LocalConfiguration.current.fontScale >= 1.5f
    val modifier = Modifier.fillMaxWidth().reportReveal(chapter, clock, .55f, 1f)
    if (large) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            chapter.summaryFacts.forEach { (label, value) -> SummaryFact(label, value, Modifier.fillMaxWidth()) }
        }
    } else {
        // Fixed columns let long labels wrap inside their cell; FlowRow can drop
        // an overflowing last item when the story stage constrains its height.
        Row(modifier, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            chapter.summaryFacts.forEach { (label, value) -> SummaryFact(label, value, Modifier.weight(1f)) }
        }
    }
}

@Composable
private fun SummaryFact(label: String, value: String, modifier: Modifier) {
    Column(modifier) {
        Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = DoneAtReportPalette.ink)
        Text(label, style = MaterialTheme.typography.labelMedium, color = DoneAtReportPalette.muted)
    }
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

@Composable
private fun ReportReading(report: CycleReportSnapshot, text: TimerText, dates: RecordsText, chapters: List<ReportChapter>, modifier: Modifier, close: () -> Unit) {
    val context = LocalContext.current
    val rows = remember(report, text, dates, context) { ReportCopy(report, text, dates, context).facts() }
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
                ReportArtwork(chapters.first(), { Long.MAX_VALUE }, Modifier.fillMaxWidth().height(DoneAtReportLayout.artHeight).padding(DoneAtSpacing.l))
            }
        }
        // Detailed values keep all chart facts available to readers and TalkBack.
        chapters.filter { it.artKind == ReportArtKind.REST || it.artKind == ReportArtKind.OVERTIME || it.artKind == ReportArtKind.FOCUS || it.artKind == ReportArtKind.PAY || it.artKind == ReportArtKind.AHEAD }.forEach { chapter ->
            Surface(modifier = Modifier.fillMaxWidth(), color = DoneAtReportPalette.control, shape = RoundedCornerShape(DoneAtReportLayout.readingCardRadius)) {
                Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    Text(chapter.title, Modifier.semantics { heading() }, fontWeight = FontWeight.Bold, color = DoneAtReportPalette.ink)
                    chapter.lines.forEach { Text(it, color = DoneAtReportPalette.muted) }
                    if (report.months.isEmpty() && chapter.artKind in listOf(ReportArtKind.OVERTIME, ReportArtKind.FOCUS)) chapter.bars.forEach { (label, value) -> Text(label + " · " + if (chapter.artKind == ReportArtKind.FOCUS) text.count(value.toInt()) else text.relativeDuration(value.toDouble()), color = DoneAtReportPalette.muted) }
                }
            }
        }
        Text(stringResource(R.string.reportBasisNote), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.bodySmall)
        Button(onClick = close, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = DoneAtReportPalette.orange, contentColor = DoneAtReportPalette.ink)) { Text(stringResource(R.string.done)) }
    }
}

@Composable
private fun ReportLegend(hasOvertime: Boolean) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
        listOf(DoneAtReportPalette.orange to R.string.recordsWorkRegular, DoneAtReportPalette.hot to R.string.overtime, DoneAtReportPalette.muted to R.string.recordsRestDay).filter { hasOvertime || it.second != R.string.overtime }.forEach { (color, key) ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                Box(Modifier.size(DoneAtSpacing.s).background(color, CircleShape))
                Text(stringResource(key), color = DoneAtReportPalette.muted, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}
