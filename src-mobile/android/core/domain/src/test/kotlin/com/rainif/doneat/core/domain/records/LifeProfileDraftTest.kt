package com.rainif.doneat.core.domain.records

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** iOS `LifeEmploymentTimelineTests`, and the editor's load, validation and save. */
class LifeProfileDraftTest {
    private val today = LocalDate.of(2026, 9, 6)
    private var ids = 0
    private fun newId() = "00000000-0000-4000-8000-%012d".format(++ids)
    private fun exact(year: Int, month: Int, day: Int) = LifeDates.exact(year, month, day)!!
    private fun monthly(amount: Double) = LifeSalary(amount, LifeSalaryCadence.MONTHLY)

    @Test fun theTimelineSortsNewestFirstAndLinksEveryEarlierEnd() {
        val current = monthly(12_345.0)
        val periods = listOf(
            LifeEmploymentPeriod("middle", exact(2022, 2, 1), exact(2024, 4, 1), monthly(8_000.0)),
            LifeEmploymentPeriod("current", exact(2024, 5, 1), exact(2025, 1, 1), current),
            LifeEmploymentPeriod("older", exact(2019, 3, 1), exact(2020, 1, 1), monthly(6_000.0)),
        )
        val linked = LifeEmploymentTimeline.linkedPeriods(periods, today)!!
        assertEquals(listOf("current", "middle", "older"), linked.map { it.id })
        assertEquals(listOf(current, periods[0].salary, periods[2].salary), linked.map { it.salary })
        assertNull(linked[0].endsOn)
        assertEquals(linked[0].startsOn, linked[1].endsOn)
        assertEquals(linked[1].startsOn, linked[2].endsOn)
    }

    @Test fun olderHistoryResumesAtTheLatestPriorEnd() {
        val profile = LifeProfiles.blank(0.0, ::newId).copy(
            workStartedPartial = exact(2018, 1, 1),
            employmentPeriods = listOf(
                LifeEmploymentPeriod("a", exact(2020, 1, 1), exact(2022, 1, 1), monthly(10_000.0)),
                LifeEmploymentPeriod("b", exact(2022, 1, 1), exact(2024, 5, 1), monthly(10_000.0)),
            ),
        )
        assertEquals(LocalDate.of(2024, 5, 1), LifeEmploymentTimeline.inferredCurrentStart(profile, today))
    }

    @Test fun theTimelineRejectsAFutureStartAndDuplicateStarts() {
        assertNull(LifeEmploymentTimeline.linkedPeriods(listOf(LifeEmploymentPeriod("a", exact(2027, 1, 1), null, monthly(10_000.0))), today))
        val start = exact(2025, 1, 1)
        assertNull(
            LifeEmploymentTimeline.linkedPeriods(
                listOf(LifeEmploymentPeriod("a", start, null, monthly(10_000.0)), LifeEmploymentPeriod("b", start, null, monthly(10_000.0))), today,
            ),
        )
    }

    @Test fun aNewDraftOffersTodaysSalaryAndDefaults() {
        val draft = LifeProfileDraft.load(null, today, configuredMonthly = 18_500.0, newId = ::newId)
        assertEquals("60", draft.retirementAge)
        assertEquals("8", draft.sleepHours)
        assertEquals("18500", draft.roughAmount)
        assertEquals(1, draft.employment.size)
        assertEquals(today, draft.employment.single().startDate)
        assertTrue(draft.canSave(today))
    }

    @Test fun validationFollowsTheEditor() {
        val base = LifeProfileDraft(bornYear = "1990")
        assertTrue(base.canSave(today))
        assertFalse(base.copy(bornYear = "90").canSave(today))
        assertFalse(base.copy(retirementAge = "0").canSave(today))
        assertFalse(base.copy(sleepHours = "").canSave(today))
        assertFalse("a salary that is not a number", base.copy(roughAmount = "0").canSave(today))
        assertFalse("the step down must come before retirement", base.copy(declines = true, declineAge = "60").canSave(today))
        assertTrue(base.copy(declines = true, declineAge = "45", ratioPercent = "60").canSave(today))
        assertFalse("detailed needs the current salary", base.copy(mode = LifeWorkHistoryMode.DETAILED, employment = listOf(LifeProfileDraft.Employment("c", today))).canSave(today))
    }

    @Test fun savingWritesTheFieldsAsIOSDoes() {
        val draft = LifeProfileDraft(bornYear = "1990", retirementAge = "62", sleepHours = "7.5", roughAmount = "12000", declines = true)
        val saved = draft.applied(LifeProfiles.blank(0.0, ::newId), today)!!
        assertEquals(LifeDates.yearOnly(1990), saved.bornOn)
        assertEquals(1990, saved.birthYear)
        assertEquals(LifeDates.yearOnly(1996), saved.schoolStartedOn)
        assertEquals(LifeDates.yearOnly(2012), saved.workStartedPartial)
        assertEquals("2012-07-01", saved.workStartedOn)
        assertEquals(LifeDates.yearOnly(2052), saved.retirementOn)
        assertEquals(450, saved.averageSleepMinutes)
        assertEquals(SleepSource.MANUAL, saved.sleepSource)
        assertEquals(monthly(12_000.0), saved.roughCurrentSalary)
        assertEquals(LifeIncomeDecline(45, 0.6), saved.futureIncomeDecline)
        // Loading what was saved shows the same fields again.
        val reloaded = LifeProfileDraft.load(saved, today, null, ::newId)
        assertEquals(draft.bornYear, reloaded.bornYear)
        assertEquals(draft.retirementAge, reloaded.retirementAge)
        assertEquals(draft.sleepHours, reloaded.sleepHours)
        assertEquals(draft.roughAmount, reloaded.roughAmount)
        assertTrue(reloaded.declines)
    }

    @Test fun aDetailedHistorySavesLinkedJobsAndStartsWorkAtTheEarliest() {
        var draft = LifeProfileDraft(bornYear = "1990", mode = LifeWorkHistoryMode.DETAILED, roughAmount = "15000", employment = listOf(LifeProfileDraft.Employment("now", LocalDate.of(2024, 5, 1))))
        draft = draft.addingEmployment(today, "older").let { it.copy(employment = it.employment.map { e -> if (e.id == "older") e.copy(amount = "9000") else e }) }
        assertEquals(LocalDate.of(2023, 5, 1), draft.employment.last().startDate)
        assertEquals(LocalDate.of(2023, 5, 2) to LocalDate.of(2026, 9, 6), draft.startRange(0, today))
        val saved = draft.applied(LifeProfiles.blank(0.0, ::newId), today)!!
        assertEquals(listOf("now", "older"), saved.employmentPeriods.map { it.id })
        assertEquals(exact(2024, 5, 1), saved.employmentPeriods[1].endsOn)
        assertEquals(exact(2023, 5, 1), saved.workStartedPartial)
    }
}
