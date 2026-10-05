import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import App

/// StoreKit's test environment is process-global; run this suite serially.
// XcodeBuildMCP's test-products runner currently stalls inside SKTestSession
// initialization. Run explicitly from an IDE-backed StoreKit session.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DONEAT_STOREKIT_INTEGRATION"] == "1"))
@MainActor
struct LifetimeOfferStoreKitTests {
    private struct SessionBox: @unchecked Sendable { let value: SKTestSession }

    @Test(.timeLimit(.minutes(1))) func discountedSKUGrantsTheSameRestorableLifetimeEntitlement() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let session = try await Task.detached {
            SessionBox(value: try SKTestSession(contentsOf: root.appendingPathComponent("DoneAt.storekit")))
        }.value.value
        session.disableDialogs = true
        session.clearTransactions()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }
        let suite = "LifetimeOfferStoreKitTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let plus = PlusEntitlement(defaults: defaults)
        await plus.checkCurrentEntitlements()
        await plus.loadProducts()
        let product = try #require(plus.discountedLifetimeProduct())
        #expect(product.id == PlusProductID.lifetimeOffer)
        plus.inviteLifetimeOffer(from: .update321)
        plus.claimLifetimeOffer()
        #expect(plus.lifetimeOffer?.isActive(at: .now) == true)
        await plus.purchaseLifetimeOffer()
        #expect(plus.isLifetime)
        let restored = PlusEntitlement(defaults: UserDefaults(suiteName: suite)!)
        await restored.refreshFromStore()
        #expect(restored.isLifetime)
        #expect(!restored.canOfferLifetime)
    }
}
