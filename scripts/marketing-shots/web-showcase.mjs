// 网页版首屏以下「原生 App 展示」用的图：从本机商店图产物导出 WebP 到
// public/showcase/。out/ 与 raw/ 不入库，所以换版本时在有这些产物的检出里跑：
//
//   node scripts/marketing-shots/web-showcase.mjs [--from <marketing-shots 目录>]
//
// iPhone 用 3.2.0 商店图（17 种商店语言），电脑用 Windows 主窗 raw（19 种界面语言，
// 带自绘的最小化 / 关闭按钮，一眼能认出是电脑窗口）。宽度按页面上的最大显示宽度
// 的 2 倍取：手机约 240px → 480，电脑约 300px → 600。
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, rmSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "../..");
const fromArg = process.argv.indexOf("--from");
const shots = fromArg > 0 ? resolve(process.argv[fromArg + 1]) : here;
const iosDir = join(shots, "ios/out/creative-3.2.0");
const windowsDir = join(shots, "windows/raw");
const dest = join(repo, "public/showcase");

// 与 components/native-showcase.tsx 的 IPHONE_SHOTS 顺序、文件名一致。
const IPHONE_SHOTS = [
  ["02-countdown-detail", "countdown"],
  ["07-widgets", "widgets"],
  ["04-calendar", "calendar"],
  ["03-watch", "watch"],
];

for (const dir of [iosDir, windowsDir]) {
  if (!existsSync(dir)) {
    console.error(`Missing ${dir}. Pass --from <scripts/marketing-shots with out/ and raw/>.`);
    process.exit(1);
  }
}

function webp(src, out, width) {
  mkdirSync(dirname(out), { recursive: true });
  const r = spawnSync("cwebp", ["-quiet", "-q", "80", "-m", "6", "-resize", String(width), "0", src, "-o", out], {
    stdio: "inherit",
  });
  if (r.status !== 0) throw new Error(`cwebp failed for ${src}`);
}

rmSync(dest, { recursive: true, force: true });

const iosLocales = [
  ...new Set(
    readdirSync(iosDir)
      .map((name) => name.match(/^(.+)-iphone-02-countdown-detail\.png$/)?.[1])
      .filter(Boolean)
  ),
];
for (const locale of iosLocales) {
  for (const [source, name] of IPHONE_SHOTS) {
    webp(join(iosDir, `${locale}-iphone-${source}.png`), join(dest, locale, `iphone-${name}.webp`), 480);
  }
}

const desktopLocales = readdirSync(windowsDir)
  .map((name) => name.match(/^(.+)-countdown\.png$/)?.[1])
  .filter(Boolean);
for (const locale of desktopLocales) {
  webp(join(windowsDir, `${locale}-countdown.png`), join(dest, locale, "desktop.webp"), 600);
}

let bytes = 0;
const walk = (dir) =>
  readdirSync(dir, { withFileTypes: true }).forEach((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) walk(path);
    else bytes += statSync(path).size;
  });
walk(dest);
console.log(
  `iPhone: ${iosLocales.length} locales; desktop: ${desktopLocales.length} locales; ${(bytes / 1024 / 1024).toFixed(2)} MB`
);
