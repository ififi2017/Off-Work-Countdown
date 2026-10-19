import Foundation

/// One local invitation, one real deadline. Reopening a paywall never renews it.
/// The store owns price and purchase verification; this state only controls access.
struct LifetimeOffer: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case onboarding, update321
        /// The 3.2.3 gift: wrapped on the timer until opened, then a week.
        case update323
    }
    let source: Source
    var claimedAt: Date?
    var latestObservedAt: Date

    /// A first-run invitation is a decision made in the moment; the update
    /// gift is opened on the user's own time, so it keeps for a week.
    var duration: TimeInterval {
        switch source {
        case .onboarding, .update321: 24 * 60 * 60
        case .update323: 7 * 24 * 60 * 60
        }
    }

    var expiresAt: Date? { claimedAt?.addingTimeInterval(duration) }

    func isActive(at now: Date) -> Bool {
        guard let claimedAt, let expiresAt else { return false }
        // Moving the device clock backwards cannot add time to this offer.
        let effectiveNow = max(now, latestObservedAt)
        return effectiveNow >= claimedAt && effectiveNow < expiresAt
    }

    mutating func claim(at now: Date) {
        guard claimedAt == nil else { return }
        claimedAt = max(now, latestObservedAt)
        latestObservedAt = max(now, latestObservedAt)
    }

    mutating func observe(at now: Date) { latestObservedAt = max(now, latestObservedAt) }

    static func validPrice(regular: Decimal, discounted: Decimal, sameCurrency: Bool) -> Bool {
        sameCurrency && regular > 0 && discounted > 0 && discounted < regular
    }
}
