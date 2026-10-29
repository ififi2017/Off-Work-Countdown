package com.rainif.doneat.plus

import android.content.Context
import android.util.AtomicFile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.File
import java.net.URI
import java.util.UUID
import javax.net.ssl.HttpsURLConnection

/** Only this narrow client sends purchase tokens; it has no reference to the records archive. */
internal class BillingServerClient(context: Context, private val publicKeys: Map<String, String>) {
    private val packageName = context.packageName
    private val file = AtomicFile(File(context.noBackupFilesDir, "plus-server-receipts.json"))
    private var cached: Map<String, String> = emptyMap()
    val configured: Boolean get() = publicKeys.isNotEmpty()

    fun load() {
        cached = runCatching {
            Json.parseToJsonElement(file.openRead().bufferedReader().use { it.readText() }).jsonObject
                .mapValues { it.value.jsonPrimitive.content }
        }.getOrDefault(emptyMap())
    }

    fun receipts(purchases: List<VerifiedPurchase>, nowMs: Long): Map<String, BillingReceipt> =
        purchases.mapNotNull { purchase ->
            val raw = cached[BillingReceipt.tokenHash(purchase.token)] ?: return@mapNotNull null
            BillingReceipt.read(raw, publicKeys, packageName, purchase.productId, purchase.token, purchase.isSubscription, nowMs)
                ?.let { purchase.token to it }
        }.toMap()

    suspend fun refresh(purchases: List<VerifiedPurchase>, nowMs: Long): Boolean = withContext(Dispatchers.IO) {
        if (!configured) return@withContext true
        val keep = purchases.map { BillingReceipt.tokenHash(it.token) }.toSet()
        val next = cached.filterKeys { it in keep }.toMutableMap()
        var success = true
        for (purchase in purchases.filter { it.purchased && !it.suspended }) {
            ensureActive()
            val hash = BillingReceipt.tokenHash(purchase.token)
            val previous = next[hash]?.let { BillingReceipt.read(it, publicKeys, packageName, purchase.productId,
                purchase.token, purchase.isSubscription, nowMs) }
            // Collapse lifecycle callbacks; explicit expiry is still checked on every publication.
            if (previous != null && previous.usableAt(nowMs) && nowMs - previous.verifiedAtMs in 0 until 120_000) continue
            try {
                val nonce = UUID.randomUUID().toString()
                val body = buildJsonObject { put("purchaseToken", purchase.token); put("productId", purchase.productId); put("nonce", nonce) }.toString()
                val connection = URI("${BillingReceipt.ISSUER}/v1/billing/google/verify").toURL().openConnection() as HttpsURLConnection
                val raw = try {
                    connection.requestMethod = "POST"
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 10_000
                    connection.readTimeout = 15_000
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.setRequestProperty("Cache-Control", "no-store")
                    connection.doOutput = true
                    connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                    check(connection.responseCode == 200)
                    val bytes = connection.inputStream.use { input ->
                        val buffer = ByteArray(32_769)
                        var count = 0
                        while (count < buffer.size) {
                            val read = input.read(buffer, count, buffer.size - count)
                            if (read < 0) break
                            count += read
                        }
                        buffer.copyOf(count)
                    }
                    check(bytes.size <= 32_768)
                    Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject.getValue("receipt").jsonPrimitive.content
                } finally { connection.disconnect() }
                ensureActive()
                val verified = BillingReceipt.read(raw, publicKeys, packageName, purchase.productId, purchase.token,
                    purchase.isSubscription, System.currentTimeMillis(), nonce)
                check(verified != null && verified.usableAt(System.currentTimeMillis()))
                check(previous == null || verified.revision >= previous.revision)
                next[hash] = raw
            } catch (error: CancellationException) { throw error }
            catch (_: Exception) { success = false } // Keep the last signed evidence; never log a token or response.
        }
        if (next != cached) {
            val bytes = buildJsonObject { next.forEach { (hash, receipt) -> put(hash, receipt) } }.toString().toByteArray()
            val stream = file.startWrite()
            try { stream.write(bytes); file.finishWrite(stream); cached = next }
            catch (error: Exception) { file.failWrite(stream); throw error }
        }
        success
    }
}
