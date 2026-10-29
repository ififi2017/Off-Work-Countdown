package com.rainif.doneat.core.domain.widget

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlinx.serialization.json.*

/** Salary-free suite contract, mirroring iOS WidgetSuiteContract. No archive or entitlement token is stored. */
data class WidgetAccess(val plus: Boolean = false, val validUntilMs: Long? = null) {
    fun isUnlocked(nowMs: Long) = plus && (validUntilMs == null || nowMs < validUntilMs)
    companion object { val LOCKED = WidgetAccess() }
}

data class WidgetTimeSegment(val startMs: Long, val endMs: Long) {
    val durationMs get() = maxOf(0, endMs - startMs)
    fun remainingMs(nowMs: Long) = maxOf(0, endMs - maxOf(startMs, nowMs))
}

enum class WidgetCalendarDayKind { WORK, REST, HOLIDAY, MAKEUP_WORK, LEAVE }
enum class WidgetCalendarScheduleKind { NONE, WEEKLY, ALTERNATING_WEEKS, ROTATION, CUSTOM }
data class WidgetCalendarDay(
    val dayKey: String, val startMs: Long, val kind: WidgetCalendarDayKind,
    val title: String? = null, val colorHex: String? = null,
    val segments: List<WidgetTimeSegment> = emptyList(), val cycleDay: Int? = null, val cycleLength: Int? = null,
) {
    val isWork get() = kind == WidgetCalendarDayKind.WORK || kind == WidgetCalendarDayKind.MAKEUP_WORK
    val workMs get() = segments.sumOf { it.durationMs }
    val startAtMs get() = segments.firstOrNull()?.startMs
    val endAtMs get() = segments.lastOrNull()?.endMs
    fun remainingMs(nowMs: Long) = segments.sumOf { it.remainingMs(nowMs) }
}

data class WidgetCalendarPayload(
    val timeZoneIdentifier: String, val firstDayOfWeek: Int, val scheduleKind: WidgetCalendarScheduleKind,
    val days: List<WidgetCalendarDay> = emptyList(), val labels: Map<String, String> = emptyMap(),
) {
    fun day(nowMs: Long): WidgetCalendarDay? {
        val key = Instant.ofEpochMilli(nowMs).atZone(ZoneId.of(timeZoneIdentifier)).toLocalDate().toString()
        return days.firstOrNull { it.dayKey == key }
    }
    fun week(nowMs: Long): List<WidgetCalendarDay> {
        if (day(nowMs) == null) return emptyList()
        val date = Instant.ofEpochMilli(nowMs).atZone(ZoneId.of(timeZoneIdentifier)).toLocalDate()
        val start = date.with(TemporalAdjusters.previousOrSame(DayOfWeek.of(firstDayOfWeek)))
        val end = start.plusDays(6).toString()
        return days.filter { it.dayKey >= start.toString() && it.dayKey <= end }
    }
}

enum class WidgetSummaryPeriodKind { WEEK, MONTH, YEAR }
enum class WidgetSummaryBarState { PAST, CURRENT, FUTURE, REST }
data class WidgetSummaryBar(val label: String, val valueMs: Long, val state: WidgetSummaryBarState)
data class WidgetSummaryPeriod(
    val kind: WidgetSummaryPeriodKind, val title: String, val subtitle: String?,
    val startDayKey: String, val endDayKey: String, val workedMs: Long, val overtimeMs: Long,
    val workdays: Int, val plannedWorkdays: Int, val remainingWorkdays: Int, val progress: Double,
    val bars: List<WidgetSummaryBar> = emptyList(), val comparison: String? = null, val includesToday: Boolean = true,
) {
    fun workedMs(liveSegments: List<WidgetTimeSegment>, generatedAtMs: Long, nowMs: Long): Long {
        if (!includesToday || nowMs <= generatedAtMs) return workedMs
        return workedMs + liveSegments.sumOf { maxOf(0, minOf(it.endMs, nowMs) - maxOf(it.startMs, generatedAtMs)) }
    }
}
data class WidgetSummaryPayload(
    val access: WidgetAccess, val periods: List<WidgetSummaryPeriod> = emptyList(),
    val liveSegments: List<WidgetTimeSegment> = emptyList(), val labels: Map<String, String> = emptyMap(),
) { fun period(kind: WidgetSummaryPeriodKind) = periods.firstOrNull { it.kind == kind } }

data class WidgetLifePayload(
    val access: WidgetAccess, val bornDay: Long? = null, val bornIsApproximate: Boolean = false,
    val careerStartDay: Long? = null, val retirementDay: Long? = null, val lifeYears: Int = 80,
    val hidesExactAges: Boolean = false, val labels: Map<String, String> = emptyMap(),
)
data class WidgetHoliday(
    val name: String, val startDayKey: String, val startMs: Long, val endDayKey: String, val days: Int, val isEstimated: Boolean,
)
enum class WidgetLeaveDayKind { LEAVE, HOLIDAY, REST }
data class WidgetLeaveDay(val dayKey: String, val kind: WidgetLeaveDayKind)
data class WidgetLeave(
    val startDayKey: String, val startMs: Long, val requestedDays: Double, val totalDays: Int, val days: List<WidgetLeaveDay>,
)
data class WidgetHolidayPayload(
    val access: WidgetAccess, val weekendStartMs: Long? = null, val nextHoliday: WidgetHoliday? = null,
    val nextLeave: WidgetLeave? = null, val leaveRemainingDays: Double? = null, val labels: Map<String, String> = emptyMap(),
)
data class WidgetFocusBlock(
    val title: String, val symbol: String? = null, val startMs: Long, val endMs: Long,
    val round: Int = 1, val rounds: Int = 1, val isBreak: Boolean = false, val isRunning: Boolean = false,
)
data class WidgetFocusPayload(val access: WidgetAccess, val blocks: List<WidgetFocusBlock> = emptyList(), val labels: Map<String, String> = emptyMap()) {
    fun current(nowMs: Long) = blocks.firstOrNull { access.isUnlocked(nowMs) && it.isRunning && it.startMs <= nowMs && nowMs < it.endMs }
    fun next(nowMs: Long) = blocks.firstOrNull { access.isUnlocked(nowMs) && !it.isRunning && it.startMs > nowMs && !it.isBreak }
}

data class WidgetSuiteSnapshot(
    val schemaVersion: Int = 1, val generatedAtMs: Long, val locale: String, val timeZoneIdentifier: String,
    val calendar: WidgetCalendarPayload, val summary: WidgetSummaryPayload, val life: WidgetLifePayload,
    val holiday: WidgetHolidayPayload, val focus: WidgetFocusPayload,
    val countdownSegments: List<WidgetTimeSegment> = emptyList(), val countdownTimeZoneIdentifier: String = timeZoneIdentifier,
    val lifeTimeZoneIdentifier: String = timeZoneIdentifier,
) {
    /** Apply on disk read AND every recompose: a widget must not retain expired paid data in its tree. */
    fun redacted(nowMs: Long): WidgetSuiteSnapshot = copy(
        summary = if (summary.access.isUnlocked(nowMs)) summary else WidgetSummaryPayload(WidgetAccess.LOCKED),
        life = if (life.access.isUnlocked(nowMs)) life else WidgetLifePayload(WidgetAccess.LOCKED),
        focus = if (focus.access.isUnlocked(nowMs)) focus else WidgetFocusPayload(WidgetAccess.LOCKED),
        holiday = if (holiday.access.isUnlocked(nowMs)) holiday else holiday.copy(
            access = WidgetAccess.LOCKED, nextLeave = null, leaveRemainingDays = null,
            labels = holiday.labels.filterKeys { it != "remaining" && it != "requested" },
        ),
    )

    fun encode(): String = WidgetSuiteJSON.encode(this)
    companion object { fun decode(text: String): WidgetSuiteSnapshot? = WidgetSuiteJSON.decode(text) }
}

/** Explicit whitelists keep business archives and money out of this device-local snapshot. */
private object WidgetSuiteJSON {
    private fun obj(vararg pairs: Pair<String, JsonElement>) = JsonObject(pairs.toMap())
    private fun s(v: String?) = v?.let(::JsonPrimitive) ?: JsonNull
    private fun n(v: Number?) = v?.let(::JsonPrimitive) ?: JsonNull
    private fun b(v: Boolean) = JsonPrimitive(v)
    private fun arr(v: List<JsonElement>) = JsonArray(v)
    private fun labels(v: Map<String, String>) = JsonObject(v.mapValues { JsonPrimitive(it.value) })
    private fun access(v: WidgetAccess) = obj("plus" to b(v.plus), "validUntilMs" to n(v.validUntilMs))
    private fun segments(v: List<WidgetTimeSegment>) = arr(v.map { arr(listOf(n(it.startMs), n(it.endMs))) })
    fun encode(v: WidgetSuiteSnapshot): String = obj(
        "schemaVersion" to n(v.schemaVersion), "generatedAtMs" to n(v.generatedAtMs), "locale" to s(v.locale),
        "timeZoneIdentifier" to s(v.timeZoneIdentifier), "countdownTimeZoneIdentifier" to s(v.countdownTimeZoneIdentifier),
        "lifeTimeZoneIdentifier" to s(v.lifeTimeZoneIdentifier),
        "countdownSegments" to segments(v.countdownSegments),
        "calendar" to obj(
            "timeZoneIdentifier" to s(v.calendar.timeZoneIdentifier), "firstDayOfWeek" to n(v.calendar.firstDayOfWeek),
            "scheduleKind" to s(v.calendar.scheduleKind.name), "labels" to labels(v.calendar.labels),
            "days" to arr(v.calendar.days.map { d -> obj("dayKey" to s(d.dayKey), "startMs" to n(d.startMs), "kind" to s(d.kind.name),
                "title" to s(d.title), "colorHex" to s(d.colorHex), "segments" to segments(d.segments), "cycleDay" to n(d.cycleDay), "cycleLength" to n(d.cycleLength)) }),
        ),
        "summary" to obj("access" to access(v.summary.access), "liveSegments" to segments(v.summary.liveSegments), "labels" to labels(v.summary.labels),
            "periods" to arr(v.summary.periods.map { p -> obj("kind" to s(p.kind.name), "title" to s(p.title), "subtitle" to s(p.subtitle),
                "startDayKey" to s(p.startDayKey), "endDayKey" to s(p.endDayKey), "workedMs" to n(p.workedMs), "overtimeMs" to n(p.overtimeMs),
                "workdays" to n(p.workdays), "plannedWorkdays" to n(p.plannedWorkdays), "remainingWorkdays" to n(p.remainingWorkdays), "progress" to n(p.progress),
                "comparison" to s(p.comparison), "includesToday" to b(p.includesToday),
                "bars" to arr(p.bars.map { bar -> obj("label" to s(bar.label), "valueMs" to n(bar.valueMs), "state" to s(bar.state.name)) })) })),
        "life" to obj("access" to access(v.life.access), "bornDay" to n(v.life.bornDay), "bornIsApproximate" to b(v.life.bornIsApproximate),
            "careerStartDay" to n(v.life.careerStartDay), "retirementDay" to n(v.life.retirementDay), "lifeYears" to n(v.life.lifeYears),
            "hidesExactAges" to b(v.life.hidesExactAges), "labels" to labels(v.life.labels)),
        "holiday" to obj("access" to access(v.holiday.access), "weekendStartMs" to n(v.holiday.weekendStartMs),
            "leaveRemainingDays" to n(v.holiday.leaveRemainingDays), "labels" to labels(v.holiday.labels),
            "nextHoliday" to (v.holiday.nextHoliday?.let { h -> obj("name" to s(h.name), "startDayKey" to s(h.startDayKey), "startMs" to n(h.startMs),
                "endDayKey" to s(h.endDayKey), "days" to n(h.days), "isEstimated" to b(h.isEstimated)) } ?: JsonNull),
            "nextLeave" to (v.holiday.nextLeave?.let { l -> obj("startDayKey" to s(l.startDayKey), "startMs" to n(l.startMs), "requestedDays" to n(l.requestedDays),
                "totalDays" to n(l.totalDays), "days" to arr(l.days.map { obj("dayKey" to s(it.dayKey), "kind" to s(it.kind.name)) })) } ?: JsonNull)),
        "focus" to obj("access" to access(v.focus.access), "labels" to labels(v.focus.labels), "blocks" to arr(v.focus.blocks.map { f -> obj("title" to s(f.title),
            "symbol" to s(f.symbol), "startMs" to n(f.startMs), "endMs" to n(f.endMs), "round" to n(f.round), "rounds" to n(f.rounds), "isBreak" to b(f.isBreak), "isRunning" to b(f.isRunning)) })),
    ).toString()

    private fun JsonObject.str(k: String) = getValue(k).jsonPrimitive.content
    private fun JsonObject.strOrNull(k: String) = (get(k) as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.num(k: String) = getValue(k).jsonPrimitive.long
    private fun JsonObject.optNum(k: String): Long? {
        val value = get(k) ?: return null
        if (value == JsonNull) return null
        require(value is JsonPrimitive && !value.isString)
        return value.long
    }
    private fun JsonObject.int(k: String) = getValue(k).jsonPrimitive.int
    private fun JsonObject.bool(k: String): Boolean {
        val value = getValue(k).jsonPrimitive
        require(!value.isString)
        return value.boolean
    }
    private fun JsonObject.list(k: String) = getValue(k).jsonArray.map { it.jsonObject }
    private fun JsonObject.map(k: String) = getValue(k).jsonObject.mapValues { it.value.jsonPrimitive.content }
    private fun JsonObject.access(): WidgetAccess = getValue("access").jsonObject.let { WidgetAccess(it.bool("plus"), it.optNum("validUntilMs")) }
    private fun JsonObject.segments(k: String): List<WidgetTimeSegment> = getValue(k).jsonArray.map { e ->
        val a = e.jsonArray
        require(a.size == 2)
        WidgetTimeSegment(a[0].jsonPrimitive.long, a[1].jsonPrimitive.long).also { require(it.endMs >= it.startMs) }
    }
    fun decode(text: String): WidgetSuiteSnapshot? = runCatching {
        val o = Json.parseToJsonElement(text).jsonObject
        require(o.int("schemaVersion") == 1)
        val c = o.getValue("calendar").jsonObject
        val summary = o.getValue("summary").jsonObject
        val life = o.getValue("life").jsonObject
        val holiday = o.getValue("holiday").jsonObject
        val focus = o.getValue("focus").jsonObject
        ZoneId.of(o.str("timeZoneIdentifier")); ZoneId.of(o.str("countdownTimeZoneIdentifier")); ZoneId.of(c.str("timeZoneIdentifier")); ZoneId.of(o.str("lifeTimeZoneIdentifier"))
        require(c.int("firstDayOfWeek") in 1..7)
        WidgetSuiteSnapshot(1, o.num("generatedAtMs"), o.str("locale"), o.str("timeZoneIdentifier"),
            WidgetCalendarPayload(c.str("timeZoneIdentifier"), c.int("firstDayOfWeek"), WidgetCalendarScheduleKind.valueOf(c.str("scheduleKind")),
                c.list("days").map { d ->
                    LocalDate.parse(d.str("dayKey"))
                    WidgetCalendarDay(d.str("dayKey"), d.num("startMs"), WidgetCalendarDayKind.valueOf(d.str("kind")), d.strOrNull("title"),
                        d.strOrNull("colorHex"), d.segments("segments"), d.optNum("cycleDay")?.toInt(), d.optNum("cycleLength")?.toInt())
                }, c.map("labels")),
            WidgetSummaryPayload(summary.access(), summary.list("periods").map { p -> WidgetSummaryPeriod(
                WidgetSummaryPeriodKind.valueOf(p.str("kind")), p.str("title"), p.strOrNull("subtitle"), p.str("startDayKey"), p.str("endDayKey"),
                p.num("workedMs"), p.num("overtimeMs"), p.int("workdays"), p.int("plannedWorkdays"), p.int("remainingWorkdays"), p.getValue("progress").jsonPrimitive.double,
                p.list("bars").map { WidgetSummaryBar(it.str("label"), it.num("valueMs"), WidgetSummaryBarState.valueOf(it.str("state"))) },
                p.strOrNull("comparison"), p.bool("includesToday")) }, summary.segments("liveSegments"), summary.map("labels")),
            WidgetLifePayload(life.access(), life.optNum("bornDay"), life.bool("bornIsApproximate"), life.optNum("careerStartDay"), life.optNum("retirementDay"),
                life.int("lifeYears"), life.bool("hidesExactAges"), life.map("labels")),
            WidgetHolidayPayload(holiday.access(), holiday.optNum("weekendStartMs"), (holiday["nextHoliday"] as? JsonObject)?.let { h ->
                WidgetHoliday(h.str("name"), h.str("startDayKey"), h.num("startMs"), h.str("endDayKey"), h.int("days"), h.bool("isEstimated")) },
                (holiday["nextLeave"] as? JsonObject)?.let { l -> WidgetLeave(l.str("startDayKey"), l.num("startMs"), l.getValue("requestedDays").jsonPrimitive.double,
                    l.int("totalDays"), l.list("days").map { WidgetLeaveDay(it.str("dayKey"), WidgetLeaveDayKind.valueOf(it.str("kind"))) }) },
                (holiday["leaveRemainingDays"] as? JsonPrimitive)?.doubleOrNull, holiday.map("labels")),
            WidgetFocusPayload(focus.access(), focus.list("blocks").map { f -> WidgetFocusBlock(f.str("title"), f.strOrNull("symbol"), f.num("startMs"),
                f.num("endMs"), f.int("round"), f.int("rounds"), f.bool("isBreak"), if ("isRunning" in f) f.bool("isRunning") else false) }, focus.map("labels")),
            o.segments("countdownSegments"), o.str("countdownTimeZoneIdentifier"), o.str("lifeTimeZoneIdentifier"))
    }.getOrNull()
}
