import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from 'jose';
import { ApiError, type Env, type StoredEntitlement } from './types';

const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'), { timeoutDuration: 5000 });
let signingKey: { pem: string; key: Promise<CryptoKey> } | undefined;

export async function authenticatePubSub(request: Request, env: Env): Promise<void> {
  const auth = request.headers.get('Authorization');
  if (!auth?.startsWith('Bearer ') || auth.length > 8192) throw new ApiError(401, 'unauthorized');
  try {
    const { payload } = await jwtVerify(auth.slice(7), googleKeys, {
      algorithms: ['RS256'], issuer: ['https://accounts.google.com', 'accounts.google.com'],
      audience: env.PUBSUB_AUDIENCE, requiredClaims: ['exp', 'iat', 'email', 'email_verified'],
      maxTokenAge: '2h', clockTolerance: 30,
    });
    if (payload.email !== env.PUBSUB_SERVICE_ACCOUNT_EMAIL || payload.email_verified !== true) throw new Error('identity');
  } catch {
    // Pub/Sub retries a non-2xx, including temporary failure to fetch Google's public keys.
    throw new ApiError(401, 'unauthorized');
  }
}

export async function signReceipt(env: Env, grant: StoredEntitlement, nonce: string, now: number): Promise<string> {
  if (signingKey?.pem !== env.ENTITLEMENT_PRIVATE_KEY) {
    signingKey = { pem: env.ENTITLEMENT_PRIVATE_KEY, key: importPKCS8(env.ENTITLEMENT_PRIVATE_KEY, 'RS256') };
  }
  const status = grant.status === 'active' && grant.kind === 'subscription' && (grant.expiresAtMs ?? 0) <= now ? 'inactive' : grant.status;
  // This is receipt cache validity, never the subscription's actual expiry.
  const cacheUntilMs = status === 'active'
    ? grant.kind === 'subscription' ? grant.expiresAtMs! : grant.verifiedAtMs + 366 * 86_400_000
    : now + 86_400_000;
  return new SignJWT({ v: 1, productId: grant.productId, kind: grant.kind, status,
    expiresAtMs: grant.expiresAtMs, verifiedAtMs: grant.verifiedAtMs, cacheUntilMs,
    testPurchase: grant.testPurchase, revision: grant.revision, nonce })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT', kid: env.SIGNING_KEY_ID })
    .setIssuer(env.ISSUER).setAudience(env.PACKAGE_NAME).setSubject(grant.tokenHash)
    .setIssuedAt(Math.floor(now / 1000)).setExpirationTime(Math.ceil(cacheUntilMs / 1000))
    .sign(await signingKey.key);
}
