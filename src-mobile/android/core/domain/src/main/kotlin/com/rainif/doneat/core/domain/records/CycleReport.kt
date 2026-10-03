package com.rainif.doneat.core.domain.records

import java.net.URI
import java.net.URLEncoder
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/** A civil period remains stable when a notification is opened after travel or days later. */
enum class CycleReportKind(val raw: String) { WEEK("week"), MONTH("month"), YEAR("year") }
data class CycleReportPeriod(val kind: CycleReportKind, val startDayKey: String, val endDayKey: String, val timeZoneIdentifier: String) {
    val startDate: LocalDate get() = LocalDate.parse(startDayKey)
    val endDate: LocalDate get() = LocalDate.parse(endDayKey)
    val zone: ZoneId get() = ZoneId.of(timeZoneIdentifier)
    val dayKeys: List<String> get() {
        val maximum = when (kind) { CycleReportKind.WEEK -> 7L; CycleReportKind.MONTH -> 31L; CycleReportKind.YEAR -> 366L }
        val span = java.time.temporal.ChronoUnit.DAYS.between(startDate, endDate) + 1
        if (span !in 1L..maximum) return emptyList()
        return generateSequence(startDate) { it.plusDays(1) }.take(span.toInt()).map { it.toString() }.toList()
    }
    val notificationIdentifier get() = PREFIX + kind.raw + "." + startDayKey
    val notificationAtMs get() = endDate.plusDays(1).atTime(9, 0).atZone(zone).toInstant().toEpochMilli()
    fun isComplete(nowMs: Double) = Instant.ofEpochMilli(nowMs.toLong()).atZone(zone).toLocalDate() > endDate
    fun referenceDate(nowMs: Double) = minOf(Instant.ofEpochMilli(nowMs.toLong()).atZone(zone).toLocalDate(), endDate)
    fun neighbour(by: Long, firstDayOfWeek: DayOfWeek = DayOfWeek.MONDAY): CycleReportPeriod {
        if (kind == CycleReportKind.WEEK) return copy(startDayKey = startDate.plusWeeks(by).toString(), endDayKey = endDate.plusWeeks(by).toString())
        return containing(when (kind) {
        CycleReportKind.WEEK -> startDate.plusWeeks(by)
        CycleReportKind.MONTH -> startDate.plusMonths(by)
        CycleReportKind.YEAR -> startDate.plusYears(by)
    }, kind, zone, firstDayOfWeek)
    }
    val url: String get() {
        fun encode(s: String) = URLEncoder.encode(s, StandardCharsets.UTF_8.name())
        return "doneat://report?kind=${kind.raw}&start=$startDayKey&end=$endDayKey&tz=${encode(timeZoneIdentifier)}"
    }
    companion object {
        const val PREFIX = "owc.report."
        fun containing(date: LocalDate, kind: CycleReportKind, zone: ZoneId, firstDayOfWeek: DayOfWeek = DayOfWeek.MONDAY): CycleReportPeriod {
            val start = when (kind) {
                CycleReportKind.WEEK -> date.with(TemporalAdjusters.previousOrSame(firstDayOfWeek))
                CycleReportKind.MONTH -> date.withDayOfMonth(1)
                CycleReportKind.YEAR -> date.withDayOfYear(1)
            }
            val end = when (kind) {
                CycleReportKind.WEEK -> start.plusDays(6)
                CycleReportKind.MONTH -> start.plusMonths(1).minusDays(1)
                CycleReportKind.YEAR -> start.plusYears(1).minusDays(1)
            }
            return CycleReportPeriod(kind, start.toString(), end.toString(), zone.id)
        }
        fun fromUrl(value: String): CycleReportPeriod? = runCatching {
            val uri = URI(value)
            require(uri.scheme == "doneat" && uri.host == "report")
            val queryItems = uri.rawQuery.split('&')
            require(queryItems.size == 4)
            val parts = queryItems.associate { item ->
                val pair = item.split('=', limit = 2)
                require(pair.size == 2)
                pair[0] to URLDecoder.decode(pair[1], StandardCharsets.UTF_8.name())
            }
            require(parts.keys == setOf("kind", "start", "end", "tz"))
            val kind = CycleReportKind.entries.first { it.raw == parts["kind"] }
            val report = CycleReportPeriod(kind, parts.getValue("start"), parts.getValue("end"), parts.getValue("tz"))
            require(report.startDayKey.matches(Regex("\\d{4}-\\d{2}-\\d{2}")) && report.endDayKey.matches(Regex("\\d{4}-\\d{2}-\\d{2}")))
            val span = java.time.temporal.ChronoUnit.DAYS.between(report.startDate, report.endDate) + 1
            require(when (kind) {
                CycleReportKind.WEEK -> span == 7L
                else -> report == containing(report.startDate, kind, report.zone)
            })
            report.zone
            report
        }.getOrNull()
    }
}

data class CycleReportFigures(val workdays: Int = 0, val workedMs: Long = 0, val overtimeMs: Long = 0, val income: Double? = null) {
    val hasData get() = workdays > 0 || workedMs > 0
    companion object {
        fun fromHeadline(h: RecordsHeadlineSummary?): CycleReportFigures {
            if (h == null) return CycleReportFigures()
            val actual = h.actualForecast
            return if (actual != null) CycleReportFigures(actual.actual.days.toInt(), kotlin.math.round(actual.actual.hours * 3_600_000).toLong(), kotlin.math.round(actual.actualOvertimeHours * 3_600_000).toLong(), actual.actual.earnings)
            else CycleReportFigures(h.workdays, h.regularWorkMs + h.overtimeMs, h.overtimeMs, h.estimatedIncome)
        }
    }
}
enum class CycleReportDayKind { WORK, REST, UPCOMING, UNKNOWN }
data class CycleReportDay(val dayKey: String, val date: LocalDate, val kind: CycleReportDayKind, val workMs: Long, val overtimeMs: Long, val isToday: Boolean)
data class CycleReportBaseline(val periods: Int, val baselineWorkedMs: Long, val deltaMs: Long) { val deltaFraction get() = if (baselineWorkedMs > 0) deltaMs.toDouble() / baselineWorkedMs else 0.0 }
data class CycleReportOvertime(val days: List<CycleReportDay>, val dayCount: Int, val longestDay: CycleReportDay)
data class CycleReportNextBreak(val startDayKey: String, val startDate: LocalDate, val length: Int, val daysAway: Int) { val endDate get() = startDate.plusDays(length.toLong() - 1) }
data class CycleReportAhead(val leaveUsedHalfDays: Int, val leaveRemainingHalfDays: Int?, val leaveEntitledHalfDays: Int?, val nextBreak: CycleReportNextBreak?, val horizon: List<Boolean>, val isHistorical: Boolean)
data class CycleReportFocus(val rounds: Int, val focusedMs: Long, val perDay: List<Int>, val bestDayIndex: Int, val topIcon: FocusTaskIcon?)
data class CycleReportPay(val total: Double, val perHour: Double?, val overtimeExtra: Double?)
data class CycleReportMonth(val period: CycleReportPeriod, val figures: CycleReportFigures, val restDayCount: Int, val focusRounds: Int)
data class CycleReportSnapshot(
    val period: CycleReportPeriod, val days: List<CycleReportDay>, val figures: CycleReportFigures,
    val restDayCount: Int, val longestRestRun: Int, val longestRestStart: Int?, val isInProgress: Boolean,
    val baseline: CycleReportBaseline? = null, val overtime: CycleReportOvertime? = null,
    val ahead: CycleReportAhead? = null, val focus: CycleReportFocus? = null, val pay: CycleReportPay? = null,
    val months: List<CycleReportMonth> = emptyList(), val leaveUsedHalfDays: Int = 0,
) {
    val hasData get() = figures.hasData || (period.kind == CycleReportKind.YEAR && ((focus?.rounds ?: 0) > 0 || leaveUsedHalfDays > 0))
    val income get() = figures.income
    fun withoutIncome() = copy(figures = figures.copy(income = null), pay = null, months = months.map { it.copy(figures = it.figures.copy(income = null)) })
}

object CycleReportNotificationPlan {
    /** Android keeps its own absolute registrations; there is no iOS pending-notification slot budget. */
    fun items(weekly: Boolean, monthly: Boolean, yearly: Boolean, nowMs: Double, zone: ZoneId, firstDayOfWeek: DayOfWeek): List<CycleReportPeriod> {
        val today = Instant.ofEpochMilli(nowMs.toLong()).atZone(zone).toLocalDate()
        return listOf(CycleReportKind.WEEK to weekly, CycleReportKind.MONTH to monthly, CycleReportKind.YEAR to yearly)
            .filter { it.second }.map { (kind, _) ->
                val current = CycleReportPeriod.containing(today, kind, zone, firstDayOfWeek)
                val previous = current.neighbour(-1, firstDayOfWeek)
                // Reopening on the first day before 09:00 retains the report just completed.
                if (previous.notificationAtMs > nowMs) previous else current
            }.sortedBy { it.notificationAtMs }
    }
}
