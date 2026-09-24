package com.rainif.doneat.ui

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

/** The four main destinations, as iOS `AppTab`. Each keeps its own back stack. */
enum class AppTab { TIMER, FOCUS, RECORDS, SETTINGS }

/**
 * Every screen a back stack can hold (iOS `AppRoute`). Serializable so each
 * tab's stack survives the process being recreated.
 */
sealed interface Route : NavKey {
    @Serializable data object TimerHome : Route
    @Serializable data object FocusHome : Route
    @Serializable data object RecordsHome : Route
    @Serializable data object SettingsHome : Route

    @Serializable data object Schedule : Route
    @Serializable data object Salary : Route
    @Serializable data object Notifications : Route
    @Serializable data object Health : Route
    @Serializable data object Theme : Route
    @Serializable data object Language : Route
    @Serializable data object RecordsData : Route
    @Serializable data object Plus : Route
    @Serializable data object About : Route
    @Serializable data object Acknowledgements : Route

    /** Records: one day, and the list of every recorded day by year and month. */
    @Serializable data class RecordsDay(val dayKey: String) : Route
    @Serializable data object RecordsAll : Route
    @Serializable data class RecordsYear(val year: Int) : Route
    @Serializable data class RecordsMonth(val year: Int, val month: Int) : Route
    @Serializable data class RecordsDayEdit(val dayKey: String) : Route
    @Serializable data object RecordsLifeEdit : Route

    /** Focus: creating a task (in a block, the next free one, or a favourite), editing one, the timer. */
    @Serializable data class FocusCreate(val blockStartAtMs: Long?, val currentOrNext: Boolean, val favoriteID: String?) : Route
    @Serializable data class FocusTaskEdit(val taskID: String) : Route
    @Serializable data object FocusTimerSettings : Route

    /** The schedule page's shift types, edited within its draft. */
    @Serializable data object ShiftTypes : Route
    @Serializable data class ShiftTypeEdit(val id: String, val isNew: Boolean) : Route
}

val AppTab.root: Route
    get() = when (this) {
        AppTab.TIMER -> Route.TimerHome
        AppTab.FOCUS -> Route.FocusHome
        AppTab.RECORDS -> Route.RecordsHome
        AppTab.SETTINGS -> Route.SettingsHome
    }
