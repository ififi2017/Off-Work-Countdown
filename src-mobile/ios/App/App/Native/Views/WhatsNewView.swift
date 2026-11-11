import SwiftUI

/// What's new in this release. 3.3.0 is workplace automation: one workday
/// shown as it now records itself, then why it is cheap on battery and
/// private, and the free Shortcuts path. Free users see all of it; the
/// update gift is left wrapped on the timer for after this page.
struct WhatsNewView: View {
    let shifts: ShiftSessionStore
    let onDismiss: () -> Void
    let onSetUpAutomation: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var text: AppText { shifts.text }
    private var plus: PlusEntitlement { shifts.plus }

    var body: some View {
        NavigationStack {
            WhatsNewAutomationContent(
                text: text,
                isPlus: plus.isAuthorized,
                hasGift: plus.hasWrappedLifetimeOffer,
                onDismiss: onDismiss,
                onSetUp: onSetUpAutomation
            )
        }
        .tint(OWCDesign.accent)
        .interactiveDismissDisabled()
        .task {
            await plus.checkCurrentEntitlements()
            // Left on the timer, wrapped, for after this page closes.
            plus.inviteUpdateGift()
            if !plus.isAuthorized, plus.products.isEmpty { await plus.loadProducts() }
        }
    }
}

/// The page itself, without the store, so Canvas can show every variant.
struct WhatsNewAutomationContent: View {
    let text: AppText
    let isPlus: Bool
    let hasGift: Bool
    var heroFrozenAt: Double? = nil
    var onDismiss: () -> Void = {}
    var onSetUp: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "DoneAt 3.3.0")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(OWCDesign.accent)
                    Text(text.t("whatsNewAutomationTitle"))
                        .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(text.t("whatsNewAutomationSubtitle"))
                        .font(.body).foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                WhatsNewAutomationHero(text: text, frozenAt: heroFrozenAt)
                VStack(alignment: .leading, spacing: 20) {
                    feature("location.fill", "whatsNewAutoRecordTitle", "whatsNewAutoRecordBody")
                    feature("stopwatch", "whatsNewOvertimeTitle", "whatsNewOvertimeBody")
                    feature("leaf", "whatsNewBatteryTitle", "whatsNewBatteryBody")
                    feature("square.2.layers.3d", "whatsNewShortcutsTitle", "whatsNewShortcutsBody", badge: text.t("automationUIShortcutsFree"))
                    feature("lock", "whatsNewPrivacyTitle", "whatsNewPrivacyBody")
                }
                if !isPlus {
                    Text(text.t("whatsNewAutomationPlusNote"))
                        .font(.footnote).foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hasGift {
                    Label(text.t("whatsNewGiftNote"), systemImage: "gift")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(OWCDesign.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(OWCDesign.page)
        // Kept in reach however long the page runs.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button(text.t("whatsNewContinue"), action: onDismiss)
                    .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                Button(text.t("whatsNewSetUpAutomation"), action: onSetUp)
                    .buttonStyle(OWCPrimaryButtonStyle())
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .tint(OWCDesign.accent)
    }

    private func feature(_ symbol: String, _ titleKey: String, _ bodyKey: String, badge: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol).font(.title3).foregroundStyle(OWCDesign.accent)
                    .frame(width: 26).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(text.t(titleKey)).font(.headline)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(OWCDesign.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(OWCDesign.accent.opacity(0.12), in: Capsule())
                    }
                }
                Text(text.t(bodyKey)).font(.subheadline).foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor private func whatsNewPreviewText(_ language: String = "zh-TW") -> AppText {
    let defaults = UserDefaults(suiteName: "WhatsNewPreview.\(language)")!
    defaults.set(language, forKey: "ios.native.languageOverride")
    return AppText(preferences: PreferencesStore(defaults: defaults, records: .inMemory()))
}

#Preview("3.3.0 · free, animated") {
    WhatsNewAutomationContent(text: whatsNewPreviewText(), isPlus: false, hasGift: true)
}

#Preview("3.3.0 · arrival frame") {
    WhatsNewAutomationContent(text: whatsNewPreviewText(), isPlus: true, hasGift: false, heroFrozenAt: 2.6)
}

#Preview("3.3.0 · clock-out frame, English") {
    WhatsNewAutomationContent(text: whatsNewPreviewText("en"), isPlus: false, hasGift: true, heroFrozenAt: 6.6)
        .preferredColorScheme(.dark)
}
