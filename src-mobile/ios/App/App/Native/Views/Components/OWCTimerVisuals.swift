import SwiftUI
import UIKit

struct OWCProgressMeter: View {
    let progress: Double
    /// Localised name for VoiceOver — the percentage inside the bar is drawn at
    /// a fixed size and is not a text element the screen reader can reach.
    let label: String
    var overtime = false
    var paused = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var shimmer = false

    private var fill: Color { overtime ? OWCDesign.orangeDeep : OWCDesign.accent }

    fileprivate static let bubbleHeight: CGFloat = 22
    // Fixed on purpose, in both places: the bubble's width is measured with the
    // matching UIFont below, and the bubble has to stay inside a progress bar
    // whose height does not grow. Chart annotations don't scale; neither does
    // this. The percentage is also read out via the meter's accessibility value.
    fileprivate static let bubbleFont = Font.system(size: 13, weight: .semibold).monospacedDigit()

    private static let measuringFont = UIFont.monospacedDigitSystemFont(
        ofSize: 13,
        weight: .semibold
    )

    fileprivate static func bubbleWidth(for label: String) -> CGFloat {
        let measured = (label as NSString)
            .size(withAttributes: [.font: measuringFont])
            .width
        return max(bubbleHeight + 12, ceil(measured) + 18)
    }

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(100, max(0, progress))
            let width = max(8, proxy.size.width * clamped / 100)
            let label = (clamped / 100).formatted(
                .percent.precision(.fractionLength(1)).locale(locale)
            )
            // Measured, not assumed: a fixed width cannot hold both "0.0%" and
            // "100.0%", and the wide case is exactly the one that overflowed.
            let bubbleWidth = Self.bubbleWidth(for: label)
            let pointerWidth: CGFloat = 12
            let targetX = proxy.size.width * clamped / 100
            // Same construction as the Web progress bar (components/ProgressBar.tsx):
            // the pointer is anchored to the progress position and never moves,
            // and the bubble slides around it. Clamping the pointer instead is
            // what made it miss the mark at 0% and 100% — it ran out of travel
            // before the fill did.
            let halfBubble = bubbleWidth / 2
            // The bubble may hang this far past the track, into the page inset.
            let allowedOverflow: CGFloat = 14
            // Half the pointer plus the corner radius, so the pointer's base
            // always lands on the bubble's flat edge rather than its curve.
            let pointerInset = pointerWidth / 2 + Self.bubbleHeight / 2
            let clampedCentre = min(
                max(targetX, halfBubble - allowedOverflow),
                proxy.size.width - halfBubble + allowedOverflow
            )
            let maxShift = max(0, halfBubble - pointerInset)
            let bubbleShift = min(max(clampedCentre - targetX, -maxShift), maxShift)
            let bubbleX = targetX - halfBubble + bubbleShift
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(OWCDesign.control)
                    .overlay {
                        if paused, !reduceMotion {
                            LinearGradient(
                                colors: [.clear, Color(uiColor: .systemBackground).opacity(0.88), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: proxy.size.width * 0.42)
                            .offset(x: shimmer ? proxy.size.width : -proxy.size.width)
                            // Declared here rather than at the mutation site so
                            // it outranks the animation-free transaction below:
                            // the inner modifier sets the transaction last.
                            .animation(
                                .linear(duration: 1.35).repeatForever(autoreverses: false),
                                value: shimmer
                            )
                        }
                    }
                    .clipShape(Capsule())
                Capsule()
                    .fill(paused ? OWCDesign.secondary.opacity(0.55) : fill)
                    .frame(width: width)
            }
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Text(label)
                        .font(Self.bubbleFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: bubbleWidth, height: Self.bubbleHeight)
                        .background(paused ? OWCDesign.secondary : fill)
                        .clipShape(Capsule())
                        .offset(x: bubbleX)
                    OWCDownTriangle()
                        .fill(paused ? OWCDesign.secondary : fill)
                        .frame(width: pointerWidth, height: 6)
                        // Anchored to the progress position, not to the bubble.
                        // -0.5 tucks it under the bubble so the two read as one
                        // shape instead of a bubble and a loose chevron.
                        .offset(x: targetX - pointerWidth / 2, y: Self.bubbleHeight - 0.5)
                }
                .offset(y: -28)
            }
            .onAppear { shimmer = paused && !reduceMotion }
            // The bar can start shimmering without the view reappearing — the
            // lunch break begins while the screen is already in front.
            .onChange(of: paused) { shimmer = paused && !reduceMotion }
        }
        .frame(height: 8)
        .padding(.top, 27)
        // Every number here is recomputed each second from a TimelineView, so
        // none of this geometry should ever interpolate. Left to itself the
        // meter inherited whatever transition an ancestor happened to be
        // running — the onboarding cross-fade — and the first layout pass, which
        // reports a zero-sized proxy, became an animation: the bar crawled in
        // from the left and the track unrolled from the top. One guard at the
        // boundary, rather than one per leaf, because every leaf inside reads
        // that same proxy.
        .transaction { $0.animation = nil }
        // The percentage is drawn at a fixed size inside the bar, so state it
        // here instead — this is the only way a VoiceOver user gets the number.
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Text((min(100, max(0, progress)) / 100)
            .formatted(.percent.precision(.fractionLength(0)).locale(locale))))
    }
}

/// Celebration burst for the end of a shift.
///
/// Driven by a counter, not a flag: replaying is `burst += 1` and never depends
/// on toggling a boolean back to false first.
///
/// Every flake is a real projectile — launch angle, speed, air drag, gravity,
/// its own spin and a sideways flutter — because confetti that simply falls
/// from the top of the screen at a constant rate reads as a loading indicator,
/// not a celebration. The paper flip is faked by scaling width with the spin,
/// and the back of each flake is drawn darker so the turn is visible.
struct OWCConfettiOverlay: View {
    let burst: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flakes: [Flake] = []
    @State private var startedAt = Date.distantPast

    private static let life: Double = 5.0

    var body: some View {
        TimelineView(.animation(paused: flakes.isEmpty)) { timeline in
            Canvas { context, size in
                guard !flakes.isEmpty else { return }
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                for flake in flakes {
                    draw(flake, at: elapsed, in: &context, size: size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        // Driven by `onChange`, not `.task(id:)`. The task restarts every time
        // the overlay leaves and returns — switching tabs — and would fire the
        // same burst again. `onChange` only runs when the counter actually
        // moves, which is a new celebration or a tap to replay.
        .onChange(of: burst) { _, newBurst in
            startBurst(newBurst)
        }
        .task(id: burst) {
            guard burst > 0 else { return }
            try? await Task.sleep(for: .seconds(Self.life + 0.2))
            guard !Task.isCancelled else { return }
            flakes = []
        }
    }

    private func startBurst(_ burst: Int) {
        guard burst > 0, !reduceMotion else { return }
        flakes = Self.makeFlakes(seed: burst)
        startedAt = .now
    }

    private func draw(
        _ flake: Flake,
        at elapsed: Double,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let t = elapsed - flake.delay
        guard t > 0, t < flake.life else { return }

        // Drag bleeds the launch impulse away, so flakes decelerate outward and
        // then fall under gravity instead of flying in straight lines.
        let drag = (1 - exp(-t * flake.drag)) / flake.drag
        let x = flake.origin.x * size.width
            + flake.velocity.dx * drag
            + sin(t * flake.flutterRate + flake.tilt) * flake.flutter
        let y = flake.origin.y * size.height
            + flake.velocity.dy * drag
            + 0.5 * 980 * t * t * flake.weight

        guard y < size.height + 40 else { return }

        let progress = t / flake.life
        // Hold full opacity for most of the flight, then fade — fading from the
        // first frame makes the burst look weak at the moment it should peak.
        let fade = progress < 0.72 ? 1 : max(0, 1 - (progress - 0.72) / 0.28)
        let spin = flake.spinPhase + t * flake.spin
        let flip = cos(spin)
        let width = flake.size.width * max(0.16, abs(flip))

        // Each flake has one fill: a copied graphics state preserves its
        // transform and opacity without allocating a compositing layer.
        var layer = context
        layer.opacity = fade
        layer.translateBy(x: x, y: y)
        layer.rotate(by: .radians(flake.tilt + t * flake.spin * 0.35))
        let rect = CGRect(
            x: -width / 2,
            y: -flake.size.height / 2,
            width: width,
            height: flake.size.height
        )
        let color = flip < 0 ? flake.color.opacity(0.55) : flake.color
        switch flake.shape {
        case .strip:
            layer.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
        case .dot:
            layer.fill(Path(ellipseIn: rect), with: .color(color))
        case .ribbon:
            layer.fill(
                Path(roundedRect: rect, cornerRadius: rect.width / 2),
                with: .color(color)
            )
        }
    }

    // MARK: - Particles

    fileprivate struct Flake {
        enum Kind { case strip, dot, ribbon }
        let origin: CGPoint
        let velocity: CGVector
        let size: CGSize
        let color: Color
        let shape: Kind
        let spin: Double
        let spinPhase: Double
        let tilt: Double
        let flutter: Double
        let flutterRate: Double
        let drag: Double
        let weight: Double
        let delay: Double
        let life: Double
    }

    private static let palette: [Color] = [
        OWCDesign.orange,
        Color(red: 0.98, green: 0.75, blue: 0.18),
        .white,
        Color(red: 0.99, green: 0.42, blue: 0.44),
        Color(red: 0.30, green: 0.78, blue: 0.78),
        Color(red: 0.62, green: 0.55, blue: 0.98),
    ]

    private static func makeFlakes(seed: Int) -> [Flake] {
        var rng = SeededGenerator(seed: UInt64(seed &* 7919 &+ 13))
        var result: [Flake] = []

        // Coverage first: two corner cannons open, a centre pop follows, and a
        // curtain falls the whole width for the rest of the five seconds. A
        // single burst empties the top half of the screen after a second and
        // leaves the celebration looking over before it is.
        struct Cannon {
            let origin: (x: ClosedRange<Double>, y: Double)
            let aim: Double
            let spread: Double
            let count: Int
            let delay: ClosedRange<Double>
            let speed: ClosedRange<Double>
            let weight: ClosedRange<Double>
        }

        let cannons: [Cannon] = [
            // Lower corners, firing inward and up.
            Cannon(origin: (-0.02...(-0.02), 1.02), aim: -.pi / 3.1, spread: 0.44,
                   count: 44, delay: 0...0.06, speed: 950...1420, weight: 0.75...1.1),
            Cannon(origin: (1.02...1.02, 1.02), aim: -.pi + .pi / 3.1, spread: 0.44,
                   count: 44, delay: 0.03...0.09, speed: 950...1420, weight: 0.75...1.1),
            // Centre pop, so the middle of the screen is not empty.
            Cannon(origin: (0.42...0.58, 0.44), aim: -.pi / 2, spread: .pi,
                   count: 30, delay: 0.22...0.34, speed: 380...820, weight: 0.7...1.0),
            // The curtain: staggered across the full width and most of the run,
            // drifting rather than launched.
            Cannon(origin: (0...1, -0.06), aim: .pi / 2, spread: 0.5,
                   count: 72, delay: 0.15...2.9, speed: 60...190, weight: 0.5...0.9),
        ]

        for cannon in cannons {
            for _ in 0..<cannon.count {
                let angle = cannon.aim + rng.double(in: -cannon.spread...cannon.spread)
                let speed = rng.double(in: cannon.speed)
                let kind: Flake.Kind = {
                    let roll = rng.double(in: 0...1)
                    if roll < 0.62 { return .strip }
                    if roll < 0.84 { return .ribbon }
                    return .dot
                }()
                let width = kind == .dot
                    ? rng.double(in: 5...8)
                    : rng.double(in: 6...10)
                let height = kind == .strip
                    ? rng.double(in: 9...16)
                    : (kind == .ribbon ? rng.double(in: 3...5) : width)
                let delay = rng.double(in: cannon.delay)
                result.append(
                    Flake(
                        origin: CGPoint(
                            x: rng.double(in: cannon.origin.x),
                            y: cannon.origin.y
                        ),
                        velocity: CGVector(
                            dx: cos(angle) * speed,
                            dy: sin(angle) * speed
                        ),
                        size: CGSize(width: width, height: height),
                        color: palette[Int(rng.next() % UInt64(palette.count))],
                        shape: kind,
                        spin: rng.double(in: 5...15) * (rng.bool() ? 1 : -1),
                        spinPhase: rng.double(in: 0...(2 * .pi)),
                        tilt: rng.double(in: 0...(2 * .pi)),
                        flutter: rng.double(in: 8...26),
                        flutterRate: rng.double(in: 3...8),
                        drag: rng.double(in: 2.4...3.6),
                        weight: rng.double(in: cannon.weight),
                        delay: delay,
                        // Everything still has time to cross the screen before
                        // the run ends; nothing should freeze mid-air.
                        life: max(1.6, life - delay - rng.double(in: 0...0.4))
                    )
                )
            }
        }
        return result
    }
}

/// Deterministic per burst, so a replay of the same burst looks identical and
/// two different bursts do not.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() % 1_000_000) / 1_000_000
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func bool() -> Bool { next() % 2 == 0 }
}

private nonisolated struct OWCDownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

