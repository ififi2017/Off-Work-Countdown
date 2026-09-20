import SwiftUI

/// 135° hatching — the app's one mark for "estimated or planned".
///
/// Deliberately a texture and not a lower opacity: a faded block reads as
/// *less important*, and an estimate is not less important than a fact, only
/// less certain. Because it is a shape rather than a colour, it also survives
/// Differentiate Without Color and a black-and-white screenshot.
nonisolated struct OWCHatchPattern: Shape {
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

extension View {
    /// Native Liquid Glass for controls hosted by the app's custom iPad chrome.
    /// The frame belongs to each action so adjacent buttons keep separate hit areas.
    func owcTabletGlassAction() -> some View {
        buttonStyle(.glass)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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

struct OWCWeekdayButton: View {
    let label: String
    let selected: Bool
    let locked: Bool
    let differentiateWithoutColor: Bool
    let lockedHint: String
    let action: () -> Void

    var body: some View {
        Button {
            guard !locked else { return }
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(label)
                    .font(.footnote.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .foregroundStyle(selected ? Color(uiColor: .systemBackground) : OWCDesign.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                if differentiateWithoutColor, selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .padding(4)
                }
            }
            .background(selected ? OWCDesign.accent : OWCDesign.control)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(locked ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(locked ? lockedHint : "")
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
    @State private var isAwayFromTop = false

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
            // Collapsing a large navigation title grows the viewport. Never
            // disable the pan while it still needs to return to the top.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 1
            } action: { _, awayFromTop in
                isAwayFromTop = awayFromTop
            }
            .scrollDisabled(!isAwayFromTop && contentHeight <= viewport.size.height + 1)
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
    /// Colours the glyph and draws it small, for a row whose icon is a colour
    /// swatch rather than a symbol.
    var iconTint: Color? = nil
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
        iconTint: Color? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.textIcon = textIcon
        self.title = title
        self.subtitle = subtitle
        self.isLast = isLast
        self.centersVertically = centersVertically
        self.isDestructive = isDestructive
        self.iconTint = iconTint
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
                    .imageScale(iconTint == nil ? .medium : .small)
                    .foregroundStyle(isDestructive ? Color.red : (iconTint ?? OWCDesign.secondary))
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
