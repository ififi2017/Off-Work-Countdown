package com.rainif.doneat.plus

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

class PlaySignatureTest {
    @Test fun verifiesExactPayloadPackageProductAndKey() {
        val keys = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val wrong = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val json = """{"packageName":"com.rainif.doneat","productId":"configured.plus","purchaseToken":"token"}"""
        val signed = Signature.getInstance("SHA1withRSA").run {
            initSign(keys.private)
            update(json.toByteArray())
            Base64.getEncoder().encodeToString(sign())
        }
        val key = Base64.getEncoder().encodeToString(keys.public.encoded)
        val other = Base64.getEncoder().encodeToString(wrong.public.encoded)
        val allowed = setOf("configured.plus")
        assertTrue(PlaySignature.verify(json, signed, key, "com.rainif.doneat", allowed))
        assertFalse(PlaySignature.verify(json.replace("token", "other"), signed, key, "com.rainif.doneat", allowed))
        assertFalse(PlaySignature.verify(json, signed, other, "com.rainif.doneat", allowed))
        assertFalse(PlaySignature.verify(json, signed, key, "another.package", allowed))
        assertFalse(PlaySignature.verify(json, signed, key, "com.rainif.doneat", setOf("another.product")))
    }
}
