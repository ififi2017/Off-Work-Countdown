import { describe, expect, it } from "vitest";
import {
  checkScheduleRuleFixtures,
  createScheduleRuleFixtures,
  scheduleRuleFixturePath,
} from "./generate-ios-schedule-rule-fixtures.mjs";

describe("iOS schedule-rule fixtures", () => {
  // A change to lib/countdown.ts must reach ScheduleRules.swift too. This
  // fails on any pull request that changes the shared rules without
  // regenerating, which is the prompt to update the Swift port with it.
  it("match the current TypeScript rules", () => {
    expect(checkScheduleRuleFixtures(scheduleRuleFixturePath, createScheduleRuleFixtures())).toBeNull();
  }, 120_000);
});
