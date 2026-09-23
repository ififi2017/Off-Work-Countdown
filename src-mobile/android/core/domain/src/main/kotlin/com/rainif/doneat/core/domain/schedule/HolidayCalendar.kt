package com.rainif.doneat.core.domain.schedule

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Versioned, bundled national calendars (`HolidayTemplates.json`, shared with
 * iOS). No runtime network or date prediction: outside a region's covered
 * years there is simply no entry. Loaded once by the caller and passed in; the
 * rules never read a global.
 */
class HolidayCalendar private constructor(
    val datasetVersion: String,
    private val regions: Map<String, Region>,
) {
    data class Day(val isWorkday: Boolean, val names: Map<String, String>)

    private class Region(val years: IntRange, val days: Map<Int, Day>)

    val regionIdentifiers: List<String> get() = regions.keys.sorted()

    fun coveredThroughYear(regionIdentifier: String): Int? = regions[regionIdentifier]?.years?.last

    fun covers(year: Int, regionIdentifier: String) = regions[regionIdentifier]?.years?.contains(year) == true

    /** `dateCode` is `yyyymmdd`. */
    fun day(dateCode: Int, regionIdentifier: String): Day? = regions[regionIdentifier]?.days?.get(dateCode)

    /** Effects only, for transport to paired devices whose bundle may differ. */
    fun workdayOverrides(regionIdentifier: String): Map<Int, Boolean> =
        regions[regionIdentifier]?.days?.mapValues { it.value.isWorkday } ?: emptyMap()

    class InvalidDataset(message: String) : IllegalArgumentException(message)

    companion object {
        val EMPTY = HolidayCalendar("", emptyMap())

        /** Parses and validates the whole dataset; any malformed row rejects it. */
        fun parse(json: String): HolidayCalendar {
            val root = Json.parseToJsonElement(json).jsonObject
            fun fail(reason: String): Nothing = throw InvalidDataset(reason)
            if (root["schemaVersion"]?.jsonPrimitive?.int != 1) fail("schemaVersion")
            val version = root["datasetVersion"]?.jsonPrimitive?.content.orEmpty()
            if (version.isEmpty()) fail("datasetVersion")
            val names = root.getValue("names").jsonArray.map { entry ->
                entry.jsonObject.mapValues { it.value.jsonPrimitive.content }
            }
            val regions = root.getValue("regions").jsonObject.mapValues { (identifier, element) ->
                val source = element.jsonObject
                val from = source.getValue("coveredFromYear").jsonPrimitive.int
                val through = source.getValue("coveredThroughYear").jsonPrimitive.int
                if (identifier.isEmpty() || !isValidRegionIdentifier(identifier) || from > through) fail("region $identifier")
                val days = HashMap<Int, Day>()
                for (row in source.getValue("days").jsonArray) {
                    val values = row.jsonArray.map { it.jsonPrimitive.int }
                    if (values.size != 3 || values[1] !in 0..1 || values[2] !in names.indices ||
                        days.containsKey(values[0]) || !isValidDateCode(values[0]) || values[0] / 10_000 !in from..through
                    ) fail("row $identifier $values")
                    days[values[0]] = Day(values[1] == 1, names[values[2]])
                }
                Region(from..through, days)
            }
            return HolidayCalendar(version, regions)
        }

        /** Empty or absent means "no region"; otherwise two uppercase ASCII letters. */
        fun isValidRegionIdentifier(identifier: String?): Boolean {
            if (identifier.isNullOrEmpty()) return true
            return identifier.length == 2 && identifier.all { it in 'A'..'Z' }
        }

        fun isValidDateCode(value: Int): Boolean {
            val year = value / 10_000
            val month = value / 100 % 100
            val day = value % 100
            if (year !in 1..9_999 || month !in 1..12 || day !in 1..31) return false
            return CivilZone.civilDate(CivilZone.dayNumber(year, month, day)) == Triple(year, month, day)
        }
    }
}
