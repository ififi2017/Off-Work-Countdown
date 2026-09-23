import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  androidRuleFixturePath,
  checkAndroidRuleFixtures,
  createAndroidRuleFixtures,
} from "./generate-android-rule-fixtures.mjs";

describe("Android rule fixtures", () => {
  // A change to lib/ must reach the Kotlin rules core too; regenerate, then
  // make :core:domain:test pass against the new cases.
  it("match the current TypeScript rules", () => {
    expect(checkAndroidRuleFixtures(androidRuleFixturePath, createAndroidRuleFixtures())).toBeNull();
  }, 120_000);

  it("reports a single changed case as stale", () => {
    const committed = readFileSync(androidRuleFixturePath, "utf8");
    const edited = committed.replace('"p":0,', '"p":1,');
    expect(edited).not.toBe(committed);
    expect(checkAndroidRuleFixtures(androidRuleFixturePath, edited)).toMatch(/stale/);
  });
});
