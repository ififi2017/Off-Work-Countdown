package com.rainif.doneat.core.domain

import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.WorkSchedule
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
import java.security.MessageDigest
import java.time.ZoneId
import kotlin.math.abs

/** The TypeScript-oracle cases, parsed once per test JVM. */
object SharedRuleFixtures {
    val root: JsonObject by lazy {
        val text = checkNotNull(javaClass.getResource("/shared-rule-fixtures.json")) {
            "shared-rule-fixtures.json missing; run npm run generate:android-rule-fixtures"
        }.readText()
        Json.parseToJsonElement(text).jsonObject
    }

    val data: JsonObject get() = root.getValue("data").jsonObject

    fun section(name: String): List<JsonObject> = data.getValue(name).jsonArray.map { it.jsonObject }

    data class Profile(val id: String, val hours: ScheduleHours, val zone: ZoneId)

    val profiles: List<Profile> by lazy {
        section("profiles").map { p ->
            Profile(
                id = p.string("id")!!,
                hours = ScheduleHours(
                    startTime = p.string("startTime")!!,
                    endTime = p.string("endTime")!!,
                    workdays = p.getValue("workdays").jsonArray.map { it.jsonPrimitive.int },
                    schedule = workSchedule(p.getValue("schedule").jsonObject),
                    breakStartTime = p.string("breakStartTime"),
                    breakDurationMinutes = p.getValue("breakDurationMinutes").jsonPrimitive.int,
                ),
                zone = ZoneId.of(p.string("timeZoneIdentifier")!!),
            )
        }
    }

    val salaries: List<SalarySettings> by lazy {
        section("salaries").map {
            SalarySettings(
                amount = it.string("salaryAmount")!!,
                type = SalaryType.fromRaw(it.string("salaryType")!!),
                monthlyWorkingDays = it.double("monthlyWorkingDays")!!,
                annualBonusMonths = it.double("annualBonusMonths")!!,
            )
        }
    }

    fun input(
        profile: Profile,
        nowMs: Double,
        overtimeEndAtMs: Double? = null,
        forcedWorkdayStartMs: Double? = null,
        zone: ZoneId = profile.zone,
    ) = ScheduleRuleInput(profile.hours, nowMs, zone, overtimeEndAtMs, forcedWorkdayStartMs)

    private fun workSchedule(o: JsonObject) = WorkSchedule(
        mode = checkNotNull(ScheduleMode.fromRaw(o.string("mode")!!)),
        referenceWeekStartMs = o.double("referenceWeekStartMs"),
        referenceWeekType = o.string("referenceWeekType"),
        singleWeekendWorkday = o.double("singleWeekendWorkday")?.toInt(),
        rotationAnchorMs = o.double("rotationAnchorMs"),
        rotationWorkDays = o.double("rotationWorkDays")?.toInt(),
        rotationRestDays = o.double("rotationRestDays")?.toInt(),
    )

    fun segments(e: JsonElement) = e.jsonArray.map {
        val s = it.jsonObject
        ShiftSegment(s.double("startAtMs")!!, s.double("endAtMs")!!)
    }

    fun sha256(lines: List<String>): String =
        MessageDigest.getInstance("SHA-256").digest(lines.joinToString("").toByteArray())
            .joinToString("") { "%02x".format(it) }

    /** Digest lines carry whole milliseconds only, as the generator writes them. */
    fun integer(value: Double): String {
        check(Math.rint(value) == value && abs(value) < 9e15) { "not a whole millisecond: $value" }
        return value.toLong().toString()
    }

    fun segmentsText(segments: List<ShiftSegment>) =
        segments.joinToString(",") { "${integer(it.startAtMs)}-${integer(it.endAtMs)}" }
}

fun JsonObject.string(key: String): String? = (get(key) ?: JsonNull).let { if (it is JsonNull) null else it.jsonPrimitive.content }
fun JsonObject.double(key: String): Double? = (get(key) ?: JsonNull).asDouble()
fun JsonObject.bool(key: String): Boolean = getValue(key).jsonPrimitive.boolean
fun JsonElement.asDouble(): Double? = if (this is JsonNull) null else jsonPrimitive.content.toDouble()
fun JsonElement.asArray(): JsonArray = jsonArray
