package com.rainif.doneat.core.domain.schedule

import java.text.BreakIterator
import java.util.Locale
import java.util.UUID

/** Inclusive month/day bounds, recurring yearly and wrapping across New Year when needed. */
data class AnnualShiftDateRange(val startMonth: Int, val startDay: Int, val endMonth: Int, val endDay: Int) {
    val isValid: Boolean get() = valid(startMonth, startDay) && valid(endMonth, endDay)

    fun contains(month: Int, day: Int): Boolean {
        if (!isValid || !valid(month, day)) return false
        val start = startMonth * 100 + startDay
        val end = endMonth * 100 + endDay
        val date = month * 100 + day
        return if (start <= end) date in start..end else date >= start || date <= end
    }

    fun overlaps(other: AnnualShiftDateRange): Boolean = isValid && other.isValid && (
        contains(other.startMonth, other.startDay) || contains(other.endMonth, other.endDay) ||
            other.contains(startMonth, startDay) || other.contains(endMonth, endDay)
        )

    private fun valid(month: Int, day: Int): Boolean = month in 1..12 && day in 1..31 &&
        CivilZone.civilDate(CivilZone.dayNumber(2000, month, day)) == Triple(2000, month, day)
}

/**
 * Plan 018 P8's extended scheduling, ported from `src-mobile/ios/Shared`
 * (ExtendedSchedule.swift, ExtendedScheduleRules.swift). iOS-only behaviour:
 * the Swift is the specification and `extended-schedule-fixtures.json` holds
 * its answers. Resolution only produces the `(start, end, break, isWorkday)`
 * tuple [CivilZone] already consumes; it is not a second scheduling engine.
 *
 * Day keys are civil-date labels (`YYYY-MM-DD`), not instants.
 */
data class ShiftType(
    val id: UUID,
    val name: String,
    val kind: Kind,
    /** Civil minutes after midnight; an end at or before the start crosses midnight. */
    val startMinutes: Int,
    val endMinutes: Int,
    val breakEnabled: Boolean,
    val breakStartMinutes: Int,
    val breakDurationMinutes: Int,
    val colorHex: String,
    /** Archived types stay so past days that used them still resolve. */
    val isArchived: Boolean,
    val annualDateRange: AnnualShiftDateRange? = null,
) {
    enum class Kind(val raw: String) {
        WORK("work"),
        REST("rest");

        companion object {
            fun fromRaw(raw: String) = entries.first { it.raw == raw }
        }
    }

    val isValid: Boolean
        get() {
            val trimmed = SwiftText.trimWhitespaceAndNewlines(name)
            return trimmed.isNotEmpty() &&
                SwiftText.characterCount(trimmed) <= MAXIMUM_NAME_LENGTH &&
                startMinutes in 0 until 1_440 &&
                endMinutes in 0 until 1_440 &&
                breakStartMinutes in 0 until 1_440 &&
                breakDurationMinutes in 0 until 1_440 &&
                (!breakEnabled || breakDurationMinutes > 0) &&
                COLOR.matches(colorHex) &&
                (annualDateRange?.let { kind == Kind.WORK && it.isValid } ?: true)
        }

    companion object {
        const val MAXIMUM_NAME_LENGTH = 40
        private val COLOR = Regex("#[0-9A-Fa-f]{6}")
    }
}

/** One shift type per day of the cycle, counted from [anchorDayKey]. */
data class ShiftCycleRule(val preset: Preset, val anchorDayKey: String, val days: List<UUID>) {
    enum class Preset(val raw: String) {
        WEEKLY("weekly"),
        ALTERNATING_WEEKS("alternatingWeeks"),
        ROTATION("rotation"),
        CUSTOM("custom");

        companion object {
            /** Only an editor hint: a preset a newer build added reads as custom. */
            fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw } ?: CUSTOM
        }
    }

    companion object {
        const val MAXIMUM_LENGTH = 366
    }
}

/** What a schedule edit changes and what a Records snapshot keeps. Hand-set days stay live. */
data class ExtendedScheduleContent(
    val shiftTypes: List<ShiftType>,
    val rule: ShiftCycleRule?,
    val holidayRegionIdentifier: String? = null,
    /** Free schedules stop automatic carry-over and holiday assignments from this civil day. */
    val clearedFromDayKey: String? = null,
) {
    val hasOverlappingAnnualDateRanges: Boolean
        get() {
            val ranges = shiftTypes.filter { it.kind == ShiftType.Kind.WORK && !it.isArchived }.mapNotNull { it.annualDateRange }
            return ranges.indices.any { i -> ranges.drop(i + 1).any(ranges[i]::overlaps) }
        }

    val isValid: Boolean
        get() {
            if (hasOverlappingAnnualDateRanges) return false
            if (clearedFromDayKey != null && ExtendedScheduleResolver.parse(clearedFromDayKey) == null) return false
            if (!HolidayCalendar.isValidRegionIdentifier(holidayRegionIdentifier)) return false
            if (!shiftTypes.all { it.isValid }) return false
            if (shiftTypes.map { it.id }.toSet().size != shiftTypes.size) return false
            val rule = rule ?: return true
            val known = shiftTypes.map { it.id }.toSet()
            return rule.days.isNotEmpty() &&
                rule.days.size <= ShiftCycleRule.MAXIMUM_LENGTH &&
                rule.days.all { it in known } &&
                ExtendedScheduleResolver.parse(rule.anchorDayKey) != null
        }
}

/** The stored schedule (one per archive, logical key `extended-schedule`). */
data class ExtendedSchedule(
    val isEnabled: Boolean,
    val content: ExtendedScheduleContent,
    /** The zone whose civil dates the rule anchor and roster day keys name. */
    val timeZoneIdentifier: String = "GMT",
    val editedAtMs: Double = 0.0,
    val editCount: Int = 0,
    val editTieBreaker: String = "00000000-0000-0000-0000-000000000000",
) {
    companion object {
        const val LOGICAL_KEY = "extended-schedule"
    }
}

/** One day the user assigned by hand. Wins over the rule and over carry-over. */
data class RosterDay(
    val dayKey: String,
    val shiftTypeID: UUID,
    /** The type as it stood when a past day was edited, so renames never rewrite history. */
    val assignedShiftType: ShiftType? = null,
    /** Missing on older rows, which must conservatively remain manual. */
    val generatedFromPattern: Boolean? = null,
    val timeZoneIdentifier: String = "GMT",
    val editedAtMs: Double = 0.0,
    val editCount: Int = 0,
    val editTieBreaker: String = "00000000-0000-0000-0000-000000000000",
)

/** The clock readings one assigned day works, in the shape the rules take. */
data class ExtendedScheduleDayHours(
    val startTime: String,
    val endTime: String,
    val breakStartTime: String?,
    val breakDurationMinutes: Int,
) {
    /**
     * What is still worked once [portion] is taken as leave (plan 020), or
     * null when nothing is. The shift splits at half its working minutes with
     * the break left out, so 09:00–18:00 with lunch at 12:00–13:00 splits at
     * 14:00: taking the morning leaves 14:00–18:00, taking the afternoon
     * leaves 09:00–14:00 with its lunch.
     *
     * Minutes are wall-clock minutes. Across a DST change during the shift the
     * split can sit an hour away from half the elapsed time; the planner,
     * which works on absolute segments, may preview that night differently.
     */
    fun remaining(after: LeavePortion): ExtendedScheduleDayHours? {
        if (after == LeavePortion.WHOLE) return null
        val start = WallClock.parse(startTime).minutes
        val length = Math.floorMod(WallClock.parse(endTime).minutes - start + 1_440 - 1, 1_440) + 1
        var breakOffset: Int? = null
        if (breakStartTime != null && breakDurationMinutes > 0) {
            val offset = Math.floorMod(WallClock.parse(breakStartTime).minutes - start + 1_440, 1_440)
            // The same test `CivilZone.timeline` applies: strictly inside.
            if (offset > 0 && offset + breakDurationMinutes < length) breakOffset = offset
        }
        val working = length - (if (breakOffset == null) 0 else breakDurationMinutes)
        val half = working / 2
        if (half <= 0) return null
        fun clock(offset: Int) = ExtendedScheduleResolver.timeString((start + offset) % 1_440)
        val from: Int
        val to: Int
        val keepsBreak: Boolean
        if (breakOffset != null && half > breakOffset) {
            // The first half runs through the break.
            val split = half + breakDurationMinutes
            if (after == LeavePortion.FIRST_HALF) { from = split; to = length; keepsBreak = false } else { from = 0; to = split; keepsBreak = true }
        } else {
            val secondStart = if (breakOffset == half) half + breakDurationMinutes else half
            if (after == LeavePortion.FIRST_HALF) {
                from = secondStart; to = length; keepsBreak = breakOffset != null && breakOffset > half
            } else {
                from = 0; to = half; keepsBreak = false
            }
        }
        return ExtendedScheduleDayHours(
            startTime = clock(from),
            endTime = clock(to),
            breakStartTime = if (keepsBreak) breakStartTime else null,
            breakDurationMinutes = if (keepsBreak) breakDurationMinutes else 0,
        )
    }
}

/** Which part of one shift a leave request frees (plan 020). */
enum class LeavePortion(val raw: String) {
    WHOLE("whole"),
    FIRST_HALF("firstHalf"),
    SECOND_HALF("secondHalf");

    val halfDays get() = if (this == WHOLE) 2 else 1

    companion object {
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw }
    }
}

/** One civil day's conclusion, and which layer reached it. */
data class ExtendedScheduleDay(
    val isWorkday: Boolean,
    /** Null on rest or unassigned days, where the caller keeps its own hours. */
    val hours: ExtendedScheduleDayHours?,
    val shiftTypeID: UUID?,
    val source: Source,
) {
    enum class Source(val raw: String) {
        HAND_SET("handSet"),
        RULE("rule"),
        HOLIDAY("holiday"),
        CARRIED_OVER("carriedOver"),
        ANNUAL_RANGE("annualRange"),
        /**
         * Leave (plan 020) replaced an assigned shift: rest for a whole shift,
         * the remaining half's hours for half of one.
         */
        LEAVE("leave"),
        /**
         * Half a shift of leave over the fixed schedule underneath a fallback
         * plan. The hours are the remaining half; whether the day is worked at
         * all is still the fixed schedule's answer.
         */
        LEAVE_OVER_BASE("leaveOverBase"),
        UNASSIGNED("unassigned"),
    }

    /** Whether a fallback plan leaves this day's work-or-rest answer to the fixed schedule underneath. */
    val followsBaseSchedule get() = source == Source.UNASSIGNED || source == Source.LEAVE_OVER_BASE

    companion object {
        val UNASSIGNED = ExtendedScheduleDay(false, null, null, Source.UNASSIGNED)
    }
}

/**
 * The stored extended schedule flattened into what resolution needs, with its
 * index built once. A null plan (no schedule, or switched off) keeps every rule
 * on the fixed-hours path.
 */
class ExtendedSchedulePlan(
    val shiftTypes: List<ShiftType>,
    val rule: ShiftCycleRule?,
    /** Civil day key to shift type, for the days the user set by hand. */
    val handSetDays: Map<String, UUID>,
    val holidayRegionIdentifier: String? = null,
    val clearedFromDayKey: String? = null,
    /** `yyyymmdd` to isWorkday; when present it replaces the bundled calendar. */
    val holidayOverrides: Map<Int, Boolean>? = null,
    /** Past assignments carry their type so old snapshots resolve the exact hours chosen. */
    val frozenShiftTypes: Map<String, ShiftType> = emptyMap(),
    /** Historical rows over a classic snapshot: unassigned days keep the base schedule. */
    val fallsBackToBaseSchedule: Boolean = false,
    /** The day [pinning] fixed; resolves without counting as authored. */
    val pinnedDayKey: String? = null,
    val holidays: HolidayCalendar = HolidayCalendar.EMPTY,
    /**
     * Leave taken per civil day key (plan 020), laid over whatever the rest of
     * the plan resolves. Empty for every plan without adopted leave.
     */
    val leaveDays: Map<String, LeavePortion> = emptyMap(),
    /** The fixed hours underneath a fallback plan, which half a shift of leave on an otherwise unassigned day is taken from. */
    val baseHours: ExtendedScheduleDayHours? = null,
) {
    internal val index = ExtendedScheduleIndex(this)

    /** The same plan with one day fixed to the given clock readings. Never stored. */
    fun pinning(dayKey: String, hours: ExtendedScheduleDayHours): ExtendedSchedulePlan {
        val start = WallClock.parse(hours.startTime)
        val end = WallClock.parse(hours.endTime)
        val breakStart = hours.breakStartTime?.let { WallClock.parse(it).minutes }
        val types = shiftTypes.filter { it.id != PINNED_SHIFT_TYPE_ID } + ShiftType(
            id = PINNED_SHIFT_TYPE_ID,
            name = "pinned",
            kind = ShiftType.Kind.WORK,
            startMinutes = start.minutes,
            endMinutes = end.minutes,
            breakEnabled = breakStart != null && hours.breakDurationMinutes > 0,
            breakStartMinutes = breakStart ?: 0,
            breakDurationMinutes = if (breakStart == null) 0 else hours.breakDurationMinutes,
            colorHex = "#000000",
            isArchived = true,
        )
        return ExtendedSchedulePlan(
            types, rule, handSetDays, holidayRegionIdentifier, clearedFromDayKey, holidayOverrides,
            frozenShiftTypes, fallsBackToBaseSchedule, pinnedDayKey = dayKey, holidays = holidays,
            leaveDays = leaveDays, baseHours = baseHours,
        )
    }

    /** The hours this plan gives one civil day, or null when it is rest. */
    fun hours(dayKey: String): ExtendedScheduleDayHours? {
        val dayNumber = ExtendedScheduleResolver.dayNumber(dayKey) ?: return null
        return ExtendedScheduleResolver(this).day(dayNumber).hours
    }

    companion object {
        val PINNED_SHIFT_TYPE_ID: UUID = UUID.fromString("00000000-0000-0000-0000-00000000F1ED")

        /**
         * The same plan with [leave] laid over it, or a fallback plan carrying
         * only the leave over [baseHours] when there is no plan. Null stays null
         * without leave, so a user who never adopted any keeps the exact path
         * they had.
         */
        fun applying(leave: Map<String, LeavePortion>, plan: ExtendedSchedulePlan?, baseHours: ExtendedScheduleDayHours): ExtendedSchedulePlan? {
            if (leave.isEmpty()) return plan
            plan ?: return ExtendedSchedulePlan(
                shiftTypes = emptyList(), rule = null, handSetDays = emptyMap(),
                fallsBackToBaseSchedule = true, leaveDays = leave, baseHours = baseHours,
            )
            return ExtendedSchedulePlan(
                plan.shiftTypes, plan.rule, plan.handSetDays, plan.holidayRegionIdentifier, plan.clearedFromDayKey,
                plan.holidayOverrides, plan.frozenShiftTypes, plan.fallsBackToBaseSchedule, plan.pinnedDayKey, plan.holidays,
                leaveDays = leave,
                baseHours = if (plan.fallsBackToBaseSchedule) baseHours else plan.baseHours,
            )
        }

        /** Later rows win, as the Swift dictionary builders do. */
        fun handSetDays(rosterDays: List<RosterDay>): Map<String, UUID> =
            rosterDays.associate { it.dayKey to it.shiftTypeID }

        fun frozenShiftTypes(rosterDays: List<RosterDay>): Map<String, ShiftType> =
            rosterDays.mapNotNull { day -> day.assignedShiftType?.let { day.dayKey to it } }.toMap()

        /**
         * The live plan, or null for a schedule that is absent or switched off.
         * `includeDisabled` is for history: days worked under a schedule keep
         * resolving through it after the user switches it off.
         */
        fun of(
            schedule: ExtendedSchedule?,
            rosterDays: List<RosterDay>,
            holidays: HolidayCalendar,
            includeDisabled: Boolean = false,
        ): ExtendedSchedulePlan? {
            if (schedule == null || !(schedule.isEnabled || includeDisabled)) return null
            return ExtendedSchedulePlan(
                shiftTypes = schedule.content.shiftTypes,
                rule = schedule.content.rule,
                handSetDays = handSetDays(rosterDays),
                holidayRegionIdentifier = schedule.content.holidayRegionIdentifier,
                clearedFromDayKey = schedule.content.clearedFromDayKey,
                frozenShiftTypes = frozenShiftTypes(rosterDays),
                holidays = holidays,
            )
        }

        /**
         * Historical assignments over an otherwise fixed snapshot. Frozen rows
         * always apply; legacy rows only when [includesLegacyRows], using the
         * live archived types older builds left them pointing at.
         */
        fun historical(
            rosterDays: List<RosterDay>,
            legacyShiftTypes: List<ShiftType> = emptyList(),
            includesLegacyRows: Boolean = false,
        ): ExtendedSchedulePlan? {
            val handSet = rosterDays
                .filter { it.assignedShiftType != null || includesLegacyRows }
                .associate { it.dayKey to it.shiftTypeID }
            if (handSet.isEmpty()) return null
            return ExtendedSchedulePlan(
                shiftTypes = legacyShiftTypes,
                rule = null,
                handSetDays = handSet,
                frozenShiftTypes = frozenShiftTypes(rosterDays),
                fallsBackToBaseSchedule = true,
            )
        }
    }
}

/** Everything resolution needs from a plan, parsed once. */
internal class ExtendedScheduleIndex(plan: ExtendedSchedulePlan) {
    val holidays = plan.holidays
    val rule = plan.rule
    val holidayRegionIdentifier = plan.holidayRegionIdentifier
    val holidayOverrides = plan.holidayOverrides
    val fallsBackToBaseSchedule = plan.fallsBackToBaseSchedule
    val clearedFromDayNumber = plan.clearedFromDayKey?.let(ExtendedScheduleResolver::dayNumber)
    val defaultWorkTypeID = plan.shiftTypes.firstOrNull { it.kind == ShiftType.Kind.WORK && !it.isArchived }?.id
    val defaultRestTypeID = plan.shiftTypes.firstOrNull { it.kind == ShiftType.Kind.REST && !it.isArchived }?.id
    val annualWorkTypes = plan.shiftTypes.filter { it.kind == ShiftType.Kind.WORK && !it.isArchived && it.isValid }
        .mapNotNull { type -> type.annualDateRange?.let { type.id to it } }
    val ruleAnchorDayNumber = plan.rule?.let { ExtendedScheduleResolver.dayNumber(it.anchorDayKey) }
    val leaveByDayNumber: Map<Int, LeavePortion> = plan.leaveDays.mapNotNull { (key, portion) ->
        ExtendedScheduleResolver.dayNumber(key)?.let { it to portion }
    }.toMap()
    val baseHours = plan.baseHours

    /** What each defined type resolves to. First valid definition of an id wins; invalid ones resolve to nothing. */
    val dayByType: Map<UUID, Pair<Boolean, ExtendedScheduleDayHours?>>
    val handSetByDayNumber: Map<Int, UUID>
    val frozenByDayNumber: Map<Int, ShiftType>
    /** Month key to that month's hand-set days, by day of the month. */
    val authoredMonths: Map<Int, Map<Int, UUID>>
    val authoredFrozenMonths: Map<Int, Map<Int, ShiftType>>
    val authoredMonthKeys: List<Int>

    init {
        val byType = HashMap<UUID, Pair<Boolean, ExtendedScheduleDayHours?>>()
        for (type in plan.shiftTypes) {
            if (byType.containsKey(type.id) || !type.isValid) continue
            byType[type.id] = when (type.kind) {
                ShiftType.Kind.REST -> false to null
                ShiftType.Kind.WORK -> true to ExtendedScheduleResolver.hours(type)
            }
        }
        dayByType = byType

        val byDay = HashMap<Int, UUID>()
        val months = HashMap<Int, HashMap<Int, UUID>>()
        // A day set to a type this schedule does not have (written under an
        // earlier set of types) says nothing about the day; the pattern and
        // holidays decide it. Archived types are still present. Matches iOS.
        val knownTypeIDs = plan.shiftTypes.mapTo(HashSet()) { it.id }
        for ((key, typeID) in plan.handSetDays) {
            if (typeID !in knownTypeIDs) continue
            val (year, month, day) = ExtendedScheduleResolver.parse(key) ?: continue
            byDay[CivilZone.dayNumber(year, month, day)] = typeID
            months.getOrPut(ExtendedScheduleResolver.monthKey(year, month)) { HashMap() }[day] = typeID
        }
        val frozen = HashMap<Int, ShiftType>()
        val frozenMonths = HashMap<Int, HashMap<Int, ShiftType>>()
        for ((key, type) in plan.frozenShiftTypes) {
            val (year, month, day) = ExtendedScheduleResolver.parse(key) ?: continue
            // Carry-over copies a frozen type even when it no longer validates;
            // the day itself only takes a valid one.
            frozenMonths.getOrPut(ExtendedScheduleResolver.monthKey(year, month)) { HashMap() }[day] = type
            if (type.isValid) frozen[CivilZone.dayNumber(year, month, day)] = type
        }
        plan.pinnedDayKey?.let(ExtendedScheduleResolver::dayNumber)?.let {
            byDay[it] = ExtendedSchedulePlan.PINNED_SHIFT_TYPE_ID
        }
        handSetByDayNumber = byDay
        frozenByDayNumber = frozen
        authoredMonths = months
        authoredFrozenMonths = frozenMonths
        authoredMonthKeys = months.keys.sorted()
    }
}

/**
 * Resolution for one run of the rules; memoises per day, since a next-shift
 * search or a long expansion asks about the same days repeatedly.
 */
class ExtendedScheduleResolver(plan: ExtendedSchedulePlan) {
    private val index = plan.index
    private val cache = HashMap<Int, ExtendedScheduleDay>()

    val fallsBackToBaseSchedule get() = index.fallsBackToBaseSchedule
    val baseHours get() = index.baseHours

    fun day(dayNumber: Int): ExtendedScheduleDay = cache.getOrPut(dayNumber) { resolve(dayNumber) }

    /** Leave is laid over everything else. It only ever frees work: leave on a day the schedule already rests changes nothing. */
    private fun resolve(dayNumber: Int): ExtendedScheduleDay {
        val base = resolveSchedule(dayNumber)
        val portion = index.leaveByDayNumber[dayNumber] ?: return base
        if (base.source == ExtendedScheduleDay.Source.UNASSIGNED && index.fallsBackToBaseSchedule) {
            if (portion == LeavePortion.WHOLE) return ExtendedScheduleDay(false, null, null, ExtendedScheduleDay.Source.LEAVE)
            val hours = index.baseHours?.remaining(portion) ?: return base
            return ExtendedScheduleDay(true, hours, null, ExtendedScheduleDay.Source.LEAVE_OVER_BASE)
        }
        val hours = base.hours
        if (!base.isWorkday || hours == null) return base
        return ExtendedScheduleDay(portion != LeavePortion.WHOLE, hours.remaining(portion), base.shiftTypeID, ExtendedScheduleDay.Source.LEAVE)
    }

    /** Frozen, then hand-set, then (unless cleared) holidays over the saved pattern. */
    private fun resolveSchedule(dayNumber: Int): ExtendedScheduleDay {
        index.frozenByDayNumber[dayNumber]?.let { return day(it, ExtendedScheduleDay.Source.HAND_SET) }
        index.handSetByDayNumber[dayNumber]?.let { return day(it, ExtendedScheduleDay.Source.HAND_SET) }
        if (index.fallsBackToBaseSchedule) return ExtendedScheduleDay.UNASSIGNED
        val cleared = index.clearedFromDayNumber
        if (index.rule == null && cleared != null && dayNumber >= cleared) return ExtendedScheduleDay.UNASSIGNED
        val base = annualDay(patternDay(dayNumber), dayNumber)
        val region = index.holidayRegionIdentifier
        if (region.isNullOrEmpty()) return base
        val (year, month, day) = CivilZone.civilDate(dayNumber)
        val dateCode = year * 10_000 + month * 100 + day
        // Explicit overrides (a paired device's transport copy) replace the bundled calendar.
        val overrides = index.holidayOverrides
        val isWorkday = (if (overrides != null) overrides[dateCode] else index.holidays.day(dateCode, region)?.isWorkday)
            ?: return base
        if (!isWorkday) {
            index.defaultRestTypeID?.let { return day(it, ExtendedScheduleDay.Source.HOLIDAY) }
            return ExtendedScheduleDay(false, null, null, ExtendedScheduleDay.Source.HOLIDAY)
        }
        if (base.isWorkday) return base.copy(source = ExtendedScheduleDay.Source.HOLIDAY)
        val workID = index.defaultWorkTypeID ?: return base
        return annualDay(day(workID, ExtendedScheduleDay.Source.HOLIDAY), dayNumber)
    }

    private fun annualDay(base: ExtendedScheduleDay, dayNumber: Int): ExtendedScheduleDay {
        if (!base.isWorkday || index.annualWorkTypes.isEmpty()) return base
        val (_, month, date) = CivilZone.civilDate(dayNumber)
        val type = index.annualWorkTypes.firstOrNull { it.second.contains(month, date) } ?: return base
        return day(type.first, if (base.source == ExtendedScheduleDay.Source.HOLIDAY) base.source else ExtendedScheduleDay.Source.ANNUAL_RANGE)
    }

    private fun patternDay(dayNumber: Int): ExtendedScheduleDay {
        val rule = index.rule
        val anchor = index.ruleAnchorDayNumber
        if (rule != null && rule.days.isNotEmpty() && anchor != null) {
            val position = Math.floorMod(dayNumber - anchor, rule.days.size)
            return day(rule.days[position], ExtendedScheduleDay.Source.RULE)
        }
        return carriedOver(dayNumber)
    }

    /**
     * An untouched month repeats the nearest earlier authored month by day
     * number; a day number that month lacks (29–31 from February) is rest. A
     * month the user touched is authored: its unset days stay unassigned.
     */
    private fun carriedOver(dayNumber: Int): ExtendedScheduleDay {
        val (year, month, day) = CivilZone.civilDate(dayNumber)
        val monthKey = monthKey(year, month)
        if (index.authoredMonths.containsKey(monthKey)) return ExtendedScheduleDay.UNASSIGNED
        val sourceKey = nearestAuthoredMonth(monthKey) ?: return ExtendedScheduleDay.UNASSIGNED
        val typeID = index.authoredMonths[sourceKey]?.get(day) ?: return ExtendedScheduleDay.UNASSIGNED
        index.authoredFrozenMonths[sourceKey]?.get(day)?.let { return day(it, ExtendedScheduleDay.Source.CARRIED_OVER) }
        return day(typeID, ExtendedScheduleDay.Source.CARRIED_OVER)
    }

    private fun nearestAuthoredMonth(monthKey: Int): Int? {
        val keys = index.authoredMonthKeys
        var low = 0
        var high = keys.size
        while (low < high) {
            val middle = (low + high) / 2
            if (keys[middle] < monthKey) low = middle + 1 else high = middle
        }
        return if (low > 0) keys[low - 1] else null
    }

    /** A type the plan does not define is unassigned: sync can deliver a day before its type. */
    private fun day(typeID: UUID, source: ExtendedScheduleDay.Source): ExtendedScheduleDay {
        val (isWorkday, hours) = index.dayByType[typeID] ?: return ExtendedScheduleDay.UNASSIGNED
        return ExtendedScheduleDay(isWorkday, hours, typeID, source)
    }

    private fun day(type: ShiftType, source: ExtendedScheduleDay.Source) = when (type.kind) {
        ShiftType.Kind.REST -> ExtendedScheduleDay(false, null, type.id, source)
        ShiftType.Kind.WORK -> ExtendedScheduleDay(true, hours(type), type.id, source)
    }

    companion object {
        private val DAY_KEY = Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")

        fun monthKey(year: Int, month: Int) = year * 12 + (month - 1)

        fun parse(dayKey: String): Triple<Int, Int, Int>? {
            if (!DAY_KEY.matches(dayKey)) return null
            val (year, month, day) = dayKey.split("-").map { it.toInt() }
            if (year !in 1..9_999 || month !in 1..12 || day !in 1..31) return null
            val civil = CivilZone.civilDate(CivilZone.dayNumber(year, month, day))
            return if (civil == Triple(year, month, day)) civil else null
        }

        fun dayNumber(dayKey: String): Int? = parse(dayKey)?.let { (y, m, d) -> CivilZone.dayNumber(y, m, d) }

        fun dayKey(dayNumber: Int): String {
            val (y, m, d) = CivilZone.civilDate(dayNumber)
            return "%04d-%02d-%02d".format(Locale.ROOT, y, m, d)
        }

        fun timeString(minutes: Int): String {
            val clamped = minutes.coerceIn(0, 1_439)
            return "%02d:%02d".format(Locale.ROOT, clamped / 60, clamped % 60)
        }

        internal fun hours(type: ShiftType) = ExtendedScheduleDayHours(
            startTime = timeString(type.startMinutes),
            endTime = timeString(type.endMinutes),
            breakStartTime = if (type.breakEnabled && type.breakDurationMinutes > 0) timeString(type.breakStartMinutes) else null,
            breakDurationMinutes = if (type.breakEnabled) type.breakDurationMinutes else 0,
        )
    }
}

/** Swift `String` semantics the shift-type limits depend on. */
internal object SwiftText {
    /** Unicode White_Space, which `.whitespacesAndNewlines` trims. */
    private fun isWhiteSpace(c: Char) = c in '\u0009'..'\u000D' || c == ' ' || c == '\u0085' || c == ' ' ||
        c == ' ' || c in ' '..' ' || c == ' ' || c == ' ' || c == ' ' ||
        c == ' ' || c == '　'

    fun trimWhitespaceAndNewlines(text: String) = text.trim(::isWhiteSpace)

    /** Extended grapheme clusters, as `String.count`: one emoji family is one character. */
    fun characterCount(text: String): Int {
        val iterator = BreakIterator.getCharacterInstance()
        iterator.setText(text)
        var count = 0
        while (iterator.next() != BreakIterator.DONE) count++
        return count
    }
}
