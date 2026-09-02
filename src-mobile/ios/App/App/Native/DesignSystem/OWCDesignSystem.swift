import SwiftUI
import UIKit

enum OWCBrand {
    static let shortName = "DoneAt"
}

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
    static let brandPlum = Color(red: 0.169, green: 0.098, blue: 0.208)
    static let brandCream = Color(red: 1.0, green: 0.945, blue: 0.847)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.53, blue: 0.18, alpha: 1)
            : UIColor(red: 0.95, green: 0.35, blue: 0.04, alpha: 1)
    })

    static let lifeChildhood = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.72, blue: 0.86, alpha: 1)
            : UIColor(red: 0.45, green: 0.58, blue: 0.76, alpha: 1)
    })
    static let lifeStudy = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.78, blue: 0.68, alpha: 1)
            : UIColor(red: 0.32, green: 0.58, blue: 0.50, alpha: 1)
    })
    static let lifeWork = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.86, green: 0.64, blue: 0.38, alpha: 1)
            : UIColor(red: 0.72, green: 0.48, blue: 0.20, alpha: 1)
    })
    static let lifeRetirement = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.70, green: 0.68, blue: 0.78, alpha: 1)
            : UIColor(red: 0.52, green: 0.50, blue: 0.62, alpha: 1)
    })
    static let lifeUnset = Color(uiColor: .tertiarySystemFill)

    /// Records uses a stronger categorical palette than the Life timeline.
    /// Those cells are much smaller and sit next to one another, so the softer
    /// life-stage colors collapsed into nearly the same tint on a phone.
    static let recordsWork = Color(uiColor: .systemIndigo)
    static let recordsOvertime = Color(uiColor: .systemOrange)
    static let recordsBreak = Color(uiColor: .systemTeal)
    static let recordsSleep = Color(uiColor: .systemBlue)
    static let recordsFree = Color(uiColor: .systemPurple)
    static let recordsUnclassified = Color(uiColor: .systemGray2)

    /// The categorical token for a stretch of a day. Brand orange is absent on
    /// purpose: it means selection and today, never a kind of time.
    static func recordsColor(_ kind: TimeAllocationKind) -> Color {
        switch kind {
        case .work: recordsWork
        case .overtime: recordsOvertime
        case .workBreak: recordsBreak
        case .sleep: recordsSleep
        case .free: recordsFree
        case .unclassified: recordsUnclassified
        }
    }

    static func lifeColor(_ kind: LifeStageKind) -> Color {
        switch kind {
        case .childhood: lifeChildhood
        case .study: lifeStudy
        case .work: lifeWork
        case .retirement: lifeRetirement
        case .unset: lifeUnset
        }
    }

    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let rowHeight: CGFloat = 52
    static let pageInset: CGFloat = 16
    static let contentInset: CGFloat = 20

    /// Fixed vertical rhythm for the setup screen. These used to be `Spacer`s,
    /// which split the leftover height evenly and left the layout drifting with
    /// the device.
    static let heroGap: CGFloat = 26
    static let sectionGap: CGFloat = 22

    /// Clearance a detail page leaves under its last element.
    ///
    /// The tab bar stays up across a push, floating over the content, and the
    /// system inset stops the content at the bar rather than a comfortable
    /// distance from it — the language page's footer ended about 13pt from the
    /// glass edge, close enough to read as a mistake. Mirrors the 22pt the
    /// pages open with.
    static let detailBottomInset: CGFloat = 24
}

enum OWCSystemSettings {
    static let applicationURL = URL(string: UIApplication.openSettingsURLString)!
}

/// 135° hatching — the app's one mark for "estimated or planned".
///
/// Deliberately a texture and not a lower opacity: a faded block reads as
/// *less important*, and an estimate is not less important than a fact, only
/// less certain. Because it is a shape rather than a colour, it also survives
/// Differentiate Without Color and a black-and-white screenshot.
struct OWCHatchPattern: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard spacing > 0, rect.height > 0 else { return path }
        var x = rect.minX - rect.height
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            x += spacing
        }
        return path
    }
}

extension View {
    /// Marks a filled shape as an estimate. The caller clips it, because only
    /// the caller knows whether the thing is a capsule, a cell or a bar.
    func owcEstimated(
        _ isEstimated: Bool,
        tint: Color = OWCDesign.secondary,
        spacing: CGFloat = 5,
        lineWidth: CGFloat = 1
    ) -> some View {
        overlay {
            if isEstimated {
                OWCHatchPattern(spacing: spacing)
                    .stroke(tint.opacity(0.55), lineWidth: lineWidth)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Shared circular Liquid Glass geometry for compact toolbar controls.
/// The glass remains visually compact while the outer frame preserves the
/// platform's 44-point minimum hit target.
struct OWCGlassCircleLabel<Content: View>: View {
    var visualSize: CGFloat = 34
    @ViewBuilder let content: Content

    init(visualSize: CGFloat = 34, @ViewBuilder content: () -> Content) {
        self.visualSize = visualSize
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: visualSize, height: visualSize)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// A root page's large title and controls share one row. System large-title
/// navigation deliberately puts trailing toolbar items on the row above the
/// title, which is not the hierarchy used by the Timer, Records and Settings
/// roots in this app.
struct OWCRootPageHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
            Text(title)
                .font(.largeTitle.bold())
                .tracking(-0.85)
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 52)
    }
}

/// Appears only after `OWCRootPageHeader` has scrolled away. It overlays the
/// scroll view instead of changing its safe-area inset, so crossing the
/// collapse threshold cannot move the user's content.
struct OWCCompactRootBar<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 72)

            HStack(spacing: 8) {
                leading
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.horizontal, OWCDesign.contentInset)
        .frame(height: 52)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }
}

struct OWCAppHeader: View {
    let store: OffWorkStore
    var showsFocus = false

    private let visualSize: CGFloat = 34
    /// Align the visible circle with the cards' 16pt page inset. The shared
    /// label has a wider 44pt hit target, so using the same inset on that outer
    /// frame made the circle itself look five points farther inward.
    private var hitTargetInset: CGFloat {
        OWCDesign.pageInset - (44 - visualSize) / 2
    }

    var body: some View {
        HStack {
            if showsFocus {
                NavigationLink(value: AppRoute.focus) {
                    OWCGlassCircleLabel(visualSize: visualSize) {
                        Image(systemName: "timer")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.t("focusTitle"))
            }
            Spacer()
            Button { withAnimation(.snappy(duration: 0.28)) { store.toggleQuickTheme() } } label: {
                OWCGlassCircleLabel(visualSize: visualSize) {
                    Group {
                        if store.quickThemeIsAuto {
                            Text(verbatim: "A")
                                .font(.body.weight(.semibold))
                        } else {
                            Image(systemName: store.quickThemeIcon)
                                .font(.body)
                        }
                    }
                    .foregroundStyle(OWCDesign.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("theme"))
        }
        .padding(.horizontal, hitTargetInset)
        .frame(minHeight: 44)
    }

}

/// Status chip above a timer (lunch, rest, overtime).
///
/// `Image` + `Text`, not `Label`. A `Label` inside a short capsule can clip
/// hierarchical symbols into an empty slot, which reads as a leading space
/// before the Chinese copy and no icon at all.
struct TimerPhasePill: View {
    let title: String
    var systemImage: String
    var tint: Color
    var fill: Color
    var font: Font = .footnote.weight(.semibold)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(font)
                .symbolRenderingMode(.monochrome)
                .accessibilityHidden(true)
            Text(title)
                .font(font)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(fill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

enum OWCText {
    /// "09:00 – 18:00", still in that order inside an Arabic or Hebrew layout.
    ///
    /// A clock range is a left-to-right sequence in every language, but the
    /// surrounding paragraph direction would otherwise reorder the two ends of
    /// it. The isolate does this at the text level, so it survives being handed
    /// to a `String` parameter — flipping `layoutDirection` on the view is not
    /// available there, and applied to a whole row it would mirror the row.
    static func ltrRange(_ from: String, _ to: String) -> String {
        "\u{2066}\(from) – \(to)\u{2069}"
    }
}

struct OWCSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.footnote)
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
            // Solid, not `.thinMaterial`. The material picked up so much of the
            // page underneath that in light mode a card was barely a shade off
            // the background; `secondarySystemGroupedBackground` is what the
            // system's own grouped lists sit on, and it separates in both
            // appearances without needing a border.
            .background(OWCDesign.card)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }
}

private struct OWCScrollContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Keeps short settings pages still, while preserving scrolling when their
/// content actually extends beyond the available height.
///
/// A permanently enabled `ScrollView` installs a vertical pan recognizer even
/// when there is nowhere to scroll. Near the leading edge that recognizer can
/// win against UIKit's interactive-pop recognizer, making swipe-back feel
/// unreliable. Measuring the laid-out content lets short pages behave like a
/// plain `VStack`; pages such as the expanded salary form remain scrollable.
struct OWCContentSizedScrollView<Content: View>: View {
    private let showsIndicators: Bool
    private let content: Content
    @State private var contentHeight: CGFloat = 0

    init(
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical, showsIndicators: showsIndicators) {
                content
                    .frame(maxWidth: .infinity)
                    .background {
                        GeometryReader { contentGeometry in
                            Color.clear.preference(
                                key: OWCScrollContentHeightKey.self,
                                value: contentGeometry.size.height
                            )
                        }
                    }
                    // Outside the measurement above on purpose. The height this
                    // view reports decides whether the page scrolls at all, and
                    // padding a short page into scrolling would undo the whole
                    // point of this container.
                    .padding(.bottom, OWCDesign.detailBottomInset)
            }
            .scrollDisabled(contentHeight <= viewport.size.height + 1)
            .scrollBounceBehavior(.basedOnSize)
        }
        .onPreferenceChange(OWCScrollContentHeightKey.self) { contentHeight = $0 }
    }
}

struct OWCRow<Accessory: View>: View {
    let icon: String?
    let textIcon: String?
    let title: String
    let subtitle: String?
    let isLast: Bool
    let accessory: Accessory
    /// Centres the leading glyph and trailing accessory against the whole
    /// title-plus-subtitle block instead of pinning them to the title line.
    /// Descriptive onboarding rows and radio-style choices use this layout.
    var centersVertically = false
    /// Tints the glyph and title red, for rows that delete something. The
    /// confirmation is still the caller's job; this only stops a destructive
    /// row from reading like a neutral one.
    var isDestructive = false
    /// Whether an accessory is actually coming. Set by the initialisers, not by
    /// the caller: a row with nothing at its trailing edge must not reserve
    /// room for one, and must let its text claim the full width before the
    /// spacer takes any — otherwise the text negotiates width against a spacer
    /// that wants everything, and wraps a word or two early with visible empty
    /// margin beside it.
    fileprivate var reservesAccessory = true

    // A fixed gutter, so every title in a card starts on the same vertical line
    // however wide the glyph is — `calendar.badge.clock` is a good deal wider
    // than `clock`, and sizing to the glyph left the titles ragged. It is
    // @ScaledMetric rather than a constant so the gutter grows with the label
    // and the icon still fits at accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = OWCDesign.rowHeight
    @ScaledMetric(relativeTo: .body) private var iconTitleOffset: CGFloat = 2
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        icon: String? = nil,
        textIcon: String? = nil,
        title: String,
        subtitle: String? = nil,
        isLast: Bool = false,
        centersVertically: Bool = false,
        isDestructive: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.textIcon = textIcon
        self.title = title
        self.subtitle = subtitle
        self.isLast = isLast
        self.centersVertically = centersVertically
        self.isDestructive = isDestructive
        self.accessory = accessory()
    }

    private var stacksAccessory: Bool { dynamicTypeSize.isAccessibilitySize }

    /// A row carrying a subtitle is a block of text, not a single line. Centring
    /// the icon against that block parks it between the two lines whenever the
    /// subtitle wraps; it belongs beside the title.
    ///
    /// `centersVertically` opts out, for rows whose subtitle is part of the main
    /// description or whose radio mark belongs in the centre of the whole row.
    private var alignsToTitle: Bool { !centersVertically && (subtitle != nil || stacksAccessory) }

    var body: some View {
        HStack(alignment: alignsToTitle ? .top : .center, spacing: 12) {
            if let textIcon {
                Text(verbatim: textIcon)
                    .font(.body)
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(width: iconWidth)
                    .padding(.top, alignsToTitle ? iconTitleOffset : 0)
            } else if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(isDestructive ? Color.red : OWCDesign.secondary)
                    .frame(width: iconWidth)
                    // Nudged down so the glyph sits on the title's optical
                    // centre rather than on the top of its line box.
                    .padding(.top, alignsToTitle ? iconTitleOffset : 0)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(isDestructive ? Color.red : OWCDesign.primary)
                    // Settings rows have a trailing value. A wrapping title is
                    // flexible, so the `Spacer` beside it used to take half the
                    // leftover width and "Off work reminder" broke under
                    // "Off-work progress" even though both strings fit. No
                    // subtitle means a single line, and the value yields —
                    // except at accessibility sizes, where the accessory has
                    // already moved onto its own line and the title can use
                    // the full width.
                    .lineLimit(stacksAccessory ? 3 : (subtitle == nil ? 1 : 2))
                    .minimumScaleFactor(stacksAccessory || subtitle != nil ? 1 : 0.85)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .lineLimit(3)
                        // Chinese at footnote size sets very tight by default;
                        // a wrapped subtitle read as one solid block. Scaled to
                        // match the 4pt the body copy above these rows uses.
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // At accessibility sizes the title alone eats the row, and the
                // value was truncating to "12:00 · …". Drop it onto its own line
                // instead, the way Settings does.
                if stacksAccessory { accessory }
            }
            // A row with nothing at its trailing edge has no spacer at all.
            //
            // Not even `Spacer(minLength: 0)`: a spacer is a flexible view, and
            // an `HStack` divides the width between its flexible children
            // rather than letting the first one take what it needs. Measured,
            // that handed a wrapping subtitle 246 of the 284 pt available and
            // broke it four characters early, with the empty 38 pt sitting
            // beside it. Gone, the text is the only flexible thing in the row
            // and `maxWidth: .infinity` gives it the lot.
            .layoutPriority(1)
            .frame(maxWidth: reservesAccessory ? nil : .infinity, alignment: .leading)
            if reservesAccessory {
                Spacer(minLength: 8)
                if !stacksAccessory { accessory }
            }
        }
        .padding(.horizontal, 16)
        // A wrapped subtitle otherwise sits right on the separator.
        .padding(.vertical, subtitle == nil && !stacksAccessory ? 0 : 10)
        .frame(minHeight: rowHeight)
        .overlay(alignment: .bottomTrailing) {
            if !isLast {
                Rectangle()
                    .fill(OWCDesign.separator)
                    .frame(height: 0.5)
                    // Inset to the title, which sits after the icon gutter plus
                    // both paddings — so it tracks the icon as that scales.
                    .padding(.leading, icon == nil && textIcon == nil ? 16 : iconWidth + 28)
            }
        }
        .contentShape(Rectangle())
    }
}

extension OWCRow where Accessory == EmptyView {
    init(
        icon: String? = nil,
        textIcon: String? = nil,
        title: String,
        subtitle: String? = nil,
        isLast: Bool = false,
        centersVertically: Bool = false,
        isDestructive: Bool = false
    ) {
        self.init(
            icon: icon,
            textIcon: textIcon,
            title: title,
            subtitle: subtitle,
            isLast: isLast,
            centersVertically: centersVertically,
            isDestructive: isDestructive
        ) { EmptyView() }
        reservesAccessory = false
    }
}

struct OWCDetailAccessory: View {
    let text: String?
    var external = false

    var body: some View {
        HStack(spacing: 6) {
            if let text {
                Text(text)
                    .font(.body)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.tertiary)
        }
    }
}

/// A navigation row whose disclosure indicator remains centered in the row,
/// even when the title wraps or gains supporting text.
///
/// Keep navigation lists on this shared primitive instead of rebuilding the
/// trailing chevron in each feature. That makes the hit target, separator and
/// alignment consistent across Records, Settings and future detail screens.
struct OWCDisclosureRow: View {
    let title: String
    var subtitle: String? = nil
    let isLast: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(subtitle == nil ? 1 : 2)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .lineLimit(3)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.tertiary)
                .frame(width: 24, height: 44, alignment: .center)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, subtitle == nil ? 0 : 10)
        .frame(minHeight: OWCDesign.rowHeight)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(OWCDesign.separator)
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct OWCPrimaryButtonStyle: ButtonStyle {
    var filled = true
    var color: Color = OWCDesign.accent
    var minimumHeight: CGFloat = 50
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressing = isEnabled && configuration.isPressed
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(filled ? Color.white.opacity(isEnabled ? 1 : 0.72) : OWCDesign.primary.opacity(isEnabled ? 1 : 0.45))
            .frame(maxWidth: .infinity, minHeight: minimumHeight)
            .background((filled ? color : OWCDesign.control).opacity(isEnabled ? 1 : 0.42))
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
            .opacity(pressing ? 0.72 : 1)
            .scaleEffect(pressing && !reduceMotion ? 0.985 : 1)
            .animation(
                isEnabled && !reduceMotion ? OWCMotion.press : OWCMotion.reduced,
                value: configuration.isPressed
            )
    }
}

struct OWCRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // `.animation(_:body:)`, not `.animation(_:value:)`.
        //
        // The value form wraps the row's own label, so everything inside it
        // inherited the press transaction. Releasing a radio row changes
        // `isPressed` and the row's checkmark in the same pass, and the label
        // therefore cross-faded `circle` into `checkmark.circle.fill` in one
        // 20 pt slot — two symbols legibly stacked, on the tapped row only,
        // while every other row in the same list swapped instantly. Scoped to
        // this closure the press decorations still animate and the label's own
        // content changes on whatever terms its own view set.
        configuration.label
            .animation(.easeOut(duration: 0.12)) { content in
                content
                    .background(configuration.isPressed ? OWCDesign.control : .clear)
                    .opacity(configuration.isPressed ? 0.82 : 1)
            }
    }
}

struct OWCSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
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

struct OWCDetailBackModifier<Trailing: View>: ViewModifier {
    let backTitle: String
    let pageTitle: String
    /// The page's own control, at the trailing edge of the header row. Empty on
    /// every page that has nothing to put there.
    @ViewBuilder let trailing: Trailing
    let hasUnsavedChanges: Bool
    let unsavedChangesTitle: String
    let keepEditingTitle: String
    let discardChangesTitle: String
    let onDiscardChanges: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showDiscardPrompt = false
    @State private var promptFeedback = 0
    @State private var discardFeedback = 0

    init(
        backTitle: String,
        pageTitle: String,
        hasUnsavedChanges: Bool = false,
        unsavedChangesTitle: String = "",
        keepEditingTitle: String = "",
        discardChangesTitle: String = "",
        onDiscardChanges: @escaping () -> Void = {},
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.backTitle = backTitle
        self.pageTitle = pageTitle
        self.trailing = trailing()
        self.hasUnsavedChanges = hasUnsavedChanges
        self.unsavedChangesTitle = unsavedChangesTitle
        self.keepEditingTitle = keepEditingTitle
        self.discardChangesTitle = discardChangesTitle
        self.onDiscardChanges = onDiscardChanges
    }

    func body(content: Content) -> some View {
        content
            // Settings destinations now use the same native large-title
            // navigation as the roots. The title therefore collapses into the
            // translucent system bar while a language/theme/etc. list scrolls.
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden(true)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: requestDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(backTitle)
                    .confirmationDialog(
                        unsavedChangesTitle,
                        isPresented: $showDiscardPrompt,
                        titleVisibility: .visible
                    ) {
                        Button(discardChangesTitle, role: .destructive, action: discardAndDismiss)
                        Button(keepEditingTitle, role: .cancel) {}
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    trailing
                }
            }
            .background(
                OWCSystemBackSwipeBridge(
                    blocksBackSwipe: hasUnsavedChanges,
                    onBlockedBackSwipe: requestDismiss
                )
            )
            .sensoryFeedback(.warning, trigger: promptFeedback)
            .sensoryFeedback(.impact(weight: .medium), trigger: discardFeedback)
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            promptFeedback += 1
            showDiscardPrompt = true
        } else {
            performDismiss()
        }
    }

    private func discardAndDismiss() {
        discardFeedback += 1
        onDiscardChanges()
        performDismiss()
    }

    private func performDismiss() {
        dismiss()
    }
}

extension View {
    /// Adds navigation chrome only while a permanently-mounted tab root is
    /// active. Tablet and landscape roots intentionally stay in the view tree
    /// during tab changes so Liquid Glass does not flash; an ordinary
    /// `navigationTitle` on an invisible sibling can otherwise keep winning
    /// the shared NavigationStack's preference resolution.
    @ViewBuilder
    func owcNavigationTitle(
        _ title: String,
        displayMode: NavigationBarItem.TitleDisplayMode,
        isActive: Bool
    ) -> some View {
        if isActive {
            navigationTitle(title)
                .navigationBarTitleDisplayMode(displayMode)
        } else {
            self
        }
    }

    func owcDetailBack(title: String, pageTitle: String) -> some View {
        modifier(OWCDetailBackModifier(backTitle: title, pageTitle: pageTitle) { EmptyView() })
    }

    /// The same header with a control at its trailing edge — a page that can be
    /// saved, rather than one that only commits as you go.
    func owcDetailBack<Trailing: View>(
        title: String,
        pageTitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(OWCDetailBackModifier(backTitle: title, pageTitle: pageTitle, trailing: trailing))
    }

    /// Keeps a page with a local draft in place until the user explicitly
    /// discards it. The same request path handles the glass back button and the
    /// native leading-edge swipe.
    func owcDetailBack<Trailing: View>(
        title: String,
        pageTitle: String,
        hasUnsavedChanges: Bool,
        unsavedChangesTitle: String,
        keepEditingTitle: String,
        discardChangesTitle: String,
        onDiscardChanges: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(
            OWCDetailBackModifier(
                backTitle: title,
                pageTitle: pageTitle,
                hasUnsavedChanges: hasUnsavedChanges,
                unsavedChangesTitle: unsavedChangesTitle,
                keepEditingTitle: keepEditingTitle,
                discardChangesTitle: discardChangesTitle,
                onDiscardChanges: onDiscardChanges,
                trailing: trailing
            )
        )
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
    var textAlignment: TextAlignment = .trailing
    let onCommit: () -> Void

    @FocusState private var focused: Bool
    @State private var selection: TextSelection?

    var body: some View {
        TextField(placeholder, text: $text, selection: $selection)
            .font(
                (emphasized ? Font.title3 : .body).weight(.semibold)
                .monospacedDigit()
            )
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(textAlignment)
            .focused($focused)
            // One deterministic width. Chaining .frame(width:) with a
            // .frame(maxWidth:) left the layout solving for two constraints at
            // once, and the keyboard's own resize could drive it negative.
            .frame(width: width ?? 170)
            .onChange(of: text) { sanitize() }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    Task { @MainActor in
                        await Task.yield()
                        selection = TextSelection(range: text.startIndex..<text.endIndex)
                    }
                } else {
                    onCommit()
                }
            }
            .onSubmit { onCommit() }
    }

    private func sanitize() {
        var allowed = String(text.compactMap(Self.asciiDigitOrSeparator))
        if decimal {
            // Keep only the first separator; "1.2.3" is not a number anybody meant.
            var seenSeparator = false
            allowed = String(allowed.compactMap { character -> Character? in
                guard character == "." else { return character }
                if seenSeparator { return nil }
                seenSeparator = true
                return "."
            })
        } else {
            allowed = allowed.filter { $0 != "." }
        }
        let capped = String(allowed.prefix(maxDigits))
        if capped != text { text = capped }
    }

    /// Folds a typed character to an ASCII digit, or to `.` for any separator
    /// this field accepts, or drops it.
    ///
    /// The filter used to be `$0.isNumber`, which is true for Arabic-Indic ٠١٢,
    /// Devanagari ०१२ and every other Unicode decimal digit. Those keystrokes
    /// were accepted into the field and then failed everywhere downstream —
    /// `Int(_:)` returns nil for them, and the salary string reaches the
    /// JavaScript rules verbatim where `Number()` gives `NaN`. The field looked
    /// filled in and the calculation came out empty.
    ///
    /// U+066B, the Arabic decimal separator, is the same story from the other
    /// side: it is neither "." nor "," so it was dropped in silence, turning
    /// "1٫5" into "15".
    private static func asciiDigitOrSeparator(_ character: Character) -> Character? {
        if character.isWholeNumber, let value = character.wholeNumberValue, (0...9).contains(value) {
            return Character(String(value))
        }
        switch character {
        case ".", ",", "\u{066B}": return "."
        default: return nil
        }
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
            // Flatten first. Without it each shadow is derived from the union of
            // every sublayer underneath, so the two blurs below are recomputed
            // against a live subtree on every frame of a page transition rather
            // than against one finished texture.
            .compositingGroup()
            .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
