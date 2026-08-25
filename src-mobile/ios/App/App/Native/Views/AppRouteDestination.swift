import SwiftUI

/// The single destination registry used by every phone and iPad navigation
/// stack. Links carry only `AppRoute` values so layout variants cannot drift
/// into separate destination hierarchies.
struct AppRouteDestination: View {
    let route: AppRoute
    let store: OffWorkStore

    // The tab bar deliberately stays up across a push, the way it does in the
    // App Store. Detail pages owe it clearance instead — see
    // `OWCContentSizedScrollView`.
    @ViewBuilder
    var body: some View {
        switch route {
        case .schedule:
            ScheduleSettingsView(store: store)
        case .salary:
            SalaryDesignView(store: store)
        case .notifications:
            NotificationDesignView(store: store)
        case .lunch:
            LunchSettingsView(store: store)
        case .health:
            HealthReminderSettingsView(store: store)
        case .theme:
            ThemeSettingsView(store: store)
        case .language:
            LanguageSettingsView(store: store)
        case .about:
            AboutView(store: store)
        }
    }
}
