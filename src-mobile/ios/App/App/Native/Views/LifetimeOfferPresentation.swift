import SwiftUI

/// A small, persistent entry in the timer's leading toolbar. A wrapped gift
/// waits there until it is opened; an opened one shows its saving and the time
/// left. Switching tabs does not dismiss or renew the offer; the deadline
/// belongs to PlusEntitlement.
struct LifetimeOfferToolbarButton: View {
    let plus: PlusEntitlement
    let text: AppText
    /// The gift is open over the app; the opened one stands in for this one.
    var isHidden = false
    /// Where the gift is drawn, in global coordinates, for the opened gift
    /// to start from and land on.
    var onGiftFrame: (CGRect) -> Void = { _ in }
    let onOpen: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if plus.canOfferLifetime, let offer = plus.lifetimeOffer {
            Group {
                if let deadline = offer.expiresAt {
                    TimelineView(PausableSecondsSchedule(isPaused: scenePhase != .active)) { context in
                        if offer.isActive(at: context.date) {
                            Button(action: onOpen) {
                                HStack(spacing: 7) {
                                    OfferGiftIcon(size: 25)
                                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onGiftFrame($0) }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(plus.lifetimeSavingsLabel(text: text) ?? text.t("plusOfferTitle"))
                                            .font(.caption2.weight(.bold))
                                        Text(text.formatOfferRemaining(deadline.timeIntervalSince(max(context.date, offer.latestObservedAt))))
                                            .font(.caption.monospacedDigit().weight(.semibold))
                                    }
                                    .lineLimit(1)
                                }
                            }
                            .accessibilityLabel(text.t("plusOfferTitle"))
                            .accessibilityValue(text.t("plusOfferDeadline", values: ["date": text.formatDate(deadline) + " " + text.formatTime(deadline)]))
                        }
                    }
                    .task(id: deadline) {
                        let remaining = deadline.timeIntervalSince(max(.now, offer.latestObservedAt))
                        if remaining > 0 {
                            do { try await Task.sleep(for: .seconds(remaining)) }
                            catch { return }
                        }
                        // Refresh the parent toolbar so expiry removes the entire item,
                        // rather than leaving an empty Liquid Glass button behind.
                        plus.observeLifetimeOffer()
                    }
                } else {
                    Button(action: onOpen) {
                        OfferGiftIcon(size: 30)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onGiftFrame($0) }
                    }
                    .accessibilityLabel(text.t("plusGiftOpen"))
                }
            }
            .opacity(isHidden ? 0 : 1)
            .allowsHitTesting(!isHidden)
            // Hand over to the opened gift at once; fade back in as it lands.
            .animation(isHidden ? nil : (reduceMotion ? OWCMotion.reduced : OWCMotion.giftOverlay), value: isHidden)
            .onChange(of: scenePhase) { _, _ in plus.observeLifetimeOffer() }
            .onDisappear { plus.observeLifetimeOffer() }
        }
    }
}

/// A dimensional gift, drawn in vectors at both toolbar and invitation sizes.
/// All painted surfaces use HDR colors; motion never changes screen brightness.
struct OfferGiftIcon: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .frame(width: size * 1.3, height: size * 1.3)
            .phaseAnimator(reduceMotion || voiceOver || scenePhase != .active
                ? [GiftPhase.rest] : GiftPhase.allCases) { _, phase in
                GiftArtwork(lidLift: phase == .peek ? 0.045 : 0)
                    .frame(width: size * 1.3, height: size * 1.3)
                    .offset(y: phase == .floating || phase == .peek ? -size * 0.035 : 0)
            } animation: { phase in
                phase == .peek ? OWCMotion.offerPeek : OWCMotion.offerFloat
            }
            .accessibilityHidden(true)
    }
}

private enum GiftPhase: CaseIterable {
    case rest, floating, peek, settling
}

/// The gift itself. `lidLift` raises the lid by a fraction of the height and
/// `lidTilt` turns it about its left edge, so the same drawing can sit closed
/// in the toolbar, burst open, and settle half-open over the paywall.
struct GiftArtwork: View {
    var lidLift: CGFloat = 0
    var lidTilt: Angle = .zero
    private static let headroom: CGFloat = 0.5

    private static func hdr(_ red: Float, _ green: Float, _ blue: Float) -> Color {
        var resolved = Color.white.resolve(in: EnvironmentValues())
        resolved.linearRed = red
        resolved.linearGreen = green
        resolved.linearBlue = blue
        return Color(Color.ResolvedHDR(resolved, headroom: 1.65))
    }

    private let orange = LinearGradient(colors: [Self.hdr(1.4, 0.25, 0.025), Self.hdr(1.08, 0.085, 0.012)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    private let lidOrange = LinearGradient(colors: [Self.hdr(1.55, 0.34, 0.045), Self.hdr(1.18, 0.13, 0.018)],
                                           startPoint: .top, endPoint: .bottom)
    private let satin = LinearGradient(stops: [
        .init(color: Self.hdr(1.28, 0.86, 0.4), location: 0),
        .init(color: Self.hdr(1.65, 1.4, 0.95), location: 0.45),
        .init(color: Self.hdr(1.35, 0.96, 0.5), location: 1)
    ], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 100
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7 * unit)
                    .fill(orange)
                    .frame(width: 66 * unit, height: 49 * unit)
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 1.5 * unit)
                            .fill(Self.hdr(1.02, 0.07, 0.01))
                            .frame(width: 3 * unit, height: 36 * unit)
                            .padding(.trailing, 4 * unit)
                    }
                    .overlay {
                        Rectangle().fill(satin).frame(width: 12 * unit)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7 * unit))
                    .offset(x: 17 * unit, y: 42 * unit)

                // A shallow seam separates the removable lid from the box.
                RoundedRectangle(cornerRadius: 2 * unit)
                    .fill(Self.hdr(1.02, 0.065, 0.008))
                    .frame(width: 66 * unit, height: 4 * unit)
                    .offset(x: 17 * unit, y: 47 * unit)

                ZStack(alignment: .topLeading) {
                    GiftBow()
                        .stroke(satin, style: StrokeStyle(lineWidth: 6 * unit, lineCap: .round, lineJoin: .round))
                        .frame(width: 100 * unit, height: 100 * unit)
                    RoundedRectangle(cornerRadius: 4 * unit)
                        .fill(lidOrange)
                        .frame(width: 76 * unit, height: 16 * unit)
                        .overlay {
                            Rectangle().fill(satin).frame(width: 12 * unit)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4 * unit))
                        .offset(x: 12 * unit, y: 34 * unit)
                    RoundedRectangle(cornerRadius: 3 * unit)
                        .fill(satin)
                        .frame(width: 14 * unit, height: 10 * unit)
                        .offset(x: 43 * unit, y: 27 * unit)
                }
                .rotationEffect(lidTilt, anchor: UnitPoint(x: 0.12, y: 0.5))
                .offset(y: -geometry.size.height * lidLift)
            }
            .shadow(color: Color(red: 0.35, green: 0.12, blue: 0.04).opacity(0.18),
                    radius: 3 * unit, y: 3 * unit)
            // The offscreen buffer is only as large as its view: give a lifted,
            // tilted lid room above and beside the box before rasterising.
            .padding(Self.headroom * geometry.size.width)
            .drawingGroup(opaque: false, colorMode: .extendedLinear)
            .padding(-Self.headroom * geometry.size.width)
            .allowedDynamicRange(.high)
        }
        .accessibilityHidden(true)
    }
}

private nonisolated struct GiftBow: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 100
        return Path { path in
            path.move(to: CGPoint(x: 49 * unit, y: 32 * unit))
            path.addCurve(to: CGPoint(x: 27 * unit, y: 19 * unit),
                          control1: CGPoint(x: 25 * unit, y: 33 * unit),
                          control2: CGPoint(x: 20 * unit, y: 28 * unit))
            path.addCurve(to: CGPoint(x: 49 * unit, y: 32 * unit),
                          control1: CGPoint(x: 34 * unit, y: 8 * unit),
                          control2: CGPoint(x: 45 * unit, y: 17 * unit))
            path.move(to: CGPoint(x: 51 * unit, y: 32 * unit))
            path.addCurve(to: CGPoint(x: 73 * unit, y: 19 * unit),
                          control1: CGPoint(x: 75 * unit, y: 33 * unit),
                          control2: CGPoint(x: 80 * unit, y: 28 * unit))
            path.addCurve(to: CGPoint(x: 51 * unit, y: 32 * unit),
                          control1: CGPoint(x: 66 * unit, y: 8 * unit),
                          control2: CGPoint(x: 55 * unit, y: 17 * unit))
        }
    }
}

/// Light spilling out of an opened gift: short strokes radiating from the lid.
struct GiftRays: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
            let radius = min(size.width, size.height) / 2
            for index in 0..<9 {
                let angle = Angle.degrees(-170 + Double(index) * 20).radians
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                var path = Path()
                path.move(to: CGPoint(x: center.x + direction.x * radius * 0.55, y: center.y + direction.y * radius * 0.55))
                path.addLine(to: CGPoint(x: center.x + direction.x * radius * 0.82, y: center.y + direction.y * radius * 0.82))
                context.stroke(path, with: .color(Color(red: 1, green: 0.8, blue: 0.55)),
                               style: StrokeStyle(lineWidth: max(2, radius * 0.045), lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The first-run invitation, offered once after the introductory paywall
/// closes. It shows the same offer paywall the update gift opens onto.
struct LifetimeOfferSheet: View {
    let plus: PlusEntitlement
    let text: AppText
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GiftOfferPaywall(plus: plus, text: text, onNotNow: { dismiss() }, onDone: { dismiss() })
            .presentationDetents([.large])
            .onChange(of: plus.isAuthorized) { _, owned in if owned { dismiss() } }
            .task { plus.observeLifetimeOffer() }
            .onDisappear { plus.observeLifetimeOffer() }
    }
}
