import { readFileSync } from 'node:fs';
const config = JSON.parse(readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8'));
const required = ['GOOGLE_SERVICE_ACCOUNT_EMAIL', 'PUBSUB_SERVICE_ACCOUNT_EMAIL', 'PUBSUB_SUBSCRIPTION'];
if (required.some(key => !config.vars[key] || config.vars[key].includes('CONFIGURE_ME')) ||
    !/^[a-f0-9-]{36}$/.test(config.d1_databases[0].database_id) ||
    config.d1_databases[0].database_id === '00000000-0000-0000-0000-000000000000') {
  console.error('Complete the public deployment configuration first. See README.md.');
  process.exit(1);
}
