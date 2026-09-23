import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createScheduleRuleFixtureJson } from "./generate-ios-schedule-rule-fixtures.mjs";

// Android task T06. The Kotlin rules core is held to the same TypeScript
// oracle cases as ScheduleRuleFixtureTests.swift: the body is the iOS fixture
// JSON verbatim, not a second set of cases. The header records hashes of every
// input, so a change to lib/ or the oracle makes this file stale even when the
// iOS fixture happens not to change.

const sourceFiles = [
  "lib/countdown.ts",
  "lib/reminders.ts",
  "lib/summary.ts",
  "lib/watch-projection.ts",
  "scripts/ios-schedule-rule-oracle.mjs",
  "scripts/generate-ios-schedule-rule-fixtures.mjs",
];

export const androidRuleFixturePath = resolve(
  "src-mobile/android/core/domain/src/test/resources/shared-rule-fixtures.json"
);

function sha256(text) {
  return createHash("sha256").update(text).digest("hex");
}

export function createAndroidRuleFixtures() {
  const data = createScheduleRuleFixtureJson();
  const counts = Object.fromEntries(
    Object.entries(JSON.parse(data))
      .filter(([, value]) => Array.isArray(value))
      .map(([name, rows]) => [name, rows.length])
  );
  // Line endings are normalised so a CRLF checkout hashes the same.
  const sourceHashes = Object.fromEntries(
    sourceFiles.map((path) => [path, sha256(readFileSync(resolve(path), "utf8").replace(/\r\n/g, "\n"))])
  );
  return `{"fixtureSchemaVersion":1,
"generator":"scripts/generate-android-rule-fixtures.mjs",
"note":"Generated from lib/ through scripts/ios-schedule-rule-oracle.mjs. Do not edit by hand; data is identical to the iOS ScheduleRuleFixtures.",
"sourceHashes":${JSON.stringify(sourceHashes)},
"counts":${JSON.stringify(counts)},
"data":${data}
}
`;
}

export function checkAndroidRuleFixtures(outputPath, expected) {
  let existing;
  try {
    existing = readFileSync(outputPath, "utf8");
  } catch {
    return `Android rule fixture is missing or unreadable: ${outputPath}`;
  }
  if (existing !== expected) {
    return "Android rule fixture is stale. Run: npm run generate:android-rule-fixtures";
  }
  return null;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const output = createAndroidRuleFixtures();
  if (process.argv.slice(2).includes("--check")) {
    const failure = checkAndroidRuleFixtures(androidRuleFixturePath, output);
    if (failure) {
      console.error(failure);
      process.exitCode = 1;
    }
  } else {
    mkdirSync(dirname(androidRuleFixturePath), { recursive: true });
    writeFileSync(androidRuleFixturePath, output);
  }
}
