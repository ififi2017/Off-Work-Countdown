import Foundation
import Testing
@testable import App

@MainActor
@Test("Lifetime unlocks Plus until it is revoked")
func lifetimeAuthorizesUntilRevoked() {
    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let authorized = PlusEntitlementDecision.resolve(
        now: now,
        snapshot: PlusEntitlementSnapshot(
            lifetime: PlusLifetimeEvidence(revoked: false),
            subscription: nil,
            askToBuyPending: false
        )
    )
    #expect(authorized == .authorized(.lifetime))

    let revoked = PlusEntitlementDecision.resolve(
        now: now,
        snapshot: PlusEntitlementSnapshot(
            lifetime: PlusLifetimeEvidence(revoked: true),
            subscription: nil,
            askToBuyPending: false
        )
    )
    #expect(revoked == .unauthorized)
}

@MainActor
@Test("Grace period stays authorized past the subscription expiration")
func gracePeriodUsesGraceDeadline() {
    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let expired = now.addingTimeInterval(-3_600)
    let grace = now.addingTimeInterval(86_400)
    let access = PlusEntitlementDecision.resolve(
        now: now,
        snapshot: PlusEntitlementSnapshot(
            lifetime: nil,
            subscription: PlusSubscriptionEvidence(
                state: .inGracePeriod,
                expirationDate: expired,
                gracePeriodExpirationDate: grace,
                isTrial: false
            ),
            askToBuyPending: false
        )
    )
    #expect(access == .authorized(.inGracePeriod(graceExpiresAt: grace)))
}

@MainActor
@Test("Offline monthlies lose access after expiration")
func offlineMonthlyDoesNotExtendLocally() {
    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let access = PlusEntitlementDecision.offlineAccess(
        now: now,
        cached: PlusEntitlementSnapshot(
            lifetime: nil,
            subscription: PlusSubscriptionEvidence(
                state: .subscribed,
                expirationDate: now.addingTimeInterval(-1),
                gracePeriodExpirationDate: nil,
                isTrial: false
            ),
            askToBuyPending: false
        )
    )
    #expect(access == .unauthorized)
}

@MainActor
@Test("Ask to Buy is pending, not an error")
func askToBuyIsPending() {
    let access = PlusEntitlementDecision.resolve(
        now: .now,
        snapshot: PlusEntitlementSnapshot(
            lifetime: nil,
            subscription: nil,
            askToBuyPending: true
        )
    )
    #expect(access == .pendingAskToBuy)
}
