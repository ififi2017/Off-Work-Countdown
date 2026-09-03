// One-off social assets from the iPhone simulator: English night shift + countdown-to-zero.
import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { join } from "node:path";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const OUT = join(DIR, "out");
const UDID = process.env.IOS_SHOTS_UDID || "455563FE-D04A-428A-8B36-5B60716526A4";
const BUNDLE = "com.rainif.offworkcountdown.macappstore";
const APP = "/tmp/off-work-countdown-ios-shots-derived-data/Build/Products/Debug-iphonesimulator/App.app";

mkdirSync(RAW, { recursive: true });
mkdirSync(OUT, { recursive: true });

function run(command, args, { capture = false, allowFailure = false } = {}) {
  const result = spawnSync(command, args, {
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

function terminate() {
  simctl(["terminate", UDID, BUNDLE], { allowFailure: true });
}

function launch(extra = []) {
  simctl([
    "launch",
    "--terminate-running-process",
    UDID,
    BUNDLE,
    "-AppleLanguages", "(en)",
    "-AppleLocale", "en_US",
    "-ios.native.languageOverride", "en",
    "-ios.native.onboardingComplete", "YES",
    "-ios.native.debugAlwaysOnboarding", "NO",
    "-ios.native.selectedTab", "timer",
    "-ios.native.countdownStarted", "YES",
    "-ios.native.scheduleMode", "classic",
    "-ios.native.lunchEnabled", "NO",
    "-ios.native.salaryEnabled", "YES",
    "-ios.native.salaryType", "monthly",
    "-ios.native.salaryAmount", "12000",
    "-ios.native.monthlyWorkingDays", "22",
    "-ios.native.notificationMode", "milestones",
    "-ios.native.liveActivityEnabled", "YES",
    "-ios.native.liveActivityLead", "30",
    "-ios.native.qaOrientation", "portrait",
    ...extra,
  ]);
}

function pad(n) {
  return String(n).padStart(2, "0");
}

simctl(["boot", UDID], { allowFailure: true });
simctl(["bootstatus", UDID, "-b"]);
simctl(["uninstall", UDID, BUNDLE], { allowFailure: true });
simctl(["install", UDID, APP]);

// Night shift: patched debug clock at 01:22, 22:00–06:00.
simctl(["ui", UDID, "appearance", "dark"]);
simctl([
  "status_bar", UDID, "override",
  "--time", "01:22",
  "--dataNetwork", "wifi",
  "--wifiMode", "active",
  "--wifiBars", "3",
  "--cellularMode", "active",
  "--cellularBars", "4",
  "--batteryState", "charged",
  "--batteryLevel", "100",
]);
launch([
  "-ios.native.qaDebugScenario", "working",
  "-theme", "dark",
  "-hideEarnings", "NO",
]);
await sleep(4500);
const nightPath = join(RAW, "en-night-shift-iphone.png");
rmSync(nightPath, { force: true });
simctl(["io", UDID, "screenshot", "--type=png", "--mask=ignored", nightPath]);
console.log("captured en-night-shift-iphone.png");
terminate();

// Countdown to zero on the real clock. Aim for the next :00 at least 25s away.
simctl(["ui", UDID, "appearance", "light"]);
simctl(["status_bar", UDID, "clear"], { allowFailure: true });
simctl([
  "status_bar", UDID, "override",
  "--dataNetwork", "wifi",
  "--wifiMode", "active",
  "--wifiBars", "3",
  "--cellularMode", "active",
  "--cellularBars", "4",
  "--batteryState", "charged",
  "--batteryLevel", "100",
]);

const now = new Date();
const zero = new Date(now);
zero.setSeconds(0, 0);
zero.setMilliseconds(0);
zero.setMinutes(zero.getMinutes() + 1);
if (zero.getTime() - now.getTime() < 25_000) {
  zero.setMinutes(zero.getMinutes() + 1);
}
const endMinutes = zero.getHours() * 60 + zero.getMinutes();
const startMinutes = (endMinutes - 8 * 60 + 1440) % 1440;
const today = `${zero.getFullYear()}-${pad(zero.getMonth() + 1)}-${pad(zero.getDate())}`;
console.log(`zero at ${zero.toTimeString()} (start ${startMinutes} end ${endMinutes})`);

launch([
  "-ios.native.forcedWorkdayDate", today,
  "-ios.native.startMinutes", String(startMinutes),
  "-ios.native.endMinutes", String(endMinutes),
  "-theme", "light",
  "-hideEarnings", "NO",
]);
await sleep(4000);

const videoPath = join(OUT, "en-countdown-to-zero.mp4");
rmSync(videoPath, { force: true });
const waitMs = zero.getTime() - Date.now() - 8_000;
if (waitMs > 0) {
  console.log(`waiting ${Math.round(waitMs / 1000)}s to start recording`);
  await sleep(waitMs);
}

const recorder = spawn("xcrun", [
  "simctl", "io", UDID, "recordVideo",
  "--codec=h264",
  "--mask=ignored",
  "--force",
  videoPath,
], { stdio: ["ignore", "pipe", "pipe"] });

let started = false;
recorder.stderr.on("data", (chunk) => {
  const text = chunk.toString();
  process.stderr.write(text);
  if (text.includes("Recording started")) started = true;
});
recorder.stdout.on("data", (chunk) => process.stdout.write(chunk));

const startDeadline = Date.now() + 4000;
while (!started && Date.now() < startDeadline) {
  await sleep(100);
}
if (!started) console.warn("did not see Recording started; recording anyway");

const remaining = zero.getTime() - Date.now() + 2_200;
await sleep(Math.max(remaining, 8_000));
recorder.kill("SIGINT");
const exit = await new Promise((resolve) => recorder.on("close", resolve));
if (exit !== 0 && exit !== 130) {
  throw new Error(`recordVideo exited ${exit}`);
}
console.log(`recorded ${videoPath}`);
terminate();
console.log("done ios social captures");
