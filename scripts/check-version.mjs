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

const tag = process.env.GITHUB_REF_NAME;
if (tag?.startsWith("desktop-v") && tag.slice("desktop-v".length) !== expected) {
  console.error(`Release tag ${tag} does not match product version ${expected}.`);
  process.exit(1);
}

console.log(`Web and desktop versions are aligned at ${expected}.`);
