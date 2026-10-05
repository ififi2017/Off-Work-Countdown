import Foundation

/// One local invitation, one real deadline. Reopening a paywall never renews it.
/// The store owns price and purchase verification; this state only controls access.
struct LifetimeOffer: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case onboarding, update321 }
    let source: Source
    var claimedAt: Date?
    var latestObservedAt: Date
    static let duration: TimeInterval = 24 * 60 * 60

    var expiresAt: Date? { claimedAt?.addingTimeInterval(Self.duration) }

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
