import Foundation

/// Actual inputs used by the current service coordinator. Appearance and
/// CloudKit bookkeeping are deliberately absent; changes to either must not
/// reschedule reminders or republish the running shift.
struct ServiceScheduleSignal: Equatable, Sendable {
    let focusPlanningRevision: UInt64
    let scheduleSignature: String
    let focusRuntimeRevision: UInt64

    init(focusPlanningRevision: UInt64, scheduleSignature: String, focusRuntimeRevision: UInt64) {
        self.focusPlanningRevision = focusPlanningRevision
        self.scheduleSignature = scheduleSignature
        self.focusRuntimeRevision = focusRuntimeRevision
    }

    init(shifts: ShiftSessionStore) {
        focusPlanningRevision = shifts.focus.focusPlanningRevision
        scheduleSignature = Self.scheduleSignature(from: shifts)
        focusRuntimeRevision = shifts.focus.focusRuntimeRevision
    }

    private static func scheduleSignature(from shifts: ShiftSessionStore) -> String {
        let scheduleFields = [
            "\(shifts.preferences.startMinutes)-\(shifts.preferences.endMinutes)",
            shifts.preferences.workdays.sorted().map(String.init).joined(separator: ","),
            "\(shifts.preferences.scheduleMode.rawValue)-\(shifts.preferences.alternatingWeekType.rawValue)-\(shifts.preferences.alternatingWeekendWorkday)-\(shifts.preferences.alternatingReferenceWeekStartMs)",
            "\(shifts.preferences.rotationWorkDays)-\(shifts.preferences.rotationRestDays)-\(shifts.preferences.rotationAnchorMs)",
            shifts.preferences.languageCode,
            shifts.preferences.recordsTimeZoneIdentifier,
            shifts.session.countdownTimeZoneIdentifier,
            // Focus tasks live in the records archive; graphical plans and
            // templates live in their own small local value. Either changing
            // must republish "Coming up" before iOS suspends us on Home.
            "records-\(shifts.records.historyRevision)-\(shifts.records.focusRevision)-\(shifts.focus.focusPlanningRevision)",
            // The extended schedule and its days are history records, so the
            // revision above already moves with them. Spelled out anyway: the
            // countdown's hours depend on them, not only "Coming up".
            "extended-\(shifts.preferences.isExtendedScheduleEnabled)",
        ]
        return [
            "\(shifts.session.publishesLiveSurfaces)",
            scheduleFields.joined(separator: "|"),
            "\(shifts.preferences.lunchEnabled)-\(shifts.preferences.lunchStartMinutes)-\(shifts.preferences.lunchDurationMinutes)",
            shifts.preferences.notificationMode.rawValue,
            "\(shifts.preferences.lunchStartReminderEnabled)-\(shifts.preferences.lunchEndReminderEnabled)-\(shifts.preferences.microBreakEnabled)-\(shifts.preferences.microBreakIntervalMinutes)",
            "\(shifts.preferences.cycleEndSummaryNotificationEnabled)-\(shifts.plus.isAuthorized)",
            "\(shifts.session.overtimeEndAtMs ?? 0)",
            "\(shifts.session.earlyOffAtMs ?? 0)-\(shifts.session.earlyOffShiftEndAtMs ?? 0)",
            "\(shifts.session.earlyStartAtMs ?? 0)",
            shifts.session.forcedWorkdayKey ?? "",
            "\(shifts.preferences.annualBonusEnabled)-\(shifts.preferences.annualBonusMonths)",
            "\(shifts.preferences.salaryEnabled)-\(shifts.preferences.salaryAmount)-\(shifts.preferences.salaryType.rawValue)-\(shifts.preferences.monthlyWorkingDays)",
            "\(shifts.preferences.liveActivityEnabled)-\(shifts.preferences.liveActivityLeadMinutes)",
            "\(shifts.preferences.focusLiveActivityEnabled)-\(shifts.focus.focusNotificationsEnabled)",
        ].joined(separator: "|")
    }

}
