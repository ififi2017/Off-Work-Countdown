import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CHROME =
  process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

/**
 * Render an HTML file to a PNG via Chrome --screenshot.
 *
 * `transparent` keeps the page background clear, so the PNG can be overlaid on
 * video. Store images must stay opaque — see flattenPng — so this is off by
 * default and only the App Preview captions ask for it.
 */
export async function captureHtml({ html, htmlPath, width, height, scale, outFile, transparent = false }) {
  writeFileSync(htmlPath, html);
  // Remove the previous image so a failed run cannot leave an old success behind.
  rmSync(outFile, { force: true });
  const profile = mkdtempSync(join(tmpdir(), "off-work-shots-"));
  const chrome = spawn(
    CHROME,
    [
      "--headless=new",
      // Short-lived renderers do not need Chrome's update-time app-bundle clone.
      "--disable-features=MacAppCodeSignClone",
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
  let stopped = false;
  const exited = new Promise((resolve, reject) => {
    chrome.once("exit", (code, signal) => {
      stopped = true;
      resolve({ code, signal });
    });
    chrome.once("error", (error) => {
      stopped = true;
      reject(error);
    });
  });
  let poll;
  let timeout;
  try {
    // Some Chrome versions keep running after --screenshot has written the PNG.
    // Wait for a complete file or an early process exit, whichever comes first.
    const result = await Promise.race([
      new Promise((resolve, reject) => {
        let lastSize = -1;
        poll = setInterval(() => {
          if (!existsSync(outFile)) return;
          const size = statSync(outFile).size;
          if (size > 0 && size === lastSize) resolve();
          lastSize = size;
        }, 150);
        timeout = setTimeout(() => reject(new Error(`Chrome timed out writing ${outFile}`)), 60000);
      }),
      exited,
    ]);
    if (result && result.code !== 0) {
      throw new Error(`Chrome exited with ${result.signal ?? result.code} writing ${outFile}`);
    }
    if (!existsSync(outFile) || statSync(outFile).size === 0) {
      throw new Error(`Chrome did not write ${outFile}`);
    }
  } finally {
    clearTimeout(timeout);
    clearInterval(poll);
    if (!stopped) {
      chrome.kill("SIGTERM");
      const forceKill = setTimeout(() => chrome.kill("SIGKILL"), 5000);
      await exited.catch(() => {}).finally(() => clearTimeout(forceKill));
    }
    rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
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
