package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.CivilZone

/**
 * A Records day editor's draft (iOS `RecordDayEditDraft`), immutable so a
 * screen can keep it across configuration changes. Archive refreshes never
 * replace edits the user has not submitted: [stillMatches] tells a caller
 * whether a result still belongs to the draft on screen.
 */
data class DayEditDraft(
    val dayKey: String,
    val loadedKind: Kind,
    val loadedStartMinutes: Int,
    val loadedEndMinutes: Int,
    val hasStoredOverride: Boolean,
    val kind: Kind = loadedKind,
    val startMinutes: Int = loadedStartMinutes,
    val endMinutes: Int = loadedEndMinutes,
    val editGeneration: Int = 0,
) {
    enum class Kind(val write: DayRecordWrite) {
        CUSTOM_HOURS(DayRecordWrite.CUSTOM_HOURS),
        AS_SCHEDULED(DayRecordWrite.CONFIRMED),
        LEAVE(DayRecordWrite.LEAVE),
        REST_DAY(DayRecordWrite.REST),
        MAKEUP_DAY(DayRecordWrite.MAKEUP),
    }

    data class Submission(val dayKey: String, val write: DayRecordWrite, val startMinutes: Int, val endMinutes: Int, val editGeneration: Int)

    val hasChanges: Boolean
        get() = kind != loadedKind || (kind == Kind.CUSTOM_HOURS && (startMinutes != loadedStartMinutes || endMinutes != loadedEndMinutes))

    val submission get() = Submission(dayKey, kind.write, startMinutes, endMinutes, editGeneration)

    fun stillMatches(submission: Submission) = this.submission == submission

    fun withKind(value: Kind) = if (value == kind) this else copy(kind = value, editGeneration = editGeneration + 1)
    fun withStart(minutes: Int) = if (minutes == startMinutes) this else copy(startMinutes = minutes, editGeneration = editGeneration + 1)
    fun withEnd(minutes: Int) = if (minutes == endMinutes) this else copy(endMinutes = minutes, editGeneration = editGeneration + 1)

    companion object {
        /**
         * Loads the day as stored: an override decides the kind, else a user or
         * bundled exception, else custom hours. Times come from the resolved
         * segments in the records zone, defaulting to 09:00–18:00.
         */
        fun load(dayKey: String, state: RecordState, resolution: DayResolution?, recordsTimeZone: String): DayEditDraft {
            val zone = CivilZone(FoundationCompat.javaZone(recordsTimeZone))
            fun minutes(ms: Double?, fallback: Int): Int = ms?.let { zone.civil(it) }?.let { it.hour * 60 + it.minute } ?: fallback
            val override = state.overrides.firstOrNull { it.dayKey == dayKey && it.kind != DayOverrideKind.CLEARED }
            val kind = when {
                override != null -> when (override.kind) {
                    DayOverrideKind.CUSTOM_SEGMENTS, DayOverrideKind.CLEARED -> Kind.CUSTOM_HOURS
                    DayOverrideKind.CONFIRMED_AS_SCHEDULED -> Kind.AS_SCHEDULED
                    DayOverrideKind.NOT_WORKING -> Kind.LEAVE
                }
                else -> state.exceptions.firstOrNull { it.dayKey.startsWith("$dayKey#") && !it.isCleared }
                    ?.let { if (it.effect == CalendarEffect.REST) Kind.REST_DAY else Kind.MAKEUP_DAY }
                    ?: Kind.CUSTOM_HOURS
            }
            return DayEditDraft(
                dayKey = dayKey,
                loadedKind = kind,
                loadedStartMinutes = minutes(resolution?.segments?.firstOrNull()?.startAtMs, 9 * 60),
                loadedEndMinutes = minutes(resolution?.segments?.lastOrNull()?.endAtMs, 18 * 60),
                hasStoredOverride = override != null,
            )
        }
    }
}
