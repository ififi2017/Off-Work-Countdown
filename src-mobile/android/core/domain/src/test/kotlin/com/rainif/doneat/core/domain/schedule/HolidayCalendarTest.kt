package com.rainif.doneat.core.domain.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File

/** England and Wales dates checked against https://www.gov.uk/bank-holidays.json. */
class HolidayCalendarTest {
    private val holidays by lazy {
        HolidayCalendar.parse(File(System.getProperty("owc.holidayTemplates")).readText())
    }

    @Test fun englandAndWalesBankHolidaysMatchGovUk() {
        val expected = mapOf(
            20260406 to "Easter Monday",
            20260831 to "Summer Bank Holiday",
            20270329 to "Easter Monday",
            20270830 to "Summer Bank Holiday",
        )
        for ((date, name) in expected) {
            val day = holidays.day(date, "GB")
            assertEquals(name, day?.names?.get("en"))
            assertFalse(day!!.isWorkday)
        }
        // Scotland (2 January, St Andrew's Day) and Northern Ireland
        // (St Patrick's Day, 12 July) are not separate regions.
        assertNull(holidays.day(20260102, "GB"))
        assertNull(holidays.day(20261130, "GB"))
        assertNull(holidays.day(20260317, "GB"))
        assertNull(holidays.day(20260712, "GB"))
    }
}
