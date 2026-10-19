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
    /// Where the header gift is drawn, so the layer's own gift can meet it.
    var onHeaderGiftFrame: (CGRect) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !plus.isAuthorized {
                        HStack(spacing: 14) {
                            GiftArtwork(lidLift: GiftOfferLayout.headerLidLift, lidTilt: GiftOfferLayout.headerLidTilt)
                                .frame(width: GiftOfferLayout.headerGiftSize, height: GiftOfferLayout.headerGiftSize)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onHeaderGiftFrame($0) }
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
///
/// The flying gift starts and ends on the frames the toolbar and the paywall
/// header report, at their size, so nothing jumps where they hand over. The
/// paywall is built hidden while the gift holds still and only fades in, so
/// its layout never lands in the middle of an animation.
struct GiftOfferOverlay: View {
    let plus: PlusEntitlement
    let text: AppText
    /// The toolbar gift's frame in global coordinates, when it has reported one.
    let toolbarFrame: CGRect?
    /// The flying gift is drawn over the toolbar's: hide the toolbar's.
    let onCover: () -> Void
    /// The gift has landed: let the toolbar's own gift fade back in.
    let onHandBack: () -> Void
    /// Remove this layer. Called once.
    let onFinish: () -> Void

    @State private var unwraps: Bool
    @State private var started = false
    @State private var paywallMounted = false
    @State private var paywallShown = false
    @State private var giftCenter: CGPoint?
    @State private var giftSize: CGFloat?
    @State private var lidLift: CGFloat = 0
    @State private var lidTilt: Double = 0
    @State private var rays = false
    @State private var caption = false
    @State private var backdrop = false
    @State private var openFeedback = 0
    @State private var giftOpacity: Double = 1
    @State private var headerFrame: CGRect?
    @State private var closing = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let openGiftSize: CGFloat = 150

    init(plus: PlusEntitlement, text: AppText, toolbarFrame: CGRect?,
         onCover: @escaping () -> Void, onHandBack: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.plus = plus
        self.text = text
        self.toolbarFrame = toolbarFrame
        self.onCover = onCover
        self.onHandBack = onHandBack
        self.onFinish = onFinish
        _unwraps = State(initialValue: plus.hasWrappedLifetimeOffer)
    }

    var body: some View {
        GeometryReader { geometry in
            let home = toolbarRect(in: geometry)
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(backdrop ? 1 : 0)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                if paywallMounted {
                    GiftOfferPaywall(plus: plus, text: text, onNotNow: { close(in: geometry) }, onDone: finish,
                                     translucent: true, onHeaderGiftFrame: { headerFrame = $0 })
                        .opacity(paywallShown ? 1 : 0)
                        .allowsHitTesting(paywallShown)
                        .accessibilityHidden(!paywallShown)
                }
                if !paywallShown {
                    ZStack {
                        GiftRays()
                            .frame(width: Self.openGiftSize * 1.9, height: Self.openGiftSize * 1.9)
                            .scaleEffect(rays ? 1 : 0.4)
                            .opacity(rays ? 1 : 0)
                        GiftArtwork(lidLift: lidLift, lidTilt: .degrees(lidTilt))
                            .frame(width: giftSize ?? home.width, height: giftSize ?? home.width)
                    }
                    .position(giftCenter ?? CGPoint(x: home.midX, y: home.midY))
                    .opacity(giftOpacity)
                    .allowsHitTesting(false)
                    if unwraps {
                        Text(text.t("plusGiftTitle"))
                            .font(.title2.bold())
                            .foregroundStyle(OWCDesign.primary)
                            .opacity(caption ? 1 : 0)
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
            if phase != .active, closing { finish() }
        }
    }

    /// The toolbar gift in this layer's coordinates: the reported frame, or
    /// where the bar puts a leading item when none has been reported yet.
    private func toolbarRect(in geometry: GeometryProxy) -> CGRect {
        let origin = geometry.frame(in: .global).origin
        if let toolbarFrame, toolbarFrame.width > 0 {
            return toolbarFrame.offsetBy(dx: -origin.x, dy: -origin.y)
        }
        return CGRect(x: 26, y: 3, width: 39, height: 39)
    }

    private func headerRect(in geometry: GeometryProxy) -> CGRect {
        let origin = geometry.frame(in: .global).origin
        if let headerFrame { return headerFrame.offsetBy(dx: -origin.x, dy: -origin.y) }
        let side = max(0, (geometry.size.width - GiftOfferLayout.maxWidth) / 2)
        return CGRect(x: max(OWCDesign.contentInset, side), y: GiftOfferLayout.navigationBar + GiftOfferLayout.topPadding,
                      width: GiftOfferLayout.headerGiftSize, height: GiftOfferLayout.headerGiftSize)
    }

    private func place(_ rect: CGRect) {
        giftCenter = CGPoint(x: rect.midX, y: rect.midY)
        giftSize = rect.width
    }

    /// Show the built paywall over the gift, which then steps aside.
    private func revealPaywall() async {
        paywallMounted = true
        // Two frames for the hidden page to lay out before it is shown.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(34))
        withAnimation(OWCMotion.phase) { paywallShown = true }
    }

    private func open(in geometry: GeometryProxy) async {
        let home = toolbarRect(in: geometry)
        place(home)
        // Drawn exactly over the toolbar's gift first; only then hide that one.
        await Task.yield()
        onCover()
        guard !reduceMotion else {
            backdrop = true
            if unwraps, !plus.revealLifetimeOffer(from: plus.lifetimeOffer?.source ?? .update323) {
                finish()
                return
            }
            paywallMounted = true
            paywallShown = true
            return
        }
        if unwraps { await unwrap(in: geometry) } else { await arrive(in: geometry) }
    }

    private func unwrap(in geometry: GeometryProxy) async {
        let source = plus.lifetimeOffer?.source ?? .update323
        withAnimation(OWCMotion.giftArrive) {
            giftCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.4)
            giftSize = Self.openGiftSize
            backdrop = true
        }
        try? await Task.sleep(for: .seconds(OWCMotion.giftArriveDuration))
        // Opening shows the price, so this is when the week starts.
        guard plus.revealLifetimeOffer(from: source) else {
            finish()
            return
        }
        openFeedback += 1
        withAnimation(OWCMotion.giftOpen) {
            lidLift = 0.34
            lidTilt = -24
        }
        withAnimation(OWCMotion.giftRays) {
            rays = true
            caption = true
        }
        // Build the page while the open gift holds still.
        paywallMounted = true
        try? await Task.sleep(for: .seconds(OWCMotion.giftOpenHold))
        await revealPaywall()
    }

    /// The mirror of closing: the opened gift settles into the header, then
    /// the paywall fades in around it.
    private func arrive(in geometry: GeometryProxy) async {
        paywallMounted = true
        // The hidden page reports where its header gift sits.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(34))
        withAnimation(OWCMotion.giftReturn) {
            place(headerRect(in: geometry))
            lidLift = GiftOfferLayout.headerLidLift
            lidTilt = GiftOfferLayout.headerLidTilt.degrees
            backdrop = true
        }
        try? await Task.sleep(for: .seconds(OWCMotion.giftReturnDuration))
        await revealPaywall()
    }

    private func close(in geometry: GeometryProxy) {
        guard !closing else { return }
        closing = true
        guard !reduceMotion else {
            finish()
            return
        }
        place(headerRect(in: geometry))
        lidLift = GiftOfferLayout.headerLidLift
        lidTilt = GiftOfferLayout.headerLidTilt.degrees
        rays = false
        caption = false
        withAnimation(OWCMotion.stateExit) { paywallShown = false }
        withAnimation(OWCMotion.giftReturn) {
            place(toolbarRect(in: geometry))
            lidLift = 0
            lidTilt = 0
            backdrop = false
        }
        Task {
            try? await Task.sleep(for: .seconds(OWCMotion.giftReturnDuration))
            paywallMounted = false
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
