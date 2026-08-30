import Foundation
import StoreKit
import UIKit

enum PlusProductID {
    static let group = "plus"
    static let monthly = "com.rainif.offworkcountdown.plus.monthly"
    static let yearly = "com.rainif.offworkcountdown.plus.yearly"
    static let lifetime = "com.rainif.offworkcountdown.plus.lifetime"
    static let all = [monthly, yearly, lifetime]
}

enum PlusAuthorizationKind: Equatable, Sendable {
    case lifetime
    case subscribed(expiresAt: Date)
    case inGracePeriod(graceExpiresAt: Date)
}

enum PlusAuthorization: Equatable, Sendable {
    case authorized(PlusAuthorizationKind)
    case unauthorized
    case pendingAskToBuy
    case unverified
}

struct PlusLifetimeEvidence: Equatable, Sendable {
    var revoked: Bool
}

struct PlusSubscriptionEvidence: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case subscribed
        case inGracePeriod
        case billingRetry
        case expired
        case revoked
    }

    var state: State
    var expirationDate: Date?
    var gracePeriodExpirationDate: Date?
    var isTrial: Bool
}

struct PlusEntitlementSnapshot: Equatable, Sendable {
    var lifetime: PlusLifetimeEvidence?
    var subscription: PlusSubscriptionEvidence?
    var askToBuyPending: Bool
}

/// Pure 006 state machine. Views must not reimplement this.
enum PlusEntitlementDecision {
    static func resolve(
        now: Date,
        snapshot: PlusEntitlementSnapshot
    ) -> PlusAuthorization {
        if snapshot.askToBuyPending {
            return .pendingAskToBuy
        }
        if let lifetime = snapshot.lifetime, !lifetime.revoked {
            return .authorized(.lifetime)
        }
        guard let subscription = snapshot.subscription else {
            return .unauthorized
        }
        switch subscription.state {
        case .subscribed:
            guard let expires = subscription.expirationDate, expires > now else {
                return .unauthorized
            }
            return .authorized(.subscribed(expiresAt: expires))
        case .inGracePeriod:
            guard let grace = subscription.gracePeriodExpirationDate, grace > now else {
                return .unauthorized
            }
            return .authorized(.inGracePeriod(graceExpiresAt: grace))
        case .billingRetry, .expired, .revoked:
            return .unauthorized
        }
    }

    static func offlineAccess(
        now: Date,
        cached: PlusEntitlementSnapshot
    ) -> PlusAuthorization {
        resolve(now: now, snapshot: cached)
    }
}

enum PlusPaywallReason: String, Hashable, Sendable {
    case intro
    case charts
    case life
    case historyEdit
    case sync
    case focus
}

@MainActor
@Observable
final class PlusEntitlement {
    private enum Key {
        static let cachedSnapshot = "ios.native.plusCachedSnapshot"
        static let hasSeenIntro = "ios.native.plusHasSeenIntro"
        static let productsEverRequested = "ios.native.plusProductsRequested"
#if DEBUG
        static let debugAuthorized = "ios.native.debugPlusAuthorized"
#endif
    }

    private(set) var authorization: PlusAuthorization = .unauthorized
    private(set) var products: [Product] = []
    private(set) var yearlyEligibleForTrial = false
    private(set) var isLoadingProducts = false
    private(set) var lastProductError: String?
    private(set) var purchaseInFlight = false
    private(set) var hasActiveSubscription = false
    var hasSeenIntro: Bool {
        didSet { defaults.set(hasSeenIntro, forKey: Key.hasSeenIntro) }
    }

    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var cachedSnapshot = PlusEntitlementSnapshot(askToBuyPending: false)

    var isAuthorized: Bool {
        if case .authorized = authorization { return true }
        return false
    }

    /// New observations stop after expire/revoke. A skip-the-paywall user still
    /// collects clock-in rows for the free list.
    var shouldCollectObservations: Bool {
        switch authorization {
        case .authorized, .unverified:
            return true
        case .pendingAskToBuy:
            return false
        case .unauthorized:
            return cachedSnapshot.subscription == nil && cachedSnapshot.lifetime == nil
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasSeenIntro = defaults.bool(forKey: Key.hasSeenIntro)
        if let data = defaults.data(forKey: Key.cachedSnapshot),
           let cached = try? JSONDecoder().decode(CodableSnapshot.self, from: data) {
            cachedSnapshot = cached.snapshot
        }
        authorization = PlusEntitlementDecision.offlineAccess(now: .now, cached: cachedSnapshot)
#if DEBUG
        if defaults.bool(forKey: Key.debugAuthorized) {
            authorization = .authorized(.lifetime)
        }
#endif
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            await self?.refreshFromStore()
            for await update in Transaction.updates {
                if let transaction = try? checkVerified(update) {
                    await transaction.finish()
                }
                await self?.refreshFromStore()
            }
        }
        statusTask = Task { [weak self] in
            for await _ in Product.SubscriptionInfo.Status.updates {
                await self?.refreshFromStore()
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        statusTask?.cancel()
        updatesTask = nil
        statusTask = nil
    }

    func markIntroSeen() {
        hasSeenIntro = true
    }

    /// Products load only after the user asks to see plans.
    func loadProducts() async {
        isLoadingProducts = true
        lastProductError = nil
        defaults.set(true, forKey: Key.productsEverRequested)
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: PlusProductID.all)
            products = loaded.sorted { lhs, rhs in
                rank(lhs) < rank(rhs)
            }
            if let yearly = loaded.first(where: { $0.id == PlusProductID.yearly }) {
                yearlyEligibleForTrial = await yearly.subscription?.isEligibleForIntroOffer ?? false
            }
        } catch {
            lastProductError = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let transaction = try? checkVerified(verification) {
                    await transaction.finish()
                }
                await refreshFromStore()
            case .pending:
                authorization = .pendingAskToBuy
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastProductError = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshFromStore()
        } catch {
            lastProductError = error.localizedDescription
        }
    }

    func manageSubscriptions() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        Task {
            try? await AppStore.showManageSubscriptions(in: scene)
        }
    }

    func yearlyProduct() -> Product? {
        products.first { $0.id == PlusProductID.yearly }
    }

    func monthlyProduct() -> Product? {
        products.first { $0.id == PlusProductID.monthly }
    }

    func lifetimeProduct() -> Product? {
        products.first { $0.id == PlusProductID.lifetime }
    }

#if DEBUG
    func debugSetAuthorized(_ granted: Bool) {
        defaults.set(granted, forKey: Key.debugAuthorized)
        if granted {
            authorization = .authorized(.lifetime)
        } else {
            authorization = PlusEntitlementDecision.resolve(now: .now, snapshot: cachedSnapshot)
        }
    }
#endif

    private func refreshFromStore() async {
        var lifetime: PlusLifetimeEvidence?
        var subscription: PlusSubscriptionEvidence?
        var askToBuyPending = false
        var sawActiveSubscription = false

        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(entitlement) else {
                authorization = .unverified
                return
            }
            if transaction.productType == .nonConsumable, transaction.productID == PlusProductID.lifetime {
                lifetime = PlusLifetimeEvidence(revoked: transaction.revocationDate != nil)
            }
        }

        if let statuses = try? await Product.SubscriptionInfo.status(for: PlusProductID.group) {
            for status in statuses {
                guard case .verified(let renewal) = status.renewalInfo,
                      case .verified(let transaction) = status.transaction
                else {
                    authorization = .unverified
                    return
                }
                if transaction.revocationDate != nil {
                    subscription = PlusSubscriptionEvidence(
                        state: .revoked,
                        expirationDate: transaction.expirationDate,
                        gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                        isTrial: renewal.offerType == .introductory
                    )
                    continue
                }
                switch status.state {
                case .subscribed:
                    sawActiveSubscription = true
                    subscription = PlusSubscriptionEvidence(
                        state: .subscribed,
                        expirationDate: transaction.expirationDate,
                        gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                        isTrial: renewal.offerType == .introductory
                    )
                case .inGracePeriod:
                    sawActiveSubscription = true
                    subscription = PlusSubscriptionEvidence(
                        state: .inGracePeriod,
                        expirationDate: transaction.expirationDate,
                        gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                        isTrial: renewal.offerType == .introductory
                    )
                case .inBillingRetryPeriod:
                    subscription = PlusSubscriptionEvidence(
                        state: .billingRetry,
                        expirationDate: transaction.expirationDate,
                        gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                        isTrial: false
                    )
                case .expired:
                    subscription = PlusSubscriptionEvidence(
                        state: .expired,
                        expirationDate: transaction.expirationDate,
                        gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                        isTrial: false
                    )
                case .revoked:
                    subscription = PlusSubscriptionEvidence(
                        state: .revoked,
                        expirationDate: transaction.expirationDate,
                        gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                        isTrial: false
                    )
                default:
                    break
                }
            }
        }

        hasActiveSubscription = sawActiveSubscription
        let snapshot = PlusEntitlementSnapshot(
            lifetime: lifetime,
            subscription: subscription,
            askToBuyPending: askToBuyPending
        )
        cachedSnapshot = snapshot
        if let data = try? JSONEncoder().encode(CodableSnapshot(snapshot: snapshot)) {
            defaults.set(data, forKey: Key.cachedSnapshot)
        }
#if DEBUG
        if defaults.bool(forKey: Key.debugAuthorized) {
            authorization = .authorized(.lifetime)
            return
        }
#endif
        authorization = PlusEntitlementDecision.resolve(now: .now, snapshot: snapshot)
    }

    private func rank(_ product: Product) -> Int {
        switch product.id {
        case PlusProductID.yearly: 0
        case PlusProductID.monthly: 1
        case PlusProductID.lifetime: 2
        default: 3
        }
    }
}

private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified:
        throw PlusVerificationError.unverified
    case .verified(let value):
        return value
    }
}

private enum PlusVerificationError: Error {
    case unverified
}

private struct CodableSnapshot: Codable {
    var lifetimeRevoked: Bool?
    var hasLifetime: Bool
    var subscriptionState: String?
    var expirationMs: Double?
    var graceMs: Double?
    var isTrial: Bool
    var askToBuyPending: Bool

    var snapshot: PlusEntitlementSnapshot {
        var lifetime: PlusLifetimeEvidence?
        if hasLifetime {
            lifetime = PlusLifetimeEvidence(revoked: lifetimeRevoked ?? false)
        }
        var subscription: PlusSubscriptionEvidence?
        if let subscriptionState {
            let state: PlusSubscriptionEvidence.State
            switch subscriptionState {
            case "subscribed": state = .subscribed
            case "grace": state = .inGracePeriod
            case "retry": state = .billingRetry
            case "expired": state = .expired
            case "revoked": state = .revoked
            default: state = .expired
            }
            subscription = PlusSubscriptionEvidence(
                state: state,
                expirationDate: expirationMs.map { Date(timeIntervalSince1970: $0 / 1_000) },
                gracePeriodExpirationDate: graceMs.map { Date(timeIntervalSince1970: $0 / 1_000) },
                isTrial: isTrial
            )
        }
        return PlusEntitlementSnapshot(
            lifetime: lifetime,
            subscription: subscription,
            askToBuyPending: askToBuyPending
        )
    }

    init(snapshot: PlusEntitlementSnapshot) {
        hasLifetime = snapshot.lifetime != nil
        lifetimeRevoked = snapshot.lifetime?.revoked
        askToBuyPending = snapshot.askToBuyPending
        isTrial = snapshot.subscription?.isTrial ?? false
        expirationMs = snapshot.subscription?.expirationDate.map { $0.timeIntervalSince1970 * 1_000 }
        graceMs = snapshot.subscription?.gracePeriodExpirationDate.map { $0.timeIntervalSince1970 * 1_000 }
        switch snapshot.subscription?.state {
        case .subscribed: subscriptionState = "subscribed"
        case .inGracePeriod: subscriptionState = "grace"
        case .billingRetry: subscriptionState = "retry"
        case .expired: subscriptionState = "expired"
        case .revoked: subscriptionState = "revoked"
        case nil: subscriptionState = nil
        }
    }
}
