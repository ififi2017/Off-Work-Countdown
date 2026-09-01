import { describe, it, expect } from "vitest";
import { zonedWeekStartMs, zonedYearStartMs } from "./countdown";
import { startOfWeek, startOfYear, countWorkdays, countScheduledWorkdays, summarize } from "./summary";

// 2026-07-03 是周五，2026-07-04 周六，2026-07-05 周日
const at = (y: number, m: number, d: number, h = 0) =>
  new Date(y, m - 1, d, h, 0, 0, 0);

const MON_TO_FRI = [1, 2, 3, 4, 5];

describe("startOfWeek", () => {
  it("anchors to Monday", () => {
    expect(startOfWeek(at(2026, 7, 3)).getDate()).toBe(29); // 周五 -> 6/29 周一
    expect(startOfWeek(at(2026, 6, 29)).getDate()).toBe(29); // 周一 -> 自身
  });

  it("sends Sunday back six days, not forward one", () => {
    // getDay() 里周日是 0，天真的 -(0-1) 会把周日推到「下周一」
    const sunday = at(2026, 7, 5);
    const monday = startOfWeek(sunday);
    expect(monday.getDay()).toBe(1);
    expect(monday.getDate()).toBe(29);
    expect(monday.getMonth()).toBe(5); // 六月
  });

  it("clears the time so the day boundary is unambiguous", () => {
    const s = startOfWeek(at(2026, 7, 3, 23));
    expect([s.getHours(), s.getMinutes(), s.getSeconds()]).toEqual([0, 0, 0]);
  });
});

describe("startOfYear", () => {
  it("returns 1 January of the same year", () => {
    const s = startOfYear(at(2026, 7, 3));
    expect([s.getFullYear(), s.getMonth(), s.getDate()]).toEqual([2026, 0, 1]);
  });
});

describe("countWorkdays", () => {
  it("counts a full Monday-to-Friday week", () => {
    expect(countWorkdays(at(2026, 6, 29), at(2026, 7, 4), MON_TO_FRI)).toBe(5);
  });

  it("excludes the end date", () => {
    // 周一到周二（不含周二）只有一天
    expect(countWorkdays(at(2026, 6, 29), at(2026, 6, 30), MON_TO_FRI)).toBe(1);
    expect(countWorkdays(at(2026, 6, 29), at(2026, 6, 29), MON_TO_FRI)).toBe(0);
  });

  it("respects a custom workday set", () => {
    expect(countWorkdays(at(2026, 6, 29), at(2026, 7, 6), [0, 6])).toBe(2);
  });

  it("returns zero when no days are selected", () => {
    expect(countWorkdays(at(2026, 1, 1), at(2026, 12, 31), [])).toBe(0);
  });

  it("counts every weekday of 2026 — 261", () => {
    // 2026-01-01 是周四，全年 365 天：52 整周共 260 个工作日，
    // 余下的 12-31（周四）再加 1
    expect(countWorkdays(at(2026, 1, 1), at(2027, 1, 1), MON_TO_FRI)).toBe(261);
  });

  it("advances by calendar date, so a DST month keeps its day count", () => {
    // 多数北半球时区在三月切换夏令时；按毫秒累加会漏掉或重复一天
    expect(countWorkdays(at(2026, 3, 1), at(2026, 4, 1), [0, 1, 2, 3, 4, 5, 6]))
      .toBe(31);
  });
});

describe("summarize", () => {
  const base = {
    workdays: MON_TO_FRI,
    plannedDailyHours: 9,
    dailySalary: 1000,
  };

  it("counts alternating and rotation patterns through the shared schedule rule", () => {
    expect(countScheduledWorkdays(
      at(2026, 6, 29),
      at(2026, 7, 13),
      MON_TO_FRI,
      {
        mode: "alternating",
        referenceWeekStartMs: at(2026, 6, 29).getTime(),
        referenceWeekType: "single",
        singleWeekendWorkday: 6,
      }
    )).toBe(11);
    expect(countScheduledWorkdays(
      at(2026, 7, 1),
      at(2026, 7, 9),
      [],
      {
        mode: "rotation",
        rotationAnchorMs: at(2026, 7, 1).getTime(),
        rotationWorkDays: 2,
        rotationRestDays: 2,
      }
    )).toBe(4);
  });

  it("counts finished days in full and today by its progress", () => {
    // 周三午间，本周已完成周一、周二，今天走了一半
    const s = summarize({
      ...base,
      periodStart: at(2026, 6, 29), // 周一
      asOf: at(2026, 7, 1, 13),
      currentShiftStart: at(2026, 7, 1, 9), // 周三
      currentShiftEnd: at(2026, 7, 1, 18),
      todayProgress: 50,
    });
    expect(s.days).toBeCloseTo(2.5);
    expect(s.hours).toBeCloseTo(22.5);
    expect(s.earnings).toBeCloseTo(2500);
  });

  it("ignores today when it is not a workday", () => {
    const s = summarize({
      ...base,
      periodStart: at(2026, 6, 29),
      asOf: at(2026, 7, 4, 13),
      currentShiftStart: at(2026, 7, 4, 9), // 周六
      currentShiftEnd: at(2026, 7, 4, 18),
      todayProgress: 80,
    });
    expect(s.days).toBe(5); // 周一至周五，周六不计
  });

  it("clamps progress into 0-100", () => {
    const over = summarize({
      ...base,
      periodStart: at(2026, 6, 29),
      asOf: at(2026, 6, 29, 13),
      currentShiftStart: at(2026, 6, 29, 9),
      currentShiftEnd: at(2026, 6, 29, 18),
      todayProgress: 250,
    });
    expect(over.days).toBe(1);

    const under = summarize({
      ...base,
      periodStart: at(2026, 6, 29),
      asOf: at(2026, 6, 29, 13),
      currentShiftStart: at(2026, 6, 29, 9),
      currentShiftEnd: at(2026, 6, 29, 18),
      todayProgress: -40,
    });
    expect(under.days).toBe(0);
  });

  it("reports null earnings when no salary is configured", () => {
    const s = summarize({
      ...base,
      dailySalary: null,
      periodStart: at(2026, 6, 29),
      asOf: at(2026, 7, 1, 13),
      currentShiftStart: at(2026, 7, 1, 9),
      currentShiftEnd: at(2026, 7, 1, 18),
      todayProgress: 0,
    });
    expect(s.earnings).toBeNull();
    expect(s.hours).toBeCloseTo(18); // 两天 × 9 小时
  });

  it("uses the night shift's start day for workday and week ownership", () => {
    const s = summarize({
      ...base,
      plannedDailyHours: 8,
      periodStart: at(2026, 6, 29),
      asOf: at(2026, 7, 4, 2),
      currentShiftStart: at(2026, 7, 3, 22), // 周五开始，周六凌晨仍算周五
      currentShiftEnd: at(2026, 7, 4, 6),
      todayProgress: 50,
    });
    expect(s.days).toBeCloseTo(4.5);
    expect(s.hours).toBeCloseTo(36);
  });

  it("does not carry a Sunday night shift into Monday's new week", () => {
    const s = summarize({
      ...base,
      plannedDailyHours: 8,
      periodStart: at(2026, 7, 6), // 周一
      asOf: at(2026, 7, 6, 2),
      currentShiftStart: at(2026, 7, 5, 22), // 上一周周日开始
      currentShiftEnd: at(2026, 7, 6, 6),
      todayProgress: 50,
    });
    expect(s).toEqual({ days: 0, hours: 0, earnings: 0 });
  });

  it("does not carry a New Year's Eve night shift into the new year", () => {
    const s = summarize({
      ...base,
      plannedDailyHours: 8,
      periodStart: at(2027, 1, 1),
      asOf: at(2027, 1, 1, 2),
      currentShiftStart: at(2026, 12, 31, 22),
      currentShiftEnd: at(2027, 1, 1, 6),
      todayProgress: 50,
    });
    expect(s).toEqual({ days: 0, hours: 0, earnings: 0 });
  });

  it("does not pull a future shift into the current week", () => {
    const s = summarize({
      ...base,
      periodStart: at(2026, 6, 29),
      asOf: at(2026, 7, 5, 20), // 周日，下一班是下周一
      currentShiftStart: at(2026, 7, 6, 9),
      currentShiftEnd: at(2026, 7, 6, 18),
      todayProgress: 0,
    });
    expect(s).toEqual({ days: 5, hours: 45, earnings: 5000 });
  });

  it("subtracts configured lunch from completed days", () => {
    const s = summarize({
      ...base,
      plannedDailyHours: 8,
      periodStart: at(2026, 6, 29),
      asOf: at(2026, 7, 1, 9),
      currentShiftStart: at(2026, 7, 1, 9),
      currentShiftEnd: at(2026, 7, 1, 18),
      todayProgress: 0,
    });
    expect(s.hours).toBe(16); // 周一、周二各 8 个有效工时
  });

  it("uses today's effective hours and linear overtime pay without changing past days", () => {
    const s = summarize({
      ...base,
      periodStart: at(2026, 6, 29),
      asOf: at(2026, 7, 1, 20),
      currentShiftStart: at(2026, 7, 1, 9),
      currentShiftEnd: at(2026, 7, 1, 20),
      todayProgress: 100,
      todayEffectiveHours: 10,
      todayPayRatio: 1.25,
    });
    expect(s.days).toBe(3);
    expect(s.hours).toBe(28); // 两个名义 9 小时工作日 + 今日 10 小时
    expect(s.earnings).toBe(3250); // 两个日薪 + 今日按 1.25 日薪
  });

  it("counts later workdays after a completed shift snapshot becomes stale", () => {
    const s = summarize({
      ...base,
      periodStart: at(2026, 6, 29), // 周一
      asOf: at(2026, 7, 1, 13), // 页面一直开到周三
      currentShiftStart: at(2026, 6, 29, 9),
      currentShiftEnd: at(2026, 6, 29, 18),
      todayProgress: 100,
    });
    expect(s).toEqual({ days: 2, hours: 18, earnings: 2000 });
  });

  it("counts the week in the records time zone, not the host calendar", () => {
    // 2026-07-06 04:00 UTC is Monday afternoon in Tokyo and still Sunday evening
    // in Los Angeles. The same asOf must not share a week boundary.
    const asOfMs = Date.parse("2026-07-06T04:00:00.000Z");
    const shiftStartMs = Date.parse("2026-07-06T00:00:00.000Z");
    const tokyo = summarize({
      ...base,
      periodStart: new Date(zonedWeekStartMs(asOfMs, "Asia/Tokyo")),
      asOf: new Date(asOfMs),
      currentShiftStart: new Date(shiftStartMs),
      currentShiftEnd: new Date(shiftStartMs + 9 * 3_600_000),
      todayProgress: 0,
      timeZone: "Asia/Tokyo",
    });
    const losAngeles = summarize({
      ...base,
      periodStart: new Date(zonedWeekStartMs(asOfMs, "America/Los_Angeles")),
      asOf: new Date(asOfMs),
      currentShiftStart: new Date(shiftStartMs),
      currentShiftEnd: new Date(shiftStartMs + 9 * 3_600_000),
      todayProgress: 0,
      timeZone: "America/Los_Angeles",
    });
    expect(tokyo.days).not.toBe(losAngeles.days);
  });

  it("counts the year in the records time zone, not the host calendar", () => {
    const asOfMs = Date.parse("2026-01-01T04:00:00.000Z");
    const tokyo = summarize({
      ...base,
      periodStart: new Date(zonedYearStartMs(asOfMs, "Asia/Tokyo")),
      asOf: new Date(asOfMs),
      currentShiftStart: new Date(asOfMs),
      currentShiftEnd: new Date(asOfMs + 9 * 3_600_000),
      todayProgress: 0,
      timeZone: "Asia/Tokyo",
    });
    const losAngeles = summarize({
      ...base,
      periodStart: new Date(zonedYearStartMs(asOfMs, "America/Los_Angeles")),
      asOf: new Date(asOfMs),
      currentShiftStart: new Date(asOfMs),
      currentShiftEnd: new Date(asOfMs + 9 * 3_600_000),
      todayProgress: 0,
      timeZone: "America/Los_Angeles",
    });
    expect(tokyo.days).not.toBe(losAngeles.days);
  });
});
