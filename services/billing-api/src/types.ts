export interface Env {
  DB: D1Database;
  VERIFY_IP_LIMIT: RateLimit;
  VERIFY_TOKEN_LIMIT: RateLimit;
  PACKAGE_NAME: string;
  SUBSCRIPTION_PRODUCT: string;
  SUBSCRIPTION_BASE_PLANS: string;
  LIFETIME_PRODUCT: string;
  LIFETIME_PURCHASE_OPTION: string;
  ISSUER: string;
  SIGNING_KEY_ID: string;
  GOOGLE_SERVICE_ACCOUNT_EMAIL: string;
  GOOGLE_PRIVATE_KEY: string;
  ENTITLEMENT_PRIVATE_KEY: string;
  PUBSUB_SERVICE_ACCOUNT_EMAIL: string;
  PUBSUB_SUBSCRIPTION: string;
  PUBSUB_AUDIENCE: string;
}

export interface Entitlement {
  productId: string;
  kind: 'subscription' | 'lifetime';
  status: 'active' | 'inactive' | 'pending';
  expiresAtMs: number | null;
  verifiedAtMs: number;
  testPurchase: boolean;
}

export interface StoredEntitlement extends Entitlement {
  tokenHash: string;
  revision: number;
  replacedByHash: string | null;
}

export class ApiError extends Error {
  constructor(public readonly status: number, public readonly code: string) {
    super(code); // Never include purchase tokens, Google URLs, payloads or credentials.
  }
}

export function object(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new ApiError(400, 'invalid_request');
  return value as Record<string, unknown>;
}

export function boundedString(value: unknown, max = 4096): string {
  if (typeof value !== 'string' || !value.length || value.length > max || /[\u0000-\u0020]/.test(value)) {
    throw new ApiError(400, 'invalid_request');
  }
  return value;
}

export async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}
