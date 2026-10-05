import Foundation
import Testing
@testable import App

@Suite("Lifetime offer eligibility and real deadlines")
@MainActor
struct LifetimeOfferTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func invitationDoesNotStartClock() {
        let offer = LifetimeOffer(source: .update321, latestObservedAt: now)
        #expect(offer.expiresAt == nil)
        #expect(!offer.isActive(at: now))
    }

    @Test func claimExpiresAtExactly24HoursAndNeverRestarts() {
        var offer = LifetimeOffer(source: .onboarding, latestObservedAt: now)
        offer.claim(at: now)
        offer.claim(at: now.addingTimeInterval(100))
        #expect(offer.expiresAt == now.addingTimeInterval(86_400))
        #expect(offer.isActive(at: now.addingTimeInterval(86_399)))
        #expect(!offer.isActive(at: now.addingTimeInterval(86_400)))
    }

    @Test func returningClockCannotReviveExpiredOffer() throws {
        var offer = LifetimeOffer(source: .update321, latestObservedAt: now)
        offer.claim(at: now)
        offer.observe(at: now.addingTimeInterval(86_401))
        let restored = try JSONDecoder().decode(LifetimeOffer.self, from: JSONEncoder().encode(offer))
        #expect(!restored.isActive(at: now.addingTimeInterval(60)))
    }

    @Test func onlyRealLowerPricesInSameCurrencyQualify() {
        #expect(LifetimeOffer.validPrice(regular: 100, discounted: 75, sameCurrency: true))
        #expect(!LifetimeOffer.validPrice(regular: 100, discounted: 100, sameCurrency: true))
        #expect(!LifetimeOffer.validPrice(regular: 100, discounted: 120, sameCurrency: true))
        #expect(!LifetimeOffer.validPrice(regular: 100, discounted: 75, sameCurrency: false))
        #expect(!LifetimeOffer.validPrice(regular: 100, discounted: 0, sameCurrency: true))
    }

    @Test func unavailableStoreCannotConsumeOfferAndReloadPreservesInvitation() {
        let suite = "LifetimeOfferTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let plus = PlusEntitlement(defaults: defaults)
        plus.inviteLifetimeOffer(from: .update321)
        plus.claimLifetimeOffer(at: now)
        #expect(plus.lifetimeOffer?.claimedAt == nil)
        let reloaded = PlusEntitlement(defaults: defaults)
        reloaded.inviteLifetimeOffer(from: .onboarding)
        #expect(reloaded.lifetimeOffer?.source == .update321)
        #expect(reloaded.lifetimeOffer?.claimedAt == nil)
    }

    @Test func ownedPlusCannotReceiveOffer() {
        let suite = "LifetimeOfferTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.debugPlusAuthorized")
        let plus = PlusEntitlement(defaults: defaults)
        plus.inviteLifetimeOffer(from: .update321)
        #expect(plus.lifetimeOffer == nil)
        #expect(!plus.canOfferLifetime)
    }

    @Test func revealingPriceStartsOnceAndSurvivesRelaunch() throws {
        let suite = "LifetimeOfferReveal.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.qaLifetimeOffer")
        let plus = PlusEntitlement(defaults: defaults)
        let firstReveal = Date.now
        #expect(plus.revealLifetimeOffer(from: .onboarding, at: firstReveal))
        let deadline = try #require(plus.lifetimeOffer?.expiresAt)
        #expect(deadline == firstReveal.addingTimeInterval(86_400))
        let reloaded = PlusEntitlement(defaults: defaults)
        #expect(reloaded.revealLifetimeOffer(from: .update321, at: firstReveal.addingTimeInterval(120)))
        #expect(reloaded.lifetimeOffer?.expiresAt == deadline)
        #expect(!reloaded.revealLifetimeOffer(from: .onboarding, at: deadline))
        #expect(reloaded.lifetimeOffer?.expiresAt == deadline)
    }

    @Test func revealingWithoutPriceDoesNotCreateOrActivateOffer() throws {
        let suite = "LifetimeOfferNoPrice.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let plus = PlusEntitlement(defaults: defaults)
        #expect(!plus.revealLifetimeOffer(from: .onboarding))
        #expect(plus.lifetimeOffer == nil)
    }

    @Test("Offer percentages follow app language rather than the device region")
    func savingsFollowAppLanguage() async throws {
        let suite = "LifetimeOfferLanguage.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.qaLifetimeOffer")
        defaults.set("CHN", forKey: "ios.native.qaLifetimeOfferStorefront")
        let plus = PlusEntitlement(defaults: defaults)
        let preferences = PreferencesStore(defaults: defaults, records: .inMemory())
        let text = AppText(preferences: preferences)
        for (language, expected) in [("ja", "約25%オフ"), ("en", "≈25% off"), ("zh-CN", "≈7.5折"), ("zh-TW", "≈7.5折")] {
            let command = preferences.applyPreferences { $0.languageOverride = language }
            _ = await command.value
            #expect(plus.lifetimeSavingsLabel(text: text) == expected)
        }
    }

}
