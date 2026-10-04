import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import './check-deploy.mjs';

// Wrangler automatically overrides conflicting custom-domain DNS in non-TTY mode.
// Keep production deployment interactive so an existing service cannot be silently replaced.
if (!process.stdin.isTTY || !process.stdout.isTTY || process.env.CI) {
  console.error('Run deployment in an interactive terminal so DNS/Worker conflicts can be reviewed.');
  process.exit(1);
}
const result = spawnSync(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'deploy'], {
  cwd: fileURLToPath(new URL('../', import.meta.url)), stdio: 'inherit',
  env: { ...process.env, WRANGLER_SEND_METRICS: 'false' },
});
process.exitCode = result.status ?? 1;
