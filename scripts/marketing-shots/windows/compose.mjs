// 微软商店截图：1920×1080 CSS，以 2 倍渲染成 3840×2160（商店接受的最大档，16:9）。
// 版式和 macOS 那套同源：左文右图，右边固定舞台，主窗和迷你窗都在舞台正中。
//
// 不补窗口装饰：Windows 上主窗关掉了系统标题栏，最小化 / 关闭按钮是应用自己画的，
// 已经在截图里了。窗口圆角按 Windows 11 的 8px。没有小组件那张——桌面小组件只有
// macOS 有。

import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BRAND, brandMark, escapeHTML, fontStack } from "../brand.mjs";
import { captureHtml, flattenPng } from "../chrome.mjs";

const DIR = new URL(".", import.meta.url).pathname;
const RAW = join(DIR, "raw");
const OUT = join(DIR, "out");
const HTML_DIR = join(tmpdir(), "off-work-shots-html");
mkdirSync(OUT, { recursive: true });
mkdirSync(HTML_DIR, { recursive: true });

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
      sub: "A small timer you can drag anywhere, above your other windows and off the taskbar. Tap the woodfish while you wait.",
    },
    {
      shot: "stats",
      title: "See how your month adds up",
      sub: "Days worked, hours including overtime and every woodfish knock, month by month. It all stays on this PC.",
    },
    {
      shot: "setup",
      title: "Set your hours once",
      sub: "Nine to five, twelve-hour days, or a night shift that runs past midnight.",
    },
    {
      shot: "settings",
      title: "Set it up the way you work",
      sub: "Launch at startup, a global shortcut, 19 languages, light and dark.",
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
      title: "让倒计时\n浮在最上层",
      sub: "拖到屏幕任意位置，盖在其他窗口之上，也不占任务栏。等下班的时候，还能敲敲木鱼。",
    },
    {
      shot: "stats",
      title: "这个月干了多少，\n一眼就知道",
      sub: "出勤天数、含加班的工时，还有敲过的每一下木鱼，按月记着，只存在这台电脑上。",
    },
    {
      shot: "setup",
      title: "上下班时间\n只需设置一次",
      sub: "朝九晚六、十二小时班，还是跨过午夜的夜班，都算得对。",
    },
    {
      shot: "settings",
      title: "按你的工作方式来",
      sub: "开机自启、全局快捷键、19 种语言，明暗主题跟随系统。",
    },
  ],
};

function dataUri(path) {
  if (!existsSync(path)) {
    throw new Error(`Missing ${path}. Run npm run shots:windows:capture first.`);
  }
  return `data:image/png;base64,${readFileSync(path).toString("base64")}`;
}

function page(card, language) {
  const kind = card.mini ? "mini" : "window";
  const width = card.mini ? 600 : 640;

  return `<!doctype html><html><head><meta charset="utf-8"><style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 1920px; height: 1080px; overflow: hidden; }
    body {
      font-family: ${fontStack(language)};
      background:
        radial-gradient(1000px 740px at 78% 70%, rgba(244, 90, 30, .24), transparent 58%),
        radial-gradient(700px 560px at 8% 12%, rgba(255, 154, 69, .10), transparent 64%),
        linear-gradient(158deg, ${BRAND.eveningStart} 0%, ${BRAND.plum} 48%, ${BRAND.eveningEnd} 100%);
      display: flex; align-items: stretch;
      padding: 0 132px;
    }
    .copy {
      flex: 0 0 700px; width: 700px;
      display: flex; flex-direction: column; justify-content: center;
      padding-right: 48px;
    }
    .brand {
      display: inline-flex; align-items: center; gap: 12px;
      color: ${BRAND.orangeBright}; font-size: 22px; font-weight: 700; letter-spacing: .04em;
    }
    .mark { width: 32px; height: 32px; }
    .title {
      margin-top: 28px;
      font-size: 72px; font-weight: 700; line-height: 1.12; letter-spacing: -0.03em;
      color: ${BRAND.cream}; text-wrap: balance;
    }
    .sub {
      margin-top: 28px; font-size: 30px; line-height: 1.48; font-weight: 400;
      color: color-mix(in srgb, ${BRAND.cream} 64%, transparent);
      text-wrap: balance;
    }
    .stage {
      flex: 1; min-width: 0;
      display: flex; align-items: center; justify-content: center;
    }
    .shot { position: relative; width: ${width}px; }
    .shot img { display: block; width: 100%; height: auto; }
    .shot.window {
      border-radius: 8px; overflow: hidden;
      box-shadow: 0 0 0 1px rgba(0, 0, 0, .22), 0 40px 80px rgba(0, 0, 0, .42), 0 10px 24px rgba(0, 0, 0, .28);
    }
    .shot.mini {
      filter: drop-shadow(0 32px 56px rgba(0, 0, 0, .38));
    }
  </style></head><body>
    <div class="copy">
      <div class="brand">${brandMark(BRAND.cream)}<span>${BRAND.name}</span></div>
      <div class="title">${escapeHTML(card.title).replaceAll("\n", "<br>")}</div>
      <div class="sub">${escapeHTML(card.sub)}</div>
    </div>
    <div class="stage">
      <div class="shot ${kind}">
        <img src="${dataUri(join(RAW, `${language}-${card.shot}.png`))}" alt="">
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
      htmlPath: join(HTML_DIR, `p-windows-${name}.html`),
      width: 1920,
      height: 1080,
      scale: 2,
      outFile,
    });
    // 商店拒收带透明通道的 PNG 这一条，微软与 Apple 一样稳妥起见都压实。
    flattenPng(outFile);
    console.log(`composed ${name}.png`);
  }
}

console.log("done");
