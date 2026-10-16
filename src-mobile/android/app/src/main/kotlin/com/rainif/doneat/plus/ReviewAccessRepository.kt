package com.rainif.doneat.plus

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import com.rainif.doneat.BuildConfig
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.net.URI
import java.security.SecureRandom
import java.util.Base64
import javax.net.ssl.HttpsURLConnection

enum class ReviewAccessError { UNAVAILABLE, INVALID_CODE, NETWORK, REVOKED, STORAGE }
data class ReviewAccessState(val configured: Boolean = false, val active: Boolean = false, val busy: Boolean = false, val hasSession: Boolean = false,
    val expiresAtMs: Long? = null, val error: ReviewAccessError? = null)

class ReviewAccessRepository(context: Context, private val scope: CoroutineScope) {
    private val app = context.applicationContext
    private val store = ReviewDeviceStore(app)
    private val keys = runCatching { Json.parseToJsonElement(BuildConfig.REVIEW_ACCESS_PUBLIC_KEYS).jsonObject.mapValues { it.value.jsonPrimitive.content } }.getOrDefault(emptyMap())
    private val _state = MutableStateFlow(ReviewAccessState(configured = keys.isNotEmpty()))
    val state: StateFlow<ReviewAccessState> = _state.asStateFlow()
    @Volatile private var session: ReviewSession? = null
    private var foreground = false
    private var operation: Job? = null
    private var expiry: Job? = null
    private var renewal: Job? = null
    private var generation = 0L
    private val disk = Mutex()
    private val loaded = CompletableDeferred<Unit>()
    private val initialized = scope.async(Dispatchers.IO) {
        disk.withLock { runCatching {
            store.load()?.also { cached ->
                val verified = ReviewGrant.read(cached.grant, keys, cached.id, ReviewGrant.keyHash(store.publicKey()))
                check(verified != null && verified.issuedAtMs == cached.lease.serverTimeMs && verified.expiresAtMs == cached.lease.expiresAtMs)
            }
        }.getOrElse { runCatching { store.clear() }; null } }
    }
    init { scope.launch { val cached = initialized.await(); if (generation == 0L) { session = cached; publish(); if (foreground) refresh() }; loaded.complete(Unit) } }
    internal suspend fun awaitLoaded() { loaded.await() }
    private fun bootCount(): Int = Settings.Global.getInt(app.contentResolver, Settings.Global.BOOT_COUNT, -1)
    private fun remaining(): Long = session?.lease?.remainingMs(SystemClock.elapsedRealtime(), bootCount()) ?: 0
    /** Read at use time too: process suspension must not leave an expired Boolean valid. */
    fun verifiedExpiry(nowMs: Long): Long? = if (keys.isEmpty()) null else session?.lease?.effectiveExpiryMs(nowMs, SystemClock.elapsedRealtime(), bootCount())
    fun onForeground(value: Boolean) {
        foreground = value
        renewal?.cancel()
        if (value) { publish(); refresh() }
    }
    fun refresh() {
        if (keys.isEmpty() || operation?.isActive == true) return
        val current = session ?: return
        launchOperation(null, current)
    }
    fun activate(code: String) {
        if (keys.isEmpty() || operation?.isActive == true) return
        val credential = code.trim().replace("-", "").replace(" ", "").uppercase(java.util.Locale.ROOT)
        if (!credential.matches(Regex("[A-Z0-9]{32}"))) { _state.value = _state.value.copy(error = ReviewAccessError.INVALID_CODE); return }
        launchOperation(credential, null)
    }
    private fun launchOperation(credential: String?, current: ReviewSession?) {
        val epoch = ++generation
        _state.value = _state.value.copy(busy = true, error = null)
        operation = scope.launch {
            try {
                initialized.await()
                val next = withContext(Dispatchers.IO) {
                    val started = SystemClock.elapsedRealtime()
                    val boot = bootCount()
                    val public = store.publicKey(create = credential != null)
                    val nonce = random()
                    val op = if (credential != null) "activate" else "renew"
                    val challenge = challenge(op, public, nonce, credential, current)
                    val result = complete(op, public, nonce, challenge)
                    ensureActive()
                    val id = result.getValue("installationId").jsonPrimitive.content
                    if (current != null) check(id == current.id)
                    val raw = result.getValue("grant").jsonPrimitive.content
                    val grant = ReviewGrant.read(raw, keys, id, ReviewGrant.keyHash(public), nonce) ?: error("invalid grant")
                    check(result.getValue("serverTimeMs").jsonPrimitive.long == grant.issuedAtMs)
                    if (current != null) check(grant.revision >= (ReviewGrant.read(current.grant, keys, current.id, ReviewGrant.keyHash(public))?.revision ?: Long.MAX_VALUE))
                    val secret = result["renewalSecret"]?.jsonPrimitive?.content ?: current?.secret ?: error("missing secret")
                    check(secret.matches(Regex("[A-Za-z0-9_-]{43}")))
                    ReviewSession(id, secret, raw, ReviewLease(grant.issuedAtMs, started, boot, grant.expiresAtMs))
                }
                ensureActive()
                if (epoch != generation) return@launch
                disk.withLock { withContext(Dispatchers.IO) { store.save(next) } }
                if (epoch != generation) return@launch
                session = next
                publish()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: ReviewApiFailure) {
                if (epoch != generation) return@launch
                if (failure.status in setOf(401, 403, 404, 410)) {
                    session = null
                    disk.withLock { withContext(Dispatchers.IO) { runCatching { store.clear() } } }
                }
                publish(if (failure.status == 503) ReviewAccessError.UNAVAILABLE else if (failure.status in setOf(401,403,404,410))
                    if (credential != null) ReviewAccessError.INVALID_CODE else ReviewAccessError.REVOKED else ReviewAccessError.NETWORK)
            } catch (_: java.io.IOException) { if (epoch == generation) publish(ReviewAccessError.NETWORK) }
            catch (_: Exception) { if (epoch == generation) publish(ReviewAccessError.STORAGE) }
            finally { if (epoch == generation) _state.value = _state.value.copy(busy = false) }
        }
    }
    fun exit() {
        ++generation
        operation?.cancel(); renewal?.cancel(); expiry?.cancel()
        val previous = session
        session = null
        _state.value = ReviewAccessState(configured = keys.isNotEmpty(), busy = true)
        operation = scope.launch {
            try {
                initialized.await()
                disk.withLock { withContext(Dispatchers.IO) { store.clear() } }
                if (previous != null) withContext(Dispatchers.IO) {
                    runCatching {
                        val public = store.publicKey()
                        val nonce = random()
                        complete("exit", public, nonce, challenge("exit", public, nonce, null, previous))
                    }
                }
            } catch (_: Exception) { _state.value = _state.value.copy(error = ReviewAccessError.STORAGE) }
            finally { _state.value = _state.value.copy(busy = false) }
        }
    }
    private fun publish(error: ReviewAccessError? = null) {
        val duration = remaining().takeIf { keys.isNotEmpty() } ?: 0
        _state.value = _state.value.copy(active = duration > 0, hasSession = session != null, expiresAtMs = session?.lease?.expiresAtMs, error = error)
        expiry?.cancel(); renewal?.cancel()
        if (duration > 0) {
            expiry = scope.launch { delay(duration); publish() }
            if (foreground) renewal = scope.launch { delay((duration - 300_000).coerceAtLeast(60_000)); refresh() }
        }
    }
    private fun challenge(op: String, public: ByteArray, nonce: String, credential: String?, current: ReviewSession?): JsonObject =
        post("challenge", buildJsonObject {
            put("operation", op); put("publicKeySpki", Base64.getEncoder().encodeToString(public)); put("nonce", nonce)
            if (credential != null) put("credential", credential) else { put("installationId", current!!.id); put("renewalSecret", current.secret) }
        })
    private fun complete(op: String, public: ByteArray, nonce: String, challenge: JsonObject): JsonObject {
        val id = challenge.getValue("challengeId").jsonPrimitive.content
        val challengeNonce = challenge.getValue("challengeNonce").jsonPrimitive.content
        val message = listOf("doneat-review-access-v1", op, id, challengeNonce, ReviewGrant.keyHash(public), nonce).joinToString("\n")
        return post(op, buildJsonObject {
            put("challengeId", id); put("challengeNonce", challengeNonce); put("publicKeySpki", Base64.getEncoder().encodeToString(public))
            put("nonce", nonce); put("signature", store.sign(message))
        })
    }
    private fun post(path: String, body: JsonObject): JsonObject {
        val connection = URI("${ReviewGrant.ISSUER}/v1/review-access/$path").toURL().openConnection() as HttpsURLConnection
        try {
            connection.requestMethod = "POST"; connection.instanceFollowRedirects = false
            connection.connectTimeout = 10_000; connection.readTimeout = 15_000; connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json"); connection.setRequestProperty("Cache-Control", "no-store")
            connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            if (connection.responseCode != 200) throw ReviewApiFailure(connection.responseCode)
            val bytes = connection.inputStream.use { it.readReviewBytes() }; check(bytes.size <= 32_768)
            return Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
        } finally { connection.disconnect() }
    }
    private class ReviewApiFailure(val status: Int) : Exception()
    private fun random(): String = ByteArray(32).also { SecureRandom().nextBytes(it) }.let { Base64.getUrlEncoder().withoutPadding().encodeToString(it) }
}
