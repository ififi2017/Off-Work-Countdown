import StoreKit
import SwiftUI

struct PaywallView: View {
    let store: OffWorkStore
    var reason: PlusPaywallReason = .intro
    var showsSkip: Bool = false
    var onDismiss: () -> Void = {}

    @State private var showsPlans = false
    @State private var confirmsLifetime = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(store.t(titleKey))
                    .font(.largeTitle.bold())
                    .tracking(-0.6)
                Text(store.t("plusIntroBody"))
                    .font(.body)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(3)

                if showsPlans {
                    plans
                } else {
                    Button(store.t("plusSeePlans")) {
                        showsPlans = true
                        Task { await store.plus.loadProducts() }
                    }
                    .buttonStyle(OWCPrimaryButtonStyle())
                }

                if reason != .intro {
                    Button(store.t("plusContinueReadonly"), action: onDismiss)
                        .buttonStyle(OWCPrimaryButtonStyle(filled: false))
                } else if showsSkip {
                    Button(store.t("plusSkip")) {
                        store.plus.markIntroSeen()
                        onDismiss()
                    }
                    .buttonStyle(OWCPrimaryButtonStyle(filled: false))
                }

                legal
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .background(OWCDesign.page)
        .onChange(of: store.plus.isAuthorized) { _, authorized in
            if authorized {
                store.plus.markIntroSeen()
                onDismiss()
            }
        }
        .confirmationDialog(
            store.t("plusLifetimeWhileSubscribed"),
            isPresented: $confirmsLifetime,
            titleVisibility: .visible
        ) {
            Button(store.t("plusBuyLifetime")) {
                if let product = store.plus.lifetimeProduct() {
                    Task { await store.plus.purchase(product) }
                }
            }
        }
    }

    @ViewBuilder
    private var plans: some View {
        if store.plus.isLoadingProducts {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            VStack(spacing: 10) {
                if let yearly = store.plus.yearlyProduct() {
                    productButton(
                        title: yearlyCTA(yearly),
                        subtitle: yearly.displayPrice,
                        product: yearly
                    )
                }
                if let monthly = store.plus.monthlyProduct() {
                    productButton(
                        title: store.t("plusMonthly"),
                        subtitle: monthly.displayPrice,
                        product: monthly
                    )
                }
                if let lifetime = store.plus.lifetimeProduct() {
                    Button {
                        if store.plus.hasActiveSubscription {
                            confirmsLifetime = true
                        } else {
                            Task { await store.plus.purchase(lifetime) }
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(store.t("plusLifetime"))
                            Text(lifetime.displayPrice)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .buttonStyle(OWCPrimaryButtonStyle(filled: false))
                }
                Button(store.t("plusRestore")) {
                    Task { await store.plus.restore() }
                }
                .font(.body)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
        if let error = store.plus.lastProductError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
        }
        if case .pendingAskToBuy = store.plus.authorization {
            Text(store.t("plusWaitingApproval"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
        }
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t("plusAutoRenew"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
            HStack(spacing: 16) {
                Link(store.t("plusTerms"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link(store.t("plusPrivacy"), destination: URL(string: "https://doneat.app/privacy")!)
            }
            .font(.footnote)
        }
        .padding(.top, 8)
    }

    private func productButton(title: String, subtitle: String, product: Product) -> some View {
        Button {
            Task { await store.plus.purchase(product) }
        } label: {
            VStack(spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(OWCPrimaryButtonStyle())
        .disabled(store.plus.purchaseInFlight)
    }

    private func yearlyCTA(_ product: Product) -> String {
        if store.plus.yearlyEligibleForTrial {
            return store.t("plusStartTrial", values: ["price": product.displayPrice])
        }
        return store.t("plusYearly")
    }

    private var titleKey: String {
        switch reason {
        case .intro: "plusIntroTitle"
        case .charts: "plusChartsLocked"
        case .life: "plusLifeLocked"
        case .historyEdit: "plusEditLocked"
        case .sync: "plusSyncLocked"
        case .focus: "plusFocusLocked"
        }
    }
}

struct PlusIntroView: View {
    let store: OffWorkStore

    var body: some View {
        PaywallView(store: store, reason: .intro, showsSkip: true) {
            store.plus.markIntroSeen()
        }
    }
}
