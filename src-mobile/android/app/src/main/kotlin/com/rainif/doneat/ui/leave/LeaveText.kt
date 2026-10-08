package com.rainif.doneat.ui.leave

import android.content.res.Resources
import android.text.format.DateFormat
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.leave.LeaveAdoption
import com.rainif.doneat.core.domain.leave.LeavePlannerSchedule
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.LeaveBalance
import com.rainif.doneat.core.domain.records.LeaveDay
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.LeavePortion
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.timer.TimerText
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The leave pages' words (iOS `ShiftSessionStore` leave labels). Days are civil
 * dates in the records time zone, as every leave row stores them; times are
 * read there too, so a plan made at home reads the same while travelling.
 */
class LeaveText(private val res: Resources, val locale: Locale, val zone: ZoneId, use24Hour: Boolean) {
    private fun pattern(skeleton: String) = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, skeleton), locale)

    private val weekdayDay = pattern("MMMdEEE")
    private val monthDay = pattern("MMMd")
    private val month = pattern("yMMMM")
    private val fullDate = pattern("yMMMd")
    private val time = pattern(if (use24Hour) "Hm" else "hm")
    private val numbers = TimerText(res, locale, use24Hour, hideEarnings = false, zone = zone)

    fun string(id: Int): String = res.getString(id)

    /** "3.5 days" from seven half days. */
    fun halfDays(count: Int): String = numbers.days(count / 2.0)

    fun wholeDays(count: Int): String = numbers.days(count.toDouble())

    fun wholeNumber(value: Int): String = numbers.count(value)

    /** Numeric value for templates that already provide their localized day unit. */
    fun halfDaysNumber(count: Int): String = NumberFormat.getNumberInstance(locale)
        .apply { maximumFractionDigits = 1 }.format(count / 2.0)

    /** "Mon, Oct 12": one day of a plan. */
    fun day(dayNumber: Int): String = weekdayDay.format(LeavePlannerSchedule.date(dayNumber))
    fun day(dayKey: String): String = ExtendedScheduleResolver.dayNumber(dayKey)?.let(::day) ?: dayKey

    fun month(dayNumber: Int): String = month.format(LeavePlannerSchedule.date(dayNumber))

    fun monthDay(dayNumber: Int): String = monthDay.format(LeavePlannerSchedule.date(dayNumber))
    fun monthDay(dayKey: String): String = ExtendedScheduleResolver.dayNumber(dayKey)?.let(::monthDay) ?: dayKey

    fun fullDate(dayNumber: Int): String = fullDate.format(LeavePlannerSchedule.date(dayNumber))
    fun fullDate(date: LocalDate): String = fullDate.format(date)
    fun fullDate(dayKey: String): String = ExtendedScheduleResolver.dayNumber(dayKey)?.let(::fullDate) ?: dayKey

    /** Each end isolated, so a range of dates reads in order in either direction. */
    fun range(start: String, end: String) = if (start == end) start else "${TimerText.isolate(start)} – ${TimerText.isolate(end)}"

    fun time(atMs: Double): String = time.format(Instant.ofEpochMilli(atMs.toLong()).atZone(zone))

    /** "Fri, Oct 9 18:00": when the last shift before a break ends. */
    fun moment(atMs: Double): String {
        val date = Instant.ofEpochMilli(atMs.toLong()).atZone(zone).toLocalDate()
        return "${day(LeavePlannerSchedule.dayNumber(date))} ${time(atMs)}"
    }

    fun balanceName(balance: LeaveBalance): String =
        balance.name?.trim()?.takeIf { it.isNotEmpty() } ?: string(kindTitle(balance.kind))

    fun portion(portion: LeavePortion): String = string(
        when (portion) {
            LeavePortion.WHOLE -> R.string.leaveWhole
            LeavePortion.FIRST_HALF -> R.string.leaveFirstHalf
            LeavePortion.SECOND_HALF -> R.string.leaveSecondHalf
        },
    )

    /** An adopted plan's dates, e.g. "Oct 12 – Oct 23". */
    fun planTitle(days: List<LeaveDay>): String {
        val first = days.firstOrNull() ?: return ""
        return range(monthDay(first.dayKey), monthDay(days.last().dayKey))
    }

    fun validUntil(dayKey: String): String = Strings.leaveValidUntilDate(res, fullDate(dayKey))

    fun available(count: Int): String = Strings.leaveAvailable(res, halfDays(count))

    fun uses(count: Int): String = Strings.leaveUses(res, halfDays(count))

    fun trialsLeft(count: Int): String =
        if (count > 0) Strings.leaveTrialsLeft(res, count) else string(R.string.leaveTrialsUsedUp)

    companion object {
        fun kindTitle(kind: String): Int = when (LeaveBalance.normalizedKind(kind)) {
            "annual" -> R.string.leaveKindAnnual
            "compensatory" -> R.string.leaveKindCompensatory
            else -> R.string.leaveKindCustom
        }

        fun kindIcon(kind: String): ImageVector = when (LeaveBalance.normalizedKind(kind)) {
            "annual" -> Icons.Outlined.WbSunny
            "compensatory" -> Icons.AutoMirrored.Outlined.Undo
            else -> Icons.Outlined.LocalOffer
        }
    }
}

@Composable
fun rememberLeaveText(graph: AppGraph): LeaveText {
    val resources = LocalResources.current
    val locale = LocalConfiguration.current.locales[0]
    val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
    val use24Hour = DateFormat.is24HourFormat(LocalContext.current)
    val zone = FoundationCompat.javaZone(prefs.recordsTimeZoneIdentifier)
    return remember(resources, locale, zone, use24Hour) { LeaveText(resources, locale, zone, use24Hour) }
}

/** What is still spendable of [balance] once adopted plans are deducted; 0 when it no longer applies. */
fun RecordState.availableLeaveHalfDays(balance: LeaveBalance): Int =
    LeaveAdoption.budgets(listOf(balance), leaveDays).firstOrNull()?.availableHalfDays ?: 0

/** The settings row's value: what is left across every balance, or nothing before the first one. */
fun RecordState.leaveSummaryHalfDays(): Int? =
    if (leaveBalances.isEmpty()) null else LeaveAdoption.budgets(leaveBalances, leaveDays).sumOf { it.availableHalfDays }

/** Today in the records zone: the first day the planner may use. */
fun AppGraph.leaveToday(): LocalDate {
    val zone = FoundationCompat.javaZone(settings.preferences.value.recordsTimeZoneIdentifier)
    return Instant.ofEpochMilli(nowMs().toLong()).atZone(zone).toLocalDate()
}
