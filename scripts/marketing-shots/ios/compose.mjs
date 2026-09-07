// Compose simulator captures into opaque App Store screenshots.
//
// Same stacking as doneat-site DeviceHero: the official frame PNG sizes the
// box, the capture sits in the screen hole, the frame stacks on top.
// iPhone hole is 75 / 66 / 75 / 66 on 1470×3000. iPad hole is 118 / 124 /
// 118 / 124 on 2300×3000. Do not punch, crop, or redraw the frame.

import { existsSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { BRAND, brandMark, escapeHTML, fontStack } from "../brand.mjs";
import { captureHtml, flattenPng } from "../chrome.mjs";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = process.env.IOS_SHOTS_RAW_DIR || join(DIR, "raw");
const OUT = process.env.IOS_SHOTS_OUT_DIR || join(DIR, "out");
const FRAMES = join(DIR, "frames");
const HTML_DIR = join(tmpdir(), "off-work-shots-html");
mkdirSync(OUT, { recursive: true });
mkdirSync(HTML_DIR, { recursive: true });
for (const name of readdirSync(OUT)) {
  if (name.endsWith(".png")) rmSync(join(OUT, name));
}
for (const name of readdirSync(DIR)) {
  if (name.startsWith("p-") && name.endsWith(".html")) rmSync(join(DIR, name));
}

const IPHONE_FRAME = join(FRAMES, "iphone-17-pro-max-deep-blue.png");
const IPAD_FRAME = join(FRAMES, "ipad-pro-m5-13-inch-space-black-portrait.png");

const IPHONE = {
  canvas: { width: 660, height: 1434, scale: 2 },
  aspect: "1470 / 3000",
  screen: {
    top: "2.2%",
    left: "5.102041%",
    width: "89.795918%",
    height: "95.6%",
    radius: "14.4% / 6.62%",
  },
};
const IPAD = {
  canvas: { width: 1032, height: 1376, scale: 2 },
  aspect: "2300 / 3000",
  screen: {
    top: "4.133333%",
    left: "5.130435%",
    width: "89.739130%",
    height: "91.733333%",
    radius: "2.91% / 2.18%",
  },
};

const COPY = {
  en: {
    iphone: [
      {
        shot: "timer",
        file: "en-1.png",
        title: "See exactly when work ends",
        sub: "Remaining time, progress, and what’s next — in one view.",
      },
      {
        shot: "widgets",
        file: "en-2.png",
        title: "Still counting on the Home Screen",
        sub: "Medium, large, and Live Activities. No need to open the app.",
      },
      {
        shot: "lunch",
        file: "en-3.png",
        title: "Lunch pauses the clock",
        sub: "Breaks don’t count as work. The remaining time stays honest.",
      },
      {
        shot: "records",
        file: "en-4.png",
        plus: true,
        title: "See the shape of your year",
        sub: "Your workdays, time, and trends in one place.",
      },
      {
        shot: "life",
        file: "en-5.png",
        plus: true,
        title: "Put work in the bigger picture",
        sub: "See your life and work in one view.",
      },
      {
        shot: "focus",
        file: "en-6.png",
        plus: true,
        title: "Make room for focused work",
        sub: "Tasks, focus blocks, and breaks fit into your day.",
      },
    ],
    ipad: [
      {
        shot: "timer",
        file: "en-ipad-1.png",
        title: "Built for the bigger screen",
        sub: "Your countdown and today’s details, together.",
      },
      {
        shot: "widgets",
        file: "en-ipad-2.png",
        title: "Widgets that fill a desk",
        sub: "Four sizes on the Home Screen, still counting with the app closed.",
      },
      {
        shot: "lunch",
        file: "en-ipad-3.png",
        title: "Lunch, at iPad scale",
        sub: "Pause the countdown for lunch. Keep work and breaks clear.",
      },
      {
        shot: "records",
        file: "en-ipad-4.png",
        plus: true,
        title: "Your year, side by side",
        sub: "Workdays, time, and trends have room to tell the story.",
      },
      {
        shot: "life",
        file: "en-ipad-5.png",
        plus: true,
        title: "Your working life, in view",
        sub: "Life and work have room to share the same picture.",
      },
      {
        shot: "focus",
        file: "en-ipad-6.png",
        plus: true,
        title: "A clearer place to focus",
        sub: "Tasks and focus blocks stay close to the rest of your day.",
      },
    ],
  },
  "zh-CN": {
    iphone: [
      {
        shot: "timer",
        file: "zh-1.png",
        title: "一眼看清几点下班",
        sub: "还剩多久、走了多远、接下来做什么，都在这一屏。",
      },
      {
        shot: "widgets",
        file: "zh-2.png",
        title: "不用打开，也能看到",
        sub: "中号、大号和灵动岛，倒计时一直在走。",
      },
      {
        shot: "lunch",
        file: "zh-3.png",
        title: "午休时，倒计时会停",
        sub: "午饭不算工时，剩下的时间是准的。",
      },
      {
        shot: "records",
        file: "zh-4.png",
        plus: true,
        title: "把这一年看得更清楚",
        sub: "工作日、工时和趋势，都能回头看。",
      },
      {
        shot: "life",
        file: "zh-5.png",
        plus: true,
        title: "把工作放进人生里看",
        sub: "从出生到退休，看看时间花在哪里。",
      },
      {
        shot: "focus",
        file: "zh-6.png",
        plus: true,
        title: "在上班时间，留一段专注",
        sub: "任务、专注时段和休息，都排在今天。",
      },
    ],
    ipad: [
      {
        shot: "timer",
        file: "zh-ipad-1.png",
        title: "为 iPad 大屏做的",
        sub: "倒计时和今天的细节，都在同一屏。",
      },
      {
        shot: "widgets",
        file: "zh-ipad-2.png",
        title: "倒计时铺在主屏幕上",
        sub: "四种大小，应用关着也在走。",
      },
      {
        shot: "lunch",
        file: "zh-ipad-3.png",
        title: "午休，大屏上也停",
        sub: "午休暂停进度，工作和休息分得清楚。",
      },
      {
        shot: "records",
        file: "zh-ipad-4.png",
        plus: true,
        title: "把这一年展开来看",
        sub: "工作日、工时和趋势，一起放进更大的画面。",
      },
      {
        shot: "life",
        file: "zh-ipad-5.png",
        plus: true,
        title: "把工作放回人生里看",
        sub: "从第一份工作到退休，前后的时间都看得见。",
      },
      {
        shot: "focus",
        file: "zh-ipad-6.png",
        plus: true,
        title: "给专注留一块清楚的地方",
        sub: "任务和专注时段，和今天的其他安排放在一起。",
      },
    ],
  },
  "zh-TW": {
    iphone: [
      {
        shot: "timer",
        file: "zh-tw-1.png",
        title: "一眼看清幾點下班",
        sub: "還剩多久、走了多遠、接下來做什麼，都在這一屏。",
      },
      {
        shot: "widgets",
        file: "zh-tw-2.png",
        title: "不用打開，也能看到",
        sub: "中型、大型和動態島，倒數一直在走。",
      },
      {
        shot: "lunch",
        file: "zh-tw-3.png",
        title: "午休時，倒數會停",
        sub: "午飯不算工時，剩下的時間是準的。",
      },
      {
        shot: "records",
        file: "zh-tw-4.png",
        plus: true,
        title: "把這一年看得更清楚",
        sub: "工作日、工時和趨勢，都能回頭看。",
      },
      {
        shot: "life",
        file: "zh-tw-5.png",
        plus: true,
        title: "把工作放進人生裡看",
        sub: "從出生到退休，看看時間花在哪裡。",
      },
      {
        shot: "focus",
        file: "zh-tw-6.png",
        plus: true,
        title: "在上班時間，留一段專注",
        sub: "任務、專注時段和休息，都排在今天。",
      },
    ],
    ipad: [
      {
        shot: "timer",
        file: "zh-tw-ipad-1.png",
        title: "為 iPad 大螢幕做的",
        sub: "倒數和今天的細節，都在同一屏。",
      },
      {
        shot: "widgets",
        file: "zh-tw-ipad-2.png",
        title: "倒數鋪在主畫面上",
        sub: "四種大小，應用程式關著也在走。",
      },
      {
        shot: "lunch",
        file: "zh-tw-ipad-3.png",
        title: "午休，大螢幕上也停",
        sub: "午休暫停進度，工作和休息分得清楚。",
      },
      {
        shot: "records",
        file: "zh-tw-ipad-4.png",
        plus: true,
        title: "把這一年展開來看",
        sub: "工作日、工時和趨勢，一起放進更大的畫面。",
      },
      {
        shot: "life",
        file: "zh-tw-ipad-5.png",
        plus: true,
        title: "把工作放回人生裡看",
        sub: "從第一份工作到退休，前後的時間都看得見。",
      },
      {
        shot: "focus",
        file: "zh-tw-ipad-6.png",
        plus: true,
        title: "給專注留一塊清楚的地方",
        sub: "任務和專注時段，和今天的其他安排放在一起。",
      },
    ],
  },
};

function fileUri(path) {
  if (!existsSync(path)) throw new Error(`Missing ${path}`);
  return pathToFileURL(path).href;
}

function page(card, language, platform, frameUri, sourceUri) {
  const spec = platform === "iphone" ? IPHONE : IPAD;
  const hole = spec.screen;
  const isPhone = platform === "iphone";

  return `<!doctype html><html><head><meta charset="utf-8"><style>
    * { box-sizing: border-box; }
    html, body { margin: 0; width: ${spec.canvas.width}px; height: ${spec.canvas.height}px; overflow: hidden; }
    body {
      font-family: ${fontStack(language)};
      color: ${BRAND.plum};
      background: ${BRAND.cream};
      display: flex; flex-direction: column;
    }
    .copy {
      position: relative; z-index: 3; flex: none;
      padding: ${isPhone ? "36px 24px 0" : "32px 36px 0"};
      text-align: center;
    }
    .brand {
      display: inline-flex; align-items: center; gap: 8px;
      color: ${BRAND.orange}; font-size: ${isPhone ? 17 : 18}px; font-weight: 700;
    }
    .plus {
      padding: 2px 6px; border: 1px solid color-mix(in srgb, ${BRAND.orange} 60%, ${BRAND.cream});
      border-radius: 999px; font-size: .68em; font-weight: 700; letter-spacing: .02em;
    }
    .mark { width: ${isPhone ? 36 : 40}px; height: ${isPhone ? 36 : 40}px; display: block; }
    h1 {
      margin: 12px auto 0; max-width: ${isPhone ? 600 : 920}px;
      font-size: ${isPhone ? 40 : 42}px; line-height: 1.12; letter-spacing: -.036em; font-weight: 700;
      text-wrap: balance;
    }
    p {
      margin: 10px auto 0; max-width: ${isPhone ? 560 : 840}px;
      color: color-mix(in srgb, ${BRAND.plum} 62%, ${BRAND.cream});
      font-size: ${isPhone ? 18 : 20}px; line-height: 1.4;
      text-wrap: balance;
    }
    .stage {
      position: relative; z-index: 2; flex: 1; min-height: 0;
      display: flex; justify-content: center; align-items: center;
      padding: ${isPhone ? "8px 16px 32px" : "8px 24px 32px"};
    }
    .device {
      position: relative;
      aspect-ratio: ${spec.aspect};
      width: ${isPhone ? "88%" : "82%"};
      height: auto;
      filter: drop-shadow(0 16px 24px rgba(43, 25, 53, .16));
    }
    .screen {
      position: absolute;
      top: ${hole.top}; left: ${hole.left};
      width: ${hole.width}; height: ${hole.height};
      overflow: hidden; border-radius: ${hole.radius};
    }
    .screen img {
      position: absolute; inset: 0; width: 100%; height: 100%;
      object-fit: cover; object-position: center top;
    }
    .frame {
      position: relative; z-index: 1;
      display: block; width: 100%; height: auto;
    }
  </style></head><body>
    <div class="copy">
      <div class="brand">${brandMark(BRAND.plum)}<span>${BRAND.name}</span>${card.plus ? '<span class="plus">Plus</span>' : ""}</div>
      <h1>${escapeHTML(card.title)}</h1>
      <p>${escapeHTML(card.sub)}</p>
    </div>
    <div class="stage">
      <div class="device">
        <div class="screen"><img src="${sourceUri}" alt=""></div>
        <img class="frame" src="${frameUri}" alt="">
      </div>
    </div>
  </body></html>`;
}

if (!existsSync(IPHONE_FRAME) || !existsSync(IPAD_FRAME)) {
  throw new Error(`Official Apple frames missing in ${FRAMES}`);
}

const iphoneFrameUri = fileUri(IPHONE_FRAME);
const ipadFrameUri = fileUri(IPAD_FRAME);

for (const [language, platforms] of Object.entries(COPY)) {
  for (const platform of ["iphone", "ipad"]) {
    const spec = platform === "iphone" ? IPHONE : IPAD;
    const frameUri = platform === "iphone" ? iphoneFrameUri : ipadFrameUri;
    for (const [index, card] of platforms[platform].entries()) {
      const name = `${language}-${platform}-${String(index + 1).padStart(2, "0")}-${card.shot}`;
      const outFile = join(OUT, `${name}.png`);
      await captureHtml({
        html: page(card, language, platform, frameUri, fileUri(join(RAW, card.file))),
        htmlPath: join(HTML_DIR, `p-${name}.html`),
        width: spec.canvas.width,
        height: spec.canvas.height,
        scale: spec.canvas.scale,
        outFile,
      });
      flattenPng(outFile);
      console.log(`composed ${name}.png`);
    }
  }
}

console.log(`done: App Store screenshots are in ${OUT}`);
