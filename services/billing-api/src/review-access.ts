import { ApiError, boundedString, sha256, type Env } from './types';
import { installationKey, proofMessage, randomSecret, reviewSigningKey, signReviewGrant, verifyProof } from './review-crypto';
export const REVIEW_PREFIX = '/v1/review-access/';
const RETENTION_MS = 7 * 86_400_000;
interface Credential { credential_hash: string; revision: number }
interface Installation { installation_id: string; credential_hash: string; credential_revision: number; key_hash: string }
interface Challenge { credential_hash: string; credential_revision: number; installation_id: string | null }
function denied(): never { throw new ApiError(401, 'review_access_denied'); }
function exact(body: Record<string, unknown>, allowed: string[]): void {
  if (Object.keys(body).length !== allowed.length || Object.keys(body).some(key => !allowed.includes(key))) throw new ApiError(400, 'invalid_request');
}
function nonce(value: unknown): string {
  const result = boundedString(value, 128);
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(result)) throw new ApiError(400, 'invalid_request');
  return result;
}
function uuid(value: unknown): string {
  const result = boundedString(value, 36);
  if (!/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(result)) throw new ApiError(400, 'invalid_request');
  return result;
}
export function normalizeCredential(value: unknown): string {
  if (typeof value !== 'string' || value.length > 80 || !/^[A-Za-z2-7 -]+$/.test(value)) denied();
  const normalized = value.replace(/[ -]/g, '').toUpperCase();
  if (!/^[A-Z2-7]{32}$/.test(normalized)) denied();
  return normalized;
}
export async function requireReviewConfiguration(env: Env): Promise<void> {
  if (env.REVIEW_ACCESS_ENABLED !== 'true') throw new ApiError(503, 'review_access_disabled');
  if (!env.REVIEW_PRIVATE_KEY || !env.REVIEW_SIGNING_KEY_ID || !/^review-[A-Za-z0-9_-]{1,80}$/.test(env.REVIEW_SIGNING_KEY_ID) ||
      env.REVIEW_SIGNING_KEY_ID === env.SIGNING_KEY_ID || env.REVIEW_PRIVATE_KEY === env.ENTITLEMENT_PRIVATE_KEY ||
      env.PACKAGE_NAME !== 'com.rainif.doneat' || env.ISSUER !== 'https://api.doneat.app' || !env.REVIEW_AUTH_LIMIT || !env.REVIEW_INSTALL_LIMIT) {
    throw new ApiError(503, 'review_not_configured');
  }
  await reviewSigningKey(env);
}
export async function handleReviewAccess(body: Record<string, unknown>, route: string, env: Env, now = Date.now()): Promise<Record<string, unknown>> {
  if (route === 'challenge') {
    const operation = body.operation;
    if (typeof operation !== 'string' || !['activate', 'renew', 'exit'].includes(operation)) throw new ApiError(400, 'invalid_request');
    exact(body, operation === 'activate' ? ['operation', 'publicKeySpki', 'nonce', 'credential'] : ['operation', 'publicKeySpki', 'nonce', 'installationId', 'renewalSecret']);
    const requestNonce = nonce(body.nonce); const key = await installationKey(body.publicKeySpki);
    // No IP buckets: independent reviewers may share the same Google egress.
    if (!(await env.REVIEW_INSTALL_LIMIT!.limit({ key: key.hash })).success) throw new ApiError(429, 'rate_limited');
    let credentialHash: string; let credentialRevision: number; let installationId: string | null = null;
    if (operation === 'activate') {
      credentialHash = await sha256(normalizeCredential(body.credential));
      if (!(await env.REVIEW_AUTH_LIMIT!.limit({ key: credentialHash })).success) throw new ApiError(429, 'rate_limited');
      const credential = await env.DB.prepare('SELECT credential_hash, revision FROM review_credentials WHERE credential_hash = ? AND revoked = 0').bind(credentialHash).first<Credential>();
      if (!credential) denied();
      credentialRevision = credential.revision;
    } else {
      installationId = uuid(body.installationId); const renewal = boundedString(body.renewalSecret, 43);
      if (!/^[A-Za-z0-9_-]{43}$/.test(renewal)) denied();
      if (!(await env.REVIEW_AUTH_LIMIT!.limit({ key: installationId })).success) throw new ApiError(429, 'rate_limited');
      const installation = await env.DB.prepare(`SELECT i.* FROM review_installations i JOIN review_credentials c USING(credential_hash)
        WHERE i.installation_id = ? AND i.renewal_hash = ? AND i.key_hash = ? AND i.revoked = 0
        AND i.last_renewed_at_ms > ? AND c.revoked = 0 AND c.revision = i.credential_revision`)
        .bind(installationId, await sha256(renewal), key.hash, now - RETENTION_MS).first<Installation>();
      if (!installation) denied();
      credentialHash = installation.credential_hash; credentialRevision = installation.credential_revision;
    }
    const challengeId = crypto.randomUUID(); const challengeNonce = randomSecret();
    await env.DB.prepare(`INSERT INTO review_challenges(challenge_id, nonce_hash, operation, key_hash, request_nonce,
      credential_hash, credential_revision, installation_id, expires_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(challengeId, await sha256(challengeNonce), operation, key.hash, requestNonce, credentialHash, credentialRevision, installationId, now + 60_000).run();
    return { challengeId, challengeNonce, expiresAtMs: now + 60_000, serverTimeMs: now };
  }
  if (!['activate', 'renew', 'exit'].includes(route)) throw new ApiError(404, 'not_found');
  exact(body, ['challengeId', 'challengeNonce', 'publicKeySpki', 'nonce', 'signature']);
  const challengeId = uuid(body.challengeId); const challengeNonce = nonce(body.challengeNonce); const requestNonce = nonce(body.nonce);
  const key = await installationKey(body.publicKeySpki);
  if (!(await env.REVIEW_INSTALL_LIMIT!.limit({ key: key.hash })).success) throw new ApiError(429, 'rate_limited');
  await verifyProof(key.key, body.signature, proofMessage(route, challengeId, challengeNonce, key.hash, requestNonce));
  // DELETE RETURNING chooses one atomic winner across isolates; failed proofs do not consume.
  const challenge = await env.DB.prepare(`DELETE FROM review_challenges WHERE challenge_id = ? AND nonce_hash = ?
    AND operation = ? AND key_hash = ? AND request_nonce = ? AND expires_at_ms > ? RETURNING *`)
    .bind(challengeId, await sha256(challengeNonce), route, key.hash, requestNonce, now).first<Challenge>();
  if (!challenge) denied();
  const activeCredential = `EXISTS (SELECT 1 FROM review_credentials c WHERE c.credential_hash = ? AND c.revision = ? AND c.revoked = 0)`;
  let installationId = challenge.installation_id; let renewalSecret: string | undefined;
  if (route === 'activate') {
    installationId = crypto.randomUUID(); renewalSecret = randomSecret();
    const created = await env.DB.prepare(`INSERT INTO review_installations(installation_id, credential_hash, credential_revision,
      public_key_spki, key_hash, renewal_hash, last_renewed_at_ms) SELECT ?, ?, ?, ?, ?, ?, ? WHERE ${activeCredential} RETURNING installation_id`)
      .bind(installationId, challenge.credential_hash, challenge.credential_revision, key.spki, key.hash, await sha256(renewalSecret), now,
        challenge.credential_hash, challenge.credential_revision).first();
    if (!created) denied();
  } else {
    const guard = `installation_id = ? AND key_hash = ? AND credential_hash = ? AND credential_revision = ?
      AND revoked = 0 AND last_renewed_at_ms > ? AND ${activeCredential}`;
    const args = [installationId, key.hash, challenge.credential_hash, challenge.credential_revision, now - RETENTION_MS, challenge.credential_hash, challenge.credential_revision];
    const result = route === 'exit'
      ? await env.DB.prepare(`DELETE FROM review_installations WHERE ${guard} RETURNING installation_id`).bind(...args).first()
      : await env.DB.prepare(`UPDATE review_installations SET last_renewed_at_ms = ? WHERE ${guard} RETURNING installation_id`).bind(now, ...args).first();
    if (!result) denied();
    if (route === 'exit') return { exited: true, serverTimeMs: now };
  }
  return { grant: await signReviewGrant(env, installationId!, key.hash, challenge.credential_revision, requestNonce, now), installationId,
    ...(renewalSecret ? { renewalSecret } : {}), serverTimeMs: now };
}
export async function cleanupReviewAccess(db: D1Database, now = Date.now()): Promise<void> {
  await db.batch([
    db.prepare('DELETE FROM review_challenges WHERE expires_at_ms <= ?').bind(now),
    db.prepare('DELETE FROM review_installations WHERE last_renewed_at_ms <= ?').bind(now - RETENTION_MS),
  ]);
}
