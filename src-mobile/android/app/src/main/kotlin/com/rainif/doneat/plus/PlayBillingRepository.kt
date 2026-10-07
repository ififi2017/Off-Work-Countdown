package com.rainif.doneat.plus

import android.app.Activity
import android.content.Context
import android.util.AtomicFile
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.Purchase
import com.rainif.doneat.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume

/** Play data is the only entitlement input. The signed offline cache lives under noBackup. */
internal class PlayBillingRepository(private val context: Context, private val scope: CoroutineScope) {
    private companion object { val billingMutex = Mutex() }
    private val subscription = BuildConfig.PLUS_SUBSCRIPTION_PRODUCT
    private val lifetime = BuildConfig.PLUS_LIFETIME_PRODUCT
    private val monthly = BuildConfig.PLUS_MONTHLY_BASE_PLAN
    private val yearly = BuildConfig.PLUS_YEARLY_BASE_PLAN
    private val yearlyTrial = BuildConfig.PLUS_YEARLY_TRIAL_OFFER
    private val lifetimeOption = BuildConfig.PLUS_LIFETIME_PURCHASE_OPTION
    private val key = BuildConfig.PLAY_BILLING_PUBLIC_KEY
    private val configured = subscription.isNotBlank() && lifetime.isNotBlank() && key.isNotBlank() &&
        monthly.isNotBlank() && yearly.isNotBlank() && lifetimeOption.isNotBlank() &&
        subscription != lifetime && monthly != yearly
    private val allowed = setOf(subscription, lifetime)
    private val store = AtomicFile(File(context.noBackupFilesDir, "plus-purchases.json"))
    private val server = BillingServerClient(context, runCatching {
        kotlinx.serialization.json.Json.parseToJsonElement(BuildConfig.BILLING_API_PUBLIC_KEYS)
            .let { it as kotlinx.serialization.json.JsonObject }
            .mapValues { (_, value) -> (value as kotlinx.serialization.json.JsonPrimitive).content }
    }.getOrDefault(emptyMap()))
    private val serverRequired = BuildConfig.BILLING_API_PUBLIC_KEYS.isNotBlank()
    private val purchasing = AtomicBoolean(false)
    private val _state = MutableStateFlow(PlusStoreState(if (configured) PlusStatus.LOADING else PlusStatus.UNCONFIGURED))
    val state: StateFlow<PlusStoreState> = _state.asStateFlow()
    private var verifiedAtMs = 0L
    private var hasPurchasedBefore = false
    private var proofs = listOf<Proof>()
    private var details = listOf<ProductDetails>()
    private var expiryCheck: Job? = null
    private val client: BillingClient? = if (!configured) null else BillingClient.newBuilder(context)
        .setListener { result, _ ->
            purchasing.set(false)
            if (result.responseCode == BillingClient.BillingResponseCode.OK) scope.launch { refresh() }
            else _state.value = _state.value.copy(
                operationFailed = result.responseCode != BillingClient.BillingResponseCode.USER_CANCELED,
                busy = false,
            )
        }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    init {
        if (configured) {
            loadCache()
            server.load()
            publish(offline = true)
        }
    }

    suspend fun refresh(): Boolean = try { billingMutex.withLock {
        loadCache() // A WorkManager instance may have updated the same no-backup proof file.
        server.load()
        val billing = client ?: return@withLock false
        _state.value = _state.value.copy(busy = true, currentEntitlementsVerified = false, discountedLifetimeOffer = null)
        if (!connect(billing)) {
            publish(offline = true)
            scheduleRetry()
            return@withLock false
        }
        val subs = queryPurchases(billing, BillingClient.ProductType.SUBS)
        val oneTime = queryPurchases(billing, BillingClient.ProductType.INAPP)
        if (subs == null || oneTime == null) {
            publish(offline = true)
            scheduleRetry()
            return@withLock false
        }
        val now = System.currentTimeMillis()
        val oldSeen = proofs.associate { it.token to it.firstSeenAtMs }
        val incoming = (subs + oneTime).mapNotNull { purchase ->
            if (!PlaySignature.verify(purchase.originalJson, purchase.signature, key, context.packageName, allowed) ||
                purchase.products.size != 1 || purchase.products.single() !in allowed) return@mapNotNull null
            Proof(purchase.originalJson, purchase.signature, purchase.purchaseToken,
                if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED)
                    oldSeen[purchase.purchaseToken]?.takeIf { it > 0 } ?: now else 0L,
                purchase)
        }
        // A signature failure must not turn a prior verified grant into a confirmed revocation.
        if (incoming.size != subs.size + oneTime.size) {
            publish(offline = true)
            return@withLock false
        }
        proofs = incoming
        if (incoming.any { it.purchase?.purchaseState == Purchase.PurchaseState.PURCHASED }) hasPurchasedBefore = true
        verifiedAtMs = now
        val saved = runCatching { saveCache() }.isSuccess
        if (!saved) scheduleRetry()
        _state.value = _state.value.copy(operationFailed = false)
        val acknowledged = acknowledge(billing, now)
        // Acknowledgement remains on Play's existing retry path even if the verification service is unavailable.
        val serverVerified = if (serverRequired) server.configured && server.refresh(verifiedPurchases(), now) else true
        if (!serverVerified) scheduleRetry()
        _state.value = _state.value.copy(operationFailed = !serverVerified)
        publish(offline = false)
        queryDetails(billing)
        acknowledged && saved && serverVerified
    } } catch (error: CancellationException) { throw error } catch (error: Exception) {
        publish(offline = true)
        scheduleRetry()
        false
    }

    suspend fun purchase(activity: Activity, offer: PlusOffer, lifetimeOfferActive: (() -> Boolean)? = null) {
        if (!purchasing.compareAndSet(false, true)) return
        try {
            // A lifetime invitation requires a current entitlement query too, never just a cached free state.
            if (lifetimeOfferActive != null && !refresh()) {
                purchasing.set(false)
                return
            }
            billingMutex.withLock { performPurchase(activity, offer, lifetimeOfferActive) }
        }
        catch (error: CancellationException) { purchasing.set(false); throw error }
        catch (error: Exception) {
            purchasing.set(false)
            _state.value = _state.value.copy(operationFailed = true, busy = false)
        }
    }

    private suspend fun performPurchase(activity: Activity, offer: PlusOffer, lifetimeOfferActive: (() -> Boolean)?) {
        _state.value = _state.value.copy(busy = true)
        var launched = false
        var termsChanged = false
        try {
            val billing = client ?: return
            if (!connect(billing)) { publish(offline = true); return }
            // ProductDetails are short-lived: always refresh before launching Play.
            queryDetails(billing)
            // A trial or price change requires another tap on the newly displayed terms.
            if (lifetimeOfferActive == null) {
                // Discount tokens are reachable only through the explicit invitation purchase path.
                if (offer.offerId != null || _state.value.offers.none { it == offer }) { termsChanged = true; return }
            } else if (_state.value.discountedLifetimeOffer != offer ||
                _state.value.status != PlusStatus.FREE || !_state.value.currentEntitlementsVerified ||
                _state.value.hasActiveSubscription || _state.value.operationFailed || !lifetimeOfferActive()
            ) { termsChanged = true; return }
            if (!offer.isPlayOfferActive(System.currentTimeMillis())) { termsChanged = true; return }
            val plan = offer.plan
            val product = details.firstOrNull { it.productId == if (plan == PlusPlan.LIFETIME) lifetime else subscription } ?: return
            val params = BillingFlowParams.ProductDetailsParams.newBuilder()
                .setProductDetails(product).setOfferToken(offer.offerToken).build()
            val result = billing.launchBillingFlow(activity, BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(listOf(params)).build())
            launched = result.responseCode == BillingClient.BillingResponseCode.OK
            if (!launched) _state.value = _state.value.copy(operationFailed = true, busy = false)
        } finally {
            // A successful launch holds the flight until Play's callback returns.
            if (!launched) {
                purchasing.set(false)
                _state.value = _state.value.copy(busy = false, operationFailed = !termsChanged)
            }
        }
    }

    private fun verifiedPurchases(): List<VerifiedPurchase> = proofs.mapNotNull { proof ->
            if (!PlaySignature.verify(proof.json, proof.signature, key, context.packageName, allowed)) return@mapNotNull null
            val purchase = proof.purchase ?: runCatching { Purchase(proof.json, proof.signature) }.getOrNull() ?: return@mapNotNull null
            if (purchase.purchaseToken != proof.token) return@mapNotNull null
            VerifiedPurchase(purchase.products.singleOrNull() ?: return@mapNotNull null, proof.token,
                purchase.products.single() == subscription, purchase.purchaseState == Purchase.PurchaseState.PURCHASED,
                purchase.purchaseState == Purchase.PurchaseState.PENDING, purchase.isSuspended,
                purchase.isAcknowledged, proof.firstSeenAtMs)
        }

    private fun publish(offline: Boolean) {
        val now = System.currentTimeMillis()
        val verified = verifiedPurchases()
        val receipts = if (serverRequired) server.receipts(verified, now) else emptyMap()
        val status = if (serverRequired) ServerEntitlementPolicy.status(verified, receipts, now, offline)
            else EntitlementEngine.status(verified, now, verifiedAtMs, offline)
        val activeSub = if (serverRequired) ServerEntitlementPolicy.status(verified.filter { it.isSubscription }, receipts, now, offline) == PlusStatus.SUBSCRIBED
            else EntitlementEngine.hasActiveSubscription(verified, now, verifiedAtMs, offline)
        val expiry = verified.filter { it.isSubscription && it.purchased && !it.suspended }
            .mapNotNull { receipts[it.token]?.takeIf { receipt -> receipt.activeAt(now) }?.expiresAtMs }.maxOrNull()
        _state.value = _state.value.copy(status = status,
            busy = false, hasPurchasedBefore = hasPurchasedBefore,
            hasActiveSubscription = activeSub, verifiedSubscriptionExpiresAtMs = expiry,
            currentEntitlementsVerified = !offline && !_state.value.operationFailed)
        // An app kept in the foreground must also stop granting when its signed evidence expires.
        // This is a single in-memory deadline, with no network polling or system alarm.
        expiryCheck?.cancel()
        val deadline = receipts.values.filter { it.activeAt(now) }.minOfOrNull { it.cacheUntilMs }
        expiryCheck = deadline?.let { end -> scope.launch {
            delay((end - now).coerceAtLeast(1))
            billingMutex.withLock { publish(offline = true) }
        } }
    }

    private suspend fun connect(billing: BillingClient): Boolean {
        if (billing.isReady) return true
        return suspendCancellableCoroutine { continuation ->
            billing.startConnection(object : BillingClientStateListener {
                override fun onBillingServiceDisconnected() { /* next call reconnects */ }
                override fun onBillingSetupFinished(result: BillingResult) {
                    if (continuation.isActive) continuation.resume(result.responseCode == BillingClient.BillingResponseCode.OK)
                }
            })
        }
    }

    private suspend fun queryPurchases(billing: BillingClient, type: String): List<Purchase>? =
        suspendCancellableCoroutine { continuation ->
            billing.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(type).build()) { result, purchases ->
                if (continuation.isActive) continuation.resume(if (result.responseCode == BillingClient.BillingResponseCode.OK) purchases else null)
            }
        }

    private suspend fun queryDetails(billing: BillingClient) {
        val requests = listOf(subscription to BillingClient.ProductType.SUBS, lifetime to BillingClient.ProductType.INAPP)
            .map { (id, type) -> QueryProductDetailsParams.Product.newBuilder().setProductId(id).setProductType(type).build() }
        // Query each type separately; Play can resolve one type even when the other is unavailable.
        details = requests.flatMap { product ->
            suspendCancellableCoroutine<List<ProductDetails>> { continuation ->
                billing.queryProductDetailsAsync(QueryProductDetailsParams.newBuilder().setProductList(listOf(product)).build()) { result, fetched ->
                    if (continuation.isActive) continuation.resume(
                        if (result.responseCode == BillingClient.BillingResponseCode.OK) fetched.productDetailsList else emptyList(),
                    )
                }
            }
        }
        var discountedLifetime: PlusOffer? = null
        val now = System.currentTimeMillis()
        val offers = details.flatMap { product ->
            if (product.productId == lifetime) {
                val selection = selectLifetimeOffers(lifetimeOption, product.oneTimePurchaseOfferDetailsList.orEmpty().map {
                    PlayLifetimeOption(it.purchaseOptionId, it.offerId, it.offerToken, it.formattedPrice,
                        it.priceAmountMicros, it.priceCurrencyCode, rental = it.rentalDetails != null,
                        preorder = it.preorderDetails != null, validFromMs = it.validTimeWindow?.startTimeMillis,
                        validUntilMs = it.validTimeWindow?.endTimeMillis, fullPriceMicros = it.fullPriceMicros,
                        remainingQuantity = it.limitedQuantityInfo?.remainingQuantity)
                }, now)
                discountedLifetime = selection.discounted
                listOfNotNull(selection.regular)
            } else {
                val options = product.subscriptionOfferDetails.orEmpty().map { option ->
                    PlaySubscriptionOption(option.basePlanId, option.offerId, option.offerToken,
                        option.pricingPhases.pricingPhaseList.map { phase ->
                            PlayPricePhase(phase.billingPeriod, phase.formattedPrice, phase.priceAmountMicros,
                                phase.priceCurrencyCode, phase.recurrenceMode, phase.billingCycleCount)
                        })
                }
                listOfNotNull(
                    selectSubscriptionOffer(PlusPlan.MONTHLY, monthly, yearlyTrial, options),
                    selectSubscriptionOffer(PlusPlan.YEARLY, yearly, yearlyTrial, options),
                )
            }
        }
        _state.value = _state.value.copy(offers = offers.distinctBy { it.plan }, discountedLifetimeOffer = discountedLifetime)
    }

    private suspend fun acknowledge(billing: BillingClient, now: Long): Boolean {
        var retry = false
        for (proof in proofs) {
            val purchase = proof.purchase ?: continue
            val evidence = VerifiedPurchase(purchase.products.singleOrNull() ?: continue, proof.token,
                purchase.products.single() == subscription, purchase.purchaseState == Purchase.PurchaseState.PURCHASED,
                purchase.purchaseState == Purchase.PurchaseState.PENDING, purchase.isSuspended,
                purchase.isAcknowledged, proof.firstSeenAtMs)
            if (!EntitlementEngine.shouldAcknowledge(evidence, now)) continue
            val ok = suspendCancellableCoroutine<Boolean> { continuation ->
                billing.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(proof.token).build()) { result ->
                    if (continuation.isActive) continuation.resume(result.responseCode == BillingClient.BillingResponseCode.OK)
                }
            }
            if (!ok) retry = true
        }
        if (retry) scheduleRetry()
        return !retry
    }

    private fun scheduleRetry() {
        if (!configured) return
        val work = OneTimeWorkRequestBuilder<PlusBillingRetryWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES).build()
        WorkManager.getInstance(context).enqueueUniqueWork("plus-billing-retry", ExistingWorkPolicy.KEEP, work)
    }

    private fun loadCache() {
        runCatching {
            val data = JSONObject(store.openRead().bufferedReader().use { it.readText() })
            verifiedAtMs = data.optLong("verifiedAtMs")
            hasPurchasedBefore = data.optBoolean("hasPurchasedBefore")
            val list = data.getJSONArray("proofs")
            proofs = (0 until list.length()).map { index ->
                val item = list.getJSONObject(index)
                Proof(item.getString("json"), item.getString("signature"), item.getString("token"), item.getLong("firstSeenAtMs"), null)
            }
        }
    }

    private fun saveCache() {
        val data = JSONObject().put("verifiedAtMs", verifiedAtMs).put("hasPurchasedBefore", hasPurchasedBefore)
            .put("proofs", JSONArray().also { list ->
            proofs.forEach { proof -> list.put(JSONObject().put("json", proof.json).put("signature", proof.signature)
                .put("token", proof.token).put("firstSeenAtMs", proof.firstSeenAtMs)) }
        }).toString().toByteArray()
        val stream = store.startWrite()
        try { stream.write(data); store.finishWrite(stream) } catch (error: Exception) { store.failWrite(stream); throw error }
    }

    private data class Proof(val json: String, val signature: String, val token: String, val firstSeenAtMs: Long, val purchase: Purchase?)

    fun close() { expiryCheck?.cancel(); client?.endConnection() }
}

class PlusBillingRetryWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val repository = PlayBillingRepository(applicationContext, scope)
        return try {
            if (repository.refresh()) Result.success() else Result.retry()
        } finally {
            repository.close()
            scope.cancel()
        }
    }
}
