import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createInterface } from "node:readline/promises";

export const npmCommand = process.platform === "win32" ? "npm.cmd" : "npm";

function commandLabel(command, args) {
  return [command, ...args].join(" ");
}

export function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env ?? process.env,
    encoding: "utf8",
    stdio: options.capture ? ["ignore", "pipe", "pipe"] : "inherit",
  });

  if (result.error) throw result.error;

  const allowedStatuses = options.allowedStatuses ?? [0];
  if (!allowedStatuses.includes(result.status ?? 1)) {
    const details = [result.stdout, result.stderr]
      .filter(Boolean)
      .map((value) => value.trim())
      .filter(Boolean)
      .join("\n");
    throw new Error(
      `${commandLabel(command, args)} failed${details ? `:\n${details}` : "."}`
    );
  }

  return result;
}

export function capture(command, args, options = {}) {
  return run(command, args, { ...options, capture: true }).stdout.trim();
}

export function parseCommonOptions(argv) {
  const options = {
    dryRun: false,
    help: false,
    skipChecks: false,
    yes: false,
    positional: [],
  };

  for (const argument of argv) {
    if (argument === "--dry-run") options.dryRun = true;
    else if (argument === "--help" || argument === "-h") options.help = true;
    else if (argument === "--skip-checks") options.skipChecks = true;
    else if (argument === "--yes" || argument === "-y") options.yes = true;
    else if (argument.startsWith("-")) {
      throw new Error(`Unknown option: ${argument}`);
    } else {
      options.positional.push(argument);
    }
  }

  return options;
}

export function readProductVersion() {
  const packageJson = JSON.parse(readFileSync("package.json", "utf8"));
  if (typeof packageJson.version !== "string") {
    throw new Error("package.json does not contain a product version.");
  }
  return packageJson.version;
}

export function normalizeVersion(value) {
  const version = value.replace(/^desktop-v/, "").replace(/^v/, "");
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version)) {
    throw new Error(`Invalid release version: ${value}`);
  }
  return version;
}

export function ensureCleanMain({ requireRemoteMatch }) {
  const branch = capture("git", ["branch", "--show-current"]);
  if (branch !== "main") {
    throw new Error(`Run this command from main, not ${branch || "detached HEAD"}.`);
  }

  if (capture("git", ["status", "--porcelain"])) {
    throw new Error("The working tree is not clean. Commit or stash changes first.");
  }

  console.log("Fetching origin/main and release tags...");
  run("git", ["fetch", "origin", "main", "--tags"]);

  const counts = capture("git", [
    "rev-list",
    "--left-right",
    "--count",
    "origin/main...HEAD",
  ])
    .split(/\s+/)
    .map(Number);
  const [behind, ahead] = counts;

  if (behind > 0) {
    throw new Error(
      `main is ${behind} commit(s) behind origin/main. Pull or resolve divergence first.`
    );
  }
  if (requireRemoteMatch && ahead > 0) {
    throw new Error(
      `main is ${ahead} commit(s) ahead of origin/main. Push or merge through a PR first.`
    );
  }

  return { ahead, behind };
}

export function releaseTagExists(tag) {
  const local = run("git", ["show-ref", "--verify", "--quiet", `refs/tags/${tag}`], {
    capture: true,
    allowedStatuses: [0, 1],
  });
  const remote = run(
    "git",
    ["ls-remote", "--exit-code", "--tags", "origin", `refs/tags/${tag}`],
    { capture: true, allowedStatuses: [0, 2] }
  );
  return local.status === 0 || remote.status === 0;
}

export function runWebChecks() {
  const checks = [
    [npmCommand, ["run", "check:version"]],
    [npmCommand, ["run", "lint"]],
    [npmCommand, ["test"]],
    [npmCommand, ["run", "build"]],
    [npmCommand, ["run", "check:build:web"]],
    [npmCommand, ["run", "build:desktop"]],
    [npmCommand, ["run", "check:build:desktop"]],
  ];

  for (const [command, args] of checks) run(command, args);
}

export function runDesktopReleaseChecks(tag) {
  run(npmCommand, ["run", "check:version"], {
    env: { ...process.env, GITHUB_REF_NAME: tag },
  });
  run(npmCommand, ["run", "lint"]);
  run(npmCommand, ["test"]);
  run(npmCommand, ["run", "build"]);
  run(npmCommand, ["run", "check:build:web"]);
  run(npmCommand, ["run", "build:desktop"]);
  run(npmCommand, ["run", "check:build:desktop"]);
  run("cargo", ["fmt", "--check", "--manifest-path", "src-tauri/Cargo.toml"]);
  run("cargo", ["test", "--manifest-path", "src-tauri/Cargo.toml"]);
  run("cargo", ["build", "--release", "--manifest-path", "src-tauri/Cargo.toml"]);
}

export async function confirmExact({ expected, message, yes }) {
  if (yes) return;
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error(`Interactive confirmation is unavailable. Re-run with --yes.`);
  }

  const prompt = createInterface({ input: process.stdin, output: process.stdout });
  const answer = await prompt.question(`${message}\nType ${expected} to continue: `);
  prompt.close();

  if (answer.trim() !== expected) throw new Error("Cancelled.");
}
