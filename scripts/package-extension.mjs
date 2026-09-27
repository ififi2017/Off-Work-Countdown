// 把 build/chrome-extension 打成 Chrome 应用商店可直接上传的 ZIP：manifest.json 在
// 压缩包根目录，不带 .DS_Store。先跑 `npm run build:extension`（`npm run
// package:extension` 会连带构建）。产物是 build/doneat-chrome-extension-<version>.zip。
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(import.meta.dirname, "..");
const source = resolve(root, "build/chrome-extension");

export function packageExtension() {
  const manifestPath = resolve(source, "manifest.json");
  if (!existsSync(manifestPath)) {
    throw new Error("Missing build/chrome-extension. Run npm run build:extension first.");
  }
  const { version } = JSON.parse(readFileSync(manifestPath, "utf8"));
  const zip = resolve(root, `build/doneat-chrome-extension-${version}.zip`);
  rmSync(zip, { force: true });
  const result = spawnSync("zip", ["-qrX", zip, ".", "-x", "*.DS_Store"], {
    cwd: source,
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`zip exited with ${result.status}`);
  return { zip, version };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { zip } = packageExtension();
  console.log(`Chrome Web Store package ready: ${zip}`);
}
