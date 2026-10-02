#!/usr/bin/env node
// Vercel "Ignored Build Step" (vercel.json `ignoreCommand`).
// Exit 0 skips the deployment; exit 1 builds it.
//
// Skips only when every changed file is outside the Web build: native iOS /
// Android / Desktop / extension work, docs, plans, store metadata and tooling
// scripts. Anything unknown, and any doubt about the diff itself, builds.
// `tsconfig.json` includes every `**/*.ts(x)`, so `next build` type-checks
// TypeScript in those directories too; such files always build, as do the
// scripts that TypeScript imports (WEB_SCRIPTS).
//
// Preview: diff against the merge base with main, i.e. "what this branch
// changes". Production: diff against the last successful production deploy.
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const NON_WEB_PREFIXES = [
  'src-mobile/',
  'src-tauri/',
  'src-extension/',
  'app-store-connect/',
  'docs/',
  'plans/',
  'readme_image/',
  'assets/',
  'scripts/',
  '.github/',
];
// Scripts reached from type-checked TypeScript, plus this file itself.
const WEB_SCRIPTS = new Set([
  'scripts/generate-desktop-holidays.mjs',
  'scripts/vercel-ignore-build.mjs',
]);
const NON_WEB_FILES = new Set([
  'README.md',
  'README_CN.md',
  'AGENTS.md',
  'CLAUDE.md',
  'LICENSE',
  'THIRD_PARTY_LICENSES',
]);
const TYPE_CHECKED = /\.(c|m)?tsx?$/;

export function affectsWeb(file) {
  if (TYPE_CHECKED.test(file) || WEB_SCRIPTS.has(file)) return true;
  if (NON_WEB_FILES.has(file)) return false;
  return !NON_WEB_PREFIXES.some((prefix) => file.startsWith(prefix));
}

const git = (...args) =>
  execFileSync('git', args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();

function changedFiles(env) {
  const head = env.VERCEL_GIT_COMMIT_SHA || git('rev-parse', 'HEAD');
  const remote =
    env.VERCEL_GIT_REPO_OWNER && env.VERCEL_GIT_REPO_SLUG
      ? `https://github.com/${env.VERCEL_GIT_REPO_OWNER}/${env.VERCEL_GIT_REPO_SLUG}.git`
      : 'origin';
  let base;
  if (env.VERCEL_ENV === 'production') {
    base = env.VERCEL_GIT_PREVIOUS_SHA;
    if (!base) return null;
    try {
      git('cat-file', '-e', `${base}^{commit}`);
    } catch {
      git('fetch', '--quiet', '--depth=1', remote, base);
    }
  } else {
    // Vercel clones shallowly; fetch enough of main to find the merge base.
    // The branch goes first so FETCH_HEAD ends up pointing at main.
    if (env.VERCEL_GIT_COMMIT_REF) {
      git('fetch', '--quiet', '--depth=300', remote, env.VERCEL_GIT_COMMIT_REF);
    }
    git('fetch', '--quiet', '--depth=300', remote, 'main');
    base = git('merge-base', 'FETCH_HEAD', head);
  }
  const output = git('diff', '--name-only', base, head);
  return output ? output.split('\n') : [];
}

function main() {
  let files;
  try {
    files = changedFiles(process.env);
  } catch (error) {
    console.log(`Building: could not determine the diff (${error.message.split('\n')[0]}).`);
    process.exit(1);
  }
  if (!files) {
    console.log('Building: no previous deployment to compare with.');
    process.exit(1);
  }
  const web = files.filter(affectsWeb);
  if (files.length === 0 || web.length > 0) {
    console.log(
      files.length === 0
        ? 'Building: no file changes detected.'
        : `Building: ${web.length} Web-related change(s), e.g. ${web.slice(0, 5).join(', ')}.`
    );
    process.exit(1);
  }
  console.log(`Skipping: ${files.length} changed file(s), none used by the Web build.`);
  process.exit(0);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) main();
