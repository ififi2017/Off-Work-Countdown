import SwiftUI

/// The single destination registry used by every phone and iPad navigation
/// stack. Links carry only `AppRoute` values so layout variants cannot drift
/// into separate destination hierarchies.
struct AppRouteDestination: View {
    @Environment(SceneState.self) private var scene
    let route: AppRoute
    let runtime: AppRuntime

    // The tab bar deliberately stays up across a push, the way it does in the
    // App Store. Detail pages owe it clearance instead — see
    // `OWCContentSizedScrollView`.
    @ViewBuilder
    var body: some View {
        Group {
            switch route {
            case .schedule:
                ScheduleSettingsView(shifts: runtime.shifts)
            case .salary:
                SalaryDesignView(shifts: runtime.shifts)
            case .notifications:
                NotificationDesignView(shifts: runtime.shifts)
            // Lunch is edited with the hours now. The route stays so upcoming
            // rows, the start button and deep links still land on it.
            case .lunch:
                ScheduleSettingsView(shifts: runtime.shifts)
            case .health:
                HealthReminderSettingsView(shifts: runtime.shifts)
            case .theme:
                ThemeSettingsView(preferences: runtime.preferences, text: runtime.text)
            case .language:
                LanguageSettingsView(preferences: runtime.preferences, text: runtime.text)
            case .recordsTimeZone:
                RecordsTimeZoneSettingsView(shifts: runtime.shifts)
            case .plus:
                PlusSettingsView(plus: runtime.plus, text: runtime.text)
            case .iCloudSync:
                RecordsSyncSettingsView(recovery: runtime.recovery, actions: runtime.recordActions)
            case .recordsData:
                RecordsDataSettingsView(actions: runtime.recordActions, recovery: runtime.recovery, life: runtime.life)
            case .recordsConflicts:
                RecordsConflictCenter(
                    records: runtime.records,
                    queries: runtime.queries,
                    preferences: runtime.preferences,
                    text: runtime.text
                )
            // One canvas, three scales. `focusPlan` used to be a second page
            // reached from the first; it stays as a route so existing links
            // and QA markers still land somewhere, and now lands on the same
            // canvas.
            case .focus, .focusPlan:
                FocusCanvasView(
                    focus: runtime.focus,
                    text: runtime.text,
                    queries: runtime.queries,
                    preferences: runtime.preferences,
                    onboardingComplete: runtime.preferences.onboardingComplete,
                    hasSeenPlusIntro: runtime.plus.hasSeenIntro,
                    browsing: scene.focus
                )
            case .appleWatch:
                AppleWatchSettingsView(plus: runtime.plus, text: runtime.text)
            case .about:
                AboutView(text: runtime.text) {
#if DEBUG
                    DebugMenuView(debug: runtime.debug)
#else
                    EmptyView()
#endif
                }
            }
        }
        .onAppear { scene.writeQASurfaceMarker("route.\(route.rawValue)", onboardingComplete: runtime.preferences.onboardingComplete, hasSeenPlusIntro: runtime.plus.hasSeenIntro) }
    }
}
