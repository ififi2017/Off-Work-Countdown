import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import vm from "node:vm";
import { afterEach, describe, expect, it } from "vitest";
import {
  createIOSNativeRulesBundle,
  writeIOSNativeRulesBundle,
} from "./build-ios-native-rules.mjs";

const temporaryDirectories = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("iOS native rule bundle", () => {
  it("keeps countdown, reminder and summary derivation behind the shared TypeScript modules", () => {
    const directory = mkdtempSync(join(tmpdir(), "owc-ios-rules-"));
    temporaryDirectories.push(directory);
    const outputPath = join(directory, "fresh", "Resources", "CountdownRules.js");
    const bundle = writeIOSNativeRulesBundle(outputPath);

    expect(bundle).toContain('require("./countdown")');
    expect(bundle).toContain('require("./reminders")');
    expect(bundle).toContain('require("./summary")');
    expect(bundle).toContain("countdown.buildShiftTimeline");
    expect(bundle).toContain(".buildShiftReminders");
    expect(bundle).not.toContain("eval(");
    expect(
      readFileSync(outputPath, "utf8")
    ).toBe(bundle);
  });

  it("executes snapshots and current-plus-next reminder projections", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);
    const input = {
      startTime: "09:00",
      endTime: "18:00",
      nowMs: new Date("2026-08-21T10:00:00+08:00").getTime(),
      workdays: [1, 2, 3, 4, 5],
      breakStartTime: "12:00",
      breakDurationMinutes: 60,
      overtimeEndAtMs: null,
      salaryAmount: "22000",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 2,
      reminderInputs: {
        mode: "simple",
        fallbackTitle: "Reminder",
        milestoneTitles: {
          milestone50: "50",
          milestone75: "25",
          milestone90: "10",
          milestone95: "5",
          milestone100: "Done",
        },
        milestoneMessages: {
          milestone50: ["50"],
          milestone75: ["25"],
          milestone90: ["10"],
          milestone95: ["5"],
          milestone100: ["Done"],
        },
        lunchStartEnabled: true,
        lunchStartBody: "Lunch",
        lunchEndEnabled: true,
        lunchEndBody: "Back",
        microBreakEnabled: false,
        microBreakIntervalMinutes: 50,
        microBreakMessages: ["Move"],
      },
    };

    const snapshot = JSON.parse(context.OWCNative.snapshot(JSON.stringify(input)));
    const reminders = JSON.parse(context.OWCNative.reminders(JSON.stringify(input)));
    const summary = JSON.parse(context.OWCNative.summarize(JSON.stringify({
      period: "week",
      asOfMs: input.nowMs,
      workdays: input.workdays,
      currentShiftStartMs: snapshot.startAtMs,
      currentShiftEndMs: snapshot.endAtMs,
      plannedDailyHours: snapshot.plannedDurationMs / 3_600_000,
      todayProgress: snapshot.progress,
      dailySalary: snapshot.dailySalary,
      todayEffectiveHours: snapshot.durationMs / 3_600_000,
      todayPayRatio: snapshot.payRatio,
    })));
    expect(snapshot.segments).toHaveLength(2);
    expect(snapshot.dailySalary).toBeCloseTo((22000 / 22) * (14 / 12));
    expect(reminders.some((reminder) => reminder.id.startsWith("current:"))).toBe(true);
    expect(reminders.some((reminder) => reminder.id.startsWith("next:"))).toBe(true);
    expect(summary.days).toBeGreaterThan(3);
    expect(summary.hours).toBeGreaterThan(24);
  });
});
