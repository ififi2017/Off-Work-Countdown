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
  for (const marker of ["mobile-app-surface", "mobile-web-tabbar", ">Timer<"]) {
    if (!representativePage.includes(marker)) {
      fail(`Mobile locale page is missing its dedicated portrait UI marker: ${marker}.`);
    }
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

  const universalBundleId = "com.rainif.offworkcountdown.macappstore";
  const capacitorConfig = readFileSync("capacitor.config.ts", "utf8");
  const iosProject = readFileSync(
    "src-mobile/ios/App/App.xcodeproj/project.pbxproj",
    "utf8"
  );
  const mainStoryboard = readFileSync(
    "src-mobile/ios/App/App/Base.lproj/Main.storyboard",
    "utf8"
  );
  const iosInfo = readFileSync("src-mobile/ios/App/App/Info.plist", "utf8");
  const mobileController = readFileSync(
    "src-mobile/ios/App/App/MobileBridgeViewController.swift",
    "utf8"
  );
  const appIcon = readFileSync(
    "src-mobile/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png"
  );
  if (!capacitorConfig.includes(`appId: "${universalBundleId}"`)) {
    fail(`Capacitor appId must stay aligned with Universal Purchase: ${universalBundleId}.`);
  }
  const bundleIdAssignments = [
    ...iosProject.matchAll(/PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);/g),
  ].map((match) => match[1].trim());
  if (
    bundleIdAssignments.length === 0 ||
    bundleIdAssignments.some((value) => value !== universalBundleId)
  ) {
    fail(`iOS bundle ids must all be ${universalBundleId}.`);
  }
  if (!mainStoryboard.includes('customClass="MobileBridgeViewController"')) {
    fail("iOS must boot through the native MobileBridgeViewController shell.");
  }
  if (!iosProject.includes("TARGETED_DEVICE_FAMILY = 1;")) {
    fail("The P1 iOS shell must remain iPhone-only until the final device matrix is decided.");
  }
  if (
    !iosInfo.includes("UISupportedInterfaceOrientations") ||
    !iosInfo.includes("UIInterfaceOrientationPortrait")
  ) {
    fail("The P1 iOS shell must declare its portrait orientation baseline.");
  }
  if (
    !mobileController.includes("CAPBridgeViewController") ||
    !mobileController.includes("UITabBar") ||
    !mobileController.includes("view.safeAreaLayoutGuide.bottomAnchor") ||
    !mobileController.includes("overrideUserInterfaceStyle")
  ) {
    fail("iOS must keep the Capacitor business-rule bridge inside its safe-area and theme-aware native UITabBar shell.");
  }
  const iconWidth = appIcon.readUInt32BE(16);
  const iconHeight = appIcon.readUInt32BE(20);
  const iconColorType = appIcon[25];
  if (
    iconWidth !== 1024 ||
    iconHeight !== 1024 ||
    iconColorType === 4 ||
    iconColorType === 6
  ) {
    fail("The Universal Purchase App Icon must be a 1024x1024 PNG without alpha.");
  }
  for (const suffix of ["", "-1", "-2"]) {
    if (
      !existsSync(
        `src-mobile/ios/App/App/Assets.xcassets/Splash.imageset/splash-dark-2732x2732${suffix}.png`
      )
    ) {
      fail("The iOS Launch Screen must include dark appearance assets.");
    }
  }

  console.log(
    "Mobile export has 19 private locale pages and the iOS Universal Purchase shell without Web/Desktop routes."
  );
} else {
  fail("Usage: node scripts/check-build-output.mjs <web|desktop|mobile>");
}
