package com.rainif.doneat.core.domain.records

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** 3.2.2 drawing vocabulary. Consumes query results; never expands a shift or a salary. */
data class RecordsDayLook(val cell: RecordsDayCell) {
    val isLocked get() = cell.appearance == RecordsDayAppearance.LOCKED
    val totalMs get() = if (isLocked) 0L else cell.workMs.coerceAtLeast(0) + cell.overtimeMs.coerceAtLeast(0)
    val isEstimated get() = !isLocked && totalMs > 0 &&
        (RecordsDayMarks.isEstimated(cell) || cell.isToday && cell.isFromSavedSchedule)
    val hasSolidHours get() = !isLocked && !isEstimated && totalMs > 0 &&
        cell.appearance in listOf(RecordsDayAppearance.RECORDED, RecordsDayAppearance.CORRECTED)
    val hasHours get() = hasSolidHours || isEstimated
    val isUnrecordedWorkday get() = !isLocked && cell.appearance == RecordsDayAppearance.UNRECORDED && !cell.isFuture
    val hasConflict get() = !isLocked && cell.hasConflict
}

data class RecordsHolidayRun(val start: Int, val length: Int, val name: String)

/** One name per uninterrupted run within one calendar week; nulls break a run. */
fun recordsHolidayRuns(names: List<String?>): List<RecordsHolidayRun> {
    val result = mutableListOf<RecordsHolidayRun>()
    var index = 0
    while (index < names.size) {
        val name = names[index]
        if (name.isNullOrEmpty()) { index++; continue }
        var length = 1
        while (index + length < names.size && names[index + length] == name) length++
        result += RecordsHolidayRun(index, length, name)
        index += length
    }
    return result
}

data class RecordsLifeYear(val age: Int, val year: Int, val middleMs: Double, val stage: LifeStageSpan?, val isPast: Boolean, val isCurrent: Boolean)

/** One cell per civil year of age, with at least eight decades, including open-ended retirement. */
fun recordsLifeYears(stages: List<LifeStageSpan>, bounds: Pair<Double, Double>, referenceMs: Double, zone: ZoneId): List<RecordsLifeYear> {
    fun day(ms: Double) = Instant.ofEpochMilli(ms.toLong()).atZone(zone).toLocalDate()
    val birth = day(bounds.first)
    val currentAge = ChronoUnit.YEARS.between(birth, day(referenceMs)).toInt().coerceAtLeast(0)
    val span = ChronoUnit.YEARS.between(birth, day(bounds.second)).toInt().coerceAtLeast(1)
    val coveredYears = maxOf(span, currentAge + 1)
    val count = maxOf(80, ((coveredYears + 9) / 10) * 10)
    return (0 until count).map { age ->
        val start = birth.plusYears(age.toLong())
        val middle = LifeDates.ms(start.plusMonths(6), zone)
        RecordsLifeYear(age, start.year, middle, LifeStageCalculator.stageAt(middle, stages), age < currentAge, age == currentAge)
    }
}

data class RecordsInsightMetrics(
    val workedMs: Double, val overtimeMs: Double, val plannedDays: Int, val plannedMs: Double,
    val recordedDays: Int, val completedWorkdays: Int, val extraWorkdays: Double, val emptyDay: LocalDate?,
)

/** A projection of finished totals for copy; formulas for hours and earnings stay in RecordsQueries. */
fun recordsInsightMetrics(summary: RecordsHeadlineSummary, cells: List<RecordsDayCell>, scale: RecordsScale): RecordsInsightMetrics {
    val forecast = summary.actualForecast
    val solid = cells.map(::RecordsDayLook).filter { it.hasSolidHours }
    val overtime = forecast?.let { it.actualOvertimeHours * 3_600_000 } ?: summary.overtimeMs.toDouble()
    val averageDay = if (summary.workdays > 0) summary.regularWorkMs.toDouble() / summary.workdays else 8 * 3_600_000.0
    return RecordsInsightMetrics(
        forecast?.actual?.let { it.hours * 3_600_000 } ?: (summary.regularWorkMs + summary.overtimeMs).toDouble(),
        overtime, kotlin.math.round(forecast?.forecast?.days ?: 0.0).toInt(), (forecast?.forecast?.hours ?: 0.0) * 3_600_000,
        if (scale == RecordsScale.WEEK) solid.size else summary.workdays,
        maxOf(summary.completedScheduledWorkdays, solid.size), if (averageDay > 0) overtime / averageDay else 0.0,
        cells.firstOrNull { RecordsDayLook(it).isUnrecordedWorkday && !it.isToday }?.date,
    )
}
