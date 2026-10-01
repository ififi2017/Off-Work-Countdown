import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildShiftTimeline, expandScheduleRange, findNextShiftTimeline, getShiftStartAtMs } from "./countdown";
import { civilDayNumber, isValidShiftType, resolveScheduleDay, type ExtendedSchedulePlan, type ShiftType } from "./extended-schedule";
import {
  addDays,
  anchoringCycle,
  applyingMode,
  assigningCycleDay,
  cycleDayOf,
  defaultScheduleSettings,
  fixedHoursFromPlan,
  paintingDays,
  parseScheduleSettings,
  resizingCycle,
  scheduleMode,
  seedPlan,
  settingRosterDay,
  settingsForPlan,
  shiftTypeInUse,
  startingPaint,
  switchingPattern,
  upsertingShiftType,
  weekdayOf,
  workScheduleConfig,
} from "./schedule-settings";
import { summarize } from "./summary";

// Reuse the committed answers of the real Swift implementation: the new TS
// port must match iOS and the Kotlin fixture consumer before it reaches PC.
const fixtures = JSON.parse(readFileSync("src-mobile/android/core/domain/src/test/resources/extended-schedule-fixtures.json", "utf8")).data as {
  plans: { name: string; recipe: ExtendedSchedulePlan & { kind: string } }[];
  days: { plan: string; days: [string, boolean, [string, string, string | null, number] | null, string | null, string][] }[];
  timelines: { plan: string; zone: string; expected: [number, [number, number][], number][] }[];
  expansions: { plan: string; zone: string; base: string; from: number; through: number; expected: [string, number, boolean, [number, number][]][] }[];
  shiftTypeValidity: { type: ShiftType; expected: boolean }[];
  dayKeys: { dayKey: string; expected: number | null }[];
};
const plans = new Map(fixtures.plans.filter(p => p.recipe.kind === "direct" && (!p.recipe.holidayRegionIdentifier || p.recipe.holidayOverrides)).map(p => [p.name, p.recipe]));

describe("iOS roster parity", () => {
  for (const fixture of fixtures.days.filter(f => plans.has(f.plan))) {
    it(`resolves ${fixture.plan} like Swift`, () => {
      const plan = plans.get(fixture.plan)!;
      for (const [key, work, hours, id, source] of fixture.days) {
        const actual = resolveScheduleDay(plan, key);
        expect([actual.isWorkday, actual.hours && [actual.hours.startTime, actual.hours.endTime, actual.hours.breakStartTime, actual.hours.breakDurationMinutes], actual.shiftTypeID, actual.source], key).toEqual([work, hours, id, source]);
      }
    });
  }
  for (const fixture of fixtures.timelines.filter(f => plans.has(f.plan))) {
    it(`keeps per-day overnight shifts and breaks in ${fixture.plan} / ${fixture.zone}`, () => {
      for (const [now, segments, end] of fixture.expected) {
        const actual = buildShiftTimeline("09:00", "17:00", new Date(now), { extendedSchedule: plans.get(fixture.plan), breakStartTime: "12:00", breakDurationMinutes: 60 }, fixture.zone);
        expect([actual.segments.map(s => [s.startAtMs, s.endAtMs]), actual.plannedEndAtMs], String(now)).toEqual([segments, end]);
      }
    });
  }
  for (const fixture of fixtures.expansions.filter(f => plans.has(f.plan))) {
    it(`expands ${fixture.plan} / ${fixture.zone} / ${fixture.base} like Swift`, () => {
      const manual = fixture.base === "manual";
      const actual = expandScheduleRange({ startTime: manual ? "08:00" : "09:00", endTime: manual ? "16:00" : "17:00", workdays: manual ? [] : [1, 2, 3, 4, 5], schedule: { mode: manual ? "off" : "classic", extendedSchedule: plans.get(fixture.plan) }, breakStartTime: manual ? null : "12:00", breakDurationMinutes: manual ? 0 : 60, fromMs: fixture.from, throughMs: fixture.through, timeZone: fixture.zone });
      expect(actual.map(d => [d.dayKey, d.shiftAnchorStartAtMs, d.isWorkday, d.segments.map(s => [s.startAtMs, s.endAtMs])])).toEqual(fixture.expected);
    });
  }
  it("validates native shift types and civil dates", () => {
    for (const f of fixtures.shiftTypeValidity) expect(isValidShiftType(f.type), f.type.name).toBe(f.expected);
    for (const f of fixtures.dayKeys) expect(civilDayNumber(f.dayKey), f.dayKey).toBe(f.expected);
  });
});

describe("schedule settings and timer consumers", () => {
  const fixed = { startTime: "09:00", endTime: "18:00", workdays: [1, 2, 3, 4, 5], breakStartTime: "12:00", breakDurationMinutes: 60 };
  const names = { work: "Day shift", rest: "Rest" };
  const today = "2026-10-01"; // a Thursday

  it("keeps old fixed weekdays for missing or damaged preferences", () => {
    expect(parseScheduleSettings(null)).toEqual(defaultScheduleSettings());
    expect(parseScheduleSettings('{"mode":"free"}')).toEqual(defaultScheduleSettings());
    expect(parseScheduleSettings('{"manual":false,"plan":{"shiftTypes":[],"rule":{"preset":"weekly","anchorDayKey":"2026-09-28","days":["missing"]},"handSetDays":{}}}')).toEqual(defaultScheduleSettings());
  });
  it("round-trips a plan and keeps manual mode unscheduled", () => {
    const plan = applyingMode(seedPlan(fixed, today, names), "rotation", fixed, today, "Rest");
    const settings = { manual: true, plan };
    expect(parseScheduleSettings(JSON.stringify(settings))).toEqual(settings);
    expect(scheduleMode(settings)).toBe("manual");
    expect(scheduleMode({ manual: false, plan })).toBe("rotation");
    expect(findNextShiftTimeline({ ...fixed, afterMs: 0, schedule: workScheduleConfig(settings) })).toBeNull();
  });
  it("seeds the fixed weekdays as a Monday-anchored weekly cycle and folds it back", () => {
    const plan = seedPlan(fixed, today, names);
    expect(plan.rule?.anchorDayKey).toBe("2026-09-28");
    for (let offset = 0; offset < 14; offset += 1) {
      const key = addDays("2026-09-28", offset);
      expect(resolveScheduleDay(plan, key).isWorkday, key).toBe(fixed.workdays.includes(weekdayOf(key)));
    }
    expect(fixedHoursFromPlan(plan)).toEqual(fixed);
    const result = settingsForPlan(plan);
    expect(result.settings.plan).toBeNull();
    expect(seedPlan(fixed, today, names, result.settings.fixedTypes).shiftTypes.map((type) => type.id)).toEqual(plan.shiftTypes.map((type) => type.id));
  });
  it("keeps a plan once a weekly cycle uses a second work shift", () => {
    const plan = seedPlan(fixed, today, names);
    const half: ShiftType = { ...plan.shiftTypes[0], id: "HALF", name: "Half", endMinutes: 720, breakEnabled: false };
    const next = assigningCycleDay(upsertingShiftType(plan, half, today), 5, "HALF");
    expect(settingsForPlan(next).settings.plan).toEqual(next);
    expect(resolveScheduleDay(next, "2026-10-03").hours?.endTime).toBe("12:00");
  });
  it("switches templates the way iOS fills them", () => {
    const plan = seedPlan(fixed, today, names);
    const rotation = applyingMode(plan, "rotation", fixed, today, "Rest");
    expect(rotation.rule?.anchorDayKey).toBe(today);
    expect(cycleDayOf(rotation.rule!, today)).toBe(1);
    expect(cycleDayOf(anchoringCycle(rotation, today, 3).rule!, today)).toBe(3);
    expect(resizingCycle(rotation, 6, "Rest").rule?.days).toHaveLength(6);
    const alternating = applyingMode(plan, "alternating", fixed, today, "Rest");
    expect([resolveScheduleDay(alternating, "2026-10-03").isWorkday, resolveScheduleDay(alternating, "2026-10-10").isWorkday]).toEqual([false, true]);
  });
  it("keeps this month and next when the pattern is dropped for a free roster", () => {
    const plan = applyingMode(seedPlan(fixed, today, names), "free", fixed, today, "Rest");
    expect(plan.rule).toBeNull();
    for (const key of ["2026-10-01", "2026-10-31", "2026-11-30"]) {
      expect(resolveScheduleDay(plan, key).isWorkday, key).toBe(fixed.workdays.includes(weekdayOf(key)));
    }
    // December repeats November by date: the 7th was a Saturday there.
    expect(resolveScheduleDay(plan, "2026-12-07")).toMatchObject({ isWorkday: false, source: "carriedOver" });
    expect(plan.handSetDays["2026-09-30"]).toBeUndefined();
    const cleared = settingRosterDay(plan, "2026-10-05", null, today);
    expect(resolveScheduleDay(cleared, "2026-10-05").source).toBe("unassigned");
  });
  it("restores a pattern and its upcoming dates after switching away and back", () => {
    const rotation = anchoringCycle(applyingMode(seedPlan(fixed, today, names), "rotation", fixed, today, "Rest"), today, 3);
    const custom = settingRosterDay(rotation, "2026-10-09", rotation.shiftTypes[0].id, today);
    const away = switchingPattern(custom, undefined, "rotation", "weekly", fixed, today, "Rest");
    expect(away.plan.rule?.preset).toBe("weekly");
    expect(away.plan.handSetDays["2026-10-09"]).toBeUndefined();
    const back = switchingPattern(away.plan, away.patterns, "weekly", "rotation", fixed, today, "Rest");
    expect(back.plan.rule).toEqual(custom.rule);
    expect(back.plan.handSetDays).toEqual(custom.handSetDays);
    expect(parseScheduleSettings(JSON.stringify({ manual: false, plan: back.plan, patterns: back.patterns })).patterns).toEqual(back.patterns);
  });
  it("paints dates with a brush and undoes a repeat, once per stroke", () => {
    const free = applyingMode(seedPlan(fixed, today, names), "free", fixed, today, "Rest");
    const [work, rest] = free.shiftTypes;
    const paint = startingPaint(rest.id);
    // Doubling back within one stroke does not flip a date twice.
    const painted = paintingDays(free, ["2026-10-05", "2026-10-06", "2026-10-05"], paint, today);
    expect([painted.handSetDays["2026-10-05"], painted.handSetDays["2026-10-06"]]).toEqual([rest.id, rest.id]);
    paint.visited.clear();
    const undone = paintingDays(painted, ["2026-10-05"], paint, today);
    expect(undone.handSetDays["2026-10-05"]).toBe(work.id);
    // A date that had nothing set goes back to nothing.
    const again = startingPaint(work.id);
    const twice = paintingDays(free, ["2026-12-25"], again, today);
    again.visited.clear();
    expect(paintingDays(twice, ["2026-12-25"], again, today).handSetDays["2026-12-25"]).toBeUndefined();
  });
  it("applies a holiday calendar to fixed weekdays without storing a plan", () => {
    const settings = { manual: false, plan: null, holidayRegion: "CN" };
    expect(parseScheduleSettings(JSON.stringify(settings))).toEqual(settings);
    const overrides = { "20261008": false, "20261011": true };
    const config = workScheduleConfig(settings, { fixedPlan: seedPlan(fixed, today, names), overrides });
    expect(resolveScheduleDay(config.extendedSchedule!, "2026-10-08")).toMatchObject({ isWorkday: false, source: "holiday" });
    expect(resolveScheduleDay(config.extendedSchedule!, "2026-10-11")).toMatchObject({ isWorkday: true, source: "holiday", hours: { startTime: "09:00" } });
    expect(resolveScheduleDay(config.extendedSchedule!, "2026-10-12").source).toBe("rule");
    // Off, or data not loaded yet, keeps the plain fixed weekdays.
    expect(workScheduleConfig({ ...settings, holidayRegion: "" }, { fixedPlan: seedPlan(fixed, today, names), overrides }).extendedSchedule).toBeUndefined();
    expect(workScheduleConfig(settings).extendedSchedule).toBeUndefined();
    // A plan never keeps the overrides or region inside it.
    const stored = settingsForPlan({ ...applyingMode(seedPlan(fixed, today, names), "rotation", fixed, today, "Rest"), holidayOverrides: overrides, holidayRegionIdentifier: "CN" }, undefined, "CN");
    expect(stored.settings.plan).not.toHaveProperty("holidayOverrides");
    expect(stored.settings.plan).not.toHaveProperty("holidayRegionIdentifier");
    expect(stored.settings.holidayRegion).toBe("CN");
  });
  it("freezes a past day's hours when its shift type changes later", () => {
    const free = applyingMode(seedPlan(fixed, today, names), "free", fixed, today, "Rest");
    const work = free.shiftTypes[0];
    const plan = settingRosterDay(free, "2026-09-29", work.id, today);
    const edited = upsertingShiftType(plan, { ...work, startMinutes: 600 }, today);
    expect(resolveScheduleDay(edited, "2026-09-29").hours?.startTime).toBe("09:00");
    expect(resolveScheduleDay(edited, "2026-10-01").hours?.startTime).toBe("10:00");
    expect(shiftTypeInUse(edited, work.id, today)).toBe(true);
  });
  it("finds a roster shift on a fixed-weekday rest day and uses its own break", () => {
    const plan = plans.get("weekly-rule")!;
    const next = findNextShiftTimeline({ startTime: "09:00", endTime: "17:00", workdays: [], schedule: { mode: "classic", extendedSchedule: plan }, afterMs: Date.parse("2026-03-06T12:00:00+08:00"), timeZone: "Asia/Shanghai" });
    expect(getShiftStartAtMs(next!)).toBe(Date.parse("2026-03-07T09:00:00+08:00"));
    expect(next!.segments).toHaveLength(2);
  });
  it("sums each roster day's effective hours rather than multiplying today's hours", () => {
    const plan = plans.get("weekly-rule")!;
    const summary = summarize({ periodStart: new Date("2026-03-02T00:00:00+08:00"), asOf: new Date("2026-03-06T18:00:00+08:00"), workdays: [], schedule: { mode: "classic", extendedSchedule: plan }, currentShiftStart: new Date("2026-03-06T09:00:00+08:00"), currentShiftEnd: new Date("2026-03-06T17:00:00+08:00"), plannedDailyHours: 7, todayProgress: 100, dailySalary: 100, timeZone: "Asia/Shanghai" });
    expect(summary.days).toBe(4);
    expect(summary.hours).toBe(31);
    expect(summary.earnings).toBe(400);
  });
});
