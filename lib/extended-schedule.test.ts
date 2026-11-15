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
  newShiftType,
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

// A weekly roster (Day, Day, Night, Night, Rest, Rest, Early from Monday
// 2026-03-02) with Saturday 2026-03-07 hand-set to Day. The full Swift parity
// cases live with the native apps in the private repository.
const weeklyRule: ExtendedSchedulePlan = {
  clearedFromDayKey: null,
  handSetDays: { "2026-03-07": "00000000-0000-4000-8000-000000000001" },
  holidayOverrides: null,
  holidayRegionIdentifier: null,
  rule: {
    anchorDayKey: "2026-03-02",
    days: [
      "00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000001",
      "00000000-0000-4000-8000-000000000002", "00000000-0000-4000-8000-000000000002",
      "00000000-0000-4000-8000-000000000004", "00000000-0000-4000-8000-000000000004",
      "00000000-0000-4000-8000-000000000003",
    ],
    preset: "weekly",
  },
  shiftTypes: [
    { annualDateRange: null, breakDurationMinutes: 60, breakEnabled: true, breakStartMinutes: 720, colorHex: "#FF8800", endMinutes: 1080, id: "00000000-0000-4000-8000-000000000001", isArchived: false, kind: "work", name: "Day", startMinutes: 540 },
    { annualDateRange: null, breakDurationMinutes: 30, breakEnabled: true, breakStartMinutes: 120, colorHex: "#FF8800", endMinutes: 360, id: "00000000-0000-4000-8000-000000000002", isArchived: false, kind: "work", name: "Night", startMinutes: 1320 },
    { annualDateRange: null, breakDurationMinutes: 0, breakEnabled: false, breakStartMinutes: 0, colorHex: "#FF8800", endMinutes: 840, id: "00000000-0000-4000-8000-000000000003", isArchived: false, kind: "work", name: "Early", startMinutes: 360 },
    { annualDateRange: null, breakDurationMinutes: 0, breakEnabled: false, breakStartMinutes: 0, colorHex: "#FF8800", endMinutes: 0, id: "00000000-0000-4000-8000-000000000004", isArchived: false, kind: "rest", name: "Rest", startMinutes: 0 },
  ],
};

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
  it.each(["work", "rest"] as const)("retains a new unassigned %s shift after saving and reloading (#348)", (kind) => {
    const plan = seedPlan(fixed, today, names);
    const added: ShiftType = {
      ...newShiftType(plan, fixed), name: "Custom shift", kind,
      startMinutes: 840, endMinutes: 1320,
    };
    const next = upsertingShiftType(plan, added, today);
    const saved = settingsForPlan(next);
    const reloaded = parseScheduleSettings(JSON.stringify(saved.settings));
    expect(reloaded.plan?.shiftTypes).toContainEqual(added);
    expect(scheduleMode(reloaded)).toBe("weekly");
    // Adding a type must not change the existing week's working hours.
    for (let offset = 0; offset < 7; offset += 1) {
      const key = addDays(today, offset);
      expect(resolveScheduleDay(reloaded.plan!, key)).toEqual(resolveScheduleDay(plan, key));
    }
    const assigned = assigningCycleDay(reloaded.plan!, 5, added.id);
    const assignedReload = parseScheduleSettings(JSON.stringify(settingsForPlan(assigned).settings));
    expect(resolveScheduleDay(assignedReload.plan!, "2026-10-03").shiftTypeID).toBe(added.id);
    // Removing the assignment must not silently remove the saved type either.
    const unassigned = assigningCycleDay(assignedReload.plan!, 5, plan.rule!.days[5]);
    expect(settingsForPlan(unassigned).settings.plan?.shiftTypes).toContainEqual(added);
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
    const plan = weeklyRule;
    const next = findNextShiftTimeline({ startTime: "09:00", endTime: "17:00", workdays: [], schedule: { mode: "classic", extendedSchedule: plan }, afterMs: Date.parse("2026-03-06T12:00:00+08:00"), timeZone: "Asia/Shanghai" });
    expect(getShiftStartAtMs(next!)).toBe(Date.parse("2026-03-07T09:00:00+08:00"));
    expect(next!.segments).toHaveLength(2);
  });
  it("sums each roster day's effective hours rather than multiplying today's hours", () => {
    const plan = weeklyRule;
    const summary = summarize({ periodStart: new Date("2026-03-02T00:00:00+08:00"), asOf: new Date("2026-03-06T18:00:00+08:00"), workdays: [], schedule: { mode: "classic", extendedSchedule: plan }, currentShiftStart: new Date("2026-03-06T09:00:00+08:00"), currentShiftEnd: new Date("2026-03-06T17:00:00+08:00"), plannedDailyHours: 7, todayProgress: 100, dailySalary: 100, timeZone: "Asia/Shanghai" });
    expect(summary.days).toBe(4);
    expect(summary.hours).toBe(31);
    expect(summary.earnings).toBe(400);
  });
});
