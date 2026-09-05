import Foundation

/// Preferences whose meaning follows the person across their devices.
/// Runtime state and device capabilities (authorization, biometrics and Live
/// Activities) stay in UserDefaults or the operating system.
struct SyncedPreferences: Codable, Equatable, Sendable {
    static let logicalKey = "preferences"

    var startMinutes: Int
    var endMinutes: Int
    var workdays: [Int]
    var scheduleMode: WorkScheduleMode
    var alternatingWeekType: AlternatingWeekType
    var alternatingWeekendWorkday: Int
    var alternatingReferenceWeekStartMs: Double
    var rotationWorkDays: Int
    var rotationRestDays: Int
    var rotationAnchorMs: Double
    var lunchEnabled: Bool
    var lunchStartMinutes: Int
    var lunchDurationMinutes: Int
    var recordsTimeZoneIdentifier: String

    var salaryAmount: String
    var salaryEnabled: Bool
    var salaryType: SalaryType
    var monthlyWorkingDays: Double
    var annualBonusEnabled: Bool
    var annualBonusMonths: Double

    var notificationMode: OffWorkNotificationMode
    var cycleEndSummaryNotificationEnabled: Bool
    var lunchStartReminderEnabled: Bool
    var lunchEndReminderEnabled: Bool
    var microBreakEnabled: Bool
    var microBreakIntervalMinutes: Int

    var theme: AppTheme
    var languageOverride: String?

    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: UUID

    var editedAt: Date {
        get { Date(timeIntervalSince1970: editedAtMs / 1_000) }
        set { editedAtMs = newValue.timeIntervalSince1970 * 1_000 }
    }

    var isValid: Bool {
        (0..<1_440).contains(startMinutes)
            && (0..<1_440).contains(endMinutes)
            && workdays == Array(Set(workdays)).sorted()
            && workdays.allSatisfy { (1...7).contains($0) }
            && (1...7).contains(alternatingWeekendWorkday)
            && alternatingReferenceWeekStartMs.isFinite
            && rotationWorkDays > 0
            && rotationRestDays > 0
            && rotationAnchorMs.isFinite
            && (0..<1_440).contains(lunchStartMinutes)
            && (1...1_439).contains(lunchDurationMinutes)
            && TimeZone(identifier: recordsTimeZoneIdentifier) != nil
            && monthlyWorkingDays.isFinite
            && monthlyWorkingDays > 0
            && annualBonusMonths.isFinite
            && annualBonusMonths >= 0
            && (1...720).contains(microBreakIntervalMinutes)
            && (languageOverride == nil || NativeLocalizer.supportedLanguages.contains { language in
                language.id == languageOverride
            })
            && editedAtMs.isFinite
            && editCount >= 0
    }

    private enum CodingKeys: String, CodingKey {
        case startMinutes, endMinutes, workdays, scheduleMode
        case alternatingWeekType, alternatingWeekendWorkday, alternatingReferenceWeekStartMs
        case rotationWorkDays, rotationRestDays, rotationAnchorMs
        case lunchEnabled, lunchStartMinutes, lunchDurationMinutes, recordsTimeZoneIdentifier
        case salaryAmount, salaryEnabled, salaryType, monthlyWorkingDays
        case annualBonusEnabled, annualBonusMonths
        case notificationMode, cycleEndSummaryNotificationEnabled
        case lunchStartReminderEnabled, lunchEndReminderEnabled
        case microBreakEnabled, microBreakIntervalMinutes
        case theme, languageOverride
        case editedAtMs, editedAt, editCount, editTieBreaker
    }
}

extension SyncedPreferences {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        startMinutes = try values.decode(Int.self, forKey: .startMinutes)
        endMinutes = try values.decode(Int.self, forKey: .endMinutes)
        workdays = try values.decode([Int].self, forKey: .workdays)
        scheduleMode = try values.decode(WorkScheduleMode.self, forKey: .scheduleMode)
        alternatingWeekType = try values.decode(AlternatingWeekType.self, forKey: .alternatingWeekType)
        alternatingWeekendWorkday = try values.decode(Int.self, forKey: .alternatingWeekendWorkday)
        alternatingReferenceWeekStartMs = try values.decode(Double.self, forKey: .alternatingReferenceWeekStartMs)
        rotationWorkDays = try values.decode(Int.self, forKey: .rotationWorkDays)
        rotationRestDays = try values.decode(Int.self, forKey: .rotationRestDays)
        rotationAnchorMs = try values.decode(Double.self, forKey: .rotationAnchorMs)
        lunchEnabled = try values.decode(Bool.self, forKey: .lunchEnabled)
        lunchStartMinutes = try values.decode(Int.self, forKey: .lunchStartMinutes)
        lunchDurationMinutes = try values.decode(Int.self, forKey: .lunchDurationMinutes)
        recordsTimeZoneIdentifier = try values.decode(String.self, forKey: .recordsTimeZoneIdentifier)
        salaryAmount = try values.decode(String.self, forKey: .salaryAmount)
        salaryEnabled = try values.decode(Bool.self, forKey: .salaryEnabled)
        salaryType = try values.decode(SalaryType.self, forKey: .salaryType)
        monthlyWorkingDays = try values.decode(Double.self, forKey: .monthlyWorkingDays)
        annualBonusEnabled = try values.decode(Bool.self, forKey: .annualBonusEnabled)
        annualBonusMonths = try values.decode(Double.self, forKey: .annualBonusMonths)
        notificationMode = try values.decode(OffWorkNotificationMode.self, forKey: .notificationMode)
        cycleEndSummaryNotificationEnabled = try values.decode(Bool.self, forKey: .cycleEndSummaryNotificationEnabled)
        lunchStartReminderEnabled = try values.decode(Bool.self, forKey: .lunchStartReminderEnabled)
        lunchEndReminderEnabled = try values.decode(Bool.self, forKey: .lunchEndReminderEnabled)
        microBreakEnabled = try values.decode(Bool.self, forKey: .microBreakEnabled)
        microBreakIntervalMinutes = try values.decode(Int.self, forKey: .microBreakIntervalMinutes)
        theme = try values.decode(AppTheme.self, forKey: .theme)
        languageOverride = try values.decodeIfPresent(String.self, forKey: .languageOverride)
        if let milliseconds = try values.decodeIfPresent(Double.self, forKey: .editedAtMs) {
            editedAtMs = milliseconds
        } else {
            let legacyDate = try values.decode(Date.self, forKey: .editedAt)
            editedAtMs = legacyDate.timeIntervalSince1970 * 1_000
        }
        editCount = try values.decode(Int.self, forKey: .editCount)
        editTieBreaker = try values.decode(UUID.self, forKey: .editTieBreaker)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(startMinutes, forKey: .startMinutes)
        try values.encode(endMinutes, forKey: .endMinutes)
        try values.encode(workdays, forKey: .workdays)
        try values.encode(scheduleMode, forKey: .scheduleMode)
        try values.encode(alternatingWeekType, forKey: .alternatingWeekType)
        try values.encode(alternatingWeekendWorkday, forKey: .alternatingWeekendWorkday)
        try values.encode(alternatingReferenceWeekStartMs, forKey: .alternatingReferenceWeekStartMs)
        try values.encode(rotationWorkDays, forKey: .rotationWorkDays)
        try values.encode(rotationRestDays, forKey: .rotationRestDays)
        try values.encode(rotationAnchorMs, forKey: .rotationAnchorMs)
        try values.encode(lunchEnabled, forKey: .lunchEnabled)
        try values.encode(lunchStartMinutes, forKey: .lunchStartMinutes)
        try values.encode(lunchDurationMinutes, forKey: .lunchDurationMinutes)
        try values.encode(recordsTimeZoneIdentifier, forKey: .recordsTimeZoneIdentifier)
        try values.encode(salaryAmount, forKey: .salaryAmount)
        try values.encode(salaryEnabled, forKey: .salaryEnabled)
        try values.encode(salaryType, forKey: .salaryType)
        try values.encode(monthlyWorkingDays, forKey: .monthlyWorkingDays)
        try values.encode(annualBonusEnabled, forKey: .annualBonusEnabled)
        try values.encode(annualBonusMonths, forKey: .annualBonusMonths)
        try values.encode(notificationMode, forKey: .notificationMode)
        try values.encode(cycleEndSummaryNotificationEnabled, forKey: .cycleEndSummaryNotificationEnabled)
        try values.encode(lunchStartReminderEnabled, forKey: .lunchStartReminderEnabled)
        try values.encode(lunchEndReminderEnabled, forKey: .lunchEndReminderEnabled)
        try values.encode(microBreakEnabled, forKey: .microBreakEnabled)
        try values.encode(microBreakIntervalMinutes, forKey: .microBreakIntervalMinutes)
        try values.encode(theme, forKey: .theme)
        try values.encodeIfPresent(languageOverride, forKey: .languageOverride)
        try values.encode(editedAtMs, forKey: .editedAtMs)
        try values.encode(editCount, forKey: .editCount)
        try values.encode(editTieBreaker, forKey: .editTieBreaker)
    }
}
