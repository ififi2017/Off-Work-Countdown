// 把 tauri 产出的可执行文件暂存成 MSIX 打包所需的目录结构，然后调用 winapp CLI
// 产出 .msixbundle。见 docs/PLAN-M6-MSSTORE.md 决策 4。
//
//   node scripts/pack-msix.mjs x64="<exe 路径>" arm64="<exe 路径>"
//   node scripts/pack-msix.mjs x64="<exe 路径>" --stage-only   # 只暂存，不打包
//   node scripts/pack-msix.mjs x64="<exe 路径>" --cert devcert.pfx  # 本地 sideload
//
// 为什么要暂存而不是直接指 target/release：那个目录有好几个 G 的中间产物，
// winapp pack 会把输入目录整个打进包里。
//
// 提交商店的包**不要**签名（不传 --cert），商店过认证后会用微软证书重签。
// --cert 只用于本地装机验收，那种场景下证书还得先 winapp cert install 信任。

import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { basename, join } from "node:path";

const MANIFEST = "src-tauri/msstore/Package.appxmanifest";
const ICON_DIR = "src-tauri/icons";
const STAGING_ROOT = "src-tauri/target/msix";

const args = process.argv.slice(2);
const stageOnly = args.includes("--stage-only");
const flagValue = (name) => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const cert = flagValue("--cert");
const output = flagValue("--out");

const slices = args
  .filter((arg) => /^[a-z0-9]+=/i.test(arg))
  .map((arg) => {
    const [arch, ...rest] = arg.split("=");
    return { arch, exe: rest.join("=") };
  });

if (slices.length === 0) {
  console.error(
    'Usage: node scripts/pack-msix.mjs x64="<path to exe>" [arm64="<path to exe>"] [--stage-only] [--cert <pfx>] [--out <file>]'
  );
  process.exit(1);
}

const manifest = readFileSync(MANIFEST, "utf8");

// 可执行文件名必须与 manifest 的 Executable 完全一致。不一致的包能装上、能过
// 打包，但点开什么都不会发生——这种问题只有在提交之后才会被发现，所以在这里拦。
const declaredExe = manifest.match(/<Application\b[^>]*\bExecutable="([^"]+)"/)?.[1];
if (!declaredExe) {
  console.error(`Could not read Application/@Executable from ${MANIFEST}.`);
  process.exit(1);
}

// manifest 引用了哪些图标就复制哪些，避免脚本和 manifest 各持一份清单后悄悄漂移。
const assets = [...new Set([...manifest.matchAll(/Assets\\([A-Za-z0-9._-]+)/g)].map((m) => m[1]))];
if (assets.length === 0) {
  console.error(`No Assets\\* references found in ${MANIFEST}; refusing to build an icon-less package.`);
  process.exit(1);
}

rmSync(STAGING_ROOT, { recursive: true, force: true });

const stagedDirs = [];
for (const { arch, exe } of slices) {
  if (!existsSync(exe)) {
    console.error(`Missing executable for ${arch}: ${exe}`);
    process.exit(1);
  }
  if (basename(exe) !== declaredExe) {
    console.error(
      `Executable name mismatch for ${arch}.\n` +
        `  manifest declares: ${declaredExe}\n` +
        `  staged file is:    ${basename(exe)}\n` +
        `Set mainBinaryName in src-tauri/tauri.msstore.conf.json, or fix the manifest.`
    );
    process.exit(1);
  }

  const dir = join(STAGING_ROOT, arch);
  mkdirSync(join(dir, "Assets"), { recursive: true });
  copyFileSync(exe, join(dir, declaredExe));
  for (const asset of assets) {
    const source = join(ICON_DIR, asset);
    if (!existsSync(source)) {
      console.error(`Manifest references Assets\\${asset} but ${source} does not exist.`);
      process.exit(1);
    }
    copyFileSync(source, join(dir, "Assets", asset));
  }
  stagedDirs.push(dir);
  console.log(`Staged ${arch}: ${dir}`);
}

if (stageOnly) {
  console.log(`Staged ${stagedDirs.length} architecture(s); skipping winapp pack.`);
  process.exit(0);
}

const packArgs = [...stagedDirs, "--manifest", MANIFEST, "--executable", declaredExe];
if (cert) packArgs.push("--cert", cert);
if (output) packArgs.push("--output", output);

console.log(`winapp ${["pack", ...packArgs].join(" ")}`);
// 刻意不用 shell:true：可执行文件名带空格，交给 shell 拼接会被拆成三个参数，
// 打出来的包能装上却指向一个不存在的入口。
const result = spawnSync("winapp", ["pack", ...packArgs], { stdio: "inherit" });

if (result.error) {
  if (result.error.code === "ENOENT") {
    console.error(
      "winapp CLI not found. Install it with: winget install microsoft.winappcli --source winget"
    );
    process.exit(1);
  }
  throw result.error;
}
process.exit(result.status ?? 1);
