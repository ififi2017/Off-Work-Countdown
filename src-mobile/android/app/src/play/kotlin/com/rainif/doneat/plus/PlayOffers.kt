package com.rainif.doneat.plus

import com.android.billingclient.api.ProductDetails.RecurrenceMode

internal data class PlayPricePhase(
    val period: String,
    val price: String,
    val priceMicros: Long,
    val currency: String,
    val recurrence: Int,
    val cycles: Int,
)

internal data class PlaySubscriptionOption(
    val basePlanId: String,
    val offerId: String?,
    val token: String,
    val phases: List<PlayPricePhase>,
)

/** Only offers returned as eligible by Play are passed here; never infer eligibility from local history. */
internal fun selectSubscriptionOffer(
    plan: PlusPlan,
    basePlanId: String,
    trialOfferId: String,
    options: List<PlaySubscriptionOption>,
): PlusOffer? {
    val period = when (plan) {
        PlusPlan.MONTHLY -> "P1M"
        PlusPlan.YEARLY -> "P1Y"
        PlusPlan.LIFETIME -> return null
    }
    val valid = options.filter { option ->
        val renewal = option.phases.lastOrNull()
        option.basePlanId == basePlanId && option.token.isNotBlank() && renewal != null &&
            renewal.period == period && renewal.priceMicros > 0 && renewal.price.isNotBlank() &&
            renewal.currency.isNotBlank() && renewal.recurrence == RecurrenceMode.INFINITE_RECURRING
    }
    val trial = if (plan == PlusPlan.YEARLY && trialOfferId.isNotBlank()) valid.firstOrNull { option ->
        val first = option.phases.first()
        option.offerId == trialOfferId && option.phases.size == 2 &&
            first.period in setOf("P7D", "P1W") && first.priceMicros == 0L &&
            ((first.recurrence == RecurrenceMode.FINITE_RECURRING && first.cycles == 1) ||
                (first.recurrence == RecurrenceMode.NON_RECURRING && first.cycles == 0)) &&
            first.currency == option.phases.last().currency
    } else null
    val selected = trial ?: valid.firstOrNull { it.offerId == null && it.phases.size == 1 } ?: return null
    return PlusOffer(plan, selected.phases.last().price, selected.token, sevenDayTrial = trial != null,
        priceMicros = selected.phases.last().priceMicros, currency = selected.phases.last().currency)
}

/** Play returns only options eligible for the current user. IDs and prices never come from a mock SKU. */
internal data class PlayLifetimeOption(
    val purchaseOptionId: String?, val offerId: String?, val token: String?,
    val price: String, val priceMicros: Long, val currency: String,
    val rental: Boolean = false, val preorder: Boolean = false,
    val validFromMs: Long? = null, val validUntilMs: Long? = null,
    val fullPriceMicros: Long? = null, val remainingQuantity: Int? = null,
) {
    fun isAvailable(nowMs: Long): Boolean = !rental && !preorder && !token.isNullOrBlank() &&
        price.isNotBlank() && priceMicros > 0 && currency.isNotBlank() &&
        (remainingQuantity == null || remainingQuantity > 0) &&
        (validFromMs == null || validFromMs >= 0 && nowMs >= validFromMs) &&
        (validUntilMs == null || validUntilMs > 0 && nowMs < validUntilMs) &&
        (validFromMs == null || validUntilMs == null || validFromMs < validUntilMs)
}

internal data class PlayLifetimeSelection(val regular: PlusOffer?, val discounted: PlusOffer?)

/** Discount must pair with this registered product's same purchase option and current currency. */
internal fun selectLifetimeOffers(
    purchaseOptionId: String, options: List<PlayLifetimeOption>, nowMs: Long,
): PlayLifetimeSelection {
    if (purchaseOptionId.isBlank()) return PlayLifetimeSelection(null, null)
    val eligible = options.filter { it.purchaseOptionId == purchaseOptionId && it.isAvailable(nowMs) }
    val regular = eligible.filter { it.offerId == null }
        .minWithOrNull(compareBy<PlayLifetimeOption> { it.priceMicros }.thenBy { it.token })
        ?: return PlayLifetimeSelection(null, null)
    fun offer(option: PlayLifetimeOption, discounted: Boolean) = PlusOffer(
        PlusPlan.LIFETIME, option.price, option.token!!,
        priceMicros = option.priceMicros, currency = option.currency,
        regularPrice = regular.price.takeIf { discounted },
        regularPriceMicros = regular.priceMicros.takeIf { discounted },
        purchaseOptionId = option.purchaseOptionId, offerId = option.offerId,
        validFromMs = option.validFromMs, validUntilMs = option.validUntilMs,
    )
    val discounted = eligible.filter {
        !it.offerId.isNullOrBlank() &&
            LifetimeOfferPolicy.validPrice(regular.priceMicros, it.priceMicros, regular.currency == it.currency) &&
            (it.fullPriceMicros == null || it.fullPriceMicros == regular.priceMicros)
    }.minWithOrNull(compareBy<PlayLifetimeOption> { it.priceMicros }.thenBy { it.offerId }.thenBy { it.token })
    return PlayLifetimeSelection(offer(regular, false), discounted?.let { offer(it, true) })
}
