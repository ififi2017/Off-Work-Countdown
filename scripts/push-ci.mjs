#!/usr/bin/env node

import {
  confirmExact,
  ensureCleanMain,
  parseCommonOptions,
  run,
  runWebChecks,
} from "./release-helpers.mjs";

const usage = `Usage: npm run deploy:web -- [options]

Checks and pushes local main to origin/main, triggering the repository CI and
the connected Web deployment.

Options:
  --dry-run       Validate state and checks without pushing
  --skip-checks   Skip local lint, tests and builds
  --yes, -y       Skip the interactive confirmation
  --help, -h      Show this help`;

async function main() {
  const options = parseCommonOptions(process.argv.slice(2));
  if (options.help) {
    console.log(usage);
    return;
  }
  if (options.positional.length > 0) {
    throw new Error(`Unexpected argument: ${options.positional[0]}`);
  }

  const { ahead } = ensureCleanMain({ requireRemoteMatch: false });
  if (ahead === 0) {
    console.log("main already matches origin/main; there is nothing to push.");
    return;
  }

  console.log(`main is ${ahead} commit(s) ahead of origin/main.`);
  if (!options.skipChecks) runWebChecks();
  else console.warn("Skipping local checks by explicit request.");

  if (options.dryRun) {
    console.log("Dry run complete. No commits were pushed.");
    return;
  }

  await confirmExact({
    expected: "push-main",
    message: "This will push main and trigger CI/Web deployment.",
    yes: options.yes,
  });
  run("git", ["push", "origin", "main"]);
  console.log("main pushed. CI and the connected Web deployment can now start.");
}

main().catch((error) => {
  console.error(`Web deploy aborted: ${error.message}`);
  process.exit(1);
});
