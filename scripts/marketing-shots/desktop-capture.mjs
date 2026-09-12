// 截桌面应用界面：Mac App Store 与微软商店两套图共用。
//
// 用 headless Chrome 打开 `npm run dev:desktop`（固定端口 3001），注入一份
// `__TAURI_INTERNALS__` 的假实现，让 Web 版以为自己跑在 Tauri 里。`platform`
// 决定主窗画哪种标题栏：macos 留出覆盖式标题栏的空白（交通灯由 compose 补画），
// windows 由应用自己画最小化 / 关闭按钮——这两个 `?platform=` 分支只存在于开发
// 构建，所以必须对着 dev server 截。
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

// Chrome 装在别处时用 CHROME_BIN 覆盖。用 Chrome 而不是仓库里其它无头方案，
// 是因为这套图依赖 macOS 上的 SF Pro / PingFang SC 字体渲染。
const CHROME =
  process.env.CHROME_BIN ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9241;
const ROOT = new URL("../../", import.meta.url);
// 设置页里会显示版本号。写死的话每次发版这套图就悄悄过期了，直接读 package.json。
const APP_VERSION = JSON.parse(readFileSync(new URL("package.json", ROOT), "utf8")).version;

// 整套图钉在同一刻：2026-09-24（周四）14:22:08。钉日期而不只是钟点，统计页的
// 月份和「今天」才不会随截图那天漂移，迷你窗上的木鱼数也和统计页那天对得上。
const NOW = [2026, 8, 24, 14, 22, 8];
const FAKE_CLOCK = `(() => {
  const off = new Date(${NOW.join(", ")}).getTime() - Date.now();
  const R = Date;
  class F extends R {
    constructor(...a) { super(...(a.length ? a : [R.now() + off])); }
    static now() { return R.now() + off; }
  }
  globalThis.Date = F;
})();`;

// 九月 1–24 日的工作日：每天按 8 小时记，四天有加班；周六那天没开计时器，只敲了
// 木鱼——统计页会把它记成「未开启计时器」，正好让画面里两种日子都出现。
function seedStats() {
  const knocks = [42, 18, 96, 7, 63, 25, 131, 54, 12, 88, 36, 71, 9, 47, 120, 58, 33, 64];
  const overtimeMinutes = { 3: 90, 8: 45, 11: 120, 15: 30 };
  const days = {};
  let index = 0;
  for (let day = 1; day <= NOW[2]; day += 1) {
    const weekday = new Date(NOW[0], NOW[1], day).getDay();
    if (weekday === 0 || weekday === 6) continue;
    days[`2026-09-${String(day).padStart(2, "0")}`] = {
      attended: true,
      plannedMs: 8 * 3_600_000,
      overtimeMs: (overtimeMinutes[index] ?? 0) * 60_000,
      woodfishCount: knocks[index],
    };
    index += 1;
  }
  days["2026-09-19"] = { attended: false, plannedMs: 0, overtimeMs: 0, woodfishCount: 21 };
  return { days };
}

// 迷你窗读的是 Store 里正在跑的班次；主窗不给快照，由 localStorage 里的设置起算。
function runningShift(lang) {
  const at = (hour) => new Date(NOW[0], NOW[1], NOW[2], hour).getTime();
  return {
    segments: [{ startAtMs: at(9), endAtMs: at(18) }],
    plannedEndAtMs: at(18), overtimeEndAtMs: null, running: true, nextShift: null,
    notificationMode: "milestones", showSalary: true, hideEarnings: false,
    dailySalary: 12000 / 22, lang,
    countdownNotStarted: "", miniSkin: "standard", woodfishSoundEnabled: false,
    showEarningsLabel: "", hideEarningsLabel: "",
  };
}

const shim = ({ countdown, locale, platform }) => `(() => {
  const store = { countdown: ${JSON.stringify(countdown)}, stats: ${JSON.stringify(seedStats())} };
  globalThis.__TAURI_INTERNALS__ = {
    transformCallback: (cb) => { const id = Date.now() + Math.random(); globalThis[\`_\${id}\`] = cb; return id; },
    invoke: async (cmd, args) => {
      if (cmd === "plugin:store|load" || cmd === "plugin:store|get_store") return 1;
      if (cmd === "plugin:store|get") { const v = args && store[args.key]; return v ? [v, true] : [null, false]; }
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

const seedMain = (lang, locale, platform) => `${FAKE_CLOCK}
${shim({ countdown: null, locale, platform })}
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

const seedMini = (lang, locale, platform) => `${FAKE_CLOCK}
${shim({ countdown: runningShift(lang), locale, platform })}`;

// 设置按钮的 aria-label 就是 t("settings")；按译文精确匹配，17 种语言都点得到。
const openSettingsSteps = (labels) => `
  const settings = [...document.querySelectorAll('button')].find((x) => x.getAttribute('aria-label') === ${JSON.stringify(labels.settings)});
  if (!settings) throw new Error("settings button not found");
  settings.click();
  await new Promise((r) => setTimeout(r, 600));`;

const openSettings = (labels) => `(async () => {${openSettingsSteps(labels)}
})()`;

// 统计页在设置里，入口是一行按钮，文字就是 desktopStats 的译文。
const openStats = (labels) => `(async () => {${openSettingsSteps(labels)}
  const entry = [...document.querySelectorAll('button')].find((x) => x.textContent.trim() === ${JSON.stringify(labels.stats)});
  if (!entry) throw new Error("stats entry not found");
  entry.click();
  await new Promise((r) => setTimeout(r, 900));
})()`;

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

async function shot(ws, outDir, o) {
  const { targetId } = await send(ws, "Target.createTarget", { url: "about:blank" });
  const { sessionId } = await send(ws, "Target.attachToTarget", { targetId, flatten: true });
  await send(ws, "Page.enable", {}, sessionId);
  await send(ws, "Runtime.enable", {}, sessionId);
  await send(ws, "Emulation.setDeviceMetricsOverride",
    { width: o.w, height: o.h, deviceScaleFactor: o.scale ?? 3, mobile: false }, sessionId);
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
    // 找不到按钮时要停下来：否则截到的是上一屏，而脚本照样报成功。
    const result = await send(ws, "Runtime.evaluate", { expression: o.after, awaitPromise: true }, sessionId);
    if (result.exceptionDetails) {
      throw new Error(`${o.name}: ${result.exceptionDetails.exception?.description ?? result.exceptionDetails.text}`);
    }
    await sleep(1200);
  }
  await send(ws, "Runtime.evaluate", {
    expression: `document.querySelectorAll('nextjs-portal').forEach(n => n.remove())`,
  }, sessionId);
  await sleep(200);
  const { data } = await send(ws, "Page.captureScreenshot", { format: "png" }, sessionId);
  writeFileSync(join(outDir, `${o.name}.png`), Buffer.from(data, "base64"));
  console.log(`captured ${o.name}.png`);
  await send(ws, "Target.closeTarget", { targetId });
}

export async function captureDesktop({
  platform,
  outDir,
  languages = [["en", "en-US"], ["zh-CN", "zh-CN"]],
}) {
  mkdirSync(outDir, { recursive: true });
  // Chrome 的用户目录放到仓库外：它里面带着 Chrome 自带扩展的 JS，留在仓库里
  // `eslint .` 会去 lint 它们并报错。.gitignore 挡得住 git，挡不住 eslint。
  const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`,
    "--hide-scrollbars", "--force-color-profile=srgb",
    `--user-data-dir=${join(tmpdir(), `off-work-shots-capture-${platform}`)}`, "about:blank"],
  { stdio: "ignore" });
  process.on("exit", () => chrome.kill());

  let wsUrl;
  for (let i = 0; i < 40 && !wsUrl; i++) {
    try { wsUrl = (await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json()).webSocketDebuggerUrl; }
    catch { await sleep(250); }
  }
  if (!wsUrl) throw new Error("Chrome DevTools did not start");
  const ws = new WebSocket(wsUrl);
  await new Promise((r) => ws.addEventListener("open", r, { once: true }));

  // DESKTOP_SHOTS_LANGUAGE=ja,ko 只重截其中几种语言。
  const only = process.env.DESKTOP_SHOTS_LANGUAGE?.split(",").map((value) => value.trim());
  for (const [lang, locale] of languages.filter(([lang]) => !only || only.includes(lang))) {
    const t = JSON.parse(readFileSync(new URL(`public/locales/${lang}/translation.json`, ROOT), "utf8"));
    const labels = { settings: t.settings, stats: t.desktopStats };
    const base = `http://localhost:3001/${lang}?platform=${platform}`;
    const main = { w: 430, h: 430, prelude: seedMain(lang, locale, platform) };
    await shot(ws, outDir, { ...main, name: `${lang}-countdown`, url: `${base}&s=0900-1800` });
    await shot(ws, outDir, { ...main, name: `${lang}-setup`, url: base });
    await shot(ws, outDir, { ...main, name: `${lang}-settings`, url: base, after: openSettings(labels) });
    await shot(ws, outDir, { ...main, name: `${lang}-stats`, url: base, after: openStats(labels) });
    // 迷你窗在成品里放得比 1:1 大，按 5 倍截才不会糊。
    await shot(ws, outDir, {
      name: `${lang}-mini-woodfish`, url: `http://localhost:3001/${lang}/mini?skin=woodfish`,
      w: 248, h: 100, scale: 5, transparent: true, prelude: seedMini(lang, locale, platform),
    });
  }

  ws.close();
  chrome.kill();
  console.log("done");
}
