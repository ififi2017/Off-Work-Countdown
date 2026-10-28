package com.rainif.doneat.widget

import com.rainif.doneat.core.domain.widget.*
import java.time.Instant
import java.time.ZoneId

/** Select display refreshes only for installed kinds; no new timer or wake-up service. */
internal fun widgetNextRefreshAt(entry: WidgetEntry?, raw: WidgetSuiteSnapshot?, installed: Set<DoneAtWidgetKind>, nowMs: Long): Long? {
    val countdownAt = entry?.let {
        if (it.phase == WidgetPhase.WORKING || it.phase == WidgetPhase.BEFORE) minOf(it.validUntilMs, nowMs + 15 * 60_000L) else it.validUntilMs
    }
    val kinds = installed.filterNot { it.countdown }.toSet()
    val snapshot = raw?.takeIf { kinds.isNotEmpty() }?.redacted(nowMs)
    val suiteAt = snapshot?.let { suite ->
        val candidates = mutableListOf<Long>()
        for (zoneID in setOf(suite.timeZoneIdentifier, suite.lifeTimeZoneIdentifier)) {
            val zone = ZoneId.of(zoneID)
            candidates += Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        }
        fun active(segments: List<WidgetTimeSegment>) = segments.any { it.startMs <= nowMs && nowMs < it.endMs }
        fun boundaries(segments: List<WidgetTimeSegment>) { segments.forEach { candidates += it.startMs; candidates += it.endMs } }
        var moving = false
        if (DoneAtWidgetKind.WEEK in kinds) {
            val segments = suite.calendar.week(nowMs).flatMap { it.segments }
            boundaries(segments)
            moving = moving || active(segments)
        }
        if (DoneAtWidgetKind.SUMMARY in kinds) {
            boundaries(suite.summary.liveSegments)
            suite.summary.access.validUntilMs?.let(candidates::add)
            moving = moving || active(suite.summary.liveSegments)
        }
        if (DoneAtWidgetKind.FOCUS in kinds) {
            suite.focus.blocks.forEach { candidates += it.startMs; candidates += it.endMs }
            suite.focus.access.validUntilMs?.let(candidates::add)
            moving = moving || suite.focus.current(nowMs) != null
        }
        if (DoneAtWidgetKind.WEEKEND in kinds) {
            suite.holiday.weekendStartMs?.let { candidates += it; moving = moving || it > nowMs }
        }
        if (DoneAtWidgetKind.HOLIDAY in kinds) suite.holiday.access.validUntilMs?.let(candidates::add)
        if (DoneAtWidgetKind.LIFE in kinds) suite.life.access.validUntilMs?.let(candidates::add)
        if (moving) candidates += (nowMs / 60_000 + 1) * 60_000
        candidates.filter { it > nowMs }.minOrNull()
    }
    return listOfNotNull(countdownAt, suiteAt).minOrNull()
}
