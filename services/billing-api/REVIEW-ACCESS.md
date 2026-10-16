# Review access operations and protocol

This service grants a separate, revocable app-review lease. It never contacts Google, writes purchase tables, creates orders, alters trials, or identifies reviewers by IP, account or country. The ordinary settings entry and all Plus consumers are implemented by Android. Possession of the reusable credential authorizes activation; this does not prove the person is a Google employee.

## Rollout gate

`REVIEW_ACCESS_ENABLED` was `false` until the gates below were met; production issuance was enabled with owner approval on 2026-10-16 (`wrangler.jsonc` is the deployed value). No credential or signing key is included in this repository. Do not enable production until isolated Worker/Android security tests and matching published About/Privacy/Data safety disclosures have been reviewed. Applying migration `0002` is additive; existing purchases are untouched. The owner confirmed this R1 implementation and data scope on 2026-10-16; that approval includes service rollout after the validation/disclosure gates, but does not include publishing the app to production. The migration and daily cron may run while issuance is disabled.

Required bindings: `REVIEW_PRIVATE_KEY` (PKCS8 RSA >=2048 bits), `REVIEW_SIGNING_KEY_ID` (`review-…`), `REVIEW_AUTH_LIMIT`, `REVIEW_INSTALL_LIMIT`. The key must differ cryptographically from `ENTITLEMENT_PRIVATE_KEY`, even if PEM whitespace differs, and the kid must differ from `SIGNING_KEY_ID`. Review signing configuration is checked independently of Google configuration. Purchase routes retain their original checks and signing key.

Create keys only in an operator-approved private directory outside the checkout, never in a shell argument, terminal output or APK. Commands below are templates, not instructions to enable production now:

```sh
npm run review:admin -- keys --directory /ABS/PRIVATE/REVIEW --kid review-YYYY-NN
npm run review:admin -- check-keys --private-file /ABS/PRIVATE/REVIEW/review-private.pem --public-file /ABS/PRIVATE/REVIEW/android-review-public-keys.json --purchase-public-file /ABS/PRIVATE/PURCHASE/android-public-keys.json --kid review-YYYY-NN
```

The directory must be mode `0700`; generated files use `0600`, exclusive creation and no secret output. `android-review-public-keys.json` is `{ "review-YYYY-NN": "base64 DER RSA SPKI" }`, configured separately from purchase keys in Android. Upload the private file to the dedicated Worker secret through the existing protected operator process (not the purchase-key uploader). Never reuse purchase public keys. Retain old review verification keys until all issued grants have expired when rotating keys. The deployment checker for purchases is not a review-rollout approval.

## Credential/session management

The operator tool generates 20 random bytes as 32 base32 characters grouped by four. It stores the reusable code only in the selected protected JSON file, and only its SHA-256 digest in D1. It refuses private output within this checkout (including resolved symlinks) and never prints codes, private keys or failed subprocess output. Use `--local` for isolated development; `--remote` mutates production and is covered only by the recorded owner-approved rollout and the gates above.

```sh
npm run review:admin -- create-credential --file /ABS/PRIVATE/REVIEW/credential.json --local
npm run review:admin -- register-credential --file /ABS/PRIVATE/REVIEW/credential.json --local
npm run review:admin -- revoke-credential --file /ABS/PRIVATE/REVIEW/credential.json --local
npm run review:admin -- revoke-installation --installation-id INSTALLATION_UUID --local
```

`register-credential` recovers a database insertion failure using the already protected file; it refuses files marked revoked. Credentials have no automatic expiry or installation count ceiling. On code leak: create replacement, update Play App access's dedicated credential field privately, then revoke the old digest. Never paste a code into Git, a PR, a command line, a URL, a screenshot, logs or this runbook. No personal email belongs in the credential. Revoking a credential first marks its protected operator file `revoked:true`, then uses one atomic D1 DELETE with cascading foreign keys to remove the digest and its installations/challenges. Pending completions fail their active-credential guard. Register refuses a marked file; never edit that marker or reuse an old code. If the database call fails after marking, repeat revoke with the same file. Revoking an installation blocks its pending renewals; the reusable code can still activate a new installation.

Exit clears local state immediately even offline. An authenticated online exit deletes that installation. Revocation/disable cannot retract an already issued offline JWT: the remaining lease is at most 24h. Expiry/exit/revocation must preserve records/settings and real Play entitlement. Disabling only `REVIEW_ACCESS_ENABLED` stops all new review requests and leaves purchase service intact. Never roll back D1 purchase data.

## HTTP contract (v1)

Only HTTPS POST JSON, without query strings; no CORS. All responses are `Cache-Control: no-store`. Maximum body 16KiB, strict field sets, no request/exception logging. Unknown keys fail. Service errors contain fixed codes only. Default disabled: `503 review_access_disabled`. Invalid authentication: `401 review_access_denied`; invalid proof: `401 invalid_proof`; rate limits: `429 rate_limited` with Retry-After 30. Other malformed fields may be `400 invalid_request`/`invalid_installation_key`. A client must treat 401 as revoked/invalid and remove review access; it must not clear paid Play state.

Installation public key: standard padded base64 of **91-byte DER SPKI P-256** (id-ecPublicKey, prime256v1, uncompressed point). Fingerprint: lowercase 64-character SHA-256 hex of the DER bytes (not base64 text). Android private key remains in Keystore. SHA256withECDSA produces the strict canonical ASN.1 DER signature expected below; this service converts DER to WebCrypto IEEE-P1363 before verification.

1. `POST /v1/review-access/challenge`:

```json
{"operation":"activate","publicKeySpki":"BASE64_DER_SPKI","nonce":"RANDOM_BASE64URL_16_TO_128_CHARS","credential":"REUSABLE_CODE"}
```

For `renew` or `exit`, replace `credential` with `installationId` (server UUIDv4) and `renewalSecret` (43-character unpadded base64url encoding of 32 random bytes). The same credential can be submitted repeatedly across installations. Code normalization removes ASCII spaces and hyphens and uppercases; the result must be 32 characters `[A-Z2-7]`.

Response:

```json
{"challengeId":"UUIDv4","challengeNonce":"RANDOM_43_CHAR_BASE64URL","expiresAtMs":1800000060000,"serverTimeMs":1800000000000}
```

The 60-second nonce is stored only as a digest. The row also binds operation, installation fingerprint, request nonce and credential revision/session. Expiry is enforced during completion even before cleanup. Challenge requests authenticate before storing the challenge.

2. Sign exactly this UTF-8 string with the installation key. The five separators are LF (`\n`); there is **no trailing LF**:

```text
doneat-review-access-v1
OPERATION
CHALLENGE_UUID
CHALLENGE_NONCE
LOWERCASE_SPKI_SHA256_HEX
REQUEST_NONCE
```

3. POST to `/v1/review-access/activate`, `/renew`, or `/exit` with exactly:

```json
{"challengeId":"UUIDv4","challengeNonce":"RETURNED_NONCE","publicKeySpki":"BASE64_DER_SPKI","nonce":"SAME_REQUEST_NONCE","signature":"UNPADDED_BASE64URL_DER_ECDSA_SIGNATURE"}
```

The challenge is atomically consumed by `DELETE … RETURNING` after proof verification. Replay, different keys/nonces/operations, revoked credentials/sessions and expired challenges fail. A failed signature does not consume the challenge. If a successful response is lost, activate again with the reusable credential, or renew with the existing installation secret and a fresh challenge. Challenges are not credentials, and consuming one never consumes the reusable code.

Activate response: `{grant, installationId, renewalSecret, serverTimeMs}`. Renew response: `{grant, installationId, serverTimeMs}`; it does not rotate the installation secret. Exit response: `{exited:true, serverTimeMs}`. Renew and exit never resubmit the shared code. The renewal secret is distinct per installation; D1 stores only its digest.

## JWT contract

RS256 only; protected header `{alg:"RS256", typ:"doneat-review-access+jwt", kid:"review-…"}`. Claims:

- `iss`: `https://api.doneat.app`; `aud`: `com.rainif.doneat:review-access`.
- `sub`: server installation UUID; `v`: 1; `purpose`: `app-review`; `scope`: `plus`.
- `credentialRevision`: positive revision; `installationKeyHash`: DER-SPKI fingerprint.
- `nonce`: request nonce; `serverTimeMs`: same exact millisecond value as response.
- `iat`: floor(serverTimeMs / 1000); `exp`: iat + 86400. The grant expires up to 999ms before serverTimeMs + 24h, never later.

Android must verify fixed algorithm/type/key map/issuer/audience/purpose/scope/version, installation identity/fingerprint, request nonce, revision/time consistency and maximum lifetime. Never resolve JWT-provided key URLs/JWKs. Purchase and review verifiers cannot accept each other's JWT type, audience or key. JWTs are leases, never purchase receipts. Use server time plus monotonic elapsed time; clock rollback cannot extend the grant, and reboot requires online renewal if remaining lifetime cannot be trusted.

## Retention and operational checks

Daily cron at `03:17 UTC` deletes expired challenges and installation sessions with last successful activation/renewal at least seven days old. Read paths reject idle sessions at exactly seven days even if cron has not run. Credential digests and dependent rows are deleted on explicit rotation/revocation; no accidental TTL on reusable codes. Cleanup SQL names only review tables. Challenges do not extend installation retention. Private local records/keys/JWTs are excluded from Android backup and RecordJSON.

Authentication buckets are per credential/session (600/min) and per installation fingerprint (30/min). There is no IP bucket or device-count cap; distinct reviewer installations behind shared egress are independent. These limits provide bounded retries, not a substitute for 160-bit credential entropy. Worker platform/zone abuse controls remain applicable and must not use geography or reviewer fingerprinting. Do not log IP/UA, public key bodies, JWTs or credentials. No analytics events are added.

Validation commands: `npm run typecheck`, `npm test`, `npm run build` (dry run only). Tests cover D1 migration, independent keys, signing/binding/24h lease, Java-compatible DER proof, cross-operation/key/nonce, concurrent replay, revocation before completion, expiry, lost-response recovery, independent installation secrets, shared egress, strict HTTP, rate limits, retention and purchase-table preservation. Local runtime timing is not production Worker CPU: before enabling, measure cold/hot RS256+ECDSA+DB on the actual current Worker plan in an approved isolated deployment; retain CPU/error/D1 evidence without payloads. Free 10ms suitability remains a release gate until that measurement exists. Upgrading a paid plan requires a separate decision.
