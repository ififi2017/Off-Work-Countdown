// One-off social assets: English night-shift desktop window + Windows mini timer.
import { spawn } from "node:child_process";
import { writeFileSync, mkdirSync, readFileSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { captureHtml, flattenPng } from "../chrome.mjs";

const CHROME =
  process.env.CHROME_BIN ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9242;
const DIR = new URL(".", import.meta.url).pathname;
const PROFILE = join(tmpdir(), "off-work-social-capture");
const APP_VERSION = JSON.parse(
  readFileSync(new URL("../../../package.json", import.meta.url), "utf8")
).version;
const RAW = join(DIR, "raw");
const OUT = join(DIR, "out");
mkdirSync(RAW, { recursive: true });
mkdirSync(OUT, { recursive: true });

function fakeClock(hour, minute, second = 8) {
  return `(() => {
  const t = new Date(); t.setHours(${hour}, ${minute}, ${second}, 0);
  const off = t.getTime() - Date.now();
  const R = Date;
  class F extends R {
    constructor(...a) { super(...(a.length ? a : [R.now() + off])); }
    static now() { return R.now() + off; }
  }
  globalThis.Date = F;
})();`;
}

const DAILY = 12000 / 22;
const SHIM = (stateExpr, locale, platform) => `(() => {
  const S = ${stateExpr};
  globalThis.__TAURI_INTERNALS__ = {
    transformCallback: (cb) => { const id = Date.now() + Math.random(); globalThis[\`_\${id}\`] = cb; return id; },
    invoke: async (cmd, args) => {
      if (cmd === "plugin:store|load" || cmd === "plugin:store|get_store") return 1;
      if (cmd === "plugin:store|get") return args && args.key === "countdown" && S ? [S, true] : [null, false];
      if (cmd === "plugin:store|set" || cmd === "plugin:store|save") return null;
      if (cmd === "plugin:event|listen") return 1;
      if (cmd === "plugin:app|version") return ${JSON.stringify(APP_VERSION)};
      if (cmd === "plugin:os|locale") return ${JSON.stringify(locale)};
      if (cmd === "get_mini_window_settings") return { platform: ${JSON.stringify(platform)}, alwaysOnTop: true, skin: "standard", soundEnabled: false };
      if (cmd === "get_autostart_state") return { enabled: true, locked: false };
      if (cmd === "get_global_shortcut_settings") return { enabled: true, accelerator: "CommandOrControl+Shift+O" };
      return null;
    },
  };
})();`;

const seedNight = `${fakeClock(1, 22)}
${SHIM("null", "en-US", "macos")}
try {
  localStorage.setItem("desktopPreferredLanguage", "en");
  localStorage.setItem("i18nextLng", "en");
  localStorage.setItem("startTime", "22:00");
  localStorage.setItem("endTime", "06:00");
  localStorage.setItem("showSalary", "true");
  localStorage.setItem("salaryType", "monthly");
  localStorage.setItem("salaryAmount", "12000");
  localStorage.setItem("monthlyWorkingDays", "22");
  localStorage.setItem("theme", "dark");
} catch {}`;

const miniPrelude = `${fakeClock(14, 22)}
(() => {
  const d = new Date();
  const a = new Date(d); a.setHours(9, 0, 0, 0);
  const b = new Date(d); b.setHours(18, 0, 0, 0);
  const s = {
    segments: [{ startAtMs: a.getTime(), endAtMs: b.getTime() }],
    plannedEndAtMs: b.getTime(), overtimeEndAtMs: null, running: true, nextShift: null,
    notificationMode: "milestones", showSalary: true, hideEarnings: false,
    dailySalary: ${DAILY}, lang: "en",
    countdownNotStarted: "", miniSkin: "standard", woodfishSoundEnabled: false,
    showEarningsLabel: "", hideEarningsLabel: "",
  };
  ${SHIM("s", "en-US", "windows")}
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

async function shot(o) {
  const { targetId } = await send(ws, "Target.createTarget", { url: "about:blank" });
  const { sessionId } = await send(ws, "Target.attachToTarget", { targetId, flatten: true });
  await send(ws, "Page.enable", {}, sessionId);
  await send(ws, "Runtime.enable", {}, sessionId);
  await send(ws, "Emulation.setDeviceMetricsOverride", {
    width: o.w,
    height: o.h,
    deviceScaleFactor: 3,
    mobile: false,
  }, sessionId);
  if (o.transparent) {
    await send(ws, "Emulation.setDefaultBackgroundColorOverride", {
      color: { r: 0, g: 0, b: 0, a: 0 },
    }, sessionId);
  }
  await send(ws, "Page.addScriptToEvaluateOnNewDocument", { source: o.prelude }, sessionId);
  await send(ws, "Page.navigate", { url: o.url }, sessionId);
  await sleep(3000);
  await send(ws, "Page.navigate", { url: o.url }, sessionId);
  await sleep(4000);
  await send(ws, "Runtime.evaluate", {
    expression: `document.querySelectorAll('nextjs-portal').forEach(n => n.remove())`,
  }, sessionId);
  await sleep(200);
  const { data } = await send(ws, "Page.captureScreenshot", { format: "png" }, sessionId);
  writeFileSync(`${RAW}/${o.name}.png`, Buffer.from(data, "base64"));
  console.log(`captured ${o.name}.png`);
  await send(ws, "Target.closeTarget", { targetId });
}

await shot({
  name: "en-night-shift-desktop",
  url: "http://localhost:3001/en?platform=macos&s=2200-0600",
  w: 430,
  h: 430,
  prelude: seedNight,
});

await shot({
  name: "en-windows-mini",
  url: "http://localhost:3001/en/mini",
  w: 248,
  h: 100,
  transparent: true,
  prelude: miniPrelude,
});

ws.close();
chrome.kill();

const miniPng = `file://${join(RAW, "en-windows-mini.png")}`;
const htmlPath = join(tmpdir(), "owc-windows-tray.html");
const html = `<!doctype html>
<meta charset="utf-8">
<style>
  html, body { margin: 0; width: 1600px; height: 900px; overflow: hidden; }
  body {
    background:
      radial-gradient(1200px 700px at 20% 10%, #2b4c7e 0%, transparent 55%),
      radial-gradient(900px 600px at 90% 80%, #1a3a5c 0%, transparent 50%),
      linear-gradient(160deg, #0f1724 0%, #1b2838 48%, #243447 100%);
    font-family: "Segoe UI", "SF Pro Text", sans-serif;
  }
  .taskbar {
    position: absolute; left: 0; right: 0; bottom: 0; height: 48px;
    background: #1c1c1ccc; backdrop-filter: blur(20px);
    border-top: 1px solid rgba(255,255,255,0.08);
    display: flex; align-items: center; justify-content: space-between;
    padding: 0 14px 0 10px; color: #fff;
  }
  .start {
    width: 36px; height: 36px; border-radius: 8px;
    display: grid; place-items: center;
    background: rgba(255,255,255,0.06);
  }
  .start-mark {
    width: 16px; height: 16px;
    background:
      linear-gradient(#00a4ef 0 0) 0 0 / 7px 7px no-repeat,
      linear-gradient(#7fba00 0 0) 9px 0 / 7px 7px no-repeat,
      linear-gradient(#f25022 0 0) 0 9px / 7px 7px no-repeat,
      linear-gradient(#ffb900 0 0) 9px 9px / 7px 7px no-repeat;
  }
  .tray { display: flex; align-items: center; gap: 14px; font-size: 12px; letter-spacing: 0.01em; }
  .mini {
    position: absolute; right: 28px; bottom: 68px; width: 248px; height: 100px;
    filter: drop-shadow(0 8px 18px rgba(0,0,0,0.35));
  }
</style>
<div class="taskbar">
  <div class="start"><div class="start-mark"></div></div>
  <div class="tray"><span>ENG</span><span>2:22 PM</span></div>
</div>
<img class="mini" src="${miniPng}" alt="">
`;
await captureHtml({
  html,
  htmlPath,
  width: 1600,
  height: 900,
  scale: 2,
  outFile: join(OUT, "en-windows-mini-tray.png"),
});
flattenPng(join(OUT, "en-windows-mini-tray.png"));
console.log("done desktop social captures");
