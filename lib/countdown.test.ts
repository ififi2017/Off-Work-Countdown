import { describe, it, expect } from "vitest";
import {
  atTime,
  getShiftBounds,
  calculateProgress,
  getDailySalary,
  getShiftLengthHours,
  DEFAULT_MONTHLY_WORKING_DAYS,
} from "./countdown";
import { presets, getPreset, presetSlugs } from "./presets";

// Fixed reference date to keep tests deterministic
const day = (h: number, m = 0) => {
  const d = new Date(2026, 6, 3); // 2026-07-03 local time
  d.setHours(h, m, 0, 0);
  return d;
};

describe("atTime", () => {
  it("builds a date at the given HH:mm on the same day", () => {
    const d = atTime(day(15, 30), "09:05");
    expect(d.getHours()).toBe(9);
    expect(d.getMinutes()).toBe(5);
    expect(d.getDate()).toBe(3);
  });
});

describe("getShiftBounds", () => {
  it("keeps a normal day shift on the same day", () => {
    const { start, end } = getShiftBounds("09:00", "18:00", day(12));
    expect(start.getHours()).toBe(9);
    expect(end.getHours()).toBe(18);
    expect(start.getDate()).toBe(3);
    expect(end.getDate()).toBe(3);
  });

  it("extends an overnight shift's end into the next day (before midnight)", () => {
    const { start, end } = getShiftBounds("22:00", "06:00", day(23));
    expect(start.getDate()).toBe(3);
    expect(end.getDate()).toBe(4);
  });

  it("anchors an overnight shift's start to the previous day (after midnight)", () => {
    const { start, end } = getShiftBounds("22:00", "06:00", day(1));
    expect(start.getDate()).toBe(2); // started yesterday
    expect(end.getDate()).toBe(3);
    expect(start <= day(1)).toBe(true);
  });

  it("treats off-hours in an overnight schedule as the upcoming shift", () => {
    const { start, end } = getShiftBounds("22:00", "06:00", day(12));
    expect(start.getDate()).toBe(3);
    expect(end.getDate()).toBe(4);
    expect(start > day(12)).toBe(true); // start still in the future
  });
});

describe("calculateProgress", () => {
  it("is 50% at the midpoint of a day shift", () => {
    expect(calculateProgress("09:00", "17:00", day(13))).toBeCloseTo(50);
  });

  it("is 0% at shift start and 100% at shift end", () => {
    expect(calculateProgress("09:00", "17:00", day(9))).toBe(0);
    expect(calculateProgress("09:00", "17:00", day(17))).toBe(100);
  });

  it("clamps to 100 after the shift ends", () => {
    expect(calculateProgress("09:00", "17:00", day(20))).toBe(100);
  });

  it("handles overnight shifts after midnight", () => {
    // 22:00–06:00 shift, at 02:00 → 4h of 8h done
    expect(calculateProgress("22:00", "06:00", day(2))).toBeCloseTo(50);
  });
});

describe("getDailySalary", () => {
  it("returns the amount as-is for daily salaries", () => {
    expect(getDailySalary("500", "daily")).toBe(500);
  });

  it("divides monthly salaries by the working-day count", () => {
    expect(getDailySalary("10000", "monthly", 20)).toBeCloseTo(500);
  });

  it("uses the default working days when none is given", () => {
    expect(getDailySalary("21750", "monthly")).toBeCloseTo(
      21750 / DEFAULT_MONTHLY_WORKING_DAYS
    );
  });

  it("returns null for empty or invalid input", () => {
    expect(getDailySalary("", "monthly")).toBeNull();
    expect(getDailySalary("abc", "daily")).toBeNull();
    expect(getDailySalary("10000", "monthly", 0)).toBeNull();
  });
});

describe("getShiftLengthHours", () => {
  it("measures a same-day shift", () => {
    expect(getShiftLengthHours("09:00", "18:00")).toBe(9);
    expect(getShiftLengthHours("09:00", "17:30")).toBe(8.5);
  });

  it("carries an overnight shift into the next day", () => {
    expect(getShiftLengthHours("22:00", "06:00")).toBe(8);
    expect(getShiftLengthHours("23:30", "07:15")).toBe(7.75);
  });

  it("treats an identical start and end as a full 24 hours", () => {
    expect(getShiftLengthHours("09:00", "09:00")).toBe(24);
  });
});

describe("presets", () => {
  it("exposes unique slugs that are URL-safe", () => {
    expect(new Set(presetSlugs).size).toBe(presetSlugs.length);
    for (const slug of presetSlugs) {
      expect(slug).toMatch(/^[a-z0-9-]+$/);
      expect(encodeURIComponent(slug)).toBe(slug);
    }
  });

  it("derives the documented daily and weekly hours", () => {
    const hours = (slug: string) => {
      const p = getPreset(slug)!;
      const perDay = getShiftLengthHours(p.shift.start, p.shift.end);
      return { perDay, perWeek: perDay * p.daysPerWeek };
    };
    expect(hours("996")).toEqual({ perDay: 12, perWeek: 72 });
    expect(hours("9-to-5")).toEqual({ perDay: 8, perWeek: 40 });
    expect(hours("9-to-6")).toEqual({ perDay: 9, perWeek: 45 });
    expect(hours("night-shift")).toEqual({ perDay: 8, perWeek: 40 });
  });

  it("returns undefined for an unknown slug rather than a default", () => {
    expect(getPreset("nope")).toBeUndefined();
  });

  it("every preset has a valid shift", () => {
    for (const p of presets) {
      expect(p.shift.start).toMatch(/^\d{2}:\d{2}$/);
      expect(p.shift.end).toMatch(/^\d{2}:\d{2}$/);
      expect(p.daysPerWeek).toBeGreaterThan(0);
      expect(p.daysPerWeek).toBeLessThanOrEqual(7);
    }
  });
});
