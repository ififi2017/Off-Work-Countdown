// Capture the six portrait surfaces used by the App Store artwork:
// working timer, Home Screen widgets, lunch, Records, Life and Focus.
// Raw names match compose.mjs.
//
// The app already has DEBUG-only QA defaults for deterministic navigation and
// orientation. This script uses those hooks instead of adding screenshot code
// to the shipping build. Raw simulator frames stay in raw/ and are ignored.

import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const DIR = new URL(".", import.meta.url).pathname;
const ROOT = new URL("../../../", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const PREVIEW_RAW = join(DIR, "previews/raw");
const DERIVED_DATA = join(tmpdir(), "off-work-countdown-ios-shots-derived-data");
const PROJECT = join(ROOT, "src-mobile/ios/App/App.xcodeproj");
const BUNDLE_ID = "com.rainif.offworkcountdown.macappstore";
const IPHONE_NAME = process.env.IOS_SHOTS_IPHONE || "iPhone 17 Pro Max";
const IPAD_NAME = process.env.IOS_SHOTS_IPAD || "iPad Pro 13-inch (M5)";
const PLATFORM = process.env.IOS_SHOTS_PLATFORM || "all";
const SCENE = process.env.IOS_SHOTS_SCENE;
const MODE = process.env.IOS_SHOTS_MODE || "screenshots";
const BEAT = process.env.IOS_SHOTS_BEAT;

if (!["all", "iphone", "ipad"].includes(PLATFORM)) {
  throw new Error("IOS_SHOTS_PLATFORM must be all, iphone, or ipad");
}
if (SCENE && !["1", "2", "3", "4", "5", "6"].includes(SCENE)) {
  throw new Error("IOS_SHOTS_SCENE must be 1 through 6");
}
if (!["screenshots", "previews"].includes(MODE)) {
  throw new Error("IOS_SHOTS_MODE must be screenshots or previews");
}

mkdirSync(RAW, { recursive: true });
mkdirSync(PREVIEW_RAW, { recursive: true });

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

function resetPersistedQaState(udid) {
  const container = containerPath(udid);
  if (container) {
    rmSync(join(container, "Library/Application Support/owc-records"), { recursive: true, force: true });
  }
}

function disableReviewPrompt(udid) {
  // `defaults write` loses the race with cfprefsd: a finished 17:00 shift
  // stays in `activeCountdownEndAtMs`, the next evening launch decodes
  // `readyForNextLaunch`, and the review alert covers every shot.
  const container = containerPath(udid);
  if (!container) return;
  const pref = join(container, `Library/Preferences/${BUNDLE_ID}.plist`);
  run("python3", ["-c", `
import plistlib, pathlib
p = pathlib.Path(${JSON.stringify(pref)})
data = plistlib.loads(p.read_bytes()) if p.exists() else {}
data["ios.native.appReviewPrompt.v1"] = b'{"phase":"never"}'
data.pop("ios.native.activeCountdownEndAtMs", None)
p.parent.mkdir(parents=True, exist_ok=True)
p.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
`], { allowFailure: true });
}

function grantNotifications(udid) {
  const tcc = join(
    process.env.HOME,
    "Library/Developer/CoreSimulator/Devices",
    udid,
    "data/Library/TCC/TCC.db",
  );
  for (const service of [
    "kTCCServiceNotifications",
    "kTCCServiceUserNotifications",
    "kTCCServiceBulletinBoard",
  ]) {
    run("sqlite3", [tcc, `INSERT OR REPLACE INTO access (
        service, client, client_type, auth_value, auth_reason, auth_version,
        indirect_object_identifier, flags, last_modified
      ) VALUES (
        '${service}', '${BUNDLE_ID}', 0, 2, 2, 1, 'UNUSED', 0,
        CAST(strftime('%s','now') AS INTEGER)
      );`], { allowFailure: true });
  }
}

const notificationDismissed = new Set();

function clickSimulatorWindow(nameContains, relX, relY) {
  const script = `
tell application "Simulator" to activate
delay 0.12
tell application "System Events"
  tell process "Simulator"
    set frontmost to true
    set win to first window whose name contains "${nameContains}"
    set {wx, wy} to position of win
    set {ww, wh} to size of win
    set ax to (wx + (ww * ${relX})) as integer
    set ay to (wy + (wh * ${relY})) as integer
    return (ax as text) & "," & (ay as text)
  end tell
end tell
`;
  const point = run("osascript", ["-e", script], { capture: true, allowFailure: true }).trim();
  if (!/^\d+,\d+$/.test(point)) return;
  const [x, y] = point.split(",");
  run("osascript", ["-e", `tell application "System Events" to click at {${x}, ${y}}`], {
    allowFailure: true,
  });
}

function dismissFocusNotification(udid) {
  if (notificationDismissed.has(udid)) return;
  const name = udid === ipad ? "iPad" : "iPhone";
  // Allow is the right button of the two-button system sheet.
  clickSimulatorWindow(name, 0.64, 0.505);
  notificationDismissed.add(udid);
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
    "-ios.native.languageOverride", language,
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
    "-ios.native.qaOnboardingPage", scene.onboardingPage == null ? "" : String(scene.onboardingPage),
    "-ios.native.qaRoute", scene.route ?? "",
    "-ios.native.qaRecordsScale", scene.recordsScale ?? "",
    "-ios.native.qaDebugScenario", scene.scenario ?? "",
    "-ios.native.qaFocusScenario", scene.focusScenario ?? "",
  ];
  terminate(udid);
  resetPersistedQaState(udid);
  disableReviewPrompt(udid);
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
  ], { timeoutMs: 180_000 });
}

async function waitForSurface(udid, expected) {
  const deadline = Date.now() + 30_000;
  let shown = null;
  const started = Date.now();
  while (Date.now() < deadline) {
    shown = surface(udid);
    if (shown === expected) return;
    if (expected === "route.focus" && shown === "settings" && Date.now() - started > 4_000) {
      return;
    }
    await sleep(250);
  }
  throw new Error(`Expected ${expected} before capture, app reported ${shown ?? "no surface marker"}`);
}

async function screenshot(udid, name, expected, settleMs = 1400) {
  await waitForSurface(udid, expected);
  await sleep(settleMs);
  if (!isRunning(udid)) throw new Error(`Refusing ${name}.png: app is not running`);
  const shown = surface(udid);
  // Focus is pushed on the settings stack. Dismissing the notification
  // sheet can make Settings rewrite the marker without leaving Focus.
  if (shown !== expected && !(expected === "route.focus" && shown === "settings")) {
    throw new Error(`Refusing ${name}.png: expected ${expected}, app reported ${shown ?? "no surface marker"}`);
  }
  const path = join(RAW, `${name}.png`);
  rmSync(path, { force: true });
  simctl(["io", udid, "screenshot", "--type=png", "--mask=ignored", path]);
  console.log(`captured ${name}.png`);
}

// MARK: - App Preview clips
//
// The store preview is a different job from the six stills: it has to show the
// things a frame cannot — digits moving, a bar filling, a card that keeps
// counting on the Lock Screen. It reuses the same seeds so the footage and the
// screenshots describe the same fictional day, salary included.

function pressSimulatorKeys(keystroke, modifiers) {
  // Home and Lock have no simctl verb. The Simulator's own menu keys do, and
  // System Events is already how this script dismisses the notification sheet.
  const using = modifiers.map((name) => `${name} down`).join(", ");
  run("osascript", ["-e", `
tell application "Simulator" to activate
delay 0.2
tell application "System Events" to keystroke "${keystroke}" using {${using}}
`], { allowFailure: true });
}

async function recordClip(udid, name, expected, {
  holdMs = 6_000,
  settleMs = 1_200,
  before = null,
  during = null,
  fromLaunch = false,
} = {}) {
  // Records and Life are still pictures once they have settled: an ambient
  // clip of them is a screenshot that costs a megabyte. Their motion is the
  // entry animation — bars growing, the life grid filling — so those beats
  // start the recorder before the view has assembled and check the surface
  // afterwards instead.
  if (expected && !fromLaunch) await waitForSurface(udid, expected);
  await sleep(settleMs);
  if (!isRunning(udid)) throw new Error(`Refusing ${name}.mov: app is not running`);
  const path = join(PREVIEW_RAW, `${name}.mov`);
  rmSync(path, { force: true });
  if (before) await before(udid);
  const recorder = spawn("xcrun", [
    "simctl", "io", udid, "recordVideo",
    "--codec", "h264", "--mask", "ignored", "--force", path,
  ], { stdio: "ignore" });
  const exited = new Promise((resolve) => recorder.once("exit", resolve));
  // recordVideo writes its header lazily; stopping too early yields no file.
  await sleep(900);
  if (during) await during();
  await sleep(holdMs);
  recorder.kill("SIGINT");
  await exited;
  if (expected && fromLaunch) {
    const shown = surface(udid);
    if (shown !== expected && !(expected === "route.focus" && shown === "settings")) {
      throw new Error(`Refusing ${name}.mov: expected ${expected}, app reported ${shown ?? "no surface marker"}`);
    }
  }
  // Bytes are the wrong measure: a locked screen barely changes, so a perfectly
  // good eight-second clip of it compresses to less than a second of the timer
  // page. Duration is the better one, but read it for what it is: the recorder
  // encodes on display change, so this is how long the screen *moved*, not how
  // long it was held. That is the check worth having — a beat that fails it is
  // a beat with nothing to film, and belongs in the stills instead.
  const bytes = statSync(path, { throwIfNoEntry: false })?.size ?? 0;
  if (bytes === 0) throw new Error(`Refusing ${name}.mov: the recorder wrote no file`);
  const probed = run("ffprobe", [
    "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path,
  ], { capture: true, allowFailure: true }).trim();
  const seconds = Number.parseFloat(probed);
  const wanted = (holdMs + 900) / 1000;
  if (Number.isFinite(seconds)) {
    if (seconds < wanted * 0.6) {
      throw new Error(
        `Refusing ${name}.mov: ${seconds.toFixed(2)}s captured of ${wanted.toFixed(1)}s held`,
      );
    }
    console.log(`recorded ${name}.mov (${seconds.toFixed(1)}s, ${(bytes / 1_048_576).toFixed(1)} MB)`);
    return;
  }
  // No ffprobe on this machine: fall back to the crude floor rather than
  // silently accepting whatever landed.
  if (bytes < 50_000) {
    throw new Error(`Refusing ${name}.mov: only ${bytes} bytes and no ffprobe to check duration`);
  }
  console.log(`recorded ${name}.mov (${(bytes / 1_048_576).toFixed(1)} MB, duration unchecked)`);
}

// Each beat is one shot of the script: what to seed, what has to be on screen
// before the recorder starts, and how long the editor needs.
const PREVIEW_BEATS = [
  {
    id: "1",
    slug: "timer",
    scene: { orientation: "portrait", scenario: "working" },
    expects: "timer",
    holdMs: 6_000,
  },
  {
    id: "2",
    slug: "lockscreen",
    // Opt-in only, and probably not worth using. Two things are wrong with it
    // and neither is fixable from here: `simctl io recordVideo` keeps
    // returning well under a second once the device is locked, and the
    // simulator reports the locked screen as luminance-reduced, so the card
    // draws the always-on variant ("21 minutes") rather than the ticking one
    // a lit screen shows. A store preview cannot show a Lock Screen honestly
    // this way; the widgets and the island are the stills' job instead.
    optIn: true,
    // The one surface that keeps moving with the app closed. This beat is
    // deliberately the only one without a debug scenario: those pin a 09:00
    // to 17:00 day on the virtual clock, which leaves hours to go and no
    // activity at all. The plain seed ends the shift 29 minutes out, inside
    // the 30 minute lead, so the card is published before the screen locks.
    scene: { orientation: "portrait" },
    expects: "timer",
    holdMs: 7_000,
    // The card and the Lock Screen widgets are both drawn by the extension,
    // and the extension is never woken again once the screen is locked. So
    // everything has to be published *before* the lock: ActivityKit needs a
    // moment after launch, and so does the widget timeline reload.
    settleMs: 8_000,
    before: async () => {
      pressSimulatorKeys("h", ["command", "shift"]);
      await sleep(3_000);
      pressSimulatorKeys("l", ["command"]);
      await sleep(3_000);
    },
  },
  {
    id: "3",
    slug: "lunch",
    scene: { orientation: "portrait", scenario: "lunch", liveActivity: false },
    expects: "timer",
    holdMs: 5_000,
  },
  {
    id: "4",
    slug: "records-week",
    scene: { orientation: "portrait", recordsScale: "week", liveActivity: false },
    expects: "records",
    holdMs: 9_000,
    settleMs: 0,
    fromLaunch: true,
  },
  {
    id: "5",
    slug: "life",
    // Opt-in, and the answer is usually the still. `simctl io recordVideo`
    // encodes on display change, so a screen that does not move yields a
    // near-empty file however long the recorder is held — this beat returned
    // 7.7s, then 2.75s, then 0.07s of the same eight second hold, purely on
    // how much happened to redraw. Life is a picture: use `en-5-life.png`
    // from the stills and give it a slow push in the edit.
    optIn: true,
    scene: { orientation: "portrait", recordsScale: "life", liveActivity: false },
    expects: "records",
    holdMs: 7_000,
    // No `fromLaunch` here, unlike the week view. Life does seconds of real
    // work as it comes up, and recording through that starved the recorder:
    // it returned 2.75s of a held 7.9s. It has no entry animation worth
    // catching anyway — this beat is a still, and the push belongs to the edit.
    settleMs: 2_500,
  },
  {
    id: "6",
    slug: "focus",
    scene: {
      orientation: "portrait",
      route: "focus",
      focusScenario: "runningFocus",
      liveActivity: false,
    },
    expects: "route.focus",
    holdMs: 7_000,
    settleMs: 2_400,
    before: async (udid) => dismissFocusNotification(udid),
  },
];

async function capturePreviews(udid, language) {
  const { stem } = LANGUAGES[language];
  for (const beat of PREVIEW_BEATS) {
    if (BEAT ? BEAT !== beat.id : beat.optIn) continue;
    launch(udid, language, beat.scene);
    const locks = beat.slug === "lockscreen";
    if (locks) {
      // Locking hides the surface marker's view, so read it before the keys.
      await waitForSurface(udid, beat.expects);
    }
    try {
      await recordClip(udid, `${stem}-${beat.id}-${beat.slug}`, locks ? null : beat.expects, {
        holdMs: beat.holdMs,
        settleMs: beat.settleMs ?? 1_200,
        before: beat.before,
        during: beat.during,
        fromLaunch: beat.fromLaunch === true,
      });
    } finally {
      // The Simulator has no unlock verb, only a Lock key that toggles, so the
      // beat is only repeatable if it always leaves the device the way it found
      // it. A throw between the lock and the unlock is what made the next run
      // record a dark screen for six seconds.
      if (locks) {
        pressSimulatorKeys("l", ["command"]);
        await sleep(1_500);
      }
    }
  }
}

const LANGUAGES = {
  en: { stem: "en", appleLanguage: "en", appleLocale: "en_US" },
  "zh-CN": { stem: "zh", appleLanguage: "zh-Hans", appleLocale: "zh_CN" },
  "zh-TW": { stem: "zh-tw", appleLanguage: "zh-Hant", appleLocale: "zh_TW" },
  ja: { stem: "ja", appleLanguage: "ja", appleLocale: "ja_JP" },
  ko: { stem: "ko", appleLanguage: "ko", appleLocale: "ko_KR" },
  de: { stem: "de", appleLanguage: "de", appleLocale: "de_DE" },
  es: { stem: "es", appleLanguage: "es", appleLocale: "es_ES" },
  fr: { stem: "fr", appleLanguage: "fr", appleLocale: "fr_FR" },
  it: { stem: "it", appleLanguage: "it", appleLocale: "it_IT" },
  pt: { stem: "pt", appleLanguage: "pt", appleLocale: "pt_BR" },
  ru: { stem: "ru", appleLanguage: "ru", appleLocale: "ru_RU" },
  ar: { stem: "ar", appleLanguage: "ar", appleLocale: "ar_SA" },
  "hi-IN": { stem: "hi", appleLanguage: "hi", appleLocale: "hi_IN" },
  id: { stem: "id", appleLanguage: "id", appleLocale: "id_ID" },
  th: { stem: "th", appleLanguage: "th", appleLocale: "th_TH" },
  tr: { stem: "tr", appleLanguage: "tr", appleLocale: "tr_TR" },
  vi: { stem: "vi", appleLanguage: "vi", appleLocale: "vi_VN" },
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
    await sleep(1600);
    dismissFocusNotification(udid);
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
    await sleep(2000);
    dismissFocusNotification(udid);
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

function applySimulatorChrome(udid) {
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

for (const udid of [iphone, ipad].filter(Boolean)) {
  simctl(["boot", udid], { allowFailure: true });
  simctl(["bootstatus", udid, "-b"]);
  // Installing over the QA copy preserves the native notification choice;
  // deleting it would put a system permission sheet over every Focus run.
  if (process.env.IOS_SHOTS_SKIP_INSTALL !== "1") {
    simctl(["install", udid, appPath]);
  }
  grantNotifications(udid);
  terminate(udid);
  disableReviewPrompt(udid);
  // iOS Simulator has no killall. A reboot makes cfprefsd reread `phase=never`.
  // Skip it on later runs: install+reboot also resets notification auth and
  // puts the system sheet back over Focus.
  if (process.env.IOS_SHOTS_REBOOT === "1") {
    simctl(["shutdown", udid]);
    simctl(["boot", udid]);
    simctl(["bootstatus", udid, "-b"]);
    grantNotifications(udid);
    disableReviewPrompt(udid);
  }
  applySimulatorChrome(udid);
}

const languages = process.env.IOS_SHOTS_LANGUAGE
  ? process.env.IOS_SHOTS_LANGUAGE.split(",").map((value) => value.trim())
  : Object.keys(LANGUAGES);
if (languages.some((language) => !LANGUAGES[language])) {
  throw new Error(`IOS_SHOTS_LANGUAGE must be one of ${Object.keys(LANGUAGES).join(", ")}`);
}
for (const language of languages) {
  if (MODE === "previews") {
    // App Previews exist only as IPHONE_67, so the iPad never records one.
    if (!iphone) throw new Error("IOS_SHOTS_MODE=previews needs the iPhone; set IOS_SHOTS_PLATFORM=iphone");
    await capturePreviews(iphone, language);
    continue;
  }
  if (iphone) await capturePhone(iphone, language);
  if (ipad) await capturePad(ipad, language);
}

if (iphone) terminate(iphone);
if (ipad) terminate(ipad);
console.log(`done: raw simulator captures are in ${MODE === "previews" ? PREVIEW_RAW : RAW}`);
