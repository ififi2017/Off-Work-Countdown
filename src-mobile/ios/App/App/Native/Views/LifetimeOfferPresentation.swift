import SwiftUI

/// A small, persistent entry in the timer's leading toolbar. Switching tabs
/// does not dismiss or renew the offer; the deadline belongs to PlusEntitlement.
struct LifetimeOfferToolbarButton: View {
    let plus: PlusEntitlement
    let text: AppText
    let onOpen: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if plus.canOfferLifetime, let offer = plus.lifetimeOffer, let deadline = offer.expiresAt {
            TimelineView(PausableSecondsSchedule(isPaused: scenePhase != .active)) { context in
                if offer.isActive(at: context.date) {
                    Button(action: onOpen) {
                        HStack(spacing: 7) {
                            OfferGiftIcon(size: 25)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(plus.lifetimeSavingsLabel(text: text) ?? text.t("plusOfferTitle"))
                                    .font(.caption2.weight(.bold))
                                Text(text.formatDuration(max(0, deadline.timeIntervalSince(max(context.date, offer.latestObservedAt))) * 1000))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                            }
                            .lineLimit(1)
                        }
                    }
                    .accessibilityLabel(text.t("plusOfferTitle"))
                    .accessibilityValue(text.t("plusOfferDeadline", values: ["date": text.formatDate(deadline) + " " + text.formatTime(deadline)]))
                }
            }
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

private struct GiftArtwork: View {
    var lidLift: CGFloat

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
                .offset(y: -geometry.size.height * lidLift)
            }
            .shadow(color: Color(red: 0.35, green: 0.12, blue: 0.04).opacity(0.18),
                    radius: 3 * unit, y: 3 * unit)
            .drawingGroup(opaque: false, colorMode: .extendedLinear)
            .allowedDynamicRange(.high)
        }
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

struct LifetimeOfferSheet: View {
    let plus: PlusEntitlement
    let text: AppText
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    OfferGiftIcon(size: 64).padding(.top, 20)
                    if plus.hasAvailableLifetimeOffer {
                        LifetimeOfferCard(plus: plus, text: text)
                    } else {
                        Text(text.t("plusOfferUnavailable")).foregroundStyle(OWCDesign.secondary)
                    }
                    Button(text.t("plusRestore")) { Task { await plus.restore() } }
                        .disabled(plus.isBusy)
                }
                .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(OWCDesign.page)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: plus.isAuthorized) { _, owned in if owned { dismiss() } }
        .task { plus.observeLifetimeOffer() }
        .onDisappear { plus.observeLifetimeOffer() }
    }
}
