import Foundation

/// A report notification ready for the system: no figures, no pay. The report
/// itself is built when the app opens it, so nothing here needs to run in the
/// background.
struct CycleReportNotification: Equatable, Sendable {
    var period: CycleReportPeriod
    var title: String
    var body: String
    var trigger: DateComponents
    var fireDate: Date
}

extension ShiftSessionStore {
    func cycleReportNotifications(at now: Date = .now) -> [CycleReportNotification] {
        let weekly = weeklyReportNotificationsAreActive
        let monthly = monthlyReportNotificationsAreActive
        guard preferences.onboardingComplete, weekly || monthly else { return [] }
        let calendar = queries.recordsGridCalendar
        return CycleReportNotificationPlan
            .items(weekly: weekly, monthly: monthly, now: now, calendar: calendar)
            .map { item in
                var components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: item.fireDate
                )
                components.timeZone = calendar.timeZone
                let copy: (title: String, body: String) = switch item.period.kind {
                case .week: (text.t("reportNotificationWeekTitle"), text.t("reportNotificationWeekBody"))
                case .month: (text.t("reportNotificationMonthTitle"), text.t("reportNotificationMonthBody"))
                }
                return CycleReportNotification(
                    period: item.period,
                    title: copy.title,
                    body: copy.body,
                    trigger: components,
                    fireDate: item.fireDate
                )
            }
    }
}
