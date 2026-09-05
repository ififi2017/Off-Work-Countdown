import SwiftUI

/// The code-native counterpart of `assets/brand/off-work-countdown-mark.svg`.
/// Keeping the ring, the hands and the endpoint separate lets the interface add
/// subtle parallax without rasterizing, tracing, or nesting an app-icon bitmap.
struct OWCBrandMark: View {
    var interactionOffset: CGSize = .zero
    var isPressed = false
    var handRotation: Angle = .zero
    var showsEndpoint = true
    var showsDepth = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    static var orangeGradient: LinearGradient {
        LinearGradient(
            colors: [OWCDesign.orange, OWCDesign.orangeDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / 1024
            let motion = reduceMotion ? CGSize.zero : interactionOffset
            ZStack(alignment: .topLeading) {
                // One quiet halo behind the crisp mark. Its geometry stays
                // fixed; interaction changes opacity rather than blur/width.
                OpenDayRing()
                    .stroke(
                        Self.orangeGradient,
                        style: StrokeStyle(lineWidth: 110 * scale, lineCap: .round)
                    )
                    .blur(radius: side * 0.025)
                    .opacity(isPressed ? 0.20 : (showsDepth ? 0.08 : 0))
                    .animation(OWCMotion.press, value: isPressed)
                    .allowsHitTesting(false)

                // The workday as a ring, broken open where the day ends.
                OpenDayRing()
                    .stroke(
                        Self.orangeGradient,
                        style: StrokeStyle(lineWidth: 110 * scale, lineCap: .round)
                    )
                    .offset(x: motion.width * -0.025, y: motion.height * -0.025)

                // Hands at 17:00. Only they carry the light/dark swap; the ring
                // and the endpoint read on either surface.
                OpenDayHands()
                    .stroke(
                        colorScheme == .dark ? OWCDesign.brandCream : OWCDesign.brandPlum,
                        style: StrokeStyle(
                            lineWidth: 88 * scale,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .rotationEffect(handRotation)
                    .offset(x: motion.width * -0.01, y: motion.height * -0.01)

                if showsEndpoint {
                    Circle()
                        .fill(Self.orangeGradient)
                        .frame(width: 172 * scale, height: 172 * scale)
                        .position(x: 664.5 * scale, y: 776.1 * scale)
                        .offset(x: motion.width * 0.09, y: motion.height * 0.09)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .shadow(
                color: showsDepth
                    ? OWCDesign.brandPlum.opacity(colorScheme == .dark ? 0.18 : 0.08)
                    : .clear,
                radius: side * 0.014,
                y: side * 0.008
            )
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        // The containing surface decides whether this mark is interactive.
        // Disabling hit testing here also disables the real Button/gesture
        // used by onboarding, About, and the draggable empty state.
        .accessibilityHidden(true)
    }

    /// Geometry mirrors the SVG master exactly: centre 512,512, radius 298, and
    /// a 262° sweep that leaves the break at five o'clock. `addRelativeArc` with
    /// a positive delta always sweeps toward increasing angle, which avoids the
    /// flipped-y ambiguity of the `clockwise:` flag.
    private struct OpenDayRing: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = min(rect.width, rect.height) / 1024
            let centre = CGPoint(x: rect.midX, y: rect.midY)

            var path = Path()
            path.addRelativeArc(
                center: centre,
                radius: 298 * scale,
                startAngle: .degrees(109),
                delta: .degrees(262)
            )
            return path
        }
    }

    private struct OpenDayHands: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = min(rect.width, rect.height) / 1024
            let origin = CGPoint(
                x: rect.midX - (512 * scale),
                y: rect.midY - (512 * scale)
            )

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + (x * scale), y: origin.y + (y * scale))
            }

            var path = Path()
            path.move(to: point(512, 347))
            path.addLine(to: point(512, 512))
            path.addLine(to: point(573, 617.7))
            return path
        }
    }
}
