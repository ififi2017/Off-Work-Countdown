// SPDX-License-Identifier: MPL-2.0
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));

// Keep legal notices beside the built Web/Desktop/extension assets. These files
// are generated, not source: the immutable revision must describe the build.
export function prepareLicenseNotices(destination = resolve(root, "public/licenses")) {
  mkdirSync(destination, { recursive: true });
  for (const [source, name] of [
    ["LICENSE", "LICENSE"],
    ["LICENSES/MIT-legacy.txt", "LICENSES/MIT-legacy.txt"],
    ["LICENSING.md", "LICENSING.md"],
    ["ASSETS.md", "ASSETS.md"],
    ["TRADEMARKS.md", "TRADEMARKS.md"],
    ["SOURCE.md", "SOURCE.md"],
    ["CONTRIBUTING.md", "CONTRIBUTING.md"],
  ]) {
    mkdirSync(dirname(resolve(destination, name)), { recursive: true });
    copyFileSync(resolve(root, source), resolve(destination, name));
  }
  let revision;
  let dirty = false;
  try {
    revision = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    dirty = execFileSync("git", ["status", "--porcelain", "--untracked-files=normal"], {
      cwd: root, encoding: "utf8",
    }).trim().length > 0;
  } catch {
    revision = process.env.DONEAT_SOURCE_COMMIT || process.env.VERCEL_GIT_COMMIT_SHA || process.env.GITHUB_SHA;
  }
  if (!revision || !/^[0-9a-f]{40}$/i.test(revision)) {
    throw new Error("Cannot identify source revision; set DONEAT_SOURCE_COMMIT when building a source archive.");
  }
  const version = JSON.parse(readFileSync(resolve(root, "package.json"), "utf8")).version;
  const repository = (process.env.DONEAT_SOURCE_REPOSITORY ||
    `https://github.com/${process.env.GITHUB_REPOSITORY || "ififi2017/Off-Work-Countdown"}`).replace(/\/$/, "");
  const status = dirty
    ? "Local development build with uncommitted changes; this commit is only its base. Do not distribute this build as an official release."
    : "Source revision for this build:";
  writeFileSync(resolve(destination, "source.txt"),
    `DoneAt ${version}\nCovered source: Mozilla Public License 2.0 (MPL-2.0).\n` +
    `${status}\n${repository}/tree/${revision}\n` +
    `Source archive: ${repository}/archive/${revision}.tar.gz\n` +
    "See LICENSE (MPL-2.0), LICENSES/MIT-legacy.txt, LICENSING.md and SOURCE.md.\n" +
    "Existing MIT permissions and third-party licenses are preserved.\n" +
    "Source questions: hello@doneat.app (no purchase required).\n");
  return { revision, dirty, destination };
}
