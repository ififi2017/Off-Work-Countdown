// Operator tool: all raw material goes directly to a private file, never stdout/CLI args.
import { randomBytes, createHash, generateKeyPairSync, createPublicKey, createPrivateKey } from 'node:crypto';
import { closeSync, existsSync, lstatSync, mkdirSync, openSync, readFileSync, realpathSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = fileURLToPath(new URL('../', import.meta.url));
const sha = value => createHash('sha256').update(value).digest('hex');
function fail() { throw new Error('Invalid operator input or operation failed; no secret material printed.'); }
function argument(name) { const i = process.argv.indexOf(name); if (i < 0 || !process.argv[i + 1]) fail(); return process.argv[i + 1]; }
function safeDirectory(path) {
  if (!isAbsolute(path)) fail();
  mkdirSync(path, { recursive: true, mode: 0o700 });
  // Keep private output outside the checkout, including through symlinks.
  const actual = realpathSync(path); const checkout = realpathSync(resolve(root, '../..'));
  if (!relative(checkout, actual).startsWith('..')) fail();
  if (lstatSync(actual).mode & 0o077) fail();
  return actual;
}
function privateWrite(path, value) {
  safeDirectory(dirname(path)); const fd = openSync(path, 'wx', 0o600);
  try { writeFileSync(fd, value); } finally { closeSync(fd); }
}
function privateRead(path) {
  if (!isAbsolute(path) || lstatSync(path).isSymbolicLink() || (lstatSync(path).mode & 0o077)) fail();
  return readFileSync(path, 'utf8');
}
function database(sql) {
  const local = process.argv.includes('--local'); const remote = process.argv.includes('--remote');
  if (local === remote) fail();
  // SQL only includes validated digests/UUIDs, never credentials or private keys.
  const result = spawnSync(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'd1', 'execute', 'billing', local ? '--local' : '--remote', '--command', sql],
    { cwd: root, stdio: ['ignore', 'ignore', 'ignore'], env: { ...process.env, WRANGLER_SEND_METRICS: 'false' } });
  if (result.status !== 0) fail();
}
const base32 = bytes => {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; let bits = 0; let value = 0; let out = '';
  for (const byte of bytes) { value = (value << 8) | byte; bits += 8; while (bits >= 5) { out += alphabet[(value >>> (bits - 5)) & 31]; bits -= 5; } }
  return out;
};
try {
  const command = process.argv[2];
  if (['create-credential', 'register-credential', 'revoke-credential', 'revoke-installation'].includes(command) &&
      process.argv.includes('--local') === process.argv.includes('--remote')) fail();
  if (command === 'keys') {
    const directory = safeDirectory(argument('--directory')); const kid = argument('--kid');
    if (!/^review-[A-Za-z0-9_-]{1,80}$/.test(kid)) fail();
    if (existsSync(`${directory}/review-private.pem`) || existsSync(`${directory}/android-review-public-keys.json`)) fail();
    const keys = generateKeyPairSync('rsa', { modulusLength: 2048 });
    privateWrite(`${directory}/review-private.pem`, keys.privateKey.export({ type: 'pkcs8', format: 'pem' }));
    privateWrite(`${directory}/android-review-public-keys.json`, JSON.stringify({ [kid]: keys.publicKey.export({ type: 'spki', format: 'der' }).toString('base64') }) + '\n');
  } else if (command === 'check-keys') {
    const privateKey = createPrivateKey(privateRead(argument('--private-file'))); const kid = argument('--kid');
    const map = JSON.parse(readFileSync(argument('--public-file'), 'utf8'));
    if (!/^review-[A-Za-z0-9_-]{1,80}$/.test(kid) || !map[kid] || privateKey.asymmetricKeyType !== 'rsa' || privateKey.asymmetricKeyDetails.modulusLength < 2048) fail();
    const actual = createPublicKey(privateKey).export({ type: 'spki', format: 'der' }).toString('base64');
    if (map[kid] !== actual) fail();
    const purchase = process.argv.includes('--purchase-public-file') ? JSON.parse(readFileSync(argument('--purchase-public-file'), 'utf8')) : {};
    if (Object.entries(purchase).some(([id, key]) => id === kid || key === actual)) fail();
  } else if (command === 'create-credential') {
    const path = argument('--file'); const raw = base32(randomBytes(20)); const hash = sha(raw); const createdAtMs = Date.now();
    privateWrite(path, JSON.stringify({ credential: raw.match(/.{4}/g).join('-'), credentialHash: hash, createdAtMs }, null, 2) + '\n');
    // If insertion fails, retain the protected file for an explicit retry with register-credential.
    database(`INSERT INTO review_credentials(credential_hash, revision, revoked, created_at_ms) VALUES ('${hash}', 1, 0, ${createdAtMs});`);
  } else if (command === 'register-credential' || command === 'revoke-credential') {
    const path = argument('--file');
    const file = JSON.parse(privateRead(path)); const normalized = String(file.credential).replace(/[ -]/g, '').toUpperCase();
    if (!/^[A-Z2-7]{32}$/.test(normalized) || file.credentialHash !== sha(normalized)) fail();
    const hash = file.credentialHash;
    if (command === 'register-credential') {
      if (file.revoked === true) fail();
      // Never reuse a revoked credential, even after its D1 digest has been deleted.
      database(`INSERT OR IGNORE INTO review_credentials(credential_hash, revision, revoked, created_at_ms) VALUES ('${hash}', 1, 0, ${Date.now()});`);
    } else {
      // Mark local material first: a failed DB call is retryable, but registering it is forbidden.
      if (file.revoked !== true) {
        const temporary = `${path}.revoked-${randomBytes(8).toString('hex')}`;
        privateWrite(temporary, JSON.stringify({ ...file, revoked: true, revokedAtMs: Date.now() }, null, 2) + '\n');
        renameSync(temporary, path);
      }
      // ON DELETE CASCADE atomically removes this credential's installations and challenges.
      database(`DELETE FROM review_credentials WHERE credential_hash = '${hash}';`);
    }
  } else if (command === 'revoke-installation') {
    const id = argument('--installation-id'); if (!/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(id)) fail();
    database(`UPDATE review_installations SET revoked = 1 WHERE installation_id = '${id}';`);
  } else fail();
  console.log('Review operator operation completed. No credential or private key was printed.');
} catch { console.error('Review operator operation failed. Check protected files, permissions and configuration. No secret was printed.'); process.exitCode = 1; }
