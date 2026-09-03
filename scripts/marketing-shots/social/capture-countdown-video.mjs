// Record an 8–10s English desktop countdown reaching zero, then stitch to mp4.
import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { readFileSync } from "node:fs";

const CHROME =
  process.env.CHROME_BIN ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9243;
const DIR = new URL(".", import.meta.url).pathname;
const RAW = join(DIR, "raw/countdown-frames");
const OUT = join(DIR, "out");
const PROFILE = join(tmpdir(), "off-work-social-countdown");
const APP_VERSION = JSON.parse(
  readFileSync(new URL("../../../package.json", import.meta.url), "utf8")
).version;

mkdirSync(RAW, { recursive: true });
mkdirSync(OUT, { recursive: true });
for (const name of ["en-countdown-to-zero.mp4"]) {
  rmSync(join(OUT, name), { force: true });
}

const prelude = `(() => {
  const t = new Date();
  t.setHours(17, 59, 51, 0);
  const off = t.getTime() - Date.now();
  const R = Date;
  class F extends R {
    constructor(...a) { super(...(a.length ? a : [R.now() + off])); }
    static now() { return R.now() + off; }
  }
  globalThis.Date = F;
  globalThis.__TAURI_INTERNALS__ = {
    transformCallback: (cb) => { const id = Date.now() + Math.random(); globalThis[\`_\${id}\`] = cb; return id; },
    invoke: async (cmd, args) => {
      if (cmd === "plugin:store|load" || cmd === "plugin:store|get_store") return 1;
      if (cmd === "plugin:store|get") return [null, false];
      if (cmd === "plugin:store|set" || cmd === "plugin:store|save") return null;
      if (cmd === "plugin:event|listen") return 1;
      if (cmd === "plugin:app|version") return ${JSON.stringify(APP_VERSION)};
      if (cmd === "plugin:os|locale") return "en-US";
      if (cmd === "get_mini_window_settings") return { platform: "macos", alwaysOnTop: true, skin: "standard", soundEnabled: false };
      if (cmd === "get_autostart_state") return { enabled: true, locked: false };
      if (cmd === "get_global_shortcut_settings") return { enabled: true, accelerator: "CommandOrControl+Shift+O" };
      return null;
    },
  };
  try {
    localStorage.setItem("desktopPreferredLanguage", "en");
    localStorage.setItem("i18nextLng", "en");
    localStorage.setItem("startTime", "09:00");
    localStorage.setItem("endTime", "18:00");
    localStorage.setItem("showSalary", "true");
    localStorage.setItem("salaryType", "monthly");
    localStorage.setItem("salaryAmount", "12000");
    localStorage.setItem("monthlyWorkingDays", "22");
    localStorage.setItem("theme", "light");
    localStorage.setItem("hideEarnings", "true");
  } catch {}
})();`;

let id = 0;
function send(ws, method, params = {}, sessionId) {
  const n = ++id;
  ws.send(JSON.stringify({ id: n, method, params, sessionId }));
  return new Promise((res, rej) => {
    const on = (e) => {
      const d = JSON.parse(e.data);
      if (d.id !== n) return;
      ws.removeEventListener("message", on);
      d.error ? rej(new Error(`${method}: ${d.error.message}`)) : res(d.result);
    };
    ws.addEventListener("message", on);
    setTimeout(() => rej(new Error(`${method} timed out`)), 60000);
  });
}

const chrome = spawn(CHROME, [
  "--headless=new",
  `--remote-debugging-port=${PORT}`,
  "--hide-scrollbars",
  "--force-color-profile=srgb",
  `--user-data-dir=${PROFILE}`,
  "about:blank",
], { stdio: "ignore" });
process.on("exit", () => chrome.kill());

let wsUrl;
for (let i = 0; i < 40; i++) {
  try {
    wsUrl = (await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json()).webSocketDebuggerUrl;
    break;
  } catch {
    await sleep(250);
  }
}
if (!wsUrl) throw new Error("Chrome DevTools did not start");
const ws = new WebSocket(wsUrl);
await new Promise((r) => ws.addEventListener("open", r, { once: true }));

const { targetId } = await send(ws, "Target.createTarget", { url: "about:blank" });
const { sessionId } = await send(ws, "Target.attachToTarget", { targetId, flatten: true });
await send(ws, "Page.enable", {}, sessionId);
await send(ws, "Runtime.enable", {}, sessionId);
await send(ws, "Emulation.setDeviceMetricsOverride", {
  width: 430,
  height: 430,
  deviceScaleFactor: 2,
  mobile: false,
}, sessionId);
await send(ws, "Page.addScriptToEvaluateOnNewDocument", { source: prelude }, sessionId);
await send(ws, "Page.navigate", { url: "http://localhost:3001/en?platform=macos&s=0900-1800" }, sessionId);
await sleep(3500);
await send(ws, "Page.navigate", { url: "http://localhost:3001/en?platform=macos&s=0900-1800" }, sessionId);
await sleep(2500);
await send(ws, "Runtime.evaluate", {
  expression: `document.querySelectorAll('nextjs-portal').forEach(n => n.remove())`,
}, sessionId);

const started = Date.now();
const frames = [];
while (Date.now() - started < 10_400) {
  const { data } = await send(ws, "Page.captureScreenshot", { format: "png" }, sessionId);
  const idx = String(frames.length).padStart(3, "0");
  const path = join(RAW, `f${idx}.png`);
  writeFileSync(path, Buffer.from(data, "base64"));
  frames.push(path);
}
await send(ws, "Target.closeTarget", { targetId });
ws.close();
chrome.kill();

console.log(`captured ${frames.length} frames`);
const mp4 = join(OUT, "en-countdown-to-zero.mp4");
const ffmpeg = spawnSyncOrThrow("ffmpeg", [
  "-y",
  "-framerate", "5",
  "-i", join(RAW, "f%03d.png"),
  "-c:v", "libx264",
  "-pix_fmt", "yuv420p",
  "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
  "-movflags", "+faststart",
  mp4,
]);
console.log(ffmpeg);
console.log(`wrote ${mp4}`);

function spawnSyncOrThrow(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`${command} failed:\n${result.stderr}`);
  }
  return result.stderr || result.stdout;
}
