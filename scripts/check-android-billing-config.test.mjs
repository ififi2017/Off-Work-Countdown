import { generateKeyPairSync } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { validateReceiptKeys, validateReviewKeys } from './check-android-billing-config.mjs';

const rsa = generateKeyPairSync('rsa', { modulusLength: 2048 });
const publicKey = rsa.publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
const kid = 'billing-2026-01';

describe('Android release receipt configuration', () => {
  it('requires configured, parseable keys and the deployed identity', () => {
    for (const value of ['', ' ', '{', 'null', '[]', '{}', JSON.stringify({ old: publicKey })]) {
      expect(() => validateReceiptKeys(value, kid)).toThrow();
    }
  });
  it('accepts the current public identity and retained rotation keys', () => {
    expect(validateReceiptKeys(JSON.stringify({ [kid]: publicKey, old: publicKey }), kid)).toEqual([kid, 'old']);
  });
  it('rejects malformed data and private key material', () => {
    const privateKey = rsa.privateKey.export({ type: 'pkcs8', format: 'der' }).toString('base64');
    for (const value of [null, 1, 'not a key', privateKey, publicKey + '!', publicKey.slice(1)]) {
      expect(() => validateReceiptKeys(JSON.stringify({ [kid]: value }), kid)).toThrow();
    }
  });
  it('rejects unsupported algorithms and weak RSA keys', () => {
    for (const key of [generateKeyPairSync('ed25519').publicKey,
      generateKeyPairSync('rsa', { modulusLength: 1024 }).publicKey]) {
      expect(() => validateReceiptKeys(JSON.stringify({ [kid]: key.export({ type: 'spki', format: 'der' }).toString('base64') }), kid)).toThrow();
    }
  });
});

describe('Review key separation', () => {
  it('requires independent key identities even under a different kid', () => {
    const billing = JSON.stringify({ [kid]: publicKey });
    expect(() => validateReviewKeys(JSON.stringify({ 'review-test': publicKey }), 'review-test', billing)).toThrow();
    const other = generateKeyPairSync('rsa', { modulusLength: 2048 }).publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
    expect(validateReviewKeys(JSON.stringify({ 'review-test': other }), 'review-test', billing)).toEqual(['review-test']);
    expect(() => validateReviewKeys(JSON.stringify({ [kid]: other }), kid, billing)).toThrow();
    expect(() => validateReviewKeys('', 'review-test', billing)).toThrow();
  });
});
