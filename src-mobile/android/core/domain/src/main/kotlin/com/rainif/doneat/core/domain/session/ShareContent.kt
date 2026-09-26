package com.rainif.doneat.core.domain.session

import java.util.Locale

/**
 * What a share says about the shift (iOS `shareCopy`, `shareHeroText`,
 * `shareProgress` and `shareURL`). Hours and times only: a share never
 * carries salary, earnings or anything from the records.
 */
data class ShareContent(
    val message: Message,
    /** The big figure's remaining time; [isDone] replaces it with "off work". */
    val heroRemainingMs: Double,
    /** The sentence's remaining time: to the start before clock-in, otherwise to the end. */
    val messageRemainingMs: Double,
    val isDone: Boolean,
    /** 0…100. */
    val progress: Double,
) {
    enum class Message { OFF_WORK, LUNCH, UNTIL_START, COUNTDOWN }

    companion object {
        private val offWork = ShareContent(Message.OFF_WORK, 0.0, 0.0, isDone = true, progress = 100.0)

        fun of(session: ShiftSession, nowMs: Double): ShareContent {
            val shift = (if (session.shouldQuerySnapshot(nowMs)) session.snapshot(nowMs) else null) ?: return offWork
            val phase = session.visualPhase(shift, nowMs)
            val message = when (phase) {
                TimerPhase.COMPLETED, TimerPhase.UNSCHEDULED, TimerPhase.REST, TimerPhase.RULES_ERROR -> Message.OFF_WORK
                TimerPhase.LUNCH -> Message.LUNCH
                TimerPhase.CLOCK_IN -> Message.UNTIL_START
                TimerPhase.RUNNING, TimerPhase.OVERTIME -> Message.COUNTDOWN
            }
            val done = phase == TimerPhase.COMPLETED || session.isShiftComplete(shift)
            val progress = when {
                done -> if (session.isEndedEarly(shift)) session.clockOffSnapshot(shift).progress else 100.0
                shift.isBeforeStart(nowMs) || phase == TimerPhase.REST -> session.countdownToClockInProgress(shift)
                else -> shift.progress
            }
            val hero = shift.heroRemainingMs(nowMs)
            return ShareContent(
                message = message,
                heroRemainingMs = hero,
                messageRemainingMs = if (message == Message.UNTIL_START) session.countdownToClockInMs(shift, nowMs) else hero,
                isDone = done,
                progress = progress,
            )
        }

        /**
         * The web app with the shift's hours only ("s=0900-1800"), as iOS shares
         * it. It stays on the web origin: the link opens the site, not the app.
         */
        fun url(startMinutes: Int, endMinutes: Int): String {
            fun compact(minutes: Int) = "%02d%02d".format(Locale.ROOT, (minutes / 60) % 24, minutes % 60)
            return "https://off.rainif.com/?utm_source=share&utm_medium=image&utm_campaign=countdown" +
                "&s=${compact(startMinutes)}-${compact(endMinutes)}&from=share"
        }
    }
}
