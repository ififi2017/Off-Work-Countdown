import SwiftUI

/// The root shell's feature-aware navigation and preference actions.
struct OWCAppHeader: View {
    let preferences: PreferencesStore
    let text: AppText
    var showsFocus = false
    var onShowSidebar: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OWCRootPageHeader(title: "") {
            HStack(spacing: 8) {
                if let onShowSidebar {
                    Button(action: onShowSidebar) {
                        Label(text.t("showSidebar"), systemImage: "sidebar.left")
                    }
                    .owcTabletGlassAction()
                    .accessibilityLabel(text.t("showSidebar"))
                }
                if showsFocus {
                    NavigationLink(value: AppRoute.focus) {
                        Label(text.t("focusTitle"), systemImage: FocusTaskIcon.focus.systemName)
                    }
                    .owcTabletGlassAction()
                    .accessibilityLabel(text.t("focusTitle"))
                }
            }
            .labelStyle(.iconOnly)
        } trailing: {
            HStack(spacing: 8) {
                OWCEarningsVisibilityButton(preferences: preferences, text: text)
                    .foregroundStyle(OWCDesign.secondary)
                    .owcTabletGlassAction()
                Button {
                    withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) {
                        _ = preferences.toggleQuickTheme()
                    }
                } label: {
                    Image(systemName: preferences.quickThemeIcon)
                        .font(.body)
                        .foregroundStyle(OWCDesign.secondary)
                }
                .owcTabletGlassAction()
                .accessibilityLabel(text.t("theme"))
            }
        }
    }
}

/// Status chip above a timer (lunch, rest, overtime).
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
            Text(title).font(font)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(fill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
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
