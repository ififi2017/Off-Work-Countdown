import SwiftUI

struct WhatsNewView: View {
    let text: AppText
    let onDismiss: () -> Void
    /// Closes the sheet and opens the Apple Watch explainer. iPhone only.
    var onLearnAboutWatch: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var revealed = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.18).ignoresSafeArea()
                ReleaseNotesCard(isRevealed: revealed, reduceMotion: reduceMotion) { card }
                    .frame(maxWidth: 460)
                    .frame(maxHeight: max(160, geometry.size.height - 40))
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter) { revealed = true }
        }
        .tint(OWCDesign.accent)
        .accessibilityAction(.escape, onDismiss)
    }

    private var card: some View {
        // The card takes its height from the text on the first pass. Measuring
        // the text after layout opened it at one height and settled at another.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .clipShape(.rect(cornerRadius: OWCDesign.cardRadius))
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text.t("close"))
            .padding(12)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(text.t("whatsNewTitle")).font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("DoneAt \(ReleaseNotes.current)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.trailing, 36)
            VStack(alignment: .leading, spacing: 6) {
                feature("applewatch", "whatsNewWatchTitle", "whatsNewWatchBody")
                if let onLearnAboutWatch, UIDevice.current.userInterfaceIdiom == .phone {
                    Button(text.t("appleWatchLearnMore"), action: onLearnAboutWatch)
                        .font(.subheadline.weight(.semibold))
                        // Aligned with the feature text, past the 26 pt glyph and 14 pt gap.
                        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 40)
                }
            }
            feature("square.stack", "whatsNewSmartStackTitle", "whatsNewSmartStackBody")
            Button(text.t("whatsNewContinue"), action: onDismiss)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private func feature(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.system(size: 20)).foregroundStyle(OWCDesign.accent)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(text.t(title)).font(.headline)
                Text(text.t(body)).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Inserts the card whole, glass and text in one transition. Fading an
/// already-inserted glass card with `.opacity` drew the glass before the text.
private struct ReleaseNotesCard<Content: View>: View {
    let isRevealed: Bool
    let reduceMotion: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                if isRevealed {
                    content
                        .glassEffect(.regular, in: .rect(cornerRadius: OWCDesign.cardRadius))
                        .glassEffectTransition(.materialize)
                        .transition(transition)
                }
            }
        } else if isRevealed {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: OWCDesign.cardRadius))
                .transition(transition)
        }
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }
}
