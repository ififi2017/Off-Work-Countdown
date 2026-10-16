import { createPublicKey } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

/** Public receipt keys only. Never read a signing key or print configuration values. */
export function validateReceiptKeys(raw, expectedKeyId) {
  if (!raw?.trim()) throw new Error('Android release requires receipt verification public keys.');
  let keys;
  try { keys = JSON.parse(raw); } catch { throw new Error('Receipt public keys must be valid JSON.'); }
  if (!keys || Array.isArray(keys) || typeof keys !== 'object' || !Object.hasOwn(keys, expectedKeyId)) {
    throw new Error('Receipt public keys must include the deployed signing key ID.');
  }
  for (const [id, value] of Object.entries(keys)) {
    if (!/^[a-zA-Z0-9._-]{1,100}$/.test(id) || typeof value !== 'string' ||
        !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw new Error('Invalid receipt public-key entry.');
    try {
      const bytes = Buffer.from(value, 'base64');
      if (bytes.toString('base64') !== value) throw new Error();
      const key = createPublicKey({ key: bytes, format: 'der', type: 'spki' });
      if (key.asymmetricKeyType !== 'rsa' || (key.asymmetricKeyDetails?.modulusLength ?? 0) < 2048) throw new Error();
    } catch { throw new Error('Receipt keys must be RSA public SPKI keys of at least 2048 bits.'); }
  }
  return Object.keys(keys);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = JSON.parse(readFileSync(new URL('../services/billing-api/wrangler.jsonc', import.meta.url), 'utf8'));
    const ids = validateReceiptKeys(process.env.ORG_GRADLE_PROJECT_doneatBillingApiPublicKeys, config.vars.SIGNING_KEY_ID);
    console.log(`Android receipt verification configured (${ids.length} public key IDs).`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
