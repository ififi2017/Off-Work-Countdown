package com.rainif.doneat.ui.records

import com.rainif.doneat.core.designsystem.DoneAtMotion

/** Playback owns time only; every chapter reads the same immutable report. */
data class CycleReportPlayer(
    val chapter: Int = 0,
    val elapsedMs: Long = 0,
    val userPaused: Boolean = true,
    val held: Boolean = false,
    val finished: Boolean = false,
) {
    val paused get() = userPaused || held || finished
    fun toggle() = copy(userPaused = !userPaused, finished = false)
    fun hold(value: Boolean) = copy(held = value)
    fun navigate(delta: Int, count: Int): CycleReportPlayer {
        val target = (chapter + delta).coerceIn(0, count - 1)
        return copy(chapter = target, elapsedMs = if (userPaused || finished) CHAPTER_MS else 0, finished = false)
    }
    fun replay() = CycleReportPlayer(userPaused = false)
    fun advance(ms: Long, count: Int): CycleReportPlayer {
        if (paused) return this
        val next = elapsedMs + ms
        if (next < CHAPTER_MS) return copy(elapsedMs = next)
        return if (chapter == count - 1) copy(elapsedMs = CHAPTER_MS, finished = true, userPaused = true)
        else copy(chapter = chapter + 1, elapsedMs = 0)
    }
    companion object { const val CHAPTER_MS = DoneAtMotion.REPORT_CHAPTER_MS }
}
