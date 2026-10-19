import SwiftUI

/// The lifetime offer as a paywall: the opened gift and what the offer is,
/// the Plus scenes to swipe through, then the plans with the offer's price
/// preselected.
struct GiftOfferPaywall: View {
    let plus: PlusEntitlement
    let text: AppText
    let onNotNow: () -> Void
    let onDone: () -> Void
    /// Over the app, the page sits on the gift layer's frosted glass rather
    /// than an opaque page, which turned solid black in Dark Mode.
    var translucent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !plus.isAuthorized {
                        HStack(spacing: 14) {
                            GiftArtwork(lidLift: GiftOfferLayout.headerLidLift, lidTilt: GiftOfferLayout.headerLidTilt)
                                .frame(width: GiftOfferLayout.headerGiftSize, height: GiftOfferLayout.headerGiftSize)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(text.t("plusOfferTitle"))
                                    .font(.title2.bold())
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.isHeader)
                                Text(text.t(plus.lifetimeOffer?.source == .update323 ? "plusGiftSubtitle" : "plusOfferWelcome"))
                                    .font(.subheadline)
                                    .foregroundStyle(OWCDesign.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        PlusFeatureCarousel(text: text)
                    }
                    PaywallContent(
                        plus: plus,
                        text: text,
                        showsBenefits: false,
                        showsIntro: false,
                        authorizedAction: onDone
                    )
                }
                .frame(maxWidth: GiftOfferLayout.maxWidth, alignment: .leading)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, GiftOfferLayout.topPadding)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(translucent ? AnyShapeStyle(Color.clear) : AnyShapeStyle(OWCDesign.page))
            .containerBackground(translucent ? AnyShapeStyle(Color.clear) : AnyShapeStyle(OWCDesign.page), for: .navigation)
            .toolbar {
                if !plus.isAuthorized {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(text.t("notNow"), action: onNotNow)
                    }
                }
            }
        }
        .tint(OWCDesign.accent)
    }
}

/// Where the paywall's gift sits, so the closing gift can start from it.
private enum GiftOfferLayout {
    static let headerGiftSize: CGFloat = 72
    static let headerLidLift: CGFloat = 0.14
    static let headerLidTilt: Angle = .degrees(-12)
    static let topPadding: CGFloat = 8
    static let maxWidth: CGFloat = 560
    /// An inline navigation bar's height.
    static let navigationBar: CGFloat = 44
}

/// The update gift, opened over the app: it leaves the timer's toolbar, its
/// lid springs off, and the offer paywall takes its place. "Not now" closes
/// the gift and sends it back to the toolbar, where its countdown runs.
struct GiftOfferOverlay: View {
    let plus: PlusEntitlement
    let text: AppText
    /// The gift has landed: let the toolbar's own gift fade back in.
    let onHandBack: () -> Void
    /// Remove this layer. Called once, after the hand-back has faded.
    let onFinish: () -> Void

    /// `opening` unwraps a new gift; `arriving` carries an already opened
    /// one from the toolbar into the paywall's header.
    private enum Phase { case opening, arriving, paywall, closing }
    @State private var phase: Phase
    @State private var started = false
    @State private var giftCenter: CGPoint?
    @State private var giftSize: CGFloat = GiftOfferOverlay.toolbarGiftSize
    @State private var lidLift: CGFloat = 0
    @State private var lidTilt: Double = 0
    @State private var rays = false
    @State private var backdrop = false
    @State private var openFeedback = 0
    @State private var giftOpacity: Double = 1
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The toolbar gift's drawn size (OfferGiftIcon at 30 pt draws 1.3×).
    private static let toolbarGiftSize: CGFloat = 38
    private static let openGiftSize: CGFloat = 150

    init(plus: PlusEntitlement, text: AppText, onHandBack: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.plus = plus
        self.text = text
        self.onHandBack = onHandBack
        self.onFinish = onFinish
        _phase = State(initialValue: plus.hasWrappedLifetimeOffer ? .opening : .arriving)
    }

    var body: some View {
        GeometryReader { geometry in
            let home = Self.toolbarPoint
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(backdrop || phase == .paywall ? 1 : 0)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                if phase == .paywall {
                    GiftOfferPaywall(plus: plus, text: text, onNotNow: { close(in: geometry) }, onDone: finish,
                                     translucent: true)
                        .transition(.opacity)
                } else {
                    ZStack {
                        GiftRays()
                            .frame(width: giftSize * 1.9, height: giftSize * 1.9)
                            .scaleEffect(rays ? 1 : 0.4)
                            .opacity(rays ? 1 : 0)
                        GiftArtwork(lidLift: lidLift, lidTilt: .degrees(lidTilt))
                            .frame(width: giftSize, height: giftSize)
                    }
                    .position(giftCenter ?? home)
                    .opacity(giftOpacity)
                    // Takes over from the paywall's gift at once, in its place.
                    .transition(.identity)
                    if phase == .opening {
                        Text(text.t("plusGiftTitle"))
                            .font(.title2.bold())
                            .foregroundStyle(OWCDesign.primary)
                            .opacity(rays ? 1 : 0)
                            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.4 + Self.openGiftSize * 0.75)
                    }
                }
            }
            .task {
                guard !started else { return }
                started = true
                await open(in: geometry)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: openFeedback)
        // Leaving the app mid-animation must not strand this layer over the timer.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, self.phase == .closing { finish() }
        }
    }

    /// The toolbar's leading item: the bar's own inset plus half the button.
    private static let toolbarPoint = CGPoint(x: 16 + 29, y: GiftOfferLayout.navigationBar / 2)

    private func headerPoint(in geometry: GeometryProxy) -> CGPoint {
        let side = max(0, (geometry.size.width - GiftOfferLayout.maxWidth) / 2)
        return CGPoint(
            x: max(OWCDesign.contentInset, side) + GiftOfferLayout.headerGiftSize / 2,
            y: GiftOfferLayout.navigationBar + GiftOfferLayout.topPadding + GiftOfferLayout.headerGiftSize / 2
        )
    }

    private func open(in geometry: GeometryProxy) async {
        if phase == .arriving {
            await arrive(in: geometry)
            return
        }
        guard phase == .opening else { return }
        let source = plus.lifetimeOffer?.source ?? .update323
        guard !reduceMotion else {
            if plus.revealLifetimeOffer(from: source) { phase = .paywall } else { onFinish() }
            return
        }
        giftCenter = Self.toolbarPoint
        // Let the gift be drawn where the toolbar's was before it leaves, so
        // the flight starts from there instead of jumping to the middle.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(16))
        withAnimation(OWCMotion.giftArrive) {
            giftCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.4)
            giftSize = Self.openGiftSize
            backdrop = true
        }
        try? await Task.sleep(for: .seconds(OWCMotion.giftArriveDuration))
        // Opening shows the price, so this is when the week starts.
        guard plus.revealLifetimeOffer(from: source) else {
            onFinish()
            return
        }
        openFeedback += 1
        withAnimation(OWCMotion.giftOpen) {
            lidLift = 0.34
            lidTilt = -24
        }
        withAnimation(OWCMotion.giftRays) { rays = true }
        try? await Task.sleep(for: .seconds(OWCMotion.giftOpenHold))
        withAnimation(OWCMotion.phase) { phase = .paywall }
    }

    /// The mirror of closing: the opened gift settles into the header, then
    /// the paywall fades in around it.
    private func arrive(in geometry: GeometryProxy) async {
        guard !reduceMotion else {
            withAnimation(OWCMotion.reduced) { phase = .paywall }
            return
        }
        giftCenter = Self.toolbarPoint
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(16))
        withAnimation(OWCMotion.giftReturn) {
            giftCenter = headerPoint(in: geometry)
            giftSize = GiftOfferLayout.headerGiftSize
            lidLift = GiftOfferLayout.headerLidLift
            lidTilt = GiftOfferLayout.headerLidTilt.degrees
            backdrop = true
        }
        try? await Task.sleep(for: .seconds(OWCMotion.giftReturnDuration))
        withAnimation(OWCMotion.phase) { phase = .paywall }
    }

    private func close(in geometry: GeometryProxy) {
        guard !reduceMotion else {
            finish()
            return
        }
        giftCenter = headerPoint(in: geometry)
        giftSize = GiftOfferLayout.headerGiftSize
        lidLift = GiftOfferLayout.headerLidLift
        lidTilt = GiftOfferLayout.headerLidTilt.degrees
        rays = false
        backdrop = true
        withAnimation(OWCMotion.stateExit) { phase = .closing }
        withAnimation(OWCMotion.giftReturn) {
            lidLift = 0
            lidTilt = 0
            giftCenter = Self.toolbarPoint
            giftSize = Self.toolbarGiftSize
            backdrop = false
        }
        Task {
            try? await Task.sleep(for: .seconds(OWCMotion.giftReturnDuration))
            // Cross-fade with the toolbar's gift, then leave without relying
            // on a removal transition finishing.
            withAnimation(OWCMotion.giftOverlay) { giftOpacity = 0 }
            onHandBack()
            try? await Task.sleep(for: .seconds(OWCMotion.giftOverlayDuration))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onHandBack()
        onFinish()
    }
}
