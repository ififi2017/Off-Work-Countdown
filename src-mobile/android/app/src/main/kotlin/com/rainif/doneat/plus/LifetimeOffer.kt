package com.rainif.doneat.plus

/** One local invitation. Showing its price starts one deadline that reopening never renews. */
enum class LifetimeOfferSource { ONBOARDING, UPDATE_321, UPDATE_323 }

data class LifetimeOffer(
    val source: LifetimeOfferSource,
    val latestObservedAtMs: Long,
    val claimedAtMs: Long? = null,
) {
    val durationMs: Long get() = if (source == LifetimeOfferSource.UPDATE_323) UPDATE_DURATION_MS else DURATION_MS
    val expiresAtMs: Long? get() = claimedAtMs?.let { it + durationMs }
    fun effectiveNow(nowMs: Long): Long = maxOf(nowMs, latestObservedAtMs)
    fun isActive(nowMs: Long): Boolean = claimedAtMs?.let { claimed ->
        effectiveNow(nowMs) >= claimed && effectiveNow(nowMs) < claimed + durationMs
    } ?: false
    fun remainingMs(nowMs: Long): Long = expiresAtMs?.let { (it - effectiveNow(nowMs)).coerceAtLeast(0) } ?: 0
    fun claim(nowMs: Long): LifetimeOffer = if (claimedAtMs != null) observe(nowMs)
        else copy(claimedAtMs = effectiveNow(nowMs), latestObservedAtMs = effectiveNow(nowMs))
    fun observe(nowMs: Long): LifetimeOffer = copy(latestObservedAtMs = effectiveNow(nowMs))
    internal fun hasValidTimestamps(): Boolean = latestObservedAtMs >= 0 &&
        (claimedAtMs == null || (claimedAtMs in 0..latestObservedAtMs && claimedAtMs <= Long.MAX_VALUE - durationMs))

    companion object {
        const val DURATION_MS = 24L * 60 * 60 * 1_000
        const val UPDATE_DURATION_MS = 7 * DURATION_MS

        /** A running legacy invitation keeps its deadline; the update gift is never renewed. */
        fun updateGift(previous: LifetimeOffer?, nowMs: Long): LifetimeOffer {
            if (previous != null && (previous.source == LifetimeOfferSource.UPDATE_323 || previous.isActive(nowMs))) return previous
            return LifetimeOffer(LifetimeOfferSource.UPDATE_323, maxOf(nowMs, previous?.latestObservedAtMs ?: nowMs))
        }
    }
}

/** Unavailable/offline evidence cannot advertise or consume the single invitation. */
internal object LifetimeOfferPolicy {
    fun canInvite(store: PlusStoreState): Boolean =
        store.status == PlusStatus.FREE && store.currentEntitlementsVerified && !store.hasActiveSubscription

    fun canOffer(store: PlusStoreState, nowMs: Long): Boolean {
        val price = store.discountedLifetimeOffer ?: return false
        return canInvite(store) && !store.busy && !store.operationFailed &&
            price.plan == PlusPlan.LIFETIME && !price.offerId.isNullOrBlank() &&
            price.offerToken.isNotBlank() && price.price.isNotBlank() && !price.purchaseOptionId.isNullOrBlank() &&
            !price.regularPrice.isNullOrBlank() && price.currency.isNotBlank() &&
            validPrice(price.regularPriceMicros ?: 0, price.priceMicros, true) && price.isPlayOfferActive(nowMs)
    }

    fun validPrice(regularMicros: Long, discountedMicros: Long, sameCurrency: Boolean): Boolean =
        sameCurrency && regularMicros > 0 && discountedMicros > 0 && discountedMicros < regularMicros

    /** Rechecked inside the purchase flight, after refreshing Play's eligibility and prices. */
    fun canPurchase(store: PlusStoreState, invitation: LifetimeOffer?, displayed: PlusOffer, nowMs: Long): Boolean =
        canOffer(store.copy(busy = false), nowMs) && invitation?.isActive(nowMs) == true &&
            store.discountedLifetimeOffer == displayed
}
