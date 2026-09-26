package com.rainif.doneat.ui.timer

import android.view.HapticFeedbackConstants
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.automirrored.outlined.DirectionsWalk
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Contrast
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.EventRepeat
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Hotel
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.LocalCafe
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.SportsScore
import androidx.compose.material.icons.outlined.TouchApp
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material.icons.outlined.WbTwilight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.CelebratingBrandMark
import com.rainif.doneat.core.designsystem.DoneAtCountdown
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtProgressMeter
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.DoneAtType
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.designsystem.LocalDoneAtStateColors
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.session.SessionCommands
import com.rainif.doneat.core.domain.session.SessionResult
import com.rainif.doneat.core.domain.session.SessionState
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.TimelineEvent
import com.rainif.doneat.core.domain.session.TimelineKind
import com.rainif.doneat.core.domain.session.TimerPhase
import com.rainif.doneat.core.domain.session.UpcomingTimeline
import com.rainif.doneat.core.domain.session.heroRemainingMs
import com.rainif.doneat.core.domain.session.isBeforeStart
import com.rainif.doneat.core.domain.session.isOnBreak
import com.rainif.doneat.core.domain.session.isOvertimeActive
import com.rainif.doneat.core.domain.settings.PreferencesRules
import com.rainif.doneat.core.domain.summary.SummaryRules
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.timer.TimerCoordinator
import androidx.compose.material.icons.outlined.Timer
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.onboarding.appIsDark
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Taps that need a second press within five seconds, against the same shift. */
private enum class Confirmation { CLOCK_IN, CLOCK_OFF, CANCEL_MANUAL, START }

private data class Armed(val kind: Confirmation, val context: String, val untilMs: Double)

private const val CONFIRM_WINDOW_MS = 5_000.0

/**
 * The main timer (iOS `TimerDesignView` and its phase views). Every figure
 * comes from the session's rules snapshot at the current second; the screen
 * owns only presentation, the pending confirmations and the celebration.
 */
@Composable
fun TimerScreen(graph: AppGraph, open: (Route) -> Unit, openSettings: (Route?) -> Unit) {
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val records by graph.records.state.collectAsStateWithLifecycle()
    val authorized by graph.plus.authorized.collectAsStateWithLifecycle()
    // One tick per second, on the second, while the screen is started; resuming recomputes from the clock.
    val now by remember { timerTicks() }.collectAsStateWithLifecycle(System.currentTimeMillis().toDouble())

    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val text = TimerText(LocalResources.current, LocalConfiguration.current.locales[0], android.text.format.DateFormat.is24HourFormat(context), device.hideEarnings)

    val snapshot = if (session.shouldQuerySnapshot(now)) session.snapshot(now) else null
    val phase = session.visualPhase(snapshot, now)
    val focusEnvironment = com.rainif.doneat.core.domain.session.SessionFocusEnvironment(session, records, authorized, id = graph.newId)
    val focusEvents = com.rainif.doneat.core.domain.focus.FocusTimeline(focusEnvironment)
        .events(records, focusEnvironment.shift(now), now)

    var armed by remember { mutableStateOf<Armed?>(null) }
    val contextKey = snapshot?.let { "${it.startAtMs}|${it.endAtMs}|${it.overtimeEndAtMs}|${session.state.sessionId}|${session.state.earlyOffAtMs}|${session.state.forcedWorkdayDate}" } ?: "none"
    fun isArmed(kind: Confirmation) = armed?.let { it.kind == kind && it.context == contextKey && now < it.untilMs } == true
    LaunchedEffect(armed) {
        val pending = armed ?: return@LaunchedEffect
        delay((pending.untilMs - System.currentTimeMillis()).toLong().coerceAtLeast(0))
        if (armed == pending) armed = null
    }

    var celebration by remember { mutableIntStateOf(0) }
    var showOvertime by rememberSaveable { mutableStateOf(false) }
    var showInvalidLunch by remember { mutableStateOf(false) }
    var pendingCommands by remember { mutableIntStateOf(0) }
    SideEffect { graph.reviewBlocked.value = pendingCommands > 0 || armed != null || showOvertime || showInvalidLunch }
    DisposableEffect(graph) { onDispose { graph.reviewBlocked.value = true } }

    fun perform(done: (() -> Unit)? = null, command: SessionCommands.(SessionState) -> SessionResult) {
        pendingCommands++
        graph.reviewBlocked.value = true
        scope.launch {
            try {
                val at = System.currentTimeMillis().toDouble()
                if (graph.sessions.run(at) { command(it) }) {
                    Haptics.confirm(view)
                    done?.invoke()
                }
            } finally {
                pendingCommands--
                graph.reviewBlocked.value = pendingCommands > 0 || armed != null || showOvertime || showInvalidLunch
            }
        }
    }

    /** First press arms (a warning tick); a second press within the window commits. */
    fun confirmThen(kind: Confirmation, commit: () -> Unit) {
        if (isArmed(kind)) {
            armed = null
            commit()
        } else {
            armed = Armed(kind, contextKey, System.currentTimeMillis() + CONFIRM_WINDOW_MS)
            Haptics.warn(view)
        }
    }

    // Housekeeping at the timer's own seams: a finished run's midnight, an expired early clock-in.
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000)
            graph.timer.reconcile()
        }
    }
    LaunchedEffect(phase) { graph.timer.reconcile() }
    LaunchedEffect(phase, snapshot?.endAtMs, session.state.countdownStarted) {
        if (phase == TimerPhase.CLOCK_IN || phase == TimerPhase.RUNNING || phase == TimerPhase.LUNCH || phase == TimerPhase.OVERTIME) {
            graph.reviews.trackRunningShift(session, snapshot, now.toLong())
        }
    }
    val completionToken = snapshot?.let { shift ->
        if (session.isEndedEarly(shift)) session.state.earlyOffAtMs ?: shift.plannedEndAtMs else shift.endAtMs
    }
    LaunchedEffect(phase, completionToken) {
        if (phase == TimerPhase.COMPLETED && completionToken != null && snapshot != null &&
            session.state.countdownStarted && (snapshot.isWorkday || session.isForcedWorkday(snapshot)) && snapshot.segments.isNotEmpty()
        ) graph.reviews.noteCompletion(completionToken.toLong())
    }

    val prefs = session.env.preferences

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            // Settings-level controls stay small and out of the instrument's way.
            Row(Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.xs), horizontalArrangement = Arrangement.End) {
                EarningsVisibilityButton(graph) { note -> scope.launch { snackbar.showSnackbar(note) } }
                IconButton(onClick = { scope.launch { graph.settings.edit { it.copy(theme = PreferencesRules.nextQuickTheme(it.theme)) } } }) {
                    Icon(
                        when (prefs.theme) {
                            "light" -> Icons.Outlined.LightMode
                            "dark" -> Icons.Outlined.DarkMode
                            else -> Icons.Outlined.Contrast
                        },
                        contentDescription = stringResource(R.string.theme),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            // Lunch and overtime are interludes of the running surface; only a real change of state fades.
            // The surface fading out keeps drawing the phase it last had, not the incoming one.
            val lastPhase = remember { mutableMapOf<String, TimerPhase>() }
            lastPhase[phase.surfaceIdentity] = phase
            Crossfade(phase.surfaceIdentity, Modifier.weight(1f), animationSpec = LocalDoneAtMotion.current.phase(), label = "timerPhase") { identity ->
                val phase = lastPhase.getValue(identity)
                Box(Modifier.fillMaxSize().wrapContentWidth(Alignment.CenterHorizontally).widthIn(max = 680.dp)) {
                    when (phase) {
                        TimerPhase.UNSCHEDULED -> UnscheduledSurface(session, now, text, focusEvents, isArmed(Confirmation.START)) {
                            if (!session.isLunchInsideShift(now)) showInvalidLunch = true
                            else confirmThen(Confirmation.START) { perform { start(it, System.currentTimeMillis().toDouble()) } }
                        }
                        TimerPhase.CLOCK_IN, TimerPhase.RUNNING, TimerPhase.LUNCH, TimerPhase.OVERTIME -> snapshot?.let { shift ->
                            RunningSurface(
                                session, shift, now, text,
                                focusEvents = focusEvents,
                                clockInArmed = isArmed(Confirmation.CLOCK_IN),
                                clockOffArmed = isArmed(Confirmation.CLOCK_OFF),
                                cancelArmed = isArmed(Confirmation.CANCEL_MANUAL),
                                onClockIn = { confirmThen(Confirmation.CLOCK_IN) { perform { clockInEarly(it, System.currentTimeMillis().toDouble()) } } },
                                onClockOff = { confirmThen(Confirmation.CLOCK_OFF) { perform { clockOffEarly(it, System.currentTimeMillis().toDouble()) } } },
                                onUndoClockIn = { perform { undoEarlyClockIn(it, System.currentTimeMillis().toDouble()) } },
                                onCancelManual = { confirmThen(Confirmation.CANCEL_MANUAL) {
                                    perform({ graph.reviews.clearTrackedCompletion() }) { cancelManualTiming(it, System.currentTimeMillis().toDouble()) }
                                } },
                                onOvertime = { showOvertime = true },
                                onShare = { open(Route.TimerShare) },
                            )
                        }
                        TimerPhase.COMPLETED -> snapshot?.let { shift ->
                            val token = if (session.isEndedEarly(shift)) session.state.earlyOffAtMs ?: shift.plannedEndAtMs else shift.endAtMs
                            LaunchedEffect(token) {
                                // Once per completed run in this process; a cold launch may celebrate it again, as on iOS.
                                if (graph.lastCelebratedEndAtMs != token) {
                                    graph.lastCelebratedEndAtMs = token
                                    celebration++
                                }
                            }
                            CompletedSurface(
                                session, shift, now, text,
                                onReplay = { celebration++ },
                                onUndo = { perform({
                                    graph.lastCelebratedEndAtMs = 0.0
                                    graph.reviews.revokeCompletion(token.toLong())
                                }) { undoEarlyClockOff(it, System.currentTimeMillis().toDouble()) } },
                                onOvertime = { showOvertime = true },
                                onShare = { open(Route.TimerShare) },
                            )
                        }
                        TimerPhase.REST -> snapshot?.let { shift ->
                            RestSurface(session, shift, now, text, focusEvents, isArmed(Confirmation.START)) {
                                if (!session.isLunchInsideShift(now)) showInvalidLunch = true
                                else confirmThen(Confirmation.START) {
                                    perform { start(it, System.currentTimeMillis().toDouble(), force = session.followsSchedule(System.currentTimeMillis().toDouble())) }
                                }
                            }
                        }
                        TimerPhase.RULES_ERROR -> RulesErrorSurface { openSettings(null) }
                    }
                }
            }
        }
        ConfettiBurst(celebration, Modifier.fillMaxSize())
        SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).safeDrawingPadding())
    }

    if (showOvertime) {
        OvertimeDialog(
            session = session,
            text = text,
            dark = appIsDark(),
            onDismiss = { showOvertime = false },
            onConfirm = { endAtMs ->
                val previousEnd = session.state.earlyOffAtMs ?: snapshot?.endAtMs
                perform({
                    showOvertime = false
                    // A new completion boundary: the later clock-off celebrates again.
                    graph.lastCelebratedEndAtMs = 0.0
                    previousEnd?.let { graph.reviews.revokeCompletion(it.toLong()) }
                }) { applyOvertime(it, endAtMs, System.currentTimeMillis().toDouble()) }
            },
        )
    }
    if (showInvalidLunch) {
        AlertDialog(
            onDismissRequest = { showInvalidLunch = false },
            title = { Text(stringResource(R.string.invalidLunchTitle)) },
            text = { Text(stringResource(R.string.invalidLunchMessage)) },
            confirmButton = {
                TextButton(onClick = {
                    showInvalidLunch = false
                    openSettings(Route.Schedule)
                }) { Text(stringResource(R.string.goToLunchSettings)) }
            },
            dismissButton = { TextButton(onClick = { showInvalidLunch = false }) { Text(stringResource(R.string.return_)) } },
        )
    }
}

// Surfaces

@Composable
private fun RunningSurface(
    session: ShiftSession,
    shift: ShiftSnapshot,
    now: Double,
    text: TimerText,
    focusEvents: List<TimelineEvent>,
    clockInArmed: Boolean,
    clockOffArmed: Boolean,
    cancelArmed: Boolean,
    onClockIn: () -> Unit,
    onClockOff: () -> Unit,
    onUndoClockIn: () -> Unit,
    onCancelManual: () -> Unit,
    onOvertime: () -> Unit,
    onShare: () -> Unit,
) {
    val beforeStart = shift.isBeforeStart(now)
    val onBreak = shift.isOnBreak
    val overtime = shift.isOvertimeActive(now)
    val remaining = if (beforeStart) session.countdownToClockInMs(shift, now) else shift.heroRemainingMs(now)
    val progress = if (beforeStart) session.countdownToClockInProgress(shift) else shift.progress
    val caption = stringResource(
        when {
            beforeStart -> R.string.nextShiftLabelShort
            onBreak -> if (session.usesExtendedSchedule(now)) R.string.extendedBreak else R.string.lunchInProgress
            overtime -> R.string.overtimeTimeLeftCaption
            else -> R.string.timeLeftCaption
        },
    )
    Column(Modifier.fillMaxSize()) {
        if (session.isForcedWorkday(shift)) {
            Banner(Icons.Outlined.TouchApp, stringResource(R.string.manualTimingBanner), stringResource(if (cancelArmed) R.string.cancelManualTimingConfirm else R.string.cancelManualTiming), cancelArmed, onCancelManual)
        } else if (!beforeStart && session.isStartedEarly(now)) {
            val at = session.state.earlyStartAtMs ?: shift.startAtMs
            Banner(Icons.AutoMirrored.Outlined.DirectionsWalk, Strings.clockedInEarlyNote(LocalResources.current, text.time(at)), stringResource(R.string.undoClockInEarly), false, onUndoClockIn)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            if (overtime) {
                PhasePill(Icons.Outlined.Schedule, Strings.overtimeUntil(LocalResources.current, text.time(shift.overtimeEndAtMs ?: shift.endAtMs)), overtime = true)
            }
            Hero(remaining, caption, text, if (onBreak) Icons.Outlined.LocalCafe else null)
            DoneAtProgressMeter(
                percent = progress,
                label = stringResource(R.string.progress),
                modifier = Modifier.padding(horizontal = DoneAtSpacing.xl).padding(top = DoneAtSpacing.s),
                overtime = overtime,
                paused = onBreak,
                locale = text.locale,
            )
            Column(Modifier.padding(horizontal = DoneAtSpacing.page).padding(top = DoneAtSpacing.section)) {
                val follows = session.followsSchedule(now)
                if (follows) SectionHeader(stringResource(R.string.summaryEstimateNote))
                Card {
                    InfoRow(Icons.Outlined.Schedule, stringResource(R.string.todaysShift), text.timeRange(shift.startAtMs, shift.endAtMs))
                    if (session.env.preferences.salaryEnabled) {
                        Divider()
                        InfoRow(Icons.Outlined.Payments, stringResource(R.string.moneyEarned), text.money(shift.earnedSoFar), emphasized = true)
                    }
                    if (follows) SummaryRows(session, now, shift, text)
                }
                val events = UpcomingTimeline.events(
                    shift, now,
                    ScheduleRules.reminders(session.rulesInput(now), TimerCoordinator.reminderInputs(LocalResources.current, session.env.preferences)),
                    microBreakEnabled = session.env.preferences.microBreakEnabled,
                    milestonesEnabled = session.env.preferences.notificationMode == "milestones",
                )
                ComingUp((events + focusEvents).sortedBy { it.atMs }, now, text, session)
            }
            Spacer(Modifier.heightIn(min = DoneAtSpacing.xl))
        }
        // The bar under the instrument: one decision before the start, two once it runs.
        // One height for both buttons, whichever label wraps under a large font.
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).padding(DoneAtSpacing.page), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            if (beforeStart) {
                ArmableButton(stringResource(if (clockInArmed) R.string.clockInEarlyConfirm else R.string.clockInEarly), Icons.AutoMirrored.Outlined.ArrowForward, clockInArmed, primary = true, onClick = onClockIn, modifier = Modifier.weight(1f))
            } else {
                ArmableButton(stringResource(if (clockOffArmed) R.string.clockOffEarlyConfirm else R.string.clockOffEarly), Icons.AutoMirrored.Outlined.ArrowBack, clockOffArmed, primary = false, onClick = onClockOff, modifier = Modifier.weight(1f).fillMaxHeight())
                FilledTonalButton(onClick = onOvertime, modifier = Modifier.weight(1f).fillMaxHeight().heightIn(min = 52.dp), shape = MaterialTheme.shapes.medium) {
                    Text(stringResource(if (overtime) R.string.adjustOvertime else R.string.overtime), maxLines = 2, textAlign = TextAlign.Center)
                }
            }
            // Share stays a small square beside the decisions, as on iOS.
            FilledTonalIconButton(onClick = onShare, modifier = Modifier.size(52.dp).fillMaxHeight(), shape = MaterialTheme.shapes.medium) {
                Icon(Icons.Outlined.Share, stringResource(R.string.shareButton))
            }
        }
    }
}

@Composable
private fun CompletedSurface(
    session: ShiftSession,
    shift: ShiftSnapshot,
    now: Double,
    text: TimerText,
    onReplay: () -> Unit,
    onUndo: () -> Unit,
    onOvertime: () -> Unit,
    onShare: () -> Unit,
) {
    val res = LocalResources.current
    val endedEarly = session.isEndedEarly(shift)
    val finished = session.clockOffSnapshot(shift)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = DoneAtSpacing.l), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            stringResource(R.string.offWorkToday),
            modifier = Modifier.padding(top = DoneAtSpacing.xxl).clickable(onClickLabel = stringResource(R.string.replayCelebration), onClick = onReplay).semantics { heading() },
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        shift.nextShiftStartAtMs?.let { next ->
            Text(
                Strings.nextShiftIn(res, text.relativeDuration(next - now)),
                modifier = Modifier.padding(top = DoneAtSpacing.m, start = DoneAtSpacing.xl, end = DoneAtSpacing.xl),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        Column(Modifier.padding(horizontal = DoneAtSpacing.page).widthIn(max = 560.dp)) {
            if (endedEarly) {
                session.state.earlyOffAtMs?.let { at ->
                    Spacer(Modifier.size(DoneAtSpacing.l))
                    Banner(Icons.AutoMirrored.Outlined.DirectionsWalk, Strings.clockedOffEarlyNote(res, text.time(at)), stringResource(R.string.undoClockOffEarly), false, onUndo, inset = false)
                }
            }
            Spacer(Modifier.size(DoneAtSpacing.xl))
            SectionHeader(stringResource(R.string.todayInFull))
            val lunch = session.takenLunchWindow(finished, now)
            val follows = session.followsSchedule(now)
            Card {
                InfoRow(Icons.Outlined.Schedule, stringResource(R.string.worked), text.relativeDuration(if (endedEarly) finished.elapsedMs else shift.durationMs))
                lunch?.let { (start, end) ->
                    Divider()
                    InfoRow(Icons.Outlined.LocalCafe, stringResource(R.string.lunchTaken), text.timeRange(start, end))
                }
                if (follows) {
                    Divider()
                    // Frozen at the clock-off, so the week does not keep growing after it.
                    val asOf = if (endedEarly) session.state.earlyOffAtMs ?: now else now
                    InfoRow(Icons.Outlined.CalendarMonth, stringResource(R.string.summaryThisWeek), summaryText(session.periodSummary(SummaryRules.Period.WEEK, asOf, finished), session, text), small = true)
                }
            }
            Spacer(Modifier.size(DoneAtSpacing.l))
            if (follows) SectionHeader(stringResource(R.string.summaryEstimateNote))
            Card {
                if (session.env.preferences.salaryEnabled) {
                    InfoRow(Icons.Outlined.Payments, stringResource(R.string.moneyEarned), text.money(finished.earnedSoFar), emphasized = true)
                    Divider()
                }
                val nextStart = shift.nextShiftStartAtMs
                val nextEnd = shift.nextShiftEndAtMs
                InfoRow(
                    Icons.Outlined.CalendarMonth,
                    nextStart?.let { text.relativeDay(it, now) } ?: stringResource(R.string.nextShiftLabelShort),
                    if (nextStart != null && nextEnd != null) text.timeRange(nextStart, nextEnd) else "—",
                )
            }
            Spacer(Modifier.size(DoneAtSpacing.xl))
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                FilledTonalButton(onClick = onOvertime, modifier = Modifier.weight(1f).fillMaxHeight().heightIn(min = 52.dp), shape = MaterialTheme.shapes.medium) {
                    Text(stringResource(R.string.overtime), textAlign = TextAlign.Center)
                }
                FilledTonalButton(onClick = onShare, modifier = Modifier.weight(1f).fillMaxHeight().heightIn(min = 52.dp), shape = MaterialTheme.shapes.medium) {
                    Icon(Icons.Outlined.Share, null, Modifier.size(18.dp))
                    Text(stringResource(R.string.shareButton), Modifier.padding(start = 8.dp), textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun RestSurface(session: ShiftSession, shift: ShiftSnapshot, now: Double, text: TimerText, focusEvents: List<TimelineEvent>, armed: Boolean, onStart: () -> Unit) {
    val remaining = session.countdownToClockInMs(shift, now)
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            PhasePill(Icons.Outlined.Hotel, stringResource(R.string.widgetRestDay))
            Hero(remaining, null, text, null, muted = true)
            Box(Modifier.padding(horizontal = DoneAtSpacing.xl).padding(top = DoneAtSpacing.s)) {
                // Quieter than a working day's meter: it counts rest, not work.
                DoneAtProgressMeter(session.countdownToClockInProgress(shift), stringResource(R.string.progress), Modifier.alpha(0.72f), locale = text.locale)
            }
            Column(Modifier.padding(horizontal = DoneAtSpacing.page).padding(top = DoneAtSpacing.section)) {
                SectionHeader(stringResource(R.string.summaryEstimateNote))
                Card { SummaryRows(session, now, shift, text, first = true) }
                val next = shift.nextShiftStartAtMs?.let { session.snapshot(it) }
                ComingUp((next?.let { UpcomingTimeline.nextShiftPreview(it) }.orEmpty() + focusEvents).sortedBy { it.atMs }, now, text, session, collapsible = false)
            }
            Spacer(Modifier.heightIn(min = DoneAtSpacing.l))
        }
        StartButton(armed, onStart)
    }
}

@Composable
private fun UnscheduledSurface(session: ShiftSession, now: Double, text: TimerText, focusEvents: List<TimelineEvent>, armed: Boolean, onStart: () -> Unit) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = DoneAtSpacing.xl), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Spacer(Modifier.size(DoneAtSpacing.xxl))
            CelebratingBrandMark(stringResource(R.string.app_name), Modifier.size(168.dp), showsDepth = true)
            Text(stringResource(R.string.unscheduledTitle), Modifier.padding(top = DoneAtSpacing.xl).semantics { heading() }, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            Text(stringResource(R.string.unscheduledBody), Modifier.padding(top = DoneAtSpacing.m), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            Text(
                "${TimerText.isolate(ShiftSession.timeString(session.effectiveStartMinutes(now)))} – ${TimerText.isolate(ShiftSession.timeString(session.effectiveEndMinutes(now)))}",
                Modifier.padding(top = DoneAtSpacing.l),
                style = MaterialTheme.typography.titleLarge.copy(fontFeatureSettings = "tnum"),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            ComingUp(focusEvents, now, text, session)
        }
        StartButton(armed, onStart)
    }
}

@Composable
private fun RulesErrorSurface(onOpenSettings: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(DoneAtSpacing.xl), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(Icons.Outlined.ErrorOutline, null, Modifier.size(36.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(stringResource(R.string.rulesErrorBanner), Modifier.padding(top = DoneAtSpacing.m), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        FilledTonalButton(onClick = onOpenSettings, Modifier.padding(top = DoneAtSpacing.l)) {
            Icon(Icons.Outlined.Tune, null, Modifier.size(18.dp))
            Text(stringResource(R.string.settings), Modifier.padding(start = DoneAtSpacing.s))
        }
    }
}

// Pieces

/** The countdown and its caption, sized to the width so eight digits never clip at large font scales. */
@Composable
private fun Hero(remainingMs: Double, caption: String?, text: TimerText, captionIcon: ImageVector?, muted: Boolean = false) {
    val digits = text.duration(remainingMs)
    val spoken = listOfNotNull(caption, text.relativeDuration(remainingMs)).joinToString(", ")
    BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.l).padding(top = DoneAtSpacing.l), contentAlignment = Alignment.Center) {
        val density = LocalDensity.current
        val natural = DoneAtType.countdown
        // Tabular digits are about 0.6 em wide; eight characters must fit the column.
        val fitted = with(density) {
            val maxPx = constraints.maxWidth / (digits.length * 0.62f)
            if (natural.fontSize.toPx() > maxPx) natural.copy(fontSize = maxPx.toSp(), lineHeight = (maxPx * 1.12f).toSp()) else natural
        }
        DoneAtCountdown(digits, spoken, style = fitted, color = if (muted) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface)
    }
    if (caption != null) {
        Row(Modifier.padding(top = DoneAtSpacing.xs, start = DoneAtSpacing.xl, end = DoneAtSpacing.xl), verticalAlignment = Alignment.CenterVertically) {
            if (captionIcon != null) Icon(captionIcon, null, Modifier.size(16.dp).padding(end = DoneAtSpacing.xxs), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(caption, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun PhasePill(icon: ImageVector, label: String, overtime: Boolean = false) {
    val states = LocalDoneAtStateColors.current
    val container = if (overtime) states.overtime else MaterialTheme.colorScheme.surfaceContainerHigh
    val content = if (overtime) states.onOvertime else MaterialTheme.colorScheme.onSurfaceVariant
    Surface(shape = CircleShape, color = container, contentColor = content, modifier = Modifier.padding(top = DoneAtSpacing.l)) {
        Row(Modifier.padding(horizontal = DoneAtSpacing.m, vertical = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, Modifier.size(16.dp))
            Text(label, Modifier.padding(start = DoneAtSpacing.xs), style = MaterialTheme.typography.labelLarge)
        }
    }
}

/** A note with its one action, for marks the user can take back. */
@Composable
private fun Banner(icon: ImageVector, note: String, action: String, armed: Boolean, onAction: () -> Unit, inset: Boolean = true) {
    val states = LocalDoneAtStateColors.current
    Surface(
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier.fillMaxWidth().then(if (inset) Modifier.padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.xs) else Modifier),
    ) {
        Row(Modifier.heightIn(min = 48.dp).padding(start = DoneAtSpacing.l, end = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(note, Modifier.weight(1f).padding(horizontal = DoneAtSpacing.s), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = onAction) {
                Text(action, color = if (armed) states.overtimeMeter else MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        modifier = Modifier.padding(start = DoneAtSpacing.l, bottom = DoneAtSpacing.s).semantics { heading() },
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun Card(content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow, modifier = Modifier.fillMaxWidth()) {
        Column(content = content)
    }
}

@Composable
private fun Divider() = com.rainif.doneat.ui.components.RowDivider()

@Composable
private fun InfoRow(icon: ImageVector, title: String, value: String, emphasized: Boolean = false, small: Boolean = false) {
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        TitleAndValue(Modifier.weight(1f).padding(start = DoneAtSpacing.m)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                value,
                style = (if (small) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodyLarge).copy(fontFeatureSettings = "tnum"),
                fontWeight = if (emphasized) FontWeight.SemiBold else null,
                color = if (emphasized) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End,
            )
        }
    }
}

/**
 * A title and its value on one line when both fit whole; otherwise the value
 * moves under the title, so large text never splits a word to make room.
 */
@Composable
private fun TitleAndValue(modifier: Modifier, content: @Composable () -> Unit) {
    Layout(content, modifier) { measurables, constraints ->
        val (title, value) = measurables
        val gap = DoneAtSpacing.m.roundToPx()
        val width = constraints.maxWidth
        val sideBySide = title.maxIntrinsicWidth(Constraints.Infinity) + gap + value.maxIntrinsicWidth(Constraints.Infinity) <= width
        if (sideBySide) {
            val v = value.measure(Constraints(maxWidth = width))
            val t = title.measure(Constraints(maxWidth = width - v.width - gap))
            val height = maxOf(t.height, v.height)
            layout(width, height) {
                t.placeRelative(0, (height - t.height) / 2)
                v.placeRelative(width - v.width, (height - v.height) / 2)
            }
        } else {
            val t = title.measure(Constraints(maxWidth = width))
            val v = value.measure(Constraints(maxWidth = width))
            layout(width, t.height + v.height) {
                t.placeRelative(0, 0)
                v.placeRelative(0, t.height)
            }
        }
    }
}

/** This week and this year, estimated from the schedule; money only when salary is on. */
@Composable
private fun SummaryRows(session: ShiftSession, now: Double, shift: ShiftSnapshot, text: TimerText, first: Boolean = false) {
    if (!first) Divider()
    InfoRow(Icons.Outlined.CalendarMonth, stringResource(R.string.summaryThisWeek), summaryText(session.periodSummary(SummaryRules.Period.WEEK, now, shift), session, text), small = true)
    Divider()
    InfoRow(Icons.Outlined.EventRepeat, stringResource(R.string.summaryThisYear), summaryText(session.periodSummary(SummaryRules.Period.YEAR, now, shift), session, text), small = true)
}

private fun summaryText(summary: SummaryRules.PeriodSummary?, session: ShiftSession, text: TimerText): String {
    summary ?: return "—"
    val base = "${text.days(summary.days)} · ${text.hours(summary.hours)}"
    return if (session.env.preferences.salaryEnabled) "$base · ${text.money(summary.earnings)}" else base
}

/** "Coming up": the next few rows, with the rest one tap away. */
@Composable
private fun ComingUp(events: List<TimelineEvent>, now: Double, text: TimerText, session: ShiftSession, collapsible: Boolean = true) {
    if (events.isEmpty()) return
    val res = LocalResources.current
    var expanded by rememberSaveable { mutableStateOf(false) }
    val limit = if (collapsible) COLLAPSED_ROWS else events.size
    val visible = if (expanded) events else events.take(limit)
    Spacer(Modifier.size(DoneAtSpacing.section))
    SectionHeader(stringResource(R.string.comingUp))
    Card {
        visible.forEachIndexed { index, event ->
            if (index > 0) Divider()
            val (icon, tint) = eventStyle(event.kind)
            val (title, detail) = timelineWords(event, res, text, session, now, showsShiftDetail = collapsible)
            Row(Modifier.fillMaxWidth().heightIn(min = 58.dp).padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s), verticalAlignment = Alignment.CenterVertically) {
                Surface(shape = CircleShape, color = tint.copy(alpha = 0.14f), modifier = Modifier.size(32.dp)) {
                    Box(contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(18.dp), tint = tint) }
                }
                Column(Modifier.weight(1f).padding(horizontal = DoneAtSpacing.m)) {
                    Text(title, style = MaterialTheme.typography.bodyLarge)
                    if (detail != null) Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(text.eventTime(event.atMs, now), style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (collapsible && events.size > limit) {
            Divider()
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { expanded = !expanded }.padding(horizontal = DoneAtSpacing.l),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    if (expanded) stringResource(R.string.timelineCollapse) else Strings.timelineExpand(res, text.count(events.size - limit)),
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
                Icon(if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null, tint = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

private const val COLLAPSED_ROWS = 3

@Composable
private fun eventStyle(kind: TimelineKind): Pair<ImageVector, Color> {
    val scheme = MaterialTheme.colorScheme
    return when (kind) {
        TimelineKind.SHIFT_START -> Icons.Outlined.WbTwilight to scheme.tertiary
        TimelineKind.LUNCH_START -> Icons.Outlined.LocalCafe to scheme.tertiary
        TimelineKind.LUNCH_END -> Icons.AutoMirrored.Outlined.ArrowForward to scheme.tertiary
        TimelineKind.HEALTH -> Icons.AutoMirrored.Outlined.DirectionsWalk to scheme.secondary
        TimelineKind.MILESTONE -> Icons.Outlined.NotificationsActive to scheme.secondary
        TimelineKind.SHIFT_END -> Icons.Outlined.SportsScore to scheme.primary
        TimelineKind.FOCUS -> Icons.Outlined.Timer to scheme.primary
        TimelineKind.FOCUS_BREAK -> Icons.Outlined.LocalCafe to scheme.tertiary
    }
}

/**
 * A button that asks twice. Armed, it takes the deeper overtime orange and a
 * warning glyph while retaining its layout.
 */
@Composable
private fun ArmableButton(label: String, icon: ImageVector, armed: Boolean, primary: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val states = LocalDoneAtStateColors.current
    val colors = when {
        armed -> ButtonDefaults.buttonColors(containerColor = states.overtimeMeter, contentColor = states.onOvertimeMeter)
        primary -> ButtonDefaults.buttonColors()
        else -> ButtonDefaults.filledTonalButtonColors()
    }
    Button(onClick = onClick, modifier = modifier.heightIn(min = 52.dp), shape = MaterialTheme.shapes.medium, colors = colors) {
        Icon(if (armed) Icons.Outlined.WarningAmber else icon, null, Modifier.size(18.dp))
        Text(label, Modifier.padding(start = DoneAtSpacing.s), maxLines = 2, textAlign = TextAlign.Center)
    }
}

/** Manual timing: a rest day worked anyway, or an unscheduled day. The first tap arms. */
@Composable
private fun StartButton(armed: Boolean, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(DoneAtSpacing.page)) {
        DoneAtPrimaryButton(
            stringResource(if (armed) R.string.nonWorkdayTapAgain else R.string.manualTiming),
            onClick,
            Modifier.fillMaxWidth(),
        )
    }
}
