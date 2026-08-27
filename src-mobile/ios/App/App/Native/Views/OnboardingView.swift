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
    private static let pageTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing),
        removal: .move(edge: .leading)
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
                        case 0:
                            welcome
                        case 1:
                            notificationPrimer
                        case 2:
                            systemSurfaces
                        case 3:
                            adaptiveLayouts
                        case 4:
                            privacy
                        case 5:
                            ready
                        default:
                            allSet
                        }
                    }
                    .id(store.onboardingPage)
                    .transition(pageTransition)
                    // `maxWidth: .infinity` is what centres the pages, and it
                    // has to be here because `GeometryReader` aligns its child
                    // to `.topLeading`. Before this scroll wrapper existed the
                    // parent filled the width and every page came out centred by
                    // accident; afterwards the two pages that cap themselves at
                    // 560 and stop there — the notification primer and the
                    // privacy page — were pinned to the left edge on iPad, while
                    // the pages that happened to add their own
                    // `.frame(maxWidth: .infinity)` still looked right.
                    //
                    // Fixed once here rather than on those two pages, so a page
                    // added later cannot forget it.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .animation(pageAnimation, value: store.onboardingPage)
        // The grouped background, not the plain one: cards are
        // `secondarySystemGroupedBackground`, which is pure white in light mode
        // — exactly the same white as `systemBackground` — so on a plain
        // background every card here silently vanished and its rows were left
        // floating without a container.
        .background(OWCDesign.page)
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
                showPage(1)
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.top, 16)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 12)
    }

    private var notificationPrimer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.title2.weight(.semibold))
                .foregroundStyle(OWCDesign.orangeDeep)
                .frame(width: 52, height: 52)
                .background(OWCDesign.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(store.t("enableNotificationsTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .padding(.top, 22)
            Text(store.t("mobileNotificationPrimerBody"))
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .lineSpacing(4)
                .padding(.top, 12)
            OWCGroupCard {
                OWCRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: store.t("notificationModeMilestones"),
                    subtitle: store.t("onboardingProgressNotificationsBody"),
                    centersVertically: true
                )
                OWCRow(
                    icon: "cup.and.saucer",
                    title: store.t("lunchBreak"),
                    subtitle: store.t("onboardingLunchNotificationsBody"),
                    centersVertically: true
                )
                OWCRow(
                    icon: "figure.walk",
                    title: store.t("microBreakReminder"),
                    subtitle: store.t("onboardingHealthNotificationsBody"),
                    isLast: true,
                    centersVertically: true
                )
            }
            .padding(.top, 28)
            Spacer()

            pageDots
            VStack(spacing: 10) {
                Button(store.t("notificationContinue")) {
                    navigationFeedback += 1
                    Task {
                        let granted = await notifications.request()
                        if granted { store.notificationMode = .simple }
                        showPage(2, feedback: false)
                    }
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                Button(store.t("notNow")) {
                    showPage(2)
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

    private var systemSurfaces: some View {
        onboardingShowcase(
            title: store.t("onboardingEverywhereTitle"),
            // The iPad copy drops the Dynamic Island along with its mockup.
            body: store.t(horizontalSizeClass == .regular
                          ? "onboardingEverywhereBodyTablet"
                          : "onboardingEverywhereBody"),
            button: store.t("continue")
        ) {
            VStack(spacing: 16) {
                // The Dynamic Island is an iPhone feature; showing it to an iPad
                // owner promises hardware they do not have.
                if horizontalSizeClass != .regular {
                // Compact Dynamic Island: the real one is a short pill with the
                // app glyph leading and the timer trailing, not a full-width bar.
                HStack(spacing: 0) {
                    Image(systemName: "timer")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(OWCDesign.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Spacer(minLength: 34)
                    Text(verbatim: "14:59")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .frame(width: 172, height: 37)
                .background(.black, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                }
                .owcShowcaseLift()
                }

                // Two equal halves, each centred in its own. Before, the widget
                // was pinned left at a fixed width and the ring floated in the
                // whole remainder, which left the row visibly lopsided.
                // Both cards carry the same fixed footprint, so the row hugs
                // them and centres under the copy. Letting one half stretch put
                // the pair off to one side of the title.
                HStack(spacing: 12) {
                    onboardingWidget
                    // Lock Screen circular complication: a ring with a whole
                    // percent inside, matching accessoryCircular.
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(OWCDesign.control, lineWidth: 7)
                            Circle()
                                .trim(from: 0, to: 0.73)
                                .stroke(OWCDesign.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(verbatim: "73%")
                                .font(.system(.callout, design: .rounded).bold().monospacedDigit())
                        }
                        .frame(width: 84, height: 84)
                        Text(store.t("widgetWorking"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    .padding(.vertical, 18)
                    // Same footprint as the widget beside it. Letting it grow
                    // to the full half left the ring swimming in empty card.
                    .frame(width: 150, height: 150)
                    .background(OWCDesign.card)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .owcShowcaseLift()
                }
            }
        } action: {
            showPage(3)
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
            showPage(4)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.title2.weight(.semibold))
                .foregroundStyle(OWCDesign.orangeDeep)
                .frame(width: 52, height: 52)
                .background(OWCDesign.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(store.t("onboardingPrivacyTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .padding(.top, 22)
            Text(store.t("onboardingPrivacyBody"))
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .lineSpacing(4)
                .padding(.top, 12)
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
            .padding(.top, 28)
            Spacer()

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
                        showPage(5, feedback: false)
                    }
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                Button(store.t("notNow")) { showPage(5) }
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
                Text("02:34:18")
                    .font(.system(size: heroNumberSize, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(store.t("timeLeftCaption"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                Capsule().fill(OWCDesign.control)
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(OWCDesign.accent)
                                .frame(width: proxy.size.width * 0.73)
                        }
                    }
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

    /// Mirrors the real small widget's construction — brand row, status pill,
    /// tabular countdown, bar, then percent and boundary time. Kept in the same
    /// order and weights as OffWorkCountdownWidget.smallContent so the preview
    /// is a likeness rather than a rough sketch.
    private var onboardingWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(.brandIcon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(verbatim: OWCBrand.shortName)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 7)
            HStack(spacing: 6) {
                Circle().fill(OWCDesign.accent).frame(width: 6, height: 6)
                Text(store.t("widgetWorking"))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(OWCDesign.primary.opacity(0.82))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(OWCDesign.accent.opacity(0.12), in: Capsule())
            Spacer(minLength: 6)
            Text("02:34:18")
                .font(.system(.title, design: .rounded).bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 7)
            Capsule().fill(OWCDesign.control)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(OWCDesign.accent)
                            .frame(width: proxy.size.width * 0.73)
                    }
                }
            Spacer(minLength: 5)
            HStack(spacing: 6) {
                Text(verbatim: "73%")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(OWCDesign.accent)
                Spacer(minLength: 4)
                Text(verbatim: "19:00")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
        .padding(14)
        .frame(width: 150, height: 150, alignment: .leading)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .owcShowcaseLift()
    }

    /// Hours, weekdays, or skip a schedule.
    private var ready: some View {
        OnboardingSchedulePage(store: store, onContinue: advanceToAllSet)
    }

    /// What that schedule will do, and what is left to explore.
    private var allSet: some View {
        OnboardingReadyPage(store: store) {
            store.completeOnboarding(enableNotifications: false)
        }
    }

    private var pageDots: some View {
        OnboardingDots(page: store.onboardingPage)
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

    private func showPage(_ page: Int, feedback: Bool = true) {
        if feedback { navigationFeedback += 1 }
        withAnimation(pageAnimation) {
            store.onboardingPage = page
        }
    }

    private func advanceToAllSet() {
        navigationFeedback += 1
        store.onboardingPage = OnboardingPages.allSet
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : Self.pageAnimation
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : Self.pageTransition
    }
}

/// The pages, in order. One list rather than a count repeated at every call
/// site: the indicator, the QA jump and the "which page is last" question all
/// read from here, so adding a page cannot leave one of them behind.
enum OnboardingPages {
    static let count = 7
    static let schedule = 5
    static let allSet = 6
}

/// Always centred in the page's column.
///
/// A bare `HStack` takes its intrinsic width and lets whatever stack it sits in
/// decide where that goes, so the dots drifted from page to page: centred
/// inside the pages built on a centred `VStack`, hard left inside the ones
/// built on `VStack(alignment: .leading)`. The indicator belongs in the same
/// place on every page — it is the one element that is supposed to look
/// identical throughout, being the thing that measures progress across them.
private struct OnboardingDots: View {
    let page: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<OnboardingPages.count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? OWCDesign.accent : OWCDesign.control)
                    .frame(width: index == page ? 20 : 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
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

            // All four panels are measured in the same fixed stage. Changing
            // mode therefore never makes the option card, progress dots or CTA
            // jump; only the detail content changes state.
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
        // Same cap as the notification and privacy pages. The outer
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
        OnboardingDots(page: store.onboardingPage)
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

/// The last screen: what the schedule they just set is actually going to do,
/// and the three switches that are worth knowing about before they need them.
///
/// The list is the real preview the setup screen shows — the same rows, from
/// the same shared rules — rather than a mock-up written for onboarding. A
/// first-run summary that disagrees with the app it is summarising is worse
/// than no summary, and this one cannot: if the schedule says the next shift
/// starts Monday at 09:00, that is because the rules said so.
private struct OnboardingReadyPage: View {
    @Bindable var store: OffWorkStore
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped once, on appear. The rows are laid out at full size from the
    /// first frame and only their opacity and offset are driven, so nothing
    /// below them moves while they arrive.
    @State private var revealed = false
    @State private var finishFeedback = 0

    /// Four is what fits under the copy on the smallest phone without the
    /// primary button leaving the screen. The rows are already one per *kind*
    /// of event, so four covers a shift with lunch and reminders on.
    private static let maxRows = 4

    var body: some View {
        let now = Date.now
        let upcoming = Array(
            (store.setupSnapshot(at: now).map { store.shiftPreview(for: $0, at: now).upcoming } ?? [])
                .prefix(Self.maxRows)
        )

        VStack(spacing: 0) {
            Spacer(minLength: 18)

            Image(systemName: "calendar.badge.checkmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(OWCDesign.orangeDeep)
                .frame(width: 52, height: 52)
                .background(OWCDesign.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity)

            Text(store.t("onboardingAllSetTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            Text(store.t("onboardingAllSetBody"))
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("comingUp"))
                OWCGroupCard {
                    if upcoming.isEmpty {
                        // No schedule, or hours the rules cannot place a shift
                        // in. Saying so beats an empty card, and it is the same
                        // sentence the schedule page used to describe the mode.
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
                                // Nothing on this page navigates; the button
                                // under it is the only way on. With no row
                                // tappable there is no ragged clock column to
                                // protect, so the chevron's width goes back to
                                // the times rather than sitting empty beside
                                // them.
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
            .padding(.top, 26)

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("onboardingExploreTitle"))
                OWCGroupCard {
                    OWCRow(
                        icon: "cup.and.saucer",
                        title: store.t("lunchBreak"),
                        subtitle: store.t("onboardingExploreLunchBody"),
                        centersVertically: true
                    )
                    .owcRevealed(revealed, index: exploreIndex(0, after: upcoming.count), reduceMotion: reduceMotion)
                    OWCRow(
                        icon: "figure.walk",
                        title: store.t("microBreakReminder"),
                        subtitle: store.t("onboardingExploreHealthBody"),
                        centersVertically: true
                    )
                    .owcRevealed(revealed, index: exploreIndex(1, after: upcoming.count), reduceMotion: reduceMotion)
                    OWCRow(
                        icon: "bell.badge",
                        title: store.t("offWorkReminder"),
                        subtitle: store.t("onboardingExploreReminderBody"),
                        isLast: true,
                        centersVertically: true
                    )
                    .owcRevealed(revealed, index: exploreIndex(2, after: upcoming.count), reduceMotion: reduceMotion)
                }
                Text(store.t("onboardingExploreBody"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 9)
            }
            .owcRevealed(
                revealed,
                index: exploreIndex(0, after: upcoming.count),
                reduceMotion: reduceMotion,
                travels: false
            )
            .padding(.top, 22)

            Spacer(minLength: 18)

            OnboardingDots(page: store.onboardingPage)
            Button(store.t("onboardingFinish")) {
                finishFeedback += 1
                onFinish()
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        // Same cap and inset as the notification and privacy pages.
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .sensoryFeedback(.success, trigger: finishFeedback)
        .onAppear { revealed = true }
    }

    /// Continues the stagger across the card boundary, so the two lists read as
    /// one sequence rather than two that happen to start together.
    private func exploreIndex(_ offset: Int, after rows: Int) -> Int {
        max(rows, 1) + offset
    }
}
