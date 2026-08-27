import Combine
import SwiftUI
import UIKit

struct OffWorkCountdownRootView: View {
    @State private var store = OffWorkStore()
    @State private var notifications = NotificationService()
    @State private var liveActivities = LiveActivityService()
    @State private var serviceTask: Task<Void, Never>?
    @State private var clockInCommitFeedback = 0
    @State private var clockOffCommitFeedback = 0
    /// Settings changed but the reminders have not been rebuilt yet. Flushed
    /// when the app leaves the foreground, or immediately when the countdown
    /// itself starts or stops.
    @State private var pendingReschedule = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !store.onboardingComplete {
                OnboardingView(store: store)
                    // Only the outgoing side scales. Scaling the incoming app
                    // meant its layout settled at a different size than it
                    // animated at, so everything nudged down once the
                    // transition finished — a cross-fade cannot do that.
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            } else if verticalSizeClass == .compact {
                // Compact height is a phone on its side — including Plus/Max,
                // whose regular width would otherwise take the iPad shell.
                PhoneLandscapeShellView(store: store).transition(.opacity)
            } else if horizontalSizeClass == .regular {
                tabletLayout.transition(.opacity)
            } else {
                phoneLayout.transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.5), value: store.onboardingComplete)
        .preferredColorScheme(store.preferredColorScheme)
        .environment(\.layoutDirection, store.layoutDirection)
        .environment(\.locale, store.locale)
        .environment(notifications)
        .tint(OWCDesign.accent)
        .sensoryFeedback(.success, trigger: clockInCommitFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: clockOffCommitFeedback)
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
        .onChange(of: store.earlyStartAtMs) { oldValue, newValue in
            if newValue != nil, newValue != oldValue { clockInCommitFeedback += 1 }
        }
        .onChange(of: store.earlyOffAtMs) { oldValue, newValue in
            if newValue != nil, newValue != oldValue { clockOffCommitFeedback += 1 }
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
                store.settingsPath.removeAll()
                store.timerPath.removeAll()
                store.selectedTab = .timer
                store.presentedRoute = nil
                return
            }
            guard let route = AppRoute(rawValue: url.host ?? "") else { return }
            store.settingsPath.removeAll()
            store.selectedTab = .settings
            store.presentedRoute = route
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                store.resetCelebratedSession()
            }
            if scenePhase == .active {
                store.reconcileCountdownSession()
                store.refreshSystemLanguage()
                Task { @MainActor in
                    // Notification authorization can change while the user is
                    // in Settings. Refresh the shared status and rebuild the
                    // pending schedule as soon as the app becomes active.
                    await notifications.refresh()
                    guard store.onboardingComplete else { return }
                    pendingReschedule = false
                    scheduleServices()
                }
            } else if pendingReschedule {
                pendingReschedule = false
                scheduleServices()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            if store.reconcileCountdownSession() {
                pendingReschedule = false
                scheduleServices()
            }
        }
        .onAppear {
            CountdownRules.warmUp()
            store.reconcileCountdownSession()
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
        guard store.publishesLiveSurfaces else {
            return (["false"] + scheduleFields).joined(separator: "|")
        }
        return [
            "true",
            scheduleFields.joined(separator: "|"),
            "\(store.lunchEnabled)-\(store.lunchStartMinutes)-\(store.lunchDurationMinutes)",
            store.notificationMode.rawValue,
            "\(store.lunchStartReminderEnabled)-\(store.lunchEndReminderEnabled)-\(store.microBreakEnabled)-\(store.microBreakIntervalMinutes)",
            "\(store.overtimeEndAtMs ?? 0)",
            "\(store.earlyOffAtMs ?? 0)-\(store.earlyOffShiftEndAtMs ?? 0)",
            "\(store.earlyStartAtMs ?? 0)",
            store.forcedWorkdayKey ?? "",
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
        // Compact-height (landscape phone, including Plus/Max) is selected
        // above, so this is portrait only.
        TabView(selection: $store.selectedTab) {
            NavigationStack(path: $store.timerPath) {
                TimerDesignView(
                    store: store,
                    wide: false,
                    onOpenSettings: openPhoneSettings
                )
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(route: route, store: store)
                }
            }
            .tabItem {
                Label(store.t("timerTab"), systemImage: "timer")
            }
            .tag(AppTab.timer)

            NavigationStack(path: $store.settingsPath) {
                SettingsDesignView(store: store)
                    .navigationDestination(for: AppRoute.self) { route in
                        AppRouteDestination(route: route, store: store)
                    }
            }
            .onChange(of: store.presentedRoute) { _, route in
                guard let route else { return }
                store.settingsPath.append(route)
                store.presentedRoute = nil
            }
            .tabItem {
                Label(store.t("settings"), systemImage: "slider.horizontal.3")
            }
            .tag(AppTab.settings)
        }
        .background(OWCDesign.page)
    }

    private var tabletLayout: some View {
        TabletShellView(store: store)
    }

    private func openPhoneSettings(_ route: AppRoute?) {
        store.presentedRoute = nil
        if let route {
            withAnimation(tabAnimation) {
                store.timerPath = [route]
                store.selectedTab = .timer
            }
        } else {
            store.settingsPath.removeAll()
            withAnimation(tabAnimation) {
                store.selectedTab = .settings
            }
        }
    }

    private var tabAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.navigation
    }

    private func scheduleServices() {
        serviceTask?.cancel()
        guard store.onboardingComplete else { return }
        serviceTask = Task { @MainActor in
            // Foreground edits are coalesced by `pendingReschedule`. Once the
            // app is leaving the foreground there must be no additional sleep:
            // iOS may suspend the process before a delayed task gets to rebuild
            // notifications, Live Activities and the widget timeline.
            if !store.publishesLiveSurfaces {
                await notifications.clearShiftNotifications()
                // The start branch below has always checked here; this one did
                // not, so a countdown restarted mid-teardown had its freshly
                // created Live Activity ended by the task it replaced.
                guard !Task.isCancelled else { return }
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

}
