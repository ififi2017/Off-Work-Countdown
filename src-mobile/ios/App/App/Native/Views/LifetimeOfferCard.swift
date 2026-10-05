import StoreKit
import SwiftUI

struct LifetimeOfferCard: View {
    let plus: PlusEntitlement
    let text: AppText
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if plus.canOfferLifetime, let offer = plus.lifetimeOffer,
           plus.discountedLifetimeProduct() != nil || plus.previewsLifetimeOffer {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if offer.claimedAt == nil || offer.isActive(at: context.date) {
                    content(offer: offer, now: context.date)
                }
            }
            .onChange(of: scenePhase) { _, _ in plus.observeLifetimeOffer() }
            .onDisappear { plus.observeLifetimeOffer() }
            .task(id: offer.expiresAt) {
                guard let deadline = offer.expiresAt else { return }
                let remaining = deadline.timeIntervalSince(max(.now, offer.latestObservedAt))
                guard remaining > 0 else { return }
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
                // Invalidate the parent too, so regular plans return at expiry.
                plus.observeLifetimeOffer()
            }
        }
    }

    private func content(offer: LifetimeOffer, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(text.t("plusOfferTitle"), systemImage: "gift")
                .font(.headline).foregroundStyle(OWCDesign.accent)
            if let savings = plus.lifetimeSavingsLabel(text: text) {
                Text(savings).font(.title2.bold()).foregroundStyle(OWCDesign.accent)
            }
            Text(text.t(offer.source == .update321 ? "plusOfferWelcomeBack" : "plusOfferWelcome"))
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            priceLayout {
                Text(plus.discountedLifetimeProduct()?.displayPrice ?? plus.previewLifetimeOfferPrices?.discounted ?? "—")
                    .font(.title.bold().monospacedDigit())
                Text(plus.discountedLifetimeProduct() == nil ? (plus.previewLifetimeOfferPrices?.regular ?? "—") : (plus.lifetimeProduct()?.displayPrice ?? "—"))
                    .font(.body.monospacedDigit()).strikethrough()
                    .foregroundStyle(OWCDesign.secondary)
            }
            Text(text.t("plusOfferTerms"))
                .font(.footnote).foregroundStyle(OWCDesign.secondary)
            if let deadline = offer.expiresAt {
                countdownLayout {
                    Text(text.t("plusOfferRemaining"))
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text(text.formatDuration(max(0, deadline.timeIntervalSince(max(now, offer.latestObservedAt))) * 1000))
                        .monospacedDigit().multilineTextAlignment(.trailing)
                        .fixedSize()
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text.t("plusOfferDeadline", values: ["date": text.formatDate(deadline) + " " + text.formatTime(deadline)]))
            }
            if plus.previewsLifetimeOffer && plus.discountedLifetimeProduct() == nil {
                Text(text.t("plusOfferPreview"))
                    .font(.footnote).foregroundStyle(OWCDesign.secondary)
            }
            Button {
                if offer.claimedAt == nil { plus.claimLifetimeOffer() }
                else { Task { await plus.purchaseLifetimeOffer() } }
            } label: {
                HStack {
                    if plus.purchaseInFlight { ProgressView().tint(.white) }
                    Text(text.t(offer.claimedAt == nil ? "plusOfferClaim" : "plusBuyLifetime"))
                }
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .disabled(plus.isBusy || (offer.claimedAt != nil && plus.discountedLifetimeProduct() == nil))
            if let error = plus.lastProductError {
                Text(error).font(.footnote).foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OWCDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: OWCDesign.cardRadius).strokeBorder(OWCDesign.accent.opacity(0.28)) }
    }

    private var priceLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
    }

    private var countdownLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout())
    }
}
