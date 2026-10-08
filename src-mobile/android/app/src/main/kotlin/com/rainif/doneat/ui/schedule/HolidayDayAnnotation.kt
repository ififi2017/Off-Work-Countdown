package com.rainif.doneat.ui.schedule

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.res.stringResource
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.l10n.Strings
import java.time.LocalDate
import java.util.Locale

/** Calendar facts only: annotating a manually assigned day never changes its resolved shift. */
internal data class HolidayDayAnnotation(val name: String, val isMakeupWorkday: Boolean, val isEstimated: Boolean) {
    fun status(makeupLabel: String, estimatedLabel: String): String? =
        listOfNotNull(makeupLabel.takeIf { isMakeupWorkday }, estimatedLabel.takeIf { isEstimated })
            .takeIf { it.isNotEmpty() }?.joinToString(" · ")

    fun description(makeupLabel: String, estimatedLabel: String): String =
        listOfNotNull(name, status(makeupLabel, estimatedLabel)).joinToString(" · ")
}

internal fun holidayDayAnnotation(calendar: HolidayCalendar, region: String?, date: LocalDate, locale: Locale): HolidayDayAnnotation? {
    if (region.isNullOrEmpty()) return null
    val day = calendar.day(date.year * 10_000 + date.monthValue * 100 + date.dayOfMonth, region) ?: return null
    return HolidayDayAnnotation(localizedHolidayName(day, locale), day.isWorkday, calendar.isEstimated(date.year, region))
}

internal fun localizedHolidayName(day: HolidayCalendar.Day, locale: Locale): String {
    val regional = if (locale.country.isNotEmpty()) "${locale.language}-${locale.country}" else null
    val chinese = if (locale.language == "zh") when {
        locale.country == "HK" -> "zh-HK"
        locale.country in setOf("TW", "MO") || locale.script == "Hant" -> "zh-TW"
        else -> "zh-CN"
    } else null
    return day.names[locale.toLanguageTag()] ?: regional?.let(day.names::get) ?: chinese?.let(day.names::get)
        ?: day.names[locale.language] ?: day.names["en"] ?: day.names.toSortedMap().values.firstOrNull().orEmpty()
}

/** Compact visible caption; full festival, workday and prediction facts stay in accessibility and details. */
@Composable
internal fun HolidayDayCaption(annotation: HolidayDayAnnotation, modifier: Modifier = Modifier, onSelectedColor: Boolean = false) {
    Text(if (annotation.isMakeupWorkday) stringResource(R.string.holidayMakeupShort) else annotation.name,
        modifier.fillMaxWidth(), style = MaterialTheme.typography.labelSmall.copy(lineHeight = MaterialTheme.typography.labelSmall.fontSize),
        color = if (onSelectedColor) MaterialTheme.colorScheme.onPrimary else if (annotation.isMakeupWorkday) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

/** Keep the full dataset warning visible even in a week without a holiday-labelled day. */
@Composable
internal fun HolidayCoverageNotice(calendar: HolidayCalendar, region: String?, first: LocalDate, last: LocalDate) {
    if (region.isNullOrEmpty()) return
    val resources = LocalResources.current
    val nextYear = (first.year + 1).takeIf { first.monthValue == 12 && last.year == first.year }
    val years = ((first.year..last.year).toList() + listOfNotNull(nextYear)).distinct()
    years.forEach { year ->
        val warning = when {
            calendar.isEstimated(year, region) -> Strings.holidayEstimatedYearWarning(resources, year.toString())
            !calendar.covers(year, region) -> if (year == nextYear) Strings.holidayCoverageNextYearWarning(resources, year.toString())
                else Strings.holidayCoverageYearWarning(resources, year.toString())
            else -> null
        }
        if (warning != null) Text(warning, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
