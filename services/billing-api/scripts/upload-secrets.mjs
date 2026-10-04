import { readFileSync } from 'node:fs';
import { createPrivateKey } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import './check-deploy.mjs';

// Read local files and pipe directly to Wrangler; never print credentials or pass them in argv.
try {
  const source = process.argv[2];
  if (!source) throw new Error('Usage: npm run secrets -- /absolute/path/to/google-service-account.json');
  const config = JSON.parse(readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8'));
  const google = JSON.parse(readFileSync(source, 'utf8'));
  if (google.type !== 'service_account' || google.client_email !== config.vars.GOOGLE_SERVICE_ACCOUNT_EMAIL) {
    throw new Error('The Google JSON does not match the configured billing service account.');
  }
  const signing = readFileSync(new URL('../.secrets/entitlement-private.pem', import.meta.url), 'utf8');
  if (createPrivateKey(google.private_key).asymmetricKeyType !== 'rsa' || createPrivateKey(signing).asymmetricKeyType !== 'rsa') {
    throw new Error('Both private keys must be RSA keys.');
  }
  const result = spawnSync(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'secret', 'bulk'], {
    cwd: fileURLToPath(new URL('../', import.meta.url)),
    input: JSON.stringify({ GOOGLE_PRIVATE_KEY: google.private_key, ENTITLEMENT_PRIVATE_KEY: signing }),
    stdio: ['pipe', 'inherit', 'inherit'], env: { ...process.env, WRANGLER_SEND_METRICS: 'false' },
  });
  process.exitCode = result.status ?? 1;
} catch (error) {
  // Only our fixed messages are safe; parser/crypto errors can contain fragments of the source.
  const safe = ['Usage:', 'The Google JSON', 'Both private keys'];
  console.error(safe.some(prefix => error.message?.startsWith(prefix)) ? error.message : 'Could not read or validate the local key files. No secrets were uploaded.');
  process.exitCode = 1;
}
