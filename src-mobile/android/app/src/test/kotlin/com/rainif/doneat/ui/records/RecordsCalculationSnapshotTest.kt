package com.rainif.doneat.ui.records

import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.SessionEnvironment
import com.rainif.doneat.core.domain.session.SessionState
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.settings.PreferencesRules
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class RecordsCalculationSnapshotTest {
    private val zone = ZoneId.of("UTC")
    private val today = LocalDate.parse("2026-10-16")
    private val now = today.atStartOfDay(zone).toInstant().toEpochMilli().toDouble()
    private fun queries(authorized: Boolean = true, state: RecordState = RecordState()) =
        RecordsQueries(state, HolidayCalendar.EMPTY, zone, authorized)

    @Test fun rebuildingPresentationContextKeepsTheExactResolvedPageAndEffectKey() {
        val q = queries()
        val before = RecordsCalculationSnapshot(q, now)
        val page = loadPage(before, RecordsScale.MONTH, today)
        // A new RecordsContext for an earnings mask / clock formatter creates a fresh key value,
        // while retaining the same queries and minute. It must not enter a loading placeholder.
        val after = RecordsCalculationSnapshot(q, now)
        assertNotSame(before, after)
        assertEquals(before, after) // LaunchedEffect equality: no reload.
        assertSame(page, page.takeIf { it.matches(after, RecordsScale.MONTH, today.withDayOfMonth(1)) })
        assertSame(page.cells, page.takeIf { it.matches(after, RecordsScale.MONTH, today.withDayOfMonth(1)) }!!.cells)
    }

    @Test fun authorizationWithdrawalRejectsTheOldPageBeforeRedactedReplacementIsReady() {
        val old = loadPage(RecordsCalculationSnapshot(queries(), now), RecordsScale.MONTH, today)
        val revoked = RecordsCalculationSnapshot(queries(authorized = false), now)
        assertFalse(old.matches(revoked, RecordsScale.MONTH, today.withDayOfMonth(1)))
        val replacement = loadPage(revoked, RecordsScale.MONTH, today)
        assertNull(replacement.headline)
        assertTrue(replacement.cells.filter { it.date < today.minusDays(6) }.all {
            it.appearance == RecordsDayAppearance.LOCKED && it.workMs == 0L && it.overtimeMs == 0L && !it.hasConflict
        })
        assertTrue(RecordsScale.YEAR.requiresPlus)
        assertTrue(RecordsScale.LIFE.requiresPlus)
    }

    @Test fun newArchiveQueryMinuteScaleAndWindowInvalidateThePage() {
        val q = queries()
        val page = loadPage(RecordsCalculationSnapshot(q, now), RecordsScale.MONTH, today)
        val first = today.withDayOfMonth(1)
        assertFalse(page.matches(RecordsCalculationSnapshot(queries(), now), RecordsScale.MONTH, first))
        assertFalse(page.matches(RecordsCalculationSnapshot(q, now + 60_000), RecordsScale.MONTH, first))
        assertFalse(page.matches(RecordsCalculationSnapshot(q, now), RecordsScale.WEEK, first))
        assertFalse(page.matches(RecordsCalculationSnapshot(q, now), RecordsScale.MONTH, first.plusMonths(1)))
    }

    @Test fun aMinuteTickKeepsThePreviousPageOnScreenUntilTheNewOneLoads() {
        val source = Any()
        val page = loadPage(RecordsCalculationSnapshot(queries(), now, source), RecordsScale.MONTH, today)
        val first = today.withDayOfMonth(1)
        // The queries are rebuilt every minute; only the source token says the business inputs held still.
        val nextMinute = RecordsCalculationSnapshot(queries(), now + 60_000, source)
        assertFalse(page.matches(nextMinute, RecordsScale.MONTH, first)) // Still reloads, so today's marks advance.
        assertTrue(page.standsIn(nextMinute, RecordsScale.MONTH, first))
        assertFalse(page.standsIn(nextMinute, RecordsScale.WEEK, first))
        assertFalse(page.standsIn(nextMinute, RecordsScale.MONTH, first.plusMonths(1)))
    }

    @Test fun aDataOrAccessChangeNeverLetsThePreviousPageStandIn() {
        val source = Any()
        val page = loadPage(RecordsCalculationSnapshot(queries(), now, source), RecordsScale.MONTH, today)
        val first = today.withDayOfMonth(1)
        val archived = RecordsCalculationSnapshot(queries(), now, Any())
        assertFalse(page.standsIn(archived, RecordsScale.MONTH, first))
        // Revoked Plus never shows old data, even if a caller reused the token.
        val revoked = RecordsCalculationSnapshot(queries(authorized = false), now + 60_000, source)
        assertFalse(page.standsIn(revoked, RecordsScale.MONTH, first))
        // Without an explicit token each query revision is its own source.
        val q = queries()
        val plain = loadPage(RecordsCalculationSnapshot(q, now), RecordsScale.MONTH, today)
        assertTrue(plain.standsIn(RecordsCalculationSnapshot(q, now + 60_000), RecordsScale.MONTH, first))
        assertFalse(plain.standsIn(RecordsCalculationSnapshot(queries(), now + 60_000), RecordsScale.MONTH, first))
    }

    @Test fun lifeRawSnapshotRetainsItsAllocationAndIncomeUntilBusinessInputsOrAccessChange() {
        val preferences = PreferencesRules.defaults("UTC", now)
        val session = ShiftSession(SessionState(), SessionEnvironment(preferences, true, null, emptyList(), HolidayCalendar.EMPTY, "UTC"))
        val inputs = LifeInputs(RecordState(), preferences, HolidayCalendar.EMPTY, session, today)
        val allocation = TimeAllocationShare(workMs = 3_600_000, freeMs = 3_600_000, dayLengthMs = 7_200_000)
        val income = com.rainif.doneat.core.domain.summary.SummaryRules.LifetimeIncome(12_000.0, 24_000.0, 36_000.0)
        val model = LifeViewModel(emptyList(), .5, .5, income = income, allocation = allocation)
        val snapshot = RecordsLifeSnapshot(inputs, model)
        // Presentation-only recomposition rebuilds equal calculation inputs, with no mask stored in them.
        val recomposedInputs = LifeInputs(inputs.archive, preferences, inputs.holidays, session, today)
        assertEquals(inputs, recomposedInputs)
        assertSame(model, snapshot.takeIf { it.matches(recomposedInputs, authorized = true) }!!.model)
        assertSame(allocation, snapshot.model!!.allocation)
        assertSame(income, snapshot.model!!.income)
        assertFalse(snapshot.matches(recomposedInputs, authorized = false))
        assertFalse(snapshot.matches(inputs.copy(today = today.plusDays(1)), authorized = true))
        assertFalse(snapshot.matches(inputs.copy(preferences = preferences.copy(salaryEnabled = !preferences.salaryEnabled)), authorized = true))
    }
}
