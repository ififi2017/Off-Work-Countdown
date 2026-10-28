package com.rainif.doneat.plus

import kotlinx.serialization.json.*
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

/** Test-only keys are generated in the JVM; no signing material is shipped or persisted. */
internal object CnReceiptTestFixtures {
    const val NOW = 1_800_000_000_000L
    const val AUDIENCE = "com.rainif.doneat.cn"
    const val REQUEST = "11111111-1111-4111-8111-111111111111"
    const val LICENSE = "22222222-2222-4222-8222-222222222222"
    const val TEST_KID = "cn-test-fixture"
    val DEVICE = "a".repeat(64)
    val NONCE = CnLicenseProtocol.encode(ByteArray(24) { it.toByte() })
    val testKey: KeyPair by lazy { KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair() }
    val productionKey: KeyPair by lazy { KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair() }
    fun publicKey(pair: KeyPair): String = Base64.getEncoder().encodeToString(pair.public.encoded)
    val testKeys get() = mapOf(TEST_KID to publicKey(testKey))
    fun claims(edit: JsonObjectBuilder.() -> Unit = {}): JsonObject = buildJsonObject {
        put("iss", CnLicenseProtocol.ISSUER); put("aud", AUDIENCE); put("channel", "cn"); put("v", 1)
        put("sub", LICENSE); put("deviceKeyHash", DEVICE); put("bindingVersion", 2); put("licenseRevision", 3)
        put("source", "license"); put("plan", "annual"); put("status", "active"); put("reason", "valid")
        put("entitlementExpiresAtMs", NOW + 365 * CnLicenseProtocol.DAY_MS)
        put("serverTimeMs", NOW); put("leaseUntilMs", NOW + CnLicenseProtocol.DAY_MS)
        put("requestId", REQUEST); put("nonce", NONCE); put("iat", NOW / 1000); put("exp", (NOW + CnLicenseProtocol.DAY_MS) / 1000)
        edit()
    }
    fun token(claims: JsonObject = claims(), pair: KeyPair = testKey, kid: String = TEST_KID): String {
        val head = buildJsonObject { put("alg", "RS256"); put("typ", "JWT"); put("kid", kid) }
        val message = CnLicenseProtocol.encode(head.toString().toByteArray()) + "." + CnLicenseProtocol.encode(claims.toString().toByteArray())
        val signature = Signature.getInstance("SHA256withRSA").run { initSign(pair.private); update(message.toByteArray()); sign() }
        return message + "." + CnLicenseProtocol.encode(signature)
    }
    fun read(token: String = token(), previous: CnReceipt? = null, device: String = DEVICE,
        request: String = REQUEST, nonce: String = NONCE): CnReceipt =
        CnReceipt.verify(token, testKeys, AUDIENCE, device, request, nonce, previous)
}
