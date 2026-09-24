package com.rainif.doneat.ui.focus

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.PostAdd
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.focus.FocusPlacement
import com.rainif.doneat.core.domain.focus.FocusStartAvailability
import com.rainif.doneat.core.domain.records.FocusTask
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.FocusTimerSettings
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.PageFooter
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow
import com.rainif.doneat.ui.timer.Haptics
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/** The fields every creation path shares (iOS `FocusTaskEditorDraft`). */
private data class TaskDraft(
    val title: String = "",
    val icon: FocusTaskIcon = FocusTaskIcon.FOCUS,
    val pomodoros: Int = 1,
    val isFavorite: Boolean = false,
    val favoriteID: String? = null,
    val existingTaskID: String? = null,
) {
    val canSave get() = title.isNotBlank()

    fun selecting(task: FocusTask, favorite: Boolean, remaining: Int? = null) = copy(
        title = task.title, icon = task.icon, pomodoros = maxOf(1, remaining ?: task.estimatedPomodoros), isFavorite = favorite,
        favoriteID = if (favorite) task.id else null, existingTaskID = if (favorite) null else task.id,
    )
}

private enum class Landing { NEXT_BLOCK, START_NOW, UNSCHEDULED }

/** "Today · 10:30", "Tomorrow · 09:00", or a date. */
private fun dayAndTime(context: FocusContext, res: android.content.res.Resources, atMs: Double, referenceMs: Double): String {
    val zone = ZoneId.systemDefault()
    val day = Instant.ofEpochMilli(atMs.toLong()).atZone(zone).toLocalDate()
    val reference = Instant.ofEpochMilli(referenceMs.toLong()).atZone(zone).toLocalDate()
    val label = when (day) {
        reference -> res.getString(R.string.focusToday)
        reference.plusDays(1) -> res.getString(R.string.tomorrow)
        else -> java.time.format.DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(context.text.locale, "MMMd"), context.text.locale).format(day)
    }
    return "$label · ${context.text.time(atMs)}"
}

/**
 * Creating a task (iOS `FocusQuickCreateSheet`): what it is, how many blocks,
 * where it lands. Creation and placement are one action; landing in a block
 * is the default, starting now and keeping a favourite for later are the others.
 */
@Composable
fun FocusCreateScreen(graph: AppGraph, blockStartAtMs: Long?, currentOrNext: Boolean, favoriteID: String?, onBack: () -> Unit) {
    val context = rememberFocusContext(graph)
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val planning = graph.focus.planning(context.state)
    val engine = graph.focus.engine(context.state)
    val favorites = planning.favorites(context.state)
    var draft by remember {
        mutableStateOf(favorites.firstOrNull { it.id == favoriteID }?.let { TaskDraft().selecting(it, favorite = true) } ?: TaskDraft())
    }
    var landing by rememberSaveable { mutableStateOf(Landing.NEXT_BLOCK) }
    var submitting by remember { mutableStateOf(false) }
    val tasks = planning.tasksForPage(context.state, context.nowMs).filter { it.completedAtMs == null }
    val existing = tasks.firstOrNull { it.id == draft.existingTaskID }
    val target = blockStartAtMs ?: context.canvas.nextEmptyBlock?.startAtMs
    val canStart = existing?.let { engine.availability(context.state, it, context.nowMs) == FocusStartAvailability.Ready }
        ?: (context.session == null && engine.hasRoom(context.nowMs))
    val finish = graph.focus.creationFinish(draft.pomodoros, target, landing == Landing.START_NOW, draft.existingTaskID, context.nowMs)
    val canSave = draft.canSave && !submitting &&
        (landing != Landing.START_NOW || canStart) &&
        (landing != Landing.UNSCHEDULED || draft.isFavorite) &&
        (draft.existingTaskID == null || landing != Landing.NEXT_BLOCK || target != null)

    fun finishWith(result: FocusPlacement?) {
        placementNotice(result, res)?.let { graph.focusNotice.value = it; Haptics.warn(view) } ?: Haptics.confirm(view)
        onBack()
    }
    fun save() {
        if (!canSave) return
        val submitted = draft
        submitting = true
        scope.launch {
            val now = graph.nowMs()
            when {
                landing == Landing.UNSCHEDULED -> {
                    graph.focus.edit { state, p -> p.saveFavorite(state, submitted.title.trim(), submitted.pomodoros, submitted.icon, now) }
                    finishWith(null)
                }
                landing == Landing.START_NOW -> {
                    val started = if (submitted.existingTaskID != null) {
                        graph.focus.updateAndStart(submitted.existingTaskID, submitted.pomodoros, now).also { ok ->
                            if (ok && submitted.isFavorite) graph.focus.edit { state, p -> p.saveFavorite(state, submitted.title.trim(), submitted.pomodoros, submitted.icon, now) }
                        }
                    } else {
                        graph.focus.addAndStart(submitted.title, submitted.pomodoros, submitted.icon, submitted.isFavorite, now)
                    }
                    if (started) finishWith(null) else submitting = false
                }
                submitted.existingTaskID != null -> finishWith(
                    graph.focus.plan { state, p ->
                        p.place(state, submitted.existingTaskID, submitted.pomodoros, target ?: return@plan com.rainif.doneat.core.domain.focus.Planned(state, FocusPlacement.NoShift), now, additionalPomodoros = submitted.pomodoros, makeFavorite = submitted.isFavorite)
                    },
                )
                blockStartAtMs != null -> finishWith(
                    graph.focus.plan { state, p -> p.createInBlock(state, submitted.title.trim(), blockStartAtMs, now, submitted.icon, submitted.pomodoros, submitted.isFavorite, scheduleAllPomodoros = true) },
                )
                else -> finishWith(
                    graph.focus.plan { state, p -> p.createInNextEmptyBlock(state, submitted.title.trim(), now, submitted.pomodoros, submitted.icon, submitted.isFavorite, scheduleAllPomodoros = true) },
                )
            }
        }
    }

    DoneAtPage(
        stringResource(R.string.focusNewTask), onBack, stringResource(R.string.focusTitle),
        actions = {
            TextButton(onClick = ::save, enabled = canSave) {
                Text(stringResource(if (landing == Landing.START_NOW) R.string.focusAddAndStart else R.string.focusSaveTask), fontWeight = FontWeight.SemiBold)
            }
        },
    ) {
        TaskFields(context, draft, { draft = it }, finish = if (landing == Landing.UNSCHEDULED) null else finish, showsFinish = landing != Landing.UNSCHEDULED,
            referenceMs = if (landing == Landing.START_NOW) context.nowMs else target?.toDouble() ?: context.nowMs)
        val destination = target?.let { dayAndTime(context, res, it.toDouble(), context.nowMs) } ?: stringResource(R.string.focusNoEmptyBlockShort)
        SettingsGroup(title = stringResource(R.string.focusLanding)) {
            if ((blockStartAtMs == null && !currentOrNext) || draft.isFavorite) {
                LandingRow(Icons.Outlined.PostAdd, stringResource(R.string.focusLandingNextBlock), destination, landing == Landing.NEXT_BLOCK, true) { landing = Landing.NEXT_BLOCK }
                RowDivider()
                val reason = when {
                    canStart -> null
                    context.session != null -> stringResource(R.string.focusStartAlreadyRunning)
                    !engine.isWithinWorkTime(context.nowMs) -> stringResource(R.string.focusOutsideWorkHours)
                    else -> (existing?.let { engine.availability(context.state, it, context.nowMs) } as? FocusStartAvailability.NotYetAvailable)
                        ?.let { Strings.focusStartAfter(res, dayAndTime(context, res, it.atMs, context.nowMs)) } ?: stringResource(R.string.focusNoRoom)
                }
                LandingRow(Icons.Outlined.PlayArrow, stringResource(R.string.focusStartNow), reason, landing == Landing.START_NOW, canStart) { landing = Landing.START_NOW }
                if (draft.isFavorite) {
                    RowDivider()
                    LandingRow(Icons.Outlined.Inbox, stringResource(R.string.focusLeaveUnscheduled), null, landing == Landing.UNSCHEDULED, true) { landing = Landing.UNSCHEDULED }
                }
            } else {
                LandingRow(
                    Icons.Outlined.PostAdd, stringResource(if (blockStartAtMs == null) R.string.focusLandingNextBlock else R.string.focusThisBlock),
                    destination, selected = false, enabled = true, onClick = null,
                )
            }
        }
        TaskOptions(context, draft, favorites, onChange = { next ->
            draft = next
            if (!next.isFavorite && landing == Landing.UNSCHEDULED) landing = Landing.NEXT_BLOCK
        })
        if (tasks.isNotEmpty()) {
            SettingsGroup(title = stringResource(R.string.focusBlockExisting)) {
                tasks.forEachIndexed { index, task ->
                    if (index > 0) RowDivider()
                    val remaining = maxOf(1, task.estimatedPomodoros - engine.completedBlocks(context.state, task))
                    OptionRow(task.icon, task.title, Strings.focusEstimateDetail(res, remaining.toString(), planning.settings(context.state).focusMinutes.toString()), draft.existingTaskID == task.id) {
                        draft = draft.selecting(task, favorite = false, remaining = remaining)
                            .copy(isFavorite = planning.savedFavorite(context.state, task.title, task.icon) != null)
                    }
                }
            }
        }
        if (blockStartAtMs != null) {
            OutlinedButton(
                onClick = {
                    scope.launch {
                        graph.focus.edit { state, p -> p.markBlockAsBreak(state, blockStartAtMs, graph.nowMs()) }
                        onBack()
                    }
                },
                modifier = Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page),
            ) { Text(stringResource(R.string.focusBlockMakeBreak)) }
        }
    }
}

/** Editing a placed task (iOS `FocusTaskEditSheet`): it can shrink only to the blocks already done or running. */
@Composable
fun FocusTaskEditScreen(graph: AppGraph, taskID: String, onBack: () -> Unit) {
    val context = rememberFocusContext(graph)
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val planning = graph.focus.planning(context.state)
    val task = context.task(taskID) ?: return
    val protectedCount = planning.protectedPomodoros(context.state, task, context.nowMs)
    var draft by remember(taskID) {
        mutableStateOf(
            TaskDraft().selecting(task, favorite = false).copy(
                isFavorite = planning.savedFavorite(context.state, task.title, task.icon) != null,
                pomodoros = maxOf(task.estimatedPomodoros, protectedCount),
            ),
        )
    }
    val proposed = planning.editedTaskBlocks(context.state, task, draft.pomodoros, context.nowMs)
    val canSave = draft.canSave && (draft.pomodoros == task.estimatedPomodoros || proposed != null)
    DoneAtPage(
        stringResource(R.string.focusEditTask), onBack, stringResource(R.string.focusTitle),
        actions = {
            TextButton(enabled = canSave, onClick = {
                val submitted = draft
                scope.launch {
                    val saved = graph.focus.plan { state, p -> p.editTask(state, taskID, submitted.title.trim(), submitted.icon, submitted.pomodoros, submitted.isFavorite, graph.nowMs()) }
                    if (saved == true) {
                        Haptics.confirm(view)
                        onBack()
                    }
                }
            }) { Text(stringResource(R.string.saveAction), fontWeight = FontWeight.SemiBold) }
        },
    ) {
        PageFooter(task.scheduledStartAtMs?.let { Strings.focusFavoriteLands(res, dayAndTime(context, res, it, context.nowMs)) } ?: stringResource(R.string.focusLeaveUnscheduled))
        TaskFields(
            context, draft, { draft = it }, finish = proposed?.lastOrNull()?.endAtMs?.toDouble(), showsFinish = task.scheduledStartAtMs != null,
            referenceMs = context.nowMs, minimum = maxOf(1, protectedCount),
        )
        TaskOptions(context, draft, planning.favorites(context.state), onChange = { draft = it })
        OutlinedButton(
            onClick = {
                scope.launch {
                    if (graph.focus.plan { state, p -> p.deleteTask(state, taskID, graph.nowMs()) } == true) onBack()
                }
            },
            enabled = context.session?.taskID != taskID,
            modifier = Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page),
        ) { Text(stringResource(R.string.focusDeleteTask), color = MaterialTheme.colorScheme.error) }
    }
}

/** Title, estimate and the finish it implies. */
@Composable
private fun TaskFields(
    context: FocusContext,
    draft: TaskDraft,
    onChange: (TaskDraft) -> Unit,
    finish: Double?,
    showsFinish: Boolean,
    referenceMs: Double,
    minimum: Int = 1,
) {
    val res = LocalResources.current
    val scheme = MaterialTheme.colorScheme
    val focusMinutes = (context.state.focusPlanningConfiguration?.timerSettings?.normalized?.focusMinutes) ?: 25
    Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = draft.title,
            // A different title is a different task: it no longer picks the existing task or favourite.
            onValueChange = { onChange(draft.copy(title = it.take(80), existingTaskID = null, favoriteID = null)) },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(stringResource(R.string.focusTaskPlaceholder)) },
            leadingIcon = { Icon(draft.icon.image, null) },
            singleLine = true,
            label = { Text(stringResource(R.string.focusTaskTitle)) },
        )
    }
    SettingsGroup {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = DoneAtSpacing.l, end = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.focusEstimate), style = MaterialTheme.typography.bodyLarge)
                Text(Strings.focusEstimateDetail(res, draft.pomodoros.toString(), focusMinutes.toString()), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
            }
            IconButton(onClick = { onChange(draft.copy(pomodoros = draft.pomodoros - 1)) }, enabled = draft.pomodoros > minimum) {
                Icon(Icons.Outlined.Remove, stringResource(R.string.focusEstimate))
            }
            Text(
                draft.pomodoros.toString(),
                Modifier.semantics { stateDescription = draft.pomodoros.toString() },
                style = MaterialTheme.typography.titleMedium,
            )
            IconButton(onClick = { onChange(draft.copy(pomodoros = draft.pomodoros + 1)) }, enabled = draft.pomodoros < maxOf(12, minimum)) {
                Icon(Icons.Outlined.Add, stringResource(R.string.focusEstimate))
            }
        }
        if (showsFinish) {
            Text(
                finish?.let { Strings.focusEstimatedFinish(res, dayAndTime(context, res, it, referenceMs)) } ?: stringResource(R.string.focusNoRoomThisShift),
                Modifier.padding(start = DoneAtSpacing.l, end = DoneAtSpacing.l, bottom = 12.dp),
                style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant,
            )
        }
    }
}

/** Icon, favourite, and the favourites to start from. */
@Composable
private fun TaskOptions(context: FocusContext, draft: TaskDraft, favorites: List<FocusTask>, onChange: (TaskDraft) -> Unit) {
    val res = LocalResources.current
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.focusChooseIcon), Modifier.padding(start = DoneAtSpacing.l), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FocusTaskIcon.entries.forEach { option ->
                val selected = option == draft.icon
                Box(
                    Modifier.size(44.dp).clip(CircleShape).background(if (selected) scheme.primary else scheme.surfaceContainerHighest)
                        .clickable(role = Role.RadioButton) { onChange(if (option == draft.icon) draft else draft.copy(icon = option, existingTaskID = null, favoriteID = null)) }
                        .semantics { contentDescription = res.getString(option.title); this.selected = selected },
                    contentAlignment = Alignment.Center,
                ) { Icon(option.image, null, tint = if (selected) scheme.onPrimary else scheme.onSurfaceVariant) }
            }
        }
    }
    SettingsGroup {
        SwitchRow(stringResource(R.string.focusMakeFavorite), draft.isFavorite, { onChange(draft.copy(isFavorite = it)) })
    }
    if (favorites.isNotEmpty()) {
        val focusMinutes = context.state.focusPlanningConfiguration?.timerSettings?.normalized?.focusMinutes ?: 25
        SettingsGroup(title = stringResource(R.string.focusFavorites)) {
            favorites.forEachIndexed { index, task ->
                if (index > 0) RowDivider()
                OptionRow(task.icon, task.title, Strings.focusEstimateDetail(res, task.estimatedPomodoros.toString(), focusMinutes.toString()), draft.favoriteID == task.id) {
                    onChange(draft.selecting(task, favorite = true))
                }
            }
        }
    }
}

@Composable
private fun OptionRow(icon: FocusTaskIcon, title: String, subtitle: String, selected: Boolean, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.RadioButton, onClick = onClick).semantics { this.selected = selected }
            .padding(horizontal = DoneAtSpacing.l, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.l),
    ) {
        Icon(icon.image, null, tint = scheme.onSurfaceVariant)
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
        }
        if (selected) Icon(Icons.Outlined.Check, null, tint = scheme.primary)
    }
}

@Composable
private fun LandingRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, subtitle: String?, selected: Boolean, enabled: Boolean, onClick: (() -> Unit)?) {
    val scheme = MaterialTheme.colorScheme
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp)
            .then(if (onClick != null) Modifier.clickable(enabled = enabled, role = Role.RadioButton, onClick = onClick).semantics { this.selected = selected } else Modifier)
            .padding(horizontal = DoneAtSpacing.l, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.l),
    ) {
        Icon(icon, null, tint = scheme.onSurfaceVariant)
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = if (enabled) scheme.onSurface else scheme.outline)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
        }
        if (selected) Icon(Icons.Outlined.Check, null, tint = scheme.primary)
    }
}

/**
 * The pomodoro cadence and focus alerts (iOS `FocusTimerSettingsSheet`). The
 * cadence is locked while a phase runs or a usual day is saved, and the page
 * says so rather than dropping the change.
 */
@Composable
fun FocusTimerSettingsScreen(graph: AppGraph, onBack: () -> Unit) {
    val context = rememberFocusContext(graph)
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val planning = graph.focus.planning(context.state)
    val current = planning.settings(context.state)
    var focus by remember { mutableIntStateOf(current.focusMinutes) }
    var short by remember { mutableIntStateOf(current.shortBreakMinutes) }
    var long by remember { mutableIntStateOf(current.longBreakMinutes) }
    var every by remember { mutableIntStateOf(current.longBreakEvery) }
    var notifications by remember { mutableStateOf(device.focusNotificationsEnabled) }
    val lockMessage = when {
        context.session != null -> stringResource(R.string.focusTimerSettingsLockedRunning)
        planning.planning(context.state).templates.isNotEmpty() -> stringResource(R.string.focusTimerSettingsLockedTemplate)
        else -> null
    }
    fun save() {
        scope.launch {
            graph.settings.updateDevice { it.copy(focusNotificationsEnabled = notifications) }
            if (lockMessage == null) {
                val saved = graph.focus.plan { state, p -> p.updateTimerSettings(state, FocusTimerSettings(focus, short, long, every), graph.nowMs()) }
                if (saved != true) return@launch
            }
            onBack()
        }
    }
    DoneAtPage(
        stringResource(R.string.focusTimerSettings), onBack, stringResource(R.string.focusTitle),
        actions = { TextButton(onClick = ::save) { Text(stringResource(R.string.saveAction), fontWeight = FontWeight.SemiBold) } },
    ) {
        PageFooter(stringResource(R.string.focusTimerSettingsBody))
        SettingsGroup(title = stringResource(R.string.focusTimerSettingsSection)) {
            StepRow(stringResource(R.string.focusFocusDuration), Strings.minutesShort(res, focus.toString()), focus, 10..60, lockMessage == null) { focus = it }
            RowDivider(inset = false)
            StepRow(stringResource(R.string.focusShortBreakDuration), Strings.minutesShort(res, short.toString()), short, 1..15, lockMessage == null) { short = it }
            RowDivider(inset = false)
            StepRow(stringResource(R.string.focusLongBreakDuration), Strings.minutesShort(res, long.toString()), long, 5..30, lockMessage == null) { long = it }
            RowDivider(inset = false)
            StepRow(stringResource(R.string.focusLongBreakEvery), Strings.focusRoundsValue(res, every.toString()), every, 2..6, lockMessage == null) { every = it }
        }
        SettingsGroup {
            SwitchRow(stringResource(R.string.notificationLocal), notifications, { notifications = it })
        }
        if (lockMessage != null) {
            Row(Modifier.padding(horizontal = DoneAtSpacing.page + DoneAtSpacing.l), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Lock, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(lockMessage, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun StepRow(title: String, value: String, current: Int, range: IntRange, enabled: Boolean, onChange: (Int) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = DoneAtSpacing.l, end = DoneAtSpacing.xs).semantics(mergeDescendants = true) { stateDescription = value },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, color = if (enabled) scheme.onSurface else scheme.outline)
        Text(value, style = MaterialTheme.typography.bodyLarge, color = scheme.onSurfaceVariant)
        IconButton(onClick = { onChange(current - 1) }, enabled = enabled && current > range.first) { Icon(Icons.Outlined.Remove, "$title −") }
        IconButton(onClick = { onChange(current + 1) }, enabled = enabled && current < range.last) { Icon(Icons.Outlined.Add, "$title +") }
    }
}
