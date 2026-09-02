import { spawnSync } from "node:child_process";
import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const DIR = new URL(".", import.meta.url).pathname;
const OUT = process.env.XHS_SHOTS_OUT_DIR || join(DIR, "out");
const EXPECTED = "1080x1440";
const MAX_JPEG_BYTES = 5 * 1024 * 1024;

const pngs = readdirSync(OUT).filter((name) => name.endsWith(".png")).sort();
const jpgs = readdirSync(OUT).filter((name) => name.endsWith(".jpg")).sort();

if (pngs.length !== 3) {
  throw new Error(`Expected 3 PNG cards, found ${pngs.length}`);
}
if (jpgs.length !== 3) {
  throw new Error(`Expected 3 JPEG cards, found ${jpgs.length}`);
}

function inspect(file) {
  const result = spawnSync(
    "sips",
    ["-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", join(OUT, file)],
    { encoding: "utf8" },
  );
  if (result.status !== 0) throw new Error(result.stderr || `sips failed for ${file}`);
  return {
    width: result.stdout.match(/pixelWidth: (\d+)/)?.[1],
    height: result.stdout.match(/pixelHeight: (\d+)/)?.[1],
    alpha: result.stdout.match(/hasAlpha: (\w+)/)?.[1],
  };
}

for (const file of pngs) {
  const { width, height, alpha } = inspect(file);
  const actual = `${width}x${height}`;
  if (actual !== EXPECTED) {
    throw new Error(`${file} is ${actual}; expected ${EXPECTED}`);
  }
  if (alpha !== "no") {
    throw new Error(`${file} has an alpha channel`);
  }
}

for (const file of jpgs) {
  const { width, height } = inspect(file);
  const actual = `${width}x${height}`;
  if (actual !== EXPECTED) {
    throw new Error(`${file} is ${actual}; expected ${EXPECTED}`);
  }
  const bytes = statSync(join(OUT, file)).size;
  if (bytes > MAX_JPEG_BYTES) {
    throw new Error(`${file} is ${(bytes / 1024 / 1024).toFixed(1)} MB; Xiaohongshu caps uploads at 20 MB, keep JPEGs under 5 MB`);
  }
}

console.log(`validated ${pngs.length} opaque 3:4 Xiaohongshu cards`);
