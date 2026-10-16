package com.rainif.doneat.ui.leave

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtLeaveTokens
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.domain.leave.LeavePresentation
import com.rainif.doneat.core.domain.leave.LeavePlanner
import com.rainif.doneat.core.domain.leave.LeavePlanGroup
import com.rainif.doneat.core.domain.leave.LeavePlannerCaveat
import com.rainif.doneat.core.domain.leave.LeavePlanProposal
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.RowDivider
import kotlinx.coroutines.delay
import java.time.DayOfWeek

internal enum class LeaveResultFilter { ALL, HOLIDAY, REGULAR }
internal enum class LeaveResultsPage { SUMMARY, ALL_PLANS, DATES }

/** The toolbar and hardware back share this rule; the summary delegates back to the parent route. */
internal fun leaveResultsBackPage(page: LeaveResultsPage): LeaveResultsPage? =
    LeaveResultsPage.SUMMARY.takeUnless { page == LeaveResultsPage.SUMMARY }

internal fun leaveGroupsForFilter(groups: List<LeavePlanGroup>, filter: LeaveResultFilter): List<LeavePlanGroup> = when (filter) {
    LeaveResultFilter.ALL -> groups
    LeaveResultFilter.HOLIDAY -> groups.filter { it.category == LeavePlanGroup.Category.HOLIDAY }
    LeaveResultFilter.REGULAR -> groups.filter { it.category == LeavePlanGroup.Category.REGULAR }
}

internal fun leaveFilterFromSaved(name: String): LeaveResultFilter =
    LeaveResultFilter.entries.firstOrNull { it.name == name } ?: LeaveResultFilter.ALL

/** Filtering never changes the selected group, even when the chosen category has no rows. */
internal fun leaveSelectedGroup(groups: List<LeavePlanGroup>, groupID: Int): LeavePlanGroup =
    groups.firstOrNull { it.id == groupID } ?: groups.first()

/** Groups sort dates for their list; the original ranked representative remains the default. */
internal fun leaveGroupSelection(group: LeavePlanGroup, savedIndex: Int?): Int =
    savedIndex?.takeIf { it in group.proposalIndices } ?: group.id

/** Selection and the fixed footer share one state; browsing this opened set never consumes another trial. */
@Composable
internal fun LeavePlanResultsContent(
    proposals: List<LeavePlanProposal>, text: LeaveText, firstWeekday: DayOfWeek,
    onDetails: (Int) -> Unit, page: LeaveResultsPage, onPageChange: (LeaveResultsPage) -> Unit,
    title: String, onBack: () -> Unit, backLabel: String, plus: Boolean, trialsLeft: Int,
    snapshot: LeaveQuerySnapshot?, revision: Int, onAdjustConditions: () -> Unit,
    holidays: HolidayCalendar = HolidayCalendar.EMPTY, holidayRegion: String? = null,
) {
    val groups = remember(proposals) { LeavePlanGroup.make(proposals) }
    val first = groups.firstOrNull() ?: return
    var categoryName by rememberSaveable(revision) { mutableStateOf(LeaveResultFilter.ALL.name) }
    val category = leaveFilterFromSaved(categoryName)
    var groupID by rememberSaveable(revision) { mutableIntStateOf(first.id) }
    var dateGroupIDs by rememberSaveable(revision) { mutableStateOf(intArrayOf()) }
    var dateIndices by rememberSaveable(revision) { mutableStateOf(intArrayOf()) }
    var browsedDateGroupID by rememberSaveable(revision) { mutableStateOf<Int?>(null) }
    var datesFromPlans by rememberSaveable(revision) { mutableStateOf(false) }
    val group = leaveSelectedGroup(groups, groupID)
    val selectedRow = remember { BringIntoViewRequester() }
    val resources = LocalResources.current
    val view = LocalView.current
    val minimumCost = remember(proposals) { proposals.minOf { it.costHalfDays } }

    fun selectedDate(candidate: LeavePlanGroup): Int {
        val saved = dateGroupIDs.indexOf(candidate.id).takeIf { it >= 0 }?.let { dateIndices.getOrNull(it) }
        return leaveGroupSelection(candidate, saved)
    }
    val selection = selectedDate(group)
    val proposal = proposals[selection]
    val visible = LeavePresentation.sortedGroups(leaveGroupsForFilter(groups, category), proposals, ::selectedDate)
    val dateGroup = groups.firstOrNull { it.id == browsedDateGroupID } ?: group
    val selectedDateRow = remember { BringIntoViewRequester() }
    val longest = visible.maxOfOrNull { LeavePresentation.strip(proposals[selectedDate(it)]).size } ?: 1

    fun showDates(candidate: LeavePlanGroup, fromPlans: Boolean) {
        browsedDateGroupID = candidate.id
        datesFromPlans = fromPlans
        onPageChange(LeaveResultsPage.DATES)
    }
    fun back() {
        if (page == LeaveResultsPage.DATES && datesFromPlans) onPageChange(LeaveResultsPage.ALL_PLANS) else onBack()
    }

    fun selectGroup(candidate: LeavePlanGroup) {
        groupID = candidate.id
        onPageChange(LeaveResultsPage.SUMMARY)
        view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
    }
    fun selectDate(index: Int) {
        if (index !in dateGroup.proposalIndices) return
        groupID = dateGroup.id
        val position = dateGroupIDs.indexOf(dateGroup.id)
        if (position < 0) {
            dateGroupIDs = dateGroupIDs + dateGroup.id
            dateIndices = dateIndices + index
        } else dateIndices = dateIndices.copyOf().also { it[position] = index }
        onPageChange(if (datesFromPlans) LeaveResultsPage.ALL_PLANS else LeaveResultsPage.SUMMARY)
        view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
    }
    BackHandler(enabled = leaveResultsBackPage(page) != null) {
        back()
    }

    LaunchedEffect(page, category, group.id) {
        if (page == LeaveResultsPage.ALL_PLANS && visible.any { it.id == group.id }) {
            withFrameNanos { }
            selectedRow.bringIntoView()
        }
    }

    LaunchedEffect(page, dateGroup.id) {
        if (page == LeaveResultsPage.DATES) { withFrameNanos { }; selectedDateRow.bringIntoView() }
    }
    val pageTitle = when (page) {
        LeaveResultsPage.ALL_PLANS -> Strings.leaveAllPlans(resources, text.wholeNumber(groups.size))
        LeaveResultsPage.DATES -> Strings.leaveAvailableDates(resources, text.wholeNumber(dateGroup.proposalIndices.size))
        else -> title
    }
    val effectiveBackLabel = if (page == LeaveResultsPage.DATES && datesFromPlans)
        Strings.leaveAllPlans(resources, text.wholeNumber(groups.size)) else backLabel
    LeaveResultsPageLayout(pageTitle, ::back, effectiveBackLabel, page, footer = if (page == LeaveResultsPage.SUMMARY) ({
        if (!plus) {
            Text(Strings.leaveTrialsLeft(resources, trialsLeft), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(text.string(R.string.leaveResultsBrowsingFree), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DoneAtPrimaryButton(text.string(R.string.leaveViewDetails), { onDetails(selection) }, Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch))
    }) else null) {
        Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            when (page) {
                LeaveResultsPage.SUMMARY -> {
                    Surface(modifier = arrival(0).fillMaxWidth(), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                        Column {
                            PlanSummary(proposal, text, proposal.costHalfDays == minimumCost, Modifier.padding(DoneAtSpacing.l),
                                holidayName = leaveHolidayName(proposal, holidays, holidayRegion, text))
                        }
                    }
                    // One full warning before the calendar; each summary only carries the short prediction label.
                    leaveSelectedEstimatedYears(proposal).forEach {
                        Row(arrival(1), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.Info, null, Modifier.size(DoneAtSpacing.m), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(Strings.holidayEstimatedYearWarning(resources, it.toString()), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Surface(modifier = arrival(2), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                        LeavePlanCalendar(proposal, text, firstWeekday, Modifier.padding(DoneAtSpacing.l), holidays, holidayRegion)
                    }
                    Surface(modifier = arrival(3), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                        Column(Modifier.padding(horizontal = DoneAtSpacing.l)) {
                            ResultsListEntry(Strings.leaveAllPlans(resources, text.wholeNumber(groups.size)), true) {
                                categoryName = LeaveResultFilter.ALL.name
                                onPageChange(LeaveResultsPage.ALL_PLANS)
                            }
                            if (group.proposalIndices.size > 1) {
                                RowDivider(inset = false)
                                ResultsListEntry(Strings.leaveAvailableDates(resources, text.wholeNumber(group.proposalIndices.size)), true) { showDates(group, false) }
                            }
                            RowDivider(inset = false)
                            ResultsListEntry(text.string(R.string.leaveAdjustConditions), true, onAdjustConditions)
                        }
                    }
                }
                LeaveResultsPage.ALL_PLANS -> {
                    ResultsFilterPicker(groups, category, text) { kind ->
                        categoryName = kind.name
                        view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
                    }
                    if (visible.isEmpty()) {
                        LeaveFilterEmptyState(snapshot, text, onAdjustConditions) { categoryName = LeaveResultFilter.ALL.name }
                    } else Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                        Column {
                            visible.forEachIndexed { position, candidate ->
                                SelectablePlanRow(proposals[selectedDate(candidate)], text, candidate.id == group.id, minimumCost,
                                    longest = longest, holidayName = leaveHolidayName(proposals[selectedDate(candidate)], holidays, holidayRegion, text), datesCount = candidate.proposalIndices.size, onDates = { showDates(candidate, true) },
                                    modifier = if (candidate.id == group.id) Modifier.bringIntoViewRequester(selectedRow) else Modifier) { selectGroup(candidate) }
                                if (position < visible.lastIndex) RowDivider(inset = false)
                            }
                        }
                    }
                    if (visible.isNotEmpty()) {
                        LeaveStripLegend(text)
                        Text(text.string(R.string.leaveSortedByLeast), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    ResultsListEntry(text.string(R.string.leaveAdjustConditions), true, onAdjustConditions)
                }
                LeaveResultsPage.DATES -> {
                    val indices = dateGroup.proposalIndices
                    val dateLongest = indices.maxOf { LeavePresentation.strip(proposals[it]).size }
                    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                        Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                            PlanSummary(proposals[selectedDate(dateGroup)], text, false, compact = true,
                                holidayName = leaveHolidayName(proposals[selectedDate(dateGroup)], holidays, holidayRegion, text))
                            LeaveDayStrip(proposals[selectedDate(dateGroup)], dateLongest)
                            Text(text.string(R.string.leaveSamePatternHint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    val months = indices.groupBy { java.time.YearMonth.from(com.rainif.doneat.core.domain.leave.LeavePlannerSchedule.date(proposals[it].firstRestDayNumber)) }
                    months.forEach { (_, dates) ->
                        Text(text.month(proposals[dates.first()].firstRestDayNumber), Modifier.semantics { heading() }, style = MaterialTheme.typography.titleSmall)
                        Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                            Column {
                                dates.forEachIndexed { position, index ->
                                    SelectablePlanRow(proposals[index], text, index == selectedDate(dateGroup), minimumCost,
                                        longest = dateLongest, dateOnly = true,
                                        modifier = if (index == selectedDate(dateGroup)) Modifier.bringIntoViewRequester(selectedDateRow) else Modifier) { selectDate(index) }
                                    if (position < dates.lastIndex) RowDivider(inset = false)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

internal fun leaveSelectedEstimatedYears(proposal: LeavePlanProposal): List<Int> =
    proposal.caveats.filterIsInstance<LeavePlannerCaveat.HolidaysEstimated>().map { it.year }.distinct().sorted()

private fun filterLabel(filter: LeaveResultFilter): Int = when (filter) {
    LeaveResultFilter.ALL -> R.string.leaveAllPlanTypes
    LeaveResultFilter.HOLIDAY -> R.string.leaveHolidayPlans
    LeaveResultFilter.REGULAR -> R.string.leaveRegularPlans
}

/** Every category stays selectable, including zero counts; the menu wraps naturally at all text sizes. */
@Composable
private fun ResultsFilterPicker(groups: List<LeavePlanGroup>, selectedFilter: LeaveResultFilter, text: LeaveText, select: (LeaveResultFilter) -> Unit) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val resources = LocalResources.current
    fun label(category: LeaveResultFilter) = Strings.leaveFilterCount(resources, text.string(filterLabel(category)), text.wholeNumber(leaveGroupsForFilter(groups, category).size))
    Box(Modifier.fillMaxWidth()) {
        Surface(shape = MaterialTheme.shapes.small, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Row(Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch)
                .clickable(role = Role.Button) { expanded = true }.padding(DoneAtSpacing.m),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                Text(label(selectedFilter), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                Icon(Icons.Outlined.KeyboardArrowDown, null, Modifier.size(DoneAtSpacing.l), tint = MaterialTheme.colorScheme.primary)
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            LeaveResultFilter.entries.forEach { category ->
                DropdownMenuItem(
                    text = { Text(label(category)) },
                    onClick = { expanded = false; select(category) },
                    modifier = Modifier.heightIn(min = DoneAtSpacing.minTouch).semantics { selected = category == selectedFilter },
                    leadingIcon = if (category == selectedFilter) ({ Icon(Icons.Outlined.Check, null) }) else null,
                )
            }
        }
    }
}

@Composable
private fun LeaveFilterEmptyState(snapshot: LeaveQuerySnapshot?, text: LeaveText, adjust: () -> Unit, viewAll: () -> Unit) {
    val resources = LocalResources.current
    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            Text(text.string(R.string.leaveFilterNoResults), style = MaterialTheme.typography.titleMedium)
            Text(text.string(R.string.leaveFilterNoResultsHint), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            snapshot?.let {
                Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    val goal = when (val goal = it.request.goal) {
                        is LeavePlanner.Goal.RestAtLeast -> Strings.leaveCurrentGoalRest(resources, text.wholeNumber(goal.days))
                        is LeavePlanner.Goal.LeaveAtMost -> Strings.leaveCurrentGoalBudget(resources, text.halfDaysNumber(goal.halfDays))
                    }
                    Text(goal, style = MaterialTheme.typography.bodyMedium)
                    Text(Strings.leaveAvailableBudget(resources, text.halfDaysNumber(it.availableHalfDays)), style = MaterialTheme.typography.bodyMedium)
                    Text(text.range(text.fullDate(it.request.fromDayNumber), text.fullDate(it.request.throughDayNumber)), style = MaterialTheme.typography.bodyMedium)
                }
            }
            DoneAtPrimaryButton(text.string(R.string.leaveAdjustConditions), adjust, Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch))
            ResultsListEntry(text.string(R.string.leaveViewAllPlans), true, viewAll)
        }
    }
}

@Composable
private fun ResultsListEntry(label: String, enabled: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch).clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, Modifier.size(DoneAtSpacing.l), tint = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun SelectablePlanRow(proposal: LeavePlanProposal, text: LeaveText, isSelected: Boolean, minimumCost: Int,
    longest: Int, holidayName: String? = null, datesCount: Int = 0, onDates: () -> Unit = {}, dateOnly: Boolean = false,
    modifier: Modifier = Modifier, select: () -> Unit,
) {
    val resources = LocalResources.current
    Row(modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch)
        .background(if (isSelected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent)
        .clickable(role = Role.RadioButton, onClick = select).semantics { selected = isSelected }.padding(DoneAtSpacing.l),
        verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            if (dateOnly) {
                Text(text.range(text.day(proposal.firstRestDayNumber), text.day(proposal.lastRestDayNumber)), style = MaterialTheme.typography.bodyLarge)
                if (proposal.caveats.isNotEmpty()) EstimatedLabel(proposal, text)
            } else {
                PlanSummary(proposal, text, proposal.costHalfDays == minimumCost, compact = true, holidayName = holidayName)
                LeaveDayStrip(proposal, longest)
                if (datesCount > 1) TextButton(onClick = onDates) { Text(Strings.leaveAvailableDates(resources, text.wholeNumber(datesCount))) }
            }
        }
        // Reserve the same selection column for every row so each day keeps the same width.
        Box(Modifier.size(DoneAtSpacing.l)) {
            if (isSelected) Icon(Icons.Outlined.Check, null, Modifier.size(DoneAtSpacing.l), tint = MaterialTheme.colorScheme.primary)
        }
    }
}

/** Cost, benefit and date keep separate visual levels; the rest reward is green. */
@Composable
private fun PlanSummary(proposal: LeavePlanProposal, text: LeaveText, bestValue: Boolean, modifier: Modifier = Modifier, compact: Boolean = false, holidayName: String? = null) {
    val resources = LocalResources.current
    Column(modifier, verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
        if (compact) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                Text(Strings.leaveDaysOff(resources, proposal.fullRestDays), style = MaterialTheme.typography.titleMedium)
                Text(if (proposal.costHalfDays == 0) text.string(R.string.leaveNoLeaveNeeded) else Strings.leaveAskFor(resources, text.halfDays(proposal.costHalfDays)),
                    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
            }
            Text(listOfNotNull(text.range(text.fullDate(proposal.firstRestDayNumber), text.fullDate(proposal.lastRestDayNumber)), holidayName).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else LeaveProposalHeadline(proposal, text, holidayName = holidayName)
        if (bestValue && proposal.costHalfDays > 0) Text(text.string(R.string.leaveBestValue), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
        if (proposal.caveats.isNotEmpty()) EstimatedLabel(proposal, text, compact)
    }
}

@Composable
private fun EstimatedLabel(proposal: LeavePlanProposal, text: LeaveText, compact: Boolean = false) {
    val resources = LocalResources.current
    val predictedYears = proposal.caveats.filterIsInstance<LeavePlannerCaveat.HolidaysEstimated>().map { it.year }.sorted()
    Row(horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.Info, null, Modifier.size(DoneAtSpacing.m), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(if (predictedYears.isEmpty()) text.string(R.string.leaveEstimated)
            else if (compact) text.string(R.string.leaveEstimatedHolidaysShort)
            else predictedYears.joinToString(" · ") { Strings.leaveEstimatedHolidaysYear(resources, it.toString()) },
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
