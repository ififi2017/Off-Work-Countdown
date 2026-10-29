package com.rainif.doneat.plus

import kotlinx.serialization.json.*
import java.util.Base64

/** Decoding is atomic: no pending command or paid history escapes before current trust is proven. */
internal data class CnLoadedLicenseCache(
    val receipt: CnReceipt?, val anchor: CnLeaseAnchor?, val paidSeen: Boolean,
    val pendingOperation: String?, val pendingPayload: ByteArray?,
)

internal object CnLicenseCache {
    /** Keep device identity stable across rotation. This stamp scopes saved commands, not Keystore aliases. */
    fun trustFingerprint(applicationId: String, audience: String, keys: Map<String, String>): String {
        require(applicationId.isNotBlank() && audience.isNotBlank() && keys.isNotEmpty())
        val value = buildJsonObject {
            put("applicationId", applicationId); put("audience", audience)
            put("issuer", CnLicenseProtocol.ISSUER); put("channel", "cn"); put("protocol", 1)
            put("keys", buildJsonObject {
                keys.toSortedMap().forEach { (kid, encoded) ->
                    put(kid, CnLicenseProtocol.hash(Base64.getDecoder().decode(encoded)))
                }
            })
        }
        return CnLicenseProtocol.hash(value.toString().toByteArray(Charsets.UTF_8))
    }

    fun read(data: JsonObject, currentTrust: String,
        verifyReceipt: (compact: String, requestId: String, nonce: String) -> CnReceipt): CnLoadedLicenseCache {
        // A matching stamp never substitutes for verifying a stored receipt. Removing its key
        // or changing that key's material rejects the whole old authorization context.
        val receipt = data["receipt"]?.jsonPrimitive?.content?.let { compact ->
            verifyReceipt(compact, data.getValue("requestId").jsonPrimitive.content, data.getValue("nonce").jsonPrimitive.content)
        }
        val stampMatches = data["trustFingerprint"]?.jsonPrimitive?.content == currentTrust
        // A still-verifiable old receipt supports normal key addition/rotation and legacy files.
        // A receipt-free initial pending command has no such proof, so its stamp must match.
        require(stampMatches || receipt != null)
        val operation = data["pendingOperation"]?.jsonPrimitive?.content
        val payload = data["pendingPayload"]?.jsonPrimitive?.content?.let(CnLicenseProtocol::decode)
        require((operation == null) == (payload == null))
        val paidSeen = data["paidSeen"]?.jsonPrimitive?.boolean ?: false
        val anchor = data["anchor"]?.jsonObject?.let { a ->
            CnLeaseAnchor(a.getValue("elapsed").jsonPrimitive.long, a.getValue("wall").jsonPrimitive.long, a.getValue("boot").jsonPrimitive.int)
        }
        return CnLoadedLicenseCache(receipt, anchor, paidSeen, operation, payload)
    }
}
