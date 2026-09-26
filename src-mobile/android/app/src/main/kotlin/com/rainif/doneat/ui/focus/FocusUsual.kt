package com.rainif.doneat.ui.focus

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.DragHandle
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.SaveAlt
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.focus.FocusTemplateTask
import com.rainif.doneat.core.domain.focus.FocusTemplates
import com.rainif.doneat.core.domain.focus.Planned
import com.rainif.doneat.core.domain.records.FocusTask
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import com.rainif.doneat.core.domain.records.FocusTemplate
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.timer.Haptics
import kotlinx.coroutines.launch

/** The Focus page's two scales (iOS `FocusCanvasScale`), remembered on the device. */
enum class FocusScale(val key: String) {
    TODAY("today"),
    USUAL("usual");

    companion object {
        fun of(key: String) = entries.firstOrNull { it.key == key } ?: TODAY
    }
}

/**
 * The usual-day editor's working copy (iOS `FocusTemplateDraft` and the
 * editor's own state). It lives on the graph so the task page opened from it
 * edits the same list; nothing is written before Save.
 */
data class FocusTemplateDraft(
    val templateID: String?,
    val name: String,
    val tasks: List<FocusTemplateTask>,
    val favoriteChanges: Map<String, Boolean> = emptyMap(),
)

/** A new usual day starts from today's plan; an existing one from its own tasks. */
private fun templateDraft(graph: AppGraph, template: FocusTemplate?, defaultName: String): FocusTemplateDraft {
    if (template != null) return FocusTemplateDraft(template.id, template.name, FocusTemplates.tasks(template.slots))
    val state = graph.records.state.value
    val slots = graph.focus.planning(state).templateDraftFromToday(state, graph.nowMs())
    return FocusTemplateDraft(null, defaultName, FocusTemplates.tasks(slots))
}

private val transparentRow
    @Composable get() = ListItemDefaults.colors(containerColor = Color.Transparent)

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        Modifier.padding(start = DoneAtSpacing.l).semantics { heading() },
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun Caption(text: String) {
    Text(text, Modifier.padding(horizontal = 6.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/** Keep task names on one line on phones; larger windows gain columns. */
@Composable
private fun <T> CardGrid(items: List<T>, card: @Composable (T, Modifier) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val columns = maxOf(1, ((maxWidth + 10.dp) / 250.dp).toInt())
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items.chunked(columns).forEach { row ->
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { card(it, Modifier.weight(1f).fillMaxHeight()) }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun FavoriteCard(title: String, icon: ImageVector, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    Surface(modifier, shape = RoundedCornerShape(14.dp), color = scheme.surfaceContainerLow, border = BorderStroke(1.dp, scheme.outlineVariant)) {
        Row(Modifier.heightIn(min = 48.dp).padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, null, Modifier.size(18.dp), tint = scheme.primary)
            Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, maxLines = 2)
        }
    }
}

/**
 * The Usual scale (iOS `FocusUsualScale`): favourites and usual days side by
 * side, the things that repeat across days rather than today's plan.
 */
@Composable
internal fun UsualScale(graph: AppGraph, context: FocusContext, open: (Route) -> Unit) {
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val scheme = MaterialTheme.colorScheme
    val planning = graph.focus.planning(context.state)
    val favorites = planning.favorites(context.state)
    val stored = planning.planning(context.state)
    var removing by remember { mutableStateOf<FocusTask?>(null) }
    var warnsCapacity by remember { mutableStateOf(false) }
    val landingHint = context.canvas.nextEmptyBlock?.let { Strings.focusFavoriteLands(res, context.text.time(it.startAtMs.toDouble())) }
        ?: stringResource(R.string.focusNoEmptyBlockShort)
    val defaultName = stringResource(R.string.focusUsualDayDefaultName)

    fun edit(template: FocusTemplate?) {
        graph.focusTemplateDraft.value = templateDraft(graph, template, defaultName)
        open(Route.FocusTemplateEdit(template?.id))
    }

    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        if (favorites.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SectionHeader(stringResource(R.string.focusFavorites))
                CardGrid(favorites) { task, modifier ->
                    Box(modifier) {
                        FavoriteCard(
                            task.title, Icons.Filled.Star,
                            Modifier.fillMaxSize().clip(RoundedCornerShape(14.dp)).combinedClickable(
                                // Says where it will land, so the tap is not a guess.
                                onClickLabel = landingHint,
                                onLongClickLabel = stringResource(R.string.focusRemoveFavorite),
                                onLongClick = { removing = task },
                                onClick = { open(Route.FocusCreate(null, true, task.id)) },
                            ),
                        )
                        DropdownMenu(expanded = removing?.id == task.id, onDismissRequest = { removing = null }) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.focusRemoveFavorite), color = scheme.error) },
                                onClick = {
                                    removing = null
                                    scope.launch { graph.focus.edit { state, p -> p.toggleFavorite(state, task.id, graph.nowMs()) } }
                                },
                            )
                        }
                    }
                }
                Caption(landingHint)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader(stringResource(R.string.focusUsualDays))
            Surface(shape = MaterialTheme.shapes.large, color = scheme.surfaceContainerLow) {
                Column {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.focusSaveTodayAsUsual)) },
                        supportingContent = { Text(stringResource(R.string.focusSaveTodayAsUsualDetail)) },
                        leadingContent = { Icon(Icons.Outlined.SaveAlt, null) },
                        trailingContent = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = scheme.onSurfaceVariant) },
                        colors = transparentRow,
                        modifier = Modifier.clickable(role = Role.Button) { edit(null) },
                    )
                    stored.templates.forEach { template ->
                        RowDivider()
                        TemplateRow(graph, context, template, isDefault = stored.defaultTemplateID == template.id, onEdit = { edit(template) }, onWarn = { warnsCapacity = true })
                    }
                }
            }
        }
        Caption(stringResource(R.string.focusCadenceNote))
    }

    if (warnsCapacity) {
        AlertDialog(
            onDismissRequest = { warnsCapacity = false },
            title = { Text(stringResource(R.string.focusTemplateCapacityWarning)) },
            text = { Text(stringResource(R.string.focusTemplateSequenceNote)) },
            confirmButton = { TextButton(onClick = { warnsCapacity = false }) { Text(stringResource(R.string.close)) } },
        )
    }
}

@Composable
private fun TemplateRow(graph: AppGraph, context: FocusContext, template: FocusTemplate, isDefault: Boolean, onEdit: () -> Unit, onWarn: () -> Unit) {
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val scheme = MaterialTheme.colorScheme
    var menu by remember { mutableStateOf(false) }
    val dropped = graph.focus.planning(context.state).templateFit(context.state, template.id, context.nowMs).second
    val filled = template.slots.count { it.kind == com.rainif.doneat.core.domain.records.FocusPlanBlockKind.TASK && it.taskTitle != null }
    val subtitle = listOfNotNull(
        Strings.focusTemplateSlots(res, filled.toString()),
        if (isDefault) stringResource(R.string.focusTemplateAuto) else null,
        if (dropped > 0) Strings.focusTemplateDropped(res, dropped.toString()) else null,
    ).joinToString(" · ")
    fun plan(op: suspend () -> Unit) {
        menu = false
        scope.launch { op() }
    }
    ListItem(
        headlineContent = { Text(template.name) },
        supportingContent = { Text(subtitle) },
        leadingContent = { Icon(if (isDefault) Icons.Filled.Star else Icons.Outlined.GridView, null, tint = if (isDefault) scheme.primary else scheme.onSurfaceVariant) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (dropped > 0) {
                    IconButton(onClick = onWarn) { Icon(Icons.Outlined.WarningAmber, stringResource(R.string.focusTemplateCapacityWarning), tint = scheme.primary) }
                }
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreHoriz, stringResource(R.string.moreActions), tint = scheme.onSurfaceVariant) }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.focusApplyTemplate)) }, onClick = {
                            plan { graph.focus.plan { state, p -> p.applyTemplate(state, template.id, graph.nowMs()) } }
                        })
                        DropdownMenuItem(text = { Text(stringResource(if (isDefault) R.string.focusUnsetDefaultTemplate else R.string.focusSetDefaultTemplate)) }, onClick = {
                            plan { graph.focus.edit { state, p -> p.setDefaultTemplate(state, if (isDefault) null else template.id, graph.nowMs()) } }
                        })
                        DropdownMenuItem(text = { Text(stringResource(R.string.focusTemplateDelete), color = scheme.error) }, onClick = {
                            plan { graph.focus.edit { state, p -> p.deleteTemplate(state, template.id, graph.nowMs()) } }
                        })
                    }
                }
            }
        },
        colors = transparentRow,
        modifier = Modifier.clickable(role = Role.Button, onClick = onEdit),
    )
}

/** Synthetic examples only; previewing Plus never reads or edits saved tasks (iOS `FocusLockedUsualScale`). */
@Composable
internal fun LockedUsualScale(res: android.content.res.Resources, onUnlock: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val samples = listOf(R.string.focusDemoWriting to FocusTaskIcon.WRITING, R.string.focusDemoMessages to FocusTaskIcon.COMMUNICATION, R.string.focusDemoLearning to FocusTaskIcon.STUDY)
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader(stringResource(R.string.focusFavorites))
            CardGrid(samples) { (title, icon), modifier ->
                FavoriteCard(stringResource(title), icon.image, modifier.clip(RoundedCornerShape(14.dp)).clickable(role = Role.Button, onClick = onUnlock))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader(stringResource(R.string.focusUsualDays))
            Surface(shape = MaterialTheme.shapes.large, color = scheme.surfaceContainerLow) {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.focusUsualDayDefaultName)) },
                    supportingContent = { Text(Strings.focusTemplateSlots(res, "4") + " · " + stringResource(R.string.focusTemplateAuto)) },
                    leadingContent = { Icon(Icons.Filled.Star, null, tint = scheme.primary) },
                    trailingContent = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = scheme.onSurfaceVariant) },
                    colors = transparentRow,
                    modifier = Modifier.clickable(role = Role.Button, onClick = onUnlock),
                )
            }
        }
        Caption(stringResource(R.string.focusCadenceNote))
    }
}

/**
 * A usual day (iOS `FocusTemplateEditorView`): task order and estimates only.
 * Actual times belong to the day it is applied to, so a shift edit cannot
 * turn a task into a break. Tasks reorder by dragging the handle, or with
 * Move up / Move down from the row's menu or an accessibility action; all
 * three make the same move.
 */
@Composable
fun FocusTemplateEditScreen(graph: AppGraph, templateID: String?, open: (Route) -> Unit, onBack: () -> Unit) {
    val context = rememberFocusContext(graph)
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val scheme = MaterialTheme.colorScheme
    val defaultName = stringResource(R.string.focusUsualDayDefaultName)
    val stored by graph.focusTemplateDraft.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) {
        // Recreated after the process was away: start again from what is saved.
        if (graph.focusTemplateDraft.value?.templateID != templateID || graph.focusTemplateDraft.value == null) {
            val template = templateID?.let { id -> graph.focus.planning(graph.records.state.value).planning(graph.records.state.value).templates.firstOrNull { it.id == id } }
            graph.focusTemplateDraft.value = templateDraft(graph, template, defaultName)
        }
    }
    val draft = stored ?: return
    fun update(change: (FocusTemplateDraft) -> FocusTemplateDraft) { graph.focusTemplateDraft.value = graph.focusTemplateDraft.value?.let(change) }
    fun leave() {
        onBack()
    }
    fun move(from: Int, to: Int) = update { d ->
        if (to !in d.tasks.indices || from !in d.tasks.indices) d
        else d.copy(tasks = d.tasks.toMutableList().apply { add(to, removeAt(from)) })
    }
    var saving by remember { mutableStateOf(false) }
    val blocks = graph.focus.planning(context.state).templateBlocks(context.state, context.nowMs)
    val omitted = draft.tasks.drop(FocusTemplates.fittingTaskCount(draft.tasks, blocks)).map { it.id }.toSet()
    val remaining = FocusTemplates.remainingPomodoros(draft.tasks, blocks)
    val focusMinutes = graph.focus.planning(context.state).settings(context.state).focusMinutes
    val canSave = draft.name.isNotBlank() && draft.tasks.isNotEmpty() && !saving

    fun save() {
        if (!canSave) return
        val submitted = draft
        saving = true
        scope.launch {
            val now = graph.nowMs()
            val saved = graph.focus.plan { state, p ->
                var s = state
                for (task in submitted.tasks) {
                    val favorite = submitted.favoriteChanges[task.id] ?: continue
                    s = if (favorite) p.saveFavorite(s, task.title, task.pomodoros, task.icon, now)
                    else p.savedFavorite(s, task.title, task.icon)?.let { p.toggleFavorite(s, it.id, now) } ?: s
                }
                val slots = FocusTemplates.slots(submitted.tasks, graph.newId)
                if (submitted.templateID != null) p.updateTemplate(s, submitted.templateID, submitted.name, slots, now)
                else p.saveTemplate(s, submitted.name, slots, now).let { Planned(it.state, it.value != null) }
            }
            saving = false
            if (saved == true) {
                Haptics.confirm(view)
                leave()
            }
        }
    }

    // Drag state: the row being dragged, how far it has moved since its last swap, and row heights to swap at.
    var dragging by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableFloatStateOf(0f) }
    val heights = remember { mutableStateMapOf<String, Int>() }

    DoneAtPage(
        stringResource(R.string.focusUsualDay), { leave() }, stringResource(R.string.focusTitle),
        actions = {
            TextButton(onClick = { save() }, enabled = canSave) { Text(stringResource(R.string.saveAction), fontWeight = FontWeight.SemiBold) }
        },
    ) {
        Column(Modifier.padding(horizontal = DoneAtSpacing.page)) {
            OutlinedTextField(
                draft.name, { name -> update { it.copy(name = name.take(60)) } },
                Modifier.fillMaxWidth(), singleLine = true,
                label = { Text(stringResource(R.string.focusUsualDayName)) },
            )
        }
        SettingsGroup(footer = stringResource(R.string.focusTemplateSequenceNote)) {
            draft.tasks.forEachIndexed { index, task ->
                key(task.id) {
                    if (index > 0) RowDivider()
                    val isDragged = dragging == task.id
                    var menu by remember { mutableStateOf(false) }
                    val moveUp = stringResource(R.string.focusTemplateMoveUp)
                    val moveDown = stringResource(R.string.focusTemplateMoveDown)
                    Row(
                        Modifier
                            .zIndex(if (isDragged) 1f else 0f)
                            .graphicsLayer {
                                translationY = if (isDragged) dragOffset else 0f
                                shadowElevation = if (isDragged) 8.dp.toPx() else 0f
                            }
                            .background(if (isDragged) scheme.surfaceContainerHigh else Color.Transparent)
                            .onSizeChanged { heights[task.id] = it.height }
                            .clickable(role = Role.Button) { open(Route.FocusTemplateTask(task.id)) }
                            .semantics {
                                customActions = listOfNotNull(
                                    CustomAccessibilityAction(moveUp) { move(index, index - 1); true }.takeIf { index > 0 },
                                    CustomAccessibilityAction(moveDown) { move(index, index + 1); true }.takeIf { index < draft.tasks.lastIndex },
                                )
                            }
                            .padding(start = DoneAtSpacing.l, top = 8.dp, bottom = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(task.icon.image, null, Modifier.size(24.dp), tint = scheme.primary)
                        Column(Modifier.weight(1f).padding(start = DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(task.title, style = MaterialTheme.typography.bodyLarge)
                            Text(Strings.focusEstimateDetail(res, task.pomodoros.toString(), focusMinutes.toString()), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
                            if (task.id in omitted) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Icon(Icons.Outlined.WarningAmber, null, Modifier.size(14.dp), tint = scheme.primary)
                                    Text(stringResource(R.string.focusTemplateTaskDoesNotFit), style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant)
                                }
                            }
                        }
                        Box {
                            IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreHoriz, stringResource(R.string.moreActions), tint = scheme.onSurfaceVariant) }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                if (index > 0) DropdownMenuItem(text = { Text(moveUp) }, onClick = { menu = false; move(index, index - 1) })
                                if (index < draft.tasks.lastIndex) DropdownMenuItem(text = { Text(moveDown) }, onClick = { menu = false; move(index, index + 1) })
                                DropdownMenuItem(text = { Text(stringResource(R.string.focusDeleteTask), color = scheme.error) }, onClick = {
                                    menu = false
                                    update { d -> d.copy(tasks = d.tasks.filter { it.id != task.id }) }
                                })
                            }
                        }
                        Icon(
                            Icons.Outlined.DragHandle, null,
                            Modifier
                                .size(48.dp)
                                .padding(12.dp)
                                // The accessibility actions above stand in for the drag.
                                .clearAndSetSemantics {}
                                .pointerInput(task.id) {
                                    detectDragGestures(
                                        onDragStart = { dragging = task.id; dragOffset = 0f; view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS) },
                                        onDragEnd = { dragging = null; dragOffset = 0f },
                                        onDragCancel = { dragging = null; dragOffset = 0f },
                                    ) { change, amount ->
                                        change.consume()
                                        dragOffset += amount.y
                                        val tasks = graph.focusTemplateDraft.value?.tasks ?: return@detectDragGestures
                                        val at = tasks.indexOfFirst { it.id == task.id }
                                        val neighbour = if (dragOffset > 0) tasks.getOrNull(at + 1) else tasks.getOrNull(at - 1)
                                        val height = neighbour?.let { heights[it.id] } ?: return@detectDragGestures
                                        if (kotlin.math.abs(dragOffset) > height / 2f) {
                                            move(at, if (dragOffset > 0) at + 1 else at - 1)
                                            dragOffset -= if (dragOffset > 0) height else -height
                                            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                                        }
                                    }
                                },
                            tint = scheme.onSurfaceVariant,
                        )
                    }
                }
            }
            if (draft.tasks.isNotEmpty()) RowDivider()
            ListItem(
                headlineContent = { Text(stringResource(R.string.focusNewTask), color = if (remaining > 0) scheme.primary else scheme.onSurface.copy(alpha = 0.38f)) },
                supportingContent = { Text(Strings.focusTemplateRemainingPomodoros(res, remaining.toString())) },
                leadingContent = { Icon(Icons.Outlined.Add, null, tint = if (remaining > 0) scheme.primary else scheme.onSurface.copy(alpha = 0.38f)) },
                colors = transparentRow,
                modifier = Modifier.clickable(enabled = remaining > 0, role = Role.Button) { open(Route.FocusTemplateTask(null)) },
            )
        }
    }
}

/**
 * One task of a usual day (iOS `FocusTaskEditorShell` in the template
 * editor): what it is and how many blocks, capped by what the shift has left.
 * It edits the editor's working copy; the usual day saves both.
 */
@Composable
fun FocusTemplateTaskScreen(graph: AppGraph, taskID: String?, onBack: () -> Unit) {
    val context = rememberFocusContext(graph)
    val res = LocalResources.current
    val template by graph.focusTemplateDraft.collectAsStateWithLifecycle()
    val parent = template
    if (parent == null) {
        LaunchedEffect(Unit) { onBack() }
        return
    }
    val planning = graph.focus.planning(context.state)
    val existing = parent.tasks.firstOrNull { it.id == taskID }
    var draft by remember {
        mutableStateOf(
            TaskDraft(
                title = existing?.title.orEmpty(),
                icon = existing?.icon ?: FocusTaskIcon.FOCUS,
                pomodoros = existing?.pomodoros ?: 1,
                isFavorite = existing?.let { t -> parent.favoriteChanges[t.id] ?: (planning.savedFavorite(context.state, t.title, t.icon) != null) } ?: false,
            ),
        )
    }
    val capacity = FocusTemplates.remainingPomodoros(parent.tasks, planning.templateBlocks(context.state, context.nowMs), excluding = taskID)

    fun save() {
        if (!draft.canSave) return
        val edited = FocusTemplateTask(
            taskKey = existing?.taskKey ?: graph.newId(),
            legacyIndex = existing?.legacyIndex ?: parent.tasks.size,
            title = draft.title.trim(),
            icon = draft.icon,
            pomodoros = draft.pomodoros,
        )
        graph.focusTemplateDraft.value = graph.focusTemplateDraft.value?.let { d ->
            val tasks = if (existing != null) d.tasks.map { if (it.id == existing.id) edited else it } else d.tasks + edited
            d.copy(tasks = tasks, favoriteChanges = d.favoriteChanges - existing?.id.orEmpty() + (edited.id to draft.isFavorite))
        }
        onBack()
    }

    DoneAtPage(
        stringResource(if (existing != null) R.string.focusEditTask else R.string.focusNewTask), onBack, stringResource(R.string.focusUsualDay),
        actions = {
            TextButton(onClick = { save() }, enabled = draft.canSave) { Text(stringResource(R.string.saveAction), fontWeight = FontWeight.SemiBold) }
        },
    ) {
        TaskFields(
            context, draft, { draft = it }, finish = null, showsFinish = false, referenceMs = context.nowMs,
            maximum = maxOf(1, capacity), capacityNote = Strings.focusTemplateRemainingPomodoros(res, capacity.toString()),
        )
        TaskOptions(context, draft, planning.favorites(context.state), onChange = { draft = it })
        if (existing != null) {
            Column(Modifier.padding(horizontal = DoneAtSpacing.page)) {
                OutlinedButton(onClick = {
                    graph.focusTemplateDraft.value = graph.focusTemplateDraft.value?.let { d -> d.copy(tasks = d.tasks.filter { it.id != existing.id }) }
                    onBack()
                }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.focusDeleteTask), color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}
