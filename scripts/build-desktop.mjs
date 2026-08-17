import { spawnSync } from "node:child_process";
import { rmSync } from "node:fs";
import { resolve } from "node:path";

// 分发渠道，见 docs/PLAN-MSSTORE.md 决策 1。默认 github（NSIS / MSI / DMG）；
// 两个商店渠道的前端都不含更新器，由对应系统商店负责安装与更新。
const channelArg = process.argv
  .slice(2)
  .find((arg) => arg.startsWith("--channel="))
  ?.slice("--channel=".length);

if (
  channelArg &&
  channelArg !== "github" &&
  channelArg !== "msstore" &&
  channelArg !== "macappstore"
) {
  console.error(`Unknown desktop channel: ${channelArg}`);
  process.exit(1);
}

// macOS 包里按系统语言显示应用名的 .lproj。生成物不入库，所以必须在每次
// beforeBuildCommand 里重建——它要早于 Tauri 打包读取 bundle.resources。
// 非 macOS 上生成也无害：tauri.macos.conf.json 只在 macOS 构建时被合并，
// 这些文件不会进 Windows / Linux 的包。
const lproj = spawnSync(
  process.execPath,
  [resolve("scripts/generate-macos-lproj.mjs")],
  { stdio: "inherit" }
);

if (lproj.error) throw lproj.error;
if (lproj.status !== 0) process.exit(lproj.status ?? 1);

const result = spawnSync(
  process.execPath,
  [resolve("node_modules/next/dist/bin/next"), "build"],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      BUILD_TARGET: "desktop",
      DESKTOP_CHANNEL: channelArg ?? "github",
    },
  }
);

if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);

// public/ 会整个进静态导出，于是下载页的演示视频（约 1.2MB）也被打进 App 包，
// 而客户端永远不会打开那个页面。构建产物里删掉，仓库和 Web 构建不受影响。
rmSync(resolve("out/demo"), { recursive: true, force: true });

process.exit(0);
