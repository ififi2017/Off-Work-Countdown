import { interpretPurchase } from './entitlement';
import { getPurchase } from './google';
import { authenticatePubSub, signReceipt } from './receipt';
import { acquireLease, finishNotification, notificationHandled, readPurchase, releaseLease, savePurchase } from './store';
import { ApiError, boundedString, object, sha256, type Env, type StoredEntitlement } from './types';

const VERIFY = '/v1/billing/google/verify';
const NOTIFICATIONS = '/v1/billing/google/notifications';
const headers = { 'Cache-Control': 'no-store', 'Content-Type': 'application/json', 'X-Content-Type-Options': 'nosniff' };

async function readBody(request: Request): Promise<Record<string, unknown>> {
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) throw new ApiError(415, 'json_required');
  if (!request.body) throw new ApiError(400, 'invalid_request');
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > 16_384) { await reader.cancel(); throw new ApiError(413, 'request_too_large'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try { return object(JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes))); }
  catch { throw new ApiError(400, 'invalid_request'); }
}

async function verify(env: Env, token: string, productId: string, force: boolean): Promise<StoredEntitlement> {
  const hash = await sha256(token);
  const now = Date.now();
  if (!force) {
    const cached = await readPurchase(env.DB, hash);
    if (cached?.productId === productId && now - cached.verifiedAtMs >= 0 && now - cached.verifiedAtMs < 120_000 &&
        !(cached.kind === 'subscription' && cached.status === 'active' && (cached.expiresAtMs ?? 0) <= now)) return cached;
  }
  const owner = await acquireLease(env.DB, hash, now);
  try {
    const data = await getPurchase(env, token, productId === env.SUBSCRIPTION_PRODUCT);
    const grant = interpretPurchase(data, productId, env, Date.now());
    const linkedHash = grant.linkedToken ? await sha256(grant.linkedToken) : undefined;
    return await savePurchase(env.DB, hash, owner, grant, linkedHash, Date.now());
  } finally {
    await releaseLease(env.DB, hash, owner);
  }
}

function requireConfiguration(env: Env): void {
  const values = [env.PACKAGE_NAME, env.SUBSCRIPTION_PRODUCT, env.SUBSCRIPTION_BASE_PLANS, env.LIFETIME_PRODUCT,
    env.LIFETIME_PURCHASE_OPTION, env.GOOGLE_SERVICE_ACCOUNT_EMAIL, env.GOOGLE_PRIVATE_KEY, env.ENTITLEMENT_PRIVATE_KEY,
    env.SIGNING_KEY_ID, env.PUBSUB_SERVICE_ACCOUNT_EMAIL, env.PUBSUB_SUBSCRIPTION, env.PUBSUB_AUDIENCE];
  if (values.some(value => !value || value.includes('CONFIGURE_ME')) || env.ISSUER !== 'https://api.doneat.app' ||
      env.SUBSCRIPTION_PRODUCT === env.LIFETIME_PRODUCT) throw new ApiError(503, 'service_not_configured');
}

async function handleVerify(request: Request, env: Env): Promise<Response> {
  // IP buckets are coarse abuse protection, not identity or an account; hashes are never written to D1 or logs.
  const ip = request.headers.get('CF-Connecting-IP') ?? 'local';
  if (!(await env.VERIFY_IP_LIMIT.limit({ key: await sha256(ip) })).success) throw new ApiError(429, 'rate_limited');
  const body = await readBody(request);
  if (Object.keys(body).some(key => !['purchaseToken', 'productId', 'nonce'].includes(key))) throw new ApiError(400, 'invalid_request');
  const token = boundedString(body.purchaseToken);
  const productId = boundedString(body.productId, 200);
  const nonce = boundedString(body.nonce, 128);
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(nonce)) throw new ApiError(400, 'invalid_request');
  if (![env.SUBSCRIPTION_PRODUCT, env.LIFETIME_PRODUCT].includes(productId)) throw new ApiError(400, 'invalid_product');
  if (!(await env.VERIFY_TOKEN_LIMIT.limit({ key: await sha256(token) })).success) throw new ApiError(429, 'rate_limited');
  const grant = await verify(env, token, productId, false);
  return Response.json({ receipt: await signReceipt(env, grant, nonce, Date.now()) }, { headers });
}

async function handleNotification(request: Request, env: Env): Promise<Response> {
  await authenticatePubSub(request, env);
  const envelope = await readBody(request);
  if (envelope.subscription !== env.PUBSUB_SUBSCRIPTION) throw new ApiError(403, 'wrong_subscription');
  const message = object(envelope.message);
  const id = boundedString(message.messageId, 200);
  if (await notificationHandled(env.DB, id)) return new Response(null, { status: 204, headers });
  let event: Record<string, unknown>;
  try { event = object(JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(
    Uint8Array.from(atob(boundedString(message.data, 12_000)), char => char.charCodeAt(0))))); }
  catch { throw new ApiError(400, 'invalid_notification'); }
  if (event.packageName !== env.PACKAGE_NAME) throw new ApiError(403, 'wrong_package');
  const variants = ['subscriptionNotification', 'oneTimeProductNotification', 'voidedPurchaseNotification',
    'pendingRefundReviewNotification', 'testNotification'].filter(key => event[key] !== undefined);
  if (variants.length !== 1) throw new ApiError(400, 'invalid_notification');
  // Refund review requests contain an order/refund token, not a purchase token. This read-only
  // service acknowledges delivery but never submits a refund decision or changes access from it.
  if (!event.testNotification && !event.pendingRefundReviewNotification) {
    const notice = object(event[variants[0]]);
    const token = boundedString(notice.purchaseToken);
    let product = env.SUBSCRIPTION_PRODUCT;
    if (event.oneTimeProductNotification) product = boundedString(notice.sku, 200);
    else if (event.voidedPurchaseNotification) {
      if (notice.productType !== 1 && notice.productType !== 2) throw new ApiError(400, 'invalid_notification');
      product = notice.productType === 1 ? env.SUBSCRIPTION_PRODUCT : env.LIFETIME_PRODUCT;
    }
    if (![env.SUBSCRIPTION_PRODUCT, env.LIFETIME_PRODUCT].includes(product)) throw new ApiError(400, 'invalid_product');
    try { await verify(env, token, product, true); }
    catch (error) {
      // An inaccessible Google purchase is retried; no receipt or revocation is manufactured.
      if (error instanceof ApiError && error.status === 422) throw new ApiError(503, 'verification_unavailable');
      throw error;
    }
  }
  await finishNotification(env.DB, id, Date.now());
  return new Response(null, { status: 204, headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      if (![VERIFY, NOTIFICATIONS].includes(url.pathname)) throw new ApiError(404, 'not_found');
      if (request.method !== 'POST') return Response.json({ error: 'method_not_allowed' }, { status: 405, headers: { ...headers, Allow: 'POST' } });
      if (url.search) throw new ApiError(400, 'query_not_allowed');
      requireConfiguration(env);
      return url.pathname === VERIFY ? await handleVerify(request, env) : await handleNotification(request, env);
    } catch (error) {
      const known = error instanceof ApiError ? error : new ApiError(503, 'verification_unavailable');
      // Deliberately no exception/request logging: upstream URLs contain purchase tokens.
      return Response.json({ error: known.code }, { status: known.status,
        headers: { ...headers, ...([429, 503].includes(known.status) ? { 'Retry-After': '30' } : {}) } });
    }
  },
} satisfies ExportedHandler<Env>;
