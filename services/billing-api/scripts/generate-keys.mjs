import { generateKeyPairSync } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const directory = fileURLToPath(new URL('../.secrets/', import.meta.url));
mkdirSync(directory, { recursive: true, mode: 0o700 });
const keys = generateKeyPairSync('rsa', { modulusLength: 2048 });
// Refuse to overwrite a deployed identity. Rotate deliberately with a new kid.
writeFileSync(`${directory}/entitlement-private.pem`, keys.privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600, flag: 'wx' });
const publicKey = keys.publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
writeFileSync(`${directory}/android-public-keys.json`, JSON.stringify({ 'billing-2026-01': publicKey }) + '\n', { mode: 0o600, flag: 'wx' });
console.log('Created .secrets/entitlement-private.pem and .secrets/android-public-keys.json. No key was printed.');
