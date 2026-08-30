// Mac App Store 截图：1440×900 CSS，以 2 倍渲染成 2880×1800（Apple 接受的最大档，16:10）。
// 左文右图。右边是一块固定舞台，主窗、迷你窗、小组件桌面图尺寸不同，都在舞台正中。
// App Store Connect 拒收带透明通道的 PNG。
//
// 交通灯由这里画：应用在 macOS 上用覆盖式标题栏，浏览器截图里那块是空的。

import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BRAND, brandMark, escapeHTML, fontStack } from "../brand.mjs";
import { captureHtml, flattenPng } from "../chrome.mjs";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const ASSETS = join(DIR, "assets");
const OUT = join(DIR, "out");
const HTML_DIR = join(tmpdir(), "off-work-shots-html");
mkdirSync(OUT, { recursive: true });
mkdirSync(HTML_DIR, { recursive: true });
if (existsSync(DIR)) {
  for (const name of readdirSync(DIR)) {
    if (name.startsWith("p-") && name.endsWith(".html")) rmSync(join(DIR, name));
  }
}

const COPY = {
  en: [
    {
      shot: "countdown",
      title: "Know when your time is yours",
      sub: "The time remaining, how far through you are, and what you have earned today.",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "Keep it on top of everything",
      sub: "A floating timer you can park in any corner. Tap the woodfish while you wait.",
    },
    {
      shot: "setup",
      title: "Set your hours once",
      sub: "Nine to five, twelve-hour days, or a night shift that runs past midnight.",
    },
    {
      shot: "settings",
      title: "Set it up the way you work",
      sub: "Launch at login, a global shortcut, 19 languages, light and dark.",
    },
    {
      shot: "widget",
      crop: true,
      title: "Or keep it on the desktop itself",
      sub: "Small and medium widgets, on your desktop or in Notification Center. They keep counting with the app closed.",
    },
  ],
  "zh-CN": [
    {
      shot: "countdown",
      title: "几点下班，心里有数",
      sub: "剩余时间、已完成进度，以及今天已经挣到的钱。",
    },
    {
      shot: "mini-woodfish",
      mini: true,
      title: "让倒计时浮在最上层",
      sub: "可以停在屏幕任意角落。等下班的时候，还能敲敲木鱼。",
    },
    {
      shot: "setup",
      title: "上下班时间只需设置一次",
      sub: "朝九晚六、十二小时班，还是跨过午夜的夜班，都算得对。",
    },
    {
      shot: "settings",
      title: "按你的工作习惯调整",
      sub: "开机自启、全局快捷键、19 种语言，明暗主题跟随系统。",
    },
    {
      shot: "widget",
      crop: true,
      title: "也可以直接放在桌面上",
      sub: "小号和中号两种小组件，放在桌面或通知中心。应用关着，倒计时照样在走。",
    },
  ],
};

function dataUri(path, mime) {
  if (!existsSync(path)) {
    throw new Error(`Missing ${path}. Run npm run shots:macos:capture first.`);
  }
  return `data:${mime};base64,${readFileSync(path).toString("base64")}`;
}

function sourceUri(card, language) {
  if (card.crop) {
    return dataUri(join(ASSETS, `widget-${language}.jpg`), "image/jpeg");
  }
  return dataUri(join(RAW, `${language}-${card.shot}.png`), "image/png");
}

function page(card, language) {
  const kind = card.mini ? "mini" : card.crop ? "crop" : "window";
  const width = card.mini ? 520 : card.crop ? 620 : 488;
  const lights = kind === "window"
    ? '<div class="lights" aria-hidden="true"><i></i><i></i><i></i></div>'
    : "";

  return `<!doctype html><html><head><meta charset="utf-8"><style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 1440px; height: 900px; overflow: hidden; }
    body {
      font-family: ${fontStack(language)};
      background:
        radial-gradient(760px 560px at 78% 70%, rgba(244, 90, 30, .24), transparent 58%),
        radial-gradient(520px 420px at 8% 12%, rgba(255, 154, 69, .10), transparent 64%),
        linear-gradient(158deg, ${BRAND.eveningStart} 0%, ${BRAND.plum} 48%, ${BRAND.eveningEnd} 100%);
      display: flex; align-items: stretch;
      padding: 0 88px;
    }
    .copy {
      flex: 0 0 520px; width: 520px;
      display: flex; flex-direction: column; justify-content: center;
      padding-right: 36px;
    }
    .brand {
      display: inline-flex; align-items: center; gap: 10px;
      color: ${BRAND.orangeBright}; font-size: 18px; font-weight: 700; letter-spacing: .04em;
    }
    .mark { width: 26px; height: 26px; }
    .title {
      margin-top: 22px;
      font-size: 56px; font-weight: 700; line-height: 1.14; letter-spacing: -0.03em;
      color: ${BRAND.cream}; text-wrap: balance;
    }
    .sub {
      margin-top: 22px; font-size: 24px; line-height: 1.48; font-weight: 400;
      color: color-mix(in srgb, ${BRAND.cream} 64%, transparent);
      text-wrap: balance;
    }
    .stage {
      flex: 1; min-width: 0;
      display: flex; align-items: center; justify-content: center;
    }
    .shot { position: relative; width: ${width}px; }
    .shot img { display: block; width: 100%; height: auto; }
    .shot.window, .shot.crop {
      border-radius: ${kind === "crop" ? 18 : 26}px; overflow: hidden;
      box-shadow: 0 36px 72px rgba(0, 0, 0, .42), 0 8px 20px rgba(0, 0, 0, .28);
    }
    .shot.mini {
      filter: drop-shadow(0 28px 48px rgba(0, 0, 0, .38));
    }
    .lights { position: absolute; top: 19px; left: 21px; display: flex; gap: 8px; z-index: 2; }
    .lights i { width: 13px; height: 13px; border-radius: 50%; display: block; }
    .lights i:nth-child(1) { background: #ff5f57; }
    .lights i:nth-child(2) { background: #febc2e; }
    .lights i:nth-child(3) { background: #28c840; }
  </style></head><body>
    <div class="copy">
      <div class="brand">${brandMark(BRAND.cream)}<span>${BRAND.name}</span></div>
      <div class="title">${escapeHTML(card.title)}</div>
      <div class="sub">${escapeHTML(card.sub)}</div>
    </div>
    <div class="stage">
      <div class="shot ${kind}">
        ${lights}
        <img src="${sourceUri(card, language)}" alt="">
      </div>
    </div>
  </body></html>`;
}

for (const [language, cards] of Object.entries(COPY)) {
  for (const [index, card] of cards.entries()) {
    const name = `${language}-${String(index + 1).padStart(2, "0")}-${card.shot}`;
    const outFile = join(OUT, `${name}.png`);
    await captureHtml({
      html: page(card, language),
      htmlPath: join(HTML_DIR, `p-${name}.html`),
      width: 1440,
      height: 900,
      scale: 2,
      outFile,
    });
    flattenPng(outFile);
    console.log(`composed ${name}.png`);
  }
}

console.log("done");
