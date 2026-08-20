// 截 macOS 形态的应用界面。与 Windows 那轮的区别：?platform=macos，
// 且 shim 里 get_mini_window_settings 报 macos —— 主窗会按覆盖式标题栏
// 给交通灯留出顶部空间（真正的交通灯由 macOS 画，浏览器里是空的，
// 由 compose.mjs 按真实位置补上）。
import { spawn } from "node:child_process";
import { writeFileSync, mkdirSync, readFileSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Chrome 装在别处时用 CHROME_BIN 覆盖。用 Chrome 而不是仓库里其它无头方案，
// 是因为这套图依赖 macOS 上的 SF Pro / PingFang SC 字体渲染。
const CHROME =
  process.env.CHROME_BIN ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9241;
const DIR = new URL(".", import.meta.url).pathname;
// Chrome 的用户目录放到仓库外：它里面带着 Chrome 自带扩展的 JS，留在仓库里
// `eslint .` 会去 lint 它们并报错。.gitignore 挡得住 git，挡不住 eslint。
const PROFILE = join(tmpdir(), "off-work-shots-capture");
// 设置页里会显示版本号。写死的话每次发版这套图就悄悄过期了，直接读 package.json。
const APP_VERSION = JSON.parse(
  readFileSync(new URL("../../../package.json", import.meta.url), "utf8")
).version;
const OUT = `${DIR}raw/`;
mkdirSync(OUT, { recursive: true });

const FAKE_CLOCK = `(() => {
  const t = new Date(); t.setHours(14, 22, 8, 0);
  const off = t.getTime() - Date.now();
  const R = Date;
  class F extends R {
    constructor(...a) { super(...(a.length ? a : [R.now() + off])); }
    static now() { return R.now() + off; }
  }
  globalThis.Date = F;
})();`;

const DAILY = 12000 / 22;
const SHIM = (stateExpr, locale) => `(() => {
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
      if (cmd === "get_mini_window_settings") return { platform: "macos", alwaysOnTop: true, skin: "standard", soundEnabled: false };
      if (cmd === "get_autostart_state") return { enabled: true, locked: false };
      if (cmd === "get_global_shortcut_settings") return { enabled: true, accelerator: "CommandOrControl+Shift+O" };
      return null;
    },
  };
})();`;

const seedMain = (lang, locale) => `${FAKE_CLOCK}
${SHIM("null", locale)}
try {
  localStorage.setItem("desktopPreferredLanguage", ${JSON.stringify(lang)});
  localStorage.setItem("i18nextLng", ${JSON.stringify(lang)});
  localStorage.setItem("startTime", "09:00");
  localStorage.setItem("endTime", "18:00");
  localStorage.setItem("showSalary", "true");
  localStorage.setItem("salaryType", "monthly");
  localStorage.setItem("salaryAmount", "12000");
  localStorage.setItem("monthlyWorkingDays", "22");
  localStorage.setItem("theme", "light");
} catch {}`;

const miniPrelude = (lang, locale) => `${FAKE_CLOCK}
(() => {
  const d = new Date();
  const a = new Date(d); a.setHours(9, 0, 0, 0);
  const b = new Date(d); b.setHours(18, 0, 0, 0);
  const s = {
    segments: [{ startAtMs: a.getTime(), endAtMs: b.getTime() }],
    plannedEndAtMs: b.getTime(), overtimeEndAtMs: null, running: true, nextShift: null,
    notificationMode: "milestones", showSalary: true, hideEarnings: false,
    dailySalary: ${DAILY}, lang: ${JSON.stringify(lang)},
    countdownNotStarted: "", miniSkin: "standard", woodfishSoundEnabled: false,
    showEarningsLabel: "", hideEarningsLabel: "",
  };
  ${SHIM("s", locale)}
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

const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`,
  "--hide-scrollbars", "--force-color-profile=srgb",
  `--user-data-dir=${PROFILE}`, "about:blank"], { stdio: "ignore" });
process.on("exit", () => chrome.kill());

let wsUrl;
for (let i = 0; i < 40; i++) {
  try { wsUrl = (await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json()).webSocketDebuggerUrl; break; }
  catch { await sleep(250); }
}
const ws = new WebSocket(wsUrl);
await new Promise((r) => ws.addEventListener("open", r, { once: true }));

async function shot(o) {
  const { targetId } = await send(ws, "Target.createTarget", { url: "about:blank" });
  const { sessionId } = await send(ws, "Target.attachToTarget", { targetId, flatten: true });
  await send(ws, "Page.enable", {}, sessionId);
  await send(ws, "Runtime.enable", {}, sessionId);
  await send(ws, "Emulation.setDeviceMetricsOverride",
    { width: o.w, height: o.h, deviceScaleFactor: 3, mobile: false }, sessionId);
  if (o.transparent) {
    await send(ws, "Emulation.setDefaultBackgroundColorOverride",
      { color: { r: 0, g: 0, b: 0, a: 0 } }, sessionId);
  }
  await send(ws, "Page.addScriptToEvaluateOnNewDocument", { source: o.prelude }, sessionId);
  await send(ws, "Page.navigate", { url: o.url }, sessionId);
  await sleep(3000);
  await send(ws, "Page.navigate", { url: o.url }, sessionId);
  await sleep(4000);
  if (o.after) {
    await send(ws, "Runtime.evaluate", { expression: o.after, awaitPromise: true }, sessionId);
    await sleep(1200);
  }
  await send(ws, "Runtime.evaluate", {
    expression: `document.querySelectorAll('nextjs-portal').forEach(n => n.remove())`,
  }, sessionId);
  await sleep(200);
  const { data } = await send(ws, "Page.captureScreenshot", { format: "png" }, sessionId);
  writeFileSync(`${OUT}${o.name}.png`, Buffer.from(data, "base64"));
  console.log(`captured ${o.name}.png`);
  await send(ws, "Target.closeTarget", { targetId });
}

const openSettings = `(async () => {
  const b = [...document.querySelectorAll('button')].find((x) => /settings|设置/i.test(x.getAttribute('aria-label') || ''));
  if (b) b.click();
  await new Promise((r) => setTimeout(r, 600));
})()`;

for (const [lang, locale] of [["en", "en-US"], ["zh-CN", "zh-CN"]]) {
  const base = `http://localhost:3001/${lang}?platform=macos`;
  await shot({ name: `${lang}-countdown`, url: `${base}&s=0900-1800`, w: 430, h: 430, prelude: seedMain(lang, locale) });
  await shot({ name: `${lang}-setup`, url: base, w: 430, h: 430, prelude: seedMain(lang, locale) });
  await shot({ name: `${lang}-settings`, url: base, w: 430, h: 430, prelude: seedMain(lang, locale), after: openSettings });
  await shot({ name: `${lang}-mini`, url: `http://localhost:3001/${lang}/mini`, w: 248, h: 100, transparent: true, prelude: miniPrelude(lang, locale) });
  await shot({ name: `${lang}-mini-woodfish`, url: `http://localhost:3001/${lang}/mini?skin=woodfish`, w: 248, h: 100, transparent: true, prelude: miniPrelude(lang, locale) });
}

ws.close(); chrome.kill();
console.log("done");
