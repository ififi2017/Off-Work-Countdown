// A layout sweep across every iOS shell, for eyes rather than for assertions.
//
// The app has three navigation shells — phone portrait, phone landscape and
// the iPad sidebar — and they share most of their views. A change aimed at one
// lands in all three, and nothing in the test suite notices: every one of those
// tests is model-layer. This walks the shells instead, and leaves a contact
// sheet you can scan in half a minute.
//
// It adds no screenshot code to the shipping build. Every scene below is set up
// through DEBUG-only launch arguments the app already reads.

import { spawnSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const ROOT = new URL("../", import.meta.url).pathname;
const OUT = join(ROOT, "scripts/ios-qa-shots");
const DERIVED_DATA = join(tmpdir(), "off-work-countdown-ios-qa-derived-data");
const PROJECT = join(ROOT, "src-mobile/ios/App/App.xcodeproj");
const BUNDLE_ID = "com.rainif.offworkcountdown.macappstore";
const IPHONE_NAME = process.env.IOS_QA_IPHONE || "iPhone 17 Pro";
const IPAD_NAME = process.env.IOS_QA_IPAD || "iPad Pro 13-inch (M5)";
const THEME = process.env.IOS_QA_THEME || "light";
const LANGUAGE = process.env.IOS_QA_LANGUAGE || "en";

// simctl wedges from time to time — a launch that never returns should cost one
// missing tile, not the whole sweep.
const COMMAND_TIMEOUT_MS = 90_000;

if (!["light", "dark", "both"].includes(THEME)) {
  throw new Error("IOS_QA_THEME must be light, dark, or both");
}

const today = new Date();
const todayKey = [
  today.getFullYear(),
  String(today.getMonth() + 1).padStart(2, "0"),
  String(today.getDate()).padStart(2, "0"),
].join("-");

/// Every surface whose layout differs between the shells. `records-day` and
/// `settings-detail` are pushed pages: they are where a navigation bar's own
/// margins show up, which is exactly where the iPad title regressed.
const SCENES = [
  { name: "timer", args: [] },
  { name: "records-week", args: ["-ios.native.qaRecordsScale", "week"] },
  { name: "records-month", args: ["-ios.native.qaRecordsScale", "month"] },
  { name: "records-year", args: ["-ios.native.qaRecordsScale", "year"] },
  { name: "records-life", args: ["-ios.native.qaRecordsScale", "life"] },
  { name: "records-day", args: ["-ios.native.qaRecordsRoute", `day:${todayKey}`] },
  { name: "settings", args: ["-ios.native.selectedTab", "settings"] },
  {
    name: "settings-detail",
    args: ["-ios.native.selectedTab", "settings", "-ios.native.qaRoute", "schedule"],
  },
];

const requested = process.env.IOS_QA_SCENES?.split(",").map((name) => name.trim());
const scenes = requested?.length
  ? SCENES.filter((scene) => requested.includes(scene.name))
  : SCENES;
if (!scenes.length) {
  throw new Error(`No scenes matched IOS_QA_SCENES. Known: ${SCENES.map((s) => s.name).join(", ")}`);
}

function run(command, args, { capture = false, allowFailure = false } = {}) {
  const result = spawnSync(command, args, {
    cwd: ROOT,
    encoding: "utf8",
    timeout: COMMAND_TIMEOUT_MS,
    killSignal: "SIGKILL",
    stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit",
  });
  if (result.status !== 0 && !allowFailure) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join("\n");
    throw new Error(`${command} ${args.join(" ")} failed${detail ? `:\n${detail}` : ""}`);
  }
  return result.stdout ?? "";
}

const simctl = (args, options) => run("xcrun", ["simctl", ...args], options);

function deviceId(named) {
  const payload = JSON.parse(simctl(["list", "devices", "available", "-j"], { capture: true }));
  const device = Object.values(payload.devices)
    .flat()
    .find((candidate) => candidate.name === named && candidate.isAvailable);
  if (!device) {
    throw new Error(`No available simulator named ${named}. Set IOS_QA_IPHONE or IOS_QA_IPAD.`);
  }
  return device.udid;
}

/// A clean install per run, not per shot: the review prompt only appears once a
/// completed shift is on file, and a fresh container has none. Every scene then
/// runs the "working" scenario, which never completes one.
function prepare(udid, appPath) {
  simctl(["boot", udid], { allowFailure: true });
  simctl(["bootstatus", udid, "-b"], { allowFailure: true });
  simctl(["uninstall", udid, BUNDLE_ID], { allowFailure: true });
  simctl(["install", udid, appPath]);
  simctl(["status_bar", udid, "override",
    "--time", "9:41",
    "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
    "--cellularMode", "active", "--cellularBars", "4",
    "--batteryState", "charged", "--batteryLevel", "100",
  ], { allowFailure: true });
}

/// Returns the pid simctl reports, or null. A launch that quietly fails leaves
/// the Home Screen up, and the screenshot after it looks like a success.
function launch(udid, scene, orientation, theme) {
  const args = [
    "launch", "--terminate-running-process", udid, BUNDLE_ID,
    "-AppleLanguages", `(${LANGUAGE})`,
    "-AppleLocale", LANGUAGE === "zh-CN" ? "zh_CN" : "en_US",
    "-theme", theme,
    "-ios.native.onboardingComplete", "YES",
    "-ios.native.debugAlwaysOnboarding", "NO",
    "-ios.native.selectedTab", "timer",
    "-ios.native.salaryEnabled", "YES",
    "-ios.native.salaryType", "monthly",
    "-ios.native.salaryAmount", "12000",
    "-ios.native.monthlyWorkingDays", "22",
    "-ios.native.qaDebugScenario", "working",
    "-ios.native.qaOrientation", orientation,
    ...scene.args,
  ];
  const output = simctl(args, { capture: true, allowFailure: true });
  return /:\s*(\d+)/.exec(output)?.[1] ?? null;
}

function isRunning(udid) {
  const output = run("xcrun", ["simctl", "spawn", udid, "launchctl", "list"], {
    capture: true,
    allowFailure: true,
  });
  return output.includes(BUNDLE_ID);
}

function pixelSize(path) {
  const output = run("sips", ["-g", "pixelWidth", "-g", "pixelHeight", path], {
    capture: true,
    allowFailure: true,
  });
  const width = Number(/pixelWidth:\s*(\d+)/.exec(output)?.[1]);
  const height = Number(/pixelHeight:\s*(\d+)/.exec(output)?.[1]);
  return Number.isFinite(width) && Number.isFinite(height) ? { width, height } : null;
}

/// Checks what it asked for rather than that a file appeared. A screenshot of
/// the Home Screen is a perfectly valid PNG, and reporting it as a captured
/// screen is worse than reporting nothing at all.
function screenshot(udid, name, orientation) {
  if (!isRunning(udid)) return "app not running";
  const path = join(OUT, `${name}.png`);
  rmSync(path, { force: true });
  simctl(["io", udid, "screenshot", "--type=png", "--mask=ignored", path], {
    capture: true,
    allowFailure: true,
  });
  try {
    readFileSync(path);
  } catch {
    return "no screenshot";
  }
  const size = pixelSize(path);
  if (!size) return "unreadable png";
  const isLandscape = size.width > size.height;
  if (isLandscape !== (orientation === "landscape")) {
    rmSync(path, { force: true });
    return `still ${isLandscape ? "landscape" : "portrait"}`;
  }
  return null;
}

function contactSheet(rows, columns) {
  const cells = (row) =>
    columns
      .map(({ key, label }) => {
        const shot = row.shots[key];
        const body = shot
          ? `<a href="${shot}"><img src="${shot}" alt="${row.name} ${label}"></a>`
          : `<div class="missing">${row.notes[key] ?? "not captured"}</div>`;
        return `<figure><figcaption>${label}</figcaption>${body}</figure>`;
      })
      .join("");
  return `<title>iOS layout sweep</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 13px -apple-system, system-ui, sans-serif; margin: 24px; }
  h1 { font-size: 17px; margin: 0 0 4px; }
  p.sub { color: color-mix(in srgb, currentColor 55%, transparent); margin: 0 0 24px; }
  section { margin-bottom: 32px; }
  h2 { font-size: 14px; margin: 0 0 8px; }
  .row { display: flex; gap: 14px; align-items: flex-start; overflow-x: auto; }
  figure { margin: 0; flex: 0 0 auto; }
  figcaption { font-size: 11px; opacity: 0.6; margin-bottom: 4px; }
  img { height: 420px; width: auto; border-radius: 8px; display: block;
        border: 1px solid color-mix(in srgb, currentColor 18%, transparent); }
  .missing { height: 420px; width: 200px; display: grid; place-items: center;
             border-radius: 8px; font-size: 11px; opacity: 0.5;
             border: 1px dashed color-mix(in srgb, currentColor 30%, transparent); }
</style>
<h1>iOS layout sweep</h1>
<p class="sub">${new Date().toLocaleString()} · ${LANGUAGE} · ${THEME}</p>
${rows.map((row) => `<section><h2>${row.name}</h2><div class="row">${cells(row)}</div></section>`).join("\n")}
`;
}

if (process.env.IOS_QA_SKIP_BUILD !== "1") {
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
  throw new Error(`Built app not found at ${appPath}. Remove IOS_QA_SKIP_BUILD and run again.`);
}

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });

const devices = [
  { key: "iphone", udid: deviceId(IPHONE_NAME), orientations: ["portrait", "landscape"] },
  { key: "ipad", udid: deviceId(IPAD_NAME), orientations: ["portrait", "landscape"] },
];
for (const device of devices) prepare(device.udid, appPath);

const themes = THEME === "both" ? ["light", "dark"] : [THEME];
const columns = devices.flatMap((device) =>
  device.orientations.flatMap((orientation) =>
    themes.map((theme) => ({
      key: `${device.key}-${orientation}-${theme}`,
      label: `${device.key} · ${orientation}${themes.length > 1 ? ` · ${theme}` : ""}`,
    }))
  )
);

const rows = [];
let missing = 0;
for (const scene of scenes) {
  const shots = {};
  const notes = {};
  for (const device of devices) {
    for (const orientation of device.orientations) {
      for (const theme of themes) {
        const name = `${scene.name}-${device.key}-${orientation}-${theme}`;
        const key = `${device.key}-${orientation}-${theme}`;
        const pid = launch(device.udid, scene, orientation, theme);
        // Long enough for the launch, the QA route push and the rotation to
        // settle. Records seeds a sample archive on first use, which is the
        // slowest of them.
        await sleep(6000);
        const problem = pid ? screenshot(device.udid, name, orientation) : "launch failed";
        if (problem) {
          notes[key] = problem;
          missing += 1;
        } else {
          shots[key] = `${name}.png`;
        }
        console.log(`${problem ? `MISS (${problem})` : "ok  "} ${name}`);
      }
    }
  }
  rows.push({ name: scene.name, shots, notes });
}

for (const device of devices) {
  simctl(["terminate", device.udid, BUNDLE_ID], { allowFailure: true });
}

const sheet = join(OUT, "index.html");
writeFileSync(sheet, contactSheet(rows, columns));
console.log(`\n${rows.length} scenes · ${columns.length} columns · ${missing} missing`);
console.log(`open ${relative(ROOT, sheet)}`);
