import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const CHROME =
  process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

function waitForFile(path, timeoutMs) {
  const started = Date.now();
  let lastSize = -1;
  return new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      if (existsSync(path)) {
        const size = statSync(path).size;
        if (size > 0 && size === lastSize) {
          clearInterval(timer);
          resolve();
          return;
        }
        lastSize = size;
      }
      if (Date.now() - started > timeoutMs) {
        clearInterval(timer);
        reject(new Error(`Chrome did not write ${path}`));
      }
    }, 150);
  });
}

/**
 * Render an HTML file to a PNG via Chrome --screenshot.
 *
 * `transparent` keeps the page background clear, so the PNG can be overlaid on
 * video. Store images must stay opaque — see flattenPng — so this is off by
 * default and only the App Preview captions ask for it.
 */
export async function captureHtml({ html, htmlPath, width, height, scale, outFile, transparent = false }) {
  writeFileSync(htmlPath, html);
  // waitForFile 只看文件在不在、大小稳不稳。重跑时上一轮的成品已经在那儿，
  // 不先删掉就会立刻判定完成、杀掉 Chrome，旧图原样留下，脚本照样报 composed。
  rmSync(outFile, { force: true });
  const profile = mkdtempSync(join(tmpdir(), "off-work-shots-"));
  const chrome = spawn(
    CHROME,
    [
      "--headless=new",
      "--disable-gpu",
      "--disable-extensions",
      "--disable-background-networking",
      "--disable-component-update",
      "--disable-sync",
      "--no-first-run",
      "--no-default-browser-check",
      "--hide-scrollbars",
      "--force-color-profile=srgb",
      ...(transparent ? ["--default-background-color=00000000"] : []),
      "--font-render-hinting=none",
      `--force-device-scale-factor=${scale}`,
      `--window-size=${width},${height}`,
      `--user-data-dir=${profile}`,
      `--screenshot=${outFile}`,
      "--virtual-time-budget=8000",
      `file://${htmlPath}`,
    ],
    { stdio: "ignore" },
  );
  try {
    await waitForFile(outFile, 20000);
  } finally {
    chrome.kill("SIGKILL");
    await sleep(50);
    rmSync(profile, { recursive: true, force: true });
  }
}

/** App Store Connect and Xiaohongshu both want fully opaque pixels. */
export function flattenPng(file) {
  const bmp = `${file}.opaque.bmp`;
  const bmpResult = spawnSync("sips", ["-s", "format", "bmp", file, "--out", bmp], {
    encoding: "utf8",
  });
  if (bmpResult.status !== 0) {
    throw new Error(bmpResult.stderr || `sips could not flatten ${file}`);
  }
  const pngResult = spawnSync("sips", ["-s", "format", "png", bmp, "--out", file], {
    encoding: "utf8",
  });
  rmSync(bmp, { force: true });
  if (pngResult.status !== 0) {
    throw new Error(pngResult.stderr || `sips could not rewrite ${file}`);
  }
}
