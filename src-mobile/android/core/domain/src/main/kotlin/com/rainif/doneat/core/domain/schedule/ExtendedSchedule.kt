package com.rainif.doneat.core.domain.schedule

import java.text.BreakIterator
import java.util.Locale
import java.util.UUID

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
                COLOR.matches(colorHex)
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
    val isValid: Boolean
        get() {
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

/** The stored schedule, as far as resolution needs it. */
data class ExtendedSchedule(
    val isEnabled: Boolean,
    val content: ExtendedScheduleContent,
)

/** One day the user assigned by hand. Wins over the rule and over carry-over. */
data class RosterDay(
    val dayKey: String,
    val shiftTypeID: UUID,
    /** The type as it stood when a past day was edited, so renames never rewrite history. */
    val assignedShiftType: ShiftType? = null,
)

/** The clock readings one assigned day works, in the shape the rules take. */
data class ExtendedScheduleDayHours(
    val startTime: String,
    val endTime: String,
    val breakStartTime: String?,
    val breakDurationMinutes: Int,
)

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
        UNASSIGNED("unassigned"),
    }

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
        )
    }

    /** The hours this plan gives one civil day, or null when it is rest. */
    fun hours(dayKey: String): ExtendedScheduleDayHours? {
        val dayNumber = ExtendedScheduleResolver.dayNumber(dayKey) ?: return null
        return ExtendedScheduleResolver(this).day(dayNumber).hours
    }

    companion object {
        val PINNED_SHIFT_TYPE_ID: UUID = UUID.fromString("00000000-0000-0000-0000-00000000F1ED")

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
    val ruleAnchorDayNumber = plan.rule?.let { ExtendedScheduleResolver.dayNumber(it.anchorDayKey) }

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
        for ((key, typeID) in plan.handSetDays) {
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

    fun day(dayNumber: Int): ExtendedScheduleDay = cache.getOrPut(dayNumber) { resolve(dayNumber) }

    /** Frozen, then hand-set, then (unless cleared) holidays over the saved pattern. */
    private fun resolve(dayNumber: Int): ExtendedScheduleDay {
        index.frozenByDayNumber[dayNumber]?.let { return day(it, ExtendedScheduleDay.Source.HAND_SET) }
        index.handSetByDayNumber[dayNumber]?.let { return day(it, ExtendedScheduleDay.Source.HAND_SET) }
        if (index.fallsBackToBaseSchedule) return ExtendedScheduleDay.UNASSIGNED
        val cleared = index.clearedFromDayNumber
        if (index.rule == null && cleared != null && dayNumber >= cleared) return ExtendedScheduleDay.UNASSIGNED
        val base = patternDay(dayNumber)
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
        return day(workID, ExtendedScheduleDay.Source.HOLIDAY)
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
