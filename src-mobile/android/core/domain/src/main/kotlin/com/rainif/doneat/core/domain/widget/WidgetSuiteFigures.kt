package com.rainif.doneat.core.domain.widget

import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import kotlin.math.floor

/** The iOS WeekProgress value, computed only from already resolved work segments. */
data class WidgetWeekProgress(
    val days: List<WidgetCalendarDay>, val totalMs: Long, val remainingMs: Long,
    val remainingDays: Double, val finishMs: Long?, val isBigWeek: Boolean,
) {
    val progress get() = if (totalMs > 0) 1 - remainingMs.toDouble() / totalMs else 0.0
    fun fill(day: WidgetCalendarDay, nowMs: Long) = if (day.isWork && day.workMs > 0) 1 - day.remainingMs(nowMs).toDouble() / day.workMs else 0.0
    companion object {
        fun from(payload: WidgetCalendarPayload, nowMs: Long): WidgetWeekProgress {
            val days = payload.week(nowMs)
            val work = days.filter { it.isWork }
            val zone = ZoneId.of(payload.timeZoneIdentifier)
            return WidgetWeekProgress(days, work.sumOf { it.workMs }, work.sumOf { it.remainingMs(nowMs) },
                work.sumOf { if (it.workMs > 0) it.remainingMs(nowMs).toDouble() / it.workMs else 0.0 }, work.lastOrNull()?.endAtMs,
                work.any { Instant.ofEpochMilli(it.startMs).atZone(zone).dayOfWeek in setOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY) })
        }
    }
}

fun WidgetCalendarPayload.weekProgress(nowMs: Long): Double = WidgetWeekProgress.from(this, nowMs).progress

data class WidgetRotationOutlook(val days: List<WidgetCalendarDay>, val workdaysBeforeRest: Int, val nextRest: WidgetCalendarDay?, val today: WidgetCalendarDay?) {
    companion object {
        fun from(payload: WidgetCalendarPayload, nowMs: Long, count: Int = 14): WidgetRotationOutlook {
            val today = payload.day(nowMs)
            val index = payload.days.indexOf(today).coerceAtLeast(0)
            val days = payload.days.drop(index).take(count)
            val before = days.takeWhile { it.isWork }
            return WidgetRotationOutlook(days, before.count { it.remainingMs(nowMs) > 0 }, days.firstOrNull { !it.isWork }, days.firstOrNull())
        }
    }
}

/** Calendar progress measures actual local intervals, including 23/25-hour DST days. */
data class WidgetCalendarProgress(val today: Double, val week: Double, val month: Double, val year: Double, val daysLeftInYear: Int) {
    companion object {
        fun at(nowMs: Long, zone: ZoneId, firstDayOfWeek: DayOfWeek): WidgetCalendarProgress {
            val date = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
            fun share(start: java.time.LocalDate, end: java.time.LocalDate): Double {
                val lower = start.atStartOfDay(zone).toInstant().toEpochMilli()
                val upper = end.atStartOfDay(zone).toInstant().toEpochMilli()
                return ((nowMs - lower).toDouble() / (upper - lower)).coerceIn(0.0, 1.0)
            }
            val week = date.with(TemporalAdjusters.previousOrSame(firstDayOfWeek))
            val month = date.withDayOfMonth(1)
            val year = date.withDayOfYear(1)
            return WidgetCalendarProgress(share(date, date.plusDays(1)), share(week, week.plusWeeks(1)), share(month, month.plusMonths(1)),
                share(year, year.plusYears(1)), ChronoUnit.DAYS.between(date, year.plusYears(1)).toInt().coerceAtLeast(0))
        }
    }
}

/** Exact scalar port of iOS LifeFigures (365.2425 days/year and 30.436875 days/month). */
data class WidgetLifeFigures(
    val daysLived: Long, val lifeShare: Double, val careerShare: Double?,
    val monthsWorked: Int?, val monthsToRetirement: Int?, val ageMonths: Int,
) {
    companion object {
        fun from(payload: WidgetLifePayload, nowMs: Long, zone: ZoneId): WidgetLifeFigures? {
            if (!payload.access.isUnlocked(nowMs)) return null
            val born = payload.bornDay ?: return null
            val midnight = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()
            val today = floor(midnight / 86_400_000.0 + 0.5).toLong()
            val days = maxOf(0, today - born)
            val start = payload.careerStartDay
            val end = payload.retirementDay
            val career = if (start != null && end != null && end > start) ((today - start).toDouble() / (end - start)).coerceIn(0.0, 1.0) else null
            return WidgetLifeFigures(days, minOf(1.0, days / (payload.lifeYears * 365.2425)), career,
                if (career != null) (maxOf(0, today - start!!) / 30.436875).toInt() else null,
                end?.let { (maxOf(0, it - today) / 30.436875).toInt() }, (days / 30.436875).toInt())
        }
    }
}
