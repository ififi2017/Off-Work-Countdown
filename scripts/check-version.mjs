import { readFileSync } from "node:fs";

const packageJson = JSON.parse(readFileSync("package.json", "utf8"));
const packageLock = JSON.parse(readFileSync("package-lock.json", "utf8"));
const tauriConfig = JSON.parse(
  readFileSync("src-tauri/tauri.conf.json", "utf8")
);
const cargoToml = readFileSync("src-tauri/Cargo.toml", "utf8");
const cargoVersion = cargoToml.match(
  /^\[package\][\s\S]*?^version\s*=\s*"([^"]+)"/m
)?.[1];

const versions = {
  package: packageJson.version,
  packageLock: packageLock.version,
  packageLockRoot: packageLock.packages?.[""]?.version,
  tauri: tauriConfig.version,
  cargo: cargoVersion,
};
const expected = versions.package;
const mismatches = Object.entries(versions).filter(
  ([, version]) => version !== expected
);

if (mismatches.length > 0) {
  console.error("Product versions must stay in sync:", versions);
  process.exit(1);
}

// MSIX 的包版本必须四段，且第四段保留给商店、必须是 0。它不参与上面那轮比较：
// 格式本来就不同，硬凑进去只会让错误信息更难读。
// 见 docs/PLAN-MSSTORE.md 决策 5。
const appxManifest = readFileSync(
  "src-tauri/msstore/Package.appxmanifest",
  "utf8"
);
const appxVersion = appxManifest.match(
  /<Identity[\s\S]*?\bVersion="([^"]+)"/
)?.[1];
const expectedAppxVersion = `${expected}.0`;

if (appxVersion !== expectedAppxVersion) {
  console.error(
    `Package.appxmanifest version ${appxVersion ?? "(not found)"} must be ${expectedAppxVersion}.`
  );
  process.exit(1);
}

const tag = process.env.GITHUB_REF_NAME;
if (tag?.startsWith("desktop-v") && tag.slice("desktop-v".length) !== expected) {
  console.error(`Release tag ${tag} does not match product version ${expected}.`);
  process.exit(1);
}

console.log(
  `Web and desktop versions are aligned at ${expected} (MSIX ${expectedAppxVersion}).`
);
