import SwiftUI

struct OnboardingView: View {
    // Rounded display digits; no text style is this size.
    @ScaledMetric(relativeTo: .largeTitle) private var heroNumberSize: CGFloat = 46
    @Bindable var store: OffWorkStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notifications = NotificationService()

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
                default:
                    ready
                }
            }
            .id(store.onboardingPage)
            .transition(pageTransition)
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
        .onAppear {
#if DEBUG
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "ios.native.qaOnboardingPage") != nil {
                store.onboardingPage = min(5, max(0, defaults.integer(forKey: "ios.native.qaOnboardingPage")))
                defaults.removeObject(forKey: "ios.native.qaOnboardingPage")
            }
#endif
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(.brandIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
            Text(store.t("offWorkCountdown"))
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
                    subtitle: store.t("onboardingProgressNotificationsBody")
                )
                OWCRow(
                    icon: "cup.and.saucer",
                    title: store.t("lunchBreak"),
                    subtitle: store.t("onboardingLunchNotificationsBody")
                )
                OWCRow(
                    icon: "figure.walk",
                    title: store.t("microBreakReminder"),
                    subtitle: store.t("onboardingHealthNotificationsBody"),
                    isLast: true
                )
            }
            .padding(.top, 28)
            Spacer()

            pageDots
            VStack(spacing: 10) {
                Button(store.t("notificationContinue")) {
                    Task {
                        let granted = await notifications.request()
                        if granted { store.notificationMode = .simple }
                        showPage(2)
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
                    subtitle: store.t("onboardingOfflineBody")
                )
                OWCRow(
                    icon: "briefcase",
                    title: store.t("workSchedule"),
                    subtitle: store.t("onboardingPrivacyWorkBody")
                )
                OWCRow(
                    icon: "faceid",
                    title: store.t("salarySettings"),
                    subtitle: store.t("onboardingSalaryLockBody"),
                    isLast: true
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
                Button(store.t("onboardingEnableBiometrics")) {
                    Task {
                        _ = await BiometricGate.confirmOwner(reason: store.t("unlockSalaryReason"))
                        showPage(5)
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
                Text(store.t("offWorkCountdown"))
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

    /// The last screen: no more explaining, just the app's name and the way in.
    private var ready: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(.brandIcon)
                .resizable()
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .owcShowcaseLift()
            Text(store.t("offWorkCountdown"))
                .font(.largeTitle.bold())
                .tracking(-0.8)
                .padding(.top, 24)
            Text(store.t("onboardingReadyBody"))
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 10)
            Spacer()

            pageDots
            Button(store.t("onboardingStartSetup")) {
                store.completeOnboarding(enableNotifications: false)
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<6, id: \.self) { page in
                Capsule()
                    .fill(page == store.onboardingPage ? OWCDesign.accent : OWCDesign.control)
                    .frame(width: page == store.onboardingPage ? 20 : 7, height: 7)
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
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

    private func showPage(_ page: Int) {
        withAnimation(pageAnimation) {
            store.onboardingPage = page
        }
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : Self.pageAnimation
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : Self.pageTransition
    }
}
