import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// These scalars live beside SwiftUI/WidgetKit views. Compile their actual
// declarations, rather than reproducing the calculations in this harness.
// Full input hashes deliberately include their UI files: any change requires
// an explicit oracle review, even when it looks unrelated to these scalars.
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const contract = "src-mobile/ios/App/App/Native/Widgets/WidgetSuiteContract.swift";
const declarations = [
  ["src-mobile/ios/App/App/Native/Widgets/WeekRosterWidgets.swift", ["WeekProgress"]],
  ["src-mobile/ios/App/App/Native/Widgets/SummaryLifeHolidayWidgets.swift", ["CalendarProgress", "LifeFigures"]],
];
const harness = "scripts/android-widget-suite-fixtures/main.swift";
const generator = "scripts/generate-android-widget-suite-fixtures.mjs";
const sourceFiles = [contract, ...declarations.map(([path]) => path), harness, generator];
export const androidWidgetSuiteFixturePath = resolve(root,
  "src-mobile/android/core/domain/src/test/resources/widget-suite-ios-scalars.json");

const read = (path) => readFileSync(resolve(root, path), "utf8").replace(/\r\n/g, "\n");
export function widgetSuiteSourceHashes() {
  return Object.fromEntries(sourceFiles.map((path) => [path,
    createHash("sha256").update(read(path)).digest("hex")]));
}

/**
 * Extract one whole declaration using Swift braces, comments and quoted
 * strings. This is deliberately a narrow lexer, not a Swift AST parser.
 * If these scalars gain dependencies, add the real source inputs; never add
 * substitute rules to the harness. Unusual future syntax (e.g. regex literals
 * with braces) may need an extractor update, and the Swift compile must pass.
 */
export function extractSwiftStruct(source, name) {
  const marker = `nonisolated struct ${name} {`;
  const start = source.indexOf(marker);
  if (start < 0 || source.indexOf(marker, start + 1) >= 0) {
    throw new Error(`Expected exactly one '${marker}' declaration`);
  }
  const opening = start + marker.length - 1;
  let depth = 1;
  let cursor = opening + 1;
  while (cursor < source.length) {
    if (source.startsWith("//", cursor)) {
      const newline = source.indexOf("\n", cursor + 2);
      cursor = newline < 0 ? source.length : newline + 1;
      continue;
    }
    if (source.startsWith("/*", cursor)) {
      let comments = 1;
      cursor += 2;
      while (cursor < source.length && comments > 0) {
        if (source.startsWith("/*", cursor)) { comments++; cursor += 2; }
        else if (source.startsWith("*/", cursor)) { comments--; cursor += 2; }
        else cursor++;
      }
      if (comments) throw new Error(`Unterminated comment in ${name}`);
      continue;
    }
    const raw = source.slice(cursor).match(/^(#+)?("""|")/);
    if (raw) {
      const hashes = raw[1] ?? "";
      const close = raw[2] + hashes;
      const escape = "\\" + hashes;
      cursor += raw[0].length;
      let closed = false;
      while (cursor < source.length) {
        if (source.startsWith(escape, cursor)) { cursor += escape.length + 1; }
        else if (source.startsWith(close, cursor)) { cursor += close.length; closed = true; break; }
        else cursor++;
      }
      if (!closed) throw new Error(`Unterminated string in ${name}`);
      continue;
    }
    if (source[cursor] === "{") depth++;
    if (source[cursor] === "}" && --depth === 0) return source.slice(start, cursor + 1);
    cursor++;
  }
  throw new Error(`Unterminated declaration ${name}`);
}

/** Cheap, platform-independent drift gate used by npm test (no Swift toolchain needed). */
export function checkWidgetSuiteSourceHashes(path = androidWidgetSuiteFixturePath) {
  let fixture;
  try { fixture = JSON.parse(readFileSync(path, "utf8")); }
  catch { return `Android widget-suite fixture is missing or unreadable: ${path}`; }
  const expected = widgetSuiteSourceHashes();
  const stale = Object.keys(expected).filter((key) => fixture.oracle?.sourceHashes?.[key] !== expected[key]);
  if (stale.length) return `Android widget-suite fixture is stale (${stale.join(", ")}). On macOS run: npm run generate:android-widget-suite-fixtures`;
  return null;
}

export function createAndroidWidgetSuiteFixtures() {
  const work = mkdtempSync(join(tmpdir(), "owc-widget-suite-"));
  try {
    const scalars = ["import Foundation", ...declarations.flatMap(([path, names]) =>
      names.map((name) => extractSwiftStruct(read(path), name)))].join("\n\n") + "\n";
    const scalarPath = join(work, "WidgetSuiteScalars.swift");
    writeFileSync(scalarPath, scalars);
    copyFileSync(resolve(root, harness), join(work, "main.swift"));
    const binary = join(work, "export");
    execFileSync("xcrun", ["swiftc", "-swift-version", "6", "-module-cache-path", join(work, "module-cache"),
      resolve(root, contract), scalarPath, join(work, "main.swift"), "-o", binary],
    { stdio: ["ignore", "ignore", "inherit"] });
    const answers = JSON.parse(execFileSync(binary, { env: { ...process.env, TZ: "UTC" }, maxBuffer: 4 * 1024 * 1024 }).toString("utf8"));
    return JSON.stringify({ ...answers, oracle: {
      fixtureSchemaVersion: 1,
      generator,
      referenceCommit: "ffd91597",
      description: "Actual Swift WidgetSuiteContract plus verbatim WeekProgress, CalendarProgress and LifeFigures. referenceCommit is the original iOS 3.2.3 baseline; sourceHashes identify every compiled source and generator input. Run on macOS; no simulator. Do not edit answers by hand.",
      sourceHashes: widgetSuiteSourceHashes(),
    } }, null, 2) + "\n";
  } finally { rmSync(work, { recursive: true, force: true }); }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.includes("--check-sources")) {
    const error = checkWidgetSuiteSourceHashes();
    if (error) { console.error(error); process.exitCode = 1; }
  } else {
    const output = createAndroidWidgetSuiteFixtures();
    if (args.includes("--check")) {
      let existing = "";
      try { existing = readFileSync(androidWidgetSuiteFixturePath, "utf8"); } catch {}
      if (existing !== output) {
        console.error("Android widget-suite fixture is stale. Run: npm run generate:android-widget-suite-fixtures");
        process.exitCode = 1;
      }
    } else {
      mkdirSync(dirname(androidWidgetSuiteFixturePath), { recursive: true });
      writeFileSync(androidWidgetSuiteFixturePath, output);
    }
  }
}
