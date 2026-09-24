package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.records.DayOverride
import com.rainif.doneat.core.domain.records.DayOverrideKind
import com.rainif.doneat.core.domain.records.DayRecordResolver
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.RecordEditContext
import com.rainif.doneat.core.domain.records.RecordEdits
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.records.WorkObservationKind
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedSchedule
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleDay
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.RosterDay
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.ShiftCycleRule
import com.rainif.doneat.core.domain.schedule.ShiftType
import com.rainif.doneat.core.domain.schedule.WallClock
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import com.rainif.doneat.core.domain.settings.PreferencesRules
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** Whether a schedule save also changes the shift in progress. iOS `ScheduleChangeDecision`. */
enum class ScheduleDecision { NEXT_SHIFT_ONLY, APPLY_TO_TODAY }

/** One day changed in the calendar. iOS `RosterDayEdit`. */
sealed interface RosterDayEdit {
    data class Shift(val id: UUID) : RosterDayEdit

    /** Drops the hand-set shift, so the pattern or the carried-over month decides the day again. */
    data object FollowPattern : RosterDayEdit
}

/**
 * The schedule page's draft (iOS `ScheduleFieldChange`): only what the user
 * changed, saved together with one "apply to today?" decision.
 */
data class ScheduleFieldChange(
    val startMinutes: Int? = null,
    val endMinutes: Int? = null,
    val workdays: Set<Int>? = null,
    val scheduleMode: ScheduleMode? = null,
    val lunchEnabled: Boolean? = null,
    val lunchStartMinutes: Int? = null,
    val lunchDurationMinutes: Int? = null,
    val alternatingWeekType: String? = null,
    val alternatingWeekendWorkday: Int? = null,
    val rotationWorkDays: Int? = null,
    val rotationRestDays: Int? = null,
    val rotationCycleDay: Int? = null,
    /** Separate from [scheduleMode], which older builds read. */
    val extendedScheduleEnabled: Boolean? = null,
    /** Shift types and rule, replaced as a whole. */
    val extendedContent: ExtendedScheduleContent? = null,
    val rosterEdits: Map<String, RosterDayEdit>? = null,
    /** Days expanded when trying a free calendar; returning to a pattern drops these, never explicit edits. */
    val materializedRosterDays: Set<String> = emptySet(),
    /** Rechecked at save: protected days and concurrent manual edits survive "clear expected days". */
    val clearExpectedFromDayKey: String? = null,
) {
    val isEmpty get() = this == ScheduleFieldChange()

    fun restoringPatternAfterFreePreview(): ScheduleFieldChange {
        if (materializedRosterDays.isEmpty()) return copy(clearExpectedFromDayKey = null)
        val edits = rosterEdits?.filterKeys { it !in materializedRosterDays }?.takeIf { it.isNotEmpty() }
        return copy(clearExpectedFromDayKey = null, rosterEdits = edits, materializedRosterDays = emptySet())
    }

    /**
     * Drops every field that already matches what is stored, so putting a
     * value back leaves the page clean rather than asking about today over nothing.
     */
    fun settled(env: SessionEnvironment, state: SessionState, nowMs: Double): ScheduleFieldChange {
        val p = env.preferences
        val stored = env.handSetDays
        val edits = rosterEdits?.filter { (key, edit) ->
            when (edit) {
                is RosterDayEdit.Shift -> stored[key] != edit.id || (key in env.generatedRosterDays && key !in materializedRosterDays)
                RosterDayEdit.FollowPattern -> stored[key] != null
            }
        }?.takeIf { it.isNotEmpty() }
        val session = ShiftSession(state, env)
        var next = copy(
            startMinutes = startMinutes?.takeIf { it != p.startMinutes },
            endMinutes = endMinutes?.takeIf { it != p.endMinutes },
            workdays = workdays?.takeIf { it != p.workdays.toSet() },
            scheduleMode = scheduleMode?.takeIf { it != session.scheduleMode },
            lunchEnabled = lunchEnabled?.takeIf { it != p.lunchEnabled },
            lunchStartMinutes = lunchStartMinutes?.takeIf { it != p.lunchStartMinutes },
            lunchDurationMinutes = lunchDurationMinutes?.takeIf { it != p.lunchDurationMinutes },
            alternatingWeekType = alternatingWeekType?.takeIf { it != p.alternatingWeekType },
            alternatingWeekendWorkday = alternatingWeekendWorkday?.takeIf { it != p.alternatingWeekendWorkday },
            rotationWorkDays = rotationWorkDays?.takeIf { it != p.rotationWorkDays },
            rotationRestDays = rotationRestDays?.takeIf { it != p.rotationRestDays },
            extendedScheduleEnabled = extendedScheduleEnabled?.takeIf { it != env.isExtendedScheduleEnabled },
            extendedContent = extendedContent?.takeIf { it != env.extendedSchedule?.content },
            rosterEdits = edits,
        )
        next = next.copy(materializedRosterDays = next.materializedRosterDays.intersect(edits?.keys.orEmpty()))
        // The cycle day is only unchanged against the anchor it will land on.
        if (next.scheduleMode == null && next.rotationWorkDays == null && next.rotationRestDays == null &&
            next.rotationCycleDay == session.rotationCycleDay(nowMs)
        ) next = next.copy(rotationCycleDay = null)
        if (next.copy(clearExpectedFromDayKey = null).isEmpty) next = next.copy(clearExpectedFromDayKey = null)
        return next
    }
}

/** Reshaping the extended schedule on the schedule page. iOS `ExtendedScheduleEditing`; every step returns a new value. */
object ScheduleEditing {
    const val REST_COLOR = "#8E8E93"

    /** Legible as small dots in both appearances; a new type takes the first one no active type uses. */
    val PALETTE = listOf("#FF9500", "#007AFF", "#AF52DE", "#34C759", "#FF2D55", "#30B0C7", "#5856D6", "#A2845E")

    fun nextColor(types: List<ShiftType>): String {
        val used = types.filter { !it.isArchived }.map { it.colorHex.uppercase() }.toSet()
        return PALETTE.firstOrNull { it !in used } ?: PALETTE[types.size % PALETTE.size]
    }

    fun activeTypes(content: ExtendedScheduleContent) = content.shiftTypes.filter { !it.isArchived }

    fun upserting(type: ShiftType, content: ExtendedScheduleContent): ExtendedScheduleContent {
        val index = content.shiftTypes.indexOfFirst { it.id == type.id }
        val types = if (index >= 0) content.shiftTypes.toMutableList().also { it[index] = type } else content.shiftTypes + type
        return content.copy(shiftTypes = types)
    }

    /** Whether the rule still hands this type out; such a type cannot go until its days get another. */
    fun ruleUses(id: UUID, content: ExtendedScheduleContent) = content.rule?.days?.contains(id) == true

    /** A saved type is archived instead of removed: days already worked under it still name it. */
    fun removing(id: UUID, content: ExtendedScheduleContent, saved: ExtendedScheduleContent?): ExtendedScheduleContent =
        if (saved?.shiftTypes?.any { it.id == id } == true) {
            content.copy(shiftTypes = content.shiftTypes.map { if (it.id == id) it.copy(isArchived = true) else it })
        } else {
            content.copy(shiftTypes = content.shiftTypes.filter { it.id != id })
        }

    fun assigning(typeID: UUID, index: Int, content: ExtendedScheduleContent): ExtendedScheduleContent {
        val rule = content.rule ?: return content
        if (index !in rule.days.indices) return content
        return content.copy(rule = rule.copy(days = rule.days.toMutableList().also { it[index] = typeID }))
    }

    /** Lengthens the cycle with rest days, or drops days from its end. */
    fun resizing(content: ExtendedScheduleContent, length: Int, restName: String, newId: () -> UUID = UUID::randomUUID): ExtendedScheduleContent {
        val rule = content.rule ?: return content
        val target = length.coerceIn(1, ShiftCycleRule.MAXIMUM_LENGTH)
        return when {
            target < rule.days.size -> content.copy(rule = rule.copy(days = rule.days.take(target)))
            target > rule.days.size -> {
                val (withRest, rest) = restTypeID(content, restName, newId)
                withRest.copy(rule = rule.copy(days = rule.days + List(target - rule.days.size) { rest }))
            }
            else -> content
        }
    }

    /** Stored hand-set days with a draft's calendar edits applied. */
    fun handSetDays(stored: Map<String, UUID>, edits: Map<String, RosterDayEdit>?): Map<String, UUID> {
        if (edits == null) return stored
        val days = stored.toMutableMap()
        edits.forEach { (key, edit) ->
            when (edit) {
                is RosterDayEdit.Shift -> days[key] = edit.id
                RosterDayEdit.FollowPattern -> days.remove(key)
            }
        }
        return days
    }

    /** Adds one calendar edit, dropping it again when it only restates what is stored. */
    fun editing(edits: Map<String, RosterDayEdit>?, dayKey: String, edit: RosterDayEdit, stored: Map<String, UUID>): Map<String, RosterDayEdit>? {
        val next = edits.orEmpty().toMutableMap()
        val restates = when (edit) {
            is RosterDayEdit.Shift -> stored[dayKey] == edit.id
            RosterDayEdit.FollowPattern -> stored[dayKey] == null
        }
        if (restates) next.remove(dayKey) else next[dayKey] = edit
        return next.takeIf { it.isNotEmpty() }
    }

    /**
     * Writes the pattern's answer into every not-hand-set day of [months] from
     * [fromKey], so dropping the pattern leaves them looking as they did; later
     * months repeat the last of them by date. Earlier days keep their history.
     */
    fun keepingPattern(plan: ExtendedSchedulePlan, months: List<Pair<Int, Int>>, fromKey: String, edits: Map<String, RosterDayEdit>?): Map<String, RosterDayEdit>? {
        val next = edits.orEmpty().toMutableMap()
        val resolver = ExtendedScheduleResolver(plan)
        val first = ExtendedScheduleResolver.dayNumber(fromKey) ?: Int.MIN_VALUE
        for ((year, month) in months) {
            for (day in 1..daysIn(year, month)) {
                val number = CivilZone.dayNumber(year, month, day)
                if (number < first) continue
                val resolved = resolver.day(number)
                val id = resolved.shiftTypeID ?: continue
                if (resolved.source != ExtendedScheduleDay.Source.RULE) continue
                next[ExtendedScheduleResolver.dayKey(number)] = RosterDayEdit.Shift(id)
            }
        }
        return next.takeIf { it.isNotEmpty() }
    }

    /**
     * Free calendar from [today]: only generated assignments are removed, and
     * days already worked or corrected ([protectedDays]) keep what they had.
     */
    fun clearingExpectedDays(draft: ScheduleFieldChange, content0: ExtendedScheduleContent, stored: List<RosterDay>, today: String, protectedDays: Set<String>): ScheduleFieldChange {
        val previousClear = content0.clearedFromDayKey
        val content = content0.copy(rule = null, clearedFromDayKey = minOf(content0.clearedFromDayKey ?: today, today))
        val generated = stored.filter { it.generatedFromPattern == true }.map { it.dayKey }.toSet() + draft.materializedRosterDays
        val edits = draft.rosterEdits.orEmpty().toMutableMap()
        val materialized = draft.materializedRosterDays.toMutableSet()
        // A day may have been timed or corrected since the button was pressed.
        if (draft.clearExpectedFromDayKey != null) {
            edits.entries.removeAll { (key, edit) ->
                key >= today && edit == RosterDayEdit.FollowPattern &&
                    (key in protectedDays || stored.none { it.dayKey == key && it.generatedFromPattern == true })
            }
        }
        for (key in generated) {
            if (key < today || key in protectedDays) continue
            // An explicit edit made after materializing the pattern wins.
            if (edits[key] != null && key !in draft.materializedRosterDays) continue
            if (stored.any { it.dayKey == key }) edits[key] = RosterDayEdit.FollowPattern else edits.remove(key)
            materialized.remove(key)
        }
        // Freeze a protected day's planned assignment before carry-over stops.
        val resolver = ExtendedScheduleResolver(
            ExtendedSchedulePlan(
                shiftTypes = content.shiftTypes, rule = null,
                handSetDays = handSetDays(ExtendedSchedulePlan.handSetDays(stored), draft.rosterEdits),
                holidayRegionIdentifier = content.holidayRegionIdentifier, clearedFromDayKey = previousClear,
            ),
        )
        for (key in protectedDays) {
            if (key < today || edits[key] != null || stored.any { it.dayKey == key }) continue
            val number = ExtendedScheduleResolver.dayNumber(key) ?: continue
            val id = resolver.day(number).shiftTypeID ?: continue
            edits[key] = RosterDayEdit.Shift(id)
            materialized += key
        }
        return draft.copy(
            clearExpectedFromDayKey = today, extendedContent = content, extendedScheduleEnabled = true,
            rosterEdits = edits.takeIf { it.isNotEmpty() }, materializedRosterDays = materialized,
        )
    }

    fun daysIn(year: Int, month: Int): Int {
        val (ny, nm) = if (month == 12) year + 1 to 1 else year to month + 1
        return CivilZone.dayNumber(ny, nm, 1) - CivilZone.dayNumber(year, month, 1)
    }

    /** The month [offset] months after the one containing [dayKey]. */
    fun month(dayKey: String, offset: Int): Pair<Int, Int>? {
        val (year, month, _) = ExtendedScheduleResolver.parse(dayKey) ?: return null
        val index = year * 12 + (month - 1) + offset
        return Math.floorDiv(index, 12) to Math.floorMod(index, 12) + 1
    }

    /** Today's one-based place in the cycle. */
    fun cycleDay(rule: ShiftCycleRule, todayKey: String): Int? {
        if (rule.days.isEmpty()) return null
        val anchor = ExtendedScheduleResolver.dayNumber(rule.anchorDayKey) ?: return null
        val today = ExtendedScheduleResolver.dayNumber(todayKey) ?: return null
        return Math.floorMod(today - anchor, rule.days.size) + 1
    }

    /** Moves the cycle so today is day [position]; what each cycle day works stays the same. */
    fun anchoring(content: ExtendedScheduleContent, todayKey: String, position: Int): ExtendedScheduleContent {
        val rule = content.rule ?: return content
        val today = ExtendedScheduleResolver.dayNumber(todayKey) ?: return content
        return content.copy(rule = rule.copy(anchorDayKey = ExtendedScheduleResolver.dayKey(today - (position - 1))))
    }

    /** The rule's work days get [workType], its rest days the first active rest type (or a new one). */
    fun filling(content: ExtendedScheduleContent, preset: ShiftCycleRule.Preset, pattern: SchedulePattern, workType: UUID, restName: String, newId: () -> UUID = UUID::randomUUID): ExtendedScheduleContent {
        val (next, rest) = restTypeID(content, restName, newId)
        return next.copy(rule = ShiftCycleRule(preset, pattern.anchorDayKey, pattern.workdays.map { if (it) workType else rest }))
    }

    /** The work type a template fills its work days with: the one the rule already uses first. */
    fun primaryWorkType(content: ExtendedScheduleContent): UUID? {
        val active = activeTypes(content).filter { it.kind == ShiftType.Kind.WORK }
        val ids = active.map { it.id }.toSet()
        return content.rule?.days?.firstOrNull { it in ids } ?: active.firstOrNull()?.id
    }

    private fun restTypeID(content: ExtendedScheduleContent, name: String, newId: () -> UUID): Pair<ExtendedScheduleContent, UUID> {
        activeTypes(content).firstOrNull { it.kind == ShiftType.Kind.REST }?.let { return content to it.id }
        val type = ShiftType(newId(), name, ShiftType.Kind.REST, 9 * 60, 17 * 60, false, 12 * 60, 60, REST_COLOR, false)
        return content.copy(shiftTypes = content.shiftTypes + type) to type.id
    }
}

/** What Records planned for a day (iOS `PlannedRosterPreview`). */
sealed interface PlannedPreview {
    data class Shift(val type: ShiftType) : PlannedPreview
    data object Rest : PlannedPreview
    data object NoPlan : PlannedPreview
}

/**
 * A past day as Records has it (iOS `RecordCoordinator.plannedRosterPreview`):
 * its frozen assignment, else its snapshot's plan. A fixed-hours day borrows
 * the name of a type with the same hours, or reads as its own hours.
 */
fun plannedPreview(state: RecordState, dayKey: String, fallbackTypes: List<ShiftType>, ignoringRosterAssignment: Boolean, holidays: HolidayCalendar): PlannedPreview {
    if (!ignoringRosterAssignment) {
        state.rosterDays.firstOrNull { it.dayKey == dayKey }?.assignedShiftType?.let {
            return if (it.kind == ShiftType.Kind.REST) PlannedPreview.Rest else PlannedPreview.Shift(it)
        }
    }
    val s = if (ignoringRosterAssignment) state.copy(rosterDays = state.rosterDays.filter { it.dayKey != dayKey }) else state
    val period = DayRecordResolver.period(dayKey, s.periods) ?: return PlannedPreview.NoPlan
    val snapshot = DayRecordResolver.snapshot(dayKey, period, s.snapshots) ?: return PlannedPreview.NoPlan
    val hours = com.rainif.doneat.core.domain.records.RecordHistory.expandableHours(s, snapshot, holidays) ?: return PlannedPreview.NoPlan
    val zone = FoundationCompat.javaZone(period.timeZoneIdentifier)
    val dayNumber = ExtendedScheduleResolver.dayNumber(dayKey) ?: return PlannedPreview.NoPlan
    val midnight = CivilZone(zone).utcMs(dayNumber, WallClock.MIDNIGHT)
    val day = ScheduleRules.expandScheduleRange(hours, midnight, midnight, zone).firstOrNull() ?: return PlannedPreview.NoPlan
    if (!day.isWorkday) return PlannedPreview.Rest
    hours.extended?.let { plan ->
        ExtendedScheduleResolver(plan).day(dayNumber).shiftTypeID?.let { id ->
            (plan.shiftTypes + fallbackTypes).firstOrNull { it.id == id }?.let {
                return if (it.kind == ShiftType.Kind.REST) PlannedPreview.Rest else PlannedPreview.Shift(it)
            }
        }
    }
    val start = ShiftSession.minutes(day.shiftAnchorStartAtMs, zone)
    val end = ShiftSession.minutes(day.segments.lastOrNull()?.endAtMs ?: return PlannedPreview.NoPlan, zone)
    val breakWindow = if (day.segments.size == 2) {
        ShiftSession.minutes(day.segments[0].endAtMs, zone) to maxOf(0, ((day.segments[1].startAtMs - day.segments[0].endAtMs) / 60_000).toInt())
    } else {
        null
    }
    fallbackTypes.firstOrNull {
        it.kind == ShiftType.Kind.WORK && it.startMinutes == start && it.endMinutes == end && it.breakEnabled == (breakWindow != null) &&
            (breakWindow == null || (it.breakStartMinutes == breakWindow.first && it.breakDurationMinutes == breakWindow.second))
    }?.let { return PlannedPreview.Shift(it) }
    // Legacy fixed snapshots predate named types: a unique type with the same hours lends its name.
    val named = fallbackTypes.filter { !it.isArchived && it.kind == ShiftType.Kind.WORK && it.startMinutes == start && it.endMinutes == end }
    val label = if (named.size == 1) named[0].name else "${ShiftSession.timeString(start)}–${ShiftSession.timeString(end)}"
    return PlannedPreview.Shift(
        ShiftType(
            ExtendedSchedulePlan.PINNED_SHIFT_TYPE_ID, label, ShiftType.Kind.WORK, start, end, breakWindow != null,
            breakWindow?.first ?: 0, breakWindow?.second ?: 0, "#F28C28", true,
        ),
    )
}

/** One cycle of an existing schedule: where it starts and which of its days are workdays. */
data class SchedulePattern(val anchorDayKey: String, val workdays: List<Boolean>)

// The session's view of a draft (iOS `ShiftSession` schedule-editing extensions).

/** Today's day key in the zone the rules resolve in. */
fun ShiftSession.extendedTodayKey(nowMs: Double) = ShiftSession.dayKey(nowMs, countdownZone)

/** Today's one-based position in the fixed rotation (iOS `PreferencesStore.rotationCycleDay`). */
fun ShiftSession.rotationCycleDay(nowMs: Double): Int {
    val p = env.preferences
    val length = maxOf(2, p.rotationWorkDays + p.rotationRestDays)
    val today = ExtendedScheduleResolver.dayNumber(ShiftSession.dayKey(nowMs, recordsZone)) ?: return 1
    val anchor = ExtendedScheduleResolver.dayNumber(ShiftSession.dayKey(p.rotationAnchorMs, recordsZone)) ?: return 1
    return Math.floorMod(today - anchor, length) + 1
}

/** The pattern a draft describes, as the rules would read it once saved. */
fun ShiftSession.workScheduleApplying(c: ScheduleFieldChange, nowMs: Double): WorkSchedule {
    val p = env.preferences
    val mode = c.scheduleMode ?: scheduleMode
    val reanchoredWeek = c.scheduleMode == ScheduleMode.ALTERNATING || c.alternatingWeekType != null
    val weekStart = if (reanchoredWeek) PreferencesRules.startOfWeekMs(nowMs, p.recordsTimeZoneIdentifier) else p.alternatingReferenceWeekStartMs
    val work = c.rotationWorkDays ?: p.rotationWorkDays
    val rest = c.rotationRestDays ?: p.rotationRestDays
    var anchor = if (c.scheduleMode == ScheduleMode.ROTATION) PreferencesRules.startOfDayMs(nowMs, p.recordsTimeZoneIdentifier) else p.rotationAnchorMs
    c.rotationCycleDay?.let { cycleDay ->
        val day = cycleDay.coerceIn(1, maxOf(2, work + rest))
        val today = Instant.ofEpochMilli(nowMs.toLong()).atZone(recordsZone).toLocalDate()
        anchor = today.minusDays((day - 1).toLong()).atStartOfDay(recordsZone).toInstant().toEpochMilli().toDouble()
    }
    return WorkSchedule(
        mode = mode,
        referenceWeekStartMs = weekStart.takeIf { mode == ScheduleMode.ALTERNATING },
        referenceWeekType = (c.alternatingWeekType ?: p.alternatingWeekType).takeIf { mode == ScheduleMode.ALTERNATING },
        singleWeekendWorkday = (c.alternatingWeekendWorkday ?: p.alternatingWeekendWorkday).takeIf { mode == ScheduleMode.ALTERNATING },
        rotationAnchorMs = anchor.takeIf { mode == ScheduleMode.ROTATION },
        rotationWorkDays = work.takeIf { mode == ScheduleMode.ROTATION },
        rotationRestDays = rest.takeIf { mode == ScheduleMode.ROTATION },
    )
}

/** The rules input a draft would give once saved. Applying a draft to today deliberately drops overtime. */
fun ShiftSession.rulesInputApplying(c: ScheduleFieldChange, nowMs: Double): ScheduleRuleInput {
    val p = env.preferences
    val lunchOn = c.lunchEnabled ?: p.lunchEnabled
    val extended = if (c.extendedScheduleEnabled ?: env.isExtendedScheduleEnabled) {
        env.plan(c.extendedContent ?: env.extendedSchedule?.content, c.rosterEdits)
    } else {
        null
    }
    return ScheduleRuleInput(
        hours = ScheduleHours(
            startTime = ShiftSession.timeString(c.startMinutes ?: p.startMinutes),
            endTime = ShiftSession.timeString(c.endMinutes ?: p.endMinutes),
            workdays = (c.workdays ?: p.workdays.toSet()).sorted(),
            schedule = workScheduleApplying(c, nowMs),
            breakStartTime = if (lunchOn) ShiftSession.timeString(c.lunchStartMinutes ?: p.lunchStartMinutes) else null,
            breakDurationMinutes = if (lunchOn) c.lunchDurationMinutes ?: p.lunchDurationMinutes else 0,
            extended = extended,
        ),
        nowMs = nowMs,
        zone = countdownZone,
        forcedWorkdayStartMs = forcedWorkdayStartMs,
    )
}

/** Whether saving [change] needs the second question about today. The rules decide. */
fun ShiftSession.shouldPromptApplyingToToday(change: ScheduleFieldChange, nowMs: Double) =
    ScheduleRules.shouldPromptApplyToday(rulesInput(nowMs), rulesInputApplying(change, nowMs))

/**
 * One cycle of the weekly, alternating or rotation schedule a draft describes,
 * answered by the shared rules, so the extended copy works the same days. A
 * mode other than the current one starts from today; the current one keeps its anchor.
 */
fun ShiftSession.schedulePattern(preset: ShiftCycleRule.Preset, change: ScheduleFieldChange, nowMs: Double): SchedulePattern {
    val mode = when (preset) {
        ShiftCycleRule.Preset.WEEKLY -> ScheduleMode.CLASSIC
        ShiftCycleRule.Preset.ALTERNATING_WEEKS -> ScheduleMode.ALTERNATING
        else -> ScheduleMode.ROTATION
    }
    var probe = change.copy(extendedScheduleEnabled = false, extendedContent = null)
    if (mode != (change.scheduleMode ?: scheduleMode)) probe = probe.copy(scheduleMode = mode)
    val input = rulesInputApplying(probe, nowMs)
    val zone = countdownZone
    val today = ExtendedScheduleResolver.dayNumber(ShiftSession.dayKey(nowMs, zone)) ?: 0
    val (length, startDay) = if (mode == ScheduleMode.ROTATION) {
        val length = maxOf(1, (input.schedule.rotationWorkDays ?: 1) + (input.schedule.rotationRestDays ?: 1))
        val anchor = ExtendedScheduleResolver.dayNumber(ShiftSession.dayKey(input.schedule.rotationAnchorMs ?: nowMs, zone)) ?: today
        length to today - Math.floorMod(today - anchor, length)
    } else {
        val monday = Instant.ofEpochMilli(nowMs.toLong()).atZone(zone).toLocalDate().with(java.time.DayOfWeek.MONDAY)
        (if (mode == ScheduleMode.ALTERNATING) 14 else 7) to (ExtendedScheduleResolver.dayNumber(FoundationCompat.dayKey(monday)) ?: today)
    }
    val civil = CivilZone(zone)
    val days = ScheduleRules.expandScheduleRange(
        input.hours.copy(extended = null), civil.utcMs(startDay, WallClock.MIDNIGHT), civil.utcMs(startDay + length - 1, WallClock.MIDNIGHT), zone,
    )
    val workdays = if (days.size == length) days.map { it.isWorkday } else List(length) { true }
    return SchedulePattern(ExtendedScheduleResolver.dayKey(startDay), workdays)
}

/**
 * A first extended schedule that works exactly the days the current schedule
 * does: one work type with its hours and lunch, one rest type, and a rule copied from the mode.
 */
fun ShiftSession.seededExtendedContent(change: ScheduleFieldChange, nowMs: Double, workName: String, restName: String, newId: () -> UUID = UUID::randomUUID): ExtendedScheduleContent {
    val p = env.preferences
    val work = ShiftType(
        id = newId(), name = workName, kind = ShiftType.Kind.WORK,
        startMinutes = change.startMinutes ?: p.startMinutes, endMinutes = change.endMinutes ?: p.endMinutes,
        breakEnabled = change.lunchEnabled ?: p.lunchEnabled,
        breakStartMinutes = change.lunchStartMinutes ?: p.lunchStartMinutes,
        breakDurationMinutes = change.lunchDurationMinutes ?: p.lunchDurationMinutes,
        colorHex = ScheduleEditing.PALETTE[0], isArchived = false,
    )
    val preset = when (change.scheduleMode ?: scheduleMode) {
        ScheduleMode.ALTERNATING -> ShiftCycleRule.Preset.ALTERNATING_WEEKS
        ScheduleMode.ROTATION -> ShiftCycleRule.Preset.ROTATION
        else -> ShiftCycleRule.Preset.WEEKLY
    }
    val stored = env.extendedSchedule?.content
    return ScheduleEditing.filling(
        ExtendedScheduleContent(listOf(work), null, stored?.holidayRegionIdentifier, stored?.clearedFromDayKey),
        preset, schedulePattern(preset, change, nowMs), work.id, restName, newId,
    )
}

/** [content] with its rule replaced by a template filled from the saved settings for that kind of schedule. */
fun ShiftSession.applyingTemplate(preset: ShiftCycleRule.Preset, content: ExtendedScheduleContent, nowMs: Double, restName: String, newId: () -> UUID = UUID::randomUUID): ExtendedScheduleContent {
    val work = ScheduleEditing.primaryWorkType(content) ?: return content
    return ScheduleEditing.filling(content, preset, schedulePattern(preset, ScheduleFieldChange(), nowMs), work, restName, newId)
}

/** Days whose plan must not move: worked, corrected by hand, or the shift in progress. */
fun ShiftSession.protectedRosterDays(records: RecordState, nowMs: Double): Set<String> {
    val days = HashSet<String>()
    records.observations.filter { it.kind != WorkObservationKind.TIMER_SURFACE_FIRST_SEEN }.forEach { days += it.shiftAnchorDate }
    records.overrides.filter { it.kind != DayOverrideKind.CLEARED }.forEach { days += it.dayKey }
    records.exceptions.filter { !it.isCleared && it.origin == com.rainif.doneat.core.domain.records.CalendarExceptionOrigin.USER }.forEach { days += it.date }
    snapshot(nowMs)?.let { if (it.isWorkday && !it.isBeforeStart(nowMs)) days += ShiftSession.dayKey(it.startAtMs, recordsZone) }
    return days
}

/** The hours and calendar in force until [untilMs], so "from the next shift only" leaves today as it is. */
fun ShiftSession.captureSchedule(untilMs: Double, nowMs: Double): TodayScheduleOverride {
    val p = env.preferences
    val kept = env.livePlan?.takeIf { usesExtendedSchedule(nowMs) }?.let { plan ->
        val shift = ScheduleRules.snapshot(rulesInput(nowMs, pinsEarlyStart = false), salary)
        val key = ShiftSession.dayKey(shift.startAtMs, countdownZone)
        KeptRosterDay(key, plan.handSetDays[key])
    }
    return TodayScheduleOverride(
        p.startMinutes, p.endMinutes, p.workdays.sorted(), p.scheduleMode, p.lunchEnabled, p.lunchStartMinutes, p.lunchDurationMinutes,
        p.alternatingWeekType, p.alternatingWeekendWorkday, p.alternatingReferenceWeekStartMs, p.rotationWorkDays, p.rotationRestDays,
        p.rotationAnchorMs, untilMs, env.isExtendedScheduleEnabled, env.extendedSchedule?.content, kept,
    )
}

/**
 * Saving the schedule page (iOS `ShiftSessionStore.applyScheduleChange` with
 * the preference and records writes it drives): preferences, the extended
 * schedule, the calendar and the Records snapshot land in one archive write,
 * and the session's marks for today follow [ScheduleDecision].
 */
object ScheduleSave {
    data class Result(val records: RecordState, val state: SessionState)

    /** Null when the save is refused or changes nothing; nothing is written then. */
    fun apply(
        records: RecordState,
        state: SessionState,
        env: SessionEnvironment,
        requested: ScheduleFieldChange,
        requestedDecision: ScheduleDecision,
        nowMs: Double,
        newId: () -> String,
    ): Result? {
        val session = ShiftSession(state, env)
        val recordsZoneId = env.preferences.recordsTimeZoneIdentifier
        val today = ShiftSession.dayKey(nowMs, session.recordsZone)
        var change = requested
        val protected = session.protectedRosterDays(records, nowMs)
        change.clearExpectedFromDayKey?.let { from ->
            val content = change.extendedContent ?: env.extendedSchedule?.content
            if (content != null) change = ScheduleEditing.clearingExpectedDays(change, content, records.rosterDays, from, protected)
        }
        change = change.settled(env, state, nowMs)
        if (change.isEmpty) return null
        // Clearing never truncates a shift in progress, but an untouched day that has not started clears too.
        val decision = if (change.clearExpectedFromDayKey != null) {
            val started = session.snapshot(nowMs)?.let { it.isWorkday && !it.isBeforeStart(nowMs) } == true
            if (started || today in protected) ScheduleDecision.NEXT_SHIFT_ONLY else ScheduleDecision.APPLY_TO_TODAY
        } else {
            requestedDecision
        }

        // The extended schedule is a record of its own, switched separately.
        var prefChange = change.copy(
            extendedScheduleEnabled = null, extendedContent = null, rosterEdits = null,
            materializedRosterDays = emptySet(), clearExpectedFromDayKey = null,
        )
        change.extendedContent?.let { if (!it.isValid) return null }
        change.rosterEdits?.let { edits ->
            val content = change.extendedContent ?: env.extendedSchedule?.content ?: return null
            val known = content.shiftTypes.map { it.id }.toSet()
            val admitted = edits.all { (key, edit) ->
                ExtendedScheduleResolver.dayNumber(key) != null &&
                    (key >= today || DayRecordResolver.period(key, records.periods) != null) &&
                    (edit !is RosterDayEdit.Shift || edit.id in known)
            }
            if (!admitted) return null
        }
        change.extendedScheduleEnabled?.let { enabled ->
            if (records.extendedSchedule == null && change.extendedContent == null) return null
            // "Schedule off" means start by hand; a roster is a schedule.
            if (enabled && (prefChange.scheduleMode ?: session.scheduleMode) == ScheduleMode.OFF) prefChange = prefChange.copy(scheduleMode = ScheduleMode.CLASSIC)
        }

        val replacedProjection = if (decision == ScheduleDecision.APPLY_TO_TODAY) session.projectedDayOverride(nowMs) else null
        val preserved = if (decision == ScheduleDecision.NEXT_SHIFT_ONLY) session.captureSchedule(session.overrideExpiry(nowMs), nowMs) else null

        var recs = records
        val settledPrefs = prefChange.settled(env, state, nowMs)
        if (!settledPrefs.isEmpty) {
            val next = applying(env.preferences, settledPrefs, nowMs)
            if (!next.isValid) return null
            recs = PreferencesRules.commit(recs, next, nowMs, newId())
        }
        if (change.extendedScheduleEnabled != null || change.extendedContent != null) {
            recs = updateExtendedSchedule(recs, change.extendedContent, change.extendedScheduleEnabled, recordsZoneId, nowMs, newId) ?: return null
        }
        change.rosterEdits?.let { recs = applyRosterEdits(recs, it, change.materializedRosterDays, recordsZoneId, nowMs, newId) }

        val newEnv = env.with(recs)
        var s = state.copy(todayOverride = preserved)
        fun started(x: SessionState) = if (x.countdownStarted) x else x.copy(countdownStarted = true, sessionId = newId())
        fun boundary(x: SessionState) = x.copy(activeCountdownEndAtMs = ShiftSession(x, newEnv).snapshot(nowMs)?.endAtMs)
        if (decision == ScheduleDecision.APPLY_TO_TODAY) {
            s = s.copy(todayOverride = null, overtimeEndAtMs = null).clearingEarlyClockOff().clearingEarlyClockIn()
            // Hours never cancel rest-day manual timing; once today is a workday the mark is redundant.
            if (ShiftSession(s, newEnv).snapshot(nowMs)?.isWorkday == true) s = s.copy(forcedWorkdayDate = null)
            s = when {
                ShiftSession(s, newEnv).scheduleMode == ScheduleMode.OFF -> s.copy(
                    countdownStarted = false, forcedWorkdayDate = null, activeCountdownEndAtMs = null, overtimeEndAtMs = null,
                ).clearingEarlyClockIn().clearingEarlyClockOff().clearingSessionTimeZone()
                newEnv.onboardingComplete -> boundary(started(s))
                else -> s
            }
        } else if (newEnv.onboardingComplete && ShiftSession(s, newEnv).effectiveScheduleMode(nowMs) != ScheduleMode.OFF) {
            s = started(s)
        }

        val newSession = ShiftSession(s, newEnv)
        val effectiveFrom = if (decision == ScheduleDecision.APPLY_TO_TODAY) today else ShiftSession.dayKey(ShiftSession.startOfNextDayMs(nowMs, session.recordsZone), session.recordsZone)
        val context = RecordEditContext(nowMs, recordsZoneId, canEdit = true, holidays = env.holidays, currentHours = { newSession.hoursConfiguration(nowMs) }, newId = newId)
        recs = RecordEdits.commitHours(recs, newSession.hoursConfiguration(nowMs), effectiveFrom, context).first
        if (decision == ScheduleDecision.APPLY_TO_TODAY) recs = replacingProjectedOverride(recs, replacedProjection, newSession.projectedDayOverride(nowMs), context)
        return Result(recs, s)
    }

    /** iOS `PreferencesStore.applySetupScheduleChange`: a new pattern starts from today. */
    fun applying(p: SyncedPreferences, c: ScheduleFieldChange, nowMs: Double): SyncedPreferences {
        var v = p
        c.startMinutes?.let { v = v.copy(startMinutes = it) }
        c.endMinutes?.let { v = v.copy(endMinutes = it) }
        c.workdays?.takeIf { it.isNotEmpty() }?.let { v = v.copy(workdays = it.sorted()) }
        c.scheduleMode?.let { mode ->
            v = v.copy(scheduleMode = mode.raw)
            if (mode == ScheduleMode.ALTERNATING) v = v.copy(alternatingReferenceWeekStartMs = PreferencesRules.startOfWeekMs(nowMs, p.recordsTimeZoneIdentifier))
            if (mode == ScheduleMode.ROTATION) v = v.copy(rotationAnchorMs = PreferencesRules.startOfDayMs(nowMs, p.recordsTimeZoneIdentifier))
        }
        c.lunchEnabled?.let { v = v.copy(lunchEnabled = it) }
        c.lunchStartMinutes?.let { v = v.copy(lunchStartMinutes = it) }
        c.lunchDurationMinutes?.let { v = v.copy(lunchDurationMinutes = it) }
        c.alternatingWeekType?.let { v = v.copy(alternatingWeekType = it, alternatingReferenceWeekStartMs = PreferencesRules.startOfWeekMs(nowMs, p.recordsTimeZoneIdentifier)) }
        c.alternatingWeekendWorkday?.let { v = v.copy(alternatingWeekendWorkday = it) }
        c.rotationWorkDays?.let { v = v.copy(rotationWorkDays = it) }
        c.rotationRestDays?.let { v = v.copy(rotationRestDays = it) }
        c.rotationCycleDay?.let { cycleDay ->
            val zone = FoundationCompat.javaZone(p.recordsTimeZoneIdentifier)
            val day = cycleDay.coerceIn(1, maxOf(2, v.rotationWorkDays + v.rotationRestDays))
            val today = Instant.ofEpochMilli(nowMs.toLong()).atZone(zone).toLocalDate()
            v = v.copy(rotationAnchorMs = today.minusDays((day - 1).toLong()).atStartOfDay(zone).toInstant().toEpochMilli().toDouble())
        }
        return v
    }

    /** iOS `RecordCoordinator.updateExtendedSchedule`: null when the result is invalid or there is nothing to switch. */
    fun updateExtendedSchedule(state: RecordState, content: ExtendedScheduleContent?, enabled: Boolean?, zone: String, nowMs: Double, newId: () -> String): RecordState? {
        val current = state.extendedSchedule
        var schedule = current ?: ExtendedSchedule(isEnabled = false, content = content ?: return null, timeZoneIdentifier = zone, editedAtMs = nowMs)
        content?.let { schedule = schedule.copy(content = it) }
        enabled?.let { schedule = schedule.copy(isEnabled = it) }
        if (!schedule.content.isValid) return null
        if (current != null && current.isEnabled == schedule.isEnabled && current.content == schedule.content &&
            !state.isErased(RecordEntityType.EXTENDED_SCHEDULE, ExtendedSchedule.LOGICAL_KEY)
        ) return state
        val (cleared, buried) = clearingErased(state, RecordEntityType.EXTENDED_SCHEDULE, ExtendedSchedule.LOGICAL_KEY)
        var count = (current?.editCount ?: maxOf(schedule.editCount, 0)) + 1
        if (buried != null && count <= buried) count = buried + 1
        return cleared.copy(extendedSchedule = schedule.copy(editCount = count, editTieBreaker = newId(), editedAtMs = nowMs))
    }

    /**
     * iOS `RecordCoordinator.applyRosterEdits`: a shift sets the day by hand
     * (freezing its type on past days), following the pattern erases the row
     * with a tombstone other devices honour.
     */
    fun applyRosterEdits(state: RecordState, edits: Map<String, RosterDayEdit>, generated: Set<String>, zone: String, nowMs: Double, newId: () -> String): RecordState {
        val today = ShiftSession.dayKey(nowMs, FoundationCompat.javaZone(zone))
        val types = state.extendedSchedule?.content?.shiftTypes.orEmpty().associateBy { it.id }
        var s = state
        for ((key, edit) in edits.toSortedMap()) {
            s = when (edit) {
                is RosterDayEdit.Shift -> upsertRosterDay(
                    s,
                    RosterDay(
                        dayKey = key, shiftTypeID = edit.id, assignedShiftType = if (key < today) types[edit.id] else null,
                        generatedFromPattern = if (key in generated) true else null, timeZoneIdentifier = zone,
                    ),
                    nowMs, newId,
                )
                RosterDayEdit.FollowPattern -> if (s.rosterDays.any { it.dayKey == key }) RecordJson.erase(s, RecordEntityType.ROSTER_DAY, key, nowMs) else s
            }
        }
        return s
    }

    private fun upsertRosterDay(state: RecordState, draft: RosterDay, nowMs: Double, newId: () -> String): RecordState {
        val current = state.rosterDays.firstOrNull { it.dayKey == draft.dayKey }
        fun business(d: RosterDay) = d.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "")
        if (!state.isErased(RecordEntityType.ROSTER_DAY, draft.dayKey) && current != null && business(current) == business(draft)) return state
        val (cleared, buried) = clearingErased(state, RecordEntityType.ROSTER_DAY, draft.dayKey)
        var count = (current?.editCount ?: maxOf(draft.editCount, 0)) + 1
        if (buried != null && count <= buried) count = buried + 1
        val row = draft.copy(editCount = count, editTieBreaker = newId(), editedAtMs = nowMs)
        val days = if (current != null) cleared.rosterDays.map { if (it.dayKey == draft.dayKey) row else it } else cleared.rosterDays + row
        return cleared.copy(rosterDays = days)
    }

    private fun clearingErased(state: RecordState, type: RecordEntityType, key: String): Pair<RecordState, Int?> {
        val tombstone = state.erased.firstOrNull { it.entityType == type && it.logicalKey == key } ?: return state to null
        return state.copy(erased = state.erased - tombstone) to tombstone.editCount
    }

    /**
     * Only the timer projection that existed before "change today too" is
     * reconciled; a Records edit with other content stays.
     */
    private fun replacingProjectedOverride(state: RecordState, previous: DayOverride?, current: DayOverride?, context: RecordEditContext): RecordState {
        if (current != null) return RecordEdits.upsertOverride(state, current, context)
        previous ?: return state
        val stored = state.overrides.firstOrNull { it.dayKey == previous.dayKey } ?: return state
        val same = stored.kind == previous.kind && stored.segments == previous.segments && stored.note == previous.note &&
            stored.timeZoneIdentifier == previous.timeZoneIdentifier
        return if (same) RecordJson.erase(state, RecordEntityType.DAY_OVERRIDE, previous.dayKey, context.nowMs) else state
    }
}
