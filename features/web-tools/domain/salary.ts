/** Independent, local-only Web salary arithmetic. No native salary rules or persistence. */
export const CALCULATION_VERSION = "web-salary-1.0.0";

export const PAY_FREQUENCIES = {
  weekly: 52,
  biweekly: 26,
  fortnightly: 26,
  semimonthly: 24,
  monthly: 12,
} as const;

export type PayFrequency = keyof typeof PAY_FREQUENCIES;
export type CalculationPurpose = "annualized" | "worked-time" | "jurisdiction-reference";
export type ValidationCode = "required" | "invalid-number" | "out-of-range" | "zero-denominator" | "invalid-basis";
export type CalculationResult<T> = { ok: true; value: T } | {
  ok: false;
  error: { code: ValidationCode; field: string };
};

export interface ReferenceBasis {
  basisId: string;
  appliesTo: string;
  effectiveFrom: string | null;
  reviewedAt: string;
  sourceUrls: readonly string[];
}

export interface CalculationMetadata {
  calculationVersion: string;
  purpose: CalculationPurpose;
  period: string;
  assumptions: Record<string, string | number | boolean>;
  roundingPolicy: string;
  basisId?: string;
  appliesTo?: string;
  effectiveFrom?: string | null;
  reviewedAt?: string;
  sourceUrls?: readonly string[];
}

export type IncomeInput =
  | { kind: "monthly"; amount: number; monthsPerYear?: number; annualBonus?: number }
  | { kind: "hourly"; amount: number; paidHoursPerWeek: number; paidWeeksPerYear: number; annualBonus?: number }
  // A total that already includes bonuses has no second bonus field by design.
  | { kind: "annual"; amount: number; includesBonus: true }
  | { kind: "annual"; amount: number; includesBonus: false; annualBonus?: number };

export interface AnnualizedInput {
  income: IncomeInput;
  paidHoursPerWeek?: number;
  paidWeeksPerYear?: number;
  workdaysPerWeek?: number;
}

export interface AnnualizedSalary {
  annualIncome: number;
  averageMonthlyIncome: number;
  baseMonthlySalary: number | null;
  hourlyRate: number;
  dailyRate: number | null;
  annualPaidHours: number;
  payPeriods: Record<PayFrequency, number>;
  metadata: CalculationMetadata;
}

function failure(code: ValidationCode, field: string): CalculationResult<never> {
  return { ok: false, error: { code, field } };
}

function validateNumber(value: number, field: string, min = 0, max = Number.MAX_SAFE_INTEGER): CalculationResult<never> | null {
  if (!Number.isFinite(value)) return failure("invalid-number", field);
  if (value < min || value > max) return failure("out-of-range", field);
  return null;
}

function metadata(purpose: CalculationPurpose, period: string, assumptions: CalculationMetadata["assumptions"]): CalculationMetadata {
  return {
    calculationVersion: CALCULATION_VERSION,
    purpose,
    period,
    assumptions,
    roundingPolicy: "Full precision through calculation; round only for display, half away from zero, using the selected currency's minor units.",
  };
}

/** 52/26/24 are annual reference frequencies, not a dated payroll calendar. */
export function calculateAnnualized(input: AnnualizedInput): CalculationResult<AnnualizedSalary> {
  const { income } = input;
  const amountError = validateNumber(income.amount, "amount");
  if (amountError) return amountError;
  const paidHoursPerWeek = income.kind === "hourly" ? income.paidHoursPerWeek : (input.paidHoursPerWeek ?? 40);
  const paidWeeksPerYear = income.kind === "hourly" ? income.paidWeeksPerYear : (input.paidWeeksPerYear ?? 52);
  const hoursError = validateNumber(paidHoursPerWeek, "paidHoursPerWeek", 0, 168);
  const weeksError = validateNumber(paidWeeksPerYear, "paidWeeksPerYear", 0, 53);
  if (hoursError) return hoursError;
  if (weeksError) return weeksError;
  if (paidHoursPerWeek === 0) return failure("zero-denominator", "paidHoursPerWeek");
  if (paidWeeksPerYear === 0) return failure("zero-denominator", "paidWeeksPerYear");
  const bonus = income.kind === "annual" && income.includesBonus ? 0 : (income.annualBonus ?? 0);
  const bonusError = validateNumber(bonus, "annualBonus");
  if (bonusError) return bonusError;
  const months = income.kind === "monthly" ? (income.monthsPerYear ?? 12) : 12;
  const monthsError = validateNumber(months, "monthsPerYear", 1, 24);
  if (monthsError) return monthsError;
  if (input.workdaysPerWeek !== undefined) {
    const daysError = validateNumber(input.workdaysPerWeek, "workdaysPerWeek", 0, 7);
    if (daysError) return daysError;
    if (input.workdaysPerWeek === 0) return failure("zero-denominator", "workdaysPerWeek");
  }

  const annualPaidHours = paidHoursPerWeek * paidWeeksPerYear;
  const annualIncome = income.kind === "monthly" ? income.amount * months + bonus
    : income.kind === "hourly" ? income.amount * annualPaidHours + bonus : income.amount + bonus;
  const overflowError = validateNumber(annualIncome, "annualIncome");
  if (overflowError) return overflowError;
  const hourlyRate = annualIncome / annualPaidHours;
  const dailyRate = input.workdaysPerWeek === undefined ? null : annualIncome / (input.workdaysPerWeek * paidWeeksPerYear);
  if (!Number.isFinite(hourlyRate) || (dailyRate !== null && !Number.isFinite(dailyRate))) return failure("out-of-range", "paidHoursPerWeek");
  const payPeriods = Object.fromEntries(Object.entries(PAY_FREQUENCIES).map(([key, count]) => [key, annualIncome / count])) as Record<PayFrequency, number>;
  return {
    ok: true,
    value: {
      annualIncome,
      averageMonthlyIncome: annualIncome / 12,
      baseMonthlySalary: income.kind === "monthly" ? income.amount : null,
      hourlyRate,
      dailyRate,
      annualPaidHours,
      payPeriods,
      metadata: metadata("annualized", "reference-year", {
        incomeKind: income.kind, paidHoursPerWeek, paidWeeksPerYear,
        monthsPerYear: months, annualBonusAdded: bonus,
        annualAmountIncludesBonus: income.kind === "annual" && income.includesBonus,
        ...(input.workdaysPerWeek === undefined ? {} : { workdaysPerWeek: input.workdaysPerWeek }),
        payrollCalendar: "52 weekly / 26 biweekly or fortnightly / 24 semimonthly / 12 monthly reference payments",
        grossIncome: true,
      }),
    },
  };
}

export interface WorkedTimeInput {
  /** Gross income for exactly the same period as workdays and hoursPerDay. */
  income: number;
  workdays: number;
  /** Actual or estimated labor hours per workday, excluding all breaks. */
  hoursPerDay: number;
  period?: string;
}

export interface WorkedTimeSalary {
  dailyRate: number;
  hourlyRate: number;
  totalHours: number;
  metadata: CalculationMetadata;
}

export function calculateWorkedTime(input: WorkedTimeInput): CalculationResult<WorkedTimeSalary> {
  for (const [field, value, max] of [
    ["income", input.income, Number.MAX_SAFE_INTEGER],
    ["workdays", input.workdays, Number.MAX_SAFE_INTEGER],
    ["hoursPerDay", input.hoursPerDay, 24],
  ] as const) {
    const error = validateNumber(value, field, 0, max);
    if (error) return error;
    if (field !== "income" && value === 0) return failure("zero-denominator", field);
  }
  const totalHours = input.workdays * input.hoursPerDay;
  const dailyRate = input.income / input.workdays;
  const hourlyRate = input.income / totalHours;
  if (![totalHours, dailyRate, hourlyRate].every(Number.isFinite)) return failure("out-of-range", "workdays");
  return { ok: true, value: { dailyRate, hourlyRate, totalHours, metadata: metadata("worked-time", input.period ?? "selected-period", {
    workdays: input.workdays, hoursPerDay: input.hoursPerDay, samePeriodIncomeAndHours: true, breaksExcludedFromLaborHours: true, grossIncome: true,
  }) } };
}

export interface ReferenceSalaryInput {
  monthlySalary: number;
  paidDaysPerMonth: number;
  hoursPerDay: number;
  basis: ReferenceBasis;
}

/** The market module supplies reviewed divisors and source metadata; this function supplies arithmetic only. */
export function calculateReferenceSalary(input: ReferenceSalaryInput): CalculationResult<WorkedTimeSalary> {
  const { basis } = input;
  const validDate = (date: string) => /^\d{4}-\d{2}-\d{2}$/.test(date)
    && Number.isFinite(Date.parse(`${date}T00:00:00.000Z`))
    && new Date(`${date}T00:00:00.000Z`).toISOString().slice(0, 10) === date;
  const validSource = (source: string) => {
    try { return new URL(source).protocol === "https:"; } catch { return false; }
  };
  if (!basis.basisId || !basis.appliesTo || (basis.effectiveFrom !== null && !validDate(basis.effectiveFrom)) || !validDate(basis.reviewedAt)
    || basis.sourceUrls.length === 0 || basis.sourceUrls.some((url) => !validSource(url))) return failure("invalid-basis", "basis");
  const calculated = calculateWorkedTime({ income: input.monthlySalary, workdays: input.paidDaysPerMonth, hoursPerDay: input.hoursPerDay, period: "reference-month" });
  if (!calculated.ok) {
    const field = calculated.error.field === "income" ? "monthlySalary" : calculated.error.field === "workdays" ? "paidDaysPerMonth" : calculated.error.field;
    return failure(calculated.error.code, field);
  }
  return { ok: true, value: { ...calculated.value, metadata: {
    ...metadata("jurisdiction-reference", "reference-month", { paidDaysPerMonth: input.paidDaysPerMonth, hoursPerDay: input.hoursPerDay, grossIncome: true }),
    ...basis,
  } } };
}

/** Presentation only: never feed this result back into a calculation. */
export function roundForDisplay(value: number, digits = 2): number {
  if (!Number.isFinite(value) || !Number.isInteger(digits) || digits < 0 || digits > 6) throw new RangeError("Invalid display rounding input");
  return Number(new Intl.NumberFormat("en-US", { useGrouping: false, minimumFractionDigits: digits, maximumFractionDigits: digits }).format(value));
}

/** Strict locale-aware number input. Invalid or misplaced grouping is rejected, never guessed. */
export function parseLocaleNumber(input: string, locale = "en-US"): CalculationResult<number> {
  let text = input.normalize("NFKC").replace(/[\u061c\u200e\u200f]/g, "").trim();
  // Accept customary native digits even in locales whose Intl default is Latin.
  for (const zero of [0x0660, 0x06f0, 0x0966, 0x0e50]) {
    for (let digit = 0; digit <= 9; digit++) text = text.split(String.fromCodePoint(zero + digit)).join(String(digit));
  }
  if (!text) return failure("required", "number");
  let formatter: Intl.NumberFormat;
  try { formatter = new Intl.NumberFormat(locale); } catch { return failure("invalid-number", "locale"); }
  const parts = formatter.formatToParts(123456789.5);
  const decimal = parts.find((part) => part.type === "decimal")?.value.normalize("NFKC") ?? ".";
  const group = parts.find((part) => part.type === "group")?.value.normalize("NFKC");
  for (let digit = 0; digit <= 9; digit++) {
    const localized = new Intl.NumberFormat(locale, { useGrouping: false }).format(digit).normalize("NFKC");
    text = text.split(localized).join(String(digit));
  }
  const negative = text.startsWith("-") || text.startsWith("−");
  if (negative || text.startsWith("+")) text = text.slice(1);
  const pieces = text.split(decimal);
  if (pieces.length > 2 || (pieces.length === 2 && !/^\d+$/.test(pieces[1]))) return failure("invalid-number", "number");
  let integer = pieces[0];
  if (group && integer.includes(group)) {
    const groups = integer.split(group);
    const sizes = parts.filter((part) => part.type === "integer").map((part) => Array.from(part.value).length);
    const primary = sizes.at(-1) ?? 3;
    const secondary = sizes.at(-2) ?? primary;
    if (!groups.every((part) => /^\d+$/.test(part)) || groups[0].length < 1 || groups[0].length > secondary
      || groups.at(-1)?.length !== primary || groups.slice(1, -1).some((part) => part.length !== secondary)) return failure("invalid-number", "number");
    integer = groups.join("");
  }
  if (!/^\d+$/.test(integer) && !(integer === "" && pieces.length === 2)) return failure("invalid-number", "number");
  const value = Number(`${negative ? "-" : ""}${integer || "0"}${pieces.length === 2 ? `.${pieces[1]}` : ""}`);
  if (!Number.isFinite(value) || Math.abs(value) > Number.MAX_SAFE_INTEGER) return failure("invalid-number", "number");
  return { ok: true, value };
}
