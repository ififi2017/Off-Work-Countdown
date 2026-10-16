# Public interoperability fixtures

These fixtures contain only ephemeral **test** public keys, messages and signatures. Their private keys were discarded without being written to disk. They are unrelated to any production signing identity, credential, user, installation or Play order.

- `java-p256-proof.json`: generated using Android Studio JBR OpenJDK 25.0.3 SunEC, `KeyPairGenerator("EC")` with `ECGenParameterSpec("secp256r1")`, SPKI `getEncoded()`, SHA-256 DER fingerprint, and `Signature("SHA256withECDSA")`. The message uses the production `proofMessage` line contract. The Worker test verifies the real DER signature via its DER-to-P1363 conversion and WebCrypto, and rejects a trailing newline.
- `jose-rs256-grant.json`: generated using jose 6.2.12 `generateKeyPair("RS256")` and `SignJWT`; the 24-hour grant's server time, installation hash and request nonce are fixed for Android interoperability testing. The test public-key map is the same base64 DER RSA SPKI format as Android's separate review configuration. Tests should evaluate this at `serverTimeMs`, never use wall time.

No fixture key may be configured as a production review or purchase identity.
