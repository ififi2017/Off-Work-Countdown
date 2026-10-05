import SwiftUI

struct WhatsNewView: View {
    let text: AppText
    let plus: PlusEntitlement
    let onDismiss: () -> Void
    @State private var showsPlus = false
    @State private var showsOffer = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "DoneAt \(ReleaseNotes.current)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(OWCDesign.accent)
                        Text(text.t("whatsNewTitle"))
                            .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    }
                    OnboardingPlusBadge(text: text)
                    PlusFeatureStage(text: text, initialSelection: 1, showsFocus: false)
                    VStack(alignment: .leading, spacing: 20) {
                        feature("suitcase", "leavePlanAction", "whatsNewLeaveBody")
                        feature("alarm", "shiftAlarmsTitle", "whatsNewAlarmsBody")
                        feature("chart.bar.xaxis", "reportEntryTitle", "whatsNewReportsBody")
                    }
                    if plus.hasAvailableLifetimeOffer {
                        Button {
                            if plus.revealLifetimeOffer(from: .update321) { showsOffer = true }
                        } label: {
                            VStack(spacing: 12) {
                                OfferGiftIcon(size: 64)
                                Text(text.t("plusOfferTitle")).font(.headline)
                                Text(text.t("plusOfferWelcomeBack"))
                                    .font(.subheadline).foregroundStyle(OWCDesign.secondary)
                            }
                            .multilineTextAlignment(.center)
                            .padding(24).frame(maxWidth: .infinity)
                            .background(OWCDesign.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius))
                        }
                        .buttonStyle(.plain)
                    }
                    if case .pendingAskToBuy = plus.authorization {
                        Text(text.t("plusWaitingApproval"))
                            .font(.callout).foregroundStyle(OWCDesign.secondary)
                    }
                    if !plus.isAuthorized {
                        Button(text.t("onboardingExplorePlus")) { showsPlus = true }
                            .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button(text.t("whatsNewContinue"), action: onDismiss)
                        .buttonStyle(OWCPrimaryButtonStyle())
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(OWCDesign.page)
            .sheet(isPresented: $showsOffer) {
                LifetimeOfferSheet(plus: plus, text: text)
            }
            .sheet(isPresented: $showsPlus) {
                NavigationStack {
                    PaywallView(plus: plus, text: text, showsDismissButton: false) { showsPlus = false }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(text.t("close")) { showsPlus = false }
                            }
                        }
                }
            }
        }
        .tint(OWCDesign.accent)
        .interactiveDismissDisabled()
        .task {
            await plus.checkCurrentEntitlements()
            if ReleaseNotes.current == "3.2.1", plus.canOfferLifetime {
                plus.inviteLifetimeOffer(from: .update321)
            }
            if !plus.isAuthorized, plus.products.isEmpty { await plus.loadProducts() }
        }
    }

    private func feature(_ symbol: String, _ titleKey: String, _ bodyKey: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol).font(.title3).foregroundStyle(OWCDesign.accent)
                    .frame(width: 26).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(text.t(titleKey)).font(.headline)
                Text(text.t(bodyKey)).font(.subheadline).foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
