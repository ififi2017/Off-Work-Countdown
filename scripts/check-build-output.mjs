import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const target = process.argv[2];
const webRouteManifests = [
  ".next/server/app/robots.txt/route_client-reference-manifest.js",
  ".next/server/app/manifest.json/route_client-reference-manifest.js",
  ".next/server/app/api/e/route_client-reference-manifest.js",
  ".next/server/app/api/e/stats/route_client-reference-manifest.js",
];

function fail(message) {
  console.error(message);
  process.exit(1);
}

function filesUnder(root) {
  if (!existsSync(root)) return [];
  const files = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) files.push(...filesUnder(path));
    else files.push(path);
  }
  return files;
}

if (target === "web" || target === "desktop") {
  const noticeRoot = target === "web" ? "public/licenses" : "out/licenses";
  for (const name of ["LICENSE", "LICENSES/MIT-legacy.txt", "LICENSING.md", "ASSETS.md", "TRADEMARKS.md", "SOURCE.md", "CONTRIBUTING.md"]) {
    const file = join(noticeRoot, name);
    if (!existsSync(file) || readFileSync(file, "utf8") !== readFileSync(name, "utf8")) {
      fail(`Missing or stale packaged license notice: ${file}`);
    }
  }
  const sourceNotice = join(noticeRoot, "source.txt");
  if (!existsSync(sourceNotice) || !/\/tree\/[0-9a-f]{40}/.test(readFileSync(sourceNotice, "utf8"))) {
    fail(`Missing source revision: ${sourceNotice}`);
  }
}

if (target === "web") {
  const missing = webRouteManifests.filter((path) => !existsSync(path));
  if (missing.length > 0) {
    fail(`Web route manifests are missing:\n${missing.join("\n")}`);
  }
  // Every visitor's Service Worker downloads its precache list on install; the
  // lazy showcase images and the Desktop-only holiday calendars stay out of it.
  const serviceWorker = existsSync("public/sw.js") ? readFileSync("public/sw.js", "utf8") : "";
  if (!serviceWorker) fail("Web build is missing public/sw.js.");
  for (const dir of ["showcase", "holidays"]) {
    if (serviceWorker.includes(`'url':'/${dir}/`)) fail(`Web Service Worker precaches public/${dir}.`);
  }
  console.log("Web Route Handler manifests use deployable route.ts output names.");
} else if (target === "desktop") {
  const leaked = webRouteManifests.filter((path) => existsSync(path));
  if (leaked.length > 0) {
    fail(`Web-only routes leaked into the desktop build:\n${leaked.join("\n")}`);
  }
  for (const path of ["out/en.html", "out/en/mini.html"]) {
    if (!existsSync(path)) fail(`Desktop export is missing ${path}.`);
  }
  if (existsSync("out/showcase")) {
    fail("Web-only App showcase images leaked into the desktop export: out/showcase");
  }
  // Salary tools are Web-only even when draft previews are enabled.
  const salaryLeaks = filesUnder("out").filter((path) =>
    /(?:^|[\\/])(?:salary|tools)(?:[\\/.]|$)/.test(path)
  );
  if (salaryLeaks.length) {
    fail(`Web salary routes leaked into Desktop export:\n${salaryLeaks.join("\n")}`);
  }
  console.log("Desktop export excludes Web handlers and includes main/mini pages.");
} else {
  fail("Usage: node scripts/check-build-output.mjs <web|desktop>");
}
