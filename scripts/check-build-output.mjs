import { existsSync } from "node:fs";

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

if (target === "web") {
  const missing = webRouteManifests.filter((path) => !existsSync(path));
  if (missing.length > 0) {
    fail(`Web route manifests are missing:\n${missing.join("\n")}`);
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
  console.log("Desktop export excludes Web handlers and includes main/mini pages.");
} else {
  fail("Usage: node scripts/check-build-output.mjs <web|desktop>");
}
