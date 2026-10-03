package com.rainif.doneat.ui

import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.LayoutDirection
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.fragment.app.FragmentActivity
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import androidx.navigationevent.NavigationEvent
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.records.LifeProfileDraft
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.ui.records.configuredMonthlySalary
import com.rainif.doneat.core.designsystem.DoneAtGlassNavigation
import com.rainif.doneat.core.designsystem.DoneAtNavigationItem
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.ui.settings.AboutScreen
import com.rainif.doneat.ui.settings.AcknowledgementsScreen
import com.rainif.doneat.ui.settings.HealthScreen
import com.rainif.doneat.ui.settings.LanguageScreen
import com.rainif.doneat.ui.settings.NotificationsScreen
import com.rainif.doneat.ui.settings.PendingScreen
import com.rainif.doneat.ui.settings.SettingsHomeScreen
import com.rainif.doneat.ui.settings.ThemeScreen
import com.rainif.doneat.ui.timer.TimerScreen
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import java.time.Instant

/**
 * The four main destinations (iOS `AppTab`) with an independent back stack
 * each, so switching tabs never loses a place in another. The navigation
 * suite picks a bottom bar or a rail from the window size, not the device.
 *
 * Back pops the current tab's stack; at the root of any tab but the timer it
 * returns to the timer, and from the timer's root it leaves the app.
 */
@Composable
fun AppShell(graph: AppGraph, onReportStageChanged: (Boolean) -> Unit = {}) {
    val reportStageChanged by rememberUpdatedState(onReportStageChanged)
    DisposableEffect(Unit) { onDispose { reportStageChanged(false) } }
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val selectedState = rememberSaveable { mutableStateOf(tabFromStoredName(device.selectedTab)) }
    var selected by selectedState
    LaunchedEffect(device.selectedTab) { selected = tabFromStoredName(device.selectedTab) }
    val tabState = rememberSaveableStateHolder()
    val motion = LocalDoneAtMotion.current
    val direction = if (LocalLayoutDirection.current == LayoutDirection.Rtl) -1 else 1
    val stacks = mapOf(
        AppTab.TIMER to rememberNavBackStack(Route.TimerHome),
        AppTab.FOCUS to rememberNavBackStack(Route.FocusHome),
        AppTab.RECORDS to rememberNavBackStack(Route.RecordsHome),
        AppTab.SETTINGS to rememberNavBackStack(Route.SettingsHome),
    )
    fun select(tab: AppTab) {
        selected = tab
        graph.scope.launch { graph.settings.updateDevice { it.copy(selectedTab = tab.name.lowercase()) } }
    }
    fun continueAfterPlus(action: PlusPendingAction) {
        val source = stacks.getValue(selected)
        if (source.lastOrNull() is Route.PlusFor) source.removeAt(source.lastIndex)
        when (action) {
            is PlusPendingAction.FocusCreate -> {
                stacks.getValue(AppTab.FOCUS).add(Route.FocusCreate(action.blockStartAtMs, action.currentOrNext, null))
                select(AppTab.FOCUS)
            }
            PlusPendingAction.FocusHome -> select(AppTab.FOCUS)
            is PlusPendingAction.RecordsDay -> {
                stacks.getValue(AppTab.RECORDS).add(Route.RecordsDay(action.dayKey))
                select(AppTab.RECORDS)
            }
            PlusPendingAction.RecordsLifeEdit -> {
                val zone = FoundationCompat.javaZone(graph.settings.preferences.value.recordsTimeZoneIdentifier)
                val today = Instant.ofEpochMilli(graph.nowMs().toLong()).atZone(zone).toLocalDate()
                graph.lifeEditDraft.value = LifeProfileDraft.load(
                    graph.records.state.value.lifeProfile, today, configuredMonthlySalary(graph), graph.newId,
                )
                stacks.getValue(AppTab.RECORDS).add(Route.RecordsLifeEdit)
                select(AppTab.RECORDS)
            }
            PlusPendingAction.RecordsCharts -> select(AppTab.RECORDS)
            PlusPendingAction.CycleSummary -> graph.scope.launch {
                graph.settings.updateDevice { it.copy(weeklyReportEnabled = true) }
            }
            // The options stay underneath, so Back from the plan returns to them.
            is PlusPendingAction.LeavePlan -> source.add(Route.LeavePlanDetail(action.index))
        }
    }
    val requestedTab by graph.requestedTab.collectAsStateWithLifecycle()
    LaunchedEffect(requestedTab) {
        requestedTab?.let { name ->
            val tab = tabFromStoredName(name)
            stacks.getValue(tab).let { s -> while (s.size > 1) s.removeAt(s.lastIndex) }
            select(tab)
            graph.requestedTab.value = null
        }
    }
    val requestedReport by graph.requestedReport.collectAsStateWithLifecycle()
    LaunchedEffect(requestedReport) {
        requestedReport?.let { period ->
            val reports = stacks.getValue(AppTab.RECORDS)
            while (reports.size > 1) reports.removeAt(reports.lastIndex)
            reports.add(Route.CycleReport(period.kind.name, period.startDayKey, period.endDayKey, period.timeZoneIdentifier))
            select(AppTab.RECORDS)
            graph.requestedReport.value = null
        }
    }
    val stack = stacks.getValue(selected)
    LaunchedEffect(selected, stack.lastOrNull()) {
        reportStageChanged(stack.lastOrNull() is Route.CycleReport)
    }
    val reviewBlocked by graph.reviewBlocked.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = remember(context) { context.fragmentActivity() }
    LaunchedEffect(activity, selected, stack.lastOrNull(), reviewBlocked) {
        val host = activity ?: return@LaunchedEffect
        if (selected != AppTab.TIMER || stack.lastOrNull() != Route.TimerHome || reviewBlocked) return@LaunchedEffect
        host.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            // Let the root settle after launch or navigation before asking Play.
            delay(650)
            graph.reviews.requestIfEligible(host) {
                selectedState.value == AppTab.TIMER &&
                    stacks.getValue(AppTab.TIMER).lastOrNull() == Route.TimerHome &&
                    !graph.reviewBlocked.value && graph.requestedTab.value == null
            }
        }
    }

    BackHandler(enabled = stack.size <= 1 && selected != AppTab.TIMER) { select(AppTab.TIMER) }

    // A rail wherever a bottom bar would cost too much height (a phone on its side) or the window is wide.
    val window = currentWindowAdaptiveInfoV2().windowSizeClass
    val layout = if (window.isWidthAtLeastBreakpoint(600) || !window.isHeightAtLeastBreakpoint(480)) {
        NavigationSuiteType.NavigationRail
    } else {
        NavigationSuiteType.NavigationBar
    }
    val content: @Composable () -> Unit = {
        // A tab changes immediately and keeps its own saved screen state. Only
        // navigation inside that tab slides; it never crossfades two root pages.
        tabState.SaveableStateProvider(selected) {
        NavDisplay(
            backStack = stack.filterNot { it is Route.CycleReport },
            sizeTransform = null,
            transitionSpec = {
                if (motion.reduced) EnterTransition.None togetherWith ExitTransition.None
                else slideInHorizontally(motion.phase()) { direction * it } togetherWith
                    slideOutHorizontally(motion.phase()) { -direction * it / 4 }
            },
            popTransitionSpec = {
                if (motion.reduced) EnterTransition.None togetherWith ExitTransition.None
                else slideInHorizontally(motion.phase()) { -direction * it / 4 } togetherWith
                    slideOutHorizontally(motion.phase()) { direction * it }
            },
            predictivePopTransitionSpec = { swipeEdge ->
                val backDirection = when (swipeEdge) {
                    NavigationEvent.EDGE_LEFT -> 1
                    NavigationEvent.EDGE_RIGHT -> -1
                    else -> direction
                }
                if (motion.reduced) EnterTransition.None togetherWith ExitTransition.None
                else slideInHorizontally(motion.phase()) { -backDirection * it / 4 } togetherWith
                    slideOutHorizontally(motion.phase()) { backDirection * it }
            },
            onBack = { if (stack.size > 1) stack.removeAt(stack.lastIndex) },
            entryProvider = { key ->
                entry(key, stack, graph, { action -> continueAfterPlus(action) }, openSettings = { route ->
                    if (route is Route.PlusFor) {
                        // A purchase prompted by a feature returns to that feature on Back.
                        stack.add(route)
                    } else {
                        // The timer's shortcuts land in Settings, with the page already open.
                        val settings = stacks.getValue(AppTab.SETTINGS)
                        while (settings.size > 1) settings.removeAt(settings.lastIndex)
                        route?.let(settings::add)
                        select(AppTab.SETTINGS)
                    }
                })
            },
        )
        }
    }
    fun selectOrReturnToRoot(tab: AppTab) {
        if (tab == selected) stacks.getValue(tab).let { s -> while (s.size > 1) s.removeAt(s.lastIndex) }
        else select(tab)
    }
    val reportRoute = stack.lastOrNull() as? Route.CycleReport
    Box(Modifier.fillMaxSize()) {
    Box(if (reportRoute != null) Modifier.clearAndSetSemantics { } else Modifier) {
    if (layout == NavigationSuiteType.NavigationBar) {
        DoneAtGlassNavigation(
            items = AppTab.entries.map { DoneAtNavigationItem(stringResource(it.title), it.icon) },
            selectedIndex = selected.ordinal,
            onSelect = { selectOrReturnToRoot(AppTab.entries[it]) },
            content = content,
        )
    } else {
        NavigationSuiteScaffold(
            layoutType = layout,
            navigationSuiteItems = {
                AppTab.entries.forEach { tab ->
                    item(selected = tab == selected, onClick = { selectOrReturnToRoot(tab) },
                        icon = { Icon(tab.icon, contentDescription = null) },
                        label = { Text(stringResource(tab.title)) })
                }
            },
            content = content,
        )
    }
    }
    if (reportRoute != null) {
        // Keep both the source screen and the report alive until the cover has left.
        // Moving NavDisplay between two branches destroyed its transition state.
        val cover = remember(reportRoute) { MutableTransitionState(false).apply { targetState = true } }
        var unlock by remember(reportRoute) { mutableStateOf(false) }
        val close = { cover.targetState = false }
        LaunchedEffect(cover.isIdle, cover.currentState, cover.targetState) {
            if (cover.isIdle && !cover.currentState && !cover.targetState) {
                if (stack.lastOrNull() == reportRoute) stack.removeAt(stack.lastIndex)
                if (unlock) stack.add(Route.PlusFor(PlusPendingAction.RecordsCharts))
            }
        }
        AnimatedVisibility(
            visibleState = cover,
            enter = if (motion.reduced) EnterTransition.None else slideInVertically(motion.reportCover()) { it },
            exit = if (motion.reduced) ExitTransition.None else slideOutVertically(motion.reportCover()) { it },
        ) {
            NavDisplay(
                backStack = listOf<NavKey>(reportRoute),
                onBack = close,
                entryProvider = { key -> entry(key, stack, graph, ::continueAfterPlus, {}, close) {
                    unlock = true
                    close()
                } },
            )
        }
        BackHandler { close() }
    }
    }
}

private fun Context.fragmentActivity(): FragmentActivity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is FragmentActivity) return current
        current = current.baseContext
    }
    return current as? FragmentActivity
}

private fun tabFromStoredName(value: String): AppTab =
    AppTab.entries.firstOrNull { it.name.equals(value, ignoreCase = true) } ?: AppTab.TIMER

private val AppTab.title: Int
    get() = when (this) {
        AppTab.TIMER -> R.string.timerTab
        AppTab.FOCUS -> R.string.focusTitle
        AppTab.RECORDS -> R.string.recordsTab
        AppTab.SETTINGS -> R.string.settings
    }

private val AppTab.icon
    get() = when (this) {
        AppTab.TIMER -> Icons.Outlined.Schedule
        AppTab.FOCUS -> Icons.Outlined.Timer
        AppTab.RECORDS -> Icons.Outlined.CalendarMonth
        AppTab.SETTINGS -> Icons.Outlined.Tune
    }

/** The single destination registry every stack uses (iOS `AppRouteDestination`). */
private fun entry(key: NavKey, stack: NavBackStack<NavKey>, graph: AppGraph,
    continueAfterPlus: (PlusPendingAction) -> Unit, openSettings: (Route?) -> Unit,
    closeReport: (() -> Unit)? = null, unlockReport: (() -> Unit)? = null): NavEntry<NavKey> = NavEntry(key) {
    if (key is Route.RecordsDayEdit || key == Route.RecordsLifeEdit || key is Route.FocusTemplateEdit) {
        // Keep the outgoing page intact during a predictive gesture and its finish animation.
        // A child editor or tab switch keeps this key in the stack, so its draft survives.
        DisposableEffect(key, stack) {
            onDispose {
                if (key !in stack) when (key) {
                    is Route.RecordsDayEdit -> if (stack.none { it is Route.RecordsDayEdit }) graph.dayEditDraft.value = null
                    Route.RecordsLifeEdit -> if (Route.RecordsLifeEdit !in stack) graph.lifeEditDraft.value = null
                    is Route.FocusTemplateEdit -> if (stack.none { it is Route.FocusTemplateEdit }) graph.focusTemplateDraft.value = null
                    else -> Unit
                }
            }
        }
    }
    val scope = rememberCoroutineScope()
    val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val records by graph.records.state.collectAsStateWithLifecycle()
    val plus by graph.plus.authorized.collectAsStateWithLifecycle()
    val open: (Route) -> Unit = { stack.add(it) }
    val back: () -> Unit = { if (stack.size > 1 && stack.lastOrNull() == key) stack.removeAt(stack.lastIndex) }
    val edit: ((com.rainif.doneat.core.domain.records.SyncedPreferences) -> com.rainif.doneat.core.domain.records.SyncedPreferences) -> Unit =
        { change -> scope.launch { graph.settings.edit(change) } }
    val settingsLabel = stringResource(R.string.settings)
    when (key) {
        Route.TimerHome -> TimerScreen(graph, open, openSettings)
        Route.TimerShare -> com.rainif.doneat.share.ShareScreen(graph, back)
        Route.FocusHome -> com.rainif.doneat.ui.focus.FocusScreen(graph, open, openSettings)
        is Route.FocusCreate -> com.rainif.doneat.ui.focus.FocusCreateScreen(graph, key.blockStartAtMs, key.currentOrNext, key.favoriteID, back)
        is Route.FocusTaskEdit -> com.rainif.doneat.ui.focus.FocusTaskEditScreen(graph, key.taskID, back)
        Route.FocusTimerSettings -> com.rainif.doneat.ui.focus.FocusTimerSettingsScreen(graph, back)
        is Route.FocusTemplateEdit -> com.rainif.doneat.ui.focus.FocusTemplateEditScreen(graph, key.templateID, open, back)
        is Route.FocusTemplateTask -> com.rainif.doneat.ui.focus.FocusTemplateTaskScreen(graph, key.taskID, back)
        is Route.CycleReport -> com.rainif.doneat.ui.records.CycleReportScreen(graph, key, closeReport ?: back, unlockReport ?: {})
        Route.RecordsHome -> com.rainif.doneat.ui.records.RecordsScreen(graph, open, openSettings)
        is Route.RecordsDay -> com.rainif.doneat.ui.records.RecordsDayScreen(graph, key.dayKey, open, back, openSettings)
        Route.RecordsAll -> com.rainif.doneat.ui.records.AllRecordsScreen(graph, open, back)
        is Route.RecordsYear -> com.rainif.doneat.ui.records.YearRecordsScreen(graph, key.year, open, back)
        is Route.RecordsMonth -> com.rainif.doneat.ui.records.MonthRecordsScreen(graph, key.year, key.month, open, back)
        is Route.RecordsDayEdit -> com.rainif.doneat.ui.records.RecordsDayEditScreen(graph, key.dayKey, back)
        Route.RecordsLifeEdit -> com.rainif.doneat.ui.records.LifeProfileEditScreen(graph, back)
        Route.SettingsHome -> SettingsHomeScreen(prefs, records, open)
        Route.Schedule -> com.rainif.doneat.ui.schedule.ScheduleScreen(graph, open, back)
        Route.ShiftTypes -> com.rainif.doneat.ui.schedule.ShiftTypesScreen(graph, open, back)
        is Route.ShiftTypeEdit -> com.rainif.doneat.ui.schedule.ShiftTypeEditScreen(graph, key.id, key.isNew, back)
        Route.Salary -> com.rainif.doneat.ui.settings.SalaryScreen(graph, back)
        Route.RecordsData -> com.rainif.doneat.ui.settings.RecordsDataScreen(graph, open, back)
        Route.RecordsConflicts -> com.rainif.doneat.ui.settings.RecordsConflictCenter(graph, back)
        Route.Plus -> com.rainif.doneat.plus.PlusScreen(graph, back)
        is Route.PlusFor -> com.rainif.doneat.plus.PlusScreen(graph, back, key.action, continueAfterPlus)
        Route.Notifications -> NotificationsScreen(
            prefs, device.notificationPermissionRequested, edit,
            markPermissionRequested = { scope.launch { graph.settings.updateDevice { it.copy(notificationPermissionRequested = true) } } },
            isPlus = plus,
            open = open,
            onBack = back,
            device = device,
            editDevice = { change -> scope.launch { graph.settings.updateDevice(change) } },
        )
        Route.Health -> HealthScreen(prefs, edit, back)
        Route.Theme -> ThemeScreen(prefs, device, edit,
            setDynamic = { on -> scope.launch { graph.settings.updateDevice { it.copy(dynamicColor = on) } } },
            setAccent = { rgb -> scope.launch { graph.settings.updateDevice { it.copy(accentColor = rgb, dynamicColor = false) } } },
            onBack = back)
        Route.Language -> {
            val context = androidx.compose.ui.platform.LocalContext.current
            LanguageScreen(prefs, { code ->
                scope.launch {
                    // Android 13+ also records it as the app's system language; the activity then restarts in it.
                    if (graph.settings.edit { it.copy(languageOverride = code) }) AppLocale.applyToSystem(context, code)
                }
            }, back)
        }
        Route.About -> AboutScreen(open, back) { com.rainif.doneat.plus.PlusDebugSection(graph.plus) }
        Route.Acknowledgements -> AcknowledgementsScreen(back)
        is Route.Leave -> com.rainif.doneat.ui.leave.LeaveScreen(graph, key.fromRecords, open, back)
        is Route.LeaveBalanceEdit -> com.rainif.doneat.ui.leave.LeaveBalanceEditScreen(graph, key.balanceID, key.guided, back) {
            // A first balance set up from Records opens the time off page in the editor's place.
            if (key.guided && stack.lastOrNull() == key) {
                stack.removeAt(stack.lastIndex)
                stack.add(Route.Leave(fromRecords = true))
            } else back()
        }
        Route.LeavePlanner -> com.rainif.doneat.ui.leave.LeavePlannerScreen(graph, open, back)
        Route.LeavePlanResults -> com.rainif.doneat.ui.leave.LeavePlanResultsScreen(graph, open, back)
        is Route.LeavePlanDetail -> com.rainif.doneat.ui.leave.LeavePlanDetailScreen(graph, key.index, back) {
            // Adopted: back to the page the planner was opened from.
            while (stack.size > 1 && stack.last().let { it is Route.LeavePlanner || it is Route.LeavePlanResults || it is Route.LeavePlanDetail }) {
                stack.removeAt(stack.lastIndex)
            }
        }
        is Route.LeaveAdoptedPlan -> com.rainif.doneat.ui.leave.AdoptedLeavePlanScreen(graph, key.planID, back)
        else -> PendingScreen("", back, settingsLabel)
    }
}
