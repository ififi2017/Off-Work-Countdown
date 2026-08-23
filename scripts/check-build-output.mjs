import { existsSync, readFileSync, readdirSync } from "node:fs";
import { extname, join } from "node:path";

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
} else if (target === "mobile") {
  const leaked = webRouteManifests.filter((path) => existsSync(path));
  if (leaked.length > 0) {
    fail(`Web-only routes leaked into the Mobile build:\n${leaked.join("\n")}`);
  }

  const locales = readdirSync("public/locales", { withFileTypes: true })
    .filter(
      (entry) =>
        entry.isDirectory() &&
        existsSync(join("public/locales", entry.name, "translation.json"))
    )
    .map((entry) => entry.name)
    .sort();
  if (locales.length !== 19) {
    fail(`Expected 19 UI locales, found ${locales.length}.`);
  }

  for (const path of ["out/index.html", ...locales.map((lang) => `out/${lang}.html`)]) {
    if (!existsSync(path)) fail(`Mobile export is missing ${path}.`);
  }
  if (existsSync("out/en/mini.html")) {
    fail("Desktop Mini Timer leaked into the Mobile export.");
  }
  for (const path of [
    "out/demo",
    "out/badges",
    "out/baidu_verify_codeva-SXZydSeYe0.html",
    "out/sw.js",
  ]) {
    if (existsSync(path)) fail(`Web-only Mobile artifact exists: ${path}.`);
  }
  for (const lang of locales) {
    if (existsSync(`out/${lang}`)) {
      fail(`Web-only localized route tree leaked into Mobile: out/${lang}`);
    }
  }

  const entry = readFileSync("out/index.html", "utf8");
  if (!entry.includes('data-build-target="mobile"')) {
    fail("Mobile root entry is missing its build-target marker.");
  }
  if (entry.includes("location.search") || entry.includes("location.hash")) {
    fail("Mobile root entry must not carry URL data into the locale route.");
  }

  const representativePage = readFileSync("out/en.html", "utf8");
  if (!representativePage.includes("ios-app")) {
    fail("Mobile locale page is missing its dedicated app-surface marker.");
  }
  const mobileClientBundle = filesUnder("out/_next/static/chunks")
    .filter((path) => extname(path) === ".js")
    .map((path) => readFileSync(path, "utf8"))
    .join("\n");
  if (!mobileClientBundle.includes("ios-tabbar")) {
    fail("Mobile client bundle is missing its browser QA tab bar.");
  }

  const searchableExtensions = new Set([".html", ".js", ".json", ".txt"]);
  const forbiddenMarkers = [
    "/_vercel/insights",
    "get.microsoft.com/badge",
    "baidu-site-verification",
    "Notification.requestPermission",
    "navigator.serviceWorker",
    "new Notification",
    "workbox-",
    "__TAURI_INTERNALS__",
    "plugin:updater",
    "latest-cn.json",
    "ms-windows-store:",
  ];
  const leaks = [];
  for (const path of filesUnder("out")) {
    if (!searchableExtensions.has(extname(path))) continue;
    const content = readFileSync(path, "utf8");
    for (const marker of forbiddenMarkers) {
      if (content.includes(marker)) leaks.push(`${marker}: ${path}`);
    }
  }
  if (leaks.length > 0) {
    fail(`Web-only code leaked into the Mobile export:\n${leaks.join("\n")}`);
  }

  console.log("Mobile export retains 19 private regression pages.");
} else {
  fail("Usage: node scripts/check-build-output.mjs <web|desktop|mobile>");
}
