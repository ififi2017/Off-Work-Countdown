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
import kotlinx.coroutines.SupervisorJob
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
    private val key = BuildConfig.PLAY_BILLING_PUBLIC_KEY
    private val configured = subscription.isNotBlank() && lifetime.isNotBlank() && key.isNotBlank() &&
        monthly.isNotBlank() && yearly.isNotBlank() && subscription != lifetime && monthly != yearly
    private val allowed = setOf(subscription, lifetime)
    private val store = AtomicFile(File(context.noBackupFilesDir, "plus-purchases.json"))
    private val purchasing = AtomicBoolean(false)
    private val _state = MutableStateFlow(PlusStoreState(if (configured) PlusStatus.LOADING else PlusStatus.UNCONFIGURED))
    val state: StateFlow<PlusStoreState> = _state.asStateFlow()
    private var verifiedAtMs = 0L
    private var hasPurchasedBefore = false
    private var proofs = listOf<Proof>()
    private var details = listOf<ProductDetails>()
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
            publish(offline = true)
        }
    }

    suspend fun refresh(): Boolean = try { billingMutex.withLock {
        loadCache() // A WorkManager instance may have updated the same no-backup proof file.
        val billing = client ?: return@withLock false
        _state.value = _state.value.copy(busy = true)
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
        publish(offline = false)
        val acknowledged = acknowledge(billing, now)
        queryDetails(billing)
        acknowledged && saved
    } } catch (error: CancellationException) { throw error } catch (error: Exception) {
        publish(offline = true)
        scheduleRetry()
        false
    }

    suspend fun purchase(activity: Activity, plan: PlusPlan) {
        if (!purchasing.compareAndSet(false, true)) return
        try { billingMutex.withLock { performPurchase(activity, plan) } }
        catch (error: CancellationException) { purchasing.set(false); throw error }
        catch (error: Exception) {
            purchasing.set(false)
            _state.value = _state.value.copy(operationFailed = true, busy = false)
        }
    }

    private suspend fun performPurchase(activity: Activity, plan: PlusPlan) {
        _state.value = _state.value.copy(busy = true)
        var launched = false
        try {
            val billing = client ?: return
            if (!connect(billing)) { publish(offline = true); return }
            // ProductDetails are short-lived: always refresh before launching Play.
            queryDetails(billing)
            val product = details.firstOrNull { it.productId == if (plan == PlusPlan.LIFETIME) lifetime else subscription } ?: return
            val offerToken = if (plan == PlusPlan.LIFETIME) product.oneTimePurchaseOfferDetailsList?.firstOrNull()?.offerToken
                else product.subscriptionOfferDetails?.firstOrNull { offer ->
                    offer.basePlanId == (if (plan == PlusPlan.MONTHLY) monthly else yearly) && offer.offerId == null
                }?.offerToken
            if (offerToken.isNullOrBlank()) return
            val params = BillingFlowParams.ProductDetailsParams.newBuilder()
                .setProductDetails(product).setOfferToken(offerToken).build()
            val result = billing.launchBillingFlow(activity, BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(listOf(params)).build())
            launched = result.responseCode == BillingClient.BillingResponseCode.OK
            if (!launched) _state.value = _state.value.copy(operationFailed = true, busy = false)
        } finally {
            // A successful launch holds the flight until Play's callback returns.
            if (!launched) {
                purchasing.set(false)
                _state.value = _state.value.copy(busy = false, operationFailed = true)
            }
        }
    }

    private fun publish(offline: Boolean) {
        val now = System.currentTimeMillis()
        val verified = proofs.mapNotNull { proof ->
            if (!PlaySignature.verify(proof.json, proof.signature, key, context.packageName, allowed)) return@mapNotNull null
            val purchase = proof.purchase ?: runCatching { Purchase(proof.json, proof.signature) }.getOrNull() ?: return@mapNotNull null
            if (purchase.purchaseToken != proof.token) return@mapNotNull null
            VerifiedPurchase(purchase.products.singleOrNull() ?: return@mapNotNull null, proof.token,
                purchase.products.single() == subscription, purchase.purchaseState == Purchase.PurchaseState.PURCHASED,
                purchase.purchaseState == Purchase.PurchaseState.PENDING, purchase.isSuspended,
                purchase.isAcknowledged, proof.firstSeenAtMs)
        }
        _state.value = _state.value.copy(status = EntitlementEngine.status(verified, now, verifiedAtMs, offline),
            busy = false, hasPurchasedBefore = hasPurchasedBefore)
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
        val offers = details.flatMap { product ->
            if (product.productId == lifetime) product.oneTimePurchaseOfferDetailsList.orEmpty().take(1).map {
                PlusOffer(PlusPlan.LIFETIME, it.formattedPrice, product.description)
            } else product.subscriptionOfferDetails.orEmpty().filter { it.offerId == null }.mapNotNull { offer ->
                val plan = when (offer.basePlanId) { monthly -> PlusPlan.MONTHLY; yearly -> PlusPlan.YEARLY; else -> null }
                val price = offer.pricingPhases.pricingPhaseList.lastOrNull()?.formattedPrice
                if (plan == null || price == null) null else PlusOffer(plan, price, product.description)
            }
        }
        _state.value = _state.value.copy(offers = offers.distinctBy { it.plan })
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

    fun close() { client?.endConnection() }
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
