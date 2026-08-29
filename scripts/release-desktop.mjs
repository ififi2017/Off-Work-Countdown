#!/usr/bin/env node

import {
  confirmExact,
  ensureCleanMain,
  normalizeVersion,
  parseCommonOptions,
  readProductVersion,
  releaseTagExists,
  run,
  runDesktopReleaseChecks,
} from "./release-helpers.mjs";

const usage = `Usage: npm run release:desktop -- [version] [options]

Validates the merged main branch, creates desktop-v<version>, and pushes the
tag to trigger the four-platform Desktop Release workflow. When omitted,
version is read from package.json.

Options:
  --dry-run       Validate state and checks without creating or pushing a tag
  --skip-checks   Skip local lint, tests, Web/Desktop builds and Rust checks
  --yes, -y       Skip the interactive confirmation
  --help, -h      Show this help`;

async function main() {
  const options = parseCommonOptions(process.argv.slice(2));
  if (options.help) {
    console.log(usage);
    return;
  }
  if (options.positional.length > 1) {
    throw new Error("Pass at most one version.");
  }

  const productVersion = normalizeVersion(readProductVersion());
  const version = normalizeVersion(options.positional[0] ?? productVersion);
  if (version !== productVersion) {
    throw new Error(
      `Requested ${version}, but the product files are at ${productVersion}. Bump all versions first.`
    );
  }
  const tag = `desktop-v${version}`;

  ensureCleanMain({ requireRemoteMatch: true });
  if (releaseTagExists(tag)) {
    throw new Error(`${tag} already exists locally or on origin.`);
  }

  if (!options.skipChecks) runDesktopReleaseChecks(tag);
  else console.warn("Skipping local checks by explicit request.");

  if (options.dryRun) {
    console.log(`Dry run complete. ${tag} was not created or pushed.`);
    return;
  }

  await confirmExact({
    expected: tag,
    message: `This will create and push ${tag}, immediately triggering Desktop Release.`,
    yes: options.yes,
  });
  run("git", ["tag", "-a", tag, "-m", `DoneAt ${version}`]);
  run("git", ["push", "origin", tag]);
  console.log(`${tag} pushed. The Desktop Release workflow can now start.`);
}

main().catch((error) => {
  console.error(`Desktop release aborted: ${error.message}`);
  process.exit(1);
});
