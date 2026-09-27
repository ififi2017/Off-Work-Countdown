// Chrome 应用商店素材，按官方尺寸出图：
// - 截图 1280×800，整幅铺满、直角、不留边；英文和简体中文各四张（商店可按语言上传截图）。
// - 小宣传图 440×280、大宣传图 1400×560：商店不分语言，官方建议少放文字，
//   所以只放标志、品牌名和不依赖语言的倒计时界面。
// - 图标 128×128：图案 96×96，四周各留 16px 透明边，深浅背景上都看得清。
//
// 版式与 Windows / macOS 那套同源：晚间梅子渐变，左文右图。

import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import sharp from "sharp";
import { BRAND, brandMark, escapeHTML, fontStack } from "../brand.mjs";
import { captureHtml, flattenPng } from "../chrome.mjs";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const OUT = join(DIR, "out");
const HTML_DIR = join(tmpdir(), "off-work-shots-html");
const ICON = new URL("../../../assets/brand/off-work-countdown-icon-rounded.svg", import.meta.url);
mkdirSync(OUT, { recursive: true });
mkdirSync(HTML_DIR, { recursive: true });

const COPY = {
  en: [
    {
      shots: ["countdown"],
      title: "Know when your time is yours",
      sub: "One click on the toolbar shows the time left, how far through the day you are and what you have earned so far.",
    },
    {
      shots: ["setup"],
      title: "Set your hours once",
      sub: "Pick your hours and workdays. Lunch pauses the clock, and night shifts that run past midnight count correctly.",
    },
    {
      shots: ["settings"],
      title: "Your numbers stay with you",
      sub: "No account to create. Hours, pay and preferences are saved in this browser, and nothing is sent anywhere.",
    },
    {
      shots: ["countdown-dark", "countdown-sunset"],
      title: "Make it feel like yours",
      sub: "Light, Dark, Sunset and Cyberpunk themes in 19 languages. Works offline.",
    },
  ],
  "zh-CN": [
    {
      shots: ["countdown"],
      title: "几点下班，\n心里有数",
      sub: "点一下工具栏，就能看到剩余时间、\n今天的进度和已经挣到的钱。",
    },
    {
      shots: ["setup"],
      title: "上下班时间\n只需设置一次",
      sub: "选好上下班时间和工作日。\n午休自动暂停，跨过午夜的夜班也算得对。",
    },
    {
      shots: ["settings"],
      title: "数据只留在\n你的浏览器里",
      sub: "不用注册账号。\n作息、薪资和偏好都存在这台浏览器里，\n不会发送到任何地方。",
    },
    {
      shots: ["countdown-dark", "countdown-sunset"],
      title: "换成你喜欢的样子",
      sub: "浅色、深色、日落和赛博朋克四种主题，\n支持 19 种语言，离线也能用。",
    },
  ],
};

function dataUri(path) {
  if (!existsSync(path)) {
    throw new Error(`Missing ${path}. Run npm run shots:chrome-web-store:capture first.`);
  }
  return `data:image/png;base64,${readFileSync(path).toString("base64")}`;
}

const background = (glowX) => `
  radial-gradient(760px 560px at ${glowX} 72%, rgba(244, 90, 30, .24), transparent 58%),
  radial-gradient(520px 420px at 8% 10%, rgba(255, 154, 69, .10), transparent 64%),
  linear-gradient(158deg, ${BRAND.eveningStart} 0%, ${BRAND.plum} 48%, ${BRAND.eveningEnd} 100%)`;

// Chrome 的工具栏弹窗是圆角浮层；这里只给圆角和投影，不画任何浏览器外框。
const popupStyle = `
  .popup { display: block; border-radius: 12px; overflow: hidden;
    box-shadow: 0 0 0 1px rgba(0, 0, 0, .22), 0 36px 72px rgba(0, 0, 0, .42), 0 10px 24px rgba(0, 0, 0, .28); }`;

function screenshotPage(card, language) {
  const tracking = language === "en" ? "-0.03em" : "0";
  const [first, second] = card.shots;
  // 单张弹窗放大到 1.12 倍（448 宽）；两种主题并排时各缩到 0.88 倍、错开叠放。
  const stage = second
    ? `<div class="pair">
         <img class="popup back" src="${dataUri(join(RAW, `${language}-${first}.png`))}" alt="">
         <img class="popup front" src="${dataUri(join(RAW, `${language}-${second}.png`))}" alt="">
       </div>`
    : `<img class="popup single" src="${dataUri(join(RAW, `${language}-${first}.png`))}" alt="">`;
  return `<!doctype html><html lang="${language}"><head><meta charset="utf-8"><style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 1280px; height: 800px; overflow: hidden; }
    body {
      font-family: ${fontStack(language)};
      background: ${background("76%")};
      display: flex; align-items: stretch; padding: 0 88px;
    }
    .copy { flex: 0 0 440px; display: flex; flex-direction: column; justify-content: center; padding-inline-end: 32px; }
    .brand { display: inline-flex; align-items: center; gap: 10px;
      color: ${BRAND.orangeBright}; font-size: 17px; font-weight: 700; letter-spacing: .04em; }
    .mark { width: 26px; height: 26px; }
    .title { margin-top: 22px; font-size: 50px; font-weight: 700; line-height: 1.14;
      letter-spacing: ${tracking}; color: ${BRAND.cream}; text-wrap: balance; }
    .sub { margin-top: 22px; font-size: 21px; line-height: 1.52;
      color: color-mix(in srgb, ${BRAND.cream} 64%, transparent); text-wrap: pretty; }
    .stage { flex: 1; min-width: 0; display: flex; align-items: center; justify-content: center; }
    ${popupStyle}
    .single { width: 448px; }
    .pair { position: relative; width: 572px; height: 580px; }
    .pair .popup { position: absolute; width: 352px; }
    /* 深色弹窗压在梅子底上会看不清边，补一圈极淡的亮边。 */
    .back { left: 0; top: 0;
      box-shadow: 0 0 0 1px rgba(255, 255, 255, .10), 0 36px 72px rgba(0, 0, 0, .42), 0 10px 24px rgba(0, 0, 0, .28); }
    .front { right: 0; bottom: 0; }
  </style></head><body>
    <div class="copy">
      <div class="brand">${brandMark(BRAND.cream)}<span>${BRAND.name}</span></div>
      <div class="title">${escapeHTML(card.title).replaceAll("\n", "<br>")}</div>
      <div class="sub">${escapeHTML(card.sub).replaceAll("\n", "<br>")}</div>
    </div>
    <div class="stage">${stage}</div>
  </body></html>`;
}

// 小宣传图缩到一半也要认得出：只有标志和品牌名。
const smallTile = `<!doctype html><html><head><meta charset="utf-8"><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 440px; height: 280px; overflow: hidden; }
  body { font-family: ${fontStack("en")}; background: ${background("70%")};
    display: flex; align-items: center; justify-content: center; gap: 20px; }
  .mark { width: 104px; height: 104px; }
  .name { color: ${BRAND.cream}; font-size: 52px; font-weight: 700; letter-spacing: -0.03em; }
</style></head><body>${brandMark(BRAND.cream)}<span class="name">${BRAND.name}</span></body></html>`;

const marquee = `<!doctype html><html><head><meta charset="utf-8"><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 1400px; height: 560px; overflow: hidden; }
  body { font-family: ${fontStack("en")}; background: ${background("74%")};
    display: flex; align-items: center; justify-content: space-between; padding: 0 150px 0 140px; }
  .lockup { display: flex; align-items: center; gap: 28px; }
  .mark { width: 150px; height: 150px; }
  .name { color: ${BRAND.cream}; font-size: 88px; font-weight: 700; letter-spacing: -0.03em; }
  ${popupStyle}
  .popup { width: 384px; }
</style></head><body>
  <div class="lockup">${brandMark(BRAND.cream)}<span class="name">${BRAND.name}</span></div>
  <img class="popup" src="${dataUri(join(RAW, "en-countdown.png"))}" alt="">
</body></html>`;

async function compose(name, html, width, height) {
  const outFile = join(OUT, `${name}.png`);
  await captureHtml({ html, htmlPath: join(HTML_DIR, `p-cws-${name}.html`), width, height, scale: 1, outFile });
  // 商店图一律压成不透明像素，和其它商店那几套一样。
  flattenPng(outFile);
  console.log(`composed ${name}.png`);
}

for (const [language, cards] of Object.entries(COPY)) {
  for (const [index, card] of cards.entries()) {
    const name = `${language}-${String(index + 1).padStart(2, "0")}-${card.shots[0]}`;
    await compose(name, screenshotPage(card, language), 1280, 800);
  }
}
await compose("promo-small-440x280", smallTile, 440, 280);
await compose("promo-marquee-1400x560", marquee, 1400, 560);

// 图标：把圆角容器（1024 画布里的 48–976）缩成 96×96，放在 128×128 透明画布正中。
const svg = readFileSync(ICON, "utf8").replace(
  /<svg[^>]*>/,
  '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><svg x="16" y="16" width="96" height="96" viewBox="48 48 928 928">',
) + "</svg>";
await sharp(Buffer.from(svg), { density: 288 }).resize(128, 128).png().toFile(join(OUT, "icon-128.png"));
console.log("composed icon-128.png");

console.log("done");
