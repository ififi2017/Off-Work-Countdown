# DoneAt Play purchase verification

One Cloudflare Worker, one D1 database, two POST endpoints at `api.doneat.app`.
This directory has its own npm lockfile, deployment and tests. It does not run
inside the Next.js site or the Android process. Task status and test evidence
live only in [Android progress](../../docs/android/progress.md).

## Contract and boundaries

- `POST /v1/billing/google/verify`: JSON `{purchaseToken, productId, nonce}`.
  A fresh 16–128 character alphanumeric/underscore/hyphen nonce binds the response
  to the request. The result is `{receipt: "RS256 JWT"}`. The token is a sensitive
  bearer credential; only send it over HTTPS in the request body.
- `POST /v1/billing/google/notifications`: authenticated, **wrapped** Google
  Pub/Sub push envelope. Verify Google's signature, issuer, audience, service
  account email, verified-email claim, expiry and exact subscription name.
  A successful response is 204. Duplicate message IDs do not reapply events.
- Google Publisher `subscriptionsv2.get` / `productsv2.getproductpurchasev2`
  supplies the entitlement. No purchase date, renewal boolean or SKU duration
  is used to estimate expiry. Canceled-but-unexpired and grace-period
  subscriptions keep the expiry Google verified. Pending, held, paused,
  expired, refunded or consumed products do not grant access.
- RTDN triggers a fresh Google query, including for late/out-of-order events.
  Linked active replacements invalidate the old token; pending replacements
  leave it alone. D1 transactions and expiring per-token leases stop stale
  concurrent queries from overwriting newer results.
- The service performs **read-only purchase queries**. Client acknowledgement
  and the existing three-day retry path remain in Android. It never refunds,
  cancels, consumes or acknowledges an order. Pending refund-review notices
  contain a refund token, not a purchase token: delivery is acknowledged with
  no entitlement change. Automatic refund review/evidence submission is outside
  this service; manage any such requests through Google's available process.
- There are no DoneAt accounts, salary/records APIs, analytics, polling jobs,
  queues or scheduled tasks. This change provides verified alarm boundaries;
  it does not implement the Android wake-up alarm/ringing service.

### Signed receipt v1

Header: `alg=RS256`, `typ=JWT`, `kid=SIGNING_KEY_ID`. Claims:
`iss=https://api.doneat.app`, `aud=com.rainif.doneat`, `sub=SHA256(purchaseToken)`,
`v=1`, `productId`, `kind`, `status`, `expiresAtMs`, `verifiedAtMs`,
`cacheUntilMs`, `testPurchase`, `revision`, `nonce`, `iat`, `exp`.

Android checks the signature with bundled public keys, plus the package,
product, token hash, fresh network nonce, times and revision. It stores receipts
in `noBackupFilesDir`, never RecordJSON. A configured client does not fall back
to a local purchase boolean if verification fails. It can use a still-valid
signed receipt while offline. Subscription receipts stop at the exact Google
expiry; lifetime cache validity is 366 days and is not a purchase expiry.
A lifetime alarm window remains the domain rule's rolling **calendar year**.

Refunds/renewals reach D1 through RTDN, but an offline phone cannot receive that
new knowledge. The next successful app verification replaces its cached
receipt; recent checks coalesce for at most 120 seconds. No instantaneous
revocation of an offline phone is claimed. A single in-memory deadline updates
access if the app stays open past receipt expiry; it performs no network polling.
Transient verification failures reuse the existing one-time billing retry work. Old client-only builds remain on
their existing policy until a build with server public keys is installed.

### Stored data and failure behavior

D1 stores token SHA-256, product, entitlement state/expiry, verification time,
test flag, replacement hash and revision. These are purchase-related identifiers,
not anonymous usage statistics. Purchase rows are retained for entitlement
restoration and replacement protection. Dedupe message IDs use a 30-day window; older IDs and expired leases are removed
during later notification handling. Raw tokens,
Google response bodies, OAuth tokens, order IDs, email, salary and work records
are not stored. Google OAuth tokens are cached only in Worker memory.

Worker request/exception logging is disabled. Do not enable body/header logging,
`wrangler tail` payload tracing, or a third-party analytics plugin. Cloudflare and
Google still process network traffic under their own platform policies. The
Worker hashes the connecting IP transiently for rate limiting; it does not write
IP addresses or these IP hashes to D1. There is no claim that infrastructure has
no access to IP addresses.

HTTP 400/413/415/422 reject invalid or unavailable purchases; 401/403 reject
unauthorized push; 429 limits repeated verification; 503 requests retry after
30 seconds. Failed Google calls do not manufacture revocations or extend expiry.
Pub/Sub retries failed delivery. Rate bindings are **per Cloudflare location**,
not a global spending cap: IP 300/minute and purchase token 12/minute. D1 quotas,
Google API quotas and abuse still need monitoring.

## Local checks

Use Node 24 and npm 11 (same as CI):

```sh
cd services/billing-api
npm ci
npm run typecheck
npm test
npm run build
```

Tests run the actual Workers runtime and D1 migrations with mocked Google HTTP
responses; they are not evidence of a real Google purchase, IAM or production
connection. `build` is a dry run. No credentials are needed for these checks.
Root Web tests exclude this independent service.

## Deployment runbook

Perform the steps in order. The Android release variable stays unset until
production and license-tester checks pass and privacy disclosures are published.
The deployment script rejects the placeholder D1 ID. Never put a Google JSON key,
private PEM, purchase token or Cloudflare API token in Git, chat, an APK or a URL.

### 1. Google Cloud and Play permissions

Project: `august-edge-217210`.
Billing identity: `doneat-billing@august-edge-217210.iam.gserviceaccount.com`.
Enable **Google Play Android Developer API** and **Cloud Pub/Sub API**.
In Play Console → Users and permissions, grant this identity access to **DoneAt
only**, including **View financial data** and **Manage orders and subscriptions**
as required by Google's purchase API setup. Do not grant Play account admin or
Google Cloud Owner/Editor. The API code uses no order-management methods.
Create a JSON key for this identity; keep it in a private location outside Git.

### 2. Topic and Play RTDN

In Google Cloud → Pub/Sub → Topics, create `doneat-play-rtdn`:

- Uncheck **Add a default subscription**. No schema, ingestion, topic retention,
  BigQuery export, Cloud Storage backup, transforms or tags are needed.
- Keep **Google-owned and Google-managed encryption keys**.
- On this topic only, grant
  `google-play-developer-notifications@system.gserviceaccount.com`
  **Pub/Sub Publisher**.

In Play Console, select DoneAt → **Monetize with Play → Monetization setup →
Real-time developer notifications**. Enable and set:
`projects/august-edge-217210/topics/doneat-play-rtdn`.
Select all subscription **and one-time product** notifications. Save changes.
Send the test after the push subscription and Worker exist.

### 3. Push identity

Create another service account named `doneat-rtdn-push` in the same project.
It needs **no Play Console permissions or project-wide role**, and no downloaded
private key. Its expected email is
`doneat-rtdn-push@august-edge-217210.iam.gserviceaccount.com`.

The confirmed numeric **project number** is `1007961080129`, distinct from the project ID.
On this push service account's permissions, grant the Pub/Sub service agent
`service-1007961080129@gcp-sa-pubsub.iam.gserviceaccount.com` the **Service Account
Token Creator** role. Scope this grant to the push identity, not the whole project.
The person creating the push subscription also needs permission to act as that
identity (`iam.serviceAccounts.actAs`, included in Service Account User).

### 4. Cloudflare D1 and signing key

From this directory on a trusted computer:

```sh
npx wrangler login
npx wrangler whoami
npx wrangler d1 create billing
```

Use the intended Cloudflare account. Put the returned **database_id** into
`wrangler.jsonc`; it is public configuration. Check the domain route and product
IDs in that file. It must use the Play package `com.rainif.doneat`, not a preview
application ID. Do not replace an existing `api.doneat.app` service/DNS record
without reviewing what already owns it.

```sh
npm run db:remote
npm run keys
npm run deploy
npm run secrets -- /absolute/private/path/to/google-service-account.json
```

`keys` creates a new RSA identity in ignored `.secrets/` with restrictive file
permissions, and refuses to overwrite it. `deploy` requires an interactive terminal so Wrangler cannot silently override
conflicting DNS or another Worker. It creates the custom domain and the Worker; it returns 503 until both secrets are uploaded. `secrets` reads
the Google key and receipt key locally, validates the service account, and pipes
them directly to Wrangler encrypted secrets without printing values. It stores
only `GOOGLE_PRIVATE_KEY` and `ENTITLEMENT_PRIVATE_KEY`. Keep a secure backup of
the receipt signing key. The Google JSON itself is not uploaded wholesale.

The Worker uses `workers.dev=false`, no preview URLs and no deployment secrets
in GitHub CI. Creation/deployment uses the operator's Cloudflare login. Check
that `api.doneat.app` has active TLS and the expected Worker custom-domain route.

### 5. Authenticated push subscription

Under the topic, create a subscription with these settings:

| Field | Value |
|---|---|
| ID | `doneat-play-rtdn-push` |
| Delivery | Push |
| Endpoint | `https://api.doneat.app/v1/billing/google/notifications` |
| Authentication | Enabled |
| Service account | `doneat-rtdn-push@august-edge-217210.iam.gserviceaccount.com` |
| Audience | `https://api.doneat.app/v1/billing/google/notifications` |
| Payload unwrapping | Disabled; keep the Pub/Sub envelope |
| Acknowledgement deadline | 60 seconds |
| Retry | Exponential backoff, minimum 30 seconds / maximum 600 seconds |
| Message retention | 7 days; do not retain acknowledged messages |
| Expiration | Never expire |
| Filter / transforms / ordering | None |

Do not put Cloudflare Access, a browser challenge or a login redirect in front
of the two API routes. Authentication for push is the Google OIDC identity.

### 6. Connectivity, privacy and Android activation

1. Without authorization, POST to the notification path must return **401**,
   not 204. An empty verification body must return **400** after secrets load,
   not `service_not_configured`. Do not send a fabricated paid purchase.
2. Send **Test notification** in Play Console. Check Pub/Sub push response counts
   for **204**, the unacknowledged backlog draining, and a new D1 `notifications`
   row. A Play “publish succeeded” alone does not prove Worker delivery.
3. Update the official English/Chinese privacy policy using
   [prepared source copy](../../docs/android/privacy-policy-addition.md), About
   networking wording if needed, and the Play Data safety disclosure to match
   purchase tokens sent to Cloudflare/Google. The service stores purchase state;
   do not claim that no DoneAt purchase server exists.
4. After these checks, put the contents of `.secrets/android-public-keys.json`
   into repository **Variable** `DONEAT_BILLING_API_PUBLIC_KEYS` (public keys only).
   The Android release workflow maps it to `doneatBillingApiPublicKeys`. For a
   local build, use `ORG_GRADLE_PROJECT_doneatBillingApiPublicKeys`. Blank keeps
   the previous client-only mode; nonblank malformed configuration fails closed.
5. Use an internal/closed Play test build and a configured **license tester**
   with test payment methods. Check purchase, restore, pending, cancellation with
   remaining paid time, renewal, grace/hold where available, refund, replacement,
   network loss, expiry and duplicate/late RTDN. Inspect only sanitized outcomes
   and exact expiry; never log tokens. Do not perform real purchases for QA.
6. Measure production Worker CPU (cold and warm paths), D1 reads/writes and
   Pub/Sub delivery metrics. Local workerd timing does not prove the 10 ms free
   CPU allowance is sufficient. Record actual evidence in `progress.md` before
   calling this deployed/verified or enabling wake-up alarms.

## Operations

- Use aggregate Cloudflare invocation/error/CPU metrics and Pub/Sub push response,
  oldest-unacked-message age and backlog metrics. Alert on persistent non-2xx,
  401/403, 429, 503, quota failures and growing backlog; no token/body logging.
  Error codes distinguish configuration/verification failures without disclosing
  upstream details. This repo does not provision account alert destinations.
- Pub/Sub automatic retries cover transient outages. On a prolonged outage,
  fix permissions/secrets/quotas and inspect backlog before its retention expires.
  App foreground/restore checks independently reconcile purchases; there is no
  promise of recovering RTDN after retention expires.
- Roll back Worker code with Cloudflare deployments while retaining D1 and secrets.
  Do not delete a D1 table or rotate a signing identity as a code rollback. The
  initial schema is additive; later changes need new migrations.
- For receipt key rotation, ship an Android public-key map containing old and new
  keys first, then switch the Worker key and `SIGNING_KEY_ID`. Keep old public keys
  for supported older receipts. Older installed apps without the new key cannot
  accept new receipts: coordinate rollout and preserve recovery via an app update.
- Free-plan limits are shared across the account. Free Workers/D1 limits can stop
  requests; they are not a guarantee of unlimited free production service.
  Google Pub/Sub throughput/egress and Google API quotas are separate. Set budget
  alerts in the account consoles before enabling a paid plan; alerting is not a
  hard spending cap.

## Primary references

- [Google Play API setup and permissions](https://developers.google.com/android-publisher/getting_started)
- [Subscription v2 resource](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2)
- [One-time purchase v2 resource](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2)
- [RTDN setup](https://developer.android.com/google/play/billing/getting-ready#configure-rtdn)
- [RTDN event schemas](https://developer.android.com/google/play/billing/rtdn-reference)
- [Authenticated Pub/Sub push](https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions)
- [Workers rate limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)
- [D1 batch transactions](https://developers.cloudflare.com/d1/worker-api/d1-database/)
