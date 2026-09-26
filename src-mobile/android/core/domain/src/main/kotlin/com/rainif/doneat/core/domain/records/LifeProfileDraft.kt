package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.records.LifeDates.isValid
import com.rainif.doneat.core.domain.salary.NumberInput
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate

/** A detailed work history as the editor lays it out (iOS `LifeEmploymentTimeline`). */
object LifeEmploymentTimeline {
    /** Only adjacent stored periods remain linked; explicit gaps and invalid ends stay intact. */
    fun linkedEndIds(periods: List<LifeEmploymentPeriod>): Set<String> {
        val sorted = periods.sortedByDescending { LifeDates.anchor(it.startsOn) }
        return sorted.mapIndexedNotNull { index, period ->
            period.id.takeIf { period.endsOn == sorted.getOrNull(index - 1)?.startsOn }
        }.toSet()
    }

    /** Resolve the editor's linked ends, preserving all other boundaries and rejecting overlaps. */
    fun linkedPeriods(
        periods: List<LifeEmploymentPeriod>,
        today: LocalDate,
        linkingEndsFor: Set<String>,
    ): List<LifeEmploymentPeriod>? {
        val dated = periods.mapNotNull { period -> LifeDates.anchor(period.startsOn)?.let { period to it } }
        if (dated.isEmpty() || dated.size != periods.size || periods.map { it.id }.toSet().size != periods.size) return null
        if (!periods.all { it.startsOn.precision == CivilDatePrecision.DAY && it.salary.isValid() }) return null
        val sorted = dated.sortedByDescending { it.second }
        if (sorted[0].second.isAfter(today)) return null
        if (sorted.zipWithNext().any { (newer, older) -> !newer.second.isAfter(older.second) }) return null
        return sorted.mapIndexed { index, (period, start) ->
            val end = if (period.id in linkingEndsFor) sorted.getOrNull(index - 1)?.first?.startsOn else period.endsOn
            if (end == null) {
                if (index != 0) return null
            } else {
                val endDate = LifeDates.anchor(end) ?: return null
                if (end.precision != CivilDatePrecision.DAY || !endDate.isAfter(start)) return null
                if (index > 0 && endDate.isAfter(sorted[index - 1].second)) return null
            }
            period.copy(endsOn = end)
        }
    }

    /** Where an older history without a current job resumes: the latest past end, else the work start, else today. */
    fun inferredCurrentStart(profile: LifeProfile?, today: LocalDate): LocalDate {
        profile?.employmentPeriods?.mapNotNull { it.endsOn?.let(LifeDates::anchor) }?.filter { !it.isAfter(today) }?.maxOrNull()?.let { return it }
        profile?.workStartedPartial?.let(LifeDates::anchor)?.takeIf { !it.isAfter(today) }?.let { return it }
        profile?.workStartedOn?.let { runCatching { LocalDate.parse(it) }.getOrNull() }?.takeIf { !it.isAfter(today) }?.let { return it }
        return today
    }
}

/**
 * The Life profile editor's fields (iOS `LifeProfileEditView` state, `load`,
 * `canSave` and `save`), kept as the text the user typed. Number fields hold
 * normalized digits and "." for valid edits, or the rejected text for correction.
 */
data class LifeProfileDraft(
    val bornYear: String = "",
    val schoolYear: String = "",
    val workYear: String = "",
    val retirementAge: String = "60",
    val sleepHours: String = "8",
    val mode: LifeWorkHistoryMode = LifeWorkHistoryMode.ROUGH,
    val roughAmount: String = "",
    val roughCadence: LifeSalaryCadence = LifeSalaryCadence.MONTHLY,
    /** Newest first; the first is the current job and takes the rough salary. */
    val employment: List<Employment> = emptyList(),
    val declines: Boolean = false,
    val declineAge: String = "45",
    val ratioPercent: String = "60",
) {
    data class Employment(
        val id: String,
        val startDate: LocalDate,
        val amount: String = "",
        val cadence: LifeSalaryCadence = LifeSalaryCadence.MONTHLY,
        val wasCurrent: Boolean = false,
        val endsOn: PartialCivilDate? = null,
        val linksEndToNext: Boolean = true,
    ) {
        fun period(salary: LifeSalary?): LifeEmploymentPeriod? {
            val startsOn = LifeDates.exact(startDate.year, startDate.monthValue, startDate.dayOfMonth) ?: return null
            val resolved = salary ?: salaryOf(amount, cadence) ?: return null
            return LifeEmploymentPeriod(id, startsOn, endsOn, resolved)
        }
    }

    val incomeDecline: LifeIncomeDecline?
        get() {
            val age = NumberInput.committedText(declineAge, decimal = false, maxDigits = 3)?.toIntOrNull() ?: return null
            val percent = NumberInput.committedText(ratioPercent, decimal = false, maxDigits = 3)?.let(NumberInput::parse) ?: return null
            return LifeIncomeDecline(age, percent / 100).takeIf { it.isValid() }
        }

    fun linkedPeriods(today: LocalDate): List<LifeEmploymentPeriod>? {
        val current = salaryOf(roughAmount, roughCadence) ?: return null
        if (employment.isEmpty()) return null
        val periods = employment.mapIndexedNotNull { index, draft -> draft.period(if (index == 0) current else null) }
        if (periods.size != employment.size) return null
        return LifeEmploymentTimeline.linkedPeriods(periods, today, employment.filter { it.linksEndToNext }.map { it.id }.toSet())
    }

    fun canSave(today: LocalDate): Boolean {
        if (NumberInput.committedText(sleepHours, decimal = true, maxDigits = 4)?.let(NumberInput::parse) == null) return false
        if (!validOptionalYear(bornYear) || !validOptionalYear(schoolYear) || !validOptionalYear(workYear)) return false
        val age = NumberInput.committedText(retirementAge, decimal = false, maxDigits = 3)?.toIntOrNull()
        if (age == null || age !in 1..120) return false
        if (roughAmount.isNotEmpty() && salaryOf(roughAmount, roughCadence) == null) return false
        if (declines) {
            val decline = incomeDecline ?: return false
            if (bornYear.toIntOrNull() == null || decline.startsAtAge >= age) return false
        }
        return mode == LifeWorkHistoryMode.ROUGH || linkedPeriods(today)?.size == employment.size
    }

    /** Where the earliest detailed job starts, which is when work began. */
    private fun earliestStart(periods: List<LifeEmploymentPeriod>) =
        periods.minWithOrNull(compareBy(nullsLast()) { LifeDates.anchor(it.startsOn) })?.startsOn

    /** The profile with this draft's fields written in, or null when it cannot save. */
    fun applied(profile: LifeProfile, today: LocalDate): LifeProfile? {
        if (!canSave(today)) return null
        val bornOn = bornYear.toIntOrNull()?.let(LifeDates::yearOnly)
        val retirementOn = bornOn?.let { born -> retirementAge.toIntOrNull()?.let { LifeDates.yearOnly(born.year + it) } }
        val detailed = linkedPeriods(today)
        if (mode == LifeWorkHistoryMode.DETAILED && detailed == null) return null
        val schoolStartedOn = (schoolYear.toIntOrNull() ?: bornOn?.year?.plus(6))?.let(LifeDates::yearOnly)
        val workStartedPartial = if (mode == LifeWorkHistoryMode.ROUGH) {
            (workYear.toIntOrNull() ?: bornOn?.year?.plus(22))?.let(LifeDates::yearOnly)
        } else {
            earliestStart(detailed.orEmpty())
        }
        val sleep = sleepHours.toDoubleOrNull()
        val sleepMinutes = sleep?.let { FoundationCompat.roundedHalfAwayFromZero(it * 60).toInt() }
        return profile.copy(
            bornOn = bornOn,
            schoolStartedOn = schoolStartedOn,
            workStartedPartial = workStartedPartial,
            retirementOn = retirementOn,
            birthYear = bornOn?.year,
            workStartedOn = workStartedPartial?.let(LifeDates::anchor)?.let(FoundationCompat::dayKey),
            retirementAge = retirementAge.toIntOrNull(),
            averageSleepHours = sleep,
            averageSleepMinutes = sleepMinutes,
            sleepSource = if (sleepMinutes != null) SleepSource.MANUAL else profile.sleepSource,
            workHistoryMode = mode,
            roughCurrentSalary = salaryOf(roughAmount, roughCadence),
            employmentPeriods = if (mode == LifeWorkHistoryMode.DETAILED && detailed != null) detailed else profile.employmentPeriods,
            futureIncomeDecline = if (declines) incomeDecline else null,
        )
    }

    fun endDate(index: Int): LocalDate? = employment[index].let { job ->
        if (job.linksEndToNext) employment.getOrNull(index - 1)?.startDate else job.endsOn?.let(LifeDates::anchor)
    }

    /** The range a job's start may take: after the older job's start, before the newer one's. */
    fun startRange(index: Int, today: LocalDate): Pair<LocalDate?, LocalDate> {
        val upper = if (index == 0) today else employment[index - 1].startDate.minusDays(1)
        val lower = employment.getOrNull(index + 1)?.startDate?.plusDays(1)?.takeIf { !it.isAfter(upper) }
        return lower to upper
    }

    /** An earlier job, a year before the oldest one. */
    fun addingEmployment(today: LocalDate, id: String) =
        copy(employment = employment + Employment(id, (employment.lastOrNull()?.startDate ?: today).minusYears(1)))

    companion object {
        fun salaryOf(amount: String, cadence: LifeSalaryCadence): LifeSalary? =
            NumberInput.committedText(amount, decimal = true, maxDigits = 12)?.let(NumberInput::parse)?.takeIf { it > 0 }?.let { LifeSalary(it, cadence) }

        private fun validOptionalYear(value: String) = value.isEmpty() ||
            NumberInput.committedText(value, decimal = false, maxDigits = 4)?.toIntOrNull()?.let { it in 1_000..9_999 } == true

        fun plain(value: Int) = value.toString()

        /** At most one decimal, no grouping, "." as separator: what the fields hold. */
        fun plain(value: Double): String = BigDecimal.valueOf(value).setScale(1, RoundingMode.HALF_EVEN).stripTrailingZeros().toPlainString()

        /**
         * The editor's fields from the stored profile. With no salary on file,
         * today's salary settings (as a monthly figure) fill the current one.
         */
        fun load(stored: LifeProfile?, today: LocalDate, configuredMonthly: Double?, newId: () -> String): LifeProfileDraft {
            val profile = stored?.let(RecordJson::migrateLegacyFields)
            val born = profile?.bornOn?.year ?: profile?.birthYear
            val work = profile?.workStartedPartial?.year ?: profile?.workStartedOn?.take(4)?.toIntOrNull()
            val retirementAge = when {
                born != null && profile?.retirementOn?.year != null -> plain(profile.retirementOn.year - born)
                profile?.retirementAge != null -> plain(profile.retirementAge)
                else -> "60"
            }
            val salary = profile?.roughCurrentSalary ?: profile?.employmentPeriods?.firstOrNull { it.endsOn == null }?.salary
            val (amount, cadence) = when {
                salary != null -> plain(salary.amount) to salary.cadence
                configuredMonthly != null && configuredMonthly > 0 -> plain(configuredMonthly) to LifeSalaryCadence.MONTHLY
                else -> "" to LifeSalaryCadence.MONTHLY
            }
            val linkedEndIds = LifeEmploymentTimeline.linkedEndIds(profile?.employmentPeriods.orEmpty())
            var employment = profile?.employmentPeriods.orEmpty().mapNotNull { period ->
                val start = LifeDates.anchor(period.startsOn) ?: return@mapNotNull null
                Employment(period.id, start, plain(period.salary.amount), period.salary.cadence,
                    wasCurrent = period.endsOn == null, endsOn = period.endsOn, linksEndToNext = period.id in linkedEndIds)
            }
            if (employment.none { it.wasCurrent }) {
                val current = profile?.roughCurrentSalary
                employment = employment + Employment(
                    newId(), LifeEmploymentTimeline.inferredCurrentStart(profile, today),
                    current?.let { plain(it.amount) } ?: "", current?.cadence ?: LifeSalaryCadence.MONTHLY,
                )
            }
            val decline = profile?.futureIncomeDecline
            return LifeProfileDraft(
                bornYear = born?.let(::plain) ?: "",
                schoolYear = profile?.schoolStartedOn?.year?.let(::plain) ?: "",
                workYear = work?.let(::plain) ?: "",
                retirementAge = retirementAge,
                sleepHours = profile?.averageSleepHours?.let(::plain) ?: "8",
                mode = profile?.workHistoryMode ?: LifeWorkHistoryMode.ROUGH,
                roughAmount = amount,
                roughCadence = cadence,
                employment = employment.sortedByDescending { it.startDate },
                declines = decline != null,
                declineAge = decline?.startsAtAge?.let(::plain) ?: "45",
                ratioPercent = decline?.let { plain(it.retirementRatio * 100) } ?: "60",
            )
        }
    }
}
