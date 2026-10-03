package com.rainif.doneat.ui.records

import org.junit.Assert.*
import org.junit.Test

class CycleReportPlayerTest {
    @Test fun pausedNavigationImmediatelyCompletesTarget() {
        val next = CycleReportPlayer().navigate(1, 4)
        assertEquals(1, next.chapter)
        assertEquals(CycleReportPlayer.CHAPTER_MS, next.elapsedMs)
        assertTrue(next.paused)
        assertEquals(CycleReportPlayer.CHAPTER_MS, next.navigate(-1, 4).elapsedMs)
    }
    @Test fun holdNeverChangesUserPause() {
        val playing = CycleReportPlayer(userPaused = false).hold(true).navigate(1, 4)
        assertEquals(0L, playing.elapsedMs)
        assertTrue(playing.paused)
        assertFalse(playing.hold(false).paused)
        assertTrue(CycleReportPlayer().hold(true).hold(false).paused)
    }
    @Test fun pauseAndHoldPreservePartialArtworkTime() {
        val playing = CycleReportPlayer(userPaused = false).advance(450, 4)
        val held = playing.hold(true)
        assertEquals(450L, held.advance(900, 4).elapsedMs)
        assertEquals(451L, held.hold(false).advance(1, 4).elapsedMs)
        val paused = playing.toggle()
        assertEquals(450L, paused.advance(900, 4).elapsedMs)
        assertEquals(CycleReportPlayer.CHAPTER_MS, paused.navigate(1, 4).elapsedMs)
    }
    @Test fun completionAndReplay() {
        val done = CycleReportPlayer(chapter = 2, userPaused = false).advance(CycleReportPlayer.CHAPTER_MS, 3)
        assertTrue(done.finished)
        assertEquals(CycleReportPlayer.CHAPTER_MS, done.navigate(-1, 3).elapsedMs)
        assertFalse(done.replay().paused)
        assertEquals(0, done.replay().chapter)
    }
}
