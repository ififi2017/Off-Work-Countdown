import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, chmodSync, existsSync, rmSync, statSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
let directory, checkout, privateDir, script, capture;
before(() => {
  directory = mkdtempSync(join(tmpdir(), 'doneat-review-admin-test-'));
  checkout = join(directory, 'checkout'); privateDir = join(directory, 'private');
  mkdirSync(join(checkout, 'services/billing-api/scripts'), { recursive: true });
  mkdirSync(join(checkout, 'services/billing-api/node_modules/wrangler/bin'), { recursive: true });
  mkdirSync(privateDir, { mode: 0o700 });
  script = join(checkout, 'services/billing-api/scripts/review-admin.mjs');
  capture = join(directory, 'captured-digest-only-sql.json');
  copyFileSync(new URL('../scripts/review-admin.mjs', import.meta.url), script);
  writeFileSync(join(checkout, 'services/billing-api/node_modules/wrangler/bin/wrangler.js'), "require('node:fs').writeFileSync(process.env.REVIEW_TEST_SQL_CAPTURE,JSON.stringify(process.argv.slice(2)));process.exit(process.env.REVIEW_TEST_FAIL_DB==='true'?1:0)");
});
after(() => rmSync(directory, { recursive: true, force: true }));
function run(args, extraEnv = {}) {
  return spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', env: { ...process.env, REVIEW_TEST_SQL_CAPTURE: capture, ...extraEnv } });
}
function localCode(name = 'code.json') {
  const path = join(privateDir, name); const result = run(['create-credential', '--file', path, '--local']);
  assert.equal(result.status, 0); return { path, file: JSON.parse(readFileSync(path, 'utf8')), result };
}
test('writes 160-bit grouped base32 only to private file; CLI/database receive only digest', () => {
  const { path, file, result } = localCode();
  const normalized = file.credential.replaceAll('-', ''); assert.match(normalized, /^[A-Z2-7]{32}$/);
  assert.equal(file.credentialHash, createHash('sha256').update(normalized).digest('hex'));
  assert.equal(statSync(path).mode & 0o777, 0o600);
  const sql = readFileSync(capture, 'utf8'); assert(!sql.includes(normalized)); assert(!sql.includes(file.credential));
  assert(sql.includes(file.credentialHash)); assert(!(result.stdout + result.stderr).includes(file.credential));
  assert.equal(run(['create-credential', '--file', path, '--local']).status, 1);
});
test('revoke marks file first and performs only atomic parent DELETE with schema cascade', () => {
  const { path, file } = localCode('revoke.json');
  assert.equal(run(['revoke-credential', '--file', path, '--local']).status, 0);
  assert.equal(JSON.parse(readFileSync(path, 'utf8')).revoked, true);
  assert.equal(JSON.parse(readFileSync(capture, 'utf8')).at(-1), `DELETE FROM review_credentials WHERE credential_hash = '${file.credentialHash}';`);
  assert.equal(run(['register-credential', '--file', path, '--local']).status, 1);
  assert.equal(run(['revoke-credential', '--file', path, '--local']).status, 0);
});
test('failed DB revocation cannot leave a locally reusable credential file; explicit retry works', () => {
  const { path } = localCode('retry.json');
  assert.equal(run(['revoke-credential', '--file', path, '--local'], { REVIEW_TEST_FAIL_DB: 'true' }).status, 1);
  assert.equal(JSON.parse(readFileSync(path, 'utf8')).revoked, true);
  assert.equal(run(['register-credential', '--file', path, '--local']).status, 1);
  assert.equal(run(['revoke-credential', '--file', path, '--local']).status, 0);
});
test('rejects output within checkout and insecure private directories without printing secrets', () => {
  const inside = join(checkout, 'must-not-exist.json');
  assert.equal(run(['create-credential', '--file', inside, '--local']).status, 1); assert(!existsSync(inside));
  const insecure = join(directory, 'insecure'); mkdirSync(insecure, { mode: 0o755 }); chmodSync(insecure, 0o755);
  assert.equal(run(['create-credential', '--file', join(insecure, 'code.json'), '--local']).status, 1);
});
test('requires explicit local/remote target and validates installation UUID against SQL injection', () => {
  const invalidOutput = join(privateDir, 'no-target.json');
  assert.equal(run(['create-credential', '--file', invalidOutput]).status, 1); assert(!existsSync(invalidOutput));
  assert.equal(run(['revoke-installation', '--installation-id', '00000000-0000-4000-8000-000000000001']).status, 1);
  assert.equal(run(['revoke-installation', '--installation-id', "x'; DELETE FROM purchases;--", '--local']).status, 1);
  assert.equal(run(['revoke-installation', '--installation-id', '00000000-0000-4000-8000-000000000001', '--local']).status, 0);
  assert(readFileSync(capture, 'utf8').includes('UPDATE review_installations SET revoked = 1'));
});
test('generates separate test RSA identity, verifies matching SPKI/kid, refuses overwrite and purchase key reuse', () => {
  const output = join(privateDir, 'keys');
  const args = ['keys', '--directory', output, '--kid', 'review-operator-test'];
  const result = run(args); assert.equal(result.status, 0); assert(!result.stdout.includes('PRIVATE KEY'));
  assert.equal(run(args).status, 1);
  const publicFile = join(output, 'android-review-public-keys.json'); const privateFile = join(output, 'review-private.pem');
  const check = ['check-keys', '--private-file', privateFile, '--public-file', publicFile, '--kid', 'review-operator-test'];
  assert.equal(run(check).status, 0); assert.equal(statSync(privateFile).mode & 0o777, 0o600);
  assert.equal(run([...check, '--purchase-public-file', publicFile]).status, 1);
  const bad = [...check]; bad[bad.length - 1] = 'review-wrong-test'; assert.equal(run(bad).status, 1);
});
