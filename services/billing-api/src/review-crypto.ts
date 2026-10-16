import { exportJWK, importPKCS8, SignJWT } from 'jose';
import { ApiError, type Env } from './types';

export const REVIEW_TYPE = 'doneat-review-access+jwt';
export const REVIEW_AUDIENCE = 'com.rainif.doneat:review-access';
const encoder = new TextEncoder();
export function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
export function randomSecret(): string { return base64url(crypto.getRandomValues(new Uint8Array(32))); }
export async function hashBytes(bytes: Uint8Array): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes as BufferSource))]
    .map(byte => byte.toString(16).padStart(2, '0')).join('');
}
// DER SPKI for id-ecPublicKey + prime256v1 + uncompressed 65-byte point.
const P256_PREFIX = '3059301306072a8648ce3d020106082a8648ce3d03010703420004';
export async function installationKey(value: unknown): Promise<{ spki: string; hash: string; key: CryptoKey }> {
  if (typeof value !== 'string' || !/^[A-Za-z0-9+/]{122}==$/.test(value)) throw new ApiError(400, 'invalid_installation_key');
  let bytes: Uint8Array;
  try { bytes = Uint8Array.from(atob(value), char => char.charCodeAt(0)); }
  catch { throw new ApiError(400, 'invalid_installation_key'); }
  const prefix = [...bytes.slice(0, 27)].map(byte => byte.toString(16).padStart(2, '0')).join('');
  if (bytes.length !== 91 || prefix !== P256_PREFIX || btoa(String.fromCharCode(...bytes)) !== value) throw new ApiError(400, 'invalid_installation_key');
  try {
    const key = await crypto.subtle.importKey('spki', bytes, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
    return { spki: value, hash: await hashBytes(bytes), key };
  } catch { throw new ApiError(400, 'invalid_installation_key'); }
}
export function proofMessage(operation: string, challengeId: string, challengeNonce: string, keyHash: string, nonce: string): string {
  return ['doneat-review-access-v1', operation, challengeId, challengeNonce, keyHash, nonce].join('\n');
}
/** Strict ASN.1 DER ECDSA -> WebCrypto IEEE P1363. Reject noncanonical integers/trailing bytes. */
export function derSignature(value: unknown): Uint8Array {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{11,96}$/.test(value)) throw new ApiError(401, 'invalid_proof');
  let der: Uint8Array;
  try { der = Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - value.length % 4) % 4)), c => c.charCodeAt(0)); }
  catch { throw new ApiError(401, 'invalid_proof'); }
  if (base64url(der) !== value || der[0] !== 0x30 || der[1] !== der.length - 2) throw new ApiError(401, 'invalid_proof');
  let offset = 2;
  const result = new Uint8Array(64);
  for (let part = 0; part < 2; part++) {
    if (der[offset++] !== 2) throw new ApiError(401, 'invalid_proof');
    const length = der[offset++];
    if (!length || length > 33 || offset + length > der.length) throw new ApiError(401, 'invalid_proof');
    let bytes = der.slice(offset, offset + length); offset += length;
    if (bytes[0] & 0x80 || (length > 1 && bytes[0] === 0 && !(bytes[1] & 0x80))) throw new ApiError(401, 'invalid_proof');
    if (bytes[0] === 0) bytes = bytes.slice(1);
    if (bytes.length > 32) throw new ApiError(401, 'invalid_proof');
    result.set(bytes, (part + 1) * 32 - bytes.length);
  }
  if (offset !== der.length) throw new ApiError(401, 'invalid_proof');
  return result;
}
export async function verifyProof(key: CryptoKey, signature: unknown, message: string): Promise<void> {
  const valid = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, derSignature(signature) as BufferSource, encoder.encode(message));
  if (!valid) throw new ApiError(401, 'invalid_proof');
}
let signingKey: { pem: string; purchasePem?: string; key: Promise<CryptoKey> } | undefined;
export async function reviewSigningKey(env: Env): Promise<CryptoKey> {
  if (signingKey?.pem !== env.REVIEW_PRIVATE_KEY || signingKey?.purchasePem !== env.ENTITLEMENT_PRIVATE_KEY) {
    const key = (async () => {
      try {
        const review = await importPKCS8(env.REVIEW_PRIVATE_KEY!, 'RS256', { extractable: true });
        if ((review.algorithm as unknown as { modulusLength: number }).modulusLength < 2048) throw new Error('weak');
        if (env.ENTITLEMENT_PRIVATE_KEY) {
          const billing = await importPKCS8(env.ENTITLEMENT_PRIVATE_KEY, 'RS256', { extractable: true });
          const [reviewJwk, billingJwk] = await Promise.all([exportJWK(review), exportJWK(billing)]);
          if (reviewJwk.n === billingJwk.n && reviewJwk.e === billingJwk.e) throw new Error('shared');
        }
        return review;
      } catch { throw new ApiError(503, 'review_not_configured'); }
    })();
    signingKey = { pem: env.REVIEW_PRIVATE_KEY!, purchasePem: env.ENTITLEMENT_PRIVATE_KEY, key };
  }
  return signingKey!.key;
}
export async function signReviewGrant(env: Env, installationId: string, keyHash: string, credentialRevision: number, nonce: string, now: number): Promise<string> {
  const key = await reviewSigningKey(env);
  return new SignJWT({ v: 1, purpose: 'app-review', scope: 'plus', credentialRevision, installationKeyHash: keyHash, serverTimeMs: now, nonce })
    .setProtectedHeader({ alg: 'RS256', typ: REVIEW_TYPE, kid: env.REVIEW_SIGNING_KEY_ID! })
    .setIssuer(env.ISSUER).setAudience(REVIEW_AUDIENCE).setSubject(installationId)
    .setIssuedAt(Math.floor(now / 1000)).setExpirationTime(Math.floor(now / 1000) + 86_400).sign(key);
}
