package com.rainif.doneat.ui.leave

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.Icon
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.expand
import androidx.compose.ui.semantics.collapse
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtLeaveTokens
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.domain.leave.LeavePlanGroup
import com.rainif.doneat.core.domain.leave.LeavePlanProposal
import com.rainif.doneat.core.domain.leave.LeavePlannerSchedule
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.RowDivider
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import java.time.DayOfWeek
import java.time.YearMonth
import kotlin.math.abs

private fun kindExists(groups: List<LeavePlanGroup>, kind: LeavePlanGroup.Category) = groups.any { it.category == kind }

/** Selection has no side effects. The sole gated action is the explicit details button. */
@Composable
internal fun LeavePlanResultsContent(proposals: List<LeavePlanProposal>, text: LeaveText, firstWeekday: DayOfWeek, opening: Boolean, onDetails: (Int) -> Unit) {
    val groups = remember(proposals) { LeavePlanGroup.make(proposals) }
    val first = groups.firstOrNull { it.category == LeavePlanGroup.Category.HOLIDAY } ?: groups.firstOrNull() ?: return
    var categoryName by rememberSaveable { mutableStateOf(first.category.name) }
    val category = LeavePlanGroup.Category.entries.firstOrNull { it.name == categoryName && kindExists(groups, it) } ?: first.category
    var groupID by rememberSaveable { mutableIntStateOf(first.id) }
    // Parallel saveable integer lists preserve each group's chosen date through recreation.
    var dateGroupIDs by rememberSaveable { mutableStateOf(intArrayOf()) }
    var dateIndices by rememberSaveable { mutableStateOf(intArrayOf()) }
    var showsDates by rememberSaveable { mutableStateOf(false) }
    val visible = groups.filter { it.category == category }.ifEmpty { groups.filter { it.category == first.category } }
    val group = visible.firstOrNull { it.id == groupID } ?: visible.first()
    val groupIndex = visible.indexOf(group)
    val savedIndex = dateGroupIDs.indexOf(group.id).takeIf { it >= 0 }?.let { dateIndices.getOrNull(it) }
    val selection = savedIndex?.takeIf { it in group.proposalIndices } ?: group.proposalIndices.first()
    val proposal = proposals[selection]
    val resources = LocalResources.current
    val view = LocalView.current
    val reduced = LocalDoneAtMotion.current.reduced

    fun selectGroup(index: Int) {
        if (index !in visible.indices || index == groupIndex) return
        groupID = visible[index].id
        view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
    }
    fun selectDate(index: Int) {
        val position = dateGroupIDs.indexOf(group.id)
        if (position < 0) {
            dateGroupIDs = dateGroupIDs + group.id
            dateIndices = dateIndices + index
        } else {
            dateIndices = dateIndices.copyOf().also { it[position] = index }
        }
        showsDates = false
        view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
    }

    Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
        Surface(modifier = arrival(0), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            LeavePlanCalendar(proposal, text, firstWeekday, Modifier.padding(DoneAtSpacing.l))
        }
        Column(arrival(1), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            val categories = LeavePlanGroup.Category.entries.filter { kind -> groups.any { it.category == kind } }
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                categories.forEachIndexed { index, kind ->
                    SegmentedButton(
                        selected = category == kind,
                        onClick = {
                            if (category != kind) {
                                categoryName = kind.name
                                groupID = groups.first { it.category == kind }.id
                                view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
                            }
                        },
                        modifier = Modifier.fillMaxHeight(),
                        shape = SegmentedButtonDefaults.itemShape(index, categories.size),
                        icon = {},
                    ) { Text(text.string(if (kind == LeavePlanGroup.Category.HOLIDAY) R.string.leaveHolidayPlans else R.string.leaveRegularPlans)) }
                }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                GroupArrow(-1, groupIndex > 0, text, ::selectGroup, groupIndex)
                Text(
                    Strings.leavePlanPosition(resources, text.wholeNumber(groupIndex + 1), text.wholeNumber(visible.size)),
                    Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                GroupArrow(1, groupIndex < visible.lastIndex, text, ::selectGroup, groupIndex)
            }
            Surface(
                modifier = Modifier.fillMaxWidth().groupSwipe(groupIndex, visible.size, ::selectGroup).semantics { selected = true },
                shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow,
                border = BorderStroke(DoneAtLeaveTokens.selectionStroke, MaterialTheme.colorScheme.primary.copy(alpha = DoneAtLeaveTokens.borderAlpha)),
            ) {
                Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    AnimatedContent(selection, transitionSpec = { (fadeIn(DoneAtLeaveTokens.navigation(reduced)) togetherWith fadeOut(DoneAtLeaveTokens.navigation(reduced))).using(null) }, label = "leaveOption") { index ->
                        OptionSummary(proposals[index], text)
                    }
                    if (group.proposalIndices.size > 1) {
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch).clickable(role = Role.Button) { showsDates = true },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(Strings.leaveAvailableDates(resources, text.wholeNumber(group.proposalIndices.size)), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.primary)
                            Icon(Icons.Outlined.UnfoldMore, null, tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
            DoneAtPrimaryButton(text.string(R.string.leaveViewDetails), { onDetails(selection) }, Modifier.fillMaxWidth(), enabled = !opening)
        }
    }
    if (showsDates) LeavePlanDateSheet(proposals, group.proposalIndices, selection, text, { showsDates = false }, ::selectDate)
}

@Composable
private fun OptionSummary(proposal: LeavePlanProposal, text: LeaveText) {
    val resources = LocalResources.current
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
            Text(text.range(text.monthDay(proposal.firstRestDayNumber), text.monthDay(proposal.lastRestDayNumber)), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(Strings.leaveDaysOff(resources, proposal.fullRestDays), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            Text(if (proposal.costHalfDays == 0) text.string(R.string.leaveNoLeaveNeeded) else text.uses(proposal.costHalfDays), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            // Keep the same small caveat slot as iOS, so certainty changes do not move the dates button.
            EstimatedLabel(proposal.caveats.isNotEmpty(), text)
        }
        Icon(Icons.Filled.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun EstimatedLabel(visible: Boolean, text: LeaveText) {
    Row(
        Modifier.graphicsLayer { alpha = if (visible) 1f else 0f }.then(if (visible) Modifier else Modifier.clearAndSetSemantics {}),
        horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.Info, null, Modifier.size(DoneAtSpacing.m), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text.string(R.string.leaveEstimated), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun GroupArrow(delta: Int, enabled: Boolean, text: LeaveText, select: (Int) -> Unit, index: Int) {
    IconButton(onClick = { select(index + delta) }, enabled = enabled, modifier = Modifier.background(MaterialTheme.colorScheme.surfaceContainerHighest, CircleShape)) {
        Icon(
            if (delta < 0) Icons.AutoMirrored.Outlined.KeyboardArrowLeft else Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            text.string(if (delta < 0) R.string.leavePreviousPlan else R.string.leaveNextPlan),
            tint = MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 1f else DoneAtLeaveTokens.inactiveAlpha),
        )
    }
}

@Composable
private fun Modifier.groupSwipe(index: Int, count: Int, select: (Int) -> Unit): Modifier {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val threshold = with(LocalDensity.current) { DoneAtLeaveTokens.swipeThreshold.toPx() }
    return pointerInput(index, count, rtl) {
        var horizontal = 0f
        var vertical = 0f
        detectHorizontalDragGestures(
            onDragStart = { horizontal = 0f; vertical = 0f },
            onHorizontalDrag = { change, amount -> horizontal += amount; vertical += change.positionChange().y },
            onDragEnd = {
                if (abs(horizontal) > threshold && abs(horizontal) > abs(vertical) * DoneAtLeaveTokens.horizontalDominance) {
                    val forward = if (rtl) horizontal > 0 else horizontal < 0
                    select(index + if (forward) 1 else -1)
                }
            },
        )
    }
}

@Composable
private fun arrival(index: Int): Modifier {
    val reduced = LocalDoneAtMotion.current.reduced
    var arrived by remember { mutableStateOf(false) }
    LaunchedEffect(reduced) {
        if (!reduced && !arrived) delay(DoneAtLeaveTokens.revealLeadMs + DoneAtLeaveTokens.delay(index))
        arrived = true
    }
    val alpha by animateFloatAsState(if (arrived) 1f else 0f, DoneAtLeaveTokens.fade(reduced), label = "leaveArrivalFade")
    val travel by animateFloatAsState(if (arrived || reduced) 0f else 1f, DoneAtLeaveTokens.reveal(reduced), label = "leaveArrivalRise")
    val distance = with(LocalDensity.current) { DoneAtLeaveTokens.arrivalTravel.toPx() }
    return Modifier.graphicsLayer { this.alpha = alpha; translationY = travel * distance }
}

private sealed interface DateSheetRow {
    data class Month(val firstIndex: Int) : DateSheetRow
    data class Date(val index: Int, val first: Boolean, val last: Boolean) : DateSheetRow
}

/** Native detents and nested scrolling; preview selection never consumes a trial. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LeavePlanDateSheet(proposals: List<LeavePlanProposal>, indices: List<Int>, selection: Int, text: LeaveText, dismiss: () -> Unit, select: (Int) -> Unit) {
    val rows = remember(proposals, indices) {
        buildList {
            var start = 0
            while (start < indices.size) {
                val month = YearMonth.from(LeavePlannerSchedule.date(proposals[indices[start]].firstRestDayNumber))
                var end = start + 1
                while (end < indices.size && YearMonth.from(LeavePlannerSchedule.date(proposals[indices[end]].firstRestDayNumber)) == month) end++
                add(DateSheetRow.Month(indices[start]))
                for (i in start until end) add(DateSheetRow.Date(indices[i], i == start, i == end - 1))
                start = end
            }
        }
    }
    val reduced = LocalDoneAtMotion.current.reduced
    val density = LocalDensity.current
    val windowHeight = with(density) { LocalWindowInfo.current.containerSize.height.toDp() }
    val latestDismiss by rememberUpdatedState(dismiss)
    var reducedExpanded by remember { mutableStateOf(false) }
    val nativeState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    // Stable M3's motion specs are internal. Visible initial states and state
    // replacement also snap the gallery override without reflective APIs.
    val reducedState = remember(reducedExpanded, density) {
        SheetState(
            skipPartiallyExpanded = reducedExpanded,
            positionalThreshold = { with(density) { DoneAtLeaveTokens.swipeThreshold.toPx() } },
            velocityThreshold = { with(density) { DoneAtLeaveTokens.sheetDismissThreshold.toPx() } },
            initialValue = if (reducedExpanded) SheetValue.Expanded else SheetValue.PartiallyExpanded,
            confirmValueChange = { target ->
                when (target) {
                    SheetValue.Hidden -> latestDismiss()
                    SheetValue.Expanded -> reducedExpanded = true
                    SheetValue.PartiallyExpanded -> reducedExpanded = false
                }
                false
            },
        )
    }
    val sheetState = if (reduced) reducedState else nativeState
    val scope = rememberCoroutineScope()
    var finishing by remember { mutableStateOf(false) }
    fun finish(action: () -> Unit) {
        if (finishing) return
        finishing = true
        if (reduced) action() else scope.launch {
            try {
                sheetState.hide()
                if (!sheetState.isVisible) action()
            } finally {
                finishing = false
            }
        }
    }
    val state = rememberLazyListState(initialFirstVisibleItemIndex = (rows.indexOfFirst { it is DateSheetRow.Date && it.index == selection } - 1).coerceAtLeast(0))
    var centredSelection by remember { mutableIntStateOf(-1) }
    LaunchedEffect(selection, sheetState.currentValue) {
        if (sheetState.currentValue == SheetValue.Hidden || centredSelection == selection) return@LaunchedEffect
        // The viewport tracks the visible detent; centring never puts the
        // selection in the expanded content below a half-height sheet.
        withFrameNanos { }
        val item = snapshotFlow { state.layoutInfo.visibleItemsInfo.firstOrNull { it.key == selection } }.filterNotNull().first()
        val layout = state.layoutInfo
        state.scrollBy((item.offset + item.size / 2 - (layout.viewportStartOffset + layout.viewportEndOffset) / 2).toFloat())
        centredSelection = selection
    }
    val resources = LocalResources.current
    val threshold = with(density) { DoneAtLeaveTokens.swipeThreshold.toPx() }
    var handleHeight by remember { mutableIntStateOf(0) }
    var headerHeight by remember { mutableIntStateOf(0) }
    ModalBottomSheet(
        onDismissRequest = dismiss,
        modifier = Modifier.height(windowHeight * DoneAtLeaveTokens.sheetMaxFraction),
        sheetState = sheetState,
        sheetMaxWidth = 720.dp,
        sheetGesturesEnabled = !reduced,
        shape = MaterialTheme.shapes.extraLarge,
        containerColor = MaterialTheme.colorScheme.surface,
        dragHandle = {
            Box(Modifier.onSizeChanged { handleHeight = it.height }.then(if (!reduced) Modifier else Modifier
                .clickable(role = Role.Button) { reducedExpanded = !reducedExpanded }
                .semantics {
                    if (reducedExpanded) collapse { reducedExpanded = false; true }
                    else expand { reducedExpanded = true; true }
                }
                .pointerInput(reducedExpanded) {
                    var distance = 0f
                    detectVerticalDragGestures(
                        onDragStart = { distance = 0f },
                        onVerticalDrag = { change, amount -> change.consume(); distance += amount },
                        onDragEnd = {
                            if (distance < -threshold) reducedExpanded = true
                            else if (distance > threshold) {
                                if (reducedExpanded) reducedExpanded = false else latestDismiss()
                            }
                        },
                    )
                })) { BottomSheetDefaults.DragHandle() }
        },
    ) {
        BoxWithConstraints(Modifier.fillMaxWidth().fillMaxHeight()) {
            val offset = runCatching { sheetState.requireOffset() }.getOrDefault(with(density) { windowHeight.toPx() / 2 })
            val bottomInset = WindowInsets.safeDrawing.getBottom(density)
            val visibleHeight = with(density) { (windowHeight.toPx() - offset - handleHeight - headerHeight - bottomInset).coerceAtLeast(0f).toDp() }
            val listHeight = visibleHeight.coerceAtMost((maxHeight - with(density) { headerHeight.toDp() }).coerceAtLeast(0.dp))
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().onSizeChanged { headerHeight = it.height }.padding(horizontal = DoneAtSpacing.s), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { finish(dismiss) }) { Text(text.string(R.string.close)) }
                    Text(Strings.leaveAvailableDates(resources, text.wholeNumber(indices.size)), Modifier.weight(1f).padding(horizontal = DoneAtSpacing.s).semantics { heading() }, style = MaterialTheme.typography.titleMedium)
                }
                LazyColumn(state = state, modifier = Modifier.height(listHeight), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.s)) {
                    items(rows, key = { row -> when (row) { is DateSheetRow.Month -> "month:${row.firstIndex}"; is DateSheetRow.Date -> row.index } }) { row ->
                        when (row) {
                            is DateSheetRow.Month -> Text(text.month(proposals[row.firstIndex].firstRestDayNumber), Modifier.padding(start = DoneAtSpacing.l, top = DoneAtSpacing.l, bottom = DoneAtSpacing.s).semantics { heading() }, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            is DateSheetRow.Date -> {
                                val proposal = proposals[row.index]
                                val corners = MaterialTheme.shapes.large
                                val square = androidx.compose.foundation.shape.CornerSize(0.dp)
                                val shape = androidx.compose.foundation.shape.RoundedCornerShape(
                                    topStart = if (row.first) corners.topStart else square, topEnd = if (row.first) corners.topEnd else square,
                                    bottomStart = if (row.last) corners.bottomStart else square, bottomEnd = if (row.last) corners.bottomEnd else square,
                                )
                                Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainerLow, shape)) {
                                    Row(Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch).clickable(role = Role.Button) { finish { select(row.index) } }.semantics { selected = row.index == selection }.padding(DoneAtSpacing.l), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                                            Text(text.range(text.day(proposal.firstRestDayNumber), text.day(proposal.lastRestDayNumber)), style = MaterialTheme.typography.bodyLarge)
                                            if (proposal.caveats.isNotEmpty()) EstimatedLabel(true, text)
                                        }
                                        if (row.index == selection) Icon(Icons.Outlined.Check, null, tint = MaterialTheme.colorScheme.primary)
                                    }
                                    if (!row.last) RowDivider(inset = false)
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
            }
        }
    }
}
