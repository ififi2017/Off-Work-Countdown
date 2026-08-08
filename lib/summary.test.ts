import { describe, it, expect } from "vitest";
import { startOfWeek, startOfYear, countWorkdays, summarize } from "./summary";

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
    startTime: "09:00",
    endTime: "18:00", // 9 小时
    dailySalary: 1000,
  };

  it("counts finished days in full and today by its progress", () => {
    // 周三午间，本周已完成周一、周二，今天走了一半
    const s = summarize({
      ...base,
      periodStart: at(2026, 6, 29), // 周一
      now: at(2026, 7, 1, 13), // 周三
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
      now: at(2026, 7, 4, 13), // 周六
      todayProgress: 80,
    });
    expect(s.days).toBe(5); // 周一至周五，周六不计
  });

  it("clamps progress into 0-100", () => {
    const over = summarize({
      ...base,
      periodStart: at(2026, 6, 29),
      now: at(2026, 6, 29, 13),
      todayProgress: 250,
    });
    expect(over.days).toBe(1);

    const under = summarize({
      ...base,
      periodStart: at(2026, 6, 29),
      now: at(2026, 6, 29, 13),
      todayProgress: -40,
    });
    expect(under.days).toBe(0);
  });

  it("reports null earnings when no salary is configured", () => {
    const s = summarize({
      ...base,
      dailySalary: null,
      periodStart: at(2026, 6, 29),
      now: at(2026, 7, 1, 13),
      todayProgress: 0,
    });
    expect(s.earnings).toBeNull();
    expect(s.hours).toBeCloseTo(18); // 两天 × 9 小时
  });

  it("handles an overnight shift's length correctly", () => {
    const s = summarize({
      ...base,
      startTime: "22:00",
      endTime: "06:00", // 8 小时
      periodStart: at(2026, 6, 29),
      now: at(2026, 7, 1, 13),
      todayProgress: 0,
    });
    expect(s.hours).toBeCloseTo(16);
  });
});
