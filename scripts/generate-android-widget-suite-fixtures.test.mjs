import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  androidWidgetSuiteFixturePath, checkWidgetSuiteSourceHashes, extractSwiftStruct,
} from "./generate-android-widget-suite-fixtures.mjs";

describe("Android widget-suite Swift oracle", () => {
  it("records the current Swift, harness and generator hashes on every platform", () => {
    expect(checkWidgetSuiteSourceHashes()).toBeNull();
  });

  it("rejects missing and stale source provenance without a Swift toolchain", () => {
    const directory = mkdtempSync(join(tmpdir(), "owc-widget-hash-test-"));
    try {
      const path = join(directory, "fixture.json");
      expect(checkWidgetSuiteSourceHashes(path)).toContain("missing or unreadable");
      const changed = JSON.parse(readFileSync(androidWidgetSuiteFixturePath, "utf8"));
      changed.oracle.sourceHashes["scripts/android-widget-suite-fixtures/main.swift"] = "stale";
      writeFileSync(path, JSON.stringify(changed));
      expect(checkWidgetSuiteSourceHashes(path)).toContain("scripts/android-widget-suite-fixtures/main.swift");
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });

  it("extracts verbatim nested declarations and ignores braces in comments and strings", () => {
    const scalar = `nonisolated struct Scalar {
      // a comment with }
      /* nested /* { } */ comment } */
      let label = "a } string"
      let raw = #"another } string"#
      func count() -> Int { if true { return 1 }; return 0 }
    }`;
    const source = `import SwiftUI\n${scalar}\nstruct RenderingOnly { }`;
    expect(extractSwiftStruct(source, "Scalar")).toBe(scalar);
    expect(() => extractSwiftStruct(source, "Missing")).toThrow("exactly one");
    expect(() => extractSwiftStruct(scalar + scalar, "Scalar")).toThrow("exactly one");
    expect(() => extractSwiftStruct("nonisolated struct Scalar {", "Scalar")).toThrow("Unterminated");
  });
});
