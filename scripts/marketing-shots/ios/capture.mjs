// Capture the native iPhone and iPad surfaces used by the App Store artwork.
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

if (!["all", "iphone", "ipad"].includes(PLATFORM)) {
  throw new Error("IOS_SHOTS_PLATFORM must be all, iphone, or ipad");
}

mkdirSync(RAW, { recursive: true });

function run(command, args, { capture = false, allowFailure = false, cwd = ROOT } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit",
  });
  if (result.status !== 0 && !allowFailure) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join("\n");
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

async function returnToHomeScreen(udid) {
  terminate(udid);
  await sleep(500);
  // Bouncing through Settings makes SpringBoard render the Home Screen
  // reliably; terminating an app can otherwise leave its last frame visible.
  simctl(["launch", udid, "com.apple.Preferences"], { allowFailure: true });
  await sleep(700);
  simctl(["terminate", udid, "com.apple.Preferences"], { allowFailure: true });
  await sleep(2000);
}

function launch(udid, language, scene = {}) {
  const appleLanguage = language === "zh-CN" ? "zh-Hans" : "en";
  const appleLocale = language === "zh-CN" ? "zh_CN" : "en_US";
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
    "-ios.native.debugAlwaysOnboarding", scene.onboardingPage == null ? "NO" : "YES",
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

function screenshot(udid, name) {
  const path = join(RAW, `${name}.png`);
  rmSync(path, { force: true });
  simctl(["io", udid, "screenshot", "--type=png", "--mask=ignored", path]);
  console.log(`captured ${name}.png`);
}

async function capturePhone(udid, language) {
  launch(udid, language, { orientation: "portrait" });
  await sleep(4200);
  screenshot(udid, `${language}-iphone-main`);

  // The Live Activity survives the app leaving the foreground, which exposes
  // its compact Dynamic Island presentation against the Home Screen.
  await returnToHomeScreen(udid);
  screenshot(udid, `${language}-iphone-island`);

  // Onboarding page 5 is the native, source-controlled likeness of the actual
  // Home Screen widget, Lock Screen accessory and compact island.
  launch(udid, language, { onboardingPage: 5, orientation: "portrait" });
  await sleep(2200);
  screenshot(udid, `${language}-iphone-widgets`);

  launch(udid, language, { orientation: "landscape" });
  await sleep(2600);
  screenshot(udid, `${language}-iphone-landscape`);
}

async function capturePad(udid, language) {
  launch(udid, language, { orientation: "portrait", liveActivity: false });
  await sleep(2600);
  screenshot(udid, `${language}-ipad-main`);

  launch(udid, language, { onboardingPage: 5, orientation: "portrait", liveActivity: false });
  await sleep(2200);
  screenshot(udid, `${language}-ipad-widgets`);

  launch(udid, language, { route: "notifications", orientation: "portrait", liveActivity: false });
  await sleep(2400);
  screenshot(udid, `${language}-ipad-reminders`);

  launch(udid, language, { orientation: "landscape", liveActivity: false });
  await sleep(2600);
  screenshot(udid, `${language}-ipad-landscape`);
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
  ]);
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
  simctl(["uninstall", udid, BUNDLE_ID], { allowFailure: true });
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

for (const language of ["en", "zh-CN"]) {
  if (iphone) await capturePhone(iphone, language);
  if (ipad) await capturePad(ipad, language);
}

if (iphone) terminate(iphone);
if (ipad) terminate(ipad);
console.log(`done: raw simulator captures are in ${RAW}`);
