package com.rainif.doneat.core.domain.schedule

import com.rainif.doneat.core.domain.SharedRuleFixtures
import com.rainif.doneat.core.domain.asDouble
import com.rainif.doneat.core.domain.bool
import com.rainif.doneat.core.domain.compareSnapshot
import com.rainif.doneat.core.domain.double
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.string
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.time.ZoneId
import java.util.UUID

/**
 * Holds the Kotlin extended-schedule port to the Swift implementation's own
 * answers (`npm run generate:android-extended-fixtures`, macOS). Extended
 * scheduling has no TypeScript oracle: a failure means Kotlin and
 * `src-mobile/ios/Shared` disagree, and the Swift is the specification.
 */
class ExtendedScheduleFixtureTest {
    private companion object {
        val root: JsonObject by lazy {
            val text = checkNotNull(ExtendedScheduleFixtureTest::class.java.getResource("/extended-schedule-fixtures.json")) {
                "extended-schedule-fixtures.json missing; run npm run generate:android-extended-fixtures on macOS"
            }.readText()
            Json.parseToJsonElement(text).jsonObject
        }
        val data: JsonObject get() = root.getValue("data").jsonObject

        val holidays: HolidayCalendar by lazy {
            HolidayCalendar.parse(File(System.getProperty("owc.holidayTemplates")).readText())
        }

        val plans: Map<String, ExtendedSchedulePlan> by lazy {
            val built = LinkedHashMap<String, ExtendedSchedulePlan>()
            for (row in section("plans")) built[row.string("name")!!] = plan(row.getValue("recipe").jsonObject, built)
            built
        }

        val bases = mapOf(
            "classic" to ScheduleHours("09:00", "17:00", listOf(1, 2, 3, 4, 5), WorkSchedule(ScheduleMode.CLASSIC), "12:00", 60),
            "manual" to ScheduleHours("08:00", "16:00", emptyList(), WorkSchedule(ScheduleMode.OFF), null, 0),
        )
        val salary = SalarySettings("22000", SalaryType.MONTHLY, 21.75, 1.0)

        fun section(name: String) = data.getValue(name).jsonArray.map { it.jsonObject }

        fun uuid(e: JsonElement) = UUID.fromString(e.jsonPrimitive.content)

        fun shiftType(e: JsonElement): ShiftType {
            val o = e.jsonObject
            return ShiftType(
                id = uuid(o.getValue("id")),
                name = o.string("name")!!,
                kind = ShiftType.Kind.fromRaw(o.string("kind")!!),
                startMinutes = o.getValue("startMinutes").jsonPrimitive.int,
                endMinutes = o.getValue("endMinutes").jsonPrimitive.int,
                breakEnabled = o.bool("breakEnabled"),
                breakStartMinutes = o.getValue("breakStartMinutes").jsonPrimitive.int,
                breakDurationMinutes = o.getValue("breakDurationMinutes").jsonPrimitive.int,
                colorHex = o.string("colorHex")!!,
                isArchived = o.bool("isArchived"),
            )
        }

        fun rule(e: JsonElement?): ShiftCycleRule? {
            if (e == null || e is JsonNull) return null
            val o = e.jsonObject
            return ShiftCycleRule(
                ShiftCycleRule.Preset.fromRaw(o.string("preset")!!),
                o.string("anchorDayKey")!!,
                o.getValue("days").jsonArray.map(::uuid),
            )
        }

        fun roster(e: JsonElement): RosterDay {
            val o = e.jsonObject
            val frozen = o.getValue("assignedShiftType")
            return RosterDay(o.string("dayKey")!!, uuid(o.getValue("shiftTypeID")), if (frozen is JsonNull) null else shiftType(frozen))
        }

        fun plan(r: JsonObject, built: Map<String, ExtendedSchedulePlan>): ExtendedSchedulePlan = when (r.string("kind")) {
            "direct" -> ExtendedSchedulePlan(
                shiftTypes = r.getValue("shiftTypes").jsonArray.map(::shiftType),
                rule = rule(r["rule"]),
                handSetDays = r.getValue("handSetDays").jsonObject.mapValues { uuid(it.value) },
                holidayRegionIdentifier = r.string("holidayRegionIdentifier"),
                clearedFromDayKey = r.string("clearedFromDayKey"),
                holidayOverrides = r["holidayOverrides"]?.takeIf { it !is JsonNull }?.jsonObject
                    ?.entries?.associate { it.key.toInt() to it.value.jsonPrimitive.boolean },
                holidays = holidays,
            )
            "historical" -> ExtendedSchedulePlan.historical(
                rosterDays = r.getValue("rosterDays").jsonArray.map(::roster),
                legacyShiftTypes = r.getValue("legacyShiftTypes").jsonArray.map(::shiftType),
                includesLegacyRows = r.bool("includesLegacyRows"),
            )!!
            "schedule" -> ExtendedSchedulePlan.of(
                ExtendedSchedule(
                    isEnabled = true,
                    content = ExtendedScheduleContent(
                        shiftTypes = r.getValue("shiftTypes").jsonArray.map(::shiftType),
                        rule = rule(r["rule"]),
                        holidayRegionIdentifier = r.string("holidayRegionIdentifier"),
                        clearedFromDayKey = r.string("clearedFromDayKey"),
                    ),
                ),
                r.getValue("rosterDays").jsonArray.map(::roster),
                holidays,
            )!!
            "pinned" -> {
                val h = r.getValue("hours").jsonObject
                built.getValue(r.string("base")!!).pinning(
                    r.string("dayKey")!!,
                    ExtendedScheduleDayHours(h.string("startTime")!!, h.string("endTime")!!, h.string("breakStartTime"), h.getValue("breakDurationMinutes").jsonPrimitive.int),
                )
            }
            else -> error("unknown recipe ${r.string("kind")}")
        }

        fun input(row: JsonObject, now: Double = row.double("now")!!, base: String = row.string("base")!!) = ScheduleRuleInput(
            hours = bases.getValue(base).copy(extended = plans.getValue(row.string("plan")!!)),
            nowMs = now,
            zone = ZoneId.of(row.string("zone")!!),
            overtimeEndAtMs = row.double("ot"),
            forcedWorkdayStartMs = row.double("forced"),
        )

        fun segments(e: JsonElement) = e.jsonArray.map { pair ->
            val (start, end) = pair.jsonArray.map { it.asDouble()!! }
            ShiftSegment(start, end)
        }
    }

    @Test
    fun bundledHolidaysMatchTheFixture() {
        assertEquals(data.string("holidayDataset"), holidays.datasetVersion)
    }

    @Test
    fun dayResolution() {
        val failures = ArrayList<String>()
        var count = 0
        for (row in section("days")) {
            val name = row.string("plan")!!
            val resolver = ExtendedScheduleResolver(plans.getValue(name))
            for (day in row.getValue("days").jsonArray) {
                val (key, isWorkday, hours, typeID, source) = day.jsonArray
                val actual = resolver.day(ExtendedScheduleResolver.dayNumber(key.jsonPrimitive.content)!!)
                val expected = ExtendedScheduleDay(
                    isWorkday = isWorkday.jsonPrimitive.boolean,
                    hours = if (hours is JsonNull) null else hours.jsonArray.let { h ->
                        ExtendedScheduleDayHours(h[0].jsonPrimitive.content, h[1].jsonPrimitive.content, h[2].let { if (it is JsonNull) null else it.jsonPrimitive.content }, h[3].jsonPrimitive.int)
                    },
                    shiftTypeID = if (typeID is JsonNull) null else uuid(typeID),
                    source = ExtendedScheduleDay.Source.entries.first { it.raw == source.jsonPrimitive.content },
                )
                count++
                if (actual != expected && failures.size < 8) failures += "$name ${key.jsonPrimitive.content}: expected $expected, actual $actual"
            }
        }
        assertTrue("day cases: $count", count > 2_000)
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
    }

    @Test
    fun snapshots() {
        val cases = section("snapshots")
        val failures = ArrayList<String>()
        for (row in cases) {
            val mismatch = compareSnapshot(ScheduleRules.snapshot(input(row), salary), row.getValue("expected").jsonArray) ?: continue
            if (failures.size < 6) failures += "${row.string("plan")} ${row.string("zone")} ${row.string("base")} at ${row.double("now")}: $mismatch"
        }
        assertTrue(cases.size > 1_000)
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
    }

    @Test
    fun widgetShifts() {
        for (row in section("widgetShifts")) {
            val actual = ScheduleRules.widgetShifts(input(row), row.double("through")!!, row.getValue("max").jsonPrimitive.int)
            val expected = row.getValue("expected").jsonArray.map { e ->
                val a = e.jsonArray
                WidgetShift(segments(a[0]), a[1].asDouble()!!, a[2].asDouble()!!, a[3].asDouble()!!, a[4].asDouble(), a[5].asDouble()!!, a[6].asDouble()!!)
            }
            assertEquals("widget ${row.string("plan")} ${row.string("zone")} ${row.string("base")}", expected, actual)
        }
    }

    @Test
    fun expansions() {
        for (row in section("expansions")) {
            val hours = bases.getValue(row.string("base")!!).copy(extended = plans.getValue(row.string("plan")!!))
            val actual = ScheduleRules.expandScheduleRange(hours, row.double("from")!!, row.double("through")!!, ZoneId.of(row.string("zone")!!))
            val expected = row.getValue("expected").jsonArray.map { e ->
                val a = e.jsonArray
                ScheduleDayExpansion(a[0].jsonPrimitive.content, a[1].asDouble()!!, a[2].jsonPrimitive.boolean, segments(a[3]))
            }
            assertEquals("expansion ${row.string("plan")} ${row.string("zone")} ${row.string("base")}", expected, actual)
        }
    }

    @Test
    fun breaksAndApplyToday() {
        for (row in section("validateBreak")) {
            assertEquals("break ${row.string("plan")} ${row.string("zone")}", row.bool("expected"), ScheduleRules.validateBreak(input(row)))
        }
        for (row in section("applyToday")) {
            val base = row.string("base")!!
            val other = if (base == "classic") "manual" else "classic"
            assertEquals(
                "apply today ${row.string("plan")} ${row.string("zone")} $base",
                row.bool("expected"),
                ScheduleRules.shouldPromptApplyToday(input(row), input(row, base = other)),
            )
        }
    }

    /** The raw window early in the morning, which `resolveCurrentShift`'s settlement would otherwise mask. */
    @Test
    fun liveWindows() {
        val options = ShiftOptions(breakStartTime = "12:00", breakDurationMinutes = 60)
        var count = 0
        for (row in section("timelines")) {
            val zone = CivilZone(ZoneId.of(row.string("zone")!!), ExtendedScheduleResolver(plans.getValue(row.string("plan")!!)))
            for (e in row.getValue("expected").jsonArray) {
                val a = e.jsonArray
                val now = a[0].asDouble()!!
                val actual = zone.shiftTimeline("09:00", "17:00", now, options)
                assertEquals("window ${row.string("plan")} ${row.string("zone")} at $now", segments(a[1]), actual.segments)
                assertEquals(a[2].asDouble()!!, actual.plannedEndAtMs, 0.0)
                count++
            }
        }
        assertTrue(count > 1_000)
    }

    @Test
    fun plannedHours() {
        for (row in section("plannedHours")) {
            val zone = CivilZone(ZoneId.of(row.string("zone")!!), ExtendedScheduleResolver(plans.getValue(row.string("plan")!!)))
            val first = ExtendedScheduleResolver.dayNumber(row.string("fromDayKey")!!)!!
            val actual = (first until first + 40).map { zone.plannedHours(it) }
            val expected = row.getValue("expected").jsonArray.map { it.asDouble() }
            assertEquals("planned hours ${row.string("plan")} ${row.string("zone")}", expected, actual)
        }
    }

    @Test
    fun validation() {
        for (row in section("shiftTypeValidity")) {
            val type = shiftType(row.getValue("type"))
            assertEquals("type '${type.name}' ${type.colorHex}", row.bool("expected"), type.isValid)
        }
        for (row in section("dayKeys")) {
            assertEquals("day key '${row.string("dayKey")}'", row.double("expected")?.toInt(), ExtendedScheduleResolver.dayNumber(row.string("dayKey")!!))
        }
        for (row in section("contentValidity")) {
            val content = ExtendedScheduleContent(
                shiftTypes = row.getValue("shiftTypes").jsonArray.map(::shiftType),
                rule = rule(row["rule"]),
                holidayRegionIdentifier = row.string("holidayRegionIdentifier"),
                clearedFromDayKey = row.string("clearedFromDayKey"),
            )
            assertEquals("content ${row.string("name")}", row.bool("expected"), content.isValid)
        }
    }
}

private operator fun JsonArray.component5() = this[4]
