import SwiftUI

/// One settings section: its header and its rows.
///
/// The single definition of what each section contains. Every shell renders
/// these; only the arrangement is theirs.
struct SettingsSectionCard: View {
    let store: OffWorkStore
    let section: SettingsSection
    @Environment(\.openURL) private var openURL

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

        case .recordsData:
            link(.recordsData, icon: "externaldrive", title: store.t("recordsDataTitle"), value: store.recordsDataStatusLabel, isLast: true)

        case .about:
            link(.about, icon: "info.circle", title: store.t("aboutProject"), value: nil)
            Button {
                store.disableAutomaticReviewPrompt()
                openURL(URL(string: "https://apps.apple.com/app/id6802803318?action=write-review")!)
            } label: {
                OWCRow(icon: "star.bubble", title: store.t("rateApp")) {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(OWCRowButtonStyle())
            OWCRow(icon: "tag", title: store.t("version"), isLast: true) {
                // Version is informational, not a disclosure row. Keeping a
                // value-only accessory lets the shared OWCRow template place
                // it on the same trailing edge as other settings values,
                // without reserving an empty chevron slot.
                Text(store.appVersion)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
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
