package com.rainif.doneat.ui.records

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.unit.dp
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.records.RecordDayIndexEntry
import com.rainif.doneat.core.domain.records.RecordsAccess
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.NavigationRow
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsGroup
import java.time.LocalDate

/**
 * The free window applies before any row is built: without Plus, older
 * history is reduced to one "locked" row, so no year, date or count outside
 * the window reaches the list or the screen reader (iOS
 * `RecordsAllRecordsPresentation`).
 */
internal class VisibleRecords(entries: List<RecordDayIndexEntry>, authorized: Boolean, private val today: LocalDate) {
    private fun inWindow(entry: RecordDayIndexEntry) =
        runCatching { RecordsAccess.freeWindowContains(LocalDate.parse(entry.dayKey), today) }.getOrDefault(false)

    val entries = if (authorized) entries else entries.filter(::inWindow)
    val hasLockedHistory = !authorized && entries.any { !inWindow(it) }
    private val byYear = this.entries.groupBy { it.dayKey.take(4).toIntOrNull() }
    private val byMonth = this.entries.groupBy { it.dayKey.take(7) }
    val years = byYear.keys.filterNotNull().sortedDescending()
    private val months = byYear.mapValues { (_, days) -> days.mapNotNull { it.dayKey.substring(5, 7).toIntOrNull() }.distinct().sortedDescending() }

    fun count(year: Int) = byYear[year].orEmpty().size
    fun months(year: Int) = months[year].orEmpty()
    fun days(year: Int, month: Int) = byMonth["%04d-%02d".format(java.util.Locale.ROOT, year, month)].orEmpty()
}

@Composable
private fun rememberVisible(context: RecordsContext): VisibleRecords? {
    val archive = context.queries.state
    val authorized = context.queries.authorized
    val today = context.today
    var visible by remember(archive, authorized, today) { mutableStateOf<VisibleRecords?>(null) }
    LaunchedEffect(archive, authorized, today) {
        visible = computeRecords { check ->
            VisibleRecords(context.queries.indexedRecords(check), authorized, today)
        }
    }
    return visible
}

@Composable
fun AllRecordsScreen(graph: AppGraph, open: (Route) -> Unit, onBack: () -> Unit) {
    val context = rememberRecordsContext(graph)
    val text = context.text
    val res = LocalResources.current
    val visible = rememberVisible(context)
    DoneAtPage(text.string(R.string.recordsAllRecords), onBack, text.string(R.string.recordsTitle)) {
        if (visible == null) {
            CircularProgressIndicator(Modifier.padding(DoneAtSpacing.page))
            return@DoneAtPage
        }
        if (visible.years.isEmpty() && !visible.hasLockedHistory) {
            RecordsCard(Modifier.padding(horizontal = DoneAtSpacing.page)) {
                Column(Modifier.padding(16.dp)) {
                    Text(text.string(R.string.recordsEmptyTitle), style = MaterialTheme.typography.bodyLarge)
                    Text(text.string(R.string.recordsEmptyBody), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (visible.years.isNotEmpty()) {
            SettingsGroup {
                visible.years.forEachIndexed { index, year ->
                    if (index > 0) RowDivider(inset = false)
                    NavigationRow(
                        year.toString(),
                        { open(Route.RecordsYear(year)) },
                        supporting = if (context.queries.authorized) Strings.recordsMonthWorkdays(res, visible.count(year)) else null,
                    )
                }
            }
        }
        if (visible.hasLockedHistory) LockedRow(text)
    }
}

@Composable
fun YearRecordsScreen(graph: AppGraph, year: Int, open: (Route) -> Unit, onBack: () -> Unit) {
    val context = rememberRecordsContext(graph)
    val text = context.text
    val visible = rememberVisible(context)
    DoneAtPage(year.toString(), onBack, text.string(R.string.recordsAllRecords)) {
        if (visible == null) {
            CircularProgressIndicator(Modifier.padding(DoneAtSpacing.page))
            return@DoneAtPage
        }
        val months = visible.months(year)
        if (months.isEmpty()) {
            LockedRow(text)
        } else {
            SettingsGroup {
                months.forEachIndexed { index, month ->
                    if (index > 0) RowDivider(inset = false)
                    NavigationRow(text.monthYear(LocalDate.of(year, month, 1)), { open(Route.RecordsMonth(year, month)) })
                }
            }
        }
    }
}

@Composable
fun MonthRecordsScreen(graph: AppGraph, year: Int, month: Int, open: (Route) -> Unit, onBack: () -> Unit) {
    val context = rememberRecordsContext(graph)
    val text = context.text
    val visible = rememberVisible(context)
    DoneAtPage(text.monthYear(LocalDate.of(year, month, 1)), onBack, year.toString()) {
        if (visible == null) {
            CircularProgressIndicator(Modifier.padding(DoneAtSpacing.page))
            return@DoneAtPage
        }
        val days = visible.days(year, month)
        if (days.isEmpty()) {
            LockedRow(text)
        } else {
            SettingsGroup {
                days.forEachIndexed { index, day ->
                    if (index > 0) RowDivider(inset = false)
                    NavigationRow(text.dayTitle(day.dayKey), { open(Route.RecordsDay(day.dayKey)) })
                }
            }
        }
    }
}

@Composable
private fun LockedRow(text: RecordsText) {
    SettingsGroup {
        ListItem(
            headlineContent = { Text(text.string(R.string.recordsLockedDay)) },
            trailingContent = { Icon(Icons.Filled.Lock, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.outline) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}
