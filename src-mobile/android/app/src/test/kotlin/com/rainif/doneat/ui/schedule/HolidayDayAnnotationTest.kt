package com.rainif.doneat.ui.schedule

import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.util.Locale

class HolidayDayAnnotationTest {
    private val calendar = HolidayCalendar.parse("""{
        "schemaVersion":1,"datasetVersion":"test",
        "names":[{"en":"Spring Festival","zh-CN":"春节","zh-TW":"春節","zh-HK":"農曆新年"},{"en":"New Year's Day"}],
        "regions":{
          "CN":{"coveredFromYear":2026,"coveredThroughYear":2027,"estimatedYears":[2027],"days":[[20260217,0,0],[20270131,1,0],[20270205,0,0]]},
          "US":{"coveredFromYear":2027,"coveredThroughYear":2027,"days":[[20270101,0,1]]}
        }
    }""")

    @Test fun `makeup days name the festival and distinguish predicted workdays`() {
        val annotation = holidayDayAnnotation(calendar, "CN", LocalDate.of(2027, 1, 31), Locale.forLanguageTag("zh-Hans-CN"))!!
        assertEquals("春节", annotation.name)
        assertTrue(annotation.isMakeupWorkday)
        assertTrue(annotation.isEstimated)
        assertEquals("春节 · 调休上班 · 推测", annotation.description("调休上班", "推测"))
    }

    @Test fun `holiday facts stay distinct from workday and certainty labels`() {
        val confirmed = holidayDayAnnotation(calendar, "CN", LocalDate.of(2026, 2, 17), Locale.ENGLISH)!!
        assertEquals("Spring Festival", confirmed.description("Makeup workday", "Estimated"))
        val predicted = holidayDayAnnotation(calendar, "CN", LocalDate.of(2027, 2, 5), Locale.ENGLISH)!!
        assertEquals("Spring Festival · Estimated", predicted.description("Makeup workday", "Estimated"))
        assertFalse(predicted.isMakeupWorkday)
        val us = holidayDayAnnotation(calendar, "US", LocalDate.of(2027, 1, 1), Locale.ENGLISH)!!
        assertEquals("New Year's Day", us.description("Makeup workday", "Estimated"))
    }

    @Test fun `script qualified Chinese locales keep their regional names`() {
        val day = calendar.day(20270131, "CN")!!
        assertEquals("春節", localizedHolidayName(day, Locale.forLanguageTag("zh-Hant-TW")))
        assertEquals("農曆新年", localizedHolidayName(day, Locale.forLanguageTag("zh-Hant-HK")))
        assertEquals("春節", localizedHolidayName(day, Locale.forLanguageTag("zh-Hant")))
        assertEquals("Spring Festival", localizedHolidayName(day, Locale.FRENCH))
    }

    @Test fun `ordinary uncovered and disabled region days have no annotation`() {
        val date = LocalDate.of(2027, 1, 31)
        assertNull(holidayDayAnnotation(calendar, "CN", date.plusDays(1), Locale.ENGLISH))
        assertNull(holidayDayAnnotation(calendar, "CN", date.plusYears(1), Locale.ENGLISH))
        assertNull(holidayDayAnnotation(calendar, null, date, Locale.ENGLISH))
        assertNull(holidayDayAnnotation(calendar, "", date, Locale.ENGLISH))
    }
}
