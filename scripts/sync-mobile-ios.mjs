import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { normalizeCapacitorIOSPackageManifest } from "./mobile-ios-package.mjs";

function runNode(entry, args = []) {
  const result = spawnSync(process.execPath, [resolve(entry), ...args], {
    stdio: "inherit",
    env: process.env,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

runNode("scripts/build-mobile.mjs");
runNode("node_modules/@capacitor/cli/bin/capacitor", ["sync", "ios"]);

// Capacitor 8.4.2 keeps swift-tools-version at 5.9 but emits `.v26`, which is
// only available in PackageDescription 6.2. The string overload has existed
// since PackageDescription 5.0 and expresses the same deployment target.
const packagePath = resolve("src-mobile/ios/App/CapApp-SPM/Package.swift");
const source = readFileSync(packagePath, "utf8");
writeFileSync(
  packagePath,
  normalizeCapacitorIOSPackageManifest(source, "26.0"),
  "utf8"
);
