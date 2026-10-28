package com.rainif.doneat.core.domain.widget

import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.core.domain.schedule.*
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.rotationCycleDay
import java.text.NumberFormat
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.floor

/** The iOS 3.2.3 composer: reuse Records' resolution/reports, never schedule inside a widget. */
object WidgetSuiteComposer {
    fun compose(
        session: ShiftSession, queries: RecordsQueries, nowMs: Long, locale: String, access: WidgetAccess,
        focusBlocks: List<WidgetFocusBlock> = emptyList(), copy: (String) -> String = { it },
        formatHours: (Double) -> String = { it.toString() },
        weekendDays: Set<DayOfWeek> = setOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY),
    ): WidgetSuiteSnapshot {
        val calendar = calendar(session, queries, nowMs, locale, copy)
        val effectiveAccess = if (access.isUnlocked(nowMs)) access else WidgetAccess.LOCKED
        val live = session.snapshot(nowMs.toDouble())?.takeIf {
            session.shouldQuerySnapshot(nowMs.toDouble()) && (it.isWorkday || session.isForcedWorkday(it))
        }
            ?.segments.orEmpty().map { WidgetTimeSegment(it.startAtMs.toLong(), it.endAtMs.toLong()) }
        return WidgetSuiteSnapshot(
            generatedAtMs = nowMs, locale = locale, timeZoneIdentifier = queries.zone.id,
            calendar = calendar,
            summary = summary(session, queries, calendar, effectiveAccess, nowMs, locale, copy, formatHours),
            life = life(queries.state.lifeProfile, effectiveAccess, session.deviceZone),
            holiday = holiday(session, queries, calendar, effectiveAccess, nowMs, locale, copy, weekendDays),
            focus = WidgetFocusPayload(effectiveAccess, if (effectiveAccess.isUnlocked(nowMs)) focusBlocks.filter { it.endMs > nowMs }.take(6) else emptyList()),
            countdownSegments = live, countdownTimeZoneIdentifier = session.countdownZone.id, lifeTimeZoneIdentifier = session.deviceZone.id,
        ).redacted(nowMs)
    }

    private fun calendar(session: ShiftSession, queries: RecordsQueries, nowMs: Long, locale: String, copy: (String) -> String): WidgetCalendarPayload {
        val today = queries.today(nowMs.toDouble())
        val start = minOf(today.with(TemporalAdjusters.previousOrSame(queries.firstDayOfWeek)), today.withDayOfMonth(1))
        val end = today.withDayOfMonth(1).plusMonths(2).minusDays(1)
        val plan = session.extendedSchedulePlan(nowMs.toDouble())
        val resolver = plan?.let(::ExtendedScheduleResolver)
        val kind = scheduleKind(session, nowMs, plan)
        val region = if (session.env.isExtendedScheduleEnabled) plan?.holidayRegionIdentifier else null
        val leaveKeys = queries.state.leaveDays.map { it.dayKey }.toSet()
        val days = if (kind == WidgetCalendarScheduleKind.NONE) emptyList() else calendarResolutions(session, queries, start, end, nowMs).map { resolution ->
            val date = LocalDate.parse(resolution.dayKey)
            val holiday = annotation(session.env.holidays, region, date, locale)
            val typeID = resolver?.day(date.toEpochDay().toInt())?.shiftTypeID
            val type = plan?.shiftTypes?.firstOrNull { it.id == typeID }
            val segments = resolution.segments.map { WidgetTimeSegment(it.startAtMs.toLong(), it.endAtMs.toLong()) }
            val dayKind = when {
                resolution.dayKey in leaveKeys && segments.isEmpty() -> WidgetCalendarDayKind.LEAVE
                resolution.isScheduledWorkday && segments.isNotEmpty() -> if (holiday?.isMakeupWorkday == true) WidgetCalendarDayKind.MAKEUP_WORK else WidgetCalendarDayKind.WORK
                holiday != null && !holiday.isMakeupWorkday -> WidgetCalendarDayKind.HOLIDAY
                else -> WidgetCalendarDayKind.REST
            }
            val cycle = cycle(session, plan, date, queries.zone)
            WidgetCalendarDay(resolution.dayKey, date.atStartOfDay(queries.zone).toInstant().toEpochMilli(), dayKind,
                title = when (dayKind) {
                    WidgetCalendarDayKind.WORK, WidgetCalendarDayKind.MAKEUP_WORK -> type?.name
                    WidgetCalendarDayKind.HOLIDAY -> holiday?.name
                    WidgetCalendarDayKind.REST -> type?.takeIf { it.kind == ShiftType.Kind.REST }?.name
                    WidgetCalendarDayKind.LEAVE -> null
                },
                colorHex = type?.colorHex?.takeIf { dayKind == WidgetCalendarDayKind.WORK || dayKind == WidgetCalendarDayKind.MAKEUP_WORK },
                segments = segments.takeIf { dayKind == WidgetCalendarDayKind.WORK || dayKind == WidgetCalendarDayKind.MAKEUP_WORK }.orEmpty(),
                cycleDay = cycle?.first, cycleLength = cycle?.second,
            )
        }
        val language = Locale.forLanguageTag(locale)
        return WidgetCalendarPayload(queries.zone.id, queries.firstDayOfWeek.value, kind, days, mapOf(
            "work" to copy("widgetSuiteWork"), "rest" to copy("widgetSuiteRest"), "leave" to copy("widgetSuiteLeave"),
            "makeupWork" to copy("widgetSuiteMakeupWork"), "bigWeek" to copy("widgetSuiteBigWeek"), "smallWeek" to copy("widgetSuiteSmallWeek"),
            "weekdaysShort" to (0L..6L).joinToString("|") { offset ->
                LocalDate.of(2026, 1, 5).with(TemporalAdjusters.previousOrSame(queries.firstDayOfWeek)).plusDays(offset)
                    .format(DateTimeFormatter.ofPattern("EEEEE", language))
            },
        ))
    }

    /**
     * A fresh Android setup can commit preferences before Records has its first
     * period (iOS reconciles it before publication). The calendar still has a
     * real live schedule. Project it transiently through the same expansion and
     * three-layer resolver; never seed Records or replace any archived history.
     */
    private fun calendarResolutions(session: ShiftSession, queries: RecordsQueries, from: LocalDate, through: LocalDate, nowMs: Long): List<DayResolution> {
        val recorded = queries.resolvedDays(from, through)
        if (queries.state.periods.isNotEmpty()) return recorded
        val encoded = ScheduleHoursCodec.encode(session.hoursConfiguration(nowMs.toDouble()))
        val period = CareerPeriod("widget-live-preview", from.toString(), null, null, queries.zone.id, "gregorian",
            nowMs.toDouble(), nowMs.toDouble(), 0, "widget-live-preview")
        val snapshot = ScheduleSnapshot("widget-live-preview", period.id, from.toString(), encoded.base64, encoded.fingerprint,
            nowMs.toDouble(), 0, "widget-live-preview")
        val hours = RecordHistory.expandableHours(queries.state, snapshot, session.env.holidays) ?: return recorded
        val expanded = ScheduleRules.expandScheduleRange(hours,
            from.atStartOfDay(queries.zone).toInstant().toEpochMilli().toDouble(),
            through.atStartOfDay(queries.zone).toInstant().toEpochMilli().toDouble(), queries.zone).associateBy { it.dayKey }
        val lookup = DayRecordLookup(queries.state.exceptions, queries.state.overrides, queries.state.leaveDays)
        return recorded.map { day ->
            val base = expanded[day.dayKey] ?: return@map day
            DayRecordResolver.resolve(day.dayKey, period, snapshot, lookup, ScheduleExpansion(base.isWorkday, base.segments))
        }
    }

    private fun scheduleKind(session: ShiftSession, nowMs: Long, plan: ExtendedSchedulePlan?): WidgetCalendarScheduleKind {
        if (!session.followsSchedule(nowMs.toDouble())) return WidgetCalendarScheduleKind.NONE
        if (session.env.isExtendedScheduleEnabled && plan?.rule != null) return when (plan.rule.preset) {
            ShiftCycleRule.Preset.WEEKLY -> WidgetCalendarScheduleKind.WEEKLY
            ShiftCycleRule.Preset.ALTERNATING_WEEKS -> WidgetCalendarScheduleKind.ALTERNATING_WEEKS
            ShiftCycleRule.Preset.ROTATION -> WidgetCalendarScheduleKind.ROTATION
            ShiftCycleRule.Preset.CUSTOM -> WidgetCalendarScheduleKind.CUSTOM
        }
        return when (session.scheduleMode) {
            ScheduleMode.CLASSIC -> WidgetCalendarScheduleKind.WEEKLY
            ScheduleMode.ALTERNATING -> WidgetCalendarScheduleKind.ALTERNATING_WEEKS
            ScheduleMode.ROTATION -> WidgetCalendarScheduleKind.ROTATION
            ScheduleMode.OFF -> WidgetCalendarScheduleKind.NONE
        }
    }

    private fun cycle(session: ShiftSession, plan: ExtendedSchedulePlan?, date: LocalDate, zone: ZoneId): Pair<Int, Int>? {
        if (session.env.isExtendedScheduleEnabled && plan != null) {
            val rule = plan.rule ?: return null
            if (rule.preset != ShiftCycleRule.Preset.ROTATION || rule.days.isEmpty()) return null
            val anchor = ExtendedScheduleResolver.dayNumber(rule.anchorDayKey) ?: return null
            return Math.floorMod(date.toEpochDay().toInt() - anchor, rule.days.size) + 1 to rule.days.size
        }
        if (session.scheduleMode != ScheduleMode.ROTATION) return null
        return session.rotationCycleDay(date.atStartOfDay(zone).toInstant().toEpochMilli().toDouble()) to
            (session.env.preferences.rotationWorkDays + session.env.preferences.rotationRestDays)
    }

    private data class Annotation(val name: String, val isMakeupWorkday: Boolean, val isEstimated: Boolean)
    private fun annotation(holidays: HolidayCalendar, region: String?, date: LocalDate, locale: String): Annotation? {
        if (region.isNullOrEmpty()) return null
        val day = holidays.day(date.year * 10_000 + date.monthValue * 100 + date.dayOfMonth, region) ?: return null
        val normalized = locale.replace('_', '-')
        val name = day.names[normalized] ?: day.names[normalized.take(2)] ?: day.names["en"] ?: day.names.toSortedMap().values.firstOrNull().orEmpty()
        return Annotation(name, day.isWorkday, holidays.isEstimated(date.year, region))
    }

    private fun holiday(session: ShiftSession, queries: RecordsQueries, calendar: WidgetCalendarPayload, access: WidgetAccess, nowMs: Long, locale: String, copy: (String) -> String, weekendDays: Set<DayOfWeek>): WidgetHolidayPayload {
        val todayKey = queries.today(nowMs.toDouble()).toString()
        val days = calendar.days
        val todayIndex = days.indexOfFirst { it.dayKey == todayKey }
        val offIndex = if (todayIndex >= 0) (todayIndex until days.size).firstOrNull { !days[it].isWork } else null
        val weekend = offIndex?.let { days.subList(todayIndex, it).lastOrNull { d -> d.isWork }?.endAtMs }?.takeIf { it > nowMs }
        val region = session.extendedSchedulePlan(nowMs.toDouble())?.holidayRegionIdentifier?.takeIf { session.env.isExtendedScheduleEnabled }
        val nextHoliday = nextHoliday(session.env.holidays, region, queries.today(nowMs.toDouble()), queries.zone, locale, weekendDays)
        val nextLeave = if (access.isUnlocked(nowMs)) nextLeave(queries.state.leaveDays, days, todayKey) else null
        val remaining = if (access.isUnlocked(nowMs)) queries.state.leaveBalances
            .filter { it.isValid && (it.validThroughDayKey == null || it.validThroughDayKey >= todayKey) }
            .takeIf { it.isNotEmpty() }?.sumOf { it.remainingHalfDays }?.div(2.0) else null
        val weekly = calendar.scheduleKind == WidgetCalendarScheduleKind.WEEKLY || calendar.scheduleKind == WidgetCalendarScheduleKind.ALTERNATING_WEEKS
        return WidgetHolidayPayload(access, weekend, nextHoliday, nextLeave, remaining, mapOf(
            "untilRest" to copy(if (weekly) "widgetSuiteUntilWeekend" else "widgetSuiteUntilRestDay"),
            "remaining" to (remaining?.let { interpolate(copy("widgetSuiteLeaveRemaining"), "days" to days(it, locale, copy)) } ?: ""),
            "requested" to (nextLeave?.let { interpolate(copy("widgetSuiteLeavePlan"), "leave" to days(it.requestedDays, locale, copy), "total" to days(it.totalDays.toDouble(), locale, copy)) } ?: ""),
            "holidayDays" to (nextHoliday?.let { days(it.days.toDouble(), locale, copy) } ?: ""),
            "holidayDate" to (nextHoliday?.let { LocalDate.parse(it.startDayKey).format(DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM).withLocale(Locale.forLanguageTag(locale))) } ?: ""),
        ))
    }

    /** Only bundled named holidays; attach adjoining weekends without inventing dates beyond coverage. */
    internal fun nextHoliday(
        holidays: HolidayCalendar, region: String?, today: LocalDate, zone: ZoneId, locale: String,
        weekendDays: Set<DayOfWeek> = setOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY),
    ): WidgetHoliday? {
        if (region.isNullOrEmpty()) return null
        fun weekend(date: LocalDate) = date.dayOfWeek in weekendDays
        for (offset in 0L until 400L) {
            val date = today.plusDays(offset)
            val first = annotation(holidays, region, date, locale)?.takeUnless { it.isMakeupWorkday } ?: continue
            var start = date
            while (start > today && weekend(start.minusDays(1)) && annotation(holidays, region, start.minusDays(1), locale)?.isMakeupWorkday != true) start = start.minusDays(1)
            var end = date
            while (true) {
                val next = end.plusDays(1)
                val holiday = annotation(holidays, region, next, locale)
                if (holiday?.isMakeupWorkday == true || (holiday == null && !weekend(next))) break
                // A covered named run may cross years, but unknown future years are not predicted.
                if (!holidays.covers(next.year, region)) break
                end = next
            }
            return WidgetHoliday(first.name, start.toString(), start.atStartOfDay(zone).toInstant().toEpochMilli(), end.toString(), ChronoUnit.DAYS.between(start, end).toInt() + 1, first.isEstimated)
        }
        return null
    }

    private fun nextLeave(leaves: List<LeaveDay>, days: List<WidgetCalendarDay>, todayKey: String): WidgetLeave? {
        val byKey = leaves.groupBy { it.dayKey }.mapValues { it.value.first() }
        val key = byKey.keys.filter { it >= todayKey }.minOrNull() ?: return null
        var index = days.indexOfFirst { it.dayKey == key }
        if (index < 0) return null
        while (index > 0 && !days[index - 1].isWork && days[index - 1].dayKey >= todayKey) index--
        val run = mutableListOf<WidgetLeaveDay>()
        var requested = 0.0
        var cursor = index
        while (cursor < days.size && (!days[cursor].isWork || byKey[days[cursor].dayKey] != null)) {
            val day = days[cursor]
            val leave = byKey[day.dayKey]
            val kind = if (leave != null) {
                requested += if (leave.portion == "whole") 1.0 else 0.5
                WidgetLeaveDayKind.LEAVE
            } else if (day.kind == WidgetCalendarDayKind.HOLIDAY) WidgetLeaveDayKind.HOLIDAY else WidgetLeaveDayKind.REST
            run += WidgetLeaveDay(day.dayKey, kind)
            cursor++
        }
        val first = run.firstOrNull() ?: return null
        if (requested <= 0) return null
        return WidgetLeave(first.dayKey, days[index].startMs, requested, run.size, run)
    }

    private fun life(profile: LifeProfile?, access: WidgetAccess, zone: ZoneId): WidgetLifePayload {
        if (!access.plus || profile == null) return WidgetLifePayload(access)
        val p = RecordJson.migrateLegacyFields(profile)
        val born = p.bornOn?.let(LifeDates::anchor)
        val career = p.workStartedPartial?.let(LifeDates::anchor)
            ?: p.workStartedOn?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: born?.plusYears(22)
        fun day(date: LocalDate?) = date?.let { floor(it.atStartOfDay(zone).toInstant().toEpochMilli() / 86_400_000.0 + 0.5).toLong() }
        return WidgetLifePayload(access, day(born), p.bornOn?.precision == CivilDatePrecision.YEAR, day(career),
            day(p.retirementOn?.let(LifeDates::anchor)), hidesExactAges = p.hidesExactAges)
    }

    private fun summary(session: ShiftSession, queries: RecordsQueries, calendar: WidgetCalendarPayload, access: WidgetAccess, nowMs: Long, locale: String, copy: (String) -> String, formatHours: (Double) -> String): WidgetSummaryPayload {
        if (!access.isUnlocked(nowMs)) return WidgetSummaryPayload(access)
        val today = queries.today(nowMs.toDouble())
        val todayKey = today.toString()
        val language = Locale.forLanguageTag(locale)
        val periods = WidgetSummaryPeriodKind.entries.mapNotNull { kind ->
            val reportKind = CycleReportKind.valueOf(kind.name)
            val period = queries.reportPeriod(reportKind, today)
            val snapshot = queries.cycleReportSnapshot(period, nowMs.toDouble()) ?: return@mapNotNull null
            val resolutions = queries.resolvedDays(period.startDate, period.endDate)
            val planned = resolutions.filter { it.isScheduledWorkday && it.segments.isNotEmpty() }
            val remaining = planned.count { it.dayKey > todayKey }
            val bars = when (kind) {
                WidgetSummaryPeriodKind.WEEK -> snapshot.days.map { day -> WidgetSummaryBar(
                    day.date.format(DateTimeFormatter.ofPattern("EEEEE", language)), day.workMs,
                    if (day.isToday) WidgetSummaryBarState.CURRENT else when (day.kind) {
                        CycleReportDayKind.UPCOMING -> WidgetSummaryBarState.FUTURE
                        CycleReportDayKind.REST -> WidgetSummaryBarState.REST
                        else -> WidgetSummaryBarState.PAST
                    }) }
                WidgetSummaryPeriodKind.YEAR -> snapshot.months.mapIndexed { index, month -> WidgetSummaryBar(
                    number((index + 1).toDouble(), locale), month.figures.workedMs,
                    if (month.period.startDayKey <= todayKey && todayKey <= month.period.endDayKey) WidgetSummaryBarState.CURRENT
                    else if (month.period.startDayKey > todayKey) WidgetSummaryBarState.FUTURE else WidgetSummaryBarState.PAST) }
                WidgetSummaryPeriodKind.MONTH -> emptyList()
            }
            val previous = queries.cycleReportSnapshot(period.neighbour(-1, queries.firstDayOfWeek), nowMs.toDouble())?.takeIf { it.figures.hasData }
            val comparisonKey = when (kind) {
                WidgetSummaryPeriodKind.WEEK -> "widgetSuiteLastWeekTotal"
                WidgetSummaryPeriodKind.MONTH -> "widgetSuiteLastMonthTotal"
                WidgetSummaryPeriodKind.YEAR -> "widgetSuiteLastYearTotal"
            }
            val title = copy(when (kind) { WidgetSummaryPeriodKind.WEEK -> "widgetSuiteThisWeek"; WidgetSummaryPeriodKind.MONTH -> "widgetSuiteThisMonth"; WidgetSummaryPeriodKind.YEAR -> "widgetSuiteThisYear" })
            val subtitle = when (kind) {
                WidgetSummaryPeriodKind.WEEK -> interpolate(copy("widgetSuiteWeekNumber"), "week" to number(period.startDate.get(WeekFields.of(queries.firstDayOfWeek, WeekFields.of(language).minimalDaysInFirstWeek).weekOfWeekBasedYear()).toDouble(), locale))
                WidgetSummaryPeriodKind.MONTH -> period.startDate.format(DateTimeFormatter.ofPattern("MMMM", language))
                WidgetSummaryPeriodKind.YEAR -> number(period.startDate.year.toDouble(), locale, grouping = false)
            }
            WidgetSummaryPeriod(kind, title, subtitle, period.startDayKey, period.endDayKey, snapshot.figures.workedMs, snapshot.figures.overtimeMs,
                snapshot.figures.workdays, maxOf(planned.size, snapshot.figures.workdays), remaining,
                if (planned.isEmpty()) 0.0 else minOf(1.0, (planned.size - remaining).toDouble() / planned.size), bars,
                previous?.let { interpolate(copy(comparisonKey), "hours" to formatHours(it.figures.workedMs / 3_600_000.0)) })
        }
        val live = if (session.state.countdownStarted) calendar.days.firstOrNull { it.dayKey == todayKey }?.segments.orEmpty().filter { it.endMs > nowMs } else emptyList()
        return WidgetSummaryPayload(access, periods, live)
    }

    private fun number(value: Double, locale: String, grouping: Boolean = true): String = NumberFormat.getNumberInstance(Locale.forLanguageTag(locale)).apply {
        maximumFractionDigits = 1; minimumFractionDigits = 0; isGroupingUsed = grouping
    }.format(value)
    private fun days(value: Double, locale: String, copy: (String) -> String) = interpolate(copy("daysShort"), "count" to number(value, locale))
    private fun interpolate(text: String, vararg args: Pair<String, String>) = args.withIndex().fold(text) { result, arg ->
        result.replace("{{${arg.value.first}}}", arg.value.second).replace("%${arg.index + 1}\$s", arg.value.second)
    }
}
