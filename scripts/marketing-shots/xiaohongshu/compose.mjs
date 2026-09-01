// Xiaohongshu note cards: 1080×1440 (3:4). That is the feed's largest tile;
// 1:1 and 4:3 lose space, and a 9:16 phone screenshot gets cropped on the
// profile grid. Chinese only. Raw frames come from the iOS capture folder.
//
// Copy starts from the iOS zh-CN timer / widgets / lunch lines, then shortens
// the subtitle so it still reads at feed-thumbnail size. Titles stay ≤ 10
// characters so they survive the discovery-feed overlay.

import { existsSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import { BRAND, brandMark, escapeHTML, fontStack } from "../brand.mjs";
import { captureHtml, flattenPng } from "../chrome.mjs";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = process.env.XHS_SHOTS_RAW_DIR || join(DIR, "../ios/raw");
const OUT = process.env.XHS_SHOTS_OUT_DIR || join(DIR, "out");
const WIDTH = 540;
const HEIGHT = 720;
const SCALE = 2;

mkdirSync(OUT, { recursive: true });
for (const name of readdirSync(OUT)) {
  if (name.endsWith(".png") || name.endsWith(".jpg") || name.endsWith(".jpeg")) {
    rmSync(join(OUT, name));
  }
}

// iOS App Store copy, tightened for a 3:4 tile. Titles are unchanged.
const COPY = [
  {
    shot: "timer",
    file: "zh-1.png",
    title: "一眼看清几点下班",
    sub: "还剩多久、走了多远、接下来做什么。",
    focus: "18%",
  },
  {
    shot: "widgets",
    file: "zh-2.png",
    title: "不用打开，也能看到",
    sub: "中号、大号和灵动岛，倒计时一直在走。",
    focus: "12%",
  },
  {
    shot: "lunch",
    file: "zh-3.png",
    title: "午休时，倒计时会停",
    sub: "午饭不算工时，剩下的时间是准的。",
    focus: "16%",
  },
];

function fileUri(path) {
  if (!existsSync(path)) throw new Error(`Missing ${path}`);
  return pathToFileURL(path).href;
}

function page(card) {
  const source = fileUri(join(RAW, card.file));
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    * { box-sizing: border-box; }
    html, body { margin: 0; width: ${WIDTH}px; height: ${HEIGHT}px; overflow: hidden; }
    body {
      font-family: ${fontStack("zh-CN")};
      color: ${BRAND.plum};
      background:
        radial-gradient(420px 280px at 50% 118%, rgba(244, 90, 30, .18), transparent 58%),
        ${BRAND.cream};
      position: relative;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .copy {
      position: relative; z-index: 3; flex: none; width: 100%;
      padding: 56px 28px 0;
      text-align: center;
    }
    .brand {
      display: inline-flex; align-items: center; gap: 7px;
      color: ${BRAND.orange}; font-size: 13px; font-weight: 700;
      letter-spacing: .04em;
    }
    .mark { width: 22px; height: 22px; display: block; }
    h1 {
      margin: 14px auto 0; max-width: 484px;
      font-size: 36px; line-height: 1.16; letter-spacing: -.04em; font-weight: 720;
      text-wrap: balance;
    }
    p {
      margin: 10px auto 0; max-width: 430px;
      color: color-mix(in srgb, ${BRAND.plum} 58%, ${BRAND.cream});
      font-size: 15px; line-height: 1.45; font-weight: 470;
      text-wrap: balance;
    }
    .stage {
      position: relative; z-index: 2; width: 100%; flex: 1;
      margin-top: 22px;
      display: flex; align-items: flex-start; justify-content: center;
      overflow: hidden;
    }
    .device {
      width: 328px;
      background: linear-gradient(145deg, #3a4558, #1c2330 38%, #0e1218);
      padding: 7px;
      border-radius: 46px;
      box-shadow:
        0 28px 48px rgba(43, 25, 53, .22),
        0 6px 16px rgba(43, 25, 53, .12),
        inset 0 0 0 1px rgba(255,255,255,.22);
    }
    .screen {
      position: relative; overflow: hidden; background: #eef0f6;
      aspect-ratio: 1320 / 2868; border-radius: 40px;
    }
    .screen img {
      display: block; width: 100%; height: 100%;
      object-fit: cover; object-position: center ${card.focus};
    }
  </style></head><body>
    <div class="copy">
      <div class="brand">${brandMark()}${BRAND.name}</div>
      <h1>${escapeHTML(card.title)}</h1>
      <p>${escapeHTML(card.sub)}</p>
    </div>
    <div class="stage">
      <div class="device">
        <div class="screen"><img src="${source}" alt=""></div>
      </div>
    </div>
  </body></html>`;
}

function writeJpeg(pngPath, jpgPath) {
  const result = spawnSync(
    "sips",
    ["-s", "format", "jpeg", "-s", "formatOptions", "90", pngPath, "--out", jpgPath],
    { encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error(result.stderr || `sips could not write ${jpgPath}`);
  }
}

for (const [index, card] of COPY.entries()) {
  const name = `zh-CN-${String(index + 1).padStart(2, "0")}-${card.shot}`;
  const pngPath = join(OUT, `${name}.png`);
  await captureHtml({
    html: page(card),
    htmlPath: join(DIR, `p-${name}.html`),
    width: WIDTH,
    height: HEIGHT,
    scale: SCALE,
    outFile: pngPath,
  });
  flattenPng(pngPath);
  writeJpeg(pngPath, join(OUT, `${name}.jpg`));
  console.log(`composed ${name}.png / .jpg`);
}

console.log(`done: Xiaohongshu cards are in ${OUT}`);
console.log("post the .jpg files; keep 3:4 and upload in 01 → 03 order");
