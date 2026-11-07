package com.rainif.doneat.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtRecordsStyle
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtRecordsColors
import com.rainif.doneat.core.domain.summary.MonthlyDailyPay
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsFooter
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.timer.TimerText
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import android.text.format.DateFormat

/**
 * "Daily pay by month" (iOS `MonthlyDailyPayView`, plan 024): this month's daily
 * pay, the calendar it is divided by, and the next three months. It is drawn
 * inside the unlocked salary page, which owns the unlock and leaves it whenever
 * the page locks, so the figures never outlive the salary page's own gate.
 * Every figure comes from [MonthlyDailyPay].
 */
@Composable
internal fun MonthlyDailyPayPage(pay: MonthlyDailyPay, text: TimerText, firstWeekday: DayOfWeek, onBack: () -> Unit) {
    val res = LocalResources.current
    DoneAtPage(stringResource(R.string.monthlyDailyPayTitle), onBack, stringResource(R.string.salarySettings)) {
        Surface(
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            modifier = Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page),
        ) {
            Column(Modifier.padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    Text(monthName(pay.current.startMs, pay.zone, text), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        text.money(pay.current.dailyPay),
                        style = MaterialTheme.typography.headlineLarge.copy(fontFeatureSettings = "tnum"),
                        fontWeight = FontWeight.Bold,
                    )
                    if (pay.current.workdayCount >= 1) {
                        Text(
                            "${text.money(pay.monthlyAmount)} ÷ ${Strings.scheduledMonthWorkdays(res, text.count(pay.current.workdayCount))}",
                            style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                MonthGrid(pay, text, firstWeekday)
            }
        }
        SettingsGroup(title = stringResource(R.string.monthlyDailyPayUpcoming)) {
            pay.upcoming.forEachIndexed { index, month ->
                if (index > 0) RowDivider(inset = false)
                MonthRow(
                    monthName(month.startMs, pay.zone, text),
                    Strings.scheduledMonthWorkdays(res, text.count(month.workdayCount)),
                    text.money(month.dailyPay),
                )
            }
        }
        Column(Modifier.padding(horizontal = DoneAtSpacing.page)) { SettingsFooter(stringResource(R.string.monthlyDailyPayNote)) }
        Spacer(Modifier.heightIn(min = DoneAtSpacing.l))
    }
}

@Composable
private fun MonthRow(title: String, supporting: String, value: String) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(supporting, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(value, style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun MonthGrid(pay: MonthlyDailyPay, text: TimerText, firstWeekday: DayOfWeek) {
    val work = stringResource(R.string.extendedKindWork)
    val rest = stringResource(R.string.extendedKindRest)
    val cells: List<MonthlyDailyPay.Day?> = List(pay.leadingBlanks) { null } + pay.days
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
        Row(Modifier.clearAndSetSemantics {}) {
            (0 until 7).forEach { column ->
                Text(
                    DayOfWeek.of(Math.floorMod(firstWeekday.value - 1 + column, 7) + 1).getDisplayName(TextStyle.NARROW_STANDALONE, text.locale),
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
        cells.chunked(7).forEach { week ->
            Row(Modifier.fillMaxWidth()) {
                (0 until 7).forEach { column ->
                    Box(Modifier.weight(1f).heightIn(min = 36.dp), contentAlignment = Alignment.Center) {
                        week.getOrNull(column)?.let { day -> DayCell(day, text, if (day.isWorkday) work else rest) }
                    }
                }
            }
        }
    }
}

@Composable
private fun DayCell(day: MonthlyDailyPay.Day, text: TimerText, kind: String) {
    val accent = MaterialTheme.colorScheme.primary
    val fill = when {
        day.isToday && day.isWorkday -> accent
        day.isWorkday -> LocalDoneAtRecordsColors.current.work.copy(alpha = DoneAtRecordsStyle.workdayFillOpacity)
        else -> null
    }
    var modifier = Modifier.size(32.dp)
    if (fill != null) modifier = modifier.background(fill, CircleShape)
    if (day.isToday && !day.isWorkday) modifier = modifier.border(1.5.dp, accent, CircleShape)
    val label = "${text.count(day.day)}, $kind"
    Box(modifier.semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Text(
            text.count(day.day),
            style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"),
            fontWeight = if (day.isToday) FontWeight.SemiBold else FontWeight.Normal,
            color = when {
                day.isToday && day.isWorkday -> MaterialTheme.colorScheme.onPrimary
                day.isWorkday -> MaterialTheme.colorScheme.onSurface
                else -> MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

/** "November 2026", in the page's language and the pay's zone. */
internal fun monthName(atMs: Double, zone: ZoneId, text: TimerText): String =
    DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(text.locale, "yMMMM"), text.locale)
        .format(Instant.ofEpochMilli(atMs.toLong()).atZone(zone))

/** "Nov" ("11月" in Chinese, not "十一月"), for the salary row's subtitle. */
internal fun shortMonthName(atMs: Double, zone: ZoneId, text: TimerText): String =
    DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(text.locale, "MMM"), text.locale)
        .format(Instant.ofEpochMilli(atMs.toLong()).atZone(zone))
