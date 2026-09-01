import { describe, expect, it } from "vitest";
import {
  canShiftMonth,
  clampMonthKey,
  formatStatsDuration,
  formatWoodfishCountLabel,
  localDateKey,
  mergeWoodfishSeed,
  neighboringMonthKey,
  normalizeDesktopStats,
  recordAttendanceDay,
  setWoodfishDay,
  shiftMonthKey,
  summarizeMonth,
  workedMsForDay,
} from "./desktop-stats";

describe("desktop stats", () => {
  it("keys a day in the local calendar, not UTC", () => {
    expect(localDateKey(new Date(2026, 8, 1, 0, 30))).toBe("2026-09-01");
    expect(localDateKey(new Date(2026, 8, 1, 23, 59))).toBe("2026-09-01");
  });

  it("records a started shift as scheduled hours plus overtime", () => {
    const stats = recordAttendanceDay(
      { days: {} },
      {
        date: "2026-09-01",
        plannedMs: 8 * 60 * 60 * 1000,
        overtimeMs: 90 * 60 * 1000,
      }
    );

    expect(stats.days["2026-09-01"]).toEqual({
      attended: true,
      plannedMs: 8 * 60 * 60 * 1000,
      overtimeMs: 90 * 60 * 1000,
      woodfishCount: 0,
    });
    expect(workedMsForDay(stats.days["2026-09-01"])).toBe(
      8 * 60 * 60 * 1000 + 90 * 60 * 1000
    );
  });

  it("keeps woodfish knocks when the same day later logs a shift", () => {
    const withKnocks = setWoodfishDay({ days: {} }, "2026-09-01", 12);
    const withShift = recordAttendanceDay(withKnocks, {
      date: "2026-09-01",
      plannedMs: 7_200_000,
      overtimeMs: 0,
    });

    expect(withShift.days["2026-09-01"]).toMatchObject({
      attended: true,
      plannedMs: 7_200_000,
      woodfishCount: 12,
    });
  });

  it("never lowers a stored woodfish count, so in-flight writes cannot roll back taps", () => {
    const first = setWoodfishDay({ days: {} }, "2026-09-01", 5);
    const next = setWoodfishDay(first, "2026-09-01", 4);
    expect(next.days["2026-09-01"].woodfishCount).toBe(5);
  });

  it("shows the actual knock count instead of capping at 999", () => {
    const stats = setWoodfishDay({ days: {} }, "2026-09-01", 1240);
    expect(stats.days["2026-09-01"].woodfishCount).toBe(1240);
    expect(formatWoodfishCountLabel(1240)).toBe("1240");
    expect(formatWoodfishCountLabel(1_000_000)).toBe("1000000");
  });

  it("seeds today's leftover localStorage count without inventing attendance", () => {
    const seeded = mergeWoodfishSeed({ days: {} }, "2026-09-01", 18);
    expect(seeded.days["2026-09-01"]).toEqual({
      attended: false,
      plannedMs: 0,
      overtimeMs: 0,
      woodfishCount: 18,
    });
    expect(workedMsForDay(seeded.days["2026-09-01"])).toBe(0);
  });

  it("lists a month newest-first and ignores days outside it", () => {
    let stats = recordAttendanceDay(
      { days: {} },
      { date: "2026-08-31", plannedMs: 8_000, overtimeMs: 0 }
    );
    stats = recordAttendanceDay(stats, {
      date: "2026-09-02",
      plannedMs: 4_000,
      overtimeMs: 1_000,
    });
    stats = setWoodfishDay(stats, "2026-09-01", 3);

    const month = summarizeMonth(stats, "2026-09");
    expect(month.days.map((day) => day.date)).toEqual([
      "2026-09-02",
      "2026-09-01",
    ]);
    expect(month.daysWorked).toBe(1);
    expect(month.workedMs).toBe(5_000);
    expect(month.woodfishCount).toBe(3);
  });

  it("skips empty months when moving between recorded months", () => {
    const today = new Date(2026, 8, 15);
    const stats = recordAttendanceDay(
      { days: {} },
      { date: "2026-07-02", plannedMs: 1, overtimeMs: 0 }
    );

    expect(shiftMonthKey("2026-09", -1)).toBe("2026-08");
    expect(shiftMonthKey("2026-01", -1)).toBe("2025-12");
    expect(clampMonthKey("2026-10", stats, today)).toBe("2026-09");
    expect(neighboringMonthKey("2026-09", -1, stats, today)).toBe("2026-07");
    expect(canShiftMonth("2026-09", 1, stats, today)).toBe(false);
    expect(canShiftMonth("2026-07", -1, stats, today)).toBe(false);
    expect(canShiftMonth("2026-09", -1, stats, today)).toBe(true);
  });

  it("drops unreadable records instead of inventing days", () => {
    expect(
      normalizeDesktopStats({
        days: {
          nope: { attended: true, plannedMs: 1 },
          "2026-09-01": { attended: true, plannedMs: 8, overtimeMs: -3 },
          "2026-09-02": { woodfishCount: "12" },
        },
      }).days
    ).toEqual({
      "2026-09-01": {
        attended: true,
        plannedMs: 8,
        overtimeMs: 0,
        woodfishCount: 0,
      },
    });
  });

  it("formats worked time in hours and minutes", () => {
    expect(formatStatsDuration(90 * 60 * 1000, "en")).toMatch(/1/);
    expect(formatStatsDuration(90 * 60 * 1000, "en")).toMatch(/30/);
    expect(formatStatsDuration(0, "en")).toMatch(/0/);
  });
});
