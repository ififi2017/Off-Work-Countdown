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
                Image(systemName: store.quickThemeIcon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(width: 34, height: 34)
                    .background(OWCDesign.control)
                    .clipShape(Circle())
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
    let title: String
    let subtitle: String?
    let isLast: Bool
    let accessory: Accessory

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        isLast: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isLast = isLast
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
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
                    .padding(.leading, icon == nil ? 16 : 47)
            }
        }
        .contentShape(Rectangle())
    }
}

extension OWCRow where Accessory == EmptyView {
    init(icon: String? = nil, title: String, subtitle: String? = nil, isLast: Bool = false) {
        self.init(icon: icon, title: title, subtitle: subtitle, isLast: isLast) { EmptyView() }
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

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(100, max(0, progress))
            let width = max(8, proxy.size.width * clamped / 100)
            let bubbleWidth: CGFloat = 60
            let pointerWidth: CGFloat = 12
            let targetX = proxy.size.width * clamped / 100
            let bubbleX = min(max(0, targetX - bubbleWidth / 2), max(0, proxy.size.width - bubbleWidth))
            let pointerX = min(max(0, targetX - bubbleX - pointerWidth / 2), bubbleWidth - pointerWidth)
            let bubbleEdge: OWCProgressBubbleShape.Edge = bubbleX <= 0.5
                ? .leading
                : (bubbleX + bubbleWidth >= proxy.size.width - 0.5 ? .trailing : .none)
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
                        }
                    }
                    .clipShape(Capsule())
                Capsule()
                    .fill(paused ? OWCDesign.secondary.opacity(0.55) : fill)
                    .frame(width: width)
            }
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Text(String(format: "%.1f%%", clamped))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: bubbleWidth, height: 22)
                        .background(paused ? OWCDesign.secondary : fill)
                        .clipShape(OWCProgressBubbleShape(edge: bubbleEdge))
                        .offset(x: bubbleX)
                    OWCDownTriangle()
                        .fill(paused ? OWCDesign.secondary : fill)
                        .frame(width: pointerWidth, height: 6)
                        .offset(x: bubbleX + pointerX, y: 22)
                }
                .offset(y: -28)
            }
            .onAppear {
                guard paused, !reduceMotion else { return }
                shimmer = false
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
        }
        .frame(height: 8)
        .padding(.top, 27)
    }
}

struct OWCConfettiOverlay: View {
    let isActive: Bool
    @State private var startedAt = Date.now

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors: [Color] = [OWCDesign.accent, .pink, .yellow, .mint, .cyan, .purple, .orange, .white]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive)) { timeline in
            Canvas { context, size in
                guard isActive else { return }
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                for index in 0..<84 {
                    let delay = Double(index % 7) * 0.025
                    let t = max(0, elapsed - delay)
                    guard t > 0, t < 3.1 else { continue }
                    let seed = Double((index * 47) % 97) / 96
                    let originX = Double(size.width) * (index.isMultiple(of: 2) ? 0.34 : 0.66)
                    let originY = Double(size.height) * 0.68
                    let angle = (-0.92 * Double.pi) + (seed - 0.5) * 1.6
                    let speed = 170 + Double((index * 29) % 115)
                    let x = originX + cos(angle) * speed * t + sin(t * 8 + Double(index)) * 9
                    let y = originY + sin(angle) * speed * t + 92 * t * t
                    let fade = max(0, 1 - t / 3.1)
                    let width: CGFloat = index.isMultiple(of: 3) ? 5 : 8
                    let height: CGFloat = index.isMultiple(of: 4) ? 15 : 9
                    let rect = CGRect(x: CGFloat(x), y: CGFloat(y), width: width, height: height)
                    context.opacity = fade
                    context.drawLayer { layer in
                        layer.translateBy(x: rect.midX, y: rect.midY)
                        layer.rotate(by: .radians(t * Double((index % 5) + 2)))
                        layer.translateBy(x: -rect.midX, y: -rect.midY)
                        if index.isMultiple(of: 5) {
                            layer.fill(Path(ellipseIn: rect), with: .color(colors[index % colors.count]))
                        } else {
                            layer.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(colors[index % colors.count]))
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .opacity(reduceMotion ? 0 : 1)
        .onChange(of: isActive) {
            if isActive { startedAt = .now }
        }
    }
}

private struct OWCProgressBubbleShape: Shape {
    enum Edge { case leading, none, trailing }
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 6
        var corners: UIRectCorner = .allCorners
        if edge == .leading { corners.subtract([.topLeft, .bottomLeft]) }
        if edge == .trailing { corners.subtract([.topRight, .bottomRight]) }
        return Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
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
    let title: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label(title, systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { dismiss() } label: {
                            Label(title, systemImage: "chevron.left")
                        }
                    }
                }
            }
            .background(OWCSwipeBackEnabler())
    }
}

private struct OWCSwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

extension View {
    func owcDetailBack(title: String) -> some View {
        modifier(OWCDetailBackModifier(title: title))
    }
}
