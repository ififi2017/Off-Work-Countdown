package com.rainif.doneat.ui.records

import com.rainif.doneat.core.domain.records.*
import org.junit.Assert.*
import org.junit.Test

class CycleReportPlayerTest {
    private val timelines = listOf(ReportStage.CALENDAR.timeline(), ReportStage.HOURS.timeline(), ReportStage.REST.timeline(), ReportStage.SUMMARY.timeline())
    @Test fun pausedNavigationImmediatelyCompletesTarget() {
        val next = CycleReportPlayer().navigate(1, timelines)
        assertEquals(1, next.chapter)
        assertEquals(timelines[1].buildMs, next.elapsedMs)
        assertTrue(next.paused)
        assertEquals(timelines[0].buildMs, next.navigate(-1, timelines).elapsedMs)
        // Resuming a completed build keeps its reading hold; it does not skip immediately.
        assertEquals(1, next.toggle().advance(100, timelines).chapter)
    }
    @Test fun holdNeverChangesUserPause() {
        val playing = CycleReportPlayer(userPaused = false).hold(true).navigate(1, timelines)
        assertEquals(0L, playing.elapsedMs)
        assertTrue(playing.paused)
        assertFalse(playing.hold(false).paused)
        assertTrue(CycleReportPlayer().hold(true).hold(false).paused)
    }
    @Test fun pauseAndHoldFreezeBothClocks() {
        val playing = CycleReportPlayer(userPaused = false).advance(450, timelines)
        val held = playing.hold(true)
        assertEquals(held, held.advance(900, timelines))
        val resumed = held.hold(false).advance(1, timelines)
        assertEquals(451L, resumed.elapsedMs)
        assertEquals(451L, resumed.clockMs)
        val paused = playing.toggle()
        assertEquals(paused, paused.advance(900, timelines))
    }
    @Test fun chapterBuildHoldAndRemainderArePreserved() {
        val playing = CycleReportPlayer(userPaused = false).advance(timelines[0].buildMs, timelines)
        assertEquals(0, playing.chapter)
        assertEquals(1f, timelines[0].build(playing.elapsedMs))
        assertTrue(timelines[0].progress(playing.elapsedMs) < 1)
        val next = playing.advance(timelines[0].holdMs + 27, timelines)
        assertEquals(1, next.chapter)
        assertEquals(27L, next.elapsedMs)
        assertEquals(timelines[0].durationMs + 27, next.clockMs)
    }
    @Test fun previousRestartsPlayingChapterThenReturns() {
        val playing = CycleReportPlayer(chapter = 2, userPaused = false).advance(900, timelines)
        val restarted = playing.navigate(-1, timelines)
        assertEquals(2, restarted.chapter)
        assertEquals(0L, restarted.elapsedMs)
        assertEquals(1, restarted.navigate(-1, timelines).chapter)
        assertEquals(1, playing.toggle().navigate(-1, timelines).chapter)
    }
    @Test fun completionAndReplay() {
        val done = CycleReportPlayer(chapter = 3, userPaused = false).advance(timelines[3].buildMs, timelines)
        assertTrue(done.finished)
        assertEquals(done, done.navigate(1, timelines))
        assertEquals(timelines[2].buildMs, done.navigate(-1, timelines).elapsedMs)
        assertFalse(done.toggle().paused)
        assertEquals(0, done.replay().chapter)
        assertEquals(0L, done.replay().clockMs)
    }
    @Test fun emptyAndOptionalChaptersMatchIOS() {
        val period = CycleReportPeriod(CycleReportKind.MONTH, "2026-09-01", "2026-09-30", "UTC")
        val empty = CycleReportSnapshot(period, emptyList(), CycleReportFigures(), 0, 0, null, false)
        assertTrue(ReportStage.stages(empty).isEmpty())
        val report = empty.copy(figures = CycleReportFigures(20, 100, 0))
        assertEquals(listOf(ReportStage.CALENDAR, ReportStage.HOURS, ReportStage.REST, ReportStage.SUMMARY), ReportStage.stages(report))
        val full = report.copy(figures = report.figures.copy(overtimeMs = 1), baseline = CycleReportBaseline(1, 120, -20),
            ahead = CycleReportAhead(1, null, null, null, emptyList(), true), focus = CycleReportFocus(2, 30, emptyList(), 0, null), pay = CycleReportPay(30.0, null, null))
        assertEquals(ReportStage.entries, ReportStage.stages(full))
        assertFalse(ReportStage.stages(full.withoutIncome()).contains(ReportStage.INCOME))
        assertEquals(2_000L, ReportStage.CALENDAR.timeline(true).buildMs)
    }
}
