import SwiftUI
import UIKit

struct OffWorkCountdownRootView: View {
    @StateObject private var store = OffWorkStore()
    @StateObject private var notifications = NotificationService()
    @StateObject private var liveActivities = LiveActivityService()
    @State private var phoneTimerPath: [AppRoute] = []
    @State private var phoneSettingsPath: [AppRoute] = []
    @State private var serviceTask: Task<Void, Never>?
    /// Settings changed but the reminders have not been rebuilt yet. Flushed
    /// when the app leaves the foreground, or immediately when the countdown
    /// itself starts or stops.
    @State private var pendingReschedule = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !store.onboardingComplete {
                OnboardingView(store: store)
                    // Only the outgoing side scales. Scaling the incoming app
                    // meant its layout settled at a different size than it
                    // animated at, so everything nudged down once the
                    // transition finished — a cross-fade cannot do that.
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else if horizontalSizeClass == .regular {
                tabletLayout.transition(.opacity)
            } else {
                phoneLayout.transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: store.onboardingComplete)
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
        .onChange(of: store.countdownStarted) {
            pendingReschedule = false
            scheduleServices()
        }
        .onChange(of: scheduleSignature) {
            // Only remember that it changed. Rescheduling touches
            // UNUserNotificationCenter, ActivityKit and WidgetKit — cross-process
            // work that stalls the main runloop and tears down an active text
            // input session, which is what made the keyboard unusable after the
            // first edit. None of it is urgent while the app is in front: local
            // notifications only fire when it is not.
            pendingReschedule = true
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
            } else if pendingReschedule {
                pendingReschedule = false
                scheduleServices()
            }
        }
        .onAppear {
            CountdownRules.warmUp()
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
            "\(store.lunchStartReminderEnabled)-\(store.lunchEndReminderEnabled)-\(store.microBreakEnabled)-\(store.microBreakIntervalMinutes)",
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
        // Size class, not GeometryReader. The keyboard changes the available
        // height, which re-ran the GeometryReader body and churned the identity
        // of the TabView and NavigationStacks underneath it — the pushed screen
        // was rebuilt mid-edit, which is what dropped the keyboard and replayed
        // the push animation. Size classes do not move when the keyboard does.
        Group {
            if verticalSizeClass == .compact {
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
            // Settle first. A single edit can publish several store changes in a
            // row (a stepper held down, a value committed then clamped), and
            // each one would otherwise cancel and restart a full reschedule
            // across UNUserNotificationCenter, ActivityKit and WidgetKit.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
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
