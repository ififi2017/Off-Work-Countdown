import SwiftUI
import UIKit

struct OffWorkCountdownRootView: View {
    @StateObject private var store = OffWorkStore()
    @StateObject private var notifications = NotificationService()
    @StateObject private var liveActivities = LiveActivityService()
    @State private var phoneTimerPath: [AppRoute] = []
    @State private var phoneSettingsPath: [AppRoute] = []
    @State private var serviceTask: Task<Void, Never>?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !store.onboardingComplete {
                OnboardingView(store: store)
            } else if horizontalSizeClass == .regular {
                tabletLayout
            } else {
                phoneLayout
            }
        }
        .preferredColorScheme(store.preferredColorScheme)
        .environment(\.layoutDirection, store.layoutDirection)
        .environment(\.locale, store.locale)
        .tint(OWCDesign.accent)
        .sensoryFeedback(.success, trigger: store.countdownStarted)
        .task {
            await Task.yield()
            guard store.onboardingComplete else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, store.onboardingComplete else { return }
            scheduleServices()
        }
        .onChange(of: store.onboardingComplete) {
            if store.onboardingComplete { scheduleServices() }
        }
        .onChange(of: scheduleSignature) {
            scheduleServices()
        }
        .onOpenURL { url in
            guard url.scheme == "offworkcountdown" else { return }
            if url.host == "timer" {
                phoneSettingsPath.removeAll()
                phoneTimerPath.removeAll()
                store.selectedTab = .timer
                store.presentedRoute = nil
                return
            }
            guard let route = AppRoute(rawValue: url.host ?? "") else { return }
            phoneSettingsPath.removeAll()
            store.selectedTab = .settings
            store.presentedRoute = route
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                store.refreshSystemLanguage()
            }
        }
        .onAppear {
            store.refreshSystemLanguage()
            applyQAGeometryIfRequested()
        }
    }

    private var scheduleSignature: String {
        let scheduleFields = [
            "\(store.startMinutes)-\(store.endMinutes)",
            store.workdays.sorted().map(String.init).joined(separator: ","),
            "\(store.scheduleMode.rawValue)-\(store.alternatingWeekType.rawValue)-\(store.alternatingWeekendWorkday)-\(store.alternatingReferenceWeekStartMs)",
            "\(store.rotationWorkDays)-\(store.rotationRestDays)-\(store.rotationAnchorMs)",
            store.languageCode,
        ]
        guard store.countdownStarted else {
            return (["false"] + scheduleFields).joined(separator: "|")
        }
        return [
            "true",
            scheduleFields.joined(separator: "|"),
            "\(store.lunchEnabled)-\(store.lunchStartMinutes)-\(store.lunchDurationMinutes)",
            store.notificationMode.rawValue,
            "\(store.lunchEdgesEnabled)-\(store.microBreakEnabled)-\(store.microBreakIntervalMinutes)",
            "\(store.overtimeEndAtMs ?? 0)",
            "\(store.annualBonusEnabled)-\(store.annualBonusMonths)",
            "\(store.salaryEnabled)-\(store.salaryAmount)-\(store.salaryType.rawValue)",
            "\(store.liveActivityEnabled)-\(store.liveActivityLeadMinutes)",
        ].joined(separator: "|")
    }

    private func applyQAGeometryIfRequested() {
#if DEBUG
        let defaults = UserDefaults.standard
        guard let requested = defaults.string(forKey: "ios.native.qaOrientation") else { return }
        defaults.removeObject(forKey: "ios.native.qaOrientation")
        defaults.removeObject(forKey: "ios.native.qaOrientationError")
        let orientations: UIInterfaceOrientationMask = requested == "landscape" ? .landscape : .portrait
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                UserDefaults.standard.set(error.localizedDescription, forKey: "ios.native.qaOrientationError")
            }
        }
#endif
    }

    private var phoneLayout: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                PhoneLandscapeShellView(store: store)
            } else {
                TabView(selection: $store.selectedTab) {
                    NavigationStack(path: $phoneTimerPath) {
                        TimerDesignView(
                            store: store,
                            wide: false,
                            onOpenSettings: openPhoneSettings
                        )
                        .navigationDestination(for: AppRoute.self) { route in
                            routeDestination(route)
                        }
                    }
                    .tabItem {
                        Label(store.t("timerTab"), systemImage: "timer")
                    }
                    .tag(AppTab.timer)

                    NavigationStack(path: $phoneSettingsPath) {
                        SettingsDesignView(store: store, wide: false)
                            .navigationDestination(for: AppRoute.self) { route in
                                routeDestination(route)
                            }
                            .navigationDestination(item: $store.presentedRoute) { route in
                                routeDestination(route)
                            }
                    }
                    .tabItem {
                        Label(store.t("settings"), systemImage: "slider.horizontal.3")
                    }
                    .tag(AppTab.settings)
                }
                .background(OWCDesign.page)
            }
        }
    }

    private var tabletLayout: some View {
        TabletShellView(store: store)
    }

    private func openPhoneSettings(_ route: AppRoute?) {
        store.presentedRoute = nil
        if let route {
            withAnimation(.snappy(duration: 0.28)) {
                phoneTimerPath = [route]
                store.selectedTab = .timer
            }
        } else {
            phoneSettingsPath.removeAll()
            withAnimation(.snappy(duration: 0.28)) {
                store.selectedTab = .settings
            }
        }
    }

    private func scheduleServices() {
        serviceTask?.cancel()
        guard store.onboardingComplete else { return }
        serviceTask = Task { @MainActor in
            if !store.countdownStarted {
                await notifications.clearShiftNotifications()
                await liveActivities.endAll()
            } else {
                await notifications.reschedule(store: store)
                guard !Task.isCancelled else { return }
                await liveActivities.reschedule(store: store)
            }
            guard !Task.isCancelled else { return }
            WidgetSnapshotPublisher.shared.publish(store: store)
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .schedule: ScheduleSettingsView(store: store)
        case .salary: SalaryDesignView(store: store)
        case .notifications: NotificationDesignView(store: store)
        case .lunch: LunchSettingsView(store: store)
        case .health: HealthReminderSettingsView(store: store)
        case .theme: ThemeSettingsView(store: store)
        case .about: AboutView(store: store)
        }
    }
}
