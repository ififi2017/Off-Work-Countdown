package com.rainif.doneat.ui.records

import android.content.Context
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.ui.timer.TimerText
import com.rainif.doneat.ui.focus.title
import kotlin.math.abs
import kotlin.math.roundToInt

internal enum class ReportArtKind { TIME, OVERTIME, REST, FOCUS, BASELINE, PAY, AHEAD, SUMMARY }

/** Prepared labels and draw values; no calendar, record query or aggregate runs on a frame. */
internal data class ReportChapter(
    val stage: ReportStage,
    val title: String,
    val metric: String,
    val lines: List<String> = emptyList(),
    val bars: List<Pair<String, Long>> = emptyList(),
    val restRange: IntRange? = null,
    val calendarLeading: Int = 0,
    val cellLabels: List<String> = emptyList(),
    val artKind: ReportArtKind = ReportArtKind.TIME,
    val isYear: Boolean = false,
    val isWeek: Boolean = false,
    val restIndices: Set<Int> = emptySet(),
    val upcomingIndices: Set<Int> = emptySet(),
    val axisLabels: List<String> = emptyList(),
    val valueLabels: List<String> = emptyList(),
    val overtimeShares: List<Float> = emptyList(),
    val centerLabel: String? = null,
    val centerValue: String? = null,
    val incomeShare: Float = 0f,
    val leaveShare: Float? = null,
    val highlightedIndex: Int? = null,
    val countedMetric: ((Float) -> String)? = null,
    val summaryFacts: List<Pair<String, String>> = emptyList(),
) {
    val timeline get() = stage.timeline(isWeek)
}

internal class ReportCopy(val report: CycleReportSnapshot, val text: TimerText, val dates: RecordsText, context: Context) {
    private val res = context.resources
    fun t(id: Int) = res.getString(id)
    fun f(id: Int, vararg values: String) = res.getString(id, *values)
    fun duration(ms: Long) = text.relativeDuration(ms.toDouble())
    val year = report.period.kind == CycleReportKind.YEAR
    val week = report.period.kind == CycleReportKind.WEEK
    val periodTitle get() = when {
        year -> java.text.NumberFormat.getIntegerInstance(text.locale).apply { isGroupingUsed = false }.format(report.period.startDate.year)
        week -> dates.monthDay(report.period.startDate) + " – " + dates.monthDay(report.period.endDate)
        else -> dates.monthYear(report.period.startDate)
    }
    val headline: String get() = when (report.headline) {
        CycleReportHeadline.IN_PROGRESS -> t(R.string.reportHeadlineInProgress)
        CycleReportHeadline.PLAIN -> t(R.string.reportHeadlinePlain)
        CycleReportHeadline.STEADY -> t(R.string.reportHeadlineSteady)
        CycleReportHeadline.BREAK_SOON -> t(R.string.reportHeadlineSprint)
        CycleReportHeadline.REST -> f(R.string.reportHeadlineRoom, text.count(report.restDayCount))
        CycleReportHeadline.LIGHTER -> f(R.string.reportHeadlineLighter, duration(abs(report.baseline?.deltaMs ?: 0)))
        CycleReportHeadline.FULL -> report.baseline?.takeIf { it.deltaMs > 0 }?.let { f(R.string.reportHeadlineFull, duration(it.deltaMs)) }
            ?: f(R.string.reportHeadlineOvertime, duration(report.figures.overtimeMs))
    }
    val baselineTitle get() = if (report.baseline?.periods == 1) t(if (week) R.string.reportCompareWeek else R.string.reportCompareMonth)
        else f(if (week) R.string.reportUsualBasisWeek else R.string.reportUsualBasisMonth, text.count(report.baseline?.periods ?: 0))
    val baselineLabel get() = if (report.baseline?.periods == 1) report.period.neighbour(-1).let {
        if (week) dates.monthDay(it.startDate) + " – " + dates.monthDay(it.endDate) else dates.monthYear(it.startDate)
    } else t(if (week) R.string.reportUsualWeek else R.string.reportUsualMonth)
    val baselineSentence: String get() {
        val delta = report.baseline?.deltaMs ?: 0
        val previous = report.baseline?.periods == 1
        return f(when {
            abs(delta) < 60_000 -> if (previous) R.string.reportCompareSame else R.string.reportUsualSame
            delta > 0 -> if (previous) R.string.reportCompareMore else R.string.reportUsualMore
            else -> if (previous) R.string.reportCompareLess else R.string.reportUsualLess
        }, duration(abs(delta)))
    }
    fun aheadTitle(ahead: CycleReportAhead) = t(when {
        ahead.nextBreak != null -> if (ahead.isHistorical) R.string.reportAheadHistoricalTitle else R.string.reportAheadTitle
        ahead.leaveRemainingHalfDays != null -> R.string.reportLeaveLeft
        else -> R.string.reportLeaveUsed
    })
    fun aheadHero(ahead: CycleReportAhead): String = ahead.nextBreak?.let { next ->
        if (ahead.isHistorical) text.days(next.length.toDouble())
        else if (next.daysAway == 1) t(R.string.reportAheadTomorrow)
        else f(R.string.reportAheadInDays, text.days(next.daysAway.toDouble()))
    } ?: text.days((ahead.leaveRemainingHalfDays ?: ahead.leaveUsedHalfDays) / 2.0)
    fun aheadDetail(ahead: CycleReportAhead) = ahead.nextBreak?.let { next ->
        if (ahead.isHistorical) dates.monthDay(next.startDate) + " – " + dates.monthDay(next.endDate)
        else f(R.string.reportAheadBreak, text.days(next.length.toDouble()), dates.monthDay(next.startDate))
    }
    fun facts(): List<Pair<String, String>> = buildList {
        add(t(R.string.reportWorkdays) to text.count(report.figures.workdays))
        add(t(R.string.recordsWorkedTime) to duration(report.figures.workedMs))
        if (report.figures.overtimeMs > 0) add(t(R.string.recordsOvertime) to duration(report.figures.overtimeMs))
        add(t(R.string.reportRestDays) to text.days(report.restDayCount.toDouble()))
        if (report.longestRestRun > 0) add(t(R.string.reportLongestRest) to text.days(report.longestRestRun.toDouble()))
        if (report.baseline != null) add(baselineTitle to baselineSentence)
        report.ahead?.let { ahead ->
            aheadDetail(ahead)?.let { add(aheadTitle(ahead) to (if (ahead.isHistorical) aheadHero(ahead) + " · " + it else it)) }
            ahead.leaveRemainingHalfDays?.let { add(t(R.string.reportLeaveLeft) to text.days(it / 2.0)) }
            if (ahead.leaveUsedHalfDays > 0) add(t(R.string.reportLeaveUsed) to text.days(ahead.leaveUsedHalfDays / 2.0))
        }
        if (year) add(t(R.string.reportLeaveUsed) to text.days(report.leaveUsedHalfDays / 2.0))
        report.focus?.let { add(t(R.string.reportFocusRounds) to text.count(it.rounds)); add(t(R.string.reportFocusDuration) to duration(it.focusedMs)) }
        report.pay?.let { pay ->
            add(t(R.string.reportIncomeTitle) to text.money(pay.total))
            pay.perHour?.let { add(t(R.string.reportPerHour) to text.money(it)) }
            pay.overtimeExtra?.let { add(t(R.string.reportIncomeExtra) to text.money(it)) }
        }
    }
}

internal fun reportChapters(report: CycleReportSnapshot, text: TimerText, dates: RecordsText, context: Context, firstDayOfWeek: java.time.DayOfWeek): List<ReportChapter> {
    val c = ReportCopy(report, text, dates, context)
    with(c) {
        val calendarLeading = if (week) 0 else (report.period.startDate.dayOfWeek.value - firstDayOfWeek.value + 7) % 7
        val cells = report.days.map { text.count(it.date.dayOfMonth) }
        val rest = report.days.mapIndexedNotNull { i, day -> i.takeIf { day.kind == CycleReportDayKind.REST } }.toSet()
        val upcoming = report.days.mapIndexedNotNull { i, day -> i.takeIf { day.kind == CycleReportDayKind.UPCOMING || day.kind == CycleReportDayKind.UNKNOWN } }.toSet()
        val share = report.days.map { val total = it.workMs + it.overtimeMs; if (total > 0) it.overtimeMs.toFloat() / total else 0f }
        val axis = if (year) report.months.map { text.count(it.period.startDate.monthValue) } else if (week) report.days.map { dates.weekdayNarrow(it.date) } else emptyList()
        val work = if (year) report.months.map { dates.shortMonth(it.period.startDate) to it.figures.workedMs }
            else report.days.map { dates.dayTitle(it.dayKey) to it.workMs + it.overtimeMs }
        val strip = ReportChapter(ReportStage.CALENDAR, f(R.string.recordsWorkdayCount, text.count(report.figures.workdays)), headline,
            if (report.isInProgress) listOf(t(R.string.reportSoFar)) else emptyList(), work,
            restRange = report.longestRestStart?.let { it until it + report.longestRestRun }, calendarLeading = calendarLeading,
            cellLabels = cells, isYear = year, isWeek = week, restIndices = rest, upcomingIndices = upcoming, axisLabels = axis,
            valueLabels = work.map { java.text.NumberFormat.getNumberInstance(text.locale).apply { maximumFractionDigits = 1 }.format(it.second / 3_600_000.0) }, overtimeShares = share)
        val all = mutableListOf(strip, strip.copy(stage = ReportStage.HOURS, title = t(R.string.recordsWorkedTime), metric = duration(report.figures.workedMs),
            lines = if (report.figures.overtimeMs > 0) listOf(f(R.string.reportIncludingOvertime, duration(report.figures.overtimeMs))) else emptyList(),
            countedMetric = { duration((report.figures.workedMs * it).toLong()) }))
        if (report.figures.overtimeMs > 0) {
            val overtime = report.overtime
            val days = overtime?.days ?: report.days.filter { it.kind != CycleReportDayKind.UPCOMING }
            all += ReportChapter(ReportStage.OVERTIME, t(R.string.recordsOvertime), duration(report.figures.overtimeMs),
                overtime?.let { listOf(f(R.string.reportOvertimeDays, text.count(it.dayCount)), f(R.string.reportOvertimePeak,
                    if (week) dates.weekdayNarrow(it.longestDay.date) else dates.monthDay(it.longestDay.date), duration(it.longestDay.overtimeMs))) }.orEmpty(),
                if (year) report.months.map { dates.shortMonth(it.period.startDate) to it.figures.overtimeMs } else days.map { dates.dayTitle(it.dayKey) to it.overtimeMs },
                artKind = ReportArtKind.OVERTIME, isYear = year, isWeek = week,
                axisLabels = if (year || week) axis else days.mapIndexed { i, day -> if (i == 0 || i == days.lastIndex || (i + 1) % 5 == 0) text.count(day.date.dayOfMonth) else "" },
                countedMetric = { duration((report.figures.overtimeMs * it).toLong()) })
        }
        report.baseline?.let { b ->
            all += ReportChapter(ReportStage.BASELINE, baselineTitle, if (abs(b.deltaMs) >= 60_000) duration(abs(b.deltaMs)) else baselineSentence,
                if (abs(b.deltaMs) >= 60_000) listOf(baselineSentence) else emptyList(),
                listOf(baselineLabel + " · " + duration(b.baselineWorkedMs) to b.baselineWorkedMs, periodTitle + " · " + duration(report.figures.workedMs) to report.figures.workedMs), artKind = ReportArtKind.BASELINE)
        }
        all += strip.copy(stage = ReportStage.REST, title = t(R.string.reportRestDays), metric = if (report.restDayCount > 0) text.count(report.restDayCount) else t(R.string.reportRestNone),
            lines = buildList {
                if (report.longestRestRun > 0) add(t(R.string.reportLongestRest) + " · " + text.days(report.longestRestRun.toDouble()))
                report.longestRestStart?.let { add(dates.monthDay(report.days[it].date) + " – " + dates.monthDay(report.days[it + report.longestRestRun - 1].date)) }
                if (year) add(t(R.string.reportLeaveUsed) + " · " + text.days(report.leaveUsedHalfDays / 2.0))
            }, bars = if (year) report.months.map { dates.shortMonth(it.period.startDate) to it.restDayCount.toLong() } else work, artKind = ReportArtKind.REST,
            countedMetric = if (report.restDayCount > 0) ({ text.count((report.restDayCount * it).roundToInt()) }) else null)
        report.ahead?.let { a ->
            all += ReportChapter(ReportStage.AHEAD, aheadTitle(a), aheadHero(a), buildList {
                aheadDetail(a)?.let(::add)
                if (a.nextBreak != null) a.leaveRemainingHalfDays?.let { add(t(R.string.reportLeaveLeft) + " · " + text.days(it / 2.0)) }
                if (a.leaveUsedHalfDays > 0 && (a.nextBreak != null || a.leaveRemainingHalfDays != null)) add(t(R.string.reportLeaveUsed) + " · " + text.days(a.leaveUsedHalfDays / 2.0))
            }, bars = if (a.nextBreak != null) a.horizon.map { "" to if (it) 1L else 0L } else emptyList(), artKind = ReportArtKind.AHEAD,
                restRange = a.nextBreak?.let { (it.daysAway - 1) until (it.daysAway - 1 + it.length) },
                leaveShare = a.leaveEntitledHalfDays?.takeIf { it > 0 }?.let { (a.leaveRemainingHalfDays ?: 0).toFloat() / it })
        }
        report.focus?.let { f ->
            all += ReportChapter(ReportStage.FOCUS, t(R.string.reportFocusRounds), text.count(f.rounds), buildList {
                if (f.bestDayIndex in report.days.indices) add(c.f(R.string.reportFocusBest, dates.monthDay(report.days[f.bestDayIndex].date), text.count(f.perDay[f.bestDayIndex])))
                add(t(R.string.reportFocusDuration) + " · " + duration(f.focusedMs))
                f.topIcon?.let { add(t(R.string.reportFocusTop) + " · " + t(it.title)) }
            }, if (year) report.months.map { dates.shortMonth(it.period.startDate) to it.focusRounds.toLong() }
                else report.days.mapIndexed { i, day -> dates.dayTitle(day.dayKey) to f.perDay[i].toLong() },
                artKind = ReportArtKind.FOCUS, isYear = year, isWeek = week, axisLabels = axis, highlightedIndex = if (year) null else f.bestDayIndex, valueLabels = f.perDay.map(text::count),
                countedMetric = { text.count((f.rounds * it).roundToInt()) })
        }
        report.pay?.let { pay ->
            all += ReportChapter(ReportStage.INCOME, t(R.string.reportIncomeTitle), "", buildList {
                add(t(R.string.reportIncomeTotal) + " · " + text.money(pay.total))
                pay.overtimeExtra?.let { add(t(R.string.reportIncomeExtra) + " · " + text.money(it)) }
                add(t(R.string.reportIncomeNote))
            }, artKind = ReportArtKind.PAY, centerLabel = t(if (pay.perHour != null) R.string.reportPerHour else R.string.reportIncomeTitle),
                centerValue = text.money(pay.perHour ?: pay.total), incomeShare = ((pay.overtimeExtra ?: 0.0) / pay.total.coerceAtLeast(.01)).toFloat(),
                countedMetric = { text.money((pay.perHour ?: pay.total) * it) })
        }
        val summaryFacts = buildList {
            add(t(R.string.reportWorkdays) to text.count(report.figures.workdays))
            add(t(R.string.reportRestDays) to text.count(report.restDayCount))
            if (report.pay != null) add(t(R.string.reportIncomeTitle) to text.money(requireNotNull(report.pay).total))
            else if (report.figures.overtimeMs > 0) add(t(R.string.recordsOvertime) to duration(report.figures.overtimeMs))
            else if (report.longestRestRun > 0) add(t(R.string.reportLongestRest) to text.days(report.longestRestRun.toDouble()))
        }
        all += strip.copy(stage = ReportStage.SUMMARY, title = if (report.isInProgress) t(R.string.reportSoFar) else periodTitle,
            metric = headline, lines = emptyList(), artKind = ReportArtKind.SUMMARY, centerLabel = t(R.string.recordsWorkedTime),
            centerValue = duration(report.figures.workedMs), summaryFacts = summaryFacts)
        return ReportStage.stages(report).mapNotNull { stage -> all.firstOrNull { it.stage == stage } }
    }
}
