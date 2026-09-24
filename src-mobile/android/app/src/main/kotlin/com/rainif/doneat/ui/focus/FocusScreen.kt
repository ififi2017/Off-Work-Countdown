package com.rainif.doneat.ui.focus

import android.view.HapticFeedbackConstants
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtRecordsColors
import com.rainif.doneat.core.domain.focus.FocusDayCanvas
import com.rainif.doneat.core.domain.focus.FocusNextAction
import com.rainif.doneat.core.domain.focus.FocusPlacement
import com.rainif.doneat.core.domain.focus.FocusStartAvailability
import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusPlanBlockKind
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.records.RecordsCard
import com.rainif.doneat.ui.timer.Haptics
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The Focus tab (iOS `FocusCanvasView`), "today" scale: what am I in, how
 * long is left, what happens after; then the shift drawn to scale, where
 * creating a task and placing it are one action.
 */
@Composable
fun FocusScreen(graph: AppGraph, open: (Route) -> Unit, openSettings: (Route?) -> Unit) {
    val context = rememberFocusContext(graph)
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    var selectedBlock by rememberSaveable { mutableStateOf<Long?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var confirmsStop by remember { mutableStateOf(false) }
    var confirmsClearDay by remember { mutableStateOf(false) }
    var namesTemplate by remember { mutableStateOf<String?>(null) }
    var taskToExtend by remember { mutableStateOf<String?>(null) }
    var breakBlock by remember { mutableStateOf<FocusDayCanvas.Block?>(null) }
    val model = context.canvas
    val locked = model.isLocked
    // A sentence an editor left behind: shown here once, then cleared.
    val left by graph.focusNotice.collectAsStateWithLifecycle()
    LaunchedEffect(left) {
        left?.let {
            notice = it
            graph.focusNotice.value = null
        }
    }

    fun create(blockStartAtMs: Long?, currentOrNext: Boolean = false) {
        if (locked) openSettings(Route.Plus) else open(Route.FocusCreate(blockStartAtMs, currentOrNext, null))
    }
    fun extend(taskID: String) {
        taskToExtend = taskID
    }
    fun pick(block: FocusDayCanvas.Block) {
        if (locked) return openSettings(Route.Plus)
        selectedBlock = block.startAtMs
        val task = context.task(block.taskID)
        when {
            task != null -> open(Route.FocusTaskEdit(task.id))
            block.hasAssignment -> breakBlock = block
            block.isEditable -> create(block.startAtMs)
        }
    }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(bottom = DoneAtSpacing.xl),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.focusTitle),
                    Modifier.weight(1f).padding(start = DoneAtSpacing.page - DoneAtSpacing.xs).semantics { heading() },
                    style = MaterialTheme.typography.headlineMedium,
                )
                IconButton(onClick = { create(null) }, enabled = !locked) {
                    Icon(Icons.Outlined.Add, stringResource(R.string.focusQuickCreate))
                }
                IconButton(onClick = { open(Route.FocusTimerSettings) }) {
                    Icon(Icons.Outlined.Settings, stringResource(R.string.focusTimerSettings), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                NowBand(
                    graph, context,
                    onStop = { confirmsStop = true },
                    onExtend = ::extend,
                    onStart = { block ->
                        val taskID = block.taskID ?: return@NowBand
                        scope.launch { if (graph.focus.start(taskID, graph.nowMs(), block.startAtMs)) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
                    },
                    onAdd = { create(null, currentOrNext = true) },
                    onUnlock = { openSettings(Route.Plus) },
                )
                when {
                    locked -> LockedCanvas(context) { openSettings(Route.Plus) }
                    model.isEmpty -> Text(stringResource(R.string.focusNoShift), Modifier.padding(vertical = 24.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    else -> {
                        if (model.isNextShift) {
                            val day = java.time.Instant.ofEpochMilli(model.shiftStartAtMs).atZone(java.time.ZoneId.systemDefault()).toLocalDate()
                            val title = java.time.format.DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(context.text.locale, "EEEMMMd"), context.text.locale).format(day)
                            Text(Strings.focusBandNextShift(res, title), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        FocusBand(context, model, selectedBlock, onPick = ::pick)
                        TaskLedger(graph, context, onEdit = { open(Route.FocusTaskEdit(it)) }, onExtend = ::extend)
                        if (model.tasks.isNotEmpty() || model.blocks.any { it.hasAssignment }) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 8.dp)) {
                                if (graph.focus.planning(context.state).appliedTemplate(context.state, context.nowMs) == null && model.blocks.any { it.hasAssignment }) {
                                    OutlinedButton(onClick = { namesTemplate = res.getString(R.string.focusUsualDayDefaultName) }, Modifier.fillMaxWidth()) {
                                        Text(stringResource(R.string.focusSaveDayAsTemplate))
                                    }
                                }
                                OutlinedButton(onClick = { confirmsClearDay = true }, Modifier.fillMaxWidth()) {
                                    Text(stringResource(R.string.focusClearDayTasks), color = MaterialTheme.colorScheme.error)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (confirmsStop) {
        val focusPhase = context.session?.kind == FocusSessionKind.FOCUS
        AlertDialog(
            onDismissRequest = { confirmsStop = false },
            title = { Text(stringResource(if (focusPhase) R.string.focusStopTitle else R.string.focusEndBreakTitle)) },
            text = { Text(stringResource(if (focusPhase) R.string.focusStopConfirm else R.string.focusEndBreakBody)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmsStop = false
                    scope.launch { graph.focus.stop(FocusEndReason.STOPPED_BY_USER, graph.nowMs()) }
                }) { Text(stringResource(R.string.focusStop), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmsStop = false }) { Text(stringResource(R.string.cancelAction)) } },
        )
    }
    if (confirmsClearDay) {
        AlertDialog(
            onDismissRequest = { confirmsClearDay = false },
            title = { Text(stringResource(R.string.focusClearDayTasks)) },
            text = { Text(stringResource(R.string.focusClearDayTasksBody)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmsClearDay = false
                    scope.launch { graph.focus.edit { state, planning -> planning.clearDay(state, graph.nowMs()) } }
                }) { Text(stringResource(R.string.focusClearDayTasks), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmsClearDay = false }) { Text(stringResource(R.string.cancelAction)) } },
        )
    }
    namesTemplate?.let { name ->
        AlertDialog(
            onDismissRequest = { namesTemplate = null },
            title = { Text(stringResource(R.string.focusSaveDayAsTemplate)) },
            text = { OutlinedTextField(name, { namesTemplate = it }, label = { Text(stringResource(R.string.focusUsualDayName)) }, singleLine = true) },
            confirmButton = {
                TextButton(enabled = name.isNotBlank(), onClick = {
                    namesTemplate = null
                    scope.launch { graph.focus.plan { state, planning -> planning.saveTemplateFromToday(state, name.trim(), graph.nowMs()) } }
                }) { Text(stringResource(R.string.saveAction)) }
            },
            dismissButton = { TextButton(onClick = { namesTemplate = null }) { Text(stringResource(R.string.cancelAction)) } },
        )
    }
    taskToExtend?.let { taskID ->
        AlertDialog(
            onDismissRequest = { taskToExtend = null },
            title = { Text(stringResource(R.string.focusExtendOne)) },
            text = { Text(context.task(taskID)?.title ?: stringResource(R.string.focusTaskTitle)) },
            confirmButton = {
                TextButton(onClick = {
                    taskToExtend = null
                    scope.launch {
                        val result = graph.focus.plan { state, planning -> planning.addOneBlock(state, taskID, graph.nowMs()) }
                        val start = result?.getOrNull()
                        if (start != null) {
                            selectedBlock = start
                            Haptics.confirm(view)
                            notice = Strings.focusExtendScheduled(res, context.text.time(start.toDouble()))
                        } else {
                            Haptics.warn(view)
                            val conflict = result?.exceptionOrNull()?.message == com.rainif.doneat.core.domain.focus.FocusExtensionError.CONFLICT.name
                            notice = res.getString(if (conflict) R.string.focusExtendConflict else R.string.focusExtendNoRoom)
                        }
                    }
                }) { Text(stringResource(R.string.focusSaveTask)) }
            },
            dismissButton = { TextButton(onClick = { taskToExtend = null }) { Text(stringResource(R.string.cancelAction)) } },
        )
    }
    breakBlock?.let { block ->
        // A block turned into a break has nothing to edit but the choice itself.
        AlertDialog(
            onDismissRequest = { breakBlock = null },
            title = { Text(stringResource(R.string.focusBreak)) },
            text = { Text(context.range(block)) },
            confirmButton = {
                TextButton(onClick = {
                    breakBlock = null
                    scope.launch { graph.focus.edit { state, planning -> planning.clearCanvasBlock(state, block.startAtMs, graph.nowMs()) } }
                }) { Text(stringResource(R.string.focusBlockClear), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { breakBlock = null }) { Text(stringResource(R.string.close)) } },
        )
    }
    notice?.let {
        AlertDialog(
            onDismissRequest = { notice = null },
            text = { Text(it) },
            confirmButton = { TextButton(onClick = { notice = null }) { Text(stringResource(R.string.okAction)) } },
        )
    }
}

/** What a placement result tells the user (iOS `apply(_:)`); null when nothing needs saying. */
fun placementNotice(result: FocusPlacement?, res: android.content.res.Resources): String? = when (result) {
    is FocusPlacement.AddedUnscheduled -> res.getString(R.string.focusNoEmptyBlock)
    FocusPlacement.NoShift -> res.getString(R.string.focusNoShift)
    else -> null
}

/**
 * The one conclusion at the top of the page (iOS `FocusNowBand`): running,
 * just finished, before the shift, or the block you are in.
 */
@Composable
private fun NowBand(
    graph: AppGraph,
    context: FocusContext,
    onStop: () -> Unit,
    onExtend: (String) -> Unit,
    onStart: (FocusDayCanvas.Block) -> Unit,
    onAdd: () -> Unit,
    onUnlock: () -> Unit,
) {
    val model = context.canvas
    val session = context.session
    val scheme = MaterialTheme.colorScheme
    val res = LocalResources.current
    RecordsCard {
        Column {
            Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                when {
                    model.isLocked -> {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Outlined.Lock, null, Modifier.size(18.dp))
                            Text(stringResource(R.string.focusLockedTitle), style = MaterialTheme.typography.titleMedium)
                        }
                        Text(stringResource(R.string.focusLockedBody), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
                        Button(onClick = onUnlock) { Text(stringResource(R.string.plusSeePlans)) }
                    }
                    session != null -> Running(graph, context, session, onStop, onExtend)
                    graph.focus.dayComplete(context.nowMs, context.state) -> {
                        Text(stringResource(R.string.focusCompletedTasksTitle), style = MaterialTheme.typography.titleMedium)
                        Button(onClick = onAdd) { Text(stringResource(R.string.focusQuickCreate)) }
                    }
                    context.nowMs < model.shiftStartAtMs -> {
                        val first = model.blocks.firstOrNull { it.isAssigned && !it.isUserBreak }
                        if (first != null) {
                            Text(first.taskTitle ?: stringResource(R.string.focusTitle), style = MaterialTheme.typography.titleMedium)
                            Countdown(context, first.startAtMs.toDouble())
                            Text(context.range(first), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
                        } else {
                            Text(stringResource(R.string.focusBandEmptyBlock), style = MaterialTheme.typography.titleMedium, color = scheme.onSurfaceVariant)
                        }
                    }
                    context.nextAction == FocusNextAction.START_SHORT_BREAK || context.nextAction == FocusNextAction.START_LONG_BREAK -> {
                        // Unfinished tasks must not read as a completed day.
                        Text(stringResource(R.string.focusTitle), style = MaterialTheme.typography.titleMedium)
                        Button(onClick = onAdd) { Text(stringResource(R.string.focusQuickCreate)) }
                    }
                    model.currentBlock?.let { it.kind == FocusPlanBlockKind.TASK && !it.isUserBreak } == true -> Idle(graph, context, model.currentBlock!!, onStart, onAdd)
                    else -> {
                        Text(stringResource(if (context.nextAction == FocusNextAction.START_NEXT_FOCUS) R.string.focusStartNextFocus else R.string.focusTitle), style = MaterialTheme.typography.titleMedium)
                        val next = model.blocks.firstOrNull { it.state == FocusDayCanvas.State.FUTURE && it.kind == FocusPlanBlockKind.TASK && !it.isUserBreak }
                        Text(
                            next?.let { b -> b.taskTitle?.let { "$it · ${context.range(b)}" } ?: context.range(b) } ?: stringResource(R.string.focusNoShift),
                            style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant,
                        )
                        OutlinedButton(onClick = onAdd) { Text(stringResource(R.string.focusQuickCreate)) }
                    }
                }
            }
            if (!model.isLocked) {
                graph.focus.planning(context.state).appliedTemplate(context.state, context.nowMs)?.let {
                    Text(
                        Strings.focusAppliedTemplateNote(res, it.name),
                        Modifier.padding(start = 18.dp, end = 18.dp, bottom = 12.dp),
                        style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant,
                    )
                }
            }
            if (session != null && session.plannedEndAtMs > context.nowMs) {
                val tint = if (session.kind == FocusSessionKind.FOCUS) scheme.primary else LocalDoneAtRecordsColors.current.workBreak
                val progress = rememberTicker(graph)
                LinearProgressIndicator(
                    progress = { ((progress - session.startedAtMs) / (session.plannedEndAtMs - session.startedAtMs)).toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, bottom = 16.dp),
                    color = tint,
                )
            }
        }
    }
}

/** Seconds, only where a countdown is drawn; the page itself moves on the minute. */
@Composable
private fun rememberTicker(graph: AppGraph): Double {
    var now by remember { mutableDoubleStateOf(graph.nowMs()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = graph.nowMs()
            delay(1_000 - (now % 1_000).toLong())
        }
    }
    return now
}

@Composable
private fun Countdown(context: FocusContext, targetMs: Double, graph: AppGraph? = null) {
    val now = if (graph != null) rememberTicker(graph) else context.nowMs
    Text(
        context.text.duration((targetMs - now).coerceAtLeast(0.0)),
        style = MaterialTheme.typography.headlineMedium.copy(fontFeatureSettings = "tnum"),
        fontWeight = FontWeight.SemiBold,
    )
}

@Composable
private fun Running(graph: AppGraph, context: FocusContext, session: FocusSession, onStop: () -> Unit, onExtend: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val res = LocalResources.current
    val title = when (session.kind) {
        FocusSessionKind.SHORT_BREAK -> stringResource(R.string.focusShortBreak)
        FocusSessionKind.LONG_BREAK -> stringResource(R.string.focusLongBreak)
        FocusSessionKind.FOCUS -> context.task(session.taskID)?.title ?: stringResource(R.string.focusRunning)
    }
    val continuation = graph.focus.planning(context.state).continuationTaskID(context.state, context.nowMs)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                title, style = MaterialTheme.typography.labelLarge, maxLines = 2, overflow = TextOverflow.Ellipsis,
                color = if (session.kind == FocusSessionKind.FOCUS) scheme.primary else LocalDoneAtRecordsColors.current.workBreak,
            )
            Countdown(context, session.plannedEndAtMs, graph)
            Text(Strings.focusEndsAt(res, context.text.time(session.plannedEndAtMs)), style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant)
        }
        if (continuation != null) {
            FilledTonalIconButton(onClick = { onExtend(continuation) }) { Icon(Icons.Outlined.Add, stringResource(R.string.focusExtendOne)) }
        }
        FilledTonalIconButton(onClick = onStop) { Icon(Icons.Outlined.Stop, stringResource(R.string.focusStop)) }
    }
}

@Composable
private fun Idle(graph: AppGraph, context: FocusContext, block: FocusDayCanvas.Block, onStart: (FocusDayCanvas.Block) -> Unit, onAdd: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                stringResource(if (context.nextAction == FocusNextAction.START_NEXT_FOCUS) R.string.focusStartNextFocus else R.string.focusThisBlock),
                style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant,
            )
            Text(block.taskTitle ?: context.range(block), style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(if (block.taskTitle == null) stringResource(R.string.focusBandEmptyBlock) else context.range(block), style = MaterialTheme.typography.labelMedium, color = scheme.onSurfaceVariant)
        }
        val task = context.task(block.taskID)
        if (task != null) {
            val ready = graph.focus.engine(context.state).availability(context.state, task, context.nowMs) == FocusStartAvailability.Ready &&
                block.endAtMs - context.nowMs >= 60_000
            Button(onClick = { onStart(block) }, enabled = ready) {
                Icon(Icons.Outlined.PlayArrow, null, Modifier.size(18.dp))
                Text(stringResource(R.string.focusStart), Modifier.padding(start = 4.dp))
            }
        } else {
            Button(onClick = onAdd, enabled = graph.focus.engine(context.state).hasRoom(context.nowMs)) { Text(stringResource(R.string.focusQuickCreate)) }
        }
    }
}

/** Under the band: progress is done of scheduled, what you drew, while the estimate stays what you meant. */
@Composable
private fun TaskLedger(graph: AppGraph, context: FocusContext, onEdit: (String) -> Unit, onExtend: (String) -> Unit) {
    val model = context.canvas
    if (model.tasks.isEmpty()) return
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val scheme = MaterialTheme.colorScheme
    val planning = graph.focus.planning(context.state)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(stringResource(R.string.focusTodayTasks), Modifier.padding(start = 16.dp).semantics { heading() }, style = MaterialTheme.typography.titleSmall, color = scheme.onSurfaceVariant)
        RecordsCard {
            Column {
                model.tasks.forEachIndexed { index, row ->
                    if (index > 0) HorizontalDivider(Modifier.padding(start = 56.dp), color = scheme.outlineVariant)
                    val task = context.task(row.id)
                    val favorite = planning.savedFavorite(context.state, row.title, row.icon)
                    var menu by remember { mutableStateOf(false) }
                    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (favorite != null) Icons.Outlined.Star else row.icon.image, null, tint = scheme.onSurfaceVariant)
                        Column(Modifier.weight(1f).padding(horizontal = 16.dp)) {
                            Text(row.title, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Text(
                                if (row.isScheduled) Strings.focusBlocksDoneOfScheduled(res, row.completedBlocks.toString(), row.assignedBlocks.toString()) else stringResource(R.string.focusUnscheduled),
                                style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant,
                            )
                        }
                        when {
                            row.isRunning -> Text(stringResource(R.string.focusRunning), style = MaterialTheme.typography.labelMedium, color = scheme.primary)
                            row.isDone -> Icon(Icons.Outlined.Check, null, Modifier.size(16.dp), tint = scheme.onSurfaceVariant)
                        }
                        if (task != null) {
                            Box {
                                IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreHoriz, "${stringResource(R.string.moreActions)} · ${row.title}") }
                                DropdownMenu(menu, { menu = false }) {
                                    DropdownMenuItem({ Text(stringResource(R.string.focusEditTask)) }, { menu = false; onEdit(task.id) }, leadingIcon = { Icon(Icons.Outlined.Edit, null) })
                                    DropdownMenuItem(
                                        { Text(stringResource(R.string.focusStartNow)) },
                                        { menu = false; scope.launch { graph.focus.start(task.id, graph.nowMs()) } },
                                        leadingIcon = { Icon(Icons.Outlined.PlayArrow, null) },
                                        enabled = graph.focus.engine(context.state).availability(context.state, task, context.nowMs) == FocusStartAvailability.Ready,
                                    )
                                    DropdownMenuItem({ Text(stringResource(R.string.focusExtendOne)) }, { menu = false; onExtend(task.id) }, leadingIcon = { Icon(Icons.Outlined.Add, null) })
                                    DropdownMenuItem(
                                        { Text(stringResource(if (favorite != null) R.string.focusRemoveFavorite else R.string.focusMakeFavorite)) },
                                        { menu = false; scope.launch { graph.focus.edit { state, p -> p.toggleFavorite(state, (favorite ?: task).id, graph.nowMs()) } } },
                                        leadingIcon = { Icon(if (favorite != null) Icons.Outlined.Star else Icons.Outlined.StarOutline, null) },
                                    )
                                    DropdownMenuItem(
                                        { Text(stringResource(R.string.focusDeleteTask), color = scheme.error) },
                                        { menu = false; scope.launch { graph.focus.plan { state, p -> p.deleteTask(state, task.id, graph.nowMs()) } } },
                                        leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = scheme.error) },
                                        enabled = !row.isRunning,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        if (model.overflow.isNotEmpty()) {
            Text(
                Strings.focusOverflowNote(res, model.overflow.joinToString("、") { it.title }),
                Modifier.padding(horizontal = 6.dp), style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Without Plus: a fixed sample day previews the canvas, reading and saving
 * none of the user's plan (iOS `FocusLockedCanvas`).
 */
@Composable
private fun LockedCanvas(context: FocusContext, onUnlock: () -> Unit) {
    val res = LocalResources.current
    val start = java.time.LocalDate.now().atTime(9, 0).atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
    val samples = listOf(
        Triple(0, 25, R.string.focusDemoWriting to FocusTaskIcon.WRITING), Triple(25, 30, null), Triple(30, 55, R.string.focusDemoWriting to FocusTaskIcon.WRITING),
        Triple(55, 60, null), Triple(60, 85, R.string.focusDemoMessages to FocusTaskIcon.COMMUNICATION), Triple(85, 90, null),
        Triple(90, 115, R.string.focusDemoLearning to FocusTaskIcon.STUDY), Triple(115, 130, null),
    )
    val demo = FocusDayCanvas.empty(25, isLocked = true).copy(
        shiftStartAtMs = start,
        shiftEndAtMs = start + 130 * 60_000L,
        blocks = samples.mapIndexed { index, (from, to, task) ->
            FocusDayCanvas.Block(
                index, start + from * 60_000L, start + to * 60_000L,
                if (task == null) FocusPlanBlockKind.BREAK_TIME else FocusPlanBlockKind.TASK, FocusDayCanvas.State.FUTURE,
                taskID = task?.let { "demo" }, taskTitle = task?.let { res.getString(it.first) }, taskIcon = task?.second,
            )
        },
    )
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(stringResource(R.string.focusLockedBand), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        FocusBand(FocusContext(context.nowMs, context.state, demo, null, FocusNextAction.NONE, false, context.text), demo, null, isPreview = true) { onUnlock() }
    }
}
