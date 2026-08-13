import { spawnSync } from "node:child_process";
import { rmSync } from "node:fs";
import { resolve } from "node:path";

// 分发渠道，见 docs/PLAN-M6-MSSTORE.md 决策 1。默认 github（NSIS / MSI / DMG）；
// `--channel=msstore` 产出的前端不含更新器，更新入口深链到微软商店。
const channelArg = process.argv
  .slice(2)
  .find((arg) => arg.startsWith("--channel="))
  ?.slice("--channel=".length);

if (channelArg && channelArg !== "github" && channelArg !== "msstore") {
  console.error(`Unknown desktop channel: ${channelArg}`);
  process.exit(1);
}

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
