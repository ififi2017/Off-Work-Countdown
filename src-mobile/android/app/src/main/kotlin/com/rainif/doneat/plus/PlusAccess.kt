package com.rainif.doneat.plus

import android.app.Activity
import android.content.Context
import com.rainif.doneat.BuildConfig
import com.rainif.doneat.core.domain.alarms.ShiftAlarmAuthorization
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class PlusPlan { MONTHLY, YEARLY, LIFETIME }
data class PlusOffer(
    val plan: PlusPlan, val price: String, val offerToken: String, val sevenDayTrial: Boolean = false,
    val priceMicros: Long = 0, val currency: String = "",
    val regularPrice: String? = null, val regularPriceMicros: Long? = null,
    val purchaseOptionId: String? = null, val offerId: String? = null,
    val validFromMs: Long? = null, val validUntilMs: Long? = null,
) {
    fun isPlayOfferActive(nowMs: Long): Boolean =
        (validFromMs == null || nowMs >= validFromMs) && (validUntilMs == null || nowMs < validUntilMs)
}
data class PlusStoreState(val status: PlusStatus = PlusStatus.LOADING, val offers: List<PlusOffer> = emptyList(),
    val busy: Boolean = false, val hasPurchasedBefore: Boolean = false, val operationFailed: Boolean = false,
    val hasActiveSubscription: Boolean = status == PlusStatus.SUBSCRIBED,
    val verifiedSubscriptionExpiresAtMs: Long? = null,
    val discountedLifetimeOffer: PlusOffer? = null,
    val currentEntitlementsVerified: Boolean = false) {
    val authorized: Boolean get() = status == PlusStatus.SUBSCRIBED || status == PlusStatus.LIFETIME

    /** Callers pass now explicitly. A client cache age must never stand in for Google's expiry. */
    fun shiftAlarmAuthorization(nowMs: Long): ShiftAlarmAuthorization = when {
        status == PlusStatus.LIFETIME -> ShiftAlarmAuthorization.Lifetime
        status == PlusStatus.SUBSCRIBED && (verifiedSubscriptionExpiresAtMs ?: 0) > nowMs ->
            ShiftAlarmAuthorization.VerifiedUntil(verifiedSubscriptionExpiresAtMs!!)
        else -> ShiftAlarmAuthorization.Unavailable
    }
}

/** The sole purchase gate shared by every paid screen. */
class PlusAccess(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val repository = PlayBillingRepository(context.applicationContext, scope)
    private val offerStore = LifetimeOfferStore(context.applicationContext)
    private val _lifetimeOffer = MutableStateFlow(offerStore.load())
    val lifetimeOffer: StateFlow<LifetimeOffer?> = _lifetimeOffer.asStateFlow()
    private var offerExpiry: Job? = null
    private var lastOfferPersistedAtMs = _lifetimeOffer.value?.latestObservedAtMs ?: 0L
    val state: StateFlow<PlusStoreState> = repository.state
    private val _authorized = MutableStateFlow(repository.state.value.authorized || PlusDebugOverride.read(context))
    val authorized: StateFlow<Boolean> = _authorized.asStateFlow()
    private val _collectsObservations = MutableStateFlow(_authorized.value || !repository.state.value.hasPurchasedBefore)
    /** Mirrors iOS until D-07 changes: free users collect, lapsed buyers pause. */
    val collectsObservations: StateFlow<Boolean> = _collectsObservations.asStateFlow()

    val canInviteLifetime: Boolean get() = offerStore.isUsable && !_authorized.value &&
        LifetimeOfferPolicy.canInvite(state.value)
    val canOfferLifetime: Boolean get() = offerStore.isUsable && !_authorized.value &&
        LifetimeOfferPolicy.canOffer(state.value, effectiveOfferNow())
    val hasAvailableLifetimeOffer: Boolean get() = canOfferLifetime &&
        _lifetimeOffer.value?.let { it.claimedAtMs == null || it.isActive(effectiveOfferNow()) } == true

    init {
        observeLifetimeOffer()
        scheduleOfferExpiry()
        scope.launch { repository.state.collect {
            val granted = it.authorized || PlusDebugOverride.read(context)
            _authorized.value = granted
            _collectsObservations.value = granted || !it.hasPurchasedBefore
        } }
        if (BuildConfig.PLAY_BILLING_PUBLIC_KEY.isNotBlank()) scope.launch { repository.refresh() }
    }

    fun refresh() { scope.launch { repository.refresh() } }
    fun restore() { scope.launch { repository.refresh() } }
    fun purchase(activity: Activity, offer: PlusOffer) { scope.launch { repository.purchase(activity, offer) } }

    /** What's New may offer an unopened gift without consuming its 24-hour window. */
    fun inviteLifetimeOffer(source: LifetimeOfferSource, nowMs: Long = System.currentTimeMillis()) {
        if (_lifetimeOffer.value != null || !canInviteLifetime) return
        updateLifetimeOffer(LifetimeOffer(source, nowMs))
    }

    fun claimLifetimeOffer(nowMs: Long = System.currentTimeMillis()) {
        if (!canOfferLifetime) return
        _lifetimeOffer.value?.let { updateLifetimeOffer(it.claim(nowMs)) }
    }

    /** Showing a priced invitation, rather than merely its unopened gift, starts the deadline. */
    fun revealLifetimeOffer(source: LifetimeOfferSource, nowMs: Long = System.currentTimeMillis()): Boolean {
        if (!canOfferLifetime) return false
        inviteLifetimeOffer(source, nowMs)
        claimLifetimeOffer(nowMs)
        return _lifetimeOffer.value?.isActive(nowMs) == true
    }

    /** Ticks retain the maximum in memory; lifecycle edges and expiry persist it immediately. */
    fun observeLifetimeOffer(nowMs: Long = System.currentTimeMillis(), persist: Boolean = true) {
        val previous = _lifetimeOffer.value ?: return
        val next = previous.observe(nowMs)
        val shouldPersist = persist || next.latestObservedAtMs - lastOfferPersistedAtMs >= OFFER_OBSERVATION_SAVE_MS ||
            (previous.remainingMs(previous.latestObservedAtMs) > 0 && next.remainingMs(nowMs) == 0L)
        if (next == previous && !shouldPersist) return
        if (shouldPersist) updateLifetimeOffer(next) else _lifetimeOffer.value = next
    }

    /** Explicit purchase only: fresh Play evidence and the very same terms are checked before launch. */
    fun purchaseLifetimeOffer(activity: Activity, displayed: PlusOffer) {
        observeLifetimeOffer()
        if (!hasAvailableLifetimeOffer || _lifetimeOffer.value?.isActive(effectiveOfferNow()) != true ||
            state.value.discountedLifetimeOffer != displayed) return
        scope.launch {
            repository.purchase(activity, displayed) {
                observeLifetimeOffer()
                // Repository holds its purchase flight busy while doing this final eligibility check.
                offerStore.isUsable && !_authorized.value &&
                    LifetimeOfferPolicy.canPurchase(state.value, _lifetimeOffer.value, displayed, effectiveOfferNow())
            }
        }
    }

    private fun effectiveOfferNow(): Long = maxOf(System.currentTimeMillis(), _lifetimeOffer.value?.latestObservedAtMs ?: 0)

    private fun updateLifetimeOffer(next: LifetimeOffer) {
        if (!offerStore.save(next)) { _lifetimeOffer.value = null; return }
        val deadlineChanged = next.expiresAtMs != _lifetimeOffer.value?.expiresAtMs
        _lifetimeOffer.value = next
        lastOfferPersistedAtMs = next.latestObservedAtMs
        if (deadlineChanged || !next.isActive(effectiveOfferNow())) scheduleOfferExpiry()
    }

    private fun scheduleOfferExpiry() {
        offerExpiry?.cancel()
        val offer = _lifetimeOffer.value ?: return
        if (offer.claimedAtMs == null || !offer.isActive(effectiveOfferNow())) return
        offerExpiry = scope.launch {
            delay(offer.remainingMs(effectiveOfferNow()).coerceAtLeast(1))
            observeLifetimeOffer()
        }
    }
    fun setDebugAuthorized(value: Boolean) {
        if (!PlusDebugOverride.AVAILABLE) return
        PlusDebugOverride.write(context, value)
        _authorized.value = value || state.value.authorized
        _collectsObservations.value = _authorized.value || !state.value.hasPurchasedBefore
    }

    private companion object { const val OFFER_OBSERVATION_SAVE_MS = 60_000L }
}
