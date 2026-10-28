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
    return PlusOffer(plan, selected.phases.last().price, selected.token, sevenDayTrial = trial != null)
}
