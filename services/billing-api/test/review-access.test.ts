import javaProof from './fixtures/java-p256-proof.json';
import joseGrant from './fixtures/jose-rs256-grant.json';
import { importSPKI } from 'jose';
import { env } from 'cloudflare:workers';
import { applyD1Migrations, type D1Migration } from 'cloudflare:test';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { exportPKCS8, generateKeyPair, jwtVerify } from 'jose';
import worker from '../src/index';
import { cleanupReviewAccess, handleReviewAccess } from '../src/review-access';
import { base64url, derSignature, installationKey, proofMessage, verifyProof, REVIEW_AUDIENCE, REVIEW_TYPE } from '../src/review-crypto';
import { sha256, type Env } from '../src/types';
const bindings = env as unknown as Env & { TEST_MIGRATIONS: D1Migration[] };
const code = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; // synthetic, isolated D1 only
const nonce = 'synthetic_nonce_1234567890';
let config: Env; let rsa: Awaited<ReturnType<typeof generateKeyPair>>; let ec: CryptoKeyPair; let spki: string;
function der(raw: Uint8Array): Uint8Array {
  const parts = [raw.slice(0, 32), raw.slice(32)].map(part => {
    while (part.length > 1 && part[0] === 0) part = part.slice(1);
    if (part[0] & 128) part = new Uint8Array([0, ...part]);
    return new Uint8Array([2, part.length, ...part]);
  });
  return new Uint8Array([48, parts[0].length + parts[1].length, ...parts[0], ...parts[1]]);
}
function request(body: unknown, route = 'challenge', url?: string) {
  return new Request(url ?? `https://api.doneat.app/v1/review-access/${route}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
}
async function call(body: Record<string, unknown>, route = 'challenge', at?: number) { return handleReviewAccess(body, route, config, at); }
async function challenge(operation = 'activate', session?: Record<string, unknown>, key = spki, at?: number) {
  return call({ operation, publicKeySpki: key, nonce, ...(operation === 'activate' ? { credential: code } : { installationId: session!.installationId, renewalSecret: session!.renewalSecret }) }, 'challenge', at);
}
async function proof(c: Record<string, unknown>, operation = 'activate', keys = ec, publicKeySpki = spki, requestNonce = nonce) {
  const hash = (await installationKey(publicKeySpki)).hash;
  const message = proofMessage(operation, String(c.challengeId), String(c.challengeNonce), hash, requestNonce);
  const raw = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, keys.privateKey, new TextEncoder().encode(message)));
  return { challengeId: c.challengeId, challengeNonce: c.challengeNonce, nonce: requestNonce, publicKeySpki, signature: base64url(der(raw)) };
}
async function activate(at?: number) { return call(await proof(await challenge('activate', undefined, spki, at)), 'activate', at); }
async function error(p: Promise<unknown>, status = 401) { await expect(p).rejects.toMatchObject({ status }); }
beforeAll(async () => {
  await applyD1Migrations(bindings.DB, bindings.TEST_MIGRATIONS);
  rsa = await generateKeyPair('RS256', { extractable: true });
  ec = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
  spki = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey('spki', ec.publicKey) as ArrayBuffer)));
  config = { ...bindings, REVIEW_ACCESS_ENABLED: 'true', REVIEW_PRIVATE_KEY: await exportPKCS8(rsa.privateKey), REVIEW_SIGNING_KEY_ID: 'review-test-1',
    REVIEW_AUTH_LIMIT: { limit: async () => ({ success: true }) }, REVIEW_INSTALL_LIMIT: { limit: async () => ({ success: true }) } };
});
beforeEach(async () => {
  await bindings.DB.batch(['review_challenges', 'review_installations', 'review_credentials', 'purchases'].map(t => bindings.DB.prepare(`DELETE FROM ${t}`)));
  await bindings.DB.prepare('INSERT INTO review_credentials(credential_hash, revision, created_at_ms) VALUES (?, 1, ?)').bind(await sha256(code), Date.now()).run();
});
describe('isolated review grants', () => {
  it('normalizes a reusable base32 credential and creates independent installation sessions without Google calls', async () => {
    const network = vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('No upstream allowed'));
    try {
      const c = await call({ operation: 'activate', publicKeySpki: spki, nonce, credential: 'abcd efgh-ijkl-mnop-qrst-uvwx-yz23-4567' });
      const first = await call(await proof(c), 'activate'); const second = await activate();
      expect(first.installationId).not.toBe(second.installationId);
      expect(first.renewalSecret).toMatch(/^[A-Za-z0-9_-]{43}$/);
      expect(first.renewalSecret).not.toBe(second.renewalSecret);
      expect(network).not.toHaveBeenCalled();
      const stored = JSON.stringify(await config.DB.prepare('SELECT * FROM review_installations').all());
      expect(stored).not.toContain(String(first.renewalSecret)); expect(stored).not.toContain(code); expect(stored).not.toContain(String(first.grant));
    } finally { network.mockRestore(); }
  });
  it('signs a strictly separate 24h RS256 lease with SPKI hash, nonce and exact server time', async () => {
    const at = 1_800_000_000_123; const result = await activate(at);
    const { payload, protectedHeader } = await jwtVerify(String(result.grant), rsa.publicKey, { algorithms: ['RS256'], issuer: config.ISSUER, audience: REVIEW_AUDIENCE, typ: REVIEW_TYPE, currentDate: new Date(at) });
    expect(protectedHeader).toEqual({ alg: 'RS256', typ: REVIEW_TYPE, kid: 'review-test-1' });
    expect(payload).toMatchObject({ v: 1, purpose: 'app-review', scope: 'plus', sub: result.installationId, installationKeyHash: (await installationKey(spki)).hash, credentialRevision: 1, nonce, serverTimeMs: at });
    expect(payload.exp! - payload.iat!).toBe(86400); expect(result.serverTimeMs).toBe(payload.serverTimeMs);
    await expect(jwtVerify(String(result.grant), rsa.publicKey, { audience: config.PACKAGE_NAME, typ: 'JWT', currentDate: new Date(at) })).rejects.toThrow();
  });
  it('renews using installation secret and proof, never the shared code; exit deletes only that installation', async () => {
    const result = await activate(); const other = await activate();
    const renewed = await call(await proof(await challenge('renew', result), 'renew'), 'renew');
    expect(renewed.installationId).toBe(result.installationId); expect(renewed.renewalSecret).toBeUndefined();
    expect(await call(await proof(await challenge('exit', result), 'exit'), 'exit')).toMatchObject({ exited: true });
    await error(challenge('renew', result)); expect(await challenge('renew', other)).toHaveProperty('challengeId');
  });
  it('rejects unknown, revoked and revision-changed credentials including challenges already issued', async () => {
    const c = await challenge(); const body = await proof(c);
    await config.DB.prepare('UPDATE review_credentials SET revision = revision + 1').run();
    await error(call(body, 'activate'));
    await config.DB.prepare('UPDATE review_credentials SET revoked = 1').run(); await error(challenge());
    await error(call({ operation: 'activate', publicKeySpki: spki, nonce, credential: 'A'.repeat(32) }));
  });
  it('rejects revoked installations and credentials at renewal challenge and completion', async () => {
    const session = await activate(); const c = await challenge('renew', session);
    await config.DB.prepare('UPDATE review_installations SET revoked = 1').run();
    await error(call(await proof(c, 'renew'), 'renew')); await error(challenge('renew', session));
    await config.DB.prepare('UPDATE review_installations SET revoked = 0').run();
    const c2 = await challenge('renew', session); await config.DB.prepare('UPDATE review_credentials SET revoked = 1').run();
    await error(call(await proof(c2, 'renew'), 'renew')); await error(challenge('renew', session));
  });
  it('atomically permits one response when the same signed challenge is submitted concurrently', async () => {
    const body = await proof(await challenge());
    const results = await Promise.allSettled([call(body, 'activate'), call(body, 'activate')]);
    expect(results.filter(r => r.status === 'fulfilled')).toHaveLength(1);
    expect((await config.DB.prepare('SELECT * FROM review_installations').all()).results).toHaveLength(1);
  });
  it('rejects expired challenges at exactly 60s, replay, cross-operation and changed nonce', async () => {
    const now = Date.now(); const c = await challenge('activate', undefined, spki, now);
    await error(call(await proof(c), 'activate', now + 60_000));
    const fresh = await challenge(); await error(call(await proof(fresh, 'renew'), 'renew'));
    await error(call(await proof(fresh, 'activate', ec, spki, 'changed_request_nonce_1234'), 'activate'));
    const body = await proof(fresh); await call(body, 'activate'); await error(call(body, 'activate'));
  });
  it('rejects another public key even with a valid signature and copied installation secret', async () => {
    const other = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
    const otherSpki = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey('spki', other.publicKey) as ArrayBuffer)));
    const c = await challenge(); await error(call(await proof(c, 'activate', other, otherSpki), 'activate'));
    const session = await activate(); await error(challenge('renew', session, otherSpki));
    await error(challenge('renew', { ...session, renewalSecret: 'A'.repeat(43) }));
  });
  it('does not consume a challenge after a bad signature', async () => {
    const c = await challenge(); const body = await proof(c);
    await error(call({ ...body, signature: base64url(der(new Uint8Array(64).fill(1))) }, 'activate'));
    expect(await call(body, 'activate')).toHaveProperty('grant');
  });
  it('enforces seven-day idle retention at reads and deletes expired metadata without touching purchases or credentials', async () => {
    const at = Date.now(); const result = await activate(at); await challenge('activate', undefined, spki, at);
    await config.DB.prepare("INSERT INTO purchases(token_hash,product_id,kind,status,verified_at_ms) VALUES ('real-order','doneat_plus','subscription','active',?)").bind(at).run();
    await error(challenge('renew', result, spki, at + 7 * 86_400_000));
    await cleanupReviewAccess(config.DB, at + 7 * 86_400_000);
    expect((await config.DB.prepare('SELECT * FROM review_installations').all()).results).toHaveLength(0);
    expect((await config.DB.prepare('SELECT * FROM review_challenges').all()).results).toHaveLength(0);
    expect((await config.DB.prepare('SELECT * FROM purchases').all()).results).toHaveLength(1);
    expect((await config.DB.prepare('SELECT * FROM review_credentials').all()).results).toHaveLength(1);
    expect(await challenge('activate', undefined, spki, at + 8 * 86_400_000)).toHaveProperty('challengeId');
  });
});
describe('review HTTP and crypto boundaries', () => {
  it('accepts a real Java SunEC SHA256withECDSA DER fixture and jose RS256 grant fixture', async () => {
    const imported = await installationKey(javaProof.publicKeySpki);
    expect(imported.hash).toBe(javaProof.installationKeyHash);
    expect(proofMessage(javaProof.operation, javaProof.challengeId, javaProof.challengeNonce, imported.hash, javaProof.nonce)).toBe(javaProof.message);
    await verifyProof(imported.key, javaProof.signature, javaProof.message);
    await error(verifyProof(imported.key, javaProof.signature, javaProof.message + '\n'));
    const pem = '-----BEGIN PUBLIC KEY-----\n' + joseGrant.publicKeys['review-interop-fixture'] + '\n-----END PUBLIC KEY-----';
    const key = await importSPKI(pem, 'RS256');
    const verified = await jwtVerify(joseGrant.grant, key, { algorithms: ['RS256'], issuer: config.ISSUER, audience: REVIEW_AUDIENCE, typ: REVIEW_TYPE, currentDate: new Date(joseGrant.serverTimeMs) });
    expect(verified.payload.nonce).toBe(joseGrant.nonce);
    expect(verified.payload.installationKeyHash).toBe(javaProof.installationKeyHash);
  });
  it('deleting a credential atomically cascades sessions/challenges and keeps unrelated data', async () => {
    await activate(); await challenge();
    await config.DB.prepare('DELETE FROM review_credentials WHERE credential_hash = ?').bind(await sha256(code)).run();
    for (const table of ['review_credentials', 'review_installations', 'review_challenges']) {
      expect((await config.DB.prepare(`SELECT * FROM ${table}`).all()).results).toHaveLength(0);
    }
    await error(challenge());
  });
  it('defaults disabled and rejects missing, shared or purchase signing identities', async () => {
    const body = { operation: 'activate', credential: code, publicKeySpki: spki, nonce };
    for (const overrides of [{ REVIEW_ACCESS_ENABLED: 'false' }, { REVIEW_PRIVATE_KEY: '' }, { REVIEW_SIGNING_KEY_ID: 'billing-2026-01' }, { ENTITLEMENT_PRIVATE_KEY: config.REVIEW_PRIVATE_KEY! }, { ENTITLEMENT_PRIVATE_KEY: config.REVIEW_PRIVATE_KEY! + '\n' }]) {
      const r = await worker.fetch(request(body), { ...config, ...overrides }); expect(r.status).toBe(503); expect(r.headers.get('Cache-Control')).toBe('no-store');
    }
  });
  it('requires HTTPS, POST, JSON, no query, no extra fields, bounded streamed bodies and no CORS', async () => {
    expect((await worker.fetch(request({}, 'challenge', 'http://api.doneat.app/v1/review-access/challenge'), config)).status).toBe(400);
    expect((await worker.fetch(request({}, 'challenge', 'https://api.doneat.app/v1/review-access/challenge?code=x'), config)).status).toBe(400);
    expect((await worker.fetch(new Request('https://api.doneat.app/v1/review-access/challenge'), config)).status).toBe(405);
    expect((await worker.fetch(new Request('https://api.doneat.app/v1/review-access/challenge', { method: 'POST', body: '{}' }), config)).status).toBe(415);
    const wrongType = request({}); wrongType.headers.set('Content-Type', 'application/jsonp');
    expect((await worker.fetch(wrongType, config)).status).toBe(415);
    await error(call({ operation: ['activate'], publicKeySpki: spki, nonce, credential: code }), 400);
    const r = await worker.fetch(request({ operation: 'activate', credential: code, nonce, publicKeySpki: spki, salary: 123 }), config);
    expect(r.status).toBe(400); expect(r.headers.get('Access-Control-Allow-Origin')).toBeNull();
    expect((await worker.fetch(request({ data: 'x'.repeat(20_000) }), config)).status).toBe(413);
  });
  it('enforces per-installation and auth limits with sanitized errors', async () => {
    for (const name of ['REVIEW_AUTH_LIMIT', 'REVIEW_INSTALL_LIMIT']) {
      const response = await worker.fetch(request({ operation: 'activate', credential: code, nonce, publicKeySpki: spki }), { ...config, [name]: { limit: async () => ({ success: false }) } });
      expect(response.status).toBe(429); expect(await response.json()).toEqual({ error: 'rate_limited' });
    }
  });
  it('supports many reviewers behind a shared IP without an IP bucket', async () => {
    const counts = new Map<string, number>();
    const limited = { ...config, REVIEW_INSTALL_LIMIT: { limit: async ({ key }: { key: string }) => {
      const count = (counts.get(key) ?? 0) + 1; counts.set(key, count); return { success: count <= 30 };
    } } };
    const bodies = await Promise.all(Array.from({ length: 40 }, async () => {
      const key = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
      const publicKeySpki = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey('spki', key.publicKey) as ArrayBuffer)));
      const req = request({ operation: 'activate', credential: code, nonce, publicKeySpki });
      req.headers.set('CF-Connecting-IP', '203.0.113.42');
      return worker.fetch(req, limited);
    }));
    expect(bodies.every(r => r.status === 200)).toBe(true);
  });
  it('rejects malformed public keys and malformed/noncanonical DER proof signatures', async () => {
    await error(installationKey('bad'), 400); await error(installationKey(spki.slice(0, -2)), 400);
    expect(() => derSignature(base64url(new Uint8Array([48, 6, 2, 1, 128, 2, 1, 1])))).toThrow();
    expect(() => derSignature(base64url(new Uint8Array([48, 7, 2, 2, 0, 1, 2, 1, 1])))).toThrow();
    expect(() => derSignature(base64url(new Uint8Array([48, 6, 2, 1, 1, 2, 1, 1, 0])))).toThrow();
  });
});
