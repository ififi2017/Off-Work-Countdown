// Capture the six portrait surfaces used by the App Store artwork:
// working timer, Home Screen widgets, lunch, Records, Life and Focus.
// Raw names match compose.mjs.
//
// The app already has DEBUG-only QA defaults for deterministic navigation and
// orientation. This script uses those hooks instead of adding screenshot code
// to the shipping build. Raw simulator frames stay in raw/ and are ignored.

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const DIR = new URL(".", import.meta.url).pathname;
const ROOT = new URL("../../../", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const DERIVED_DATA = join(tmpdir(), "off-work-countdown-ios-shots-derived-data");
const PROJECT = join(ROOT, "src-mobile/ios/App/App.xcodeproj");
const BUNDLE_ID = "com.rainif.offworkcountdown.macappstore";
const IPHONE_NAME = process.env.IOS_SHOTS_IPHONE || "iPhone 17 Pro Max";
const IPAD_NAME = process.env.IOS_SHOTS_IPAD || "iPad Pro 13-inch (M5)";
const PLATFORM = process.env.IOS_SHOTS_PLATFORM || "all";
const SCENE = process.env.IOS_SHOTS_SCENE;

if (!["all", "iphone", "ipad"].includes(PLATFORM)) {
  throw new Error("IOS_SHOTS_PLATFORM must be all, iphone, or ipad");
}
if (SCENE && !["1", "2", "3", "4", "5", "6"].includes(SCENE)) {
  throw new Error("IOS_SHOTS_SCENE must be 1 through 6");
}

mkdirSync(RAW, { recursive: true });

function run(command, args, {
  capture = false,
  allowFailure = false,
  cwd = ROOT,
  timeoutMs = 60_000,
} = {}) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit",
    timeout: timeoutMs,
  });
  if (result.error || (result.status !== 0 && !allowFailure)) {
    const detail = [result.error?.message, result.stdout, result.stderr].filter(Boolean).join("\n");
    throw new Error(`${command} ${args.join(" ")} failed${detail ? `:\n${detail}` : ""}`);
  }
  return result.stdout ?? "";
}

function simctl(args, options) {
  return run("xcrun", ["simctl", ...args], options);
}

function deviceId(named) {
  const payload = JSON.parse(simctl(["list", "devices", "available", "-j"], { capture: true }));
  const devices = Object.values(payload.devices).flat();
  const device = devices.find((candidate) => candidate.name === named && candidate.isAvailable);
  if (!device) {
    throw new Error(`No available simulator named ${named}. Set IOS_SHOTS_IPHONE or IOS_SHOTS_IPAD.`);
  }
  return device.udid;
}

function terminate(udid) {
  simctl(["terminate", udid, BUNDLE_ID], { allowFailure: true });
}

function isRunning(udid) {
  return simctl(["spawn", udid, "launchctl", "list"], {
    capture: true,
    allowFailure: true,
  }).includes(BUNDLE_ID);
}

function containerPath(udid) {
  return simctl(["get_app_container", udid, BUNDLE_ID, "data"], {
    capture: true,
    allowFailure: true,
  }).trim();
}

function surface(udid) {
  const container = containerPath(udid);
  if (!container) return null;
  try {
    return readFileSync(join(container, "Library/Caches/qa-surface.txt"), "utf8").trim();
  } catch {
    return null;
  }
}

function clearSurface(udid) {
  const container = containerPath(udid);
  if (container) rmSync(join(container, "Library/Caches/qa-surface.txt"), { force: true });
}

function launch(udid, language, scene = {}) {
  const { appleLanguage, appleLocale } = LANGUAGES[language];
  const now = new Date();
  const currentMinutes = now.getHours() * 60 + now.getMinutes();
  const startMinutes = (currentMinutes - 5 * 60 + 1440) % 1440;
  const endMinutes = (currentMinutes + 29) % 1440;
  const today = [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, "0"),
    String(now.getDate()).padStart(2, "0"),
  ].join("-");
  const qaArguments = [
    "-ios.native.onboardingComplete", "YES",
    "-ios.native.releaseNotesSeen", "3.1.9",
    "-ios.native.debugAlwaysOnboarding", scene.onboardingPage == null ? "NO" : "YES",
    "-ios.native.debugPlusAuthorized", "YES",
    "-ios.native.plusHasSeenIntro", "YES",
    "-ios.native.selectedTab", "timer",
    "-ios.native.countdownStarted", "YES",
    "-ios.native.forcedWorkdayDate", today,
    "-ios.native.startMinutes", String(startMinutes),
    "-ios.native.endMinutes", String(endMinutes),
    "-ios.native.scheduleMode", "classic",
    "-ios.native.lunchEnabled", "NO",
    "-ios.native.salaryEnabled", "YES",
    "-ios.native.salaryType", "monthly",
    "-ios.native.salaryAmount", "12000",
    "-ios.native.monthlyWorkingDays", "22",
    "-hideEarnings", "NO",
    "-theme", "light",
    "-ios.native.notificationMode", "milestones",
    "-ios.native.liveActivityEnabled", scene.liveActivity === false ? "NO" : "YES",
    "-ios.native.liveActivityLead", "30",
    "-ios.native.qaOrientation", scene.orientation ?? "portrait",
  ];
  if (scene.onboardingPage != null) {
    qaArguments.push("-ios.native.qaOnboardingPage", String(scene.onboardingPage));
  }
  if (scene.route) {
    qaArguments.push("-ios.native.qaRoute", scene.route);
  }
  if (scene.recordsScale) {
    qaArguments.push("-ios.native.qaRecordsScale", scene.recordsScale);
  }
  if (scene.scenario) {
    qaArguments.push("-ios.native.qaDebugScenario", scene.scenario);
  }
  if (scene.focusScenario) {
    qaArguments.push("-ios.native.qaFocusScenario", scene.focusScenario);
  }
  clearSurface(udid);
  simctl([
    "launch",
    "--terminate-running-process",
    udid,
    BUNDLE_ID,
    "-AppleLanguages",
    `(${appleLanguage})`,
    "-AppleLocale",
    appleLocale,
    ...qaArguments,
  ]);
}

async function waitForSurface(udid, expected) {
  const deadline = Date.now() + 10_000;
  let shown = null;
  while (Date.now() < deadline) {
    shown = surface(udid);
    if (shown === expected) return;
    await sleep(250);
  }
  throw new Error(`Expected ${expected} before capture, app reported ${shown ?? "no surface marker"}`);
}

async function screenshot(udid, name, expected, settleMs = 1400) {
  await waitForSurface(udid, expected);
  await sleep(settleMs);
  if (!isRunning(udid)) throw new Error(`Refusing ${name}.png: app is not running`);
  const shown = surface(udid);
  if (shown !== expected) {
    throw new Error(`Refusing ${name}.png: expected ${expected}, app reported ${shown ?? "no surface marker"}`);
  }
  const path = join(RAW, `${name}.png`);
  rmSync(path, { force: true });
  simctl(["io", udid, "screenshot", "--type=png", "--mask=ignored", path]);
  console.log(`captured ${name}.png`);
}

const LANGUAGES = {
  en: { stem: "en", appleLanguage: "en", appleLocale: "en_US" },
  "zh-CN": { stem: "zh", appleLanguage: "zh-Hans", appleLocale: "zh_CN" },
  "zh-TW": { stem: "zh-tw", appleLanguage: "zh-Hant", appleLocale: "zh_TW" },
};

async function capturePhone(udid, language) {
  const stem = LANGUAGES[language].stem;
  if (!SCENE || SCENE === "1") {
    launch(udid, language, { orientation: "portrait", scenario: "working" });
    await screenshot(udid, `${stem}-1`, "timer", 2800);
  }

  // Onboarding page 5 is the native likeness of Home Screen widgets and the island.
  if (!SCENE || SCENE === "2") {
    launch(udid, language, { onboardingPage: 5, orientation: "portrait" });
    await screenshot(udid, `${stem}-2`, "onboarding");
  }

  if (!SCENE || SCENE === "3") {
    launch(udid, language, { orientation: "portrait", scenario: "lunch", liveActivity: false });
    await screenshot(udid, `${stem}-3`, "timer", 1800);
  }

  if (!SCENE || SCENE === "4") {
    launch(udid, language, { orientation: "portrait", recordsScale: "year", liveActivity: false });
    await screenshot(udid, `${stem}-4`, "records", 2800);
  }

  if (!SCENE || SCENE === "5") {
    launch(udid, language, { orientation: "portrait", recordsScale: "life", liveActivity: false });
    await screenshot(udid, `${stem}-5`, "records", 2800);
  }

  if (!SCENE || SCENE === "6") {
    launch(udid, language, {
      orientation: "portrait",
      route: "focus",
      focusScenario: "runningFocus",
      liveActivity: false,
    });
    await screenshot(udid, `${stem}-6`, "route.focus", 2800);
  }
}

async function capturePad(udid, language) {
  const stem = LANGUAGES[language].stem;
  if (!SCENE || SCENE === "1") {
    launch(udid, language, { orientation: "portrait", scenario: "working", liveActivity: false });
    await screenshot(udid, `${stem}-ipad-1`, "timer", 20_000);
  }

  if (!SCENE || SCENE === "2") {
    launch(udid, language, { onboardingPage: 5, orientation: "portrait", liveActivity: false });
    await screenshot(udid, `${stem}-ipad-2`, "onboarding");
  }

  if (!SCENE || SCENE === "3") {
    launch(udid, language, { orientation: "portrait", scenario: "lunch", liveActivity: false });
    await screenshot(udid, `${stem}-ipad-3`, "timer", 20_000);
  }

  if (!SCENE || SCENE === "4") {
    launch(udid, language, { orientation: "portrait", recordsScale: "year", liveActivity: false });
    await screenshot(udid, `${stem}-ipad-4`, "records", 20_000);
  }

  if (!SCENE || SCENE === "5") {
    launch(udid, language, { orientation: "portrait", recordsScale: "life", liveActivity: false });
    await screenshot(udid, `${stem}-ipad-5`, "records", 30_000);
  }

  if (!SCENE || SCENE === "6") {
    launch(udid, language, {
      orientation: "portrait",
      route: "focus",
      focusScenario: "runningFocus",
      liveActivity: false,
    });
    await screenshot(udid, `${stem}-ipad-6`, "route.focus", 20_000);
  }
}

if (process.env.IOS_SHOTS_SKIP_BUILD !== "1") {
  run("npm", ["run", "build:ios-native-rules"]);
  run("xcodebuild", [
    "-project", PROJECT,
    "-scheme", "App",
    "-destination", "generic/platform=iOS Simulator",
    "-configuration", "Debug",
    "-derivedDataPath", DERIVED_DATA,
    "CODE_SIGNING_ALLOWED=NO",
    "build",
  ], { timeoutMs: 300_000 });
}

const appPath = join(DERIVED_DATA, "Build/Products/Debug-iphonesimulator/App.app");
try {
  readFileSync(join(appPath, "Info.plist"));
} catch {
  throw new Error(`Built app not found at ${appPath}. Remove IOS_SHOTS_SKIP_BUILD and run again.`);
}

const iphone = PLATFORM === "ipad" ? null : deviceId(IPHONE_NAME);
const ipad = PLATFORM === "iphone" ? null : deviceId(IPAD_NAME);

for (const udid of [iphone, ipad].filter(Boolean)) {
  simctl(["boot", udid], { allowFailure: true });
  simctl(["bootstatus", udid, "-b"]);
  // Installing over the QA copy preserves the native notification choice;
  // deleting it would put a system permission sheet over every Focus run.
  simctl(["install", udid, appPath]);
  simctl(["ui", udid, "appearance", "light"]);
  simctl(["ui", udid, "content_size", "large"]);
  simctl([
    "status_bar", udid, "override",
    "--time", "14:22",
    "--dataNetwork", "wifi",
    "--wifiMode", "active",
    "--wifiBars", "3",
    "--cellularMode", "active",
    "--cellularBars", "4",
    "--batteryState", "charged",
    "--batteryLevel", "100",
  ]);
}

const languages = process.env.IOS_SHOTS_LANGUAGE
  ? [process.env.IOS_SHOTS_LANGUAGE]
  : Object.keys(LANGUAGES);
if (languages.some((language) => !LANGUAGES[language])) {
  throw new Error("IOS_SHOTS_LANGUAGE must be en, zh-CN, or zh-TW");
}
for (const language of languages) {
  if (iphone) await capturePhone(iphone, language);
  if (ipad) await capturePad(ipad, language);
}

if (iphone) terminate(iphone);
if (ipad) terminate(ipad);
console.log(`done: raw simulator captures are in ${RAW}`);
