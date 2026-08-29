import LocalAuthentication
import SwiftUI
import UIKit

struct OnboardingView: View {
    // Rounded display digits; no text style is this size.
    @ScaledMetric(relativeTo: .largeTitle) private var heroNumberSize: CGFloat = 46
    @Bindable var store: OffWorkStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notifications = NotificationService()
    /// Sampled once rather than read in `body`, which would build an
    /// `LAContext` on every render.
    @State private var biometry: LABiometryType = .none
    @State private var navigationFeedback = 0
    /// One reference instant keeps every first-run surface demo in sync.
    /// Reduce Motion renders this instant without starting a periodic timeline.
    @State private var demoStartedAt = Date.now
    /// Read by the page transition. Set before `onboardingPage` changes so
    /// insertion and removal agree on direction for this hop.
    @State private var goingBack = false

    private static let pageAnimation = Animation.snappy(duration: 0.32)
    /// A pure slide, deliberately without a cross-fade.
    ///
    /// `.opacity` on a transition sets `allowsGroupOpacity`, which forces the
    /// whole outgoing *and* incoming page — screen-sized, and carrying blurred
    /// shadows — into an offscreen transparency layer that has to be composited
    /// again on every frame. At 120 Hz that is an 8.3 ms budget spent on two
    /// full-screen offscreen renders plus their gaussian blurs, and it is what
    /// made the paging feel sticky. Translating a layer costs Core Animation
    /// almost nothing. Reduce Motion still cross-fades — see `pageTransition`.
    private static let forwardTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing),
        removal: .move(edge: .leading)
    )
    private static let backTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .leading),
        removal: .move(edge: .trailing)
    )

    var body: some View {
        ZStack {
            // Every page is a fixed `VStack` sized for an upright phone at the
            // default text size. The app supports landscape (see
            // `UISupportedInterfaceOrientations`), and onboarding is shown
            // before any size-class branching, so in landscape — and at
            // accessibility text sizes — the three-row cards and the two
            // buttons under them ran past the bottom of the screen and the
            // continue button was clipped. On the very first launch that is the
            // whole app.
            //
            // `minHeight: proxy.size.height` rather than a plain `ScrollView`:
            // a scroll view proposes unbounded height, which collapses the
            // `Spacer`s these pages use to centre themselves and would bunch
            // every page against the top. With the minimum in place a page that
            // fits lays out exactly as before and does not scroll at all;
            // only one that does not fit becomes scrollable.
            GeometryReader { proxy in
                ScrollView {
                    Group {
                        switch store.onboardingPage {
                        case OnboardingPages.landing:
                            welcome
                        case OnboardingPages.schedule:
                            ready
                        case OnboardingPages.reminders:
                            OnboardingRemindersPage(store: store, onContinue: advanceFromReminders)
                        case OnboardingPages.allSet:
                            allSet
                        case OnboardingPages.privacy:
                            privacy
                        case OnboardingPages.systemSurfaces:
                            systemSurfaces
                        case OnboardingPages.adaptiveLayouts:
                            adaptiveLayouts
                        default:
                            OnboardingFinalePage(
                                store: store,
                                logoSize: finaleLogoSize(in: proxy.size)
                            ) {
                                store.completeOnboarding(enableNotifications: false)
                            }
                        }
                    }
                    .id(store.onboardingPage)
                    .transition(pageTransition)
                    // `maxWidth: .infinity` is what centres the pages, and it
                    // has to be here because `GeometryReader` aligns its child
                    // to `.topLeading`. Before this scroll wrapper existed the
                    // parent filled the width and every page came out centred by
                    // accident; afterwards the two pages that cap themselves at
                    // 560 and stop there — the reminders page and the
                    // privacy page — were pinned to the left edge on iPad, while
                    // the pages that happened to add their own
                    // `.frame(maxWidth: .infinity)` still looked right.
                    //
                    // Fixed once here rather than on those two pages, so a page
                    // added later cannot forget it.
                    //
                    // 36 pt for the back control, so a leading-aligned title
                    // cannot sit under it. Inset first, then `minHeight`:
                    // padding after the frame made every page after landing
                    // 36 pt taller than the viewport, so the confirmation
                    // page scrolled on a 17 Pro even when its spacers still
                    // had room to give.
                    .padding(.top, store.onboardingPage == OnboardingPages.landing ? 0 : 36)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                // UIScrollView's default fill is systemBackground — pure white
                // in light mode, and a mismatch for every page here. While the
                // number pad is dismissing, GeometryReader grows and that white
                // shows through the newly uncovered strip under Continue before
                // the content's minHeight catches up.
                .scrollContentBackground(.hidden)
            }
        }
        .overlay(alignment: .topLeading) {
            if store.onboardingPage != OnboardingPages.landing {
                Button(action: goBack) {
                    Image(systemName: "chevron.backward")
                        .font(.title3.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .padding(.leading, 20)
                .padding(.top, 8)
                .accessibilityLabel(store.t("onboardingBack"))
            }
        }
        .animation(pageAnimation, value: store.onboardingPage)
        // The grouped background, not the plain one: cards are
        // `secondarySystemGroupedBackground`, which is pure white in light mode
        // — exactly the same white as `systemBackground` — so on a plain
        // background every card here silently vanished and its rows were left
        // floating without a container.
        //
        // ShapeStyle `.background(color)` only ignores the *container* safe
        // area. The keyboard is a separate region, so when the lunch-duration
        // number pad dismissed the strip it vacated was the hosting
        // controller's default white fill — a one-frame overlay across the
        // continue row. Painting the same colour with `ignoresSafeArea()`
        // covers that region for the whole animation.
        .background {
            OWCDesign.page.ignoresSafeArea()
        }
        // Keep the onboarding canvas at one height while the number pad moves.
        // Otherwise UIKit animates the keyboard safe area and GeometryReader
        // solves a second bottom-button position halfway through dismissal.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.layoutDirection, store.layoutDirection)
        .environment(\.locale, store.locale)
        .sensoryFeedback(.impact(weight: .light), trigger: navigationFeedback)
        .task { biometry = BiometricGate.status().biometry }
        .onAppear {
#if DEBUG
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "ios.native.qaOnboardingPage") != nil {
                store.onboardingPage = min(
                    OnboardingPages.count - 1,
                    max(0, defaults.integer(forKey: "ios.native.qaOnboardingPage"))
                )
                defaults.removeObject(forKey: "ios.native.qaOnboardingPage")
            }
#endif
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            CelebratingBrandMark()
                .frame(width: 148, height: 148)
                // Preserve the existing title baseline: the extra 40 points
                // grow upward into the intentionally empty welcome-page space.
                .padding(.top, -40)
            Text(verbatim: OWCBrand.shortName)
                .font(.largeTitle.bold())
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .padding(.top, 26)
            Text(store.t("landingTagline"))
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

#if DEBUG
            Toggle(isOn: $store.debugAlwaysShowOnboarding) {
                Text(verbatim: "DEBUG · 每次启动显示欢迎页")
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
            }
            .tint(OWCDesign.accent)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // Same column as the feature list below, or on iPad it stretches
            // edge to edge while everything else stays centred.
            .frame(maxWidth: 420)
#endif
            VStack(alignment: .leading, spacing: 18) {
                feature("clock", store.t("landingFeature1Title"), store.t("onboardingShiftBody"))
                feature("wifi.slash", store.t("onboardingOfflineTitle"), store.t("onboardingOfflineBody"))
                feature("rectangle", store.t("onboardingSystemTitle"), store.t("onboardingSystemBody"))
            }
            .padding(.top, 34)
            .frame(maxWidth: 420)
            Spacer()

            pageDots
            Button(store.t("continue")) {
                showPage(OnboardingPages.schedule)
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.top, 16)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 12)
    }

    private var systemSurfaces: some View {
        onboardingShowcase(
            title: store.t("onboardingEverywhereTitle"),
            // The iPad copy drops the Dynamic Island along with its mockup.
            body: store.t(horizontalSizeClass == .regular
                          ? "onboardingEverywhereBodyTablet"
                          : "onboardingEverywhereBody"),
            button: store.t("continue")
        ) {
            liveDemo { date in
                VStack(spacing: 12) {
                    // The Dynamic Island is an iPhone feature; showing it to an
                    // iPad owner promises hardware they do not have.
                    if horizontalSizeClass != .regular {
                        dynamicIslandDemo(at: date)
                    }

                    rectangularComplicationDemo(at: date)
                    largeWidgetDemo(at: date)
                }
            }
        } action: {
            showPage(OnboardingPages.adaptiveLayouts)
        }
    }

    /// Split by device on purpose: an iPhone owner does not need to hear about
    /// iPad, and an iPad owner does not rotate to get the full-screen clock —
    /// they collapse the sidebar. One screen, two truths.
    private var adaptiveLayouts: some View {
        let isPad = horizontalSizeClass == .regular
        return onboardingShowcase(
            title: store.t(isPad ? "onboardingSidebarTitle" : "onboardingLandscapeTitle"),
            body: store.t(isPad ? "onboardingSidebarBody" : "onboardingLandscapeBody"),
            button: store.t("continue")
        ) {
            fullScreenClockPreview(showsSidebarHint: isPad)
        } action: {
            showPage(OnboardingPages.finale)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 18)
            Image(systemName: "lock.shield")
                .font(.title2.weight(.semibold))
                .foregroundStyle(OWCDesign.orangeDeep)
                .frame(width: 52, height: 52)
                .background(OWCDesign.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(store.t("onboardingPrivacyTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.top, 22)
            Text(store.t("onboardingPrivacyBody"))
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            OWCGroupCard {
                OWCRow(
                    icon: "wifi.slash",
                    title: store.t("onboardingOfflineTitle"),
                    subtitle: store.t("onboardingOfflineBody"),
                    centersVertically: true
                )
                OWCRow(
                    icon: "briefcase",
                    title: store.t("workSchedule"),
                    subtitle: store.t("onboardingPrivacyWorkBody"),
                    centersVertically: true
                )
                OWCRow(
                    // Both the glyph and the copy come from the hardware. A
                    // face was drawn here on every device, next to a sentence
                    // that named Face ID, on iPads that only have Touch ID.
                    icon: biometry.symbolName,
                    title: store.t("salarySettings"),
                    subtitle: store.t(
                        "onboardingSalaryLockBody",
                        values: ["biometry": store.biometryName(biometry)]
                    ),
                    isLast: true,
                    centersVertically: true
                )
            }
            .padding(.top, 22)
            Spacer(minLength: 18)

            // Asking here rather than at the salary screen: the first time the
            // system prompt appears is the one time the user is being told why,
            // and a permission sheet that arrives with an explanation next to it
            // gets granted far more often than one that ambushes them later.
            pageDots
            VStack(spacing: 10) {
                Button(store.t(
                    "onboardingEnableBiometrics",
                    values: ["biometry": store.biometryName(biometry)]
                )) {
                    navigationFeedback += 1
                    Task {
                        _ = await BiometricGate.confirmOwner(reason: store.t("unlockSalaryReason"))
                        showPage(OnboardingPages.systemSurfaces, feedback: false)
                    }
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                Button(store.t("notNow")) {
                    showPage(OnboardingPages.systemSurfaces)
                }
                    .font(.body.weight(.medium))
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
    }

    /// The same instrument the landscape and collapsed-sidebar screens show:
    /// oversized tabular clock, caption, bar. Deliberately nothing else, because
    /// that is the whole point being made.
    private func fullScreenClockPreview(showsSidebarHint: Bool) -> some View {
        liveDemo { date in
            VStack(spacing: 12) {
                if showsSidebarHint {
                    HStack(spacing: 8) {
                        Image(systemName: "sidebar.left")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                            .frame(width: 30, height: 30)
                            .background(OWCDesign.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Image(systemName: "arrow.right")
                            .font(.caption2.bold())
                            .foregroundStyle(OWCDesign.tertiary)
                        Spacer(minLength: 0)
                    }
                }

                VStack(spacing: 10) {
                    Text(store.formatDuration(demoRemainingMilliseconds(at: date)))
                        .font(.system(size: heroNumberSize, weight: .bold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .environment(\.layoutDirection, .leftToRight)
                        .contentTransition(.numericText(countsDown: true))
                    Text(store.t("timeLeftCaption"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                    demoProgressBar(at: date, height: 8)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
                .background(OWCDesign.card)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .owcShowcaseLift()
            }
        }
    }

    @ViewBuilder
    private func liveDemo<Content: View>(
        @ViewBuilder content: @escaping (Date) -> Content
    ) -> some View {
        if reduceMotion {
            content(demoStartedAt)
        } else {
            TimelineView(.periodic(from: demoStartedAt, by: 1)) { context in
                content(context.date)
            }
        }
    }

    private func dynamicIslandDemo(at date: Date) -> some View {
        HStack(spacing: 0) {
            Image(.brandMark)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
            Spacer(minLength: 34)
            Text(verbatim: demoIslandCountdown(at: date))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
        }
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, 12)
        .frame(width: 172, height: 37)
        .background(.black, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
        }
        .owcShowcaseLift()
    }

    /// Mirrors WidgetKit's accessory-rectangular family: product line,
    /// countdown, and the compact linear capacity gauge.
    private func rectangularComplicationDemo(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(.brandMark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                Text(verbatim: OWCBrand.shortName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            Text(store.formatDuration(demoRemainingMilliseconds(at: date)))
                .font(.system(size: 21, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .environment(\.layoutDirection, .leftToRight)
                .contentTransition(.numericText(countsDown: true))
            demoProgressBar(at: date, height: 5)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(width: 244, height: 69, alignment: .leading)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .owcShowcaseLift()
    }

    /// A scaled likeness of the real system-large widget, including the
    /// upcoming list that distinguishes it from the old small preview.
    private func largeWidgetDemo(at date: Date) -> some View {
        let progress = demoProgress(at: date)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(.brandMark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(verbatim: OWCBrand.shortName)
                    .font(.caption.bold())
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Circle().fill(OWCDesign.accent).frame(width: 6, height: 6)
                Text(store.t("widgetWorking"))
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(OWCDesign.accent.opacity(0.12), in: Capsule())
            .padding(.top, 9)

            Text(store.formatDuration(demoRemainingMilliseconds(at: date)))
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .environment(\.layoutDirection, .leftToRight)
                .contentTransition(.numericText(countsDown: true))
                .padding(.top, 7)

            demoProgressBar(at: date, height: 6)
                .padding(.top, 8)
            HStack(spacing: 6) {
                Text(verbatim: "\(Int((progress * 100).rounded()))%")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(OWCDesign.accent)
                Spacer(minLength: 4)
                Text(verbatim: "19:00")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
            }
            .padding(.top, 5)

            Text(store.t("comingUp"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(OWCDesign.secondary)
                .padding(.top, 10)
                .padding(.bottom, 3)
            demoUpcomingRow(
                icon: "figure.walk",
                title: store.t("microBreakReminder"),
                time: "15:00"
            )
            demoUpcomingRow(
                icon: "flag.checkered",
                title: store.t("offWorkReminder"),
                time: "19:00",
                isLast: true
            )
        }
        .padding(14)
        .frame(maxWidth: 326, minHeight: 244, maxHeight: 244, alignment: .leading)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .owcShowcaseLift()
    }

    private func demoUpcomingRow(
        icon: String,
        title: String,
        time: String,
        isLast: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(OWCDesign.accent)
                .frame(width: 14)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 6)
            Text(verbatim: time)
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(OWCDesign.secondary)
        }
        .frame(height: 24)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(OWCDesign.separator)
                    .frame(height: 0.5)
                    .padding(.leading, 22)
            }
        }
    }

    private func demoProgressBar(at date: Date, height: CGFloat) -> some View {
        Capsule().fill(OWCDesign.control)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(OWCDesign.accent)
                        .frame(width: proxy.size.width * demoProgress(at: date))
                }
            }
    }

    private func demoElapsed(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(demoStartedAt))
    }

    private func demoRemainingMilliseconds(at date: Date) -> Double {
        max(0, (2 * 3_600 + 34 * 60 + 18) - demoElapsed(at: date)) * 1_000
    }

    private func demoProgress(at date: Date) -> Double {
        min(0.98, 0.73 + demoElapsed(at: date) / (8 * 3_600))
    }

    private func demoIslandCountdown(at date: Date) -> String {
        let remaining = max(0, Int(14 * 60 + 59 - demoElapsed(at: date)))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    private func onboardingShowcase<Showcase: View>(
        title: String,
        body: String,
        button: String,
        @ViewBuilder showcase: () -> Showcase,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)
            Text(title)
                .font(.title.bold())
                .tracking(-0.6)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
            showcase()
                .frame(maxWidth: 420)
                .padding(.top, 28)
            Spacer(minLength: 18)
            pageDots
            Button(button, action: action)
                .buttonStyle(OWCPrimaryButtonStyle())
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    /// Hours, weekdays, or skip a schedule.
    private var ready: some View {
        OnboardingSchedulePage(store: store) {
            store.applyOnboardingReminderDefaultsIfNeeded()
            showPage(OnboardingPages.reminders)
        }
    }

    /// What that schedule will do, now that lunch and reminders are set.
    private var allSet: some View {
        OnboardingReadyPage(store: store) {
            showPage(OnboardingPages.privacy)
        }
    }

    private var pageDots: some View {
        OnboardingDots(
            page: store.onboardingPage,
            includesAllSet: store.scheduleMode != .off
        )
    }

    private var includesAllSet: Bool { store.scheduleMode != .off }

    private var remindersNeedPermission: Bool {
        store.notificationMode != .off
            || store.microBreakEnabled
            || (store.lunchEnabled && (store.lunchStartReminderEnabled || store.lunchEndReminderEnabled))
    }

    private func feature(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
    }

    private func showPage(_ page: Int, reverse: Bool = false, feedback: Bool = true) {
        if feedback { navigationFeedback += 1 }
        goingBack = reverse
        withAnimation(pageAnimation) {
            store.onboardingPage = page
        }
    }

    private func goBack() {
        guard let previous = OnboardingPages.previous(
            from: store.onboardingPage,
            includesAllSet: includesAllSet
        ) else { return }
        showPage(previous, reverse: true)
    }

    private func advanceFromReminders() {
        navigationFeedback += 1
        Task {
            if remindersNeedPermission {
                _ = await notifications.request()
            }
            guard let next = OnboardingPages.next(
                from: OnboardingPages.reminders,
                includesAllSet: includesAllSet
            ) else { return }
            showPage(next, feedback: false)
        }
    }

    private func finaleLogoSize(in availableSize: CGSize) -> CGFloat {
        let widthCap: CGFloat = horizontalSizeClass == .regular ? 380 : 300
        let availableWidth = max(132, availableSize.width - 56)
        let availableHeight = max(132, availableSize.height * 0.42)
        return min(widthCap, min(availableWidth, availableHeight))
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : Self.pageAnimation
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return goingBack ? Self.backTransition : Self.forwardTransition
    }
}

/// The pages, in order. One list rather than a count repeated at every call
/// site: the indicator, the QA jump and the "which page is last" question all
/// read from here, so adding a page cannot leave one of them behind.
enum OnboardingPages {
    static let landing = 0
    static let schedule = 1
    static let reminders = 2
    static let allSet = 3
    static let privacy = 4
    static let systemSurfaces = 5
    static let adaptiveLayouts = 6
    static let finale = 7
    /// Highest page index plus one. The visible path can be shorter when
    /// there is no schedule: confirmation is skipped, but the remaining
    /// pages keep these indices so a QA jump still lands on the same screen.
    static let count = 8

    static func sequence(includesAllSet: Bool) -> [Int] {
        if includesAllSet {
            [landing, schedule, reminders, allSet, privacy, systemSurfaces, adaptiveLayouts, finale]
        } else {
            [landing, schedule, reminders, privacy, systemSurfaces, adaptiveLayouts, finale]
        }
    }

    static func next(from page: Int, includesAllSet: Bool) -> Int? {
        let pages = sequence(includesAllSet: includesAllSet)
        guard let index = pages.firstIndex(of: page), index + 1 < pages.count else { return nil }
        return pages[index + 1]
    }

    static func previous(from page: Int, includesAllSet: Bool) -> Int? {
        let pages = sequence(includesAllSet: includesAllSet)
        guard let index = pages.firstIndex(of: page), index > 0 else { return nil }
        return pages[index - 1]
    }
}

/// Always centred in the page's column.
///
/// A bare `HStack` takes its intrinsic width and lets whatever stack it sits in
/// decide where that goes, so the dots drifted from page to page: centred
/// inside the pages built on a centred `VStack`, hard left inside the ones
/// built on `VStack(alignment: .leading)`. The indicator belongs in the same
/// place on every page — it is the one element that is supposed to look
/// identical throughout, being the thing that measures progress across them.
struct OnboardingDots: View {
    let page: Int
    var includesAllSet: Bool = true

    private var pages: [Int] {
        OnboardingPages.sequence(includesAllSet: includesAllSet)
    }

    var body: some View {
        let current = pages.firstIndex(of: page) ?? 0
        HStack(spacing: 7) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(index == current ? OWCDesign.accent : OWCDesign.control)
                    .frame(width: index == current ? 20 : 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current + 1) / \(pages.count)")
    }
}

private struct OnboardingSchedulePage: View {
    @Bindable var store: OffWorkStore
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var timeField: SetupTimeField?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)
            Text(store.t("onboardingScheduleTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .multilineTextAlignment(.center)
            Text(store.t("onboardingScheduleBody"))
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)

            HStack(alignment: .timeChipCenter, spacing: 4) {
                ShiftHeroTimeButton(
                    title: store.t("startTime"),
                    time: store.timeString(store.startMinutes)
                ) { timeField = .start }
                Text(verbatim: "—")
                    .font(.title3)
                    .foregroundStyle(OWCDesign.tertiary)
                    .alignmentGuide(.timeChipCenter) { $0[VerticalAlignment.center] }
                    .accessibilityHidden(true)
                ShiftHeroTimeButton(
                    title: store.t("endTime"),
                    time: store.timeString(store.endMinutes)
                ) { timeField = .end }
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.top, 22)

            OWCGroupCard {
                modeRow(.classic, title: store.t("scheduleClassic"), subtitle: store.t("scheduleClassicDescription"))
                modeRow(.alternating, title: store.t("scheduleAlternating"), subtitle: store.t("scheduleAlternatingDescription"))
                modeRow(.rotation, title: store.t("scheduleRotation"), subtitle: store.t("scheduleRotationDescription"))
                modeRow(.off, title: store.t("scheduleOff"), subtitle: store.t("scheduleOffDescription"), isLast: true)
            }
            .padding(.top, 22)

            OnboardingScheduleDetailsView(store: store)
                .padding(.top, 18)

            Spacer(minLength: 18)

            onboardingDots
            Button(store.t("continue")) {
                if store.scheduleMode == .classic, store.workdays.isEmpty {
                    store.workdays = [1, 2, 3, 4, 5]
                }
                // Plain assignment: the page change is animated by the
                // `.animation(_:value:)` on the shell, which is what gives
                // every other page the same slide.
                onContinue()
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        // Same cap as the reminders and privacy pages. The outer
        // `minHeight: proxy.size.height` is what lets the Spacers centre this
        // page; a second `frame(maxWidth: .infinity)` here would report the
        // VStack's ideal height instead, and the form would sit against the
        // top again — the iPad landscape complaint.
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .sheet(item: $timeField) { field in
            OWCSetupTimePickerSheet(
                store: store,
                title: store.t(field == .start ? "startTime" : "endTime"),
                minutes: Binding(
                    get: { field == .start ? store.startMinutes : store.endMinutes },
                    set: { value in
                        if field == .start { store.startMinutes = value }
                        else { store.endMinutes = value }
                    }
                )
            )
            .presentationDetents([.medium])
        }
        .onAppear {
            if store.workdays.isEmpty { store.workdays = [1, 2, 3, 4, 5] }
        }
        .sensoryFeedback(.selection, trigger: store.scheduleMode)
    }

    private func modeRow(_ mode: WorkScheduleMode, title: String, subtitle: String, isLast: Bool = false) -> some View {
        let selected = store.scheduleMode == mode
        return Button {
            guard !selected else { return }
            store.scheduleMode = mode
            if mode == .alternating { store.anchorAlternatingWeekToToday() }
            if mode == .rotation { store.anchorRotationToToday() }
            if mode == .classic, store.workdays.isEmpty { store.workdays = [1, 2, 3, 4, 5] }
        } label: {
            OWCRow(
                title: title,
                subtitle: subtitle,
                isLast: isLast,
                centersVertically: true
            ) {
                ScheduleModeMark(selected: selected)
            }
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection) { content in
                content.background(selected ? OWCDesign.accent.opacity(0.07) : .clear)
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }

    private var onboardingDots: some View {
        OnboardingDots(
            page: store.onboardingPage,
            includesAllSet: store.scheduleMode != .off
        )
    }

}

/// The radio mark on a schedule-mode row.
///
/// One `Image` whose symbol changes, plus a content transition, rather than two
/// images swapped by a conditional. The row highlight responds on touch-down;
/// on commit, `.symbolEffect(.replace)` gives the circle-to-checkmark change the
/// shape SF Symbols draws deliberately instead of cross-fading two glyphs in
/// one 20 pt slot.
struct ScheduleModeMark: View {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? OWCDesign.accent : OWCDesign.tertiary)
            .contentTransition(.symbolEffect(.replace))
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: selected)
    }
}

/// A schedule confirmation screen: what the schedule they just set — plus
/// lunch and reminders from the previous page — is going to do.
///
/// The list is the real preview the setup screen shows — the same rows, from
/// the same shared rules — rather than a mock-up written for onboarding. A
/// first-run summary that disagrees with the app it is summarising is worse
/// than no summary, and this one cannot: if the schedule says the next shift
/// starts Monday at 09:00, that is because the rules said so.
private struct OnboardingReadyPage: View {
    @Bindable var store: OffWorkStore
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped once, on appear. The rows are laid out at full size from the
    /// first frame and only their opacity and offset are driven, so nothing
    /// below them moves while they arrive.
    @State private var revealed = false
    @State private var continueFeedback = 0

    var body: some View {
        let now = Date.now
        let upcoming = store.setupSnapshot(at: now).map {
            store.shiftPreview(for: $0, at: now).upcoming
        } ?? []

        VStack(spacing: 0) {
            Spacer(minLength: 8)

            Image(systemName: "calendar.badge.checkmark")
                .font(.title2.weight(.semibold))
                // The badge widens the layout box to the right of an otherwise
                // centred calendar, and SF Symbol baseline alignment sits the
                // ink slightly high. Nudge the glyph inside a chip that matches
                // the privacy page (52 / 16).
                // Optical, not geometric, centring. -0.1 is the measured
                // rest position for `calendar.badge.checkmark` in this chip.
                .offset(x: -0.1, y: 0.8)
                .foregroundStyle(OWCDesign.orangeDeep)
                .frame(width: 52, height: 52)
                .background(OWCDesign.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity)

            Text(store.t("onboardingAllSetTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            Text(store.onboardingScheduleRecap())
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("comingUp"))
                OWCGroupCard {
                    if upcoming.isEmpty {
                        OWCRow(
                            icon: "calendar.badge.minus",
                            title: store.t("scheduleOff"),
                            subtitle: store.t("scheduleOffManualStart"),
                            isLast: true
                        )
                        .owcRevealed(revealed, index: 0, reduceMotion: reduceMotion)
                    } else {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, entry in
                            ShiftPreviewRow(
                                store: store,
                                entry: entry,
                                now: now,
                                showsSeparator: index < upcoming.count - 1,
                                showsChevron: false,
                                reservesChevron: false
                            )
                            .owcRevealed(revealed, index: index, reduceMotion: reduceMotion)
                        }
                    }
                }
            }
            // Fades in with its own first row, so the page never shows an
            // empty card waiting to be filled.
            .owcRevealed(revealed, index: 0, reduceMotion: reduceMotion, travels: false)
            .padding(.top, 16)

            Spacer(minLength: 8)

            OnboardingDots(
                page: store.onboardingPage,
                includesAllSet: store.scheduleMode != .off
            )
            Button(store.t("continue")) {
                continueFeedback += 1
                onContinue()
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .sensoryFeedback(.impact(weight: .light), trigger: continueFeedback)
        .onAppear { revealed = true }
    }
}
