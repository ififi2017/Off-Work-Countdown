import { env } from 'cloudflare:workers';
import { applyD1Migrations, type D1Migration } from 'cloudflare:test';
import { beforeAll, beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { exportJWK, exportPKCS8, generateKeyPair, jwtVerify, SignJWT } from 'jose';
import worker from '../src/index';
import { acquireLease, readPurchase, releaseLease, savePurchase } from '../src/store';
import { sha256, type Env } from '../src/types';

const bindings = env as unknown as Env & { TEST_MIGRATIONS: D1Migration[] };
const nonce = 'test_nonce_1234567890';
let config: Env;
let keys: Awaited<ReturnType<typeof generateKeyPair>>;
let googleResponse: Record<string, unknown>;
let googleStatus: number;
let googleCalls: number;
let gate: Promise<void> | undefined;

function subscription(state = 'SUBSCRIPTION_STATE_ACTIVE', days = 30) {
  return { subscriptionState: state, lineItems: [{ productId: 'doneat_plus',
    expiryTime: new Date(Date.now() + days * 86_400_000).toISOString(), offerDetails: { basePlanId: 'monthly' } }] };
}
function lifetime(state = 'PURCHASED') {
  return { purchaseStateContext: { purchaseState: state }, productLineItem: [{ productId: 'doneat_plus_lifetime',
    productOfferDetails: { purchaseOptionId: 'lifetime', consumptionState: 'CONSUMPTION_STATE_YET_TO_BE_CONSUMED', refundableQuantity: 1 } }] };
}
function request(body: unknown, route = 'verify', authorization?: string) {
  return new Request(`https://api.doneat.app/v1/billing/google/${route}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(authorization ? { Authorization: authorization } : {}) },
    body: JSON.stringify(body),
  });
}
async function verify(token = 'a-real-purchase-token', productId = 'doneat_plus') {
  return worker.fetch(request({ purchaseToken: token, productId, nonce }), config);
}
async function receipt(response: Response) {
  expect(response.status).toBe(200);
  const body = await response.json() as { receipt: string };
  return (await jwtVerify(body.receipt, keys.publicKey, { issuer: config.ISSUER, audience: config.PACKAGE_NAME, algorithms: ['RS256'] })).payload;
}
async function authorization(claims: Record<string, unknown> = {}, audience = config.PUBSUB_AUDIENCE, expiry = '1h') {
  return `Bearer ${await new SignJWT({ email: config.PUBSUB_SERVICE_ACCOUNT_EMAIL, email_verified: true, ...claims })
    .setProtectedHeader({ alg: 'RS256', kid: 'google-test-key' }).setIssuer('https://accounts.google.com')
    .setAudience(audience).setIssuedAt().setExpirationTime(expiry).sign(keys.privateKey)}`;
}
function eventEnvelope(event: Record<string, unknown>, id = crypto.randomUUID()) {
  return { subscription: config.PUBSUB_SUBSCRIPTION, message: { messageId: id,
    data: btoa(JSON.stringify({ packageName: config.PACKAGE_NAME, eventTimeMillis: String(Date.now()), ...event })) } };
}
async function notify(event: Record<string, unknown>, id?: string) {
  return worker.fetch(request(eventEnvelope(event, id), 'notifications', await authorization()), config);
}

beforeAll(async () => {
  await applyD1Migrations(bindings.DB, bindings.TEST_MIGRATIONS);
  keys = await generateKeyPair('RS256', { extractable: true });
  const pem = await exportPKCS8(keys.privateKey);
  config = { ...bindings, GOOGLE_PRIVATE_KEY: pem, ENTITLEMENT_PRIVATE_KEY: pem,
    GOOGLE_SERVICE_ACCOUNT_EMAIL: 'billing@test-project.iam.gserviceaccount.com',
    PUBSUB_SERVICE_ACCOUNT_EMAIL: 'push@test-project.iam.gserviceaccount.com',
    PUBSUB_SUBSCRIPTION: 'projects/test-project/subscriptions/play-rtdn',
    VERIFY_IP_LIMIT: { limit: async () => ({ success: true }) },
    VERIFY_TOKEN_LIMIT: { limit: async () => ({ success: true }) } };
});
beforeEach(async () => {
  await bindings.DB.batch(['purchases', 'verification_leases', 'notifications'].map(table => bindings.DB.prepare(`DELETE FROM ${table}`)));
  googleResponse = subscription(); googleStatus = 200; googleCalls = 0; gate = undefined;
  const jwk = { ...await exportJWK(keys.publicKey), kid: 'google-test-key', alg: 'RS256', use: 'sig' };
  vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
    const url = String(input);
    if (url === 'https://oauth2.googleapis.com/token') return Response.json({ access_token: 'server-access-token', expires_in: 3600 });
    if (url === 'https://www.googleapis.com/oauth2/v3/certs') return Response.json({ keys: [jwk] });
    if (url.startsWith('https://androidpublisher.googleapis.com/')) {
      googleCalls++; if (gate) await gate;
      return Response.json(googleResponse, { status: googleStatus });
    }
    throw new Error('Unexpected network destination');
  });
});
afterEach(() => vi.restoreAllMocks());

describe('verified entitlement API', () => {
  it('binds signed receipts to nonce, package, product and token hash; stores no raw token', async () => {
    const result = await receipt(await verify());
    expect(result).toMatchObject({ v: 1, status: 'active', kind: 'subscription', productId: 'doneat_plus', nonce,
      sub: await sha256('a-real-purchase-token'), revision: 1 });
    expect(result.expiresAtMs).toBe((googleResponse.lineItems as Array<{ expiryTime: string }>)[0].expiryTime &&
      Date.parse((googleResponse.lineItems as Array<{ expiryTime: string }>)[0].expiryTime));
    const saved = JSON.stringify(await config.DB.prepare('SELECT * FROM purchases').all());
    expect(saved).not.toContain('a-real-purchase-token');
    expect(saved).not.toContain('server-access-token');
  });
  it('reuses a recent Google result without manufacturing a later verification time', async () => {
    const first = await receipt(await verify());
    const second = await receipt(await verify());
    expect(googleCalls).toBe(1);
    expect(second.verifiedAtMs).toBe(first.verifiedAtMs);
    expect(second.expiresAtMs).toBe(first.expiresAtMs);
  });
  it.each(['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED'])(
    'preserves the verified paid/grace period for %s', async state => {
      googleResponse = subscription(state);
      expect((await receipt(await verify())).status).toBe('active');
    });
  it.each(['SUBSCRIPTION_STATE_EXPIRED', 'SUBSCRIPTION_STATE_ON_HOLD', 'SUBSCRIPTION_STATE_PAUSED', 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'])(
    'does not grant %s even if an expiry field is still in the future', async state => {
      googleResponse = subscription(state);
      expect((await receipt(await verify())).status).toBe('inactive');
    });
  it('does not grant a pending subscription without an expiry', async () => {
    googleResponse = { subscriptionState: 'SUBSCRIPTION_STATE_PENDING', lineItems: [{ productId: 'doneat_plus', offerDetails: { basePlanId: 'yearly' } }] };
    expect((await receipt(await verify())).status).toBe('pending');
  });
  it('honors the precise expiry and never derives it from auto-renewal or purchase time', async () => {
    googleResponse = subscription('SUBSCRIPTION_STATE_ACTIVE', 0);
    expect((await receipt(await verify())).status).toBe('inactive');
  });
  it('rejects unknown states, invalid dates and wrong base plans', async () => {
    googleResponse = subscription('SOME_FUTURE_UNKNOWN_STATE');
    expect((await verify()).status).toBe(503);
    googleResponse = { ...subscription(), lineItems: [{ productId: 'doneat_plus', expiryTime: 'broken', offerDetails: { basePlanId: 'monthly' } }] };
    expect((await verify()).status).toBe(503);
    googleResponse = { ...subscription(), lineItems: [{ productId: 'doneat_plus', expiryTime: '2027-01-01T00:00:00Z', offerDetails: { basePlanId: 'unapproved' } }] };
    expect((await verify()).status).toBe(422);
    expect((await config.DB.prepare('SELECT * FROM purchases').all()).results).toHaveLength(0);
  });
  it.each([['PURCHASED', 'active'], ['PENDING', 'pending'], ['CANCELLED', 'inactive']])('validates lifetime %s', async (state, expected) => {
    googleResponse = lifetime(state);
    expect(await receipt(await verify('lifetime-token', 'doneat_plus_lifetime'))).toMatchObject({ status: expected, kind: 'lifetime', expiresAtMs: null });
  });
  it('denies consumed and fully refunded lifetime products', async () => {
    googleResponse = lifetime();
    const items = googleResponse.productLineItem as Array<{ productOfferDetails: Record<string, unknown> }>;
    items[0].productOfferDetails.refundableQuantity = 0;
    expect((await receipt(await verify('refund-token', 'doneat_plus_lifetime'))).status).toBe('inactive');
    items[0].productOfferDetails.refundableQuantity = 1;
    items[0].productOfferDetails.consumptionState = 'CONSUMPTION_STATE_CONSUMED';
    expect((await receipt(await verify('consumed-token', 'doneat_plus_lifetime'))).status).toBe('inactive');
  });
  it('keeps test purchases identifiable in the signed proof', async () => {
    googleResponse.testPurchase = {};
    expect((await receipt(await verify())).testPurchase).toBe(true);
  });
  it('preserves known evidence when Google is unavailable instead of inventing a revocation', async () => {
    await verify();
    const before = await readPurchase(config.DB, await sha256('a-real-purchase-token'));
    googleStatus = 403;
    const result = await notify({ subscriptionNotification: { purchaseToken: 'a-real-purchase-token', notificationType: 13 } });
    expect(result.status).toBe(503);
    expect(await readPurchase(config.DB, await sha256('a-real-purchase-token'))).toEqual(before);
    expect((await config.DB.prepare('SELECT * FROM notifications').all()).results).toHaveLength(0);
  });
  it('sanitizes unknown token and upstream errors', async () => {
    googleStatus = 404; googleResponse = { error: 'sensitive purchase token' };
    const response = await verify();
    expect(response.status).toBe(422);
    expect(await response.text()).toBe('{"error":"purchase_unavailable"}');
  });
});

describe('HTTP boundaries', () => {
  it('requires a POST JSON body and rejects tokens in URLs', async () => {
    expect((await worker.fetch(new Request('https://api.doneat.app/v1/billing/google/verify'), config)).status).toBe(405);
    expect((await worker.fetch(new Request('https://api.doneat.app/unknown'), config)).status).toBe(404);
    expect((await worker.fetch(new Request('https://api.doneat.app/v1/billing/google/verify?token=x', { method: 'POST' }), config)).status).toBe(400);
    expect((await worker.fetch(new Request('https://api.doneat.app/v1/billing/google/verify', { method: 'POST', body: '{}' }), config)).status).toBe(415);
  });
  it('rejects other products, short nonces, unexpected fields and oversized bodies before Google', async () => {
    expect((await verify('token', 'unapproved')).status).toBe(400);
    expect((await worker.fetch(request({ purchaseToken: 'token', productId: 'doneat_plus', nonce: 'short' }), config)).status).toBe(400);
    expect((await worker.fetch(request({ purchaseToken: 'token', productId: 'doneat_plus', nonce, salary: 1000 }), config)).status).toBe(400);
    expect((await worker.fetch(request({ purchaseToken: 'x'.repeat(20_000) }), config)).status).toBe(413);
    expect(googleCalls).toBe(0);
  });
  it('enforces rate limits and does not cache responses', async () => {
    const response = await worker.fetch(request({ purchaseToken: 'token', productId: 'doneat_plus', nonce }), {
      ...config, VERIFY_TOKEN_LIMIT: { limit: async () => ({ success: false }) },
    });
    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe('30');
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(googleCalls).toBe(0);
  });
  it('fails closed before external configuration is supplied', async () => {
    const response = await worker.fetch(request({}), { ...config, GOOGLE_PRIVATE_KEY: '' });
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: 'service_not_configured' });
  });
});

describe('Google notifications', () => {
  it('authenticates Google test messages and deduplicates deliveries', async () => {
    const notice = { subscriptionNotification: { purchaseToken: 'a-real-purchase-token', notificationType: 2 } };
    expect((await notify({ testNotification: {} })).status).toBe(204);
    expect(googleCalls).toBe(0);
    expect((await notify(notice, 'same-message')).status).toBe(204);
    expect((await notify(notice, 'same-message')).status).toBe(204);
    expect(googleCalls).toBe(1);
  });
  it.each(['missing', 'wrong_email', 'unverified_email', 'wrong_audience', 'expired'])(
    'rejects %s push authentication', async mode => {
      let auth: string | undefined;
      if (mode === 'wrong_email') auth = await authorization({ email: 'intruder@example.com' });
      if (mode === 'unverified_email') auth = await authorization({ email_verified: false });
      if (mode === 'wrong_audience') auth = await authorization({}, 'https://other.example');
      if (mode === 'expired') auth = await authorization({}, config.PUBSUB_AUDIENCE, '-1h');
      expect((await worker.fetch(request(eventEnvelope({ testNotification: {} }), 'notifications', auth), config)).status).toBe(401);
      expect((await config.DB.prepare('SELECT * FROM notifications').all()).results).toHaveLength(0);
    });
  it('checks the exact subscription and package', async () => {
    const body = eventEnvelope({ testNotification: {} }); body.subscription = 'projects/other/subscriptions/other';
    expect((await worker.fetch(request(body, 'notifications', await authorization()), config)).status).toBe(403);
    expect((await notify({ packageName: 'com.other.app', testNotification: {} })).status).toBe(403);
  });
  it('queries the current Google state for old events and never trusts the event type as entitlement', async () => {
    googleResponse = subscription('SUBSCRIPTION_STATE_ACTIVE', 60);
    expect((await notify({ eventTimeMillis: '1', subscriptionNotification: { purchaseToken: 'token', notificationType: 13 } })).status).toBe(204);
    expect((await readPurchase(config.DB, await sha256('token')))?.status).toBe('active');
  });
  it('rechecks full refunds and only then records the result', async () => {
    googleResponse = lifetime('CANCELLED');
    expect((await notify({ voidedPurchaseNotification: { purchaseToken: 'lifetime', productType: 2, refundType: 1 } })).status).toBe(204);
    expect((await readPurchase(config.DB, await sha256('lifetime')))?.status).toBe('inactive');
  });
});

describe('concurrent and replacement purchases', () => {
  it('blocks concurrent queries for the same token until the first completes', async () => {
    let resume!: () => void;
    gate = new Promise<void>(resolve => { resume = resolve; });
    const first = verify();
    await vi.waitFor(() => expect(googleCalls).toBe(1));
    expect((await verify()).status).toBe(503);
    resume();
    expect((await first).status).toBe(200);
    expect((await config.DB.prepare('SELECT * FROM verification_leases').all()).results).toHaveLength(0);
  });
  it('prevents a stale lease owner from overwriting a newer query', async () => {
    const hash = await sha256('token');
    const now = Date.now();
    const old = await acquireLease(config.DB, hash, now);
    const latest = await acquireLease(config.DB, hash, now + 46_000);
    const grant = { productId: 'doneat_plus', kind: 'subscription' as const, status: 'inactive' as const, expiresAtMs: now, verifiedAtMs: now, testPurchase: false };
    await expect(savePurchase(config.DB, hash, old, grant, undefined, now + 46_000)).rejects.toMatchObject({ status: 503 });
    await savePurchase(config.DB, hash, latest, grant, undefined, now + 46_000);
    await releaseLease(config.DB, hash, old);
    expect(await config.DB.prepare('SELECT owner FROM verification_leases').first()).toEqual({ owner: latest });
  });
  it('marks linked old tokens superseded and cannot resurrect them through a later stale Google response', async () => {
    await verify('old');
    googleResponse = { ...subscription(), linkedPurchaseToken: 'old' };
    await verify('new');
    expect((await readPurchase(config.DB, await sha256('old')))?.replacedByHash).toBe(await sha256('new'));
    googleResponse = subscription();
    expect((await notify({ subscriptionNotification: { purchaseToken: 'old', notificationType: 2 } })).status).toBe(204);
    expect((await receipt(await verify('old'))).status).toBe('inactive');
  });
  it('does not cancel the paid old token while its replacement is pending', async () => {
    await verify('old');
    googleResponse = { ...subscription('SUBSCRIPTION_STATE_PENDING'), linkedPurchaseToken: 'old' };
    await verify('new');
    expect((await readPurchase(config.DB, await sha256('old')))?.status).toBe('active');
  });
});


it('acknowledges refund-review delivery without guessing a purchase token or issuing a refund decision', async () => {
  const result = await notify({ pendingRefundReviewNotification: {
    version: '1.0', pendingRefundToken: 'refund-review-token', orderId: 'GPA.test', refundReason: 7,
  } });
  expect(result.status).toBe(204);
  expect(googleCalls).toBe(0);
  expect((await config.DB.prepare('SELECT * FROM purchases').all()).results).toHaveLength(0);
});
