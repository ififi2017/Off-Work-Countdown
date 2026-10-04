import { ApiError, object, type Entitlement, type Env } from './types';

function upstreamObject(value: unknown): Record<string, unknown> {
  try { return object(value); } catch { throw new ApiError(503, 'verification_unavailable'); }
}

export function interpretPurchase(value: unknown, productId: string, env: Env, now: number): Entitlement & { linkedToken?: string } {
  const data = upstreamObject(value);
  const base = { productId, verifiedAtMs: now };
  if (productId === env.SUBSCRIPTION_PRODUCT) {
    if (!Array.isArray(data.lineItems)) throw new ApiError(503, 'verification_unavailable');
    const items = data.lineItems.map(upstreamObject).filter(item => item.productId === productId);
    const plans = env.SUBSCRIPTION_BASE_PLANS.split(',');
    const accepted = items.filter(item => plans.includes(String(upstreamObject(item.offerDetails).basePlanId)));
    if (accepted.length === 0) throw new ApiError(422, 'product_mismatch');
    const expiries = accepted.map(item => typeof item.expiryTime === 'string' ? Date.parse(item.expiryTime) : NaN);
    const state = data.subscriptionState;
    const active = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED'].includes(String(state));
    const pending = state === 'SUBSCRIPTION_STATE_PENDING';
    if (!active && !pending && !['SUBSCRIPTION_STATE_EXPIRED', 'SUBSCRIPTION_STATE_ON_HOLD',
      'SUBSCRIPTION_STATE_PAUSED', 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'].includes(String(state))) {
      throw new ApiError(503, 'verification_unavailable');
    }
    if (active && expiries.some(expiry => !Number.isSafeInteger(expiry))) throw new ApiError(503, 'verification_unavailable');
    const valid = expiries.filter(Number.isSafeInteger);
    const expiry = valid.length ? Math.max(...valid) : null;
    return { ...base, kind: 'subscription', status: active && expiry !== null && expiry > now ? 'active' : pending ? 'pending' : 'inactive',
      expiresAtMs: expiry, testPurchase: data.testPurchase !== undefined,
      linkedToken: typeof data.linkedPurchaseToken === 'string' ? data.linkedPurchaseToken : undefined };
  }
  if (productId !== env.LIFETIME_PRODUCT) throw new ApiError(400, 'invalid_product');
  if (!Array.isArray(data.productLineItem)) throw new ApiError(503, 'verification_unavailable');
  const item = data.productLineItem.map(upstreamObject).find(item => item.productId === productId);
  if (!item) throw new ApiError(422, 'product_mismatch');
  const offer = upstreamObject(item.productOfferDetails);
  if (offer.purchaseOptionId !== env.LIFETIME_PURCHASE_OPTION || offer.rentOfferDetails || offer.preorderOfferDetails) {
    throw new ApiError(422, 'product_mismatch');
  }
  const state = upstreamObject(data.purchaseStateContext).purchaseState;
  if (!['PURCHASED', 'PENDING', 'CANCELLED'].includes(String(state))) throw new ApiError(503, 'verification_unavailable');
  const refunded = typeof offer.refundableQuantity === 'number' && offer.refundableQuantity <= 0;
  const consumed = offer.consumptionState === 'CONSUMPTION_STATE_CONSUMED';
  return { ...base, kind: 'lifetime', status: state === 'PURCHASED' && !refunded && !consumed ? 'active' : state === 'PENDING' ? 'pending' : 'inactive',
    expiresAtMs: null, testPurchase: data.testPurchaseContext !== undefined };
}
