package com.rainif.doneat.core.domain.settings

import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.ReminderInputs
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.session.ScheduleFieldChange
import com.rainif.doneat.core.domain.session.SessionEnvironment
import com.rainif.doneat.core.domain.session.SessionState
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.TimelineEvent
import com.rainif.doneat.core.domain.session.UpcomingTimeline
import com.rainif.doneat.core.domain.session.rulesInputApplying
import com.rainif.doneat.core.domain.session.seededExtendedContent
import java.util.UUID

/** Read-only first-run preview, using the same draft and rules as the completed setup. */
data class SetupProjection(val snapshot: ShiftSnapshot, val input: ScheduleRuleInput, val upcoming: List<TimelineEvent>) {
    fun remainingMs(nowMs: Double): Double = if (nowMs < snapshot.startAtMs) snapshot.startAtMs - nowMs
        else ScheduleRules.snapshot(input.copy(nowMs = nowMs), NO_SALARY).remainingMs

    companion object {
        private val NO_SALARY = SalarySettings("", SalaryType.MONTHLY, 22.0, 0.0)

        /** Supply the real persistence IDs when committing; preview IDs never enter an archive. */
        fun seedContent(env: SessionEnvironment, nowMs: Double, holidayRegionIdentifier: String?,
                        newId: () -> UUID = UUID::randomUUID, workName: String = "Work", restName: String = "Rest"): ExtendedScheduleContent {
            val session = previewSession(env)
            return session.seededExtendedContent(ScheduleFieldChange(), nowMs, workName, restName, newId)
                .copy(holidayRegionIdentifier = holidayRegionIdentifier ?: "")
        }

        fun resolve(env: SessionEnvironment, nowMs: Double, holidayRegionIdentifier: String? = null): SetupProjection? {
            if (env.preferences.scheduleMode == "off") return null
            val session = previewSession(env)
            var seed = 0L
            val change = if (env.onboardingComplete) ScheduleFieldChange() else ScheduleFieldChange(
                extendedScheduleEnabled = true,
                extendedContent = seedContent(env, nowMs, holidayRegionIdentifier, newId = { UUID(0x321, ++seed) }),
            )
            var input = session.rulesInputApplying(change, nowMs)
            var snapshot = ScheduleRules.snapshot(input, NO_SALARY)
            if (!snapshot.isWorkday || nowMs >= snapshot.endAtMs) {
                val next = snapshot.nextShiftStartAtMs ?: return null
                input = input.copy(nowMs = next)
                snapshot = ScheduleRules.snapshot(input, NO_SALARY)
            }
            if (!snapshot.isWorkday) return null
            val p = env.preferences
            val reminders = ScheduleRules.reminders(input, ReminderInputs(
                p.notificationMode, "", "", emptyMap(), emptyMap(),
                p.lunchEnabled && p.lunchStartReminderEnabled, "",
                p.lunchEnabled && p.lunchEndReminderEnabled, "",
                p.microBreakEnabled, "", p.microBreakIntervalMinutes, listOf(""), null,
            ))
            return SetupProjection(snapshot, input, UpcomingTimeline.events(snapshot, nowMs, reminders,
                p.microBreakEnabled, p.notificationMode != "off"))
        }

        private fun previewSession(env: SessionEnvironment): ShiftSession = ShiftSession(SessionState(), SessionEnvironment(
            env.preferences.copy(salaryAmount = "", salaryEnabled = false), true,
            env.extendedSchedule, env.rosterDays, env.holidays, env.deviceZone, false, env.leaveDays,
        ))
    }
}
