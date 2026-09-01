import Foundation
import StoreKit
import UIKit

nonisolated enum PlusProductID {
    /// App Store Connect subscription group *reference name*. Never pass this
    /// to StoreKit `status(for:)`.
    static let groupReferenceName = "plus"
    /// App Store Connect subscription group ID, used only when StoreKit can't
    /// provide a group ID from a verified Product or Transaction.
    static let storeKitConfigurationGroupID = "22345761"
    static let monthly = "com.rainif.offworkcountdown.plus.monthly"
    static let yearly = "com.rainif.offworkcountdown.plus.yearly"
    static let lifetime = "com.rainif.offworkcountdown.plus.lifetime"
    static let all = [monthly, yearly, lifetime]
}

nonisolated enum PlusStoreKitGroups {
    /// StoreKit wants the numeric subscription group ID, never `"plus"`.
    static func resolved(from discovered: [String]) -> [String] {
        var ids = Set(discovered.filter { !$0.isEmpty && $0 != PlusProductID.groupReferenceName })
        if ids.isEmpty {
            ids.insert(PlusProductID.storeKitConfigurationGroupID)
        }
        return ids.sorted()
    }
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

nonisolated struct PlusLifetimeEvidence: Equatable, Sendable {
    var revoked: Bool
}

nonisolated struct PlusSubscriptionEvidence: Equatable, Sendable {
    nonisolated enum State: Equatable, Sendable {
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

    /// StoreKit can return several products and historical states from the
    /// same subscription group. Pick the strongest current entitlement
    /// deterministically instead of letting async iteration order decide.
    static func preferred(
        _ lhs: PlusSubscriptionEvidence?,
        _ rhs: PlusSubscriptionEvidence
    ) -> PlusSubscriptionEvidence {
        guard let lhs else { return rhs }
        let left = (stateRank(lhs.state), deadline(lhs))
        let right = (stateRank(rhs.state), deadline(rhs))
        if right.0 != left.0 { return right.0 > left.0 ? rhs : lhs }
        return right.1 > left.1 ? rhs : lhs
    }

    private static func stateRank(_ state: State) -> Int {
        switch state {
        case .subscribed: 5
        case .inGracePeriod: 4
        case .billingRetry: 3
        case .expired: 2
        case .revoked: 1
        }
    }

    private static func deadline(_ evidence: PlusSubscriptionEvidence) -> Date {
        max(evidence.gracePeriodExpirationDate ?? .distantPast, evidence.expirationDate ?? .distantPast)
    }
}

struct PlusEntitlementSnapshot: Equatable, Sendable {
    var lifetime: PlusLifetimeEvidence?
    var subscription: PlusSubscriptionEvidence?
    var askToBuyPending: Bool
}

enum PlusRefreshOutcome: Equatable, Sendable {
    case confirmed(PlusEntitlementSnapshot)
    case unavailable
    case unverified
}

/// Pure 006 state machine. Views must not reimplement this.
enum PlusEntitlementDecision {
    static func resolve(
        now: Date,
        snapshot: PlusEntitlementSnapshot
    ) -> PlusAuthorization {
        if let lifetime = snapshot.lifetime, !lifetime.revoked {
            return .authorized(.lifetime)
        }
        if let subscription = snapshot.subscription {
            switch subscription.state {
            case .subscribed:
                if let expires = subscription.expirationDate, expires > now {
                    return .authorized(.subscribed(expiresAt: expires))
                }
            case .inGracePeriod:
                if let grace = subscription.gracePeriodExpirationDate, grace > now {
                    return .authorized(.inGracePeriod(graceExpiresAt: grace))
                }
            case .billingRetry, .expired, .revoked:
                break
            }
        }
        if snapshot.askToBuyPending {
            return .pendingAskToBuy
        }
        return .unauthorized
    }

    static func offlineAccess(
        now: Date,
        cached: PlusEntitlementSnapshot
    ) -> PlusAuthorization {
        resolve(now: now, snapshot: cached)
    }

    /// Network / verification failures keep the last verified snapshot and
    /// honor its deadline. A confirmed empty snapshot is the only path that
    /// may overwrite a cached grant.
    static func applyRefresh(
        now: Date,
        cached: PlusEntitlementSnapshot,
        outcome: PlusRefreshOutcome
    ) -> (authorization: PlusAuthorization, snapshot: PlusEntitlementSnapshot, persist: Bool) {
        switch outcome {
        case .unverified:
            return (.unverified, cached, false)
        case .unavailable:
            return (offlineAccess(now: now, cached: cached), cached, false)
        case .confirmed(var snapshot):
            if resolve(now: now, snapshot: snapshot) == .unauthorized, cached.askToBuyPending {
                snapshot.askToBuyPending = true
            }
            return (resolve(now: now, snapshot: snapshot), snapshot, true)
        }
    }
}

enum PlusPendingAction: Equatable, Sendable {
    case historyEdit(dayKey: String)
    case startFocus(taskID: UUID)
    case addFocusTask(title: String, pomodoros: Int, icon: FocusTaskIcon, isFavorite: Bool)
    case addAndStartFocus(title: String, pomodoros: Int, icon: FocusTaskIcon, isFavorite: Bool)
    case presentAddFocus
    case openFocus
    case enableCycleEndSummaryNotifications
    case enableSync
}

enum RecordsPaidCapability: Equatable, Sendable {
    case charts
    case life
    case recordsPageEdit
    case focus
    case enableSync
}

/// 010 free window and paid-capability matrix. Locked views must not receive
/// the real values that this gate is hiding.
enum RecordsAccess {
    static let freeLookbackDays = 6

    static func freeWindowContains(dayKey: String, today: Date, calendar: Calendar) -> Bool {
        guard let day = RecordJSON.date(fromDayKey: dayKey, calendar: calendar) else { return false }
        let start = calendar.startOfDay(for: today)
        guard let windowStart = calendar.date(byAdding: .day, value: -freeLookbackDays, to: start) else {
            return false
        }
        return day >= windowStart && day <= start
    }

    static func allows(_ capability: RecordsPaidCapability, authorized: Bool) -> Bool {
        switch capability {
        case .charts, .life, .recordsPageEdit, .focus, .enableSync:
            return authorized
        }
    }
}

enum PlusPaywallReason: String, Hashable, Sendable, Identifiable {
    case intro
    case charts
    case life
    case historyEdit
    case sync
    case focus
    case cycleEndSummaryNotifications

    var id: String { rawValue }
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
    private(set) var restoreInFlight = false
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

    /// A one-time purchase, so nothing about it renews and nothing about it can
    /// be managed. The paywall and the settings row both need to say so instead
    /// of offering a subscription to someone who already owns the app.
    var isLifetime: Bool {
        if case .authorized(.lifetime) = authorization { return true }
        return false
    }

    /// Inside the introductory offer right now, not merely eligible for it.
    /// `yearlyEligibleForTrial` answers the opposite question.
    var isInTrial: Bool {
        guard let subscription = cachedSnapshot.subscription, subscription.isTrial else { return false }
        switch subscription.state {
        case .subscribed, .inGracePeriod: return true
        case .billingRetry, .expired, .revoked: return false
        }
    }

    /// One lock for loading, buying and restoring. Three separate flags let a
    /// restore start underneath a purchase.
    var isBusy: Bool { purchaseInFlight || restoreInFlight || isLoadingProducts }

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
            await Task.yield()
            await self?.refreshFromStore()
            for await update in Transaction.updates {
                if let transaction = try? checkVerified(update) {
                    await transaction.finish()
                }
                await self?.refreshFromStore()
            }
        }
        statusTask = Task { [weak self] in
            await Task.yield()
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

    /// Called when the paywall appears, so the three plans are on screen
    /// instead of hiding behind a second tap.
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
        lastProductError = nil
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
                var pending = cachedSnapshot
                pending.askToBuyPending = true
                cachedSnapshot = pending
                if let data = try? JSONEncoder().encode(CodableSnapshot(snapshot: pending)) {
                    defaults.set(data, forKey: Key.cachedSnapshot)
                }
                authorization = PlusEntitlementDecision.resolve(now: .now, snapshot: pending)
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
        restoreInFlight = true
        defer { restoreInFlight = false }
        lastProductError = nil
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
        let fetched = await LaunchTrace.interval("storeKitRefresh") {
            await fetchStoreKitEvidence()
        }
        let outcome: PlusRefreshOutcome
        if fetched.unverified {
            outcome = .unverified
        } else if fetched.unavailable {
            outcome = .unavailable
        } else {
            outcome = .confirmed(
                PlusEntitlementSnapshot(
                    lifetime: fetched.lifetime,
                    subscription: fetched.subscription,
                    askToBuyPending: false
                )
            )
        }
        let applied = PlusEntitlementDecision.applyRefresh(
            now: .now,
            cached: cachedSnapshot,
            outcome: outcome
        )
        if fetched.sawActiveSubscription {
            hasActiveSubscription = true
        } else if case .confirmed = outcome {
            hasActiveSubscription = false
        }
        if applied.persist {
            cachedSnapshot = applied.snapshot
            if let data = try? JSONEncoder().encode(CodableSnapshot(snapshot: applied.snapshot)) {
                defaults.set(data, forKey: Key.cachedSnapshot)
            }
        }
#if DEBUG
        if defaults.bool(forKey: Key.debugAuthorized) {
            authorization = .authorized(.lifetime)
            return
        }
#endif
        authorization = applied.authorization
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

/// StoreKit's entitlement walk is the 20-second sandbox stall. Keep it off
/// the main actor so the first frame is not waiting on the network.
nonisolated private struct StoreKitEvidence: Sendable {
    var lifetime: PlusLifetimeEvidence?
    var subscription: PlusSubscriptionEvidence?
    var sawActiveSubscription = false
    var unverified = false
    var unavailable = false
}

/// `@concurrent` is required: Swift 6.2 `nonisolated async` still runs on
/// the caller, and a MainActor StoreKit walk is what held the launch screen.
@concurrent
nonisolated private func fetchStoreKitEvidence() async -> StoreKitEvidence {
    var fetched = StoreKitEvidence()
    var groupIDs: [String] = []
    for await entitlement in Transaction.currentEntitlements {
        guard let transaction = try? checkVerified(entitlement) else {
            fetched.unverified = true
            return fetched
        }
        if transaction.productType == .nonConsumable, transaction.productID == PlusProductID.lifetime {
            fetched.lifetime = PlusLifetimeEvidence(revoked: transaction.revocationDate != nil)
        }
        if transaction.productType == .autoRenewable {
            if let groupID = transaction.subscriptionGroupID {
                groupIDs.append(groupID)
            }
            let evidence = subscriptionEvidence(from: transaction)
            fetched.subscription = PlusSubscriptionEvidence.preferred(fetched.subscription, evidence)
            if let expiration = transaction.expirationDate, expiration > Date(),
               transaction.revocationDate == nil {
                fetched.sawActiveSubscription = true
            }
        }
    }

    if groupIDs.isEmpty, let products = try? await Product.products(for: PlusProductID.all) {
        for product in products {
            if let groupID = product.subscription?.subscriptionGroupID {
                groupIDs.append(groupID)
            }
        }
    }

    let resolvedGroups = PlusStoreKitGroups.resolved(from: groupIDs)
    var queried = false
    var queryFailed = false
    for groupID in resolvedGroups {
        do {
            let statuses = try await Product.SubscriptionInfo.status(for: groupID)
            queried = true
            applyStatuses(statuses, to: &fetched)
        } catch {
            queryFailed = true
        }
    }
    if queryFailed, !queried, fetched.lifetime == nil, fetched.subscription == nil {
        fetched.unavailable = true
    }
    return fetched
}

nonisolated private func subscriptionEvidence(from transaction: Transaction) -> PlusSubscriptionEvidence {
    if transaction.revocationDate != nil {
        return PlusSubscriptionEvidence(
            state: .revoked,
            expirationDate: transaction.expirationDate,
            gracePeriodExpirationDate: nil,
            isTrial: false
        )
    }
    if let expiration = transaction.expirationDate, expiration > Date() {
        return PlusSubscriptionEvidence(
            state: .subscribed,
            expirationDate: expiration,
            gracePeriodExpirationDate: nil,
            isTrial: false
        )
    }
    return PlusSubscriptionEvidence(
        state: .expired,
        expirationDate: transaction.expirationDate,
        gracePeriodExpirationDate: nil,
        isTrial: false
    )
}

nonisolated private func applyStatuses(
    _ statuses: [Product.SubscriptionInfo.Status],
    to fetched: inout StoreKitEvidence
) {
    for status in statuses {
        guard case .verified(let renewal) = status.renewalInfo,
              case .verified(let transaction) = status.transaction
        else {
            fetched.unverified = true
            return
        }
        if transaction.revocationDate != nil {
            let evidence = PlusSubscriptionEvidence(
                state: .revoked,
                expirationDate: transaction.expirationDate,
                gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                isTrial: renewal.offer?.type == .introductory
            )
            fetched.subscription = PlusSubscriptionEvidence.preferred(fetched.subscription, evidence)
            continue
        }
        switch status.state {
        case .subscribed:
            fetched.sawActiveSubscription = true
            let evidence = PlusSubscriptionEvidence(
                state: .subscribed,
                expirationDate: transaction.expirationDate,
                gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                isTrial: renewal.offer?.type == .introductory
            )
            fetched.subscription = PlusSubscriptionEvidence.preferred(fetched.subscription, evidence)
        case .inGracePeriod:
            fetched.sawActiveSubscription = true
            let evidence = PlusSubscriptionEvidence(
                state: .inGracePeriod,
                expirationDate: transaction.expirationDate,
                gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                isTrial: renewal.offer?.type == .introductory
            )
            fetched.subscription = PlusSubscriptionEvidence.preferred(fetched.subscription, evidence)
        case .inBillingRetryPeriod:
            let evidence = PlusSubscriptionEvidence(
                state: .billingRetry,
                expirationDate: transaction.expirationDate,
                gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                isTrial: false
            )
            fetched.subscription = PlusSubscriptionEvidence.preferred(fetched.subscription, evidence)
        case .expired:
            let evidence = PlusSubscriptionEvidence(
                state: .expired,
                expirationDate: transaction.expirationDate,
                gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                isTrial: false
            )
            fetched.subscription = PlusSubscriptionEvidence.preferred(fetched.subscription, evidence)
        case .revoked:
            let evidence = PlusSubscriptionEvidence(
                state: .revoked,
                expirationDate: transaction.expirationDate,
                gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                isTrial: false
            )
            fetched.subscription = PlusSubscriptionEvidence.preferred(fetched.subscription, evidence)
        default:
            break
        }
    }
}

nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified:
        throw PlusVerificationError.unverified
    case .verified(let value):
        return value
    }
}

nonisolated private enum PlusVerificationError: Error {
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
