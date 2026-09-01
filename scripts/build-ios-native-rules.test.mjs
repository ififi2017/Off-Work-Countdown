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

  it("distinguishes a future shift today from the following shift", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);

    const mondayBeforeWork = new Date(2026, 7, 24, 1, 0);
    const mondayStart = new Date(2026, 7, 24, 9, 0);
    const tuesdayStart = new Date(2026, 7, 25, 9, 0);
    const rules = {
      startTime: "09:00",
      endTime: "17:00",
      nowMs: mondayBeforeWork.getTime(),
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      breakStartTime: null,
      breakDurationMinutes: 0,
      overtimeEndAtMs: null,
      salaryAmount: "",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 0,
    };
    const snapshot = JSON.parse(context.OWCNative.snapshot(JSON.stringify(rules)));
    const widgetShifts = JSON.parse(context.OWCNative.widgetShifts(JSON.stringify({
      rules,
      throughMs: new Date(2026, 7, 27, 23, 59).getTime(),
      maximumCount: 10,
    })));

    expect(snapshot.isWorkday).toBe(true);
    expect(snapshot.startAtMs).toBe(mondayStart.getTime());
    expect(snapshot.nextShiftStartAtMs).toBe(tuesdayStart.getTime());
    expect(widgetShifts.map((shift) => shift.startAtMs)).toEqual([
      tuesdayStart.getTime(),
      new Date(2026, 7, 26, 9, 0).getTime(),
      new Date(2026, 7, 27, 9, 0).getTime(),
      // The first shift beyond the requested horizon is retained as the
      // Widget countdown target, but never rendered as an active interval.
      new Date(2026, 7, 28, 9, 0).getTime(),
    ]);
    expect(widgetShifts.every((shift) => !("dailySalary" in shift))).toBe(true);
  });

  it("expands every calendar day including rest-day planned hours", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);
    const days = JSON.parse(context.OWCNative.expandScheduleRange(JSON.stringify({
      startTime: "09:00",
      endTime: "17:00",
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      breakStartTime: null,
      breakDurationMinutes: 0,
      fromMs: new Date(2026, 7, 24).getTime(),
      throughMs: new Date(2026, 7, 30).getTime(),
    })));
    expect(days).toHaveLength(7);
    expect(days.filter((day) => day.isWorkday)).toHaveLength(5);
    expect(days.find((day) => day.dayKey === "2026-08-29").segments).toHaveLength(1);
    expect(days.every((day) => !("dailySalary" in day))).toBe(true);
  });

  it("advances clock-in progress from zero and keeps the weekend anchor stable", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);
    const rules = {
      startTime: "09:00",
      endTime: "17:00",
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      breakStartTime: null,
      breakDurationMinutes: 0,
      overtimeEndAtMs: null,
      salaryAmount: "",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 0,
    };

    const mondayJustAfterMidnight = new Date(2026, 7, 24, 0, 8);
    const beforeWork = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      ...rules,
      nowMs: mondayJustAfterMidnight.getTime(),
    })));
    expect(beforeWork.countdownProgress).toBeCloseTo(8 / (9 * 60) * 100, 5);
    expect(beforeWork.countdownProgress).toBeLessThan(2);

    const saturdayNoon = new Date(2026, 7, 29, 12, 0);
    const sundayNoon = new Date(2026, 7, 30, 12, 0);
    const saturday = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      ...rules,
      nowMs: saturdayNoon.getTime(),
    })));
    const sunday = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      ...rules,
      nowMs: sundayNoon.getTime(),
    })));
    expect(saturday.countdownAnchorAtMs).toBe(new Date(2026, 7, 29).getTime());
    expect(sunday.countdownAnchorAtMs).toBe(saturday.countdownAnchorAtMs);
    expect(sunday.countdownProgress).toBeGreaterThan(saturday.countdownProgress);
  });

  it("asks about today whenever a schedule change can alter today's record", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);
    const base = {
      startTime: "09:00",
      endTime: "17:00",
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      breakStartTime: null,
      breakDurationMinutes: 0,
      overtimeEndAtMs: null,
      salaryAmount: "",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 0,
    };
    const shouldPrompt = (current, candidate, schedulePatternChanged = false) =>
      context.OWCNative.shouldPromptApplyToday(JSON.stringify({
        current,
        candidate,
        kind: "schedule",
        schedulePatternChanged,
      }));

    const mondayAfterWork = new Date(2026, 7, 24, 18, 0).getTime();
    const settled = { ...base, nowMs: mondayAfterWork };
    expect(shouldPrompt(settled, { ...settled, startTime: "08:00", endTime: "16:00" }))
      .toBe(true);
    expect(shouldPrompt(settled, { ...settled, endTime: "19:00" })).toBe(true);

    const saturday = { ...base, nowMs: new Date(2026, 7, 29, 11, 0).getTime() };
    expect(shouldPrompt(saturday, { ...saturday, startTime: "08:00" })).toBe(false);
    const forcedSaturday = {
      ...saturday,
      forcedWorkdayStartMs: new Date(2026, 7, 29).getTime(),
    };
    expect(shouldPrompt(
      forcedSaturday,
      { ...forcedSaturday, startTime: "08:00" }
    )).toBe(false);
    expect(shouldPrompt(
      saturday,
      { ...saturday, workdays: [1, 2, 3, 4, 5, 6] },
      true
    )).toBe(true);
  });

  it("asks about today when lunch changes its record even after the break", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);
    const base = {
      startTime: "09:00",
      endTime: "17:00",
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      breakStartTime: "12:00",
      breakDurationMinutes: 60,
      overtimeEndAtMs: null,
      salaryAmount: "",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 0,
    };
    const shouldPrompt = (current, candidate) =>
      context.OWCNative.shouldPromptApplyToday(JSON.stringify({
        current,
        candidate,
        kind: "lunch",
        schedulePatternChanged: false,
      }));

    const afterLunch = { ...base, nowMs: new Date(2026, 7, 24, 14, 0).getTime() };
    expect(shouldPrompt(afterLunch, {
      ...afterLunch,
      breakStartTime: null,
      breakDurationMinutes: 0,
    })).toBe(true);
    expect(shouldPrompt(afterLunch, {
      ...afterLunch,
      breakStartTime: "15:00",
      breakDurationMinutes: 30,
    })).toBe(true);

    const beforeLunch = { ...base, nowMs: new Date(2026, 7, 24, 11, 0).getTime() };
    expect(shouldPrompt(beforeLunch, {
      ...beforeLunch,
      breakStartTime: null,
      breakDurationMinutes: 0,
    })).toBe(true);
  });

  it("keeps Friday night's overnight shift as Saturday morning settlement", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);

    const fridayStart = new Date(2026, 6, 3, 22, 0);
    const saturdayEnd = new Date(2026, 6, 4, 6, 0);
    const saturdayMorning = new Date(2026, 6, 4, 6, 30);
    const snapshot = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      startTime: "22:00",
      endTime: "06:00",
      nowMs: saturdayMorning.getTime(),
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      breakStartTime: null,
      breakDurationMinutes: 0,
      overtimeEndAtMs: null,
      salaryAmount: "",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 0,
    })));

    expect(snapshot.isWorkday).toBe(true);
    expect(snapshot.startAtMs).toBe(fridayStart.getTime());
    expect(snapshot.endAtMs).toBe(saturdayEnd.getTime());
    expect(snapshot.remainingMs).toBe(0);
  });

  it("does not replace a running overnight window with last night's settlement", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);

    const fridayNight = new Date(2026, 6, 3, 23, 0);
    const saturdayStart = new Date(2026, 6, 3, 22, 0);
    const saturdayNight = new Date(2026, 6, 4, 23, 0);
    const saturdayNightStart = new Date(2026, 6, 4, 22, 0);
    const rules = {
      startTime: "22:00",
      endTime: "06:00",
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      breakStartTime: null,
      breakDurationMinutes: 0,
      overtimeEndAtMs: null,
      salaryAmount: "",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 0,
    };

    const fridaySnapshot = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      ...rules,
      nowMs: fridayNight.getTime(),
    })));
    expect(fridaySnapshot.startAtMs).toBe(saturdayStart.getTime());
    expect(fridaySnapshot.remainingMs).toBeGreaterThan(0);

    const saturdaySnapshot = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      ...rules,
      nowMs: saturdayNight.getTime(),
    })));
    expect(saturdaySnapshot.startAtMs).toBe(saturdayNightStart.getTime());
    expect(saturdaySnapshot.remainingMs).toBeGreaterThan(0);
  });

  it("keeps a forced Saturday overnight as Sunday morning settlement", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);

    const saturdayStart = new Date(2026, 6, 4, 22, 0);
    const sundayEnd = new Date(2026, 6, 5, 6, 0);
    const sundayMorning = new Date(2026, 6, 5, 6, 30);
    const snapshot = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      startTime: "22:00",
      endTime: "06:00",
      nowMs: sundayMorning.getTime(),
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      forcedWorkdayStartMs: new Date(2026, 6, 4).setHours(0, 0, 0, 0),
      breakStartTime: null,
      breakDurationMinutes: 0,
      overtimeEndAtMs: null,
      salaryAmount: "",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 0,
    })));

    expect(snapshot.isWorkday).toBe(false);
    expect(snapshot.startAtMs).toBe(saturdayStart.getTime());
    expect(snapshot.endAtMs).toBe(sundayEnd.getTime());
    expect(snapshot.remainingMs).toBe(0);
  });

  it("keeps a day shift that overtime'd past midnight as Tuesday morning settlement", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);

    const mondayStart = new Date(2026, 6, 6, 9, 0);
    const overtimeEnd = new Date(2026, 6, 7, 1, 0);
    const afterOvertime = new Date(2026, 6, 7, 1, 30);
    const nextOpen = new Date(2026, 6, 7, 9, 30);
    const rules = {
      startTime: "09:00",
      endTime: "17:00",
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      breakStartTime: null,
      breakDurationMinutes: 0,
      overtimeEndAtMs: overtimeEnd.getTime(),
      salaryAmount: "",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 0,
    };

    const settled = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      ...rules,
      nowMs: afterOvertime.getTime(),
    })));
    expect(settled.startAtMs).toBe(mondayStart.getTime());
    expect(settled.endAtMs).toBe(overtimeEnd.getTime());
    expect(settled.remainingMs).toBe(0);
    expect(settled.isWorkday).toBe(true);

    const next = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      ...rules,
      nowMs: nextOpen.getTime(),
    })));
    expect(next.startAtMs).toBe(new Date(2026, 6, 7, 9, 0).getTime());
    expect(next.remainingMs).toBeGreaterThan(0);
  });

  it("locks a live snapshot to the requested timezone", () => {
    const context = { console };
    vm.createContext(context);
    vm.runInContext(createIOSNativeRulesBundle(), context);
    const nowMs = Date.parse("2026-08-24T17:00:00.000Z");
    const rules = {
      startTime: "09:00",
      endTime: "17:00",
      nowMs,
      workdays: [1, 2, 3, 4, 5],
      schedule: { mode: "classic" },
      breakStartTime: null,
      breakDurationMinutes: 0,
      overtimeEndAtMs: null,
      salaryAmount: "",
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusMonths: 0,
    };
    const shanghai = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      ...rules,
      timeZoneIdentifier: "Asia/Shanghai",
    })));
    const losAngeles = JSON.parse(context.OWCNative.snapshot(JSON.stringify({
      ...rules,
      timeZoneIdentifier: "America/Los_Angeles",
    })));
    expect(shanghai.startAtMs).toBe(Date.parse("2026-08-25T01:00:00.000Z"));
    expect(losAngeles.startAtMs).toBe(Date.parse("2026-08-24T16:00:00.000Z"));
  });
});
