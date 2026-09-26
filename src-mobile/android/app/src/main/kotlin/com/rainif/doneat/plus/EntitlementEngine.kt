package com.rainif.doneat.plus

/** Purchase proofs are accepted only after Play's signature has been checked. */
internal data class VerifiedPurchase(
    val productId: String,
    val token: String,
    val isSubscription: Boolean,
    val purchased: Boolean,
    val pending: Boolean,
    val suspended: Boolean,
    val acknowledged: Boolean,
    val firstPurchasedSeenAtMs: Long,
)

enum class PlusStatus { UNCONFIGURED, LOADING, FREE, SUBSCRIBED, LIFETIME, PENDING, OFFLINE, ERROR }

internal object EntitlementEngine {
    const val ACK_WINDOW_MS = 3L * 24 * 60 * 60 * 1000
    // Play does not expose a subscription expiry in Purchase. An offline subscription
    // proof is bounded so a revoked subscription cannot authorize indefinitely.
    const val OFFLINE_SUBSCRIPTION_MS = 24L * 60 * 60 * 1000

    fun status(
        purchases: List<VerifiedPurchase>,
        nowMs: Long,
        verifiedAtMs: Long,
        offline: Boolean,
    ): PlusStatus {
        if (purchases.any { it.purchased && !it.isSubscription && !it.suspended }) return PlusStatus.LIFETIME
        if (purchases.any { it.purchased && it.isSubscription && !it.suspended } &&
            (!offline || nowMs - verifiedAtMs in 0..OFFLINE_SUBSCRIPTION_MS)
        ) return PlusStatus.SUBSCRIBED
        if (purchases.any { it.pending }) return PlusStatus.PENDING
        return if (offline) PlusStatus.OFFLINE else PlusStatus.FREE
    }

    fun shouldAcknowledge(purchase: VerifiedPurchase, nowMs: Long): Boolean =
        purchase.purchased && !purchase.acknowledged &&
            nowMs - purchase.firstPurchasedSeenAtMs in 0 until ACK_WINDOW_MS
}
