package com.rainif.doneat.ui

import androidx.activity.compose.BackHandler
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
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

/**
 * The four main destinations (iOS `AppTab`) with an independent back stack
 * each, so switching tabs never loses a place in another. The navigation
 * suite picks a bottom bar or a rail from the window size, not the device.
 *
 * Back pops the current tab's stack; at the root of any tab but the timer it
 * returns to the timer, and from the timer's root it leaves the app.
 */
@Composable
fun AppShell(graph: AppGraph) {
    val scope = rememberCoroutineScope()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val selected = AppTab.entries.firstOrNull { it.name.equals(device.selectedTab, ignoreCase = true) } ?: AppTab.TIMER
    val stacks = mapOf(
        AppTab.TIMER to rememberNavBackStack(Route.TimerHome),
        AppTab.FOCUS to rememberNavBackStack(Route.FocusHome),
        AppTab.RECORDS to rememberNavBackStack(Route.RecordsHome),
        AppTab.SETTINGS to rememberNavBackStack(Route.SettingsHome),
    )
    fun select(tab: AppTab) = scope.launch { graph.settings.updateDevice { it.copy(selectedTab = tab.name.lowercase()) } }
    val stack = stacks.getValue(selected)

    BackHandler(enabled = stack.size <= 1 && selected != AppTab.TIMER) { select(AppTab.TIMER) }

    // A rail wherever a bottom bar would cost too much height (a phone on its side) or the window is wide.
    val window = currentWindowAdaptiveInfoV2().windowSizeClass
    val layout = if (window.isWidthAtLeastBreakpoint(600) || !window.isHeightAtLeastBreakpoint(480)) {
        NavigationSuiteType.NavigationRail
    } else {
        NavigationSuiteType.NavigationBar
    }
    NavigationSuiteScaffold(
        layoutType = layout,
        navigationSuiteItems = {
            AppTab.entries.forEach { tab ->
                item(
                    selected = tab == selected,
                    onClick = {
                        // Reselecting a tab returns it to its root, as a tab bar does.
                        if (tab == selected) stacks.getValue(tab).let { s -> while (s.size > 1) s.removeAt(s.lastIndex) } else select(tab)
                    },
                    icon = { Icon(tab.icon, contentDescription = null) },
                    label = { Text(stringResource(tab.title)) },
                )
            }
        },
    ) {
        NavDisplay(
            backStack = stack,
            onBack = { if (stack.size > 1) stack.removeAt(stack.lastIndex) },
            entryProvider = { key ->
                entry(key, stack, graph) { route ->
                    // The timer's shortcuts land in Settings, with the page already open.
                    val settings = stacks.getValue(AppTab.SETTINGS)
                    while (settings.size > 1) settings.removeAt(settings.lastIndex)
                    route?.let(settings::add)
                    select(AppTab.SETTINGS)
                }
            },
        )
    }
}

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
private fun entry(key: NavKey, stack: NavBackStack<NavKey>, graph: AppGraph, openSettings: (Route?) -> Unit): NavEntry<NavKey> = NavEntry(key) {
    val scope = rememberCoroutineScope()
    val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val records by graph.records.state.collectAsStateWithLifecycle()
    val open: (Route) -> Unit = { stack.add(it) }
    val back: () -> Unit = { if (stack.size > 1) stack.removeAt(stack.lastIndex) }
    val edit: ((com.rainif.doneat.core.domain.records.SyncedPreferences) -> com.rainif.doneat.core.domain.records.SyncedPreferences) -> Unit =
        { change -> scope.launch { graph.settings.edit(change) } }
    val settingsLabel = stringResource(R.string.settings)
    when (key) {
        Route.TimerHome -> TimerScreen(graph, openSettings)
        Route.FocusHome -> PendingScreen(stringResource(R.string.focusTitle), null, null)
        Route.RecordsHome -> PendingScreen(stringResource(R.string.recordsTab), null, null)
        Route.SettingsHome -> SettingsHomeScreen(prefs, records, open)
        Route.Schedule -> com.rainif.doneat.ui.schedule.ScheduleScreen(graph, open, back)
        Route.ShiftTypes -> com.rainif.doneat.ui.schedule.ShiftTypesScreen(graph, open, back)
        is Route.ShiftTypeEdit -> com.rainif.doneat.ui.schedule.ShiftTypeEditScreen(graph, key.id, key.isNew, back)
        Route.Salary -> com.rainif.doneat.ui.settings.SalaryScreen(graph, back)
        Route.RecordsData -> PendingScreen(stringResource(R.string.recordsDataTitle), back, settingsLabel)
        Route.Plus -> PendingScreen(stringResource(R.string.plusSettings), back, settingsLabel)
        Route.Notifications -> NotificationsScreen(
            prefs, device.notificationPermissionRequested, edit,
            markPermissionRequested = { scope.launch { graph.settings.updateDevice { it.copy(notificationPermissionRequested = true) } } },
            // Entitlements arrive with Play Billing (T20); until then nothing is unlocked.
            isPlus = false,
            open = open,
            onBack = back,
        )
        Route.Health -> HealthScreen(prefs, edit, back)
        Route.Theme -> ThemeScreen(prefs, device, edit, { on -> scope.launch { graph.settings.updateDevice { it.copy(dynamicColor = on) } } }, back)
        Route.Language -> {
            val context = androidx.compose.ui.platform.LocalContext.current
            LanguageScreen(prefs, { code ->
                scope.launch {
                    // Android 13+ also records it as the app's system language; the activity then restarts in it.
                    if (graph.settings.edit { it.copy(languageOverride = code) }) AppLocale.applyToSystem(context, code)
                }
            }, back)
        }
        Route.About -> AboutScreen(open, back)
        Route.Acknowledgements -> AcknowledgementsScreen(back)
        else -> PendingScreen("", back, settingsLabel)
    }
}
