// Mac App Store 截图：1440x900 CSS，以 2 倍渲染成 2880x1800（Apple 接受的最大档，
// 16:10）。一套里所有图必须同尺寸。
//
// ⚠️ App Store Connect 拒收带透明通道的 PNG，所以背景必须完全不透明。
//
// 交通灯由这里画：应用在 macOS 上用覆盖式标题栏，顶部那块空白本来就是留给
// 系统按钮的，浏览器截图里画不出来。补的是应用真实的样子，不是编出来的功能。

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
const PORT = 9242;
const DIR = new URL(".", import.meta.url).pathname;
// Chrome 的用户目录放到仓库外：它里面带着 Chrome 自带扩展的 JS，留在仓库里
// `eslint .` 会去 lint 它们并报错。.gitignore 挡得住 git，挡不住 eslint。
const PROFILE = join(tmpdir(), "off-work-shots-compose");
const OUT = `${DIR}out/`;
mkdirSync(OUT, { recursive: true });

const img = (n) => `data:image/png;base64,${readFileSync(`${DIR}raw/${n}.png`).toString("base64")}`;

const COPY = {
  en: [
    { shot: "countdown", title: "See exactly how much of your workday is left",
      sub: "The time remaining, how far through you are, and what you have earned today." },
    { shot: "mini-woodfish", mini: true, title: "Keep it on top of everything",
      sub: "A floating timer you can park in any corner. Tap the woodfish while you wait." },
    { shot: "setup", title: "Set your hours once",
      sub: "Nine to five, twelve-hour days, or a night shift that runs past midnight." },
    { shot: "settings", title: "Set it up the way you work",
      sub: "Launch at login, a global shortcut, 19 languages, light and dark." },
    { shot: "mini", mini: true, title: "Free, open source, and entirely on your Mac",
      sub: "No account. Your hours and salary never leave the machine." },
  ],
  "zh-CN": [
    { shot: "countdown", title: "一眼看清今天还剩多久下班",
      sub: "剩余时间、已完成进度，以及今天已经挣到的钱。" },
    { shot: "mini-woodfish", mini: true, title: "让倒计时浮在最上层",
      sub: "可以停在屏幕任意角落。等下班的时候，还能敲敲木鱼。" },
    { shot: "setup", title: "上下班时间只需设置一次",
      sub: "朝九晚六、十二小时班，还是跨过午夜的夜班，都算得对。" },
    { shot: "settings", title: "按你的工作习惯调整",
      sub: "开机自启、全局快捷键、19 种语言，明暗主题跟随系统。" },
    { shot: "mini", mini: true, title: "免费开源，一切都留在你的 Mac 上",
      sub: "不用注册。班次和薪资从不离开这台机器。" },
  ],
};

const page = (c, lang) => `<!doctype html><meta charset="utf-8"><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 1440px; height: 900px; overflow: hidden; }
  body {
    font-family: ${lang === "zh-CN" ? '"PingFang SC", ' : ""}-apple-system, "SF Pro Display", "Helvetica Neue", sans-serif;
    /* 完全不透明：App Store Connect 拒收带 alpha 的 PNG */
    background:
      radial-gradient(900px 700px at 84% 82%, rgba(249,146,58,.30), rgba(249,146,58,0) 62%),
      radial-gradient(760px 640px at 10% 12%, rgba(126,158,255,.26), rgba(126,158,255,0) 60%),
      linear-gradient(145deg, #0e1118 0%, #171d29 48%, #1f2735 100%);
    display: flex; align-items: center; gap: 72px; padding: 0 92px;
  }
  .copy { flex: 1; min-width: 0; }
  .title {
    font-size: 62px; font-weight: 700; line-height: 1.16; letter-spacing: -0.022em;
    color: #fff; text-wrap: balance;
  }
  .sub {
    margin-top: 26px; font-size: 27px; line-height: 1.5; font-weight: 400;
    color: rgba(255,255,255,.60);
  }
  .stage { flex: 0 0 auto; display: flex; align-items: center; justify-content: center; }
  .window { position: relative; width: ${c.mini ? 520 : 500}px; }
  .window img { display: block; width: 100%; height: auto; }
  ${c.mini ? "" : `.window { border-radius: 26px; overflow: hidden;
     box-shadow: 0 44px 88px rgba(0,0,0,.55), 0 10px 24px rgba(0,0,0,.38); }
   /* 交通灯：覆盖式标题栏下由 macOS 绘制，浏览器截图里那块是空的 */
   .lights { position: absolute; top: 19px; left: 21px; display: flex; gap: 8px; z-index: 2; }
   .lights i { width: 13px; height: 13px; border-radius: 50%; display: block; }
   .lights i:nth-child(1) { background: #ff5f57; }
   .lights i:nth-child(2) { background: #febc2e; }
   .lights i:nth-child(3) { background: #28c840; }`}
</style>
<body>
  <div class="copy">
    <div class="title">${c.title}</div>
    <div class="sub">${c.sub}</div>
  </div>
  <div class="stage">
    <div class="window">
      ${c.mini ? "" : '<div class="lights"><i></i><i></i><i></i></div>'}
      <img src="${img(`${lang}-${c.shot}`)}">
    </div>
  </div>
</body>`;

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
    setTimeout(() => rej(new Error(`${method} timed out`)), 120000);
  });
}

const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`,
  "--hide-scrollbars", "--force-color-profile=srgb", "--font-render-hinting=none",
  `--user-data-dir=${PROFILE}`, "about:blank"], { stdio: "ignore" });
process.on("exit", () => chrome.kill());

let wsUrl;
for (let i = 0; i < 40; i++) {
  try { wsUrl = (await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json()).webSocketDebuggerUrl; break; }
  catch { await sleep(250); }
}
const ws = new WebSocket(wsUrl);
await new Promise((r) => ws.addEventListener("open", r, { once: true }));

for (const [lang, cards] of Object.entries(COPY)) {
  for (const [i, c] of cards.entries()) {
    const name = `${lang}-${String(i + 1).padStart(2, "0")}-${c.shot}`;
    const file = `${DIR}p-${name}.html`;
    writeFileSync(file, page(c, lang));
    const { targetId } = await send(ws, "Target.createTarget", { url: "about:blank" });
    const { sessionId } = await send(ws, "Target.attachToTarget", { targetId, flatten: true });
    await send(ws, "Page.enable", {}, sessionId);
    await send(ws, "Emulation.setDeviceMetricsOverride",
      { width: 1440, height: 900, deviceScaleFactor: 2, mobile: false }, sessionId);
    await send(ws, "Page.navigate", { url: `file://${file}` }, sessionId);
    await sleep(1400);
    const { data } = await send(ws, "Page.captureScreenshot", { format: "png" }, sessionId);
    writeFileSync(`${OUT}${name}.png`, Buffer.from(data, "base64"));
    console.log(`composed ${name}.png`);
    await send(ws, "Target.closeTarget", { targetId });
  }
}
ws.close(); chrome.kill();
console.log("done");
