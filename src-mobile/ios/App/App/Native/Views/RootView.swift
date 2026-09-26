import StoreKit
import SwiftUI
import UIKit

struct OffWorkCountdownRootView: View {
    @State private var scene: SceneState
    private let runtime: AppRuntime
    @State private var clockInCommitFeedback = 0
    @State private var clockOffCommitFeedback = 0
    @State private var paywallPresentationActive = false
    @State private var lifeSetupPresentationActive = false
    @State private var isLandscapePhone = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var quickActionScene: HomeQuickActionSceneDelegate

    init(runtime: AppRuntime) {
        self.runtime = runtime
        _scene = State(initialValue: SceneState(defaults: runtime.defaults, recordsScale: runtime.preferences.preferredRecordsScale, showsReleaseNotes: runtime.preferences.shouldOfferReleaseNotes))
    }

    var body: some View {
        Group {
            if !runtime.preferences.onboardingComplete {
                OnboardingView(
                    preferences: runtime.preferences,
                    shifts: runtime.shifts,
                    recovery: runtime.recovery,
                    actions: runtime.recordActions,
                    text: runtime.text
                )
                    // Only the outgoing side scales. Scaling the incoming app
                    // meant its layout settled at a different size than it
                    // animated at, so everything nudged down once the
                    // transition finished — a cross-fade cannot do that.
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            } else if !runtime.plus.hasSeenIntro && !scene.showsReleaseNotes {
                PlusIntroView(plus: runtime.plus, text: runtime.text).transition(introPaywallTransition)
            } else {
                adaptiveLayout.transition(.opacity)
            }
        }
        .accessibilityHidden(showsLandscapeTimer)
        .overlay {
            if showsLandscapeTimer {
                PhoneLandscapeTimerOverlay(shifts: runtime.shifts)
                    .transition(.opacity)
            }
        }
        .background {
            PhoneLandscapePresentation(isLandscapePhone: $isLandscapePhone)
        }
        .statusBarHidden(showsLandscapeTimer)
        .persistentSystemOverlays(showsLandscapeTimer ? .hidden : .automatic)
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.paywallPresentation, value: runtime.preferences.onboardingComplete)
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.28), value: runtime.plus.hasSeenIntro)
        .preferredColorScheme(runtime.preferences.preferredColorScheme)
        .environment(\.layoutDirection, runtime.preferences.layoutDirection)
        .environment(\.locale, runtime.preferences.locale)
        .environment(runtime.notifications)
        .environment(runtime.liveActivities)
        .modifier(RecordSaveStatus(
            records: runtime.records,
            title: runtime.text.t("recordsArchiveSaveFailedTitle"),
            message: runtime.text.t("recordsArchiveSaveFailedBody"),
            retryTitle: runtime.text.t("retryAction")
        ))
        .tint(OWCDesign.accent)
        .sensoryFeedback(.selection, trigger: scene.selectedTab) { oldTab, newTab in
            runtime.preferences.onboardingComplete && oldTab != newTab
        }
        .sensoryFeedback(.success, trigger: clockInCommitFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: clockOffCommitFeedback)
        // Here rather than in each shell: a gated tap can come from the Records
        // stack, the Settings stack or the iPad detail pane, and the paywall
        // belongs over whichever one is on screen.
        .sheet(item: Bindable(scene).paywallSheet, onDismiss: {
            if let action = scene.settlePaywallDismissal(plus: runtime.plus) {
                scene.performPendingPlusAction(action, focus: runtime.focus, actions: runtime.recordActions,
                    queries: runtime.queries, recovery: runtime.recovery)
            }
            paywallPresentationActive = false
        }) { reason in
            NavigationStack {
                PaywallView(plus: runtime.plus, text: runtime.text, reason: reason, showsDismissButton: false) {
                    scene.paywallSheet = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(runtime.text.t("close")) {
                            scene.paywallSheet = nil
                        }
                    }
                }
            }
            .presentationSizing(.page)
            .presentationDetents([.large])
        }
        .onChange(of: scene.paywallSheet != nil, initial: true) { _, presented in
            if presented { paywallPresentationActive = true }
            scene.writeQASurfaceMarker(onboardingComplete: runtime.preferences.onboardingComplete, hasSeenPlusIntro: runtime.plus.hasSeenIntro)
        }
        .sheet(item: Bindable(scene).dayEditor) { draft in
            NavigationStack {
                RecordDayEditView(draft: draft, actions: runtime.recordActions)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Bindable(scene).timerSheet) { sheet in
            switch sheet {
            case .share:
                ShareComposerView(shifts: runtime.shifts)
                    .presentationSizing(AdaptivePresentationSizing(
                        wide: .page, compact: .automatic,
                        usesWideSizing: usesWideSheetSizing
                    ))
                    .presentationDetents(usesWideSheetSizing ? [.large] : [.fraction(0.78)])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
            case .overtime:
                OvertimeSheet(shifts: runtime.shifts)
                    .presentationSizing(AdaptivePresentationSizing(
                        wide: .form, compact: .automatic,
                        usesWideSizing: usesWideSheetSizing
                    ))
                    .presentationDetents(usesWideSheetSizing ? [.large] : [.medium])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: Bindable(scene).presentAddFocus) {
            FocusQuickCreateSheet(focus: runtime.focus, text: runtime.text) { _ in
                Task { @MainActor in
                    await Task.yield()
                    guard runtime.plus.isAuthorized else { return }
                    scene.openFocusTab()
                }
            }
        }
        .modifier(RecordsLifeSetupPromptModifier(
            life: runtime.life, actions: runtime.recordActions, reviewPromptPresented: scene.reviewPromptPresented,
            paywallPresentationActive: paywallPresentationActive || scene.showsReleaseNotes,
            hasBlockingPresentation: hasRootPresentation(excludingLifeSetup: true),
            presentationActive: $lifeSetupPresentationActive
        ))
        .modifier(AppReviewPromptModifier(
            shifts: runtime.shifts, isBlocked: hasRootPresentation(excludingReview: true)
                || lifeSetupPresentationActive || scenePhase != .active
        ))
        .fullScreenCover(isPresented: Binding(
            get: { runtime.preferences.onboardingComplete && scene.showsReleaseNotes },
            set: { if !$0 { scene.dismissReleaseNotes(preferences: runtime.preferences, plus: runtime.plus) } }
        )) {
            WhatsNewView(
                text: runtime.text,
                onDismiss: { scene.dismissReleaseNotes(preferences: runtime.preferences, plus: runtime.plus) },
                onLearnAboutWatch: {
                    scene.dismissReleaseNotes(preferences: runtime.preferences, plus: runtime.plus)
                    scene.presentedRoute = .appleWatch
                }
            )
                .presentationBackground(.clear)
        }
        .onChange(of: runtime.preferences.seenRelease) { _, seenRelease in
            if seenRelease == ReleaseNotes.current { scene.showsReleaseNotes = false }
        }
        .modifier(LifeSummaryRefreshModifier(life: runtime.life, isLaunching: runtime.services.isLaunching,
            onboardingComplete: runtime.preferences.onboardingComplete, authorized: runtime.plus.isAuthorized))
        .onChange(of: runtime.preferences.onboardingComplete) {
            AppOrientationPolicy.shared.update(onboardingComplete: runtime.preferences.onboardingComplete)
            if runtime.preferences.onboardingComplete, scene.selectedTab == .timer { runtime.shifts.noteTimerSurfaceVisible() }
        }
        .onChange(of: quickActionScene.pendingShortcut, initial: true) { _, _ in
            consumeQuickAction()
        }
        .onChange(of: quickActionReady) { _, _ in
            consumeQuickAction()
        }
        .onChange(of: runtime.session.earlyStartAtMs) { oldValue, newValue in
            if newValue != nil, newValue != oldValue { clockInCommitFeedback += 1 }
        }
        .onChange(of: runtime.session.earlyOffAtMs) { oldValue, newValue in
            if newValue != nil, newValue != oldValue { clockOffCommitFeedback += 1 }
        }
        .modifier(FocusActivityConfirmationModifier(focus: runtime.focus))
        .onChange(of: focusActivityCanPresent, initial: true) { _, canPresent in
            if canPresent { scene.activateFocusActivityPresentationIfPossible(isBlocked: false) }
        }
        .onOpenURL(perform: scene.handleOpenURL)
        .onChange(of: scenePhase) {
            reportScenePhase()
            if scenePhase == .active {
                AppOrientationPolicy.shared.update(onboardingComplete: runtime.preferences.onboardingComplete)
            }
        }
        .onDisappear { runtime.services.sceneDisconnected(scene.id) }
        .onAppear {
            AppOrientationPolicy.shared.update(onboardingComplete: runtime.preferences.onboardingComplete)
            reportScenePhase()
            applyQAGeometryIfRequested()
            if scene.selectedTab == .timer, runtime.preferences.onboardingComplete { runtime.shifts.noteTimerSurfaceVisible() }
#if DEBUG
            let defaults = UserDefaults.standard
            if runtime.preferences.onboardingComplete,
               runtime.plus.hasSeenIntro,
               !scene.showsReleaseNotes,
               defaults.bool(forKey: "ios.native.qaShareComposer") {
                defaults.removeObject(forKey: "ios.native.qaShareComposer")
                scene.timerSheet = .share
            }
#endif
            // The launch arguments are applied during init, before any `didSet`
            // observer exists, so the opening surface needs saying once here.
            scene.writeQASurfaceMarker(onboardingComplete: runtime.preferences.onboardingComplete, hasSeenPlusIntro: runtime.plus.hasSeenIntro)
        }
        .onChange(of: scene.selectedTab) { _, tab in
            scene.writeQASurfaceMarker(onboardingComplete: runtime.preferences.onboardingComplete, hasSeenPlusIntro: runtime.plus.hasSeenIntro)
            if tab == .timer, runtime.preferences.onboardingComplete {
                runtime.shifts.noteTimerSurfaceVisible()
            }
        }
        .environment(scene)
    }

    private var introPaywallTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity.combined(with: .scale(scale: 0.985))
            )
    }

    private var quickActionReady: Bool {
        runtime.preferences.onboardingComplete && runtime.plus.hasSeenIntro && !scene.showsReleaseNotes
    }

    private func consumeQuickAction() {
        guard let tab = quickActionScene.takePending(when: quickActionReady) else { return }
        switch tab {
        case .timer: scene.openTimer()
        case .focus: scene.openFocusTab()
        case .records:
            scene.recordsPath.removeAll()
            scene.presentedRoute = nil
            scene.selectedTab = .records
        case .settings: break
        }
    }

    private var showsLandscapeTimer: Bool {
        PhoneLandscapePresentationPolicy.shouldPresent(
            isLandscapePhone: isLandscapePhone,
            selectedTab: scene.selectedTab,
            onboardingComplete: runtime.preferences.onboardingComplete,
            hasSeenPlusIntro: runtime.plus.hasSeenIntro,
            timerIsAtRoot: scene.timerPath.isEmpty,
            hasBlockingPresentation: hasRootPresentation() || lifeSetupPresentationActive
        )
    }

    private var usesWideSheetSizing: Bool { horizontalSizeClass == .regular }

    private var focusActivityCanPresent: Bool {
        scene.focusActivityRequest != nil
            && !scene.focusActivityPresentationReady
            && !hasRootPresentation(excludingFocusActivity: true)
    }

    private func hasRootPresentation(
        excludingLifeSetup: Bool = false, excludingFocusActivity: Bool = false, excludingReview: Bool = false
    ) -> Bool {
        scene.paywallSheet != nil
            || paywallPresentationActive
            || scene.pendingPlusAction != nil
            || scene.dayEditor != nil
            || scene.timerSheet != nil
            || scene.presentAddFocus
            || scene.showsReleaseNotes
            || (!excludingFocusActivity && scene.hasFocusActivityPresentation)
            || (!excludingLifeSetup && (scene.lifeSetupOfferPresented || scene.lifeSetupEditorPresented))
            || (!excludingReview && scene.reviewPromptPresented)
    }

    private func reportScenePhase() {
        let phase: ServiceCoordinator.Phase = switch scenePhase {
        case .active: .active
        case .inactive: .inactive
        case .background: .background
        @unknown default: .inactive
        }
        runtime.services.sceneChanged(scene.id, phase: phase)
    }

    private func applyQAGeometryIfRequested() {
#if DEBUG
        let defaults = UserDefaults.standard
        guard let requested = defaults.string(forKey: "ios.native.qaOrientation") else { return }
        defaults.removeObject(forKey: "ios.native.qaOrientation")
        defaults.removeObject(forKey: "ios.native.qaOrientationError")
        let orientations: UIInterfaceOrientationMask = requested == "landscape" ? .landscape : .portrait
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // The policy owns every window of every connected scene. Reaching
            // for `connectedScenes.first` here turned whichever scene the
            // system happened to hand back first, which on an iPad running
            // Stage Manager is not necessarily the one being photographed.
            AppOrientationPolicy.shared.pinOrientationsForQA(orientations)
        }
#endif
    }

    private var adaptiveLayout: some View {
        AdaptiveAppShellView(runtime: runtime)
    }



}

private struct AdaptivePresentationSizing<Wide: PresentationSizing, Compact: PresentationSizing>: PresentationSizing {
    let wide: Wide
    let compact: Compact
    let usesWideSizing: Bool

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        usesWideSizing
            ? wide.proposedSize(for: root, context: context)
            : compact.proposedSize(for: root, context: context)
    }
}

private struct AppReviewPromptModifier: ViewModifier {
    let shifts: ShiftSessionStore
    let isBlocked: Bool
    @Environment(SceneState.self) private var scene
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content
        .alert(shifts.text.t("reviewPromptTitle"), isPresented: Bindable(scene).reviewPromptPresented) {
            Button(shifts.text.t("reviewPromptRateNow")) {
                shifts.acceptReviewPrompt()
                requestReview()
            }
            Button(shifts.text.t("reviewPromptLater"), role: .cancel) {
                shifts.deferReviewPrompt()
            }
            Button(shifts.text.t("reviewPromptNever"), role: .destructive) {
                shifts.disableAutomaticReviewPrompt()
            }
        } message: {
            Text(shifts.text.t("reviewPromptBody"))
        }
        .task(id: presentationGate) {
            guard presentationGate else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, presentationGate else { return }
            scene.presentReviewPromptIfEligible(using: shifts, isBlocked: !presentationGate)
        }
    }

    private var presentationGate: Bool {
        shifts.preferences.onboardingComplete && shifts.plus.hasSeenIntro && !isBlocked
    }
}
