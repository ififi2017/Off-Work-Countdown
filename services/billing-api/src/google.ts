import { importPKCS8, SignJWT } from 'jose';
import { ApiError, type Env } from './types';

const tokenEndpoint = 'https://oauth2.googleapis.com/token';
type AccessToken = { value: string; expiresAt: number };
type OAuthState = {
  email: string;
  privateKey: string;
  accessToken?: AccessToken;
  refreshSequence: number;
  appliedRefresh: number;
};
let oauthState: OAuthState | undefined;
let signingKey: { pem: string; key: Promise<CryptoKey> } | undefined;

function credentials(env: Env): OAuthState {
  if (oauthState?.email !== env.GOOGLE_SERVICE_ACCOUNT_EMAIL || oauthState.privateKey !== env.GOOGLE_PRIVATE_KEY) {
    oauthState = { email: env.GOOGLE_SERVICE_ACCOUNT_EMAIL, privateKey: env.GOOGLE_PRIVATE_KEY, refreshSequence: 0, appliedRefresh: 0 };
  }
  return oauthState;
}

/** A rotated PEM replaces the isolate-local key; failed imports may be retried. */
function googleSigningKey(pem: string): Promise<CryptoKey> {
  if (signingKey?.pem !== pem) {
    const key = importPKCS8(pem, 'RS256');
    signingKey = { pem, key };
    void key.catch(() => { if (signingKey?.key === key) signingKey = undefined; });
  }
  return signingKey.key;
}

async function refreshAccessToken(state: OAuthState): Promise<AccessToken> {
  const sequence = ++state.refreshSequence;
  const key = await googleSigningKey(state.privateKey);
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/androidpublisher' })
    .setProtectedHeader({ alg: 'RS256' }).setIssuer(state.email)
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
  const token = { value: data.access_token, expiresAt: Date.now() + Math.min(data.expires_in, 3600) * 1000 };
  // Refreshes keep their network I/O in the originating request. Only the latest
  // completed generation for the current identity may populate the warm cache;
  // a slower, earlier exchange cannot replace its newer token/expiry.
  if (oauthState === state && sequence > state.appliedRefresh) {
    state.accessToken = token;
    state.appliedRefresh = sequence;
  }
  return token;
}

async function googleAccessToken(state: OAuthState): Promise<AccessToken> {
  if (state.accessToken && state.accessToken.expiresAt > Date.now() + 60_000) return state.accessToken;
  // Never share an unfinished fetch Promise across Workers request contexts.
  return refreshAccessToken(state);
}

export async function getPurchase(env: Env, token: string, subscription: boolean): Promise<unknown> {
  const state = credentials(env);
  const access = await googleAccessToken(state);
  const resource = subscription ? 'subscriptionsv2' : 'productsv2';
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(env.PACKAGE_NAME)}/purchases/${resource}/tokens/${encodeURIComponent(token)}`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${access.value}` }, signal: AbortSignal.timeout(10_000),
  });
  // A delayed rejection of an older token must not discard a concurrent refresh.
  if (response.status === 401 && state.accessToken?.value === access.value) state.accessToken = undefined;
  // An unrecognized token is not evidence that a previously issued entitlement was revoked.
  if ([400, 404, 410].includes(response.status)) throw new ApiError(422, 'purchase_unavailable');
  if (!response.ok) throw new ApiError(503, 'verification_unavailable');
  return response.json();
}
