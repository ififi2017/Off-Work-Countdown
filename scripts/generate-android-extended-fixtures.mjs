import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Android task T08. Extended scheduling has no TypeScript oracle: the Swift in
// src-mobile/ios/Shared is the specification. This compiles that Swift with
// scripts/android-extended-fixtures/main.swift on macOS and records its answers
// for the Kotlin port. The header hashes every Swift input, so a Swift change
// makes the fixture stale on any platform; regenerating needs Xcode.

const models = "src-mobile/ios/App/App/Native/Models";
const sharedDir = "src-mobile/ios/Shared";
const swiftInputs = [
  `${sharedDir}/ExtendedSchedule.swift`,
  `${sharedDir}/ExtendedScheduleRules.swift`,
  `${sharedDir}/HolidayCalendar.swift`,
  `${sharedDir}/ScheduleRuleInput.swift`,
  `${sharedDir}/ShiftRuleCore.swift`,
  `${models}/ScheduleRules.swift`,
  `${models}/CountdownRules.swift`,
  `${models}/ReminderRules.swift`,
  `${models}/CareerPeriod.swift`,
  "scripts/android-extended-fixtures/main.swift",
];
// Compiled for their types only; their behaviour is not part of the fixture.
const compileOnly = [
  `${sharedDir}/WatchDisplayProjection.swift`,
  `${sharedDir}/WatchPairing.swift`,
  `${sharedDir}/WatchScheduleV2.swift`,
  `${sharedDir}/WatchShiftEvaluation.swift`,
  `${sharedDir}/WatchSnapshot.swift`,
  `${sharedDir}/WatchSnapshotCache.swift`,
];
const holidayData = `${sharedDir}/Resources/HolidayTemplates.json`;

export const androidExtendedFixturePath = resolve(
  "src-mobile/android/core/domain/src/test/resources/extended-schedule-fixtures.json"
);

function sha256(text) {
  return createHash("sha256").update(text).digest("hex");
}

export function extendedSourceHashes() {
  return Object.fromEntries(
    [...swiftInputs, holidayData].map((path) => [path, sha256(readFileSync(resolve(path), "utf8").replace(/\r\n/g, "\n"))])
  );
}

function header(hashes) {
  return `{"fixtureSchemaVersion":1,
"generator":"scripts/generate-android-extended-fixtures.mjs",
"note":"Answers of the Swift extended-schedule rules (src-mobile/ios/Shared). Do not edit by hand.",
"sourceHashes":${JSON.stringify(hashes)},
"data":`;
}

export function createAndroidExtendedFixtures() {
  const work = mkdtempSync(join(tmpdir(), "owc-extended-"));
  try {
    const binary = join(work, "export");
    execFileSync("xcrun", [
      "swiftc", "-O", "-swift-version", "6", "-default-isolation", "MainActor",
      ...[...swiftInputs, ...compileOnly].map((path) => resolve(path)),
      "-o", binary,
    ], { stdio: ["ignore", "ignore", "inherit"] });
    // A command-line tool's main bundle is its directory.
    copyFileSync(resolve(holidayData), join(work, "HolidayTemplates.json"));
    const output = execFileSync(binary, { cwd: work, maxBuffer: 256 * 1024 * 1024 }).toString("utf8").trimEnd();
    JSON.parse(output);
    return `${header(extendedSourceHashes())}${output}\n}\n`;
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

/** Cheap and platform-independent: do the committed hashes still match the Swift sources? */
export function checkExtendedSourceHashes(outputPath) {
  let existing;
  try {
    existing = JSON.parse(readFileSync(outputPath, "utf8"));
  } catch {
    return `Android extended-schedule fixture is missing or unreadable: ${outputPath}`;
  }
  const expected = extendedSourceHashes();
  const stale = Object.keys(expected).filter((path) => existing.sourceHashes?.[path] !== expected[path]);
  if (stale.length > 0) {
    return `Android extended-schedule fixture is stale (${stale.join(", ")}). On macOS run: npm run generate:android-extended-fixtures`;
  }
  return null;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const output = createAndroidExtendedFixtures();
  if (process.argv.slice(2).includes("--check")) {
    let existing = "";
    try {
      existing = readFileSync(androidExtendedFixturePath, "utf8");
    } catch {}
    if (existing !== output) {
      console.error("Android extended-schedule fixture is stale. Run: npm run generate:android-extended-fixtures");
      process.exitCode = 1;
    }
  } else {
    mkdirSync(dirname(androidExtendedFixturePath), { recursive: true });
    writeFileSync(androidExtendedFixturePath, output);
  }
}
