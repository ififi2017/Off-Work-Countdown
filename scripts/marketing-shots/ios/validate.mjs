import { spawnSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { join } from "node:path";

const DIR = new URL(".", import.meta.url).pathname;
const OUT = process.env.IOS_SHOTS_OUT_DIR || join(DIR, "out");
const files = readdirSync(OUT).filter((name) => name.endsWith(".png")).sort();
const expected = {
  iphone: "1320x2868",
  ipad: "2064x2752",
};

if (files.length !== 12) {
  throw new Error(`Expected 12 localized screenshots (3 per language per device), found ${files.length}`);
}

for (const file of files) {
  const platform = file.includes("-iphone-") ? "iphone" : file.includes("-ipad-") ? "ipad" : null;
  if (!platform) throw new Error(`Cannot determine platform for ${file}`);

  const result = spawnSync("sips", [
    "-g", "pixelWidth",
    "-g", "pixelHeight",
    "-g", "hasAlpha",
    join(OUT, file),
  ], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || `sips failed for ${file}`);

  const width = result.stdout.match(/pixelWidth: (\d+)/)?.[1];
  const height = result.stdout.match(/pixelHeight: (\d+)/)?.[1];
  const alpha = result.stdout.match(/hasAlpha: (\w+)/)?.[1];
  const actual = `${width}x${height}`;
  if (actual !== expected[platform]) {
    throw new Error(`${file} is ${actual}; expected ${expected[platform]}`);
  }
  if (alpha !== "no") {
    throw new Error(`${file} has an alpha channel; App Store screenshots must be opaque`);
  }
}

console.log(`validated ${files.length} opaque App Store screenshots`);
