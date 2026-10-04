import { importPKCS8, SignJWT } from 'jose';
import { ApiError, type Env } from './types';

const tokenEndpoint = 'https://oauth2.googleapis.com/token';
let accessToken: { email: string; privateKey: string; value: string; expiresAt: number } | undefined;

async function googleAccessToken(env: Env): Promise<string> {
  if (accessToken?.email === env.GOOGLE_SERVICE_ACCOUNT_EMAIL && accessToken.privateKey === env.GOOGLE_PRIVATE_KEY &&
      accessToken.expiresAt > Date.now() + 60_000) return accessToken.value;
  const key = await importPKCS8(env.GOOGLE_PRIVATE_KEY, 'RS256');
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/androidpublisher' })
    .setProtectedHeader({ alg: 'RS256' }).setIssuer(env.GOOGLE_SERVICE_ACCOUNT_EMAIL)
    .setAudience(tokenEndpoint).setIssuedAt().setExpirationTime('1h').sign(key);
  const response = await fetch(tokenEndpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new ApiError(503, 'verification_unavailable');
  const data = await response.json() as { access_token?: unknown; expires_in?: unknown };
  if (typeof data.access_token !== 'string' || typeof data.expires_in !== 'number' || data.expires_in <= 0) {
    throw new ApiError(503, 'verification_unavailable');
  }
  accessToken = { email: env.GOOGLE_SERVICE_ACCOUNT_EMAIL, privateKey: env.GOOGLE_PRIVATE_KEY,
    value: data.access_token, expiresAt: Date.now() + Math.min(data.expires_in, 3600) * 1000 };
  return accessToken.value;
}

export async function getPurchase(env: Env, token: string, subscription: boolean): Promise<unknown> {
  const access = await googleAccessToken(env);
  const resource = subscription ? 'subscriptionsv2' : 'productsv2';
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(env.PACKAGE_NAME)}/purchases/${resource}/tokens/${encodeURIComponent(token)}`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${access}` }, signal: AbortSignal.timeout(10_000),
  });
  if (response.status === 401) accessToken = undefined;
  // An unrecognized token is not evidence that a previously issued entitlement was revoked.
  if ([400, 404, 410].includes(response.status)) throw new ApiError(422, 'purchase_unavailable');
  if (!response.ok) throw new ApiError(503, 'verification_unavailable');
  return response.json();
}
