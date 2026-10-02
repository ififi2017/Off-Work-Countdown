// 截 Chrome 扩展弹窗的真实界面，存进 raw/。先跑 `npm run build:extension`。
//
// 用 node:http 把 build/chrome-extension 当静态站点起在本机，headless Chrome 走
// CDP 打开 popup.html。页面加载前注入固定时钟和 localStorage 里的设置——弹窗没有
// chrome.* 依赖，所以普通网页里渲染出来的就是工具栏里那一屏。
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { extname, join, normalize } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { LISTINGS } from "./listing-copy.mjs";

const CHROME =
  process.env.CHROME_BIN ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const CDP_PORT = 9243;
const ROOT = new URL("../../../", import.meta.url).pathname;
const BUILD = join(ROOT, "build/chrome-extension");
const RAW = new URL("raw/", import.meta.url).pathname;

if (!existsSync(join(BUILD, "popup.html"))) {
  throw new Error("Missing build/chrome-extension. Run npm run build:extension first.");
}
mkdirSync(RAW, { recursive: true });

// 整套图钉在 2026-09-24（周四）15:42:08：九点上班、午休一小时，离下班还剩
// 2:17:52，进度和今天的收入都停在一个好读的位置。
const NOW = [2026, 8, 24, 15, 42, 8];
const FAKE_CLOCK = `(() => {
  const off = new Date(${NOW.join(", ")}).getTime() - Date.now();
  const R = Date;
  class F extends R {
    constructor(...a) { super(...(a.length ? a : [R.now() + off])); }
    static now() { return R.now() + off; }
  }
  globalThis.Date = F;
})();`;

const preferences = (lang, running) => ({
  startTime: "09:00",
  endTime: "18:00",
  workdays: [1, 2, 3, 4, 5],
  lunchEnabled: true,
  lunchStartTime: "12:00",
  lunchDurationMinutes: 60,
  showSalary: true,
  salaryType: "monthly",
  salaryAmount: "12000",
  monthlyWorkingDays: 22,
  hideEarnings: false,
  running,
  lang,
});

const seed = ({ lang, running, theme }) => `${FAKE_CLOCK}
try {
  localStorage.setItem("doneat.popup.v1", ${JSON.stringify(JSON.stringify(preferences(lang, running)))});
  localStorage.setItem("theme", ${JSON.stringify(theme)});
} catch {}`;

// 设置按钮的 aria-label 就是 t("settings")，按译文精确匹配。
const openSettings = (label) => `(async () => {
  const button = [...document.querySelectorAll('button')].find((x) => x.getAttribute('aria-label') === ${JSON.stringify(label)});
  if (!button) throw new Error("settings button not found");
  button.click();
  await new Promise((r) => setTimeout(r, 600));
  // 停在薪资一节：下面紧跟语言和「数据留在这台浏览器里」那行，正好对上这张图的标题。
  document.getElementById("salary-section").scrollIntoView({ block: "start" });
  await new Promise((r) => setTimeout(r, 200));
})()`;

const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".woff": "font/woff" };
const server = createServer((request, response) => {
  const path = normalize(decodeURIComponent(new URL(request.url, "http://x").pathname)).replace(/^\/+/, "");
  const file = join(BUILD, path || "popup.html");
  if (!file.startsWith(BUILD) || !existsSync(file)) {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream" });
  response.end(readFileSync(file));
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;

let id = 0;
function send(ws, method, params = {}, sessionId) {
  const n = ++id;
  ws.send(JSON.stringify({ id: n, method, params, sessionId }));
  return new Promise((resolve, reject) => {
    const on = (event) => {
      const data = JSON.parse(event.data);
      if (data.id !== n) return;
      ws.removeEventListener("message", on);
      data.error ? reject(new Error(`${method}: ${data.error.message}`)) : resolve(data.result);
    };
    ws.addEventListener("message", on);
    setTimeout(() => reject(new Error(`${method} timed out`)), 60000);
  });
}

async function shot(ws, { name, height, prelude, after }) {
  const { targetId } = await send(ws, "Target.createTarget", { url: "about:blank" });
  const { sessionId } = await send(ws, "Target.attachToTarget", { targetId, flatten: true });
  await send(ws, "Page.enable", {}, sessionId);
  await send(ws, "Runtime.enable", {}, sessionId);
  // 3 倍截：成品里弹窗放大到 1.1–1.2 倍也不糊。
  await send(ws, "Emulation.setDeviceMetricsOverride", { width: 400, height, deviceScaleFactor: 3, mobile: false }, sessionId);
  await send(ws, "Emulation.setEmulatedMedia", { features: [{ name: "prefers-reduced-motion", value: "reduce" }] }, sessionId);
  await send(ws, "Page.addScriptToEvaluateOnNewDocument", { source: prelude }, sessionId);
  await send(ws, "Page.navigate", { url: `${origin}/popup.html` }, sessionId);
  await sleep(2500);
  const ready = await send(ws, "Runtime.evaluate", {
    expression: `performance.getEntriesByName("doneat:ready").length > 0`,
  }, sessionId);
  if (!ready.result.value) throw new Error(`${name}: popup did not finish loading`);
  if (after) {
    // 找不到按钮时要停下来：否则截到的是上一屏，而脚本照样报成功。
    const result = await send(ws, "Runtime.evaluate", { expression: after, awaitPromise: true }, sessionId);
    if (result.exceptionDetails) {
      throw new Error(`${name}: ${result.exceptionDetails.exception?.description ?? result.exceptionDetails.text}`);
    }
  }
  await sleep(400);
  const { data } = await send(ws, "Page.captureScreenshot", { format: "png" }, sessionId);
  writeFileSync(join(RAW, `${name}.png`), Buffer.from(data, "base64"));
  console.log(`captured ${name}.png`);
  await send(ws, "Target.closeTarget", { targetId });
}

const chrome = spawn(CHROME, ["--headless=new", "--disable-features=MacAppCodeSignClone", `--remote-debugging-port=${CDP_PORT}`,
  "--hide-scrollbars", "--force-color-profile=srgb", "--font-render-hinting=none",
  `--user-data-dir=${join(tmpdir(), "off-work-shots-chrome-web-store")}`, "about:blank"],
{ stdio: "ignore" });
process.on("exit", () => chrome.kill());

let wsUrl;
for (let i = 0; i < 40 && !wsUrl; i++) {
  try { wsUrl = (await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/version`)).json()).webSocketDebuggerUrl; }
  catch { await sleep(250); }
}
if (!wsUrl) throw new Error("Chrome DevTools did not start");
const ws = new WebSocket(wsUrl);
await new Promise((resolve) => ws.addEventListener("open", resolve, { once: true }));

// CWS_SHOTS_LANGUAGE=ja,ko 只重截其中几种语言。
const only = process.env.CWS_SHOTS_LANGUAGE?.split(",").map((value) => value.trim());
for (const lang of Object.keys(LISTINGS).filter((lang) => !only || only.includes(lang))) {
  const t = JSON.parse(readFileSync(join(ROOT, `public/locales/${lang}/translation.json`), "utf8"));
  await shot(ws, { name: `${lang}-countdown`, height: 500, prelude: seed({ lang, running: true, theme: "light" }) });
  await shot(ws, { name: `${lang}-setup`, height: 500, prelude: seed({ lang, running: false, theme: "light" }) });
  await shot(ws, { name: `${lang}-settings`, height: 560, prelude: seed({ lang, running: false, theme: "light" }), after: openSettings(t.settings) });
  for (const theme of ["dark", "sunset"]) {
    await shot(ws, { name: `${lang}-countdown-${theme}`, height: 500, prelude: seed({ lang, running: true, theme }) });
  }
}

ws.close();
chrome.kill();
server.close();
console.log("done");
