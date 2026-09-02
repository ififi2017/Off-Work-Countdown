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
            let ringGlowLineWidth = (isPressed ? 176 : 142) * scale
            let ringGlowBlur = (isPressed ? 11 : 8) * scale
            let endpointGlowSide = (isPressed ? 272 : 224) * scale

            ZStack(alignment: .topLeading) {
                // The mark's interactive response should belong to the whole
                // clock, not just the endpoint. A soft duplicate of the ring
                // makes the pressed/celebrating state read as one expanding
                // light, while the crisp stroke below keeps the logo legible.
                if showsDepth || isPressed {
                    OpenDayRing()
                        .stroke(
                            Self.orangeGradient.opacity(isPressed ? 0.52 : 0.24),
                            style: StrokeStyle(
                                lineWidth: ringGlowLineWidth,
                                lineCap: .round
                            )
                        )
                        .blur(radius: ringGlowBlur)
                        .opacity(isPressed && reduceMotion ? 0.7 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

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
                    // Give the endpoint the same ambient field as the outer
                    // ring. The existing glass effect remains the crisp,
                    // interactive surface; this layer supplies the diffuse
                    // halo that was previously visible only on the hands.
                    if showsDepth || isPressed {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        OWCDesign.orange.opacity(isPressed ? 0.38 : 0.2),
                                        OWCDesign.orange.opacity(isPressed ? 0.14 : 0.06),
                                        .clear,
                                    ],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: endpointGlowSide * 0.5
                                )
                            )
                            .frame(width: endpointGlowSide, height: endpointGlowSide)
                            .blur(radius: (isPressed ? 8 : 6) * scale)
                            .scaleEffect(isPressed && !reduceMotion ? 1.08 : 1)
                            .position(x: 664.5 * scale, y: 776.1 * scale)
                            .offset(x: motion.width * 0.09, y: motion.height * 0.09)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    Circle()
                        .fill(Self.orangeGradient)
                        .frame(width: 172 * scale, height: 172 * scale)
                        .glassEffect(
                            .regular.tint(OWCDesign.orange.opacity(0.32)).interactive(),
                            in: Circle()
                        )
                        .scaleEffect(isPressed && !reduceMotion ? 0.92 : 1)
                        .shadow(
                            color: OWCDesign.orange.opacity(isPressed ? 0.32 : (showsDepth ? 0.16 : 0)),
                            radius: (isPressed ? 12 : 7) * scale
                        )
                        .position(x: 664.5 * scale, y: 776.1 * scale)
                        .offset(x: motion.width * 0.09, y: motion.height * 0.09)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            // Keep the brand mark crisp while giving it a believable place on
            // the surface: a close plum shadow for elevation, then a wider
            // ambient glow and a soft contact shadow underneath. The backdrop
            // is added after `.shadow`, so the glow itself never casts a grey
            // halo.
            .shadow(
                color: showsDepth
                    ? OWCDesign.brandPlum.opacity(colorScheme == .dark ? 0.48 : 0.13)
                    : .clear,
                radius: max(2, side * 0.022),
                y: max(2, side * 0.016)
            )
            .background {
                if showsDepth {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        OWCDesign.orange.opacity(colorScheme == .dark ? 0.22 : 0.17),
                                        OWCDesign.orange.opacity(colorScheme == .dark ? 0.055 : 0.035),
                                        .clear,
                                    ],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: side * 0.56
                                )
                            )
                            .frame(width: side * 1.14, height: side * 1.14)

                        Ellipse()
                            .fill(
                                OWCDesign.brandPlum.opacity(
                                    colorScheme == .dark ? 0.28 : 0.075
                                )
                            )
                            .frame(width: side * 0.42, height: side * 0.06)
                            .blur(radius: side * 0.024)
                            .offset(y: side * 0.345)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(reduceMotion ? nil : OWCMotion.press, value: isPressed)
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
