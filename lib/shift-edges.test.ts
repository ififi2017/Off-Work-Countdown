import { describe, expect, it } from "vitest";
import { buildShiftTimeline, findNextShiftTimeline, getShiftBounds, getShiftEndAtMs, getShiftStartAtMs } from "./countdown";
import { resolveScheduleDay, type ExtendedSchedulePlan, type ShiftType } from "./extended-schedule";

// Edges of per-day shift assignment: an overnight shift after a day or rest
// day, shifts that start exactly where the previous one ends, make-up
// workdays on a roster with several work types, and a DST night.

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const type = (n: number, name: string, kind: "work" | "rest", start: number, end: number, extra: Partial<ShiftType> = {}): ShiftType => ({
  id: id(n), name, kind, startMinutes: start, endMinutes: end, breakEnabled: false, breakStartMinutes: 0,
  breakDurationMinutes: 0, colorHex: "#FF8800", isArchived: false, ...extra,
});
const day = type(1, "Day", "work", 540, 1020);
const night = type(2, "Night", "work", 1320, 360);
const rest = type(3, "Rest", "rest", 0, 0);
const lateNight = type(4, "Late night", "work", 1320, 120);
const afternoon = type(5, "Afternoon", "work", 960, 0);
const early = type(6, "Early", "work", 0, 480);
const full = type(7, "Full", "work", 480, 480);

const plan = (extra: Partial<ExtendedSchedulePlan> & { shiftTypes: ShiftType[] }): ExtendedSchedulePlan => ({
  rule: null, handSetDays: {}, fallsBackToBaseSchedule: false, ...extra,
});
const at = (iso: string) => Date.parse(iso);
const bounds = (p: ExtendedSchedulePlan, now: number, zone: string) => {
  const { start, end } = getShiftBounds("09:00", "17:00", new Date(now), zone, p);
  return [start.getTime(), end.getTime()];
};
const shanghai = "Asia/Shanghai";

describe("overnight shift after a day or rest day", () => {
  it("counts down to tonight's night shift after a day shift, never the day shift's start", () => {
    const p = plan({ shiftTypes: [day, night, rest], handSetDays: { "2026-03-06": day.id, "2026-03-07": night.id } });
    for (const now of ["2026-03-07T00:00:00+08:00", "2026-03-07T03:00:00+08:00", "2026-03-07T05:59:00+08:00", "2026-03-07T12:00:00+08:00"]) {
      expect(bounds(p, at(now), shanghai), now).toEqual([at("2026-03-07T22:00:00+08:00"), at("2026-03-08T06:00:00+08:00")]);
    }
    const timeline = buildShiftTimeline("09:00", "17:00", new Date(at("2026-03-07T03:00:00+08:00")), { extendedSchedule: p }, shanghai);
    expect(getShiftStartAtMs(timeline)).toBe(at("2026-03-07T22:00:00+08:00"));
  });

  it("does the same after a rest day", () => {
    const p = plan({ shiftTypes: [day, night, rest], handSetDays: { "2026-03-06": rest.id, "2026-03-07": night.id } });
    expect(bounds(p, at("2026-03-07T03:00:00+08:00"), shanghai)).toEqual([at("2026-03-07T22:00:00+08:00"), at("2026-03-08T06:00:00+08:00")]);
  });

  it("does not return yesterday's already-ended overnight window", () => {
    const p = plan({ shiftTypes: [day, night, lateNight, rest], handSetDays: { "2026-03-06": lateNight.id, "2026-03-07": night.id } });
    expect(bounds(p, at("2026-03-07T05:00:00+08:00"), shanghai)).toEqual([at("2026-03-07T22:00:00+08:00"), at("2026-03-08T06:00:00+08:00")]);
  });

  it("still returns a night shift that really started yesterday", () => {
    const p = plan({ shiftTypes: [day, night, lateNight, rest], handSetDays: { "2026-03-06": lateNight.id, "2026-03-07": night.id } });
    expect(bounds(p, at("2026-03-07T01:00:00+08:00"), shanghai)).toEqual([at("2026-03-06T22:00:00+08:00"), at("2026-03-07T02:00:00+08:00")]);
    const after = plan({ shiftTypes: [day, night, rest], handSetDays: { "2026-03-06": night.id, "2026-03-07": day.id } });
    expect(bounds(after, at("2026-03-07T03:00:00+08:00"), shanghai)).toEqual([at("2026-03-06T22:00:00+08:00"), at("2026-03-07T06:00:00+08:00")]);
  });

  it("keeps the fixed-clock path: a plain overnight shift still belongs to last evening", () => {
    const { start, end } = getShiftBounds("22:00", "06:00", new Date(at("2026-03-07T03:00:00+08:00")), shanghai);
    expect([start.getTime(), end.getTime()]).toEqual([at("2026-03-06T22:00:00+08:00"), at("2026-03-07T06:00:00+08:00")]);
  });

  it("handles a DST night: Saturday 22:00 EST to Sunday 06:00 EDT is seven hours", () => {
    const p = plan({ shiftTypes: [day, night, rest], handSetDays: { "2026-03-06": day.id, "2026-03-07": night.id, "2026-03-08": rest.id } });
    const zone = "America/New_York";
    const start = at("2026-03-07T22:00:00-05:00");
    const end = at("2026-03-08T06:00:00-04:00");
    expect(end - start).toBe(7 * 3_600_000);
    for (const now of ["2026-03-07T12:00:00-05:00", "2026-03-08T01:30:00-05:00", "2026-03-08T03:30:00-04:00"]) {
      expect(bounds(p, at(now), zone), now).toEqual([start, end]);
    }
  });
});

describe("shifts that start exactly where the previous one ends", () => {
  const next = (p: ExtendedSchedulePlan, afterMs: number, inclusive?: boolean, zone = shanghai) =>
    findNextShiftTimeline({ startTime: "09:00", endTime: "17:00", workdays: [], schedule: { mode: "classic", extendedSchedule: p }, afterMs, inclusive, timeZone: zone });
  const threeShift = plan({
    shiftTypes: [afternoon, early, rest],
    rule: { preset: "custom", anchorDayKey: "2026-03-02", days: [afternoon.id, early.id] },
  });

  it("finds 00:00–08:00 right after 16:00–00:00 when the search starts at that end", () => {
    const afternoonEnd = at("2026-03-03T00:00:00+08:00");
    const found = next(threeShift, afternoonEnd, true)!;
    expect([getShiftStartAtMs(found), getShiftEndAtMs(found)]).toEqual([afternoonEnd, at("2026-03-03T08:00:00+08:00")]);
  });

  it("keeps 'after now' exclusive: a shift starting this instant is not the next one", () => {
    const found = next(threeShift, at("2026-03-03T00:00:00+08:00"))!;
    // Tuesday is the 00:00 shift; the next afternoon shift is Wednesday's.
    expect(getShiftStartAtMs(found)).toBe(at("2026-03-04T16:00:00+08:00"));
  });

  it("chains back-to-back shifts when each end seeds the next search", () => {
    let after = at("2026-03-02T12:00:00+08:00");
    let inclusive = false;
    const starts: number[] = [];
    for (let i = 0; i < 4; i += 1) {
      const found = next(threeShift, after, inclusive)!;
      starts.push(getShiftStartAtMs(found));
      after = getShiftEndAtMs(found);
      inclusive = true;
    }
    expect(starts).toEqual(["2026-03-02T16:00", "2026-03-03T00:00", "2026-03-04T16:00", "2026-03-05T00:00"].map(s => at(`${s}:00+08:00`)));
  });

  it("finds the next 24-hour daily shift at the previous one's end", () => {
    const daily = plan({ shiftTypes: [full], rule: { preset: "custom", anchorDayKey: "2026-03-02", days: [full.id] } });
    const end = at("2026-03-04T08:00:00+08:00");
    expect(getShiftStartAtMs(next(daily, at("2026-03-03T08:00:00+08:00"), true)!)).toBe(at("2026-03-03T08:00:00+08:00"));
    expect(getShiftStartAtMs(next(daily, end, true)!)).toBe(end);
    expect(getShiftStartAtMs(next(daily, end)!)).toBe(at("2026-03-05T08:00:00+08:00"));
  });

  it("applies to the plain fixed-hours path too", () => {
    const fixed = (afterMs: number, inclusive?: boolean) => findNextShiftTimeline({ startTime: "08:00", endTime: "08:00", workdays: [0, 1, 2, 3, 4, 5, 6], afterMs, inclusive, timeZone: shanghai });
    const end = at("2026-03-04T08:00:00+08:00");
    expect(getShiftStartAtMs(fixed(end, true)!)).toBe(end);
    expect(getShiftStartAtMs(fixed(end)!)).toBe(at("2026-03-05T08:00:00+08:00"));
  });
});

describe("make-up workdays on a roster with several work types", () => {
  const overrides = (...dates: string[]) => Object.fromEntries(dates.map(d => [d.replaceAll("-", ""), true]));
  const makeup = (p: ExtendedSchedulePlan, key: string) => resolveScheduleDay(p, key);

  it("takes the work type the rule assigns on that weekday", () => {
    // Week one rests on Saturday; week two works it as Night. The first work
    // type in the list is Day, which used to win every make-up day.
    const week = (saturday: ShiftType) => [day, day, day, day, day, saturday, rest].map(t => t.id);
    const p = plan({
      shiftTypes: [day, night, rest],
      rule: { preset: "alternatingWeeks", anchorDayKey: "2026-03-02", days: [...week(rest), ...week(night)] },
      holidayRegionIdentifier: "CN",
      holidayOverrides: overrides("2026-03-07", "2026-03-08"),
    });
    expect(makeup(p, "2026-03-07")).toMatchObject({ isWorkday: true, shiftTypeID: night.id, source: "holiday" });
    // No work type on a Sunday in either week: the most assigned type, Day.
    expect(makeup(p, "2026-03-08")).toMatchObject({ isWorkday: true, shiftTypeID: day.id, source: "holiday" });
  });

  it("falls back to the type the rule assigns most often", () => {
    const p = plan({
      shiftTypes: [day, night, rest],
      rule: { preset: "weekly", anchorDayKey: "2026-03-02", days: [night, night, day, rest, rest, rest, rest].map(t => t.id) },
      holidayRegionIdentifier: "CN",
      holidayOverrides: overrides("2026-03-07"),
    });
    expect(makeup(p, "2026-03-07").shiftTypeID).toBe(night.id);
  });

  it("uses the most assigned type when the cycle is not whole weeks, ties to the first reached", () => {
    const p = plan({
      shiftTypes: [day, night, rest],
      rule: { preset: "rotation", anchorDayKey: "2026-03-02", days: [night, day, rest].map(t => t.id) },
      holidayRegionIdentifier: "CN",
      holidayOverrides: overrides("2026-03-04"),
    });
    expect(makeup(p, "2026-03-04").shiftTypeID).toBe(night.id);
  });

  it("keeps the first non-archived work type without a rule or a usable one", () => {
    const p = plan({
      shiftTypes: [{ ...day, isArchived: true }, night, rest],
      rule: null,
      handSetDays: { "2026-03-02": rest.id },
      holidayRegionIdentifier: "CN",
      holidayOverrides: overrides("2026-03-07"),
    });
    expect(makeup(p, "2026-03-07").shiftTypeID).toBe(night.id);
  });
});
