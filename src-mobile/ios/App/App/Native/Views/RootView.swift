import Combine
import StoreKit
import SwiftUI
import UIKit

struct OffWorkCountdownRootView: View {
    @State private var store = OffWorkStore(records: .persisted())
    @State private var notifications = NotificationService()
    @State private var liveActivities = LiveActivityService()
    @State private var serviceTask: Task<Void, Never>?
    @State private var clockInCommitFeedback = 0
    @State private var clockOffCommitFeedback = 0
    /// Settings changed but the reminders have not been rebuilt yet. Flushed
    /// when the app leaves the foreground, or immediately when the countdown
    /// itself starts or stops.
    @State private var pendingReschedule = false
    @State private var paywallPresentationActive = false
    @State private var lifeSetupPresentationActive = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !store.onboardingComplete && !store.firstRunRecoveryResolved {
                FirstRunRecoveryView(store: store)
            } else if !store.onboardingComplete {
                OnboardingView(store: store)
                    // Only the outgoing side scales. Scaling the incoming app
                    // meant its layout settled at a different size than it
                    // animated at, so everything nudged down once the
                    // transition finished — a cross-fade cannot do that.
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            } else if !store.plus.hasSeenIntro {
                PlusIntroView(store: store).transition(introPaywallTransition)
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
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.paywallPresentation, value: store.onboardingComplete)
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.28), value: store.plus.hasSeenIntro)
        .preferredColorScheme(store.preferredColorScheme)
        .environment(\.layoutDirection, store.layoutDirection)
        .environment(\.locale, store.locale)
        .environment(notifications)
        .environment(liveActivities)
        .tint(OWCDesign.accent)
        .sensoryFeedback(.selection, trigger: store.selectedTab) { oldTab, newTab in
            store.onboardingComplete && oldTab != newTab
        }
        .sensoryFeedback(.success, trigger: clockInCommitFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: clockOffCommitFeedback)
        // Here rather than in each shell: a gated tap can come from the Records
        // stack, the Settings stack or the iPad detail pane, and the paywall
        // belongs over whichever one is on screen.
        .sheet(item: $store.paywallSheet, onDismiss: {
            store.settlePaywallDismissal()
            paywallPresentationActive = false
        }) { reason in
            NavigationStack {
                PaywallView(store: store, reason: reason, showsDismissButton: false) {
                    store.paywallSheet = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(store.t("close")) {
                            store.paywallSheet = nil
                        }
                    }
                }
            }
        }
        .onChange(of: store.paywallSheet != nil, initial: true) { _, presented in
            if presented { paywallPresentationActive = true }
        }
        .modifier(RecordsLifeSetupPromptModifier(
            store: store,
            paywallPresentationActive: paywallPresentationActive,
            presentationActive: $lifeSetupPresentationActive
        ))
        .modifier(AppReviewPromptModifier(store: store, isBlocked: lifeSetupPresentationActive))
        .task {
            // First frame first. StoreKit, CloudKit, the rules bundle and
            // notification scheduling all used to start in the same turn as
            // `@State store = …`, which left the launch screen up for the
            // sandbox round-trip. Two yields plus a frame of sleep so SwiftUI
            // can commit RootView before any of that work starts.
            await Task.yield()
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
            LaunchTrace.endAppInit()
            CountdownRules.warmUp()
            store.plus.start()
            guard store.onboardingComplete else { return }
            store.reconcileCountdownSession()
            _ = store.reconcileRecordSchedule()
            if store.onboardingComplete, store.selectedTab == .timer {
                store.noteTimerSurfaceVisible()
            }
            _ = store.applyDefaultFocusTemplateIfNeeded()
            store.cloudSync.startIfEnabled()
            await store.resumeRestoredSyncIfNeeded()
            guard store.onboardingComplete else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, store.onboardingComplete else { return }
            scheduleServices()
        }
        .onChange(of: store.onboardingComplete) {
            AppOrientationPolicy.shared.update(onboardingComplete: store.onboardingComplete)
            if store.onboardingComplete {
                // Let Plus intro paint first. Starting the countdown and
                // publishing the widget on this turn is why the paywall took
                // one to three seconds to appear after the welcome page.
                Task { @MainActor in
                    await Task.yield()
                    store.finishOnboardingLaunch()
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled, store.onboardingComplete else { return }
                    scheduleServices()
                }
            }
        }
        .onChange(of: store.countdownStarted) {
            pendingReschedule = false
            scheduleServices()
        }
        .onChange(of: store.plus.isAuthorized) { _, authorized in
            guard authorized, store.onboardingComplete else { return }
            if store.applyDefaultFocusTemplateIfNeeded() { scheduleServices() }
            Task { await store.resumeRestoredSyncIfNeeded() }
        }
        .onChange(of: store.debugPresentationToken) {
            pendingReschedule = false
            scheduleServices()
        }
        .onChange(of: store.earlyStartAtMs) { oldValue, newValue in
            if newValue != nil, newValue != oldValue { clockInCommitFeedback += 1 }
        }
        .onChange(of: store.earlyOffAtMs) { oldValue, newValue in
            if newValue != nil, newValue != oldValue { clockOffCommitFeedback += 1 }
        }
        .onChange(of: serviceScheduleSignal) { oldSignal, newSignal in
            if oldSignal.focusRuntimeRevision != newSignal.focusRuntimeRevision {
                // Import, CloudKit and conflict resolution can replace the
                // active session while the app is foregrounded. This cannot
                // wait for a later background transition: the Lock Screen and
                // pending end notification must match the durable winner now.
                pendingReschedule = false
                scheduleServices()
                return
            }
            // Only remember that it changed. Rescheduling touches
            // UNUserNotificationCenter, ActivityKit and WidgetKit — cross-process
            // work that stalls the main runloop and tears down an active text
            // input session, which is what made the keyboard unusable after the
            // first edit. None of it is urgent while the app is in front: local
            // notifications only fire when it is not.
            pendingReschedule = true
        }
        .onOpenURL(perform: handleOpenURL)
        .onReceive(NotificationCenter.default.publisher(for: .owcOpenURL)) { output in
            guard let url = output.object as? URL else { return }
            handleOpenURL(url)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                AppOrientationPolicy.shared.update(onboardingComplete: store.onboardingComplete)
                store.reconcileCountdownSession()
                _ = store.reconcileRecordSchedule()
                _ = store.applyDefaultFocusTemplateIfNeeded()
                store.refreshSystemLanguage()
                store.refreshSystemTimeZone()
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
            AppOrientationPolicy.shared.update(onboardingComplete: store.onboardingComplete)
            store.refreshSystemLanguage()
            store.refreshSystemTimeZone()
            applyQAGeometryIfRequested()
            clearDebugServicesAfterResetIfNeeded()
            // The launch arguments are applied during init, before any `didSet`
            // observer exists, so the opening surface needs saying once here.
            store.writeQASurfaceMarker()
        }
        .onChange(of: store.selectedTab) { _, tab in
            if tab == .timer, store.onboardingComplete {
                store.noteTimerSurfaceVisible()
            }
        }
    }

    private var introPaywallTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity.combined(with: .scale(scale: 0.985))
            )
    }

    private var scheduleSignature: String {
        let scheduleFields = [
            "\(store.startMinutes)-\(store.endMinutes)",
            store.workdays.sorted().map(String.init).joined(separator: ","),
            "\(store.scheduleMode.rawValue)-\(store.alternatingWeekType.rawValue)-\(store.alternatingWeekendWorkday)-\(store.alternatingReferenceWeekStartMs)",
            "\(store.rotationWorkDays)-\(store.rotationRestDays)-\(store.rotationAnchorMs)",
            store.languageCode,
            // Focus tasks live in the records archive; graphical plans and
            // templates live in their own small local value. Either changing
            // must republish "Coming up" before iOS suspends us on Home.
            "focus-\(store.records.revision)-\(store.focusPlanningRevision)",
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
            "\(store.cycleEndSummaryNotificationEnabled)-\(store.plus.isAuthorized)",
            "\(store.overtimeEndAtMs ?? 0)",
            "\(store.earlyOffAtMs ?? 0)-\(store.earlyOffShiftEndAtMs ?? 0)",
            "\(store.earlyStartAtMs ?? 0)",
            store.forcedWorkdayKey ?? "",
            "\(store.annualBonusEnabled)-\(store.annualBonusMonths)",
            "\(store.salaryEnabled)-\(store.salaryAmount)-\(store.salaryType.rawValue)",
            "\(store.liveActivityEnabled)-\(store.liveActivityLeadMinutes)",
        ].joined(separator: "|")
    }

    private var serviceScheduleSignal: ServiceScheduleSignal {
        .init(
            scheduleSignature: scheduleSignature,
            focusRuntimeRevision: store.focusRuntimeRevision
        )
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

    private func clearDebugServicesAfterResetIfNeeded() {
#if DEBUG
        guard store.debugDidResetOnLaunch else { return }
        WidgetSnapshotPublisher.shared.clear()
        Task { @MainActor in
            await notifications.clearShiftNotifications()
            await liveActivities.endAll()
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

            NavigationStack(path: $store.recordsPath) {
                RecordsDesignView(store: store)
            }
            .tabItem {
                Label(store.t("recordsTab"), systemImage: "calendar")
            }
            .tag(AppTab.records)

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

    private func handleOpenURL(_ url: URL) {
        guard url.scheme == "offworkcountdown" else { return }
        if url.host == "timer" {
            store.settingsPath.removeAll()
            store.timerPath.removeAll()
            store.selectedTab = .timer
            store.presentedRoute = nil
            return
        }
        guard let route = AppRoute(rawValue: url.host ?? "") else { return }
        if route == .focus || route == .focusPlan {
            store.settingsPath.removeAll()
            store.presentedRoute = nil
            store.timerPath = [route]
            store.selectedTab = .timer
            return
        }
        store.settingsPath.removeAll()
        store.selectedTab = .settings
        store.presentedRoute = route
    }

    private func scheduleServices() {
        serviceTask?.cancel()
        guard store.onboardingComplete else { return }
        serviceTask = Task { @MainActor in
            // Write the widget first. Notification and Live Activity work can
            // take long enough that a replacement task cancels us before the
            // snapshot lands — debug captures were losing that race, so the
            // Home Screen kept the real-clock rest-day snapshot.
            WidgetSnapshotPublisher.shared.publish(store: store)
            guard !Task.isCancelled else { return }
            // Foreground edits are coalesced by `pendingReschedule`. Once the
            // app is leaving the foreground there must be no additional sleep:
            // iOS may suspend the process before a delayed task gets to rebuild
            // notifications, Live Activities and the widget timeline.
            if !store.publishesLiveSurfaces {
                await notifications.clearShiftNotifications()
            } else {
                await notifications.reschedule(store: store)
            }
            // The app owns one Live Activity slot. Work uses it only inside
            // its configured display window; otherwise an active focus or
            // break session may keep it. Ending everything merely because the
            // shift countdown is not publishing erased that focus activity.
            guard !Task.isCancelled else { return }
            await liveActivities.reschedule(store: store)
        }
    }

}

private struct AppReviewPromptModifier: ViewModifier {
    @Bindable var store: OffWorkStore
    let isBlocked: Bool
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content
        .alert(store.t("reviewPromptTitle"), isPresented: $store.reviewPromptPresented) {
            Button(store.t("reviewPromptRateNow")) {
                store.acceptReviewPrompt()
                requestReview()
            }
            Button(store.t("reviewPromptLater"), role: .cancel) {
                store.deferReviewPrompt()
            }
            Button(store.t("reviewPromptNever"), role: .destructive) {
                store.disableAutomaticReviewPrompt()
            }
        } message: {
            Text(store.t("reviewPromptBody"))
        }
        .task(id: presentationGate) {
            guard presentationGate else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, presentationGate else { return }
            store.presentReviewPromptIfEligible()
        }
    }

    private var presentationGate: Bool {
        store.onboardingComplete && store.plus.hasSeenIntro && !isBlocked
    }
}

private struct ServiceScheduleSignal: Equatable {
    var scheduleSignature: String
    var focusRuntimeRevision: UInt64
}
