package com.rainif.doneat.plus

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

internal object PlaySignature {
    fun verify(json: String, signature: String, publicKey: String, packageName: String, allowed: Set<String>): Boolean =
        runCatching {
            if (publicKey.isBlank() || signature.isBlank()) return false
            val payload = Json.parseToJsonElement(json).jsonObject
            if (payload["packageName"]?.jsonPrimitive?.content != packageName) return false
            val ids = payload["productIds"]?.jsonArray?.map { it.jsonPrimitive.content }
            if (ids != null && ids.size != 1) return false
            val product = ids?.singleOrNull() ?: payload["productId"]?.jsonPrimitive?.content
            if (product !in allowed) return false
            if (payload["purchaseToken"]?.jsonPrimitive?.content.isNullOrBlank()) return false
            val key = KeyFactory.getInstance("RSA").generatePublic(
                X509EncodedKeySpec(Base64.getDecoder().decode(publicKey)),
            )
            Signature.getInstance("SHA1withRSA").run {
                initVerify(key)
                update(json.toByteArray(Charsets.UTF_8))
                verify(Base64.getDecoder().decode(signature))
            }
        }.getOrDefault(false)
}
