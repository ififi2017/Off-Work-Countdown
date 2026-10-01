import Foundation

/// The shift alarm plan (plan 020 §3): the schedule the countdown follows,
/// this device's lead times and the window the entitlement allows.
extension ShiftSessionStore {
    func shiftAlarmPlan(at date: Date = .now) -> ShiftAlarmPlan {
        let settings = preferences.shiftAlarmSettings
        let windowEnd = ShiftAlarmPlanner.windowEnd(
            for: plus.authorization, now: date, calendar: preferences.recordsCalendar
        )
        let alarms = windowEnd.map { end in
            ShiftAlarmPlanner.alarms(
                configuration: session.hoursConfiguration(at: date),
                timeZone: session.countdownTimeZone,
                settings: settings,
                nowMs: date.timeIntervalSince1970 * 1_000,
                untilMs: end.timeIntervalSince1970 * 1_000
            )
        } ?? []
        return ShiftAlarmPlan(
            isEnabled: settings.isEnabled,
            windowEnd: windowEnd,
            windowIsLifetime: plus.isLifetime,
            windowRenews: plus.renewsAutomatically,
            items: alarms.map { alarm in
                let title = shiftAlarmTitle(alarm)
                return ShiftAlarmPlan.Item(
                    alarm: alarm,
                    systemID: ShiftAlarmPlanner.stableID(
                        dayKey: alarm.dayKey, fireAtMs: alarm.fireAtMs,
                        shiftStartAtMs: alarm.shiftStartAtMs, shiftName: "\(alarm.id.uuidString)|\(title)"
                    ),
                    title: title
                )
            },
            stopLabel: text.t("shiftAlarmStop"),
            snoozeLabel: text.t("shiftAlarmSnooze"),
            snoozingLabel: text.t("shiftAlarmSnoozing"),
            refreshTitle: text.t("shiftAlarmRefreshTitle"),
            refreshBody: text.t("shiftAlarmRefreshBody"),
            renewBody: text.t("shiftAlarmRenewBody")
        )
    }

    /// The settings row's value.
    var shiftAlarmsLabel: String {
        preferences.shiftAlarmSettings.isEnabled && plus.isAuthorized
            ? text.t("shiftAlarmsOnShort") : text.t("disabledShort")
    }

    /// "Early at 08:00" for a named shift type, "Work at 08:00" for fixed hours.
    func shiftAlarmTitle(_ alarm: PlannedShiftAlarm) -> String {
        let time = queries.formatRecordsTime(Date(timeIntervalSince1970: alarm.shiftStartAtMs / 1_000))
        guard let name = alarm.shiftName else {
            return text.t("shiftAlarmTitleFixed", values: ["time": time])
        }
        return text.t("shiftAlarmTitle", values: ["shift": name, "time": time])
    }
}
