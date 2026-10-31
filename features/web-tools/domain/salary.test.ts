import { describe, expect, it } from "vitest";
import {
  calculateAnnualized,
  calculateReferenceSalary,
  calculateWorkedTime,
  CALCULATION_VERSION,
  parseLocaleNumber,
  roundForDisplay,
  type CalculationResult,
} from "./salary";

function success<T>(result: CalculationResult<T>): T {
  if (!result.ok) throw new Error(JSON.stringify(result.error));
  return result.value;
}

describe("independent Web annual salary arithmetic", () => {
  it("annualizes paid hours without rounding monthly income early", () => {
    const value = success(calculateAnnualized({ income: { kind: "hourly", amount: 25, paidHoursPerWeek: 40, paidWeeksPerYear: 52 } }));
    expect(value.annualIncome).toBe(52_000);
    expect(roundForDisplay(value.averageMonthlyIncome)).toBe(4_333.33);
    expect(value.averageMonthlyIncome * 12).toBeCloseTo(52_000, 8);
    expect(value.payPeriods.biweekly).toBe(2_000);
    expect(roundForDisplay(value.payPeriods.semimonthly)).toBe(2_166.67);
    expect(value.metadata).toMatchObject({ calculationVersion: CALCULATION_VERSION, purpose: "annualized", period: "reference-year" });
    expect(value.metadata.roundingPolicy).toContain("only for display");
  });

  it("counts only paid weeks and keeps salary months separate from pay frequency", () => {
    expect(success(calculateAnnualized({ income: { kind: "hourly", amount: 25, paidHoursPerWeek: 40, paidWeeksPerYear: 50 } })).annualIncome).toBe(50_000);
    const value = success(calculateAnnualized({ income: { kind: "monthly", amount: 10_000, monthsPerYear: 13, annualBonus: 5_000 } }));
    expect(value.annualIncome).toBe(135_000);
    expect(value.baseMonthlySalary).toBe(10_000);
    expect(value.averageMonthlyIncome).toBe(11_250);
    expect(value.payPeriods.monthly).toBe(11_250);
    expect(value.payPeriods.biweekly).toBeCloseTo(135_000 / 26);
  });

  it("cannot add the same bonus again when annual input includes all compensation", () => {
    const income = { kind: "annual" as const, amount: 135_000, includesBonus: true as const, annualBonus: 5_000 };
    const value = success(calculateAnnualized({ income }));
    expect(value.annualIncome).toBe(135_000);
    expect(value.metadata.assumptions.annualBonusAdded).toBe(0);
    expect(success(calculateAnnualized({ income: { kind: "annual", amount: 130_000, includesBonus: false, annualBonus: 5_000 } })).annualIncome).toBe(135_000);
  });

  it("uses the selected paid-hour denominator while fixed annual salary stays fixed", () => {
    const fullTime = success(calculateAnnualized({ income: { kind: "annual", amount: 52_000, includesBonus: true }, paidHoursPerWeek: 40, paidWeeksPerYear: 52, workdaysPerWeek: 5 }));
    const fewerHours = success(calculateAnnualized({ income: { kind: "annual", amount: 52_000, includesBonus: true }, paidHoursPerWeek: 35, paidWeeksPerYear: 52, workdaysPerWeek: 5 }));
    expect(fullTime.hourlyRate).toBe(25);
    expect(fullTime.dailyRate).toBe(200);
    expect(fewerHours.annualIncome).toBe(fullTime.annualIncome);
    expect(fewerHours.hourlyRate).toBeGreaterThan(fullTime.hourlyRate);
  });

  it.each([
    ["amount", { kind: "monthly" as const, amount: -1 }],
    ["amount", { kind: "annual" as const, amount: Infinity, includesBonus: true as const }],
    ["annualBonus", { kind: "monthly" as const, amount: 10, annualBonus: -1 }],
    ["monthsPerYear", { kind: "monthly" as const, amount: 10, monthsPerYear: 25 }],
  ])("rejects invalid %s rather than producing a misleading number", (field, income) => {
    expect(calculateAnnualized({ income })).toMatchObject({ ok: false, error: { field } });
  });

  it("distinguishes a valid zero salary from an unusable zero denominator", () => {
    expect(success(calculateAnnualized({ income: { kind: "monthly", amount: 0 } })).hourlyRate).toBe(0);
    for (const input of [{ paidHoursPerWeek: 0 }, { paidWeeksPerYear: 0 }, { workdaysPerWeek: 0 }]) {
      expect(calculateAnnualized({ income: { kind: "monthly", amount: 10_000 }, ...input })).toMatchObject({ ok: false, error: { code: "zero-denominator" } });
    }
  });
});

describe("separate worked-time and reviewed jurisdiction reference purposes", () => {
  const basis = {
    basisId: "cn-monthly-paid-days-2025",
    appliesTo: "Monthly salary conversion reference",
    effectiveFrom: "2025-01-01",
    reviewedAt: "2026-10-31",
    sourceUrls: ["https://example.gov.cn/source"],
  };

  it("calculates 21.75 paid days and eight hours without replacing actual attendance", () => {
    const reference = success(calculateReferenceSalary({ monthlySalary: 21_750, paidDaysPerMonth: 21.75, hoursPerDay: 8, basis }));
    expect(reference.dailyRate).toBe(1_000);
    expect(reference.hourlyRate).toBe(125);
    expect(reference.metadata).toMatchObject({ ...basis, calculationVersion: CALCULATION_VERSION, purpose: "jurisdiction-reference" });
    const actual = success(calculateWorkedTime({ income: 21_750, workdays: 22, hoursPerDay: 8, period: "2026-10" }));
    expect(actual.metadata.purpose).toBe("worked-time");
    expect(actual.dailyRate).not.toBe(reference.dailyRate);
    expect(actual.totalHours).toBe(176);
  });

  it("keeps reference and actual workload examples numerically distinct", () => {
    const reference = success(calculateReferenceSalary({ monthlySalary: 36_000, paidDaysPerMonth: 30, hoursPerDay: 8, basis }));
    const actual = success(calculateWorkedTime({ income: 36_000, workdays: 22, hoursPerDay: 8 }));
    expect(reference.dailyRate).toBe(1_200);
    expect(reference.hourlyRate).toBe(150);
    expect(roundForDisplay(actual.dailyRate)).toBe(1_636.36);
    expect(roundForDisplay(actual.hourlyRate)).toBe(204.55);
  });

  it("requires a usable denominator and complete reviewed-source metadata", () => {
    expect(calculateWorkedTime({ income: 100, workdays: 0, hoursPerDay: 8 })).toEqual({ ok: false, error: { code: "zero-denominator", field: "workdays" } });
    expect(calculateWorkedTime({ income: 100, workdays: 22, hoursPerDay: 0 })).toMatchObject({ ok: false, error: { code: "zero-denominator" } });
    expect(calculateReferenceSalary({ monthlySalary: 100, paidDaysPerMonth: 0, hoursPerDay: 8, basis })).toMatchObject({ ok: false, error: { field: "paidDaysPerMonth" } });
    expect(calculateReferenceSalary({ monthlySalary: 100, paidDaysPerMonth: 21.75, hoursPerDay: 8, basis: { ...basis, sourceUrls: [] } })).toMatchObject({ ok: false, error: { code: "invalid-basis" } });
    expect(calculateReferenceSalary({ monthlySalary: 100, paidDaysPerMonth: 21.75, hoursPerDay: 8, basis: { ...basis, reviewedAt: "2026-02-30" } })).toMatchObject({ ok: false, error: { code: "invalid-basis" } });
    expect(calculateReferenceSalary({ monthlySalary: 100, paidDaysPerMonth: 21.75, hoursPerDay: 8, basis: { ...basis, sourceUrls: ["https://"] } })).toMatchObject({ ok: false, error: { code: "invalid-basis" } });
  });

  it("retains an unknown effective date without inventing one from publication", () => {
    const result = success(calculateReferenceSalary({ monthlySalary: 21_750, paidDaysPerMonth: 21.75, hoursPerDay: 8, basis: { ...basis, effectiveFrom: null } }));
    expect(result.hourlyRate).toBe(125);
    expect(result.metadata.effectiveFrom).toBeNull();
    expect(result.metadata.reviewedAt).toBe("2026-10-31");
  });
});

describe("display rounding", () => {
  it("uses half-away-from-zero for decimal ties and currency-specific precision", () => {
    expect(roundForDisplay(1.005)).toBe(1.01);
    expect(roundForDisplay(-1.005)).toBe(-1.01);
    expect(roundForDisplay(1_500.5, 0)).toBe(1_501);
    expect(roundForDisplay(1.2345, 3)).toBe(1.235);
    expect(() => roundForDisplay(Infinity)).toThrow(RangeError);
  });
});

describe("locale number input", () => {
  it.each([
    ["1,500", "en-US", 1_500],
    ["1,500.25", "en-US", 1_500.25],
    ["1.500,25", "de-DE", 1_500.25],
    ["1,500", "de-DE", 1.5],
    ["1\u202f500,25", "fr-FR", 1_500.25],
    ["1,23,456.75", "hi-IN", 123_456.75],
    ["१,२३,४५६.७५", "hi-IN", 123_456.75],
    ["๑,๕๐๐.๒๕", "th-TH", 1_500.25],
    ["١٬٥٠٠٫٢٥", "ar-EG", 1_500.25],
    ["１，５００．２５", "zh-CN", 1_500.25],
    ["0", "en-US", 0],
    [".5", "en-US", 0.5],
  ])("reads %s using %s conventions", (input, locale, expected) => {
    expect(parseLocaleNumber(input, locale)).toEqual({ ok: true, value: expected });
  });

  it.each(["1,50", "1,500,00", "1.500,25", "1e6", "NaN", "Infinity", "1 500", "$1,500", "1,500."])("rejects malformed or ambiguous English input %s", (input) => {
    expect(parseLocaleNumber(input, "en-US")).toMatchObject({ ok: false, error: { code: "invalid-number" } });
  });

  it("reports empty input separately from zero", () => {
    expect(parseLocaleNumber("  ", "zh-CN")).toEqual({ ok: false, error: { code: "required", field: "number" } });
    expect(parseLocaleNumber("0", "zh-CN")).toEqual({ ok: true, value: 0 });
  });
});
