package com.rainif.doneat.core.domain.widget

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Test

/** Actual Swift outputs at ffd91597, with exact source hashes in the pinned fixture. */
class WidgetSuiteOracleFixtureTest {
    private val fixture = Json.parseToJsonElement(javaClass.getResource("/widget-suite-ios-scalars.json")!!.readText()).jsonObject
    private fun JsonObject.long(key: String) = getValue(key).jsonPrimitive.long
    private fun JsonObject.double(key: String) = getValue(key).jsonPrimitive.double
    private fun at(day: String, hour: Int = 0) = LocalDate.parse(day).atTime(hour, 0).atZone(ZoneId.of("UTC")).toInstant().toEpochMilli()

    @Test fun weekProgressMatchesCompiledSwiftAcrossLunchAndAnOvernightShift() {
        val monday = WidgetCalendarDay("2026-10-26", at("2026-10-26"), WidgetCalendarDayKind.WORK,
            segments = listOf(WidgetTimeSegment(at("2026-10-26", 9), at("2026-10-26", 12)), WidgetTimeSegment(at("2026-10-26", 13), at("2026-10-26", 17))))
        val tuesday = WidgetCalendarDay("2026-10-27", at("2026-10-27"), WidgetCalendarDayKind.WORK,
            segments = listOf(WidgetTimeSegment(at("2026-10-27", 22), at("2026-10-28", 6))))
        val wednesday = WidgetCalendarDay("2026-10-28", at("2026-10-28"), WidgetCalendarDayKind.REST)
        val payload = WidgetCalendarPayload("UTC", 1, WidgetCalendarScheduleKind.WEEKLY, listOf(monday, tuesday, wednesday))
        for (element in fixture.getValue("week").jsonArray) {
            val e = element.jsonObject
            val actual = WidgetWeekProgress.from(payload, e.long("nowMs"))
            assertEquals(e.long("totalMs"), actual.totalMs)
            assertEquals(e.long("remainingMs"), actual.remainingMs)
            assertEquals(e.double("remainingDays"), actual.remainingDays, 0.0000001)
            assertEquals(e.double("progress"), actual.progress, 0.0000001)
        }
    }

    @Test fun calendarProgressMatchesCompiledSwiftOnBothDstTransitionDays() {
        for (element in fixture.getValue("calendar").jsonArray) {
            val e = element.jsonObject
            val actual = WidgetCalendarProgress.at(e.long("nowMs"), ZoneId.of("America/Los_Angeles"), DayOfWeek.SUNDAY)
            assertEquals(e.double("today"), actual.today, 0.0000001)
            assertEquals(e.double("week"), actual.week, 0.0000001)
            assertEquals(e.double("month"), actual.month, 0.0000001)
            assertEquals(e.double("year"), actual.year, 0.0000001)
            assertEquals(e.long("daysLeftInYear").toInt(), actual.daysLeftInYear)
        }
    }

    @Test fun lifeFiguresMatchCompiledSwiftAtUtcAndBothPositiveDatelineZones() {
        for (element in fixture.getValue("life").jsonArray) {
            val e = element.jsonObject
            val today = e.long("todayOrdinal")
            val payload = WidgetLifePayload(WidgetAccess(true), bornDay = today - 10_000, careerStartDay = today - 1_000, retirementDay = today + 2_000)
            val actual = WidgetLifeFigures.from(payload, e.long("nowMs"), ZoneId.of(e.getValue("zone").jsonPrimitive.content))!!
            assertEquals(e.long("daysLived"), actual.daysLived)
            assertEquals(e.double("lifeShare"), actual.lifeShare, 0.0000001)
            assertEquals(e.double("careerShare"), actual.careerShare!!, 0.0000001)
            assertEquals(e.long("ageMonths").toInt(), actual.ageMonths)
            assertEquals(e.long("monthsWorked").toInt(), actual.monthsWorked)
            assertEquals(e.long("monthsToRetirement").toInt(), actual.monthsToRetirement)
        }
    }
}
