import { describe, it, expect } from "vitest";
import { zonedWeekStartMs, zonedYearStartMs } from "./countdown";
import {
  completedWorkdayIncome,
  countScheduledWorkdays,
  countWorkdays,
  earningsForRatio,
  projectLifetimeGrossIncome,
  startOfWeek,
  startOfYear,
  summarize,
  summarizeRecordsActualAndForecast,
} from "./summary";

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

describe("earnings", () => {
  it("keeps live pay-ratio derivation in the shared rules", () => {
    expect(earningsForRatio(1_000, 0.5)).toBe(500);
    expect(earningsForRatio(1_000, 1.25)).toBe(1_250);
    expect(earningsForRatio(null, 1)).toBeNull();
  });

  it("counts only whole completed workdays for Records", () => {
    expect(completedWorkdayIncome(2, 1_000)).toBe(2_000);
    expect(completedWorkdayIncome(2.9, 1_000)).toBe(2_000);
    expect(completedWorkdayIncome(2, null)).toBeNull();
  });
});

describe("lifetime gross income", () => {
  it("uses supplied salaries, leaves gaps at zero, and carries the current salary to retirement", () => {
    const result = projectLifetimeGrossIncome({
      asOf: "2020-01-01",
      retirementOn: "2030-01-01",
      periods: [
        {
          startsOn: "2010-01-01",
          endsOn: "2015-01-01",
          salaryAmount: 60_000,
          salaryCadence: "yearly",
        },
      ],
      // 2015-2020 is intentionally absent: an employment gap earns zero.
      currentSalary: { salaryAmount: 10_000, salaryCadence: "monthly" },
    });
    expect(result.historicalGross).toBe(300_000);
    expect(result.projectedGross).toBe(1_200_000);
    expect(result.totalGross).toBe(1_500_000);
  });

  it("does not start current salary before a future rough work year", () => {
    const result = projectLifetimeGrossIncome({
      asOf: "2026-01-01",
      retirementOn: "2040-01-01",
      periods: [],
      currentSalary: {
        startsOn: "2030-01-01",
        salaryAmount: 120_000,
        salaryCadence: "yearly",
      },
    });
    expect(result.historicalGross).toBe(0);
    expect(result.projectedGross).toBe(1_200_000);
  });

  it("splits an employment interval at today and clips it at retirement", () => {
    const result = projectLifetimeGrossIncome({
      asOf: "2026-07-01",
      retirementOn: "2027-01-01",
      periods: [{
        startsOn: "2026-01-01",
        endsOn: "2035-01-01",
        salaryAmount: 120_000,
        salaryCadence: "yearly",
      }],
    });
    expect(result.historicalGross).toBe(60_000);
    expect(result.projectedGross).toBe(60_000);
    expect(result.totalGross).toBe(120_000);
  });

  it("ignores invalid dates, reversed ranges, and non-positive salaries", () => {
    const result = projectLifetimeGrossIncome({
      asOf: "2026-01-01",
      retirementOn: "2030-01-01",
      periods: [
        { startsOn: "2026-02-30", endsOn: null, salaryAmount: 10_000, salaryCadence: "monthly" },
        { startsOn: "2029-01-01", endsOn: "2028-01-01", salaryAmount: 10_000, salaryCadence: "monthly" },
        { startsOn: "2026-01-01", endsOn: null, salaryAmount: 0, salaryCadence: "yearly" },
      ],
    });
    expect(result).toEqual({ historicalGross: 0, projectedGross: 0, totalGross: 0 });
  });

  it("keeps the lifetime total stable when today splits a short calendar month", () => {
    const input = {
      retirementOn: "2026-03-31",
      periods: [{
        startsOn: "2026-01-31",
        endsOn: "2026-03-31",
        salaryAmount: 10_000,
        salaryCadence: "monthly" as const,
      }],
    };
    const february = projectLifetimeGrossIncome({ ...input, asOf: "2026-02-15" });
    const march = projectLifetimeGrossIncome({ ...input, asOf: "2026-03-15" });
    expect(february.totalGross).toBe(20_000);
    expect(march.totalGross).toBe(february.totalGross);
    expect(february.historicalGross + february.projectedGross).toBe(february.totalGross);
    expect(march.historicalGross + march.projectedGross).toBe(march.totalGross);
  });

  it("keeps a continued current salary additive across the as-of boundary", () => {
    const calculate = (asOf: string) => projectLifetimeGrossIncome({
      asOf,
      retirementOn: "2026-03-31",
      periods: [{
        startsOn: "2026-01-31",
        endsOn: asOf,
        salaryAmount: 10_000,
        salaryCadence: "monthly",
      }],
      currentSalary: { salaryAmount: 10_000, salaryCadence: "monthly" },
    });
    const february = calculate("2026-02-15");
    const march = calculate("2026-03-15");
    expect(february.totalGross).toBeCloseTo(20_000, 8);
    expect(march.totalGross).toBeCloseTo(february.totalGross, 8);
  });

  it("rejects overlapping employment periods instead of double-paying them", () => {
    const result = projectLifetimeGrossIncome({
      asOf: "2026-01-01",
      retirementOn: "2030-01-01",
      periods: [
        { startsOn: "2020-01-01", endsOn: "2025-01-01", salaryAmount: 60_000, salaryCadence: "yearly" },
        { startsOn: "2024-01-01", endsOn: "2026-01-01", salaryAmount: 80_000, salaryCadence: "yearly" },
      ],
    });
    expect(result).toEqual({ historicalGross: 0, projectedGross: 0, totalGross: 0 });
  });

  it("keeps older profiles at the current salary when no decline is saved", () => {
    const input = {
      asOf: "2030-01-01",
      retirementOn: "2040-01-01",
      periods: [],
      currentSalary: { salaryAmount: 120_000, salaryCadence: "yearly" as const },
    };
    expect(projectLifetimeGrossIncome(input).projectedGross).toBe(1_200_000);
    expect(projectLifetimeGrossIncome({ ...input, futureIncomeDecline: null }).projectedGross)
      .toBe(1_200_000);
    expect(projectLifetimeGrossIncome({
      ...input,
      futureIncomeDecline: { startsOn: "2035-06-15", retirementRatio: 1 },
    }).projectedGross).toBeCloseTo(1_200_000, 8);
  });

  it("declines linearly from the chosen age to the retirement ratio", () => {
    const result = projectLifetimeGrossIncome({
      asOf: "2030-01-01",
      retirementOn: "2040-01-01",
      periods: [],
      currentSalary: { salaryAmount: 120_000, salaryCadence: "yearly" },
      futureIncomeDecline: { startsOn: "2035-01-01", retirementRatio: 0.6 },
    });
    // Five years at 100%, then five years averaging 80%.
    expect(Math.abs(result.projectedGross - 1_080_000)).toBeLessThan(100);
  });

  it("anchors an already-passed decline age at today's current income", () => {
    const result = projectLifetimeGrossIncome({
      asOf: "2035-01-01",
      retirementOn: "2040-01-01",
      periods: [{
        startsOn: "2030-01-01",
        endsOn: "2035-01-01",
        salaryAmount: 120_000,
        salaryCadence: "yearly",
      }],
      currentSalary: { salaryAmount: 120_000, salaryCadence: "yearly" },
      futureIncomeDecline: { startsOn: "2032-01-01", retirementRatio: 0.6 },
    });
    expect(result.historicalGross).toBe(600_000);
    expect(Math.abs(result.projectedGross - 480_000)).toBeLessThan(100);
  });

  it("keeps gaps and history untouched and reaches zero at retirement", () => {
    const result = projectLifetimeGrossIncome({
      asOf: "2030-01-01",
      retirementOn: "2040-01-01",
      periods: [{
        startsOn: "2020-01-01",
        endsOn: "2025-01-01",
        salaryAmount: 60_000,
        salaryCadence: "yearly",
      }],
      currentSalary: {
        startsOn: "2035-01-01",
        salaryAmount: 120_000,
        salaryCadence: "yearly",
      },
      futureIncomeDecline: { startsOn: "2030-01-01", retirementRatio: 0 },
    });
    expect(result.historicalGross).toBe(300_000);
    expect(Math.abs(result.projectedGross - 300_000)).toBeLessThan(200);
    expect(Math.abs(result.totalGross - 600_000)).toBeLessThan(200);

    const retired = projectLifetimeGrossIncome({
      asOf: "2040-01-01",
      retirementOn: "2040-01-01",
      periods: [],
      currentSalary: { salaryAmount: 120_000, salaryCadence: "yearly" },
      futureIncomeDecline: { startsOn: "2030-01-01", retirementRatio: 0 },
    });
    expect(retired.projectedGross).toBe(0);
  });

  it("uses the same curve for equivalent monthly and yearly salaries", () => {
    const calculate = (salaryAmount: number, salaryCadence: "monthly" | "yearly") =>
      projectLifetimeGrossIncome({
        asOf: "2030-04-15",
        retirementOn: "2040-07-01",
        periods: [],
        currentSalary: { salaryAmount, salaryCadence },
        futureIncomeDecline: { startsOn: "2032-07-01", retirementRatio: 0.55 },
      }).projectedGross;
    expect(calculate(10_000, "monthly")).toBeCloseTo(calculate(120_000, "yearly"), 8);
  });

  it("updates the forecast when the saved decline choices change", () => {
    const calculate = (startsOn: string, retirementRatio: number) =>
      projectLifetimeGrossIncome({
        asOf: "2030-01-01",
        retirementOn: "2040-01-01",
        periods: [],
        currentSalary: { salaryAmount: 120_000, salaryCadence: "yearly" },
        futureIncomeDecline: { startsOn, retirementRatio },
      }).projectedGross;
    expect(calculate("2037-01-01", 0.8)).toBeGreaterThan(calculate("2035-01-01", 0.6));
  });
});

describe("records actual and forecast", () => {
  it("keeps recorded work separate and never forecasts the same day twice", () => {
    const hour = 3_600_000;
    const result = summarizeRecordsActualAndForecast({
      dailySalary: 800,
      asOfMs: 20 * hour,
      days: [
        {
          actualKind: "observed",
          resolvedSegments: [{ startAtMs: 9 * hour, endAtMs: 17 * hour }],
          plannedSegments: [{ startAtMs: 9 * hour, endAtMs: 17 * hour }],
          overtimeSegments: [{ startAtMs: 17 * hour, endAtMs: 19 * hour }],
          observations: [
            { kind: "started", occurredAtMs: 9 * hour },
            { kind: "stopped", occurredAtMs: 17 * hour },
          ],
          isActiveAnchor: false,
        },
        {
          actualKind: null,
          resolvedSegments: [{ startAtMs: 33 * hour, endAtMs: 41 * hour }],
          plannedSegments: [{ startAtMs: 33 * hour, endAtMs: 41 * hour }],
          overtimeSegments: [],
          observations: [],
          isActiveAnchor: false,
        },
      ],
    });
    expect(result.actual).toEqual({ days: 1, hours: 10, earnings: 1_000 });
    expect(result.forecast).toEqual({ days: 1, hours: 8, earnings: 800 });
    expect(result.total).toEqual({ days: 2, hours: 18, earnings: 1_800 });
  });

  it("uses zero for invalid durations and preserves a missing salary", () => {
    const result = summarizeRecordsActualAndForecast({
      dailySalary: null,
      asOfMs: Number.NaN,
      days: [
        {
          actualKind: "observed",
          resolvedSegments: [],
          plannedSegments: [],
          overtimeSegments: [{ startAtMs: Number.NaN, endAtMs: -1 }],
          observations: [{ kind: "started", occurredAtMs: Number.NaN }],
          isActiveAnchor: false,
        },
        {
          actualKind: null,
          resolvedSegments: [{ startAtMs: 99, endAtMs: Number.NaN }],
          plannedSegments: [],
          overtimeSegments: [],
          observations: [],
          isActiveAnchor: false,
        },
      ],
    });
    expect(result.actual).toEqual({ days: 0, hours: 0, earnings: null });
    expect(result.forecast).toEqual({ days: 0, hours: 0, earnings: null });
    expect(result.total).toEqual({ days: 0, hours: 0, earnings: null });
  });

  it("treats an omitted native optional actual kind as forecast", () => {
    const result = summarizeRecordsActualAndForecast({
      dailySalary: 800,
      asOfMs: 0,
      days: [{
        resolvedSegments: [{ startAtMs: 1, endAtMs: 8 * 3_600_000 + 1 }],
        plannedSegments: [{ startAtMs: 1, endAtMs: 8 * 3_600_000 + 1 }],
        overtimeSegments: [],
        observations: [],
        isActiveAnchor: false,
      }],
    });
    expect(result.forecast).toEqual({ days: 1, hours: 8, earnings: 800 });
  });

  it("uses observed start and stop times instead of presenting the plan as actual", () => {
    const hour = 3_600_000;
    const result = summarizeRecordsActualAndForecast({
      dailySalary: 900,
      asOfMs: 20 * hour,
      days: [{
        actualKind: "observed",
        resolvedSegments: [{ startAtMs: 9 * hour, endAtMs: 18 * hour }],
        plannedSegments: [{ startAtMs: 9 * hour, endAtMs: 18 * hour }],
        overtimeSegments: [],
        observations: [
          { kind: "started", occurredAtMs: 10 * hour },
          { kind: "stopped", occurredAtMs: 16 * hour },
        ],
        isActiveAnchor: false,
      }],
    });
    expect(result.actual).toEqual({ days: 1, hours: 6, earnings: 600 });
    expect(result.forecast.days).toBe(0);
  });

  it("excludes the effective schedule lunch gap from observed actual time", () => {
    const hour = 3_600_000;
    const result = summarizeRecordsActualAndForecast({
      dailySalary: 700,
      asOfMs: 20 * hour,
      days: [{
        actualKind: "observed",
        resolvedSegments: [
          { startAtMs: 9 * hour, endAtMs: 12 * hour },
          { startAtMs: 13 * hour, endAtMs: 17 * hour },
        ],
        plannedSegments: [
          { startAtMs: 9 * hour, endAtMs: 12 * hour },
          { startAtMs: 13 * hour, endAtMs: 17 * hour },
        ],
        overtimeSegments: [],
        observations: [
          { kind: "started", occurredAtMs: 10 * hour },
          { kind: "stopped", occurredAtMs: 16 * hour },
        ],
        isActiveAnchor: false,
      }],
    });
    expect(result.actual).toEqual({ days: 1, hours: 5, earnings: 500 });
  });

  it("uses the original planned duration as the corrected pay denominator", () => {
    const hour = 3_600_000;
    const result = summarizeRecordsActualAndForecast({
      dailySalary: 800,
      asOfMs: 20 * hour,
      days: [{
        actualKind: "corrected",
        resolvedSegments: [{ startAtMs: 9 * hour, endAtMs: 13 * hour }],
        plannedSegments: [{ startAtMs: 9 * hour, endAtMs: 17 * hour }],
        overtimeSegments: [],
        observations: [],
        isActiveAnchor: false,
      }],
    });
    expect(result.actual).toEqual({ days: 1, hours: 4, earnings: 400 });
  });

  it("unions repeated overtime declarations instead of summing their overlap", () => {
    const hour = 3_600_000;
    const result = summarizeRecordsActualAndForecast({
      dailySalary: 800,
      asOfMs: 22 * hour,
      days: [{
        actualKind: "corrected",
        resolvedSegments: [{ startAtMs: 9 * hour, endAtMs: 18 * hour }],
        plannedSegments: [{ startAtMs: 9 * hour, endAtMs: 18 * hour }],
        overtimeSegments: [
          { startAtMs: 18 * hour, endAtMs: 20 * hour },
          { startAtMs: 18 * hour, endAtMs: 21 * hour },
        ],
        observations: [],
        isActiveAnchor: false,
      }],
    });
    expect(result.actual.hours).toBe(12);
    expect(result.actual.earnings).toBeCloseTo(800 * 12 / 9, 8);
  });

  it("does not count the unelapsed end of a current overtime declaration", () => {
    const hour = 3_600_000;
    const result = summarizeRecordsActualAndForecast({
      dailySalary: 800,
      asOfMs: 19 * hour,
      days: [{
        actualKind: "observed",
        resolvedSegments: [{ startAtMs: 9 * hour, endAtMs: 18 * hour }],
        plannedSegments: [{ startAtMs: 9 * hour, endAtMs: 18 * hour }],
        overtimeSegments: [{ startAtMs: 18 * hour, endAtMs: 21 * hour }],
        observations: [{ kind: "started", occurredAtMs: 9 * hour }],
        isActiveAnchor: true,
      }],
    });
    expect(result.actual.hours).toBe(10);
    expect(result.actual.earnings).toBeCloseTo(800 * 10 / 9, 8);
    expect(result.forecast.days).toBe(0);
    expect(result.forecast.hours).toBe(2);
    expect(result.forecast.earnings).toBeCloseTo(800 * 2 / 9, 8);
    expect(result.total.days).toBe(1);
    expect(result.total.hours).toBe(12);
  });

  it("does not carry an old unmatched start into the month being viewed", () => {
    const hour = 3_600_000;
    const monthLater = 35 * 24 * hour;
    const result = summarizeRecordsActualAndForecast({
      dailySalary: 800,
      asOfMs: monthLater,
      days: [{
        actualKind: "observed",
        resolvedSegments: [{ startAtMs: 9 * hour, endAtMs: 17 * hour }],
        plannedSegments: [{ startAtMs: 9 * hour, endAtMs: 17 * hour }],
        overtimeSegments: [],
        observations: [{ kind: "started", occurredAtMs: 9 * hour }],
        isActiveAnchor: false,
      }],
    });
    expect(result.actual).toEqual({ days: 0, hours: 0, earnings: 0 });
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

describe("Records calendar-month salary", () => {
  const monthlyRules = {
    salaryAmount: "10000", salaryType: "monthly" as const,
    workdays: MON_TO_FRI, annualBonusMonths: 0, timeZoneIdentifier: "UTC",
  };
  function monthDays(year: number, month: number) {
    return Array.from({ length: new Date(Date.UTC(year, month, 0)).getUTCDate() }, (_, index) => {
      const start = Date.UTC(year, month - 1, index + 1, 9);
      if (!MON_TO_FRI.includes(new Date(start).getUTCDay())) return null;
      const segments = [{ startAtMs: start, endAtMs: start + 8 * 3_600_000 }];
      return {
        dayKey: new Date(start).toISOString().slice(0, 10),
        resolvedSegments: segments, plannedSegments: segments,
        overtimeSegments: [], observations: [], isActiveAnchor: false,
      };
    }).filter(value => value !== null);
  }
  it.each([2, 4, 7, 9])("pays 10000 for full attendance in month %i, independent of average daily pay", month => {
    const result = summarizeRecordsActualAndForecast({
      days: monthDays(2026, month), dailySalary: 10000 / 22,
      asOfMs: Date.UTC(2026, 0, 1), salaryRules: monthlyRules,
    });
    expect(result.forecast.earnings).toBeCloseTo(10000, 8);
  });
  it("adds actual and remaining forecast to one full monthly salary", () => {
    const days = monthDays(2026, 9);
    const split = 4;
    const result = summarizeRecordsActualAndForecast({
      days: days.map((day, index) => index < split ? { ...day, actualKind: "corrected" as const } : day),
      dailySalary: 10000 / 22, asOfMs: Date.UTC(2026, 8, 5), salaryRules: monthlyRules,
    });
    expect(result.actual.earnings).toBeCloseTo(10000 * split / days.length, 8);
    expect(result.total.earnings).toBeCloseTo(10000, 8);
  });
  it("allocates a cross-month week using each month's own scheduled days", () => {
    const feb = monthDays(2026, 2), mar = monthDays(2026, 3);
    const result = summarizeRecordsActualAndForecast({
      days: [...feb.slice(-2), ...mar.slice(0, 3)], dailySalary: 10000 / 22,
      asOfMs: Date.UTC(2026, 0, 1), salaryRules: monthlyRules,
    });
    expect(result.total.earnings).toBeCloseTo(10000 * (2 / feb.length + 3 / mar.length), 8);
  });
  it("pays twelve full monthly salaries over a full year", () => {
    const result = summarizeRecordsActualAndForecast({
      days: Array.from({ length: 12 }, (_, index) => monthDays(2026, index + 1)).flat(),
      dailySalary: 10000 / 22, asOfMs: Date.UTC(2025, 0, 1), salaryRules: monthlyRules,
    });
    expect(result.total.earnings).toBeCloseTo(120000, 7);
  });
  it("keeps daily wages proportional to attended days", () => {
    const days = monthDays(2026, 2);
    const result = summarizeRecordsActualAndForecast({
      days, dailySalary: 500, asOfMs: Date.UTC(2026, 0, 1),
      salaryRules: { ...monthlyRules, salaryType: "daily", salaryAmount: "500" },
    });
    expect(result.total.earnings).toBe(days.length * 500);
  });
});
