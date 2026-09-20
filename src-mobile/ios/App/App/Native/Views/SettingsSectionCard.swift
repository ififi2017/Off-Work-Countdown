import SwiftUI

/// One settings section: its header and its rows.
///
/// The single definition of what each section contains. Every shell renders
/// these; only the arrangement is theirs.
struct SettingsSectionCard: View {
    let shifts: ShiftSessionStore
    let recovery: RecoveryStore
    let section: SettingsSection
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: shifts.text.t(section.titleKey))
            OWCGroupCard { rows }
        }
    }

    @ViewBuilder
    private var rows: some View {
        switch section {
        case .shift:
            // Lunch is part of the schedule page; reminders live under Reminders.
            link(.schedule, icon: "calendar.badge.clock", title: shifts.text.t("workSchedule"), value: shifts.scheduleLabel)
            link(.salary, icon: "banknote", title: shifts.text.t("salarySettings"), value: shifts.text.salaryTypeLabel, isLast: true)

        case .reminders:
            link(.notifications, icon: "bell.badge", title: shifts.text.t("shiftReminders"), value: shifts.text.notificationModeLabel)
            link(.health, icon: "figure.walk", title: shifts.text.t("microBreakReminder"), value: shifts.healthLabel, isLast: true)

        case .appearance:
            link(.theme, icon: "display", title: shifts.text.t("theme"), value: shifts.text.themeLabel)
            link(.language, icon: "globe", title: shifts.text.t("chooselanguage"), value: shifts.text.languageLabel, isLast: true)

        case .recordsData:
            link(.recordsData, icon: "externaldrive", title: shifts.text.t("recordsDataTitle"), value: recovery.recordsDataStatusLabel(using: shifts.text), isLast: true)

        case .about:
            // An iPad cannot pair an Apple Watch, so the explainer lives on iPhone only.
            if UIDevice.current.userInterfaceIdiom == .phone {
                link(.appleWatch, icon: "applewatch", title: "Apple Watch", value: nil)
            }
            link(.about, icon: "info.circle", title: shifts.text.t("aboutProject"), value: nil)
            Button {
                shifts.disableAutomaticReviewPrompt()
                openURL(URL(string: "https://apps.apple.com/app/id6802803318?action=write-review")!)
            } label: {
                OWCRow(icon: "star.bubble", title: shifts.text.t("rateApp"), isLast: true) {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(OWCRowButtonStyle())
        }
    }

    private func link(_ route: AppRoute, icon: String, title: String, value: String?, isLast: Bool = false) -> some View {
        NavigationLink(value: route) {
            OWCRow(icon: icon, title: title, isLast: isLast) {
                OWCDetailAccessory(text: value)
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }
}
