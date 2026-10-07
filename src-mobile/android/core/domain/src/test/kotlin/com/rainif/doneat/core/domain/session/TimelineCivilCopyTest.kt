package com.rainif.doneat.core.domain.session

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TimelineCivilCopyTest {
    private val shanghai = ZoneId.of("Asia/Shanghai")
    private fun at(iso: String) = Instant.parse(iso).toEpochMilli().toDouble()

    @Test fun `today uses the countdown civil day across UTC midnight`() {
        val now = at("2026-09-21T23:00:00Z")
        val start = at("2026-09-22T01:00:00Z")
        assertEquals(TimelineCivilCopy.TODAY, TimelineCivilCopy.startDetailKey(start, now, shanghai))
        assertNull(TimelineCivilCopy.startDetailKey(start, now, ZoneId.of("UTC")))
    }

    @Test fun `future start only carries a caller supplied known status`() {
        val now = at("2026-09-21T00:00:00Z")
        val tomorrow = at("2026-09-22T01:00:00Z")
        assertNull(TimelineCivilCopy.startDetailKey(tomorrow, now, shanghai))
        assertEquals(TimelineCivilCopy.CURRENT_MONTH, TimelineCivilCopy.startDetailKey(tomorrow, now, shanghai,
            TimelineCivilCopy.knownRosterStatusKey(tomorrow, now, shanghai, known = true)))
        assertNull(TimelineCivilCopy.knownRosterStatusKey(tomorrow, now, shanghai, known = false))
    }

    @Test fun `month horizons cross year boundary and do not imply distant coverage`() {
        val now = at("2026-12-31T15:00:00Z")
        val next = at("2026-12-31T17:00:00Z")
        assertEquals(TimelineCivilCopy.NEXT_MONTH, TimelineCivilCopy.knownRosterStatusKey(next, now, shanghai, true))
        assertNull(TimelineCivilCopy.knownRosterStatusKey(at("2027-02-01T01:00:00Z"), now, shanghai, true))
    }

    @Test fun `end is today only for current live shift which started on this civil day`() {
        val start = at("2026-09-21T01:00:00Z")
        val now = at("2026-09-21T08:00:00Z")
        val end = at("2026-09-21T09:00:00Z")
        assertEquals(TimelineCivilCopy.TODAY, TimelineCivilCopy.endDetailKey(end, start, end, false, now, shanghai))
        assertNull(TimelineCivilCopy.endDetailKey(end, start, end, true, now, shanghai))
        assertNull(TimelineCivilCopy.endDetailKey(end, start, end, false, end, shanghai))
        assertNull(TimelineCivilCopy.endDetailKey(at("2026-09-22T09:00:00Z"), start, end, false, now, shanghai))
    }

    @Test fun `overnight end does not label yesterdays start as today`() {
        val start = at("2026-09-21T15:00:00Z")
        val end = at("2026-09-21T21:00:00Z")
        assertEquals(TimelineCivilCopy.TODAY, TimelineCivilCopy.endDetailKey(end, start, end, false,
            at("2026-09-21T15:30:00Z"), shanghai))
        assertNull(TimelineCivilCopy.endDetailKey(end, start, end, false,
            at("2026-09-21T17:00:00Z"), shanghai))
    }
}
