import SwiftUI

/// The interactive form of the code-native brand mark used where a user may
/// reasonably stop and explore it: onboarding, About, and the no-shift state.
struct CelebratingBrandMark: View {
    enum EasterEgg {
        case clockSpin
        case readyNudge
    }

    var showsDepth = false
    var easterEgg: EasterEgg = .clockSpin

    private static let tapThreshold = 5
    private static let designCanvasSide: CGFloat = 1024
    private static let endpointCenter = CGPoint(x: 664.5, y: 776.1)
    private static let endpointDiameter: CGFloat = 172
    private static let minimumHitDiameter: CGFloat = 44
    private static let tapTravelLimit: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var tapCount = 0
    @State private var handRotation = 0.0
    @State private var reducedPulse = false
    @State private var readyNudge = false
    @State private var isCelebrating = false
    @State private var gestureIsActive = false
    @State private var pressFeedback = 0
    @State private var releaseFeedback = 0
    @State private var celebrationFeedback = 0

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / Self.designCanvasSide
            let origin = CGPoint(
                x: (geometry.size.width - side) / 2,
                y: (geometry.size.height - side) / 2
            )
            let hitDiameter = max(
                Self.minimumHitDiameter,
                Self.endpointDiameter * scale
            )
            let visualDiameter = Self.endpointDiameter * scale

            ZStack(alignment: .topLeading) {
                OWCBrandMark(
                    handRotation: .degrees(handRotation),
                    showsEndpoint: false,
                    showsDepth: showsDepth
                )
                .opacity(reducedPulse ? 0.55 : 1)
                .scaleEffect(readyNudge && !reduceMotion ? 1.025 : 1)
                .offset(y: readyNudge && !reduceMotion ? -6 : 0)

                // The gesture is attached to the actual glass view rather than
                // a sibling overlay. `.interactive()` can therefore supply its
                // native optical response while the logo itself stays fixed.
                Circle()
                    .fill(OWCBrandMark.orangeGradient)
                    .frame(width: visualDiameter, height: visualDiameter)
                    .glassEffect(
                        .regular.tint(OWCDesign.orange.opacity(0.32)).interactive(),
                        in: Circle()
                    )
                    .shadow(
                        color: showsDepth
                            ? OWCDesign.brandPlum.opacity(colorScheme == .dark ? 0.44 : 0.11)
                            : .clear,
                        radius: max(2, side * 0.022),
                        y: max(1, side * 0.016)
                    )
                    .scaleEffect(readyNudge && !reduceMotion ? 1.10 : 1)
                    .offset(y: readyNudge && !reduceMotion ? -8 : 0)
                    // Keep Apple's 44 pt touch target without enlarging the
                    // visible endpoint or making the ring tappable.
                    .frame(width: hitDiameter, height: hitDiameter)
                    .contentShape(Circle())
                    .position(
                        x: origin.x + Self.endpointCenter.x * scale,
                        y: origin.y + Self.endpointCenter.y * scale
                    )
                    .gesture(endpointGesture)
                    .accessibilityLabel(Text(verbatim: OWCBrand.shortName))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        registerTap()
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: pressFeedback)
        .sensoryFeedback(.selection, trigger: releaseFeedback)
        .sensoryFeedback(.success, trigger: celebrationFeedback)
    }

    private var endpointGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !gestureIsActive else { return }
                gestureIsActive = true
                pressFeedback += 1
            }
            .onEnded(handleEndpointGestureEnded)
    }

    private func handleEndpointGestureEnded(_ value: DragGesture.Value) {
        gestureIsActive = false

        let stayedNearEndpoint = max(
            abs(value.translation.width),
            abs(value.translation.height)
        ) <= Self.tapTravelLimit

        if stayedNearEndpoint {
            registerTap()
        } else {
            releaseFeedback += 1
        }
    }

    private func registerTap() {
        guard !isCelebrating else { return }
        tapCount += 1
        guard tapCount >= Self.tapThreshold else { return }

        tapCount = 0
        isCelebrating = true
        celebrationFeedback += 1

        if reduceMotion {
            playReducedCelebration()
        } else {
            switch easterEgg {
            case .clockSpin:
                playHandRotation()
            case .readyNudge:
                playReadyNudge()
            }
        }
    }

    private func playHandRotation() {
        withAnimation(OWCMotion.brandCelebration) {
            // Keep the accumulated angle instead of snapping from 360 back to
            // zero at completion. Both render at five o'clock, but retaining
            // the animated value guarantees the full path is visible on a
            // physical device and lets a later celebration continue to 720.
            handRotation += 360
        } completion: {
            isCelebrating = false
        }
    }

    private func playReducedCelebration() {
        withAnimation(OWCMotion.reduced) {
            reducedPulse = true
        } completion: {
            withAnimation(OWCMotion.reduced) {
                reducedPulse = false
            } completion: {
                isCelebrating = false
            }
        }
    }

    private func playReadyNudge() {
        withAnimation(OWCMotion.brandNudge) {
            readyNudge = true
        } completion: {
            withAnimation(OWCMotion.brandSettle) {
                readyNudge = false
            } completion: {
                isCelebrating = false
            }
        }
    }
}
