package com.rainif.doneat.ui.records

import com.rainif.doneat.core.designsystem.DoneAtMotion
import com.rainif.doneat.core.designsystem.DoneAtReportMotion as Motion
import com.rainif.doneat.core.domain.records.CycleReportKind
import com.rainif.doneat.core.domain.records.CycleReportSnapshot

/** iOS CycleReportStage: absent facts omit a chapter; every report has a real finale. */
internal enum class ReportStage(val timing: Pair<Long, Long>) {
    CALENDAR(Motion.calendar), HOURS(Motion.hours), OVERTIME(Motion.overtime),
    BASELINE(Motion.baseline), REST(Motion.rest), AHEAD(Motion.ahead),
    FOCUS(Motion.focus), INCOME(Motion.income), SUMMARY(Motion.summary);

    fun timeline(week: Boolean = false): ReportTimeline {
        val (build, hold) = if (this == CALENDAR && week) Motion.weekCalendar else timing
        return ReportTimeline(build, hold)
    }
    companion object {
        fun stages(report: CycleReportSnapshot): List<ReportStage> = buildList {
            if (!report.hasData) return@buildList
            add(CALENDAR); add(HOURS)
            if (report.figures.overtimeMs > 0) add(OVERTIME)
            if (report.baseline != null) add(BASELINE)
            add(REST)
            if (report.ahead != null) add(AHEAD)
            if (report.focus != null) add(FOCUS)
            if (report.pay != null) add(INCOME)
            add(SUMMARY)
        }
        fun timelines(report: CycleReportSnapshot) = stages(report).map { it.timeline(report.period.kind == CycleReportKind.WEEK) }
    }
}
internal data class ReportTimeline(val buildMs: Long, val holdMs: Long) {
    val durationMs get() = buildMs + holdMs
    fun build(elapsed: Long) = (elapsed.toFloat() / buildMs).coerceIn(0f, 1f)
    fun progress(elapsed: Long) = (elapsed.toFloat() / durationMs).coerceIn(0f, 1f)
}

/** One display clock, with temporary holds separate from the person's playback choice. */
internal data class CycleReportPlayer(
    val chapter: Int = 0,
    val elapsedMs: Long = 0,
    val clockMs: Long = 0,
    val userPaused: Boolean = true,
    val held: Boolean = false,
    val finished: Boolean = false,
) {
    val paused get() = userPaused || held || finished
    fun toggle() = if (finished) replay() else copy(userPaused = !userPaused)
    fun hold(value: Boolean) = copy(held = value)
    fun navigate(delta: Int, timelines: List<ReportTimeline>): CycleReportPlayer {
        if (timelines.isEmpty() || delta > 0 && chapter == timelines.lastIndex) return this
        val target = if (delta < 0 && !userPaused && !finished && elapsedMs > DoneAtMotion.REPORT_PREVIOUS_RESTART_MS) chapter
            else (chapter + delta).coerceIn(timelines.indices)
        return copy(chapter = target, elapsedMs = if (userPaused || finished) timelines[target].buildMs else 0, finished = false)
    }
    fun replay() = CycleReportPlayer(userPaused = false)
    fun advance(ms: Long, timelines: List<ReportTimeline>): CycleReportPlayer {
        if (paused || ms <= 0 || timelines.isEmpty()) return this
        var index = chapter
        var elapsed = elapsedMs + ms
        while (index < timelines.lastIndex && elapsed >= timelines[index].durationMs) {
            elapsed -= timelines[index].durationMs
            index++
        }
        val done = index == timelines.lastIndex && elapsed >= timelines[index].buildMs
        return copy(chapter = index, elapsedMs = if (done) timelines[index].buildMs else elapsed,
            clockMs = clockMs + ms, finished = done, userPaused = done)
    }
}
