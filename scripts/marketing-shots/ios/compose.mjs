// Compose native simulator captures into opaque App Store screenshots.
//
// App Store Connect accepts 1284x2778 for the selected iPhone portrait slot and
// 2064x2752 for 13-inch iPads. Landscape feature cards use the corresponding
// accepted 2778x1284 and 2752x2064 canvases so the app capture stays native-sized.

import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const CHROME = process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9243;
const DIR = new URL(".", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const OUT = process.env.IOS_SHOTS_OUT_DIR || join(DIR, "out");
const IPHONE_RAW = process.env.IOS_SHOTS_IPHONE_RAW_DIR;
const PROFILE = mkdtempSync(join(tmpdir(), "off-work-ios-shots-compose-"));
mkdirSync(OUT, { recursive: true });

const IPHONE_FILENAMES = {
  en: {
    main: "程序主界面-英文.jpeg",
    widgets: "小组件-英文.jpeg",
    island: "实时活动-英文.jpeg",
    landscape: "横屏模式-英文.jpeg",
  },
  "zh-CN": {
    main: "程序主界面-中文.jpeg",
    widgets: "小组件-中文.jpeg",
    island: "实时活动-中文.jpeg",
    landscape: "横屏模式-中文.jpeg",
  },
};

const COPY = {
  en: {
    iphone: [
      {
        shot: "main",
        title: "Know exactly when work ends",
        sub: "Time left, today’s progress, and earnings — together in one calm view.",
      },
      {
        shot: "widgets",
        title: "Your countdown, at a glance",
        sub: "Home Screen and Lock Screen widgets keep the day in view.",
      },
      {
        shot: "island",
        title: "Live Activities on your Lock Screen",
        sub: "Keep the final countdown visible without reopening the app.",
      },
      {
        shot: "landscape",
        landscape: true,
        chips: ["Countdown", "Progress", "Earnings"],
        title: "Turn sideways. See the whole day.",
        sub: "A focused landscape dashboard when you want the full picture.",
      },
    ],
    ipad: [
      {
        shot: "main",
        title: "A workspace made for iPad",
        sub: "Your countdown and today’s details, with a sidebar built for the big screen.",
      },
      {
        shot: "widgets",
        title: "Keep the countdown nearby",
        sub: "Widgets bring workday progress to the Home Screen and Lock Screen.",
      },
      {
        shot: "reminders",
        title: "Reminders that fit your workday",
        sub: "Follow the final stretch, lunch boundaries, and healthy breaks.",
      },
      {
        shot: "landscape",
        landscape: true,
        chips: ["Sidebar", "Countdown", "Today’s details"],
        title: "More room for the whole picture",
        sub: "A spacious landscape layout designed for iPad.",
      },
    ],
  },
  "zh-CN": {
    iphone: [
      {
        shot: "main",
        title: "一眼看清还有多久下班",
        sub: "剩余时间、今日进度和已赚薪资，都在一个清爽界面里。",
      },
      {
        shot: "widgets",
        title: "不用打开 App，也能看到进度",
        sub: "主屏幕和锁屏小组件，让下班倒计时随时可见。",
      },
      {
        shot: "island",
        title: "锁屏实时活动，最后一程随时可见",
        sub: "不用重新打开 App，也能继续查看下班倒计时。",
      },
      {
        shot: "landscape",
        landscape: true,
        chips: ["倒计时", "今日进度", "已赚薪资"],
        title: "横过来，完整掌握今天",
        sub: "想看更多时，横屏仪表盘一次呈现关键数据。",
      },
    ],
    ipad: [
      {
        shot: "main",
        title: "为 iPad 大屏认真设计",
        sub: "倒计时、今日详情和侧边栏，在大屏上各得其所。",
      },
      {
        shot: "widgets",
        title: "让倒计时一直在身边",
        sub: "主屏幕与锁屏小组件，随时展示今天的工作进度。",
      },
      {
        shot: "reminders",
        title: "提醒跟着你的工作节奏",
        sub: "下班进度、午休节点和健康休息，一个都不会错过。",
      },
      {
        shot: "landscape",
        landscape: true,
        chips: ["侧边栏", "下班倒计时", "今日详情"],
        title: "横屏展开，更从容",
        sub: "专为 iPad 设计的宽屏布局，充分利用每一寸空间。",
      },
    ],
  },
};

function imagePath(language, platform, shot) {
  if (platform === "iphone" && IPHONE_RAW) {
    return join(IPHONE_RAW, IPHONE_FILENAMES[language][shot]);
  }
  return join(RAW, `${language}-${platform}-${shot}.png`);
}

function imageData(language, platform, shot) {
  const path = imagePath(language, platform, shot);
  const mime = path.endsWith(".jpeg") || path.endsWith(".jpg") ? "image/jpeg" : "image/png";
  return `data:${mime};base64,${readFileSync(path).toString("base64")}`;
}

function escapeHTML(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function page(card, language, platform) {
  const isPhone = platform === "iphone";
  const outputLandscape = Boolean(card.landscape);
  const width = outputLandscape ? (isPhone ? 1389 : 1376) : (isPhone ? 642 : 1032);
  const height = outputLandscape ? (isPhone ? 642 : 1032) : (isPhone ? 1389 : 1376);
  const source = imageData(language, platform, card.sourceShot ?? card.shot);
  const chips = card.chips?.map((chip) => `<span>${escapeHTML(chip)}</span>`).join("") ?? "";
  const customPhoneCapture = isPhone && Boolean(IPHONE_RAW);
  const stageClass = [
    platform,
    card.landscape ? "landscape" : "portrait",
    customPhoneCapture && card.landscape ? "native-landscape" : "",
    customPhoneCapture ? "" : card.focus ?? "",
  ]
    .filter(Boolean)
    .join(" ");

  return `<!doctype html><html><head><meta charset="utf-8"><style>
    * { box-sizing: border-box; }
    html, body { margin: 0; width: ${width}px; height: ${height}px; overflow: hidden; }
    body {
      font-family: ${language === "zh-CN" ? '"PingFang SC", ' : ""}-apple-system, "SF Pro Display", "Helvetica Neue", sans-serif;
      color: #17130f;
      background:
        radial-gradient(520px 620px at 92% 78%, rgba(255, 123, 26, .30), rgba(255, 123, 26, 0) 68%),
        radial-gradient(540px 540px at 5% 18%, rgba(126, 151, 255, .28), rgba(126, 151, 255, 0) 68%),
        linear-gradient(155deg, #fffdf9 0%, #f7f2ec 53%, #f4ece4 100%);
      position: relative; display: flex; flex-direction: column; align-items: center;
    }
    body::after {
      content: ""; position: absolute; inset: 0; pointer-events: none;
      background-image: radial-gradient(rgba(75, 55, 34, .055) .7px, transparent .7px);
      background-size: 7px 7px; opacity: .42;
    }
    .copy {
      position: relative; z-index: 3; width: 100%; flex: none;
      padding: ${isPhone ? 58 : 56}px ${isPhone ? 38 : 68}px 0;
      text-align: center;
    }
    .eyebrow {
      display: inline-flex; align-items: center; gap: 8px;
      color: #e9560b; font-size: ${isPhone ? 15 : 17}px; line-height: 1;
      font-weight: 700; letter-spacing: .08em; text-transform: uppercase;
    }
    .eyebrow::before { content: ""; width: 8px; height: 8px; border-radius: 3px; background: #f56a12; }
    h1 {
      margin: ${isPhone ? 20 : 18}px auto 0; max-width: ${isPhone ? 580 : 860}px;
      font-size: ${isPhone ? 52 : 58}px; line-height: 1.08; letter-spacing: -.038em; font-weight: 760;
      text-wrap: balance;
    }
    p {
      margin: ${isPhone ? 18 : 16}px auto 0; max-width: ${isPhone ? 550 : 780}px;
      color: rgba(44, 36, 28, .64); font-size: ${isPhone ? 22 : 24}px; line-height: 1.42; font-weight: 470;
      text-wrap: balance;
    }
    .stage {
      position: relative; z-index: 2; width: 100%; height: auto; flex: none;
      margin-top: ${isPhone ? 62 : 58}px;
      display: flex; align-items: flex-start; justify-content: center;
    }
    .device {
      position: relative; background: linear-gradient(145deg, #34363c, #08090b 34%, #1f2025 78%, #08090a);
      padding: ${isPhone ? 9 : 11}px;
      box-shadow: 0 42px 70px rgba(49, 34, 20, .28), 0 10px 24px rgba(20, 15, 10, .24), inset 0 0 0 1px rgba(255,255,255,.28);
    }
    .screen { position: relative; overflow: hidden; background: #eef0f6; }
    .screen img { display: block; width: 100%; height: 100%; object-fit: cover; }
    .iphone.portrait .device { width: 480px; border-radius: 67px; }
    .iphone.portrait .screen { aspect-ratio: 1320 / 2868; border-radius: 58px; }
    .iphone.landscape .device { width: 620px; border-radius: 46px; }
    .iphone.landscape .screen { aspect-ratio: 2868 / 1320; border-radius: 37px; }
    .iphone.landscape .screen img {
      position: absolute; left: 50%; top: 50%; width: auto; height: 217.273%; max-width: none;
      transform: translate(-50%, -50%) rotate(-90deg); transform-origin: center;
    }
    .iphone.landscape.native-landscape .screen img {
      position: static; width: 100%; height: 100%; max-width: 100%;
      transform: none; object-fit: cover;
    }
    .ipad.portrait .device { width: 790px; border-radius: 29px; }
    .ipad.portrait .screen { aspect-ratio: 2064 / 2752; border-radius: 18px; }
    .ipad.landscape .device { width: 960px; border-radius: 32px; }
    .ipad.landscape .screen { aspect-ratio: 2752 / 2064; border-radius: 18px; }
    .ipad.landscape .screen img {
      position: absolute; left: 50%; top: 50%; width: auto; height: 133.334%; max-width: none;
      transform: translate(-50%, -50%) rotate(90deg); transform-origin: center;
    }
    body.output-landscape .copy { padding: ${isPhone ? 24 : 36}px 54px 0; }
    body.output-landscape .eyebrow { font-size: ${isPhone ? 13 : 16}px; }
    body.output-landscape h1 {
      max-width: 1260px; margin-top: ${isPhone ? 10 : 14}px;
      font-size: ${isPhone ? 42 : 50}px; line-height: 1.04;
    }
    body.output-landscape p {
      max-width: 1180px; margin-top: ${isPhone ? 8 : 12}px;
      font-size: ${isPhone ? 18 : 21}px; line-height: 1.25;
    }
    body.output-landscape .stage { margin-top: ${isPhone ? 18 : 28}px; }
    body.output-landscape .iphone.landscape .device { width: 1010px; border-radius: 72px; }
    body.output-landscape .iphone.landscape .screen { border-radius: 62px; }
    body.output-landscape .ipad.landscape .device { width: 1080px; border-radius: 35px; }
    body.output-landscape .ipad.landscape .screen { border-radius: 22px; }
    body.output-landscape .chips { display: none; }
    .island-zoom {
      display: none; position: absolute; z-index: 5; top: 18px; right: -88px;
      width: 286px; height: 92px; border-radius: 48px;
      background-image: url('${source}'); background-repeat: no-repeat;
      background-size: 500px auto; background-position: center 0;
      border: 7px solid #111216;
      box-shadow: 0 24px 42px rgba(0,0,0,.3), 0 0 0 1px rgba(255,255,255,.32);
    }
    .iphone.island .island-zoom, .iphone.island-onboarding .island-zoom { display: block; }
    .iphone.island-onboarding .island-zoom {
      background-size: 500px auto; background-position: center -430px;
    }
    .widget-zoom {
      display: none; position: absolute; z-index: 5; left: 50%; top: 360px;
      width: 540px; height: 290px; transform: translateX(-50%); overflow: hidden;
      border-radius: 34px; border: 7px solid rgba(255,255,255,.92); background: #fff;
      box-shadow: 0 28px 52px rgba(36, 27, 18, .24), 0 0 0 1px rgba(39, 31, 23, .12);
    }
    .widget-zoom img {
      position: absolute; width: 1240px; height: auto; max-width: none;
      left: 50%; top: 50%; transform: translate(-50%, -50%);
    }
    .ipad.widget .widget-zoom { display: block; }
    .chips {
      position: relative; z-index: 4; flex: none; margin-top: ${isPhone ? 34 : 32}px;
      display: flex; justify-content: center; gap: 10px;
    }
    .chips:empty { display: none; }
    .chips span {
      padding: 10px 16px; border-radius: 999px; background: rgba(255,255,255,.76);
      border: 1px solid rgba(46, 37, 28, .1); color: rgba(39, 31, 24, .72);
      box-shadow: 0 9px 24px rgba(44, 30, 18, .08); font-size: ${isPhone ? 15 : 17}px; font-weight: 650;
      backdrop-filter: blur(18px);
    }
  </style></head><body class="${outputLandscape ? "output-landscape" : ""}">
    <div class="copy">
      <div class="eyebrow">${language === "zh-CN" ? "下班倒计时" : "Off Work Countdown"}</div>
      <h1>${escapeHTML(card.title)}</h1>
      <p>${escapeHTML(card.sub)}</p>
    </div>
    <div class="stage ${stageClass}">
      <div class="device">
        <div class="screen"><img src="${source}"></div>
        <div class="island-zoom"></div>
        <div class="widget-zoom"><img src="${source}"></div>
      </div>
    </div>
    <div class="chips ${stageClass}">${chips}</div>
  </body></html>`;
}

let id = 0;
function send(ws, method, params = {}, sessionId) {
  const requestId = ++id;
  ws.send(JSON.stringify({ id: requestId, method, params, sessionId }));
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`${method} timed out`)), 120000);
    const onMessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.id !== requestId) return;
      clearTimeout(timeout);
      ws.removeEventListener("message", onMessage);
      data.error ? reject(new Error(`${method}: ${data.error.message}`)) : resolve(data.result);
    };
    ws.addEventListener("message", onMessage);
  });
}

const chrome = spawn(CHROME, [
  "--headless=new",
  `--remote-debugging-port=${PORT}`,
  "--hide-scrollbars",
  "--force-color-profile=srgb",
  "--font-render-hinting=none",
  `--user-data-dir=${PROFILE}`,
  "about:blank",
], { stdio: "ignore" });
process.on("exit", () => chrome.kill());

let webSocketURL;
for (let attempt = 0; attempt < 40; attempt += 1) {
  try {
    webSocketURL = (await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json()).webSocketDebuggerUrl;
    break;
  } catch {
    await sleep(250);
  }
}
if (!webSocketURL) throw new Error("Chrome DevTools endpoint did not start");

const ws = new WebSocket(webSocketURL);
await new Promise((resolve) => ws.addEventListener("open", resolve, { once: true }));

for (const [language, platforms] of Object.entries(COPY)) {
  for (const [platform, cards] of Object.entries(platforms)) {
    for (const [index, card] of cards.entries()) {
      const metrics = card.landscape
        ? platform === "iphone"
          ? { width: 1389, height: 642, deviceScaleFactor: 2 }
          : { width: 1376, height: 1032, deviceScaleFactor: 2 }
        : platform === "iphone"
          ? { width: 642, height: 1389, deviceScaleFactor: 2 }
          : { width: 1032, height: 1376, deviceScaleFactor: 2 };
      const name = `${language}-${platform}-${String(index + 1).padStart(2, "0")}-${card.shot}`;
      const htmlPath = join(DIR, `p-${name}.html`);
      writeFileSync(htmlPath, page(card, language, platform));

      const { targetId } = await send(ws, "Target.createTarget", { url: "about:blank" });
      const { sessionId } = await send(ws, "Target.attachToTarget", { targetId, flatten: true });
      await send(ws, "Page.enable", {}, sessionId);
      await send(ws, "Emulation.setDeviceMetricsOverride", { ...metrics, mobile: false }, sessionId);
      await send(ws, "Page.navigate", { url: `file://${htmlPath}` }, sessionId);
      await sleep(900);
      const { data } = await send(ws, "Page.captureScreenshot", { format: "png" }, sessionId);
      writeFileSync(join(OUT, `${name}.png`), Buffer.from(data, "base64"));
      console.log(`composed ${name}.png`);
      await send(ws, "Target.closeTarget", { targetId });
    }
  }
}

ws.close();
chrome.kill();
console.log(`done: App Store screenshots are in ${OUT}`);
