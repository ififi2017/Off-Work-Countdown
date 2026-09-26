import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { swiftInputs, compileOnly } from "./generate-android-record-fixtures.mjs";

const output = process.argv[2];
if (!output) throw new Error("Pass the Kotlin export path");
const work = mkdtempSync(join(tmpdir(), "owc-roundtrip-"));
try {
  const binary = join(work, "roundtrip");
  execFileSync("xcrun", [
    "swiftc", "-O", "-swift-version", "6", "-default-isolation", "MainActor",
    ...[...swiftInputs.filter((path) => !path.endsWith("/main.swift")), ...compileOnly,
      "scripts/android-record-roundtrip/main.swift"].map((path) => resolve(path)),
    "-o", binary,
  ], { stdio: "inherit", env: { ...process.env, CLANG_MODULE_CACHE_PATH: join(work, "module-cache") } });
  execFileSync(binary, [resolve("docs/android/synthetic-archives/v6.json"), resolve(output)], { stdio: "inherit" });
} finally {
  rmSync(work, { recursive: true, force: true });
}
