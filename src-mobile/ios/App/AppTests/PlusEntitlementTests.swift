import Foundation
import StoreKit
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
            askToBuyPendingSince: nil
        )
    )
    #expect(authorized == .authorized(.lifetime))

    let revoked = PlusEntitlementDecision.resolve(
        now: now,
        snapshot: PlusEntitlementSnapshot(
            lifetime: PlusLifetimeEvidence(revoked: true),
            subscription: nil,
            askToBuyPendingSince: nil
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
            askToBuyPendingSince: nil
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
            askToBuyPendingSince: nil
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
            askToBuyPendingSince: .now
        )
    )
    #expect(access == .pendingAskToBuy)
}

@MainActor
@Test("Ask to Buy does not overwrite an existing lifetime grant")
func askToBuyDoesNotReplaceLifetime() {
    let access = PlusEntitlementDecision.resolve(
        now: .now,
        snapshot: PlusEntitlementSnapshot(
            lifetime: PlusLifetimeEvidence(revoked: false),
            subscription: nil,
            askToBuyPendingSince: .now
        )
    )
    #expect(access == .authorized(.lifetime))
}

@MainActor
@Test("A failed StoreKit refresh keeps the cached deadline")
func unavailableRefreshKeepsCachedGrant() {
    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let cached = PlusEntitlementSnapshot(
        lifetime: nil,
        subscription: PlusSubscriptionEvidence(
            state: .subscribed,
            expirationDate: now.addingTimeInterval(86_400),
            gracePeriodExpirationDate: nil,
            isTrial: false
        ),
        askToBuyPendingSince: nil
    )
    let applied = PlusEntitlementDecision.applyRefresh(
        now: now,
        cached: cached,
        outcome: .unavailable
    )
    #expect(applied.authorization == .authorized(.subscribed(expiresAt: cached.subscription!.expirationDate!)))
    #expect(!applied.persist)
}

@MainActor
@Test("A confirmed empty snapshot is the only way to drop a grant")
func confirmedEmptyRefreshClearsGrant() {
    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let cached = PlusEntitlementSnapshot(
        lifetime: PlusLifetimeEvidence(revoked: false),
        subscription: nil,
        askToBuyPendingSince: nil
    )
    let applied = PlusEntitlementDecision.applyRefresh(
        now: now,
        cached: cached,
        outcome: .confirmed(PlusEntitlementSnapshot(lifetime: nil, subscription: nil, askToBuyPendingSince: nil))
    )
    #expect(applied.authorization == .unauthorized)
    #expect(applied.persist)
}

@MainActor
@Test("StoreKit group IDs never include the plus reference name")
func storeKitGroupsRejectReferenceName() {
    #expect(PlusStoreKitGroups.resolved(from: ["plus"]) == [PlusProductID.storeKitConfigurationGroupID])
    #expect(PlusStoreKitGroups.resolved(from: ["22345761"]) == ["22345761"])
    #expect(!PlusStoreKitGroups.resolved(from: ["plus", "20901234"]).contains("plus"))
}

@Test("StoreKit configuration exposes monthly, yearly, and lifetime products")
func storeKitConfigurationLoadsAllProducts() async throws {
    let products = try await Product.products(for: PlusProductID.all)
    #expect(Set(products.map(\.id)) == Set(PlusProductID.all))
    #expect(products.first(where: { $0.id == PlusProductID.monthly })?.type == .autoRenewable)
    #expect(products.first(where: { $0.id == PlusProductID.yearly })?.type == .autoRenewable)
    #expect(products.first(where: { $0.id == PlusProductID.lifetime })?.type == .nonConsumable)
}

@Test("An active StoreKit status wins regardless of result order")
func storeKitEvidencePrefersActiveStatus() {
    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let expired = PlusSubscriptionEvidence(
        state: .expired,
        expirationDate: now.addingTimeInterval(-86_400),
        gracePeriodExpirationDate: nil,
        isTrial: false
    )
    let active = PlusSubscriptionEvidence(
        state: .subscribed,
        expirationDate: now.addingTimeInterval(86_400),
        gracePeriodExpirationDate: nil,
        isTrial: true
    )

    #expect(PlusSubscriptionEvidence.preferred(expired, active) == active)
    #expect(PlusSubscriptionEvidence.preferred(active, expired) == active)
}

@Test("StoreKit evidence keeps the later deadline within one state")
func storeKitEvidencePrefersLaterDeadline() {
    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let earlier = PlusSubscriptionEvidence(
        state: .inGracePeriod,
        expirationDate: now,
        gracePeriodExpirationDate: now.addingTimeInterval(3_600),
        isTrial: false
    )
    let later = PlusSubscriptionEvidence(
        state: .inGracePeriod,
        expirationDate: now,
        gracePeriodExpirationDate: now.addingTimeInterval(7_200),
        isTrial: false
    )

    #expect(PlusSubscriptionEvidence.preferred(earlier, later) == later)
}

@MainActor
@Test("The free records window is today and the previous six days in the records calendar")
func recordsFreeWindowIsSevenCivilDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
    #expect(RecordsAccess.freeWindowContains(dayKey: "2026-08-30", today: today, calendar: calendar))
    #expect(RecordsAccess.freeWindowContains(dayKey: "2026-08-24", today: today, calendar: calendar))
    #expect(!RecordsAccess.freeWindowContains(dayKey: "2026-08-23", today: today, calendar: calendar))
    #expect(!RecordsAccess.freeWindowContains(dayKey: "2026-08-31", today: today, calendar: calendar))
    #expect(!RecordsAccess.allows(.recordsPageEdit, authorized: false))
    #expect(RecordsAccess.canRevealDay(dayKey: "2026-08-24", today: today, calendar: calendar, authorized: false))
    #expect(!RecordsAccess.canRevealDay(dayKey: "2026-08-23", today: today, calendar: calendar, authorized: false))
    #expect(RecordsAccess.canRevealDay(dayKey: "2026-01-01", today: today, calendar: calendar, authorized: true))
    #expect(RecordsAccess.allows(.recordsPageEdit, authorized: true))
    #expect(!RecordsScale.week.requiresPlus)
    #expect(!RecordsScale.month.requiresPlus)
    #expect(RecordsScale.year.requiresPlus)
    #expect(RecordsScale.life.requiresPlus)
}

@MainActor
@Test("Free All Records crosses year boundaries without retaining locked metadata")
func freeAllRecordsPresentationDoesNotLeakLockedYearsOrCounts() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 1, day: 4))!
    let entries = [
        "2024-06-01", // Locked history: neither this year nor its count may survive.
        "2025-12-28", // Eight days ago: also locked.
        "2025-12-29", "2025-12-30", "2025-12-31",
        "2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04",
    ].map { RecordDayIndexEntry(dayKey: $0, dayOverride: DayOverride(
        dayKey: $0,
        shiftAnchorDate: RecordJSON.date(fromDayKey: $0, calendar: calendar)!,
        kind: .notWorking,
        segments: [],
        timeZoneIdentifier: "UTC"
    )) }

    let free = RecordsAllRecordsPresentation(
        entries: entries,
        isAuthorized: false,
        today: today,
        calendar: calendar
    )
    #expect(free.visibleEntries.map(\.dayKey) == [
        "2025-12-29", "2025-12-30", "2025-12-31",
        "2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04",
    ])
    #expect(free.years == [2026, 2025])
    #expect(free.count(in: 2026) == 4)
    #expect(free.count(in: 2025) == 3)
    #expect(free.hasLockedHistory)

    let paid = RecordsAllRecordsPresentation(
        entries: entries,
        isAuthorized: true,
        today: today,
        calendar: calendar
    )
    #expect(paid.visibleEntries.count == entries.count)
    #expect(paid.years == [2026, 2025, 2024])
    #expect(!paid.hasLockedHistory)
}

// MARK: - Ask to Buy is a purchase that has not happened yet

@MainActor
@Test("Asking to buy does not stop a free user from recording work")
func askToBuyKeepsCollectingObservations() {
    let snapshot = PlusEntitlementSnapshot(
        lifetime: nil,
        subscription: nil,
        askToBuyPendingSince: .now
    )
    #expect(PlusEntitlementDecision.collectsObservations(
        authorization: .pendingAskToBuy,
        snapshot: snapshot
    ))
}

@MainActor
@Test("A lapsed purchase does stop new observations")
func lapsedPurchaseStopsCollectingObservations() {
    let snapshot = PlusEntitlementSnapshot(
        lifetime: nil,
        subscription: PlusSubscriptionEvidence(
            state: .expired,
            expirationDate: Date(timeIntervalSince1970: 1_770_000_000),
            gracePeriodExpirationDate: nil,
            isTrial: false
        ),
        askToBuyPendingSince: nil
    )
    #expect(!PlusEntitlementDecision.collectsObservations(
        authorization: .unauthorized,
        snapshot: snapshot
    ))
}

@MainActor
@Test("An unanswered Ask to Buy lapses instead of waiting forever")
func askToBuyLapsesAfterApplesWindow() {
    let asked = Date(timeIntervalSince1970: 1_777_000_000)
    let snapshot = PlusEntitlementSnapshot(
        lifetime: nil,
        subscription: nil,
        askToBuyPendingSince: asked
    )
    let while_open = PlusEntitlementDecision.resolve(
        now: asked.addingTimeInterval(60 * 60),
        snapshot: snapshot
    )
    let after = PlusEntitlementDecision.resolve(
        now: asked.addingTimeInterval(PlusEntitlementSnapshot.askToBuyLifetimeSeconds + 1),
        snapshot: snapshot
    )
    #expect(while_open == .pendingAskToBuy)
    #expect(after == .unauthorized)
}

@MainActor
@Test("A refresh carries a live Ask to Buy but drops a lapsed one")
func refreshCarriesOnlyLiveAskToBuy() {
    let asked = Date(timeIntervalSince1970: 1_777_000_000)
    let cached = PlusEntitlementSnapshot(
        lifetime: nil,
        subscription: nil,
        askToBuyPendingSince: asked
    )
    let empty = PlusEntitlementSnapshot(lifetime: nil, subscription: nil, askToBuyPendingSince: nil)
    let live = PlusEntitlementDecision.applyRefresh(
        now: asked.addingTimeInterval(60),
        cached: cached,
        outcome: .confirmed(empty)
    )
    let lapsed = PlusEntitlementDecision.applyRefresh(
        now: asked.addingTimeInterval(PlusEntitlementSnapshot.askToBuyLifetimeSeconds + 1),
        cached: cached,
        outcome: .confirmed(empty)
    )
    #expect(live.authorization == .pendingAskToBuy)
    #expect(live.snapshot.askToBuyPendingSince == asked)
    #expect(lapsed.authorization == .unauthorized)
    #expect(lapsed.snapshot.askToBuyPendingSince == nil)
}

// MARK: - An unverifiable transaction is not proof of no purchase

@MainActor
@Test("A transaction StoreKit cannot verify keeps the cached grant")
func unverifiedRefreshKeepsCachedGrant() {
    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let cached = PlusEntitlementSnapshot(
        lifetime: PlusLifetimeEvidence(revoked: false),
        subscription: nil,
        askToBuyPendingSince: nil
    )
    let applied = PlusEntitlementDecision.applyRefresh(
        now: now,
        cached: cached,
        outcome: .unverified
    )
    #expect(applied.authorization == .authorized(.lifetime))
    #expect(!applied.persist)
}

@MainActor
@Test("An unverified refresh cannot invent a grant the cache never held")
func unverifiedRefreshCannotCreateGrant() {
    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let expiredCache = PlusEntitlementSnapshot(
        lifetime: nil,
        subscription: PlusSubscriptionEvidence(
            state: .subscribed,
            expirationDate: now.addingTimeInterval(-60),
            gracePeriodExpirationDate: nil,
            isTrial: false
        ),
        askToBuyPendingSince: nil
    )
    let empty = PlusEntitlementDecision.applyRefresh(
        now: now,
        cached: PlusEntitlementSnapshot(lifetime: nil, subscription: nil, askToBuyPendingSince: nil),
        outcome: .unverified
    )
    let expired = PlusEntitlementDecision.applyRefresh(
        now: now,
        cached: expiredCache,
        outcome: .unverified
    )
    #expect(empty.authorization == .unauthorized)
    #expect(expired.authorization == .unauthorized)
}
