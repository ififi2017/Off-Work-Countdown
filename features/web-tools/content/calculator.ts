import type { ToolPage } from "../catalog/pages";
import { calculateAnnualized, calculateReferenceSalary, calculateWorkedTime, parseLocaleNumber, type CalculationMetadata, type CalculationPurpose } from "../domain/salary";
import { cnPayReference } from "../markets/cn";

export interface CalculatorState {
  purpose: CalculationPurpose;
  incomeKind: "monthly" | "hourly" | "annual";
  amount: string;
  hours: string;
  weeks: string;
  days: string;
  dailyHours: string;
  months: string;
  bonus: string;
  includesBonus: boolean;
  currency: "CNY" | "USD";
}
export function initialCalculatorState(page: ToolPage): CalculatorState {
  const cn = page.market === "cn";
  return {
    purpose: cn ? (page.tool === "monthly-to-hourly" ? "worked-time" : "jurisdiction-reference") : "annualized",
    incomeKind: cn ? "monthly" : (page.tool === "hourly-to-annual" || page.tool === "overview" ? "hourly" : "annual"),
    amount: cn ? "10000" : (page.tool === "hourly-to-annual" || page.tool === "overview" ? "25" : "52000"),
    hours: "40", weeks: "52", days: "22", dailyHours: "8", months: "12", bonus: "0", includesBonus: true,
    currency: cn ? "CNY" : "USD",
  };
}
export interface SalaryRow { label: string; value: number; }
export type DisplayCalculation = { ok: true; rows: SalaryRow[]; metadata: CalculationMetadata } | { ok: false; message: string };
export function calculateDisplay(state: CalculatorState, lang: string): DisplayCalculation {
  const zh = lang === "zh-CN";
  const fields: (keyof CalculatorState)[] = ["amount"];
  if (state.purpose === "worked-time") fields.push("days", "dailyHours");
  if (state.purpose === "annualized") {
    fields.push("hours", "weeks");
    if (state.incomeKind === "monthly") fields.push("months");
    if (state.incomeKind !== "annual" || !state.includesBonus) fields.push("bonus");
  }
  const values: Record<string, number> = {};
  for (const field of fields) {
    const parsed = parseLocaleNumber(String(state[field]), lang);
    if (!parsed.ok) return { ok: false, message: zh ? "请填写完整的数字；千位分隔可写为1,500，小数可写为1.5。" : "Enter a complete number. Use 1,500 for thousands and 1.5 for decimals." };
    values[field] = parsed.value;
  }
  const fail = { ok: false as const, message: zh ? "请检查输入范围：金额不能为负，工作量必须大于0；每日不超过24小时，每周不超过168小时，每年不超过53周，薪资月数为1至24。" : "Check the ranges: pay cannot be negative, hours and weeks must be above zero, weekly hours at most 168, paid weeks at most 53, and salary months between 1 and 24." };
  if (state.purpose === "worked-time" && values.days > 31) return { ok: false, message: "同月工作天数不能超过31天。请填写与这笔月收入对应的实际或预计工作天数。" };
  if (state.purpose === "annualized") {
    const common = { paidHoursPerWeek: values.hours, paidWeeksPerYear: values.weeks };
    const income = state.incomeKind === "hourly" ? { kind: "hourly" as const, amount: values.amount, ...common, annualBonus: values.bonus }
      : state.incomeKind === "monthly" ? { kind: "monthly" as const, amount: values.amount, monthsPerYear: values.months, annualBonus: values.bonus }
      : state.includesBonus ? { kind: "annual" as const, amount: values.amount, includesBonus: true as const }
      : { kind: "annual" as const, amount: values.amount, includesBonus: false as const, annualBonus: values.bonus };
    const result = calculateAnnualized({ income, ...common });
    if (!result.ok) return fail;
    const v = result.value;
    return { ok: true, metadata: v.metadata, rows: [
      { label: zh ? "全年计入税前收入" : "Annual gross income", value: v.annualIncome },
      { label: zh ? "月均收入" : "Average monthly income", value: v.averageMonthlyIncome },
      ...(v.baseMonthlySalary === null ? [] : [{ label: zh ? "基础月薪" : "Base monthly salary", value: v.baseMonthlySalary }]),
      { label: zh ? "年化小时收入" : "Hourly equivalent", value: v.hourlyRate },
      { label: zh ? "每周参考额（52次）" : "Weekly reference (52 payments)", value: v.payPeriods.weekly },
      { label: zh ? "每两周参考额（26次）" : "Biweekly reference (26 payments)", value: v.payPeriods.biweekly },
      { label: zh ? "每半月参考额（24次）" : "Semimonthly reference (24 payments)", value: v.payPeriods.semimonthly },
    ] };
  }
  const result = state.purpose === "jurisdiction-reference" ? calculateReferenceSalary({ monthlySalary: values.amount, paidDaysPerMonth: cnPayReference.payDaysPerMonth, hoursPerDay: cnPayReference.hoursPerDay, basis: cnPayReference })
    : calculateWorkedTime({ income: values.amount, workdays: values.days, hoursPerDay: values.dailyHours, period: "selected-month" });
  if (!result.ok) return fail;
  return { ok: true, metadata: result.value.metadata, rows: [
    { label: state.purpose === "jurisdiction-reference" ? "日工资折算参考" : "每实际工作日收入", value: result.value.dailyRate },
    { label: state.purpose === "jurisdiction-reference" ? "小时工资折算参考" : "每实际工作小时收入", value: result.value.hourlyRate },
  ] };
}
export function formatMoney(value: number, lang: string, currency: string): string {
  return new Intl.NumberFormat(lang, { style: "currency", currency, minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value);
}
