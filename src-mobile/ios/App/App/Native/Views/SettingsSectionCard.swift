import SwiftUI

/// One settings section: its header and its rows.
///
/// The single definition of what each section contains. Every shell renders
/// these; only the arrangement is theirs.
struct SettingsSectionCard: View {
    let store: OffWorkStore
    let section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: store.t(section.titleKey))
            OWCGroupCard { rows }
        }
    }

    @ViewBuilder
    private var rows: some View {
        switch section {
        case .shift:
            link(.schedule, icon: "calendar.badge.clock", title: store.t("workSchedule"), value: store.scheduleLabel)
            link(.lunch, icon: "cup.and.saucer", title: store.t("lunchBreak"), value: store.lunchLabel)
            link(.health, icon: "figure.walk", title: store.t("microBreakReminder"), value: store.healthLabel)
            link(.salary, icon: "banknote", title: store.t("salarySettings"), value: store.salaryTypeLabel, isLast: true)

        case .reminders:
            link(.notifications, icon: "bell.badge", title: store.t("offWorkReminder"), value: store.notificationModeLabel, isLast: true)

        case .appearance:
            link(.theme, icon: "display", title: store.t("theme"), value: store.themeLabel)
            link(.language, icon: "globe", title: store.t("chooselanguage"), value: store.languageLabel, isLast: true)

        case .about:
            link(.about, icon: "info.circle", title: store.t("aboutProject"), value: nil)
            OWCRow(icon: "tag", title: store.t("version"), isLast: true) {
                HStack(spacing: 6) {
                    Text(store.appVersion)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                    // Reserves the chevron's slot so the version lines up with
                    // the values on the rows above, which all have one.
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
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
