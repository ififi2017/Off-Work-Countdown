package com.rainif.doneat.ui.leave

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ConfirmationNumber
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.ui.schedule.holidayDayAnnotation
import com.rainif.doneat.R
import com.rainif.doneat.core.data.WriteResult
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.leave.LeaveAdoption
import com.rainif.doneat.core.domain.leave.LeavePlanItem
import com.rainif.doneat.core.domain.leave.LeavePlanProposal
import com.rainif.doneat.core.domain.leave.LeavePlanner
import com.rainif.doneat.core.domain.leave.LeavePlannerCaveat
import com.rainif.doneat.core.domain.leave.LeavePlannerSchedule
import com.rainif.doneat.core.domain.leave.LeavePlanning
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.PageFooter
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsFooter
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow
import com.rainif.doneat.ui.components.ValueRow
import com.rainif.doneat.ui.onboarding.appIsDark
import com.rainif.doneat.ui.timer.Haptics
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// The leave planner (iOS `LeavePlannerSheet`, `LeavePlanResults`, `LeavePlanDetail`).

/**
 * What to plan for: a break of at least N days, or the longest break a number
 * of half days buys; the dates it must fall within; which balances to spend.
 * One successful results set uses one free view; every option inside stays available.
 */
@Composable
fun LeavePlannerScreen(graph: AppGraph, open: (Route) -> Unit, onBack: () -> Unit,
    adjusting: Boolean = false, isRoutePresent: () -> Boolean = { true }, onResultsReady: () -> Unit = { open(Route.LeavePlanResults) },
) {
    val text = rememberLeaveText(graph)
    val records by graph.records.state.collectAsStateWithLifecycle()
    val plus by graph.plus.authorized.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val holidays by graph.holidays.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val dark = appIsDark()
    val window = remember { LeavePlannerSchedule.rollingYear(graph.leaveToday()) }
    val budgets = remember(records.leaveBalances, records.leaveDays) { LeaveAdoption.budgets(records.leaveBalances, records.leaveDays) }

    val initialQuery = remember { graph.leaveQuerySnapshot.value?.request.takeIf { adjusting } }
    var goalIsRest by rememberSaveable { mutableStateOf(initialQuery?.goal !is LeavePlanner.Goal.LeaveAtMost) }
    var restDays by rememberSaveable { mutableIntStateOf((initialQuery?.goal as? LeavePlanner.Goal.RestAtLeast)?.days ?: 7) }
    var from by rememberSaveable { mutableIntStateOf(initialQuery?.fromDayNumber ?: window?.first ?: 0) }
    var through by rememberSaveable { mutableIntStateOf(initialQuery?.throughDayNumber ?: window?.last ?: 0) }
    // Ids joined by commas, so the choice survives the process like the rest of the form.
    var selectedRaw by rememberSaveable { mutableStateOf(initialQuery?.budgetIDs?.joinToString(",") ?: budgets.filter { it.availableHalfDays > 0 }.joinToString(",") { it.id }) }
    val selected = selectedRaw.split(',').filter { it.isNotEmpty() }.toSet()
    val selectedHalfDays = budgets.filter { it.id in selected }.sumOf { it.availableHalfDays }
    var leaveHalfDays by rememberSaveable { mutableIntStateOf((initialQuery?.goal as? LeavePlanner.Goal.LeaveAtMost)?.halfDays ?: selectedHalfDays.coerceIn(1, 6)) }
    var searching by remember { mutableStateOf(false) }
    var searchFailed by remember { mutableStateOf(false) }
    var searchEmpty by remember { mutableStateOf(false) }
    val resultSetGate = remember { LeaveResultSetGate() }
    var searchJob by remember { mutableStateOf<Job?>(null) }
    val routePresent = isRoutePresent()
    LaunchedEffect(routePresent) { if (!routePresent) searchJob?.cancel() }
    val cancelAndBack = { searchJob?.cancel(); onBack() }

    val request = window?.let {
        val first = maxOf(from, it.first)
        val last = minOf(maxOf(through, first), it.last)
        LeavePlanning.Request(
            goal = if (goalIsRest) LeavePlanner.Goal.RestAtLeast(restDays) else LeavePlanner.Goal.LeaveAtMost(leaveHalfDays.coerceAtMost(maxOf(1, selectedHalfDays))),
            fromDayNumber = first,
            throughDayNumber = last,
            budgetIDs = selected,
        )
    }
    val missingYears = remember(request?.fromDayNumber, request?.throughDayNumber, session, holidays) {
        request?.let { LeavePlanning.missingMainlandHolidayYears(session, it.fromDayNumber..it.throughDayNumber, holidays) }.orEmpty()
    }
    val estimatedYears = remember(request?.fromDayNumber, request?.throughDayNumber, session, holidays) {
        request?.let { LeavePlanning.estimatedHolidayYears(session, it.fromDayNumber..it.throughDayNumber, holidays) }.orEmpty()
    }

    fun search() {
        val query = request ?: return
        if (searching) return
        searching = true
        searchFailed = false
        searchEmpty = false
        searchJob = scope.launch {
            try {
                var submitted: LeaveQuerySnapshot? = null
                val result = resultSetGate.generate(
                    isPlus = { graph.plus.authorized.value },
                    trialsLeft = { graph.settings.device.value.leavePlannerTrialsLeft },
                    find = {
                        val state = graph.records.state.value
                        submitted = LeaveQuerySnapshot.capture(query, state)
                        val now = graph.nowMs()
                        withContext(Dispatchers.Default) { LeavePlanning.find(session, state, query, now, holidays) }
                    },
                    // This atomic write returns on the UI coroutine, immediately followed by publication.
                    // Avoid a dispatcher return cancellation losing navigation after spending the trial.
                    consume = { graph.settings.consumeLeavePlannerTrial() }, canOpen = isRoutePresent,
                )
                when (result) {
                    is LeaveResultSetOutcome.Results -> {
                        if (shouldPublishLeaveResults(!graph.leaveProposals.value.isNullOrEmpty(), result.proposals.isNotEmpty(), adjusting)) {
                            graph.leaveQuerySnapshot.value = submitted
                            graph.leaveEstimatedHolidayYears.value = estimatedYears
                            graph.leaveProposals.value = result.proposals
                            if (result.proposals.isNotEmpty()) graph.leaveResultsRevision.value += 1
                            onResultsReady()
                        } else searchEmpty = true
                    }
                    LeaveResultSetOutcome.Paywall -> open(Route.Plus)
                    LeaveResultSetOutcome.Failed -> searchFailed = true
                    LeaveResultSetOutcome.Busy -> Unit
                }
            } finally {
                searching = false
            }
        }
    }

    DoneAtPage(
        text.string(if (adjusting) R.string.leaveAdjustConditions else R.string.leavePlanAction), cancelAndBack, text.string(if (adjusting) R.string.leaveResultsTitle else R.string.leaveTitle),
        actions = {
            if (searching) {
                CircularProgressIndicator(Modifier.padding(end = DoneAtSpacing.l).size(DoneAtSpacing.xl), strokeWidth = 2.dp)
            } else {
                TextButton(onClick = { search() }, enabled = request != null) {
                    Text(text.string(R.string.leaveFind), fontWeight = FontWeight.SemiBold)
                }
            }
        },
    ) {
        if (!plus) LeaveTrialBanner(device.leavePlannerTrialsLeft, text, explainsCost = true)
        if (searchFailed) PageFooter(text.string(R.string.leaveTrialSaveFailed))
        if (searchEmpty) PageFooter(text.string(R.string.leaveNoResults))

        Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            val goals = listOf(true to R.string.leaveGoalRest, false to R.string.leaveGoalBudget)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                goals.forEachIndexed { index, (value, label) ->
                    SegmentedButton(goalIsRest == value, { goalIsRest = value }, SegmentedButtonDefaults.itemShape(index, goals.size)) {
                        Text(text.string(label), maxLines = 1)
                    }
                }
            }
        }
        SettingsGroup {
            if (goalIsRest) {
                StepperRow(
                    text.string(R.string.leaveGoalRest), Strings.leaveAtLeast(context.resources, text.wholeDays(restDays)),
                    canDecrease = restDays > 2, canIncrease = restDays < 60,
                    onDecrease = { restDays -= 1 }, onIncrease = { restDays += 1 },
                )
            } else {
                val ceiling = maxOf(1, selectedHalfDays)
                val value = leaveHalfDays.coerceIn(1, ceiling)
                StepperRow(
                    text.string(R.string.leaveGoalBudget), Strings.leaveUpTo(context.resources, text.halfDays(value)),
                    canDecrease = selectedHalfDays > 0 && value > 1, canIncrease = selectedHalfDays > 0 && value < ceiling,
                    onDecrease = { leaveHalfDays = value - 1 }, onIncrease = { leaveHalfDays = value + 1 },
                )
            }
        }

        if (window != null) {
            val first = maxOf(from, window.first)
            val last = minOf(maxOf(through, first), window.last)
            Column {
                SettingsGroup {
                    DatePickRow(text.string(R.string.leaveRangeStart), text.fullDate(first)) {
                        showLeaveDatePicker(context, dark, first, window.first, window.last) { picked ->
                            from = picked
                            if (through < picked) through = picked
                        }
                    }
                    RowDivider(inset = false)
                    DatePickRow(text.string(R.string.leaveRangeEnd), text.fullDate(last)) {
                        showLeaveDatePicker(context, dark, last, first, window.last) { through = it }
                    }
                }
                Column(Modifier.padding(horizontal = DoneAtSpacing.page)) {
                    SettingsFooter(Strings.leaveRangeFooter(context.resources, text.fullDate(window.first), text.fullDate(window.last)))
                    missingYears.forEach { year ->
                        Note(Strings.leaveMainlandHolidaysMissing(context.resources, year.toString()))
                    }
                    estimatedYears.forEach { year ->
                        Note(Strings.holidayEstimatedYearWarning(context.resources, year.toString()))
                    }
                }
            }
        }

        if (records.leaveBalances.isEmpty()) {
            PageFooter(text.string(R.string.leaveNoBalancesHint))
        } else SettingsGroup(text.string(R.string.leaveUseBalances)) {
            records.leaveBalances.forEachIndexed { index, balance ->
                if (index > 0) RowDivider(inset = false)
                val available = records.availableLeaveHalfDays(balance)
                SwitchRow(
                    text.balanceName(balance), balance.id in selected,
                    { on -> selectedRaw = (if (on) selected + balance.id else selected - balance.id).joinToString(",") },
                    supporting = text.available(available),
                    enabled = available > 0,
                )
            }
        }
    }
}

@Composable
private fun StepperRow(title: String, value: String, canDecrease: Boolean, canIncrease: Boolean, onDecrease: () -> Unit, onIncrease: () -> Unit) {
    val view = LocalView.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = DoneAtSpacing.l, end = DoneAtSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(value, style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"), color = MaterialTheme.colorScheme.primary)
        }
        IconButton(onClick = { onDecrease(); view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK) }, enabled = canDecrease) {
            Icon(Icons.Outlined.Remove, "$title −")
        }
        IconButton(onClick = { onIncrease(); view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK) }, enabled = canIncrease) {
            Icon(Icons.Outlined.Add, "$title +")
        }
    }
}

@Composable
private fun DatePickRow(title: String, value: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = DoneAtSpacing.l),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(value, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
    }
}

/** A footnote with an information mark, for what the planner could only estimate. */
@Composable
private fun Note(message: String) {
    Row(
        Modifier.padding(start = DoneAtSpacing.l, end = DoneAtSpacing.l, top = DoneAtSpacing.s),
        horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs),
    ) {
        Icon(Icons.Outlined.Info, null, Modifier.padding(top = DoneAtSpacing.xxs).size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * How many free plan views are left, in plain sight wherever a free user
 * plans: the form, the options and each plan they open.
 */
@Composable
private fun LeaveTrialBanner(left: Int, text: LeaveText, explainsCost: Boolean = false) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        Modifier.padding(horizontal = DoneAtSpacing.page).fillMaxWidth().semantics(mergeDescendants = true) {},
        shape = MaterialTheme.shapes.large,
        color = scheme.primary.copy(alpha = 0.10f),
    ) {
        Row(Modifier.padding(DoneAtSpacing.l), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            Icon(if (left > 0) Icons.Outlined.ConfirmationNumber else Icons.Outlined.Lock, null, tint = scheme.primary)
            Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                Text(text.trialsLeft(left), style = MaterialTheme.typography.titleSmall)
                if (explainsCost && left > 0) {
                    Text(text.string(R.string.leaveTrialNotice), style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
                }
            }
        }
    }
}

// Results

/** Every option, date and detail in this already-opened results set is free to explore. */
@Composable
fun LeavePlanResultsScreen(graph: AppGraph, open: (Route) -> Unit, onBack: () -> Unit) {
    val text = rememberLeaveText(graph)
    val proposals by graph.leaveProposals.collectAsStateWithLifecycle()
    val searchedEstimatedYears by graph.leaveEstimatedHolidayYears.collectAsStateWithLifecycle()
    val holidays by graph.holidays.collectAsStateWithLifecycle()
    val records by graph.records.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val plus by graph.plus.authorized.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val snapshot by graph.leaveQuerySnapshot.collectAsStateWithLifecycle()
    val revision by graph.leaveResultsRevision.collectAsStateWithLifecycle()
    var resultsPage by rememberSaveable(revision) { mutableStateOf(LeaveResultsPage.SUMMARY) }
    LaunchedEffect(proposals == null) { if (proposals == null) onBack() }
    val options = proposals.orEmpty()
    val back = {
        val previousPage = leaveResultsBackPage(resultsPage)
        if (previousPage == null) onBack() else resultsPage = previousPage
    }
    val title = text.string(R.string.leaveResultsTitle)
    val backLabel = text.string(if (resultsPage == LeaveResultsPage.SUMMARY) R.string.leavePlanAction else R.string.leaveResultsTitle)
    if (options.isNotEmpty()) {
        LeavePlanResultsContent(
            proposals = options, text = text, firstWeekday = device.calendarFirstDay(text.locale),
            onDetails = { index -> if (index in options.indices) open(Route.LeavePlanDetail(index)) },
            page = resultsPage, onPageChange = { resultsPage = it }, title = title, onBack = back, backLabel = backLabel,
            plus = plus, trialsLeft = device.leavePlannerTrialsLeft, snapshot = snapshot, revision = revision,
            onAdjustConditions = { open(Route.LeavePlannerAdjustment) },
            holidays = holidays, holidayRegion = records.extendedSchedule?.takeIf { it.isEnabled }?.content?.holidayRegionIdentifier,
        )
    } else {
        LeaveResultsPageLayout(title, back, backLabel, page = resultsPage) {
            if (searchedEstimatedYears.isNotEmpty()) {
                Column(Modifier.padding(horizontal = DoneAtSpacing.page)) {
                    searchedEstimatedYears.forEach { Note(Strings.holidayEstimatedYearWarning(context.resources, it.toString())) }
                }
            }
            SettingsGroup {
                Text(text.string(R.string.leaveNoResults), Modifier.padding(DoneAtSpacing.l),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            DoneAtPrimaryButton(text.string(R.string.leaveAdjustConditions), { open(Route.LeavePlannerAdjustment) }, Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page))
        }
    }
}

// One option

/**
 * One option in full: complete calendar months, the shifts to ask off and when,
 * what each balance has left after it, and the shifts either side.
 * Adopting writes every day or none.
 */
@Composable
fun LeavePlanDetailScreen(graph: AppGraph, index: Int, onBack: () -> Unit, onAdopted: () -> Unit) {
    val text = rememberLeaveText(graph)
    val holidays by graph.holidays.collectAsStateWithLifecycle()
    val proposals by graph.leaveProposals.collectAsStateWithLifecycle()
    val records by graph.records.state.collectAsStateWithLifecycle()
    val plus by graph.plus.authorized.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val context = LocalContext.current
    val proposal = proposals?.getOrNull(index)
    LaunchedEffect(proposal == null) { if (proposal == null) onBack() }
    var adopting by remember { mutableStateOf(false) }
    var failed by rememberSaveable { mutableStateOf(false) }
    proposal ?: return

    fun adopt() {
        if (adopting) return
        adopting = true
        scope.launch {
            val now = graph.nowMs()
            val planID = graph.newId()
            val zone = prefs.recordsTimeZoneIdentifier
            val result = graph.records.update { state ->
                when (val outcome = LeaveAdoption.rows(proposal, planID, zone, now, state.leaveBalances, state.leaveDays)) {
                    is LeaveAdoption.Outcome.Adopted -> LeaveAdoption.adopt(state, outcome.rows, now, graph.newId) to true
                    is LeaveAdoption.Outcome.Rejected -> state to false
                }
            }
            adopting = false
            if (result is WriteResult.Saved && result.value) {
                Haptics.confirm(view)
                onAdopted()
            } else {
                failed = true
            }
        }
    }

    val title = text.range(text.monthDay(proposal.firstRestDayNumber), text.monthDay(proposal.lastRestDayNumber))
    DoneAtPage(title, onBack, text.string(R.string.leaveResultsTitle)) {
        if (!plus) LeaveTrialBanner(device.leavePlannerTrialsLeft, text)

        // The headline: how long the break is and what it costs, before any detail.
        Column(
            Modifier.padding(horizontal = DoneAtSpacing.page + DoneAtSpacing.xs).semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xxs),
        ) {
            Text(
                Strings.leaveDaysOff(context.resources, proposal.fullRestDays),
                Modifier.semantics { heading() },
                style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold,
            )
            Text(
                if (proposal.costHalfDays == 0) text.string(R.string.leaveNoLeaveNeeded) else text.uses(proposal.costHalfDays),
                style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary,
            )
        }
        SettingsGroup {
            LeavePlanCalendar(proposal, text, device.calendarFirstDay(text.locale), Modifier.padding(DoneAtSpacing.m), holidays, records.extendedSchedule?.takeIf { it.isEnabled }?.content?.holidayRegionIdentifier)
        }

        if (proposal.items.isNotEmpty()) {
            SettingsGroup(text.string(R.string.leaveRequests)) {
                proposal.items.forEachIndexed { i, item ->
                    if (i > 0) RowDivider(inset = false)
                    ListItem(
                        headlineContent = { Text(text.day(item.dayNumber)) },
                        supportingContent = { Text(listOfNotNull(itemDetail(item, text),
                            holidayDayAnnotation(holidays, records.extendedSchedule?.takeIf { it.isEnabled }?.content?.holidayRegionIdentifier,
                                LeavePlannerSchedule.date(item.dayNumber), text.locale)?.description(text.string(R.string.holidayMakeupWorkday), text.string(R.string.holidayEstimatedLabel))).joinToString(" · ")) },
                        trailingContent = {
                            Text(itemTime(item, text), style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"))
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
            }
            SettingsGroup(text.string(R.string.leaveUseBalances)) {
                val rows = proposal.uses.mapNotNull { use -> records.leaveBalances.firstOrNull { it.id == use.balanceID }?.let { it to use } }
                rows.forEachIndexed { i, (balance, use) ->
                    if (i > 0) RowDivider(inset = false)
                    val left = records.availableLeaveHalfDays(balance) - use.halfDays
                    ValueRow(
                        text.balanceName(balance),
                        Strings.leaveBalanceAfter(context.resources, text.halfDays(use.halfDays), text.halfDays(maxOf(0, left))),
                    )
                }
            }
        }

        val caveats = caveatLabels(proposal, text, context.resources)
        if (proposal.lastShiftEndAtMs != null || proposal.nextShiftStartAtMs != null || caveats.isNotEmpty()) {
            Column {
                if (proposal.lastShiftEndAtMs != null || proposal.nextShiftStartAtMs != null) {
                    SettingsGroup {
                        proposal.lastShiftEndAtMs?.let { ValueRow(text.string(R.string.leaveLastShiftEnds), text.moment(it)) }
                        if (proposal.lastShiftEndAtMs != null && proposal.nextShiftStartAtMs != null) RowDivider(inset = false)
                        proposal.nextShiftStartAtMs?.let { ValueRow(text.string(R.string.leaveNextShiftStarts), text.moment(it)) }
                    }
                }
                Column(Modifier.padding(horizontal = DoneAtSpacing.page)) { caveats.forEach { Note(it) } }
            }
        }

        if (proposal.items.isNotEmpty()) {
            DoneAtPrimaryButton(
                text.string(R.string.leaveAdopt), onClick = { adopt() },
                modifier = Modifier.padding(horizontal = DoneAtSpacing.page).fillMaxWidth(), enabled = !adopting,
            )
        }
        Spacer(Modifier.size(DoneAtSpacing.s))
    }

    if (failed) {
        AlertDialog(
            onDismissRequest = { failed = false },
            title = { Text(text.string(R.string.leaveAdoptFailed)) },
            confirmButton = { TextButton(onClick = { failed = false }) { Text(text.string(R.string.close)) } },
        )
    }
}

private fun itemTime(item: LeavePlanItem, text: LeaveText): String {
    val first = item.segments.firstOrNull() ?: return ""
    return text.range(text.time(first.startAtMs), text.time(item.segments.last().endAtMs))
}

private fun itemDetail(item: LeavePlanItem, text: LeaveText): String = when (item.role) {
    LeavePlanItem.Role.BRIDGE -> text.portion(item.portion)
    LeavePlanItem.Role.EARLY_DEPARTURE -> text.string(R.string.leaveRoleEarly)
    LeavePlanItem.Role.LATE_RETURN -> text.string(R.string.leaveRoleLate)
}

/** Each caveat once, with predicted holidays distinguished from missing data. */
private fun caveatLabels(proposal: LeavePlanProposal, text: LeaveText, res: android.content.res.Resources): List<String> {
    val years = proposal.caveats.filterIsInstance<LeavePlannerCaveat.HolidaysNotIncluded>().map { it.year }.sorted()
    val estimatedYears = proposal.caveats.filterIsInstance<LeavePlannerCaveat.HolidaysEstimated>().map { it.year }.sorted()
    return estimatedYears.map { Strings.holidayEstimatedYearWarning(res, it.toString()) } +
        years.map { Strings.leaveEstimatedYear(res, it.toString()) } +
        listOfNotNull(
            text.string(R.string.leaveCarriedOverCaveat).takeIf { LeavePlannerCaveat.CarriedOverRoster in proposal.caveats },
            text.string(R.string.leaveUnassignedCaveat).takeIf { LeavePlannerCaveat.Unassigned in proposal.caveats },
        )
}
