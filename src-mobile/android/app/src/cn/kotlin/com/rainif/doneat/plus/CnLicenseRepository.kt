package com.rainif.doneat.plus

import android.app.Activity
import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import com.rainif.doneat.BuildConfig
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.net.HttpURLConnection
import java.net.URI

internal data class CnMembershipState(
    val busy: Boolean = false, val configured: Boolean = false, val receipt: CnReceipt? = null,
    val confirmation: JsonObject? = null, val pending: Boolean = false, val error: String? = null,
    val trialDaysRemaining: Int? = null,
)
private class CnApiFailure(val code: String) : Exception()

internal class CnLicenseRepository(private val context: Context, scope: CoroutineScope) : ChannelPlusRepository {
    private val mutex = Mutex()
    private val keys = runCatching { Json.parseToJsonElement(BuildConfig.CN_LICENSE_PUBLIC_KEYS).jsonObject.mapValues { it.value.jsonPrimitive.content } }.getOrDefault(emptyMap())
    private val cacheTrust = runCatching {
        CnLicenseCache.trustFingerprint(context.packageName, BuildConfig.CN_LICENSE_AUDIENCE, keys)
    }.getOrNull()
    private val configured = cacheTrust != null
    private val identity = runCatching { CnDeviceIdentity(context) }.getOrNull()
    private val _state = MutableStateFlow(PlusStoreState(if (configured && identity != null) PlusStatus.FREE else PlusStatus.UNCONFIGURED))
    override val state: StateFlow<PlusStoreState> = _state.asStateFlow()
    private val _membership = MutableStateFlow(CnMembershipState(configured = configured && identity != null))
    val membership: StateFlow<CnMembershipState> = _membership.asStateFlow()
    private var persisted = JsonObject(emptyMap())
    @Volatile private var evidence: Pair<CnReceipt, CnLeaseAnchor>? = null
    private val receipt: CnReceipt? get() = evidence?.first
    @Volatile private var paidSeen = false
    private var networkAnchor: CnLeaseAnchor? = null
    private var pendingOperation: String? = null
    @Volatile private var pendingPayload: ByteArray? = null
    private fun boot(): Int = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
    init {
        runCatching { identity?.read()?.let { load(Json.parseToJsonElement(it).jsonObject) } }
        publish()
        scope.launch {
            while (isActive) { delay(1000); publish() }
        }
        scope.launch {
            while (isActive) { delay(600_000); if (receipt != null) refresh() }
        }
    }
    private fun load(data: JsonObject) {
        val loaded = CnLicenseCache.read(data, requireNotNull(cacheTrust)) { jwt, requestId, nonce ->
            CnReceipt.verify(jwt, keys, BuildConfig.CN_LICENSE_AUDIENCE, identity!!.deviceHash, requestId, nonce,
                allowExpiredLeaseForRecovery = true)
        }
        // Publish none of the old context if its trust or receipt verification failed.
        persisted = data
        paidSeen = loaded.paidSeen
        pendingOperation = loaded.pendingOperation
        pendingPayload = loaded.pendingPayload
        val r = loaded.receipt; val a = loaded.anchor
        if (r != null && a != null && (!paidSeen || r.source == "license")) evidence = r to a
    }
    private fun save(extra: JsonObject = JsonObject(emptyMap())) {
        persisted = buildJsonObject {
            persisted.forEach { (k, v) -> if (k !in setOf("pendingOperation", "pendingPayload", "paidSeen")) put(k, v) }
            put("paidSeen", paidSeen)
            put("trustFingerprint", requireNotNull(cacheTrust))
            pendingOperation?.let { put("pendingOperation", it) }
            pendingPayload?.let { put("pendingPayload", CnLicenseProtocol.encode(it)) }
            extra.forEach { (k, v) -> put(k, v) }
        }
        identity!!.write(persisted.toString())
    }
    private fun publish() {
        val proof = evidence; val r = proof?.first; val a = proof?.second
        val active = r != null && a != null && a.authorized(r, SystemClock.elapsedRealtime(), System.currentTimeMillis(), boot()) && (!paidSeen || r.source == "license")
        val status = when { !configured || identity == null -> PlusStatus.UNCONFIGURED; active && r.plan == "lifetime" -> PlusStatus.LIFETIME; active -> PlusStatus.SUBSCRIBED; else -> PlusStatus.FREE }
        // Alarm grants are bounded by the verified offline lease, including lifetime and trial.
        val until = if (active) a.wallMs + (r.leaseUntilMs - r.serverTimeMs) else null
        _state.value = PlusStoreState(status, busy = _membership.value.busy, hasPurchasedBefore = paidSeen,
            verifiedSubscriptionExpiresAtMs = r?.expiresAtMs, verifiedAuthorizationUntilMs = until)
        val displayElapsed = if (a != null && a.bootCount >= 0 && a.bootCount == boot()) SystemClock.elapsedRealtime() - a.elapsedMs else null
        val trialDays = if (r?.source == "trial" && r.expiresAtMs != null) cnTrialDaysRemaining(r.expiresAtMs, r.serverTimeMs, displayElapsed) else null
        _membership.update { it.copy(receipt = r, pending = pendingPayload != null, trialDaysRemaining = trialDays) }
    }
    override fun authorizedNow(): Boolean {
        val proof = evidence ?: return false
        return configured && (!paidSeen || proof.first.source == "license") &&
            proof.second.authorized(proof.first, SystemClock.elapsedRealtime(), System.currentTimeMillis(), boot())
    }
    override suspend fun purchase(activity: Activity, offer: PlusOffer, lifetimeOfferActive: (() -> Boolean)?) = Unit
    override suspend fun refresh(): Boolean { action {
        if (pendingPayload != null) { executePending(); return@action }
        val r = receipt ?: return@action
        if (!authorizedNow() && r.reason == "valid") {
            // Reboot or a clock jump needs new server proof, not a ten-minute wait for
            // a newly issued lease. A fresh-nonce query proves current remaining time.
            val previousRequest = persisted["requestId"]?.jsonPrimitive?.content
            if (previousRequest != null) try {
                val query = CnLicenseProtocol.command(buildJsonObject { put("targetRequestId", previousRequest) })
                val current = accept(network("operation", query), query, allowExpiredRecovery = true)
                refreshExpiredRecovery(current)
                return@action
            } catch (e: CnApiFailure) {
                if (e.code != "operation_not_found") throw e
                // Short-lived result cleanup cannot prevent an ordinary fresh refresh.
            }
        }
        val op = if (r.source == "trial") "trial-refresh" else "refresh"
        submit(op, buildJsonObject { put(if (r.source == "trial") "trialId" else "licenseId", r.id) })
        }; return state.value.authorized
    }
    suspend fun startTrial() = action {
        require(!paidSeen)
        submit("trial-start", buildJsonObject { put("deviceHint", deviceHint()); put("privacyVersion", "2026-10-27") })
    }
    suspend fun preview(code: String, redeem: Boolean) = action {
        require(pendingPayload == null)
        submit(if (redeem) "redeem-preview" else "preview", buildJsonObject {
            put("code", code.trim())
            if (redeem) { val r = requireNotNull(receipt); require(r.source == "license"); put("licenseId", r.id) }
            else put("deviceHint", deviceHint())
        })
    }
    suspend fun confirm() = action {
        val c = requireNotNull(_membership.value.confirmation)
        submit(if (c.getValue("action").jsonPrimitive.content in setOf("renew", "upgrade")) "redeem" else "activate", buildJsonObject {
            put("confirmationId", c.getValue("confirmationId")); put("expectedRevision", c.getValue("expectedRevision"))
        })
        _membership.update { it.copy(confirmation = null) }
    }
    fun cancelConfirmation() { _membership.update { it.copy(confirmation = null) } }
    suspend fun recoverPending() = action {
        val pending = requireNotNull(pendingPayload)
        val target = Json.parseToJsonElement(pending.decodeToString()).jsonObject.getValue("requestId")
        // Read-only operation recovery uses its own request. Preserve the exact original command until resolved.
        val payload = CnLicenseProtocol.command(buildJsonObject { put("targetRequestId", target) })
        val result = network("operation", payload)
        val recovered = if (pendingOperation in setOf("preview", "redeem-preview")) {
            _membership.update { it.copy(confirmation = requireNotNull(result["operationResult"]).jsonObject) }; null
        } else accept(result, payload, allowExpiredRecovery = true)
        pendingPayload = null; pendingOperation = null; save()
        recovered?.let(::refreshExpiredRecovery)
    }
    private fun deviceHint(): String {
        val scoped = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        require(!scoped.isNullOrBlank())
        return CnLicenseProtocol.hash(scoped.toByteArray(Charsets.UTF_8))
    }
    private suspend fun action(block: suspend () -> Unit) = mutex.withLock {
        if (!configured || identity == null) return@withLock
        _membership.update { it.copy(busy = true, error = null) }; publish()
        try { withContext(Dispatchers.IO) { block() } }
        catch (e: CancellationException) { throw e }
        catch (e: CnApiFailure) {
            if (e.code in setOf("invalid_request", "invalid_code_or_proof", "wrong_code_kind", "confirmation_expired", "revision_conflict", "request_id_conflict", "transfer_limit_reached", "transfer_cooldown", "device_already_bound", "license_revoked", "already_lifetime", "code_already_redeemed", "trial_unavailable", "rate_limited")) {
                pendingOperation = null; pendingPayload = null; runCatching { save() }
            }
            _membership.update { it.copy(
                error = if (e.code == "rate_limited" && authorizedNow()) null else e.code,
                confirmation = if (e.code in setOf("confirmation_expired", "revision_conflict")) null else it.confirmation,
            ) }
        }
        catch (_: java.io.IOException) { _membership.update { it.copy(error = "connection_unavailable") } }
        catch (_: Exception) { _membership.update { it.copy(error = "verification_unavailable") } }
        finally { _membership.update { it.copy(busy = false) }; publish() }
    }
    private fun submit(operation: String, fields: JsonObject, refreshExpiredResult: Boolean = true) {
        require(pendingPayload == null)
        pendingPayload = CnLicenseProtocol.command(fields); pendingOperation = operation
        save() // Must be durable before the first network byte, including encrypted transient codes.
        executePending(refreshExpiredResult, freshNonce = true)
    }
    private fun executePending(refreshExpiredResult: Boolean = true, freshNonce: Boolean = false) {
        val payload = requireNotNull(pendingPayload); val op = requireNotNull(pendingOperation)
        val result = network(op, payload)
        var accepted = if (op in setOf("preview", "redeem-preview")) {
            _membership.update { it.copy(confirmation = result) }; null
        } else accept(result, payload, allowExpiredRecovery = true, freshNonce = freshNonce)
        if (!freshNonce && accepted?.reason == "valid" && accepted.leaseUntilMs > accepted.serverTimeMs) {
            // A new nonce authenticates current remaining lease time without tripping the
            // ten-minute refresh throttle. Keep the original pending until this query succeeds.
            val target = Json.parseToJsonElement(payload.decodeToString()).jsonObject.getValue("requestId")
            val query = CnLicenseProtocol.command(buildJsonObject { put("targetRequestId", target) })
            accepted = accept(network("operation", query), query, allowExpiredRecovery = true)
        }
        pendingPayload = null; pendingOperation = null; save()
        if (refreshExpiredResult) accepted?.let(::refreshExpiredRecovery)
    }
    private fun refreshExpiredRecovery(result: CnReceipt) {
        if (result.reason != "valid" || result.leaseUntilMs > result.serverTimeMs) return
        // The signature established the command outcome, not a new lease. The cleared
        // pending command and signed subject survive a crash before this fresh read.
        val trial = result.source == "trial"
        submit(if (trial) "trial-refresh" else "refresh", buildJsonObject {
            put(if (trial) "trialId" else "licenseId", result.id)
        }, refreshExpiredResult = false)
    }
    private fun accept(result: JsonObject, payload: ByteArray, allowExpiredRecovery: Boolean = false, freshNonce: Boolean = true): CnReceipt {
        val jwt = requireNotNull(result["receipt"]?.jsonPrimitive?.content)
        val request = Json.parseToJsonElement(payload.decodeToString()).jsonObject
        val parsed = CnReceipt.verify(jwt, keys, BuildConfig.CN_LICENSE_AUDIENCE, identity!!.deviceHash,
            request.getValue("requestId").jsonPrimitive.content, request.getValue("clientNonce").jsonPrimitive.content, receipt,
            allowExpiredLeaseForRecovery = allowExpiredRecovery)
        require(!paidSeen || parsed.source == "license")
        if (parsed.source == "license") paidSeen = true
        val a = requireNotNull(networkAnchor).forNetworkResult(freshNonce)
        // Preserve revision high-water state even after a receipt expires or the device reboots.
        val high = persisted["highWater"]?.jsonObject ?: JsonObject(emptyMap())
        val key = parsed.source + ":" + parsed.id
        high[key]?.jsonObject?.let { old ->
            require(parsed.revision >= old.getValue("revision").jsonPrimitive.long && parsed.binding >= old.getValue("binding").jsonPrimitive.long && parsed.serverTimeMs >= old.getValue("server").jsonPrimitive.long)
        }
        save(buildJsonObject {
            put("receipt", jwt); put("requestId", request.getValue("requestId")); put("nonce", request.getValue("clientNonce"))
            put("anchor", buildJsonObject { put("elapsed", a.elapsedMs); put("wall", a.wallMs); put("boot", a.bootCount) })
            put("highWater", buildJsonObject { high.forEach { (k,v) -> put(k,v) }; put(key, buildJsonObject { put("revision", parsed.revision); put("binding", parsed.binding); put("server", parsed.serverTimeMs) }) })
        })
        evidence = parsed to a
        return parsed
    }
    private fun network(operation: String, payload: ByteArray): JsonObject {
        networkAnchor = CnLeaseAnchor(SystemClock.elapsedRealtime(), System.currentTimeMillis(), boot())
        val p = Json.parseToJsonElement(payload.decodeToString()).jsonObject
        val challenge = post("challenge", buildJsonObject {
            put("operation", operation); put("publicKey", CnLicenseProtocol.encode(identity!!.publicKey))
            put("requestId", p.getValue("requestId")); put("payloadHash", CnLicenseProtocol.hash(payload))
        })
        require(challenge.getValue("protocol").jsonPrimitive.content == "cn-license-v1")
        val id = challenge.getValue("challengeId").jsonPrimitive.content
        val message = CnLicenseProtocol.proof(operation, id, challenge.getValue("serverNonce").jsonPrimitive.content, payload)
        return post(operation, buildJsonObject { put("payload", CnLicenseProtocol.encode(payload)); put("challengeId", id); put("signature", CnLicenseProtocol.encode(identity!!.sign(message))) })
    }
    private fun post(operation: String, body: JsonObject): JsonObject {
        val base = URI(BuildConfig.CN_LICENSE_API)
        require(base.rawUserInfo == null && base.rawQuery == null && base.rawFragment == null && base.path in setOf("", "/"))
        require(if (BuildConfig.DEBUG) (base.scheme == "https" && base.host == "api.doneat.com.cn") || (base.scheme == "http" && base.host in setOf("localhost", "127.0.0.1")) else base.toString() == CnLicenseProtocol.ISSUER)
        val connection = base.resolve("/v1/licenses/$operation").toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"; connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000; connection.readTimeout = 15_000; connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json"); connection.setRequestProperty("Accept", "application/json")
            connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val bytes = stream?.use { input ->
                val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(4096)
                while (true) { val count = input.read(buffer); if (count < 0) break; require(out.size() + count <= 65_536); out.write(buffer, 0, count) }; out.toByteArray()
            } ?: byteArrayOf()
            val json = runCatching { Json.parseToJsonElement(bytes.decodeToString(throwOnInvalidSequence = true)).jsonObject }.getOrNull()
            if (status !in 200..299) throw CnApiFailure(json?.get("error")?.jsonPrimitive?.content ?: "temporarily_unavailable")
            return requireNotNull(json)
        } finally { connection.disconnect() }
    }
}
internal fun createChannelRepository(context: Context, scope: CoroutineScope): ChannelPlusRepository = CnLicenseRepository(context, scope)
