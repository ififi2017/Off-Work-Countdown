import SwiftUI
import UIKit

enum OWCDesign {
    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let primary = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let tertiary = Color(uiColor: .tertiaryLabel)
    static let separator = Color(uiColor: .separator).opacity(0.55)
    static let control = Color(uiColor: .tertiarySystemFill)
    static let orange = Color(red: 0.976, green: 0.451, blue: 0.086)
    static let orangeDeep = Color(red: 0.918, green: 0.345, blue: 0.047)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.53, blue: 0.18, alpha: 1)
            : UIColor(red: 0.95, green: 0.35, blue: 0.04, alpha: 1)
    })

    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let rowHeight: CGFloat = 52
    static let pageInset: CGFloat = 16
    static let contentInset: CGFloat = 20
}

enum OWCSystemSettings {
    static let applicationURL = URL(string: UIApplication.openSettingsURLString)!
}

struct OWCAppHeader: View {
    @ObservedObject var store: OffWorkStore

    var body: some View {
        HStack {
            Text(store.t("offWorkCountdown"))
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.78)
                .textCase(.uppercase)
                .foregroundStyle(OWCDesign.secondary)
                .lineLimit(1)
            Spacer()
            Button { withAnimation(.snappy(duration: 0.28)) { store.toggleQuickTheme() } } label: {
                Group {
                    if store.quickThemeIsAuto {
                        Text(verbatim: "A")
                            .font(.system(size: 17, weight: .semibold))
                    } else {
                        Image(systemName: store.quickThemeIcon)
                            .font(.system(size: 17, weight: .regular))
                    }
                }
                .foregroundStyle(OWCDesign.secondary)
                .frame(width: 34, height: 34)
                .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("theme"))
        }
        .padding(.horizontal, OWCDesign.contentInset)
        .frame(height: 40)
    }

}

struct OWCSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(OWCDesign.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }
}

struct OWCGroupCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(OWCDesign.card)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }
}

struct OWCRow<Accessory: View>: View {
    let icon: String?
    let textIcon: String?
    let title: String
    let subtitle: String?
    let isLast: Bool
    let accessory: Accessory

    init(
        icon: String? = nil,
        textIcon: String? = nil,
        title: String,
        subtitle: String? = nil,
        isLast: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.textIcon = textIcon
        self.title = title
        self.subtitle = subtitle
        self.isLast = isLast
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let textIcon {
                Text(verbatim: textIcon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(width: 19)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(width: 19)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(OWCDesign.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 16)
        .frame(minHeight: OWCDesign.rowHeight)
        .overlay(alignment: .bottomTrailing) {
            if !isLast {
                Rectangle()
                    .fill(OWCDesign.separator)
                    .frame(height: 0.5)
                    .padding(.leading, icon == nil && textIcon == nil ? 16 : 47)
            }
        }
        .contentShape(Rectangle())
    }
}

extension OWCRow where Accessory == EmptyView {
    init(icon: String? = nil, textIcon: String? = nil, title: String, subtitle: String? = nil, isLast: Bool = false) {
        self.init(icon: icon, textIcon: textIcon, title: title, subtitle: subtitle, isLast: isLast) { EmptyView() }
    }
}

struct OWCDetailAccessory: View {
    let text: String?
    var external = false

    var body: some View {
        HStack(spacing: 6) {
            if let text {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OWCDesign.tertiary)
        }
    }
}

struct OWCPrimaryButtonStyle: ButtonStyle {
    var filled = true
    var color: Color = OWCDesign.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(filled ? .white : OWCDesign.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(filled ? color : OWCDesign.control)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct OWCRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? OWCDesign.control : .clear)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct OWCSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(OWCDesign.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(OWCDesign.control)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct OWCProgressMeter: View {
    let progress: Double
    var overtime = false
    var paused = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    private var fill: Color { overtime ? OWCDesign.orangeDeep : OWCDesign.accent }

    fileprivate static let bubbleHeight: CGFloat = 22
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
            let label = String(format: "%.1f%%", clamped)
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
        .task(id: burst) {
            guard burst > 0, !reduceMotion else { return }
            flakes = Self.makeFlakes(seed: burst)
            startedAt = .now
            try? await Task.sleep(for: .seconds(Self.life + 0.2))
            flakes = []
        }
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

        context.opacity = fade
        context.drawLayer { layer in
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

private struct OWCDownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct OWCPageTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 34, weight: .bold))
            .tracking(-0.7)
            .foregroundStyle(OWCDesign.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OWCDetailBackModifier: ViewModifier {
    let backTitle: String
    let pageTitle: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// Fades the control out the moment it is tapped, so it disappears in place
    /// rather than sliding off with the page — the behaviour Voice Memos has.
    /// There is deliberately no long-press menu: it opened an empty capsule.
    @State private var leaving = false

    func body(content: Content) -> some View {
        content
            // The settings roots intentionally hide UIKit's navigation bar.
            // Showing it only for a pushed page makes UIKit add its safe-area
            // inset at the end of the transition: the whole destination first
            // lands at one Y position, then jumps down. The bar therefore stays
            // hidden throughout. SwiftUI disables the edge recognizer when it is
            // hidden, and UIKit's original delegate continues rejecting it even
            // after it is enabled. The bridge below supplies the missing gate:
            // horizontal edge drags may pop, vertical drags remain scrolling.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                OWCDetailHeader(
                    backTitle: backTitle,
                    pageTitle: pageTitle,
                    compact: verticalSizeClass == .compact,
                    leaving: leaving
                ) {
                    leaving = true
                    dismiss()
                }
            }
            .background(OWCInteractivePopRestorer())
            .onAppear { leaving = false }
    }
}

private struct OWCInteractivePopRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var popRecognizer: UIGestureRecognizer?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreSystemEdgeSwipe()
        }

        private func restoreSystemEdgeSwipe() {
            guard let navigationController, navigationController.viewControllers.count > 1 else { return }
            guard let recognizer = navigationController.interactivePopGestureRecognizer else { return }
            popRecognizer = recognizer
            recognizer.delegate = self
            recognizer.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === popRecognizer else { return true }
            guard let navigationController, navigationController.viewControllers.count > 1 else { return false }
            guard navigationController.transitionCoordinator == nil else { return false }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

private struct OWCDetailHeader: View {
    let backTitle: String
    let pageTitle: String
    let compact: Bool
    let leaving: Bool
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                HStack {
                    Button(action: dismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .opacity(leaving ? 0 : 1)
                    .animation(.easeOut(duration: 0.12), value: leaving)
                    .accessibilityLabel(backTitle)
                    Spacer()
                }

                if compact {
                    Text(pageTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 58)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .frame(height: compact ? 56 : 52)

            if !compact {
                Text(pageTitle)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.7)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OWCDesign.page)
    }
}

extension View {
    func owcDetailBack(title: String, pageTitle: String) -> some View {
        modifier(OWCDetailBackModifier(backTitle: title, pageTitle: pageTitle))
    }
}

/// A numeric field that only writes its value back when editing ends.
///
/// Committing on every keystroke is what broke the keyboard: each character
/// published a store change, and `RootView.scheduleSignature` turned that into
/// a full notification + Live Activity + widget-timeline reschedule, which tore
/// down the text input session mid-typing. Editing is local; the store hears
/// about it once, on the way out.
///
/// Tapping the field also selects the whole value, so replacing "60" with "45"
/// is one tap and two digits rather than a backspace hunt.
struct OWCNumberField: View {
    let placeholder: String
    @Binding var text: String
    var decimal = false
    var maxDigits = 3
    var width: CGFloat?
    var emphasized = false
    let onCommit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(
                .system(size: emphasized ? 19 : 17, weight: .semibold)
                .monospacedDigit()
            )
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            // One deterministic width. Chaining .frame(width:) with a
            // .frame(maxWidth:) left the layout solving for two constraints at
            // once, and the keyboard's own resize could drive it negative.
            .frame(width: width ?? 170)
            .onChange(of: text) { sanitize() }
            .onChange(of: focused) {
                if !focused { onCommit() }
            }
            .onSubmit { onCommit() }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UITextField.textDidBeginEditingNotification
                )
            ) { note in
                guard let field = note.object as? UITextField else { return }
                // The field has not finished becoming first responder when the
                // notification lands, so the selection is applied on the next
                // runloop turn or it is immediately collapsed by the caret.
                DispatchQueue.main.async { field.selectAll(nil) }
            }
    }

    private func sanitize() {
        var allowed = text.filter { $0.isNumber || (decimal && ($0 == "." || $0 == ",")) }
        if decimal {
            // Keep only the first separator; "1.2.3" is not a number anybody meant.
            var seenSeparator = false
            allowed = String(allowed.compactMap { character -> Character? in
                guard character == "." || character == "," else { return character }
                if seenSeparator { return nil }
                seenSeparator = true
                return "."
            })
        }
        let capped = String(allowed.prefix(maxDigits))
        if capped != text { text = capped }
    }
}

extension View {
    /// Lifts an onboarding showcase off the page.
    ///
    /// A white rim only works against a dark ground; in light mode the card is
    /// near-white on near-white and the highlight disappeared entirely. A
    /// hairline plus a soft drop shadow reads on both — the same way iOS
    /// separates a Home Screen widget from the wallpaper behind it.
    func owcShowcaseLift() -> some View {
        self
            .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
