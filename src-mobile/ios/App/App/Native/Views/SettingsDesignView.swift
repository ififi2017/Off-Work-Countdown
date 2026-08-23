import SwiftUI

/// Direction 1e: one consistent grouped-row vocabulary for every setting.
struct SettingsDesignView: View {
    @ObservedObject var store: OffWorkStore
    let wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.t("settings"))
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.85)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, 14)
                .padding(.bottom, 4)

            settingsSection(store.t("appearanceSection")) {
                NavigationLink(value: AppRoute.theme) {
                    OWCRow(icon: "display", title: store.t("theme")) {
                        OWCDetailAccessory(text: themeLabel)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                Link(destination: OWCSystemSettings.applicationURL) {
                    OWCRow(icon: "globe", title: store.t("chooselanguage"), isLast: true) {
                        OWCDetailAccessory(
                            text: store.localizer.languageName(for: store.languageCode),
                            external: true
                        )
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }

            settingsSection(store.t("shiftSection")) {
                NavigationLink(value: AppRoute.schedule) {
                    OWCRow(icon: "calendar.badge.clock", title: store.t("workSchedule")) {
                        OWCDetailAccessory(text: scheduleLabel)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                NavigationLink(value: AppRoute.lunch) {
                    OWCRow(icon: "cup.and.saucer", title: store.t("lunchBreak")) {
                        OWCDetailAccessory(text: lunchLabel)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                NavigationLink(value: AppRoute.health) {
                    OWCRow(icon: "figure.walk", title: store.t("microBreakReminder")) {
                        OWCDetailAccessory(text: healthLabel)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                NavigationLink(value: AppRoute.salary) {
                    OWCRow(icon: "banknote", title: store.t("salarySettings"), isLast: true) {
                        OWCDetailAccessory(text: salaryTypeLabel)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }

            settingsSection(store.t("remindersSection")) {
                NavigationLink(value: AppRoute.notifications) {
                    OWCRow(icon: "bell.badge", title: store.t("offWorkReminder"), isLast: true) {
                        OWCDetailAccessory(text: notificationModeLabel)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }

            settingsSection(store.t("aboutSection")) {
                NavigationLink(value: AppRoute.about) {
                    OWCRow(icon: "info.circle", title: store.t("aboutProject")) {
                        OWCDetailAccessory(text: nil)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                OWCRow(icon: "tag", title: store.t("version"), isLast: true) {
                    Text(version)
                        .font(.system(size: 17).monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: wide ? 680 : 402)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .navigationTitle("")
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: title)
            OWCGroupCard(content: content)
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .padding(.top, 14)
    }

    private var themeLabel: String {
        switch store.theme {
        case .auto: store.t("auto")
        case .light: store.t("light")
        case .dark: store.t("dark")
        }
    }

    private var lunchLabel: String {
        guard store.lunchEnabled else { return store.t("disabledShort") }
        return "\(store.timeString(store.lunchStartMinutes)) · \(store.formatRelativeDuration(Double(store.lunchDurationMinutes) * 60_000))"
    }

    private var healthLabel: String {
        store.microBreakEnabled
            ? store.t("minutesShort", values: ["count": "\(store.microBreakIntervalMinutes)"])
            : store.t("disabledShort")
    }

    private var scheduleLabel: String {
        switch store.scheduleMode {
        case .classic: store.t("scheduleClassic")
        case .alternating: store.t("scheduleAlternating")
        case .rotation: store.t("scheduleRotation")
        case .off: store.t("disabledShort")
        }
    }

    private var salaryTypeLabel: String {
        guard store.salaryEnabled else { return store.t("disabledShort") }
        return store.salaryType == .monthly ? store.t("monthly") : store.t("daily")
    }

    private var notificationModeLabel: String {
        switch store.notificationMode {
        case .off: store.t("notificationModeOff")
        case .simple: store.t("notificationModeSimple")
        case .milestones: store.t("notificationModeMilestones")
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
