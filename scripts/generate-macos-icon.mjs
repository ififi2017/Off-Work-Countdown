import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

// 把 assets/brand/AppIcon.icon（Icon Composer 文件，iPhone 与 Watch 共用）编译成
// macOS 包里的 Assets.car，并由 Info.plist 的 CFBundleIconName = AppIcon 引用。
// macOS 26 起 Finder、程序坞、启动台用它显示 Liquid Glass 图标；更早的系统仍读
// Tauri 从 bundle.icon 生成的 icon.icns（CFBundleIconFile），两者并存。
//
// 为什么在构建前编译而不是入库：Assets.car 是 actool 的产物，随 Xcode 版本变化，
// 源头只有 AppIcon.icon 一份。
//
// 为什么有回退：编译 .icon 需要 Xcode 26 的 actool。GitHub 的 macos-latest runner
// 不保证是这个版本。编译不了时改用现有 icon.icns 生成传统图标集再编译，保证
// Assets.car 始终存在、始终含 AppIcon——Info.plist 里的 CFBundleIconName 不能
// 指向一个不存在的资源。回退时打印原因，不静默。
//
// 非 macOS 上直接跳过：tauri.macos.conf.json 只在 macOS 构建时合并。
const SOURCE_ICON = "assets/brand/AppIcon.icon";
const FALLBACK_ICNS = "src-tauri/icons/icon.icns";
const OUTPUT_DIR = "src-tauri/target/macos-icon";
// 取两个 macOS 渠道里更低的最低系统版本（GitHub 11.3，Mac App Store 13.0），
// 让 actool 为旧系统一并生成回退图像。
const MINIMUM_DEPLOYMENT_TARGET = "11.3";

if (process.platform !== "darwin") {
  console.log("Skipping macOS icon compilation on a non-macOS host.");
  process.exit(0);
}

function run(command, args) {
  return spawnSync(command, args, { encoding: "utf8" });
}

function compile(input, label) {
  rmSync(OUTPUT_DIR, { recursive: true, force: true });
  mkdirSync(OUTPUT_DIR, { recursive: true });
  const partialPlist = resolve(OUTPUT_DIR, "partial.plist");
  const result = run("xcrun", [
    "actool",
    resolve(input),
    "--compile",
    resolve(OUTPUT_DIR),
    "--platform",
    "macosx",
    "--minimum-deployment-target",
    MINIMUM_DEPLOYMENT_TARGET,
    "--app-icon",
    "AppIcon",
    "--output-partial-info-plist",
    partialPlist,
    "--output-format",
    "human-readable-text",
  ]);
  // actool 失败时不一定返回非零（崩溃信息写在输出里），所以按产物判断。
  const assets = resolve(OUTPUT_DIR, "Assets.car");
  if (result.status !== 0 || !existsSync(assets) || !existsSync(partialPlist)) {
    return { ok: false, detail: `${result.stdout ?? ""}${result.stderr ?? ""}`.trim() };
  }
  const iconName = run("plutil", ["-extract", "CFBundleIconName", "raw", "-o", "-", partialPlist]);
  if (iconName.status !== 0 || iconName.stdout.trim() !== "AppIcon") {
    return { ok: false, detail: `${label}: partial Info.plist does not name AppIcon` };
  }
  return { ok: true };
}

function fallbackCatalog() {
  const workspace = mkdtempSync(join(tmpdir(), "owc-macos-icon-"));
  const iconset = join(workspace, "icon.iconset");
  const expanded = run("iconutil", ["-c", "iconset", "-o", iconset, resolve(FALLBACK_ICNS)]);
  if (expanded.status !== 0) {
    console.error(`Could not expand ${FALLBACK_ICNS}: ${expanded.stderr}`);
    process.exit(1);
  }
  const catalog = join(workspace, "Assets.xcassets");
  const appiconset = join(catalog, "AppIcon.appiconset");
  mkdirSync(appiconset, { recursive: true });
  const images = [];
  for (const size of [16, 32, 128, 256, 512]) {
    for (const scale of [1, 2]) {
      const filename = scale === 1 ? `icon_${size}x${size}.png` : `icon_${size}x${size}@2x.png`;
      if (!existsSync(join(iconset, filename))) {
        console.error(`${FALLBACK_ICNS} is missing ${filename}.`);
        process.exit(1);
      }
      copyFileSync(join(iconset, filename), join(appiconset, filename));
      images.push({ idiom: "mac", size: `${size}x${size}`, scale: `${scale}x`, filename });
    }
  }
  writeFileSync(join(appiconset, "Contents.json"), JSON.stringify({ images, info: { author: "xcode", version: 1 } }));
  writeFileSync(join(catalog, "Contents.json"), JSON.stringify({ info: { author: "xcode", version: 1 } }));
  return catalog;
}

const primary = compile(SOURCE_ICON, "Icon Composer");
if (primary.ok) {
  console.log(`Compiled ${SOURCE_ICON} into ${OUTPUT_DIR}/Assets.car.`);
  process.exit(0);
}

console.warn(
  `Could not compile ${SOURCE_ICON} (Icon Composer icons need Xcode 26). ` +
    `Falling back to the flat ${FALLBACK_ICNS}.\n${primary.detail}`
);
const fallback = compile(fallbackCatalog(), "fallback");
if (!fallback.ok) {
  console.error(`Fallback icon compilation failed too.\n${fallback.detail}`);
  process.exit(1);
}
console.log(`Compiled the flat fallback icon into ${OUTPUT_DIR}/Assets.car.`);
