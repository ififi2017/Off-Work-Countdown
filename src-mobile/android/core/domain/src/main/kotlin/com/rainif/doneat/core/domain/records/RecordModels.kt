package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ExtendedSchedule
import com.rainif.doneat.core.domain.schedule.RosterDay
import com.rainif.doneat.core.domain.schedule.ShiftSegment

/**
 * The records archive (iOS `RecordState`) and its twelve entity families,
 * mirroring `docs/android/wire-contract.md`.
 *
 * Unlike iOS, civil dates stay `YYYY-MM-DD` labels rather than `Date`s: iOS
 * converts them through a calendar and back, which is the identity for every
 * valid key, so labels give the same documents without the time-zone
 * arithmetic. Instants are Unix milliseconds. Identifiers are upper-case UUID
 * strings, the form Swift writes, which also makes tie-breaks a plain string
 * comparison.
 */
enum class RecordEntityType(val raw: String) {
    CAREER_PERIOD("careerPeriod"),
    SCHEDULE_SNAPSHOT("scheduleSnapshot"),
    CALENDAR_EXCEPTION("calendarException"),
    DAY_OVERRIDE("dayOverride"),
    WORK_OBSERVATION("workObservation"),
    LIFE_PROFILE("lifeProfile"),
    FOCUS_TASK("focusTask"),
    FOCUS_SESSION("focusSession"),
    FOCUS_PLANNING_CONFIGURATION("focusPlanningConfiguration"),
    SYNCED_PREFERENCES("syncedPreferences"),
    EXTENDED_SCHEDULE("extendedSchedule"),
    ROSTER_DAY("rosterDay");

    companion object {
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw }
    }
}

data class CareerPeriod(
    val id: String,
    val startsOn: String,
    val endsBefore: String?,
    val label: String?,
    val timeZoneIdentifier: String,
    val calendarIdentifier: String,
    val createdAtMs: Double,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
)

data class ScheduleSnapshot(
    val id: String,
    val periodID: String,
    val effectiveFrom: String,
    /** Base64 of the `ScheduleHoursConfiguration` JSON, kept byte for byte. */
    val configurationData: String,
    val fingerprint: String,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
)

enum class CalendarEffect(val raw: String) { REST("rest"), WORK("work") }
enum class CalendarExceptionOrigin(val raw: String) { USER("user"), BUNDLED("bundled") }

data class CalendarException(
    /** `<date>#<origin>`, e.g. `2026-08-26#user`. */
    val dayKey: String,
    val date: String,
    val effect: CalendarEffect,
    val origin: CalendarExceptionOrigin,
    val isCleared: Boolean,
    val regionIdentifier: String?,
    val datasetVersion: String?,
    val label: String?,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
    val timeZoneIdentifier: String,
)

enum class DayOverrideKind(val raw: String) {
    CONFIRMED_AS_SCHEDULED("confirmedAsScheduled"),
    CUSTOM_SEGMENTS("customSegments"),
    NOT_WORKING("notWorking"),
    CLEARED("cleared"),
}

data class DayOverride(
    /** The shift start day; an overnight shift keys as the day it started. */
    val dayKey: String,
    val kind: DayOverrideKind,
    val segments: List<ShiftSegment>,
    val note: String?,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
    val timeZoneIdentifier: String,
)

enum class WorkObservationKind(val raw: String) {
    TIMER_SURFACE_FIRST_SEEN("timerSurfaceFirstSeen"),
    COUNTDOWN_STARTED("countdownStarted"),
    COUNTDOWN_STOPPED("countdownStopped"),
    OVERTIME_DECLARED("overtimeDeclared"),
}

/** An immutable use event; only sync conflict resolution changes its stamps. */
data class WorkObservation(
    val eventID: String,
    val shiftAnchorDate: String,
    val occurredAtMs: Double,
    val kind: WorkObservationKind,
    val valueData: String?,
    val scheduleSnapshotID: String,
    /** The entity's own version (currently 2), not the document's. */
    val schemaVersion: Int,
    val timeZoneIdentifier: String,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
)

enum class CivilDatePrecision(val raw: String) { YEAR("year"), DAY("day") }

data class PartialCivilDate(val year: Int, val month: Int?, val day: Int?, val precision: CivilDatePrecision)

enum class SleepSource(val raw: String) { MANUAL("manual"), HEALTH_SUGGESTED("healthSuggested") }
enum class LifeWorkHistoryMode(val raw: String) { ROUGH("rough"), DETAILED("detailed") }
enum class LifeSalaryCadence(val raw: String) { MONTHLY("monthly"), YEARLY("yearly") }

data class LifeSalary(val amount: Double, val cadence: LifeSalaryCadence)
data class LifeIncomeDecline(val startsAtAge: Int, val retirementRatio: Double)
data class LifeEmploymentPeriod(val id: String, val startsOn: PartialCivilDate, val endsOn: PartialCivilDate?, val salary: LifeSalary)

data class LifeProfile(
    val profileID: String,
    val birthYear: Int?,
    val workStartedOn: String?,
    val retirementAge: Int?,
    val averageSleepHours: Double?,
    val hidesExactAges: Boolean,
    val bornOn: PartialCivilDate?,
    val schoolStartedOn: PartialCivilDate?,
    val workStartedPartial: PartialCivilDate?,
    val retirementOn: PartialCivilDate?,
    val averageSleepMinutes: Int?,
    val sleepSource: SleepSource?,
    val sleepSourceUpdatedAtMs: Double?,
    val workHistoryMode: LifeWorkHistoryMode,
    val roughCurrentSalary: LifeSalary?,
    val employmentPeriods: List<LifeEmploymentPeriod>,
    val futureIncomeDecline: LifeIncomeDecline?,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
) {
    companion object {
        /** One profile per archive: two offline devices first-write the same row. */
        const val PROFILE_ID = "00000000-0000-0000-0000-00574F524B01"
    }
}

enum class FocusTaskIcon(val raw: String) {
    FOCUS("focus"), WORK("work"), CODE("code"), STUDY("study"),
    WRITING("writing"), COMMUNICATION("communication"), MEETING("meeting"), IDEA("idea"),
}

data class FocusTask(
    val id: String,
    val createdAtMs: Double,
    val plannedForDate: String?,
    val scheduledStartAtMs: Double?,
    val title: String,
    val estimatedPomodoros: Int,
    val icon: FocusTaskIcon,
    val isFavorite: Boolean,
    val completedAtMs: Double?,
    val deletedAtMs: Double?,
    val sortIndex: Int,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
    val templateID: String?,
    val templateTaskKey: String?,
)

enum class FocusEndReason(val raw: String) {
    COMPLETED("completed"),
    STOPPED_BY_USER("stoppedByUser"),
    STOPPED_AT_BOUNDARY("stoppedAtBoundary"),
    ABANDONED("abandoned"),
    SUPERSEDED_BY_SYNC("supersededBySync"),
}

enum class FocusSessionKind(val raw: String) { FOCUS("focus"), SHORT_BREAK("shortBreak"), LONG_BREAK("longBreak") }

data class FocusSession(
    val id: String,
    val taskID: String?,
    val shiftAnchorDate: String,
    val startedAtMs: Double,
    val plannedEndAtMs: Double,
    val endedAtMs: Double?,
    val endReason: FocusEndReason?,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
    val kind: FocusSessionKind,
    val timeZoneIdentifier: String,
    val anchorDayKey: String,
    /** Seconds, not milliseconds. */
    val actualDurationSeconds: Int?,
    val plannedEndReason: FocusEndReason,
)

enum class FocusPlanBlockKind(val raw: String) { TASK("task"), BREAK_TIME("breakTime") }

data class FocusPlanAssignment(
    val blockStartAtMs: Long,
    val kind: FocusPlanBlockKind,
    val taskID: String?,
    val taskTitle: String?,
    val taskIcon: FocusTaskIcon?,
)

data class FocusDayPlan(val dayKey: String, val shiftStartAtMs: Long, val assignments: List<FocusPlanAssignment>, val appliedTemplateID: String?)

data class FocusTemplateSlot(val blockIndex: Int, val kind: FocusPlanBlockKind, val taskKey: String?, val taskTitle: String?, val taskIcon: FocusTaskIcon?)

data class FocusTemplate(val id: String, val name: String, val slots: List<FocusTemplateSlot>, val createdAtMs: Double, val updatedAtMs: Double)

data class FocusTimerSettings(val focusMinutes: Int, val shortBreakMinutes: Int, val longBreakMinutes: Int, val longBreakEvery: Int) {
    val normalized
        get() = FocusTimerSettings(
            focusMinutes.coerceIn(10, 60),
            shortBreakMinutes.coerceIn(1, 15),
            longBreakMinutes.coerceIn(5, 30),
            longBreakEvery.coerceIn(2, 6),
        )
}

data class FocusPlanningConfiguration(
    val plans: Map<String, FocusDayPlan>,
    val templates: List<FocusTemplate>,
    val defaultTemplateID: String?,
    val autoAppliedDayKeys: Set<String>,
    val timerSettings: FocusTimerSettings,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
) {
    companion object {
        const val LOGICAL_KEY = "focus-planning"
    }
}

/** Preferences whose meaning follows the person across devices; device capabilities never sync. */
data class SyncedPreferences(
    val startMinutes: Int,
    val endMinutes: Int,
    val workdays: List<Int>,
    val scheduleMode: String,
    val alternatingWeekType: String,
    val alternatingWeekendWorkday: Int,
    val alternatingReferenceWeekStartMs: Double,
    val rotationWorkDays: Int,
    val rotationRestDays: Int,
    val rotationAnchorMs: Double,
    val lunchEnabled: Boolean,
    val lunchStartMinutes: Int,
    val lunchDurationMinutes: Int,
    val recordsTimeZoneIdentifier: String,
    /** The decimal text the user typed. */
    val salaryAmount: String,
    val salaryEnabled: Boolean,
    val salaryType: String,
    val monthlyWorkingDays: Double,
    val annualBonusEnabled: Boolean,
    val annualBonusMonths: Double,
    val notificationMode: String,
    val cycleEndSummaryNotificationEnabled: Boolean,
    val lunchStartReminderEnabled: Boolean,
    val lunchEndReminderEnabled: Boolean,
    val microBreakEnabled: Boolean,
    val microBreakIntervalMinutes: Int,
    val theme: String,
    val languageOverride: String?,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
) {
    val isValid: Boolean
        get() = startMinutes in 0 until 1_440 &&
            endMinutes in 0 until 1_440 &&
            workdays == workdays.toSortedSet().toList() &&
            // Sunday = 0; 7 stays accepted from archives the previous validator admitted.
            workdays.all { it in 0..7 } &&
            alternatingWeekendWorkday in 0..7 &&
            alternatingReferenceWeekStartMs.isFinite() &&
            rotationWorkDays > 0 &&
            rotationRestDays > 0 &&
            rotationAnchorMs.isFinite() &&
            lunchStartMinutes in 0 until 1_440 &&
            lunchDurationMinutes in 1..1_439 &&
            FoundationCompat.isValidTimeZone(recordsTimeZoneIdentifier) &&
            monthlyWorkingDays.isFinite() && monthlyWorkingDays > 0 &&
            annualBonusMonths.isFinite() && annualBonusMonths >= 0 &&
            microBreakIntervalMinutes in 1..720 &&
            (languageOverride == null || languageOverride in SUPPORTED_LANGUAGES) &&
            editedAtMs.isFinite() &&
            editCount >= 0

    companion object {
        const val LOGICAL_KEY = "preferences"
        val SUPPORTED_LANGUAGES = setOf(
            "en", "zh-CN", "zh-HK", "zh-TW", "ja", "ko", "de", "es", "fr", "it",
            "pt", "ru", "ar", "hi-IN", "mr-IN", "id", "th", "tr", "vi",
        )
        val SCHEDULE_MODES = setOf("classic", "alternating", "rotation", "off")
        val WEEK_TYPES = setOf("single", "double")
        val SALARY_TYPES = setOf("monthly", "daily")
        val NOTIFICATION_MODES = setOf("off", "simple", "milestones")
        val THEMES = setOf("auto", "light", "dark")
    }
}

/** A tombstone: a later import or sync must not resurrect this identity below [editCount]. */
data class ErasedID(val entityType: RecordEntityType, val logicalKey: String, val erasedAtMs: Double, val editCount: Int = 0)

data class RecordState(
    val periods: List<CareerPeriod> = emptyList(),
    val snapshots: List<ScheduleSnapshot> = emptyList(),
    val exceptions: List<CalendarException> = emptyList(),
    val overrides: List<DayOverride> = emptyList(),
    val observations: List<WorkObservation> = emptyList(),
    val lifeProfile: LifeProfile? = null,
    val focusTasks: List<FocusTask> = emptyList(),
    val focusSessions: List<FocusSession> = emptyList(),
    val focusPlanningConfiguration: FocusPlanningConfiguration? = null,
    val syncedPreferences: SyncedPreferences? = null,
    val extendedSchedule: ExtendedSchedule? = null,
    val rosterDays: List<RosterDay> = emptyList(),
    val recordsStartedOn: String? = null,
    val erased: List<ErasedID> = emptyList(),
) {
    fun isErased(type: RecordEntityType, key: String) = erased.any { it.entityType == type && it.logicalKey == key }
}
