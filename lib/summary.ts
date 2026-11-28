import {
  addCivilDaysMs,
  buildShiftTimeline,
  civilDateKey,
  civilDateAtMs,
  civilMonthStartMs,
  DEFAULT_MONTHLY_WORKING_DAYS,
  getDailySalary,
  getPlannedShiftDurationMs,
  getMonthlySalaryEquivalent,
  isScheduledWorkday,
  isScheduledWorkdayInZone,
  normalizeOvertimePayMultiplier,
  startOfCivilDayMs,
  type DailySalaryBasis,
  type WorkScheduleConfig,
  type SalaryType,
} from "./countdown";
import { resolveScheduleDay } from "./extended-schedule";

// 周期性汇总。**完全由配置推算，不依赖任何历史记录。**
//
// 这是刻意的选择：用户不会把页面挂满整个工作日，也不会每天都来。真去记录
// 「实际累计时长」，只能记到他碰巧打开的那几天、那几个小时，算出来的
// 「今年已赚」会比真实值低一个数量级——那不是诚实的数据，是个坏掉的指标。
// 按配置推算则不需要积累期，新用户第一次打开就能看到有意义的数字，
// 代价是必须如实标注「按当前设置推算」。

export interface PeriodSummary {
  /** 已过去的工作日数，当前班次按完成比例计入小数。 */
  days: number;
  hours: number;
  /** 未配置薪资时为 null。 */
  earnings: number | null;
}

export type LifeSalaryCadence = "monthly" | "yearly";

export interface LifeIncomePeriod {
  /** Gregorian civil date, YYYY-MM-DD. */
  startsOn: string;
  /** Nil means this salary continues until retirement. */
  endsOn?: string | null;
  salaryAmount: number;
  salaryCadence: LifeSalaryCadence;
}

export interface LifeIncomeSalary {
  salaryAmount: number;
  salaryCadence: LifeSalaryCadence;
  /** Defaults to asOf; rough profiles may start at a future work year. */
  startsOn?: string;
}

export interface LifeIncomeDecline {
  /** Gregorian civil date derived from the user's chosen starting age. */
  startsOn: string;
  /** Fixed share of current salary from startsOn until retirement, from 0 through 1. The field name is retained for saved-data compatibility. */
  retirementRatio: number;
}

export interface LifetimeIncomeSummary {
  /** Income before asOf, based only on salaries the user supplied. */
  historicalGross: number;
  /** Income from asOf to retirement at the salary covering that interval. */
  projectedGross: number;
  totalGross: number;
  /**
   * False when the supplied intervals contradict each other (two stored
   * periods overlap). The amounts are then zero and a surface should hide the
   * figure instead of printing a total of 0.
   */
  isValid: boolean;
}

export interface RecordsSummarySegment {
  startAtMs: number;
  endAtMs: number;
}

export interface RecordsSummaryObservation {
  kind: "started" | "stopped";
  occurredAtMs: number;
}

export interface RecordsActualForecastDay {
  /** Shift anchor civil date, including for overnight shifts. */
  dayKey?: string;
  /** Null is a forecast row; an actual row always wins for its civil date. */
  actualKind?: "corrected" | "observed" | "scheduled" | null;
  /** The final override/calendar/schedule-chain answer for this date. */
  resolvedSegments: RecordsSummarySegment[];
  /** Base schedule duration is the pay denominator for corrected work. */
  plannedSegments: RecordsSummarySegment[];
  /** Immutable declarations can overlap, so the shared rule unions them. */
  overtimeSegments: RecordsSummarySegment[];
  /**
   * Plan 024: the pay multiplier the day's latest overtime declaration chose
   * (0 = unpaid). Omitted or invalid means 1, the original hourly rate.
   */
  overtimePayMultiplier?: number | null;
  /**
   * Plan 024: the hours the day's latest overtime declaration counts, which
   * replace the measured overtime length in statistics and pay. Omitted or
   * invalid (not 0 to 24 hours) means the measured length.
   */
  overtimeCountedMs?: number | null;
  observations: RecordsSummaryObservation[];
  /** Whether this civil date owns the currently running shift. */
  isActiveAnchor: boolean;
}

export interface RecordsActualForecastPart {
  days: number;
  hours: number;
  earnings: number | null;
}

export interface RecordsActualForecastSummary {
  actualOvertimeHours: number;
  actual: RecordsActualForecastPart;
  forecast: RecordsActualForecastPart;
  total: RecordsActualForecastPart;
}

/** Apply one salary ratio in the shared rules layer for every native surface. */
export function earningsForRatio(
  dailySalary: number | null,
  payRatio: number
): number | null {
  if (dailySalary === null) return null;
  const earnings = Math.max(0, payRatio) * dailySalary;
  return Number.isFinite(earnings) ? earnings : null;
}

/**
 * Records income deliberately counts only completed scheduled workdays.
 * The current day and overtime belong to the timer's live summary instead.
 */
export function completedWorkdayIncome(
  completedWorkdays: number,
  dailySalary: number | null
): number | null {
  const days = Number.isFinite(completedWorkdays)
    ? Math.max(0, Math.trunc(completedWorkdays))
    : 0;
  return earningsForRatio(dailySalary, days);
}

const DAY_MS = 86_400_000;

interface CivilDay {
  year: number;
  month: number;
  day: number;
  dayNumber: number;
}

function civilDay(value: string): CivilDay | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const timestamp = Date.UTC(year, month - 1, day);
  const parsed = new Date(timestamp);
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) return null;
  return { year, month, day, dayNumber: timestamp / DAY_MS };
}

/** Each partial calendar month is prorated by that month's actual day count. */
function civilMonthsBetween(start: CivilDay, end: CivilDay): number {
  if (end.dayNumber <= start.dayNumber) return 0;
  let cursor = start.dayNumber;
  let total = 0;
  while (cursor < end.dayNumber) {
    const cursorDate = new Date(cursor * DAY_MS);
    const monthStart = Date.UTC(
      cursorDate.getUTCFullYear(),
      cursorDate.getUTCMonth(),
      1,
    ) / DAY_MS;
    const nextMonth = Date.UTC(
      cursorDate.getUTCFullYear(),
      cursorDate.getUTCMonth() + 1,
      1,
    ) / DAY_MS;
    const segmentEnd = Math.min(end.dayNumber, nextMonth);
    total += (segmentEnd - cursor) / (nextMonth - monthStart);
    cursor = segmentEnd;
  }
  return total;
}

/**
 * Gross lifetime income from user-entered salary intervals. Gaps contribute
 * zero; no raise, inflation, investment return, or missing salary is inferred.
 */
export function projectLifetimeGrossIncome(params: {
  periods: LifeIncomePeriod[];
  currentSalary?: LifeIncomeSalary | null;
  /** Missing keeps the current salary unchanged, preserving older profiles. */
  futureIncomeDecline?: LifeIncomeDecline | null;
  asOf: string;
  retirementOn: string;
}): LifetimeIncomeSummary {
  const asOf = civilDay(params.asOf);
  const retirement = civilDay(params.retirementOn);
  if (asOf === null || retirement === null) {
    return { historicalGross: 0, projectedGross: 0, totalGross: 0, isValid: false };
  }

  const periods = [...params.periods];
  if (params.currentSalary) {
    periods.push({
      startsOn: params.currentSalary.startsOn ?? params.asOf,
      endsOn: params.retirementOn,
      salaryAmount: params.currentSalary.salaryAmount,
      salaryCadence: params.currentSalary.salaryCadence,
    });
  }
  const validPeriods: Array<{
    period: LifeIncomePeriod;
    start: CivilDay;
    end: CivilDay;
    isCurrentSalary: boolean;
  }> = [];
  // The current salary owns everything from its own start. A stored period
  // that runs past that point (an open one, or one that ends or starts later)
  // is cut there, so the two can never overlap and zero the whole figure.
  const currentStart = params.currentSalary
    ? civilDay(params.currentSalary.startsOn ?? params.asOf)
    : null;
  for (const [index, period] of periods.entries()) {
    const isCurrentSalary = params.currentSalary != null && index === periods.length - 1;
    const start = civilDay(period.startsOn);
    const explicitEnd = period.endsOn ? civilDay(period.endsOn) : retirement;
    if (
      start === null || explicitEnd === null ||
      !Number.isFinite(period.salaryAmount) || period.salaryAmount <= 0
    ) continue;
    let end = explicitEnd.dayNumber <= retirement.dayNumber ? explicitEnd : retirement;
    if (!isCurrentSalary && currentStart !== null && end.dayNumber > currentStart.dayNumber) {
      end = currentStart;
    }
    if (end.dayNumber <= start.dayNumber) continue;
    validPeriods.push({ period, start, end, isCurrentSalary });
  }
  validPeriods.sort((left, right) => left.start.dayNumber - right.start.dayNumber);

  // Work history is sequential. Reject overlap rather than inventing which
  // salary wins or counting two full-time jobs for the same calendar day.
  if (validPeriods.some((value, index) =>
    index > 0 && value.start.dayNumber < validPeriods[index - 1].end.dayNumber
  )) {
    return { historicalGross: 0, projectedGross: 0, totalGross: 0, isValid: false };
  }

  let historicalGross = 0;
  let projectedGross = 0;
  const declineStart = params.futureIncomeDecline
    ? civilDay(params.futureIncomeDecline.startsOn)
    : null;
  const retirementRatio = params.futureIncomeDecline?.retirementRatio;
  const validDecline = declineStart !== null
    && retirementRatio !== undefined
    && Number.isFinite(retirementRatio)
    && retirementRatio >= 0
    && retirementRatio <= 1;
  for (const { period, start, end, isCurrentSalary } of validPeriods) {
    const monthlySalary = period.salaryCadence === "monthly"
      ? period.salaryAmount
      : period.salaryAmount / 12;
    const historicalEnd = end.dayNumber <= asOf.dayNumber ? end : asOf;
    const totalForPeriod = monthlySalary * civilMonthsBetween(start, end);
    const historicalForPeriod = monthlySalary * civilMonthsBetween(start, historicalEnd);
    historicalGross += historicalForPeriod;
    const projectedStart = start.dayNumber >= asOf.dayNumber ? start : asOf;
    if (!isCurrentSalary || !validDecline || projectedStart.dayNumber >= end.dayNumber) {
      projectedGross += totalForPeriod - historicalForPeriod;
      continue;
    }
    const anchorDay = Math.max(projectedStart.dayNumber, declineStart.dayNumber);
    projectedGross += monthlySalary * civilMonthsBetween(projectedStart, {
      ...projectedStart,
      dayNumber: Math.min(anchorDay, end.dayNumber),
    });
    if (anchorDay < end.dayNumber) {
      projectedGross += monthlySalary * retirementRatio * civilMonthsBetween(
        { ...projectedStart, dayNumber: anchorDay }, end,
      );
    }
  }
  return {
    historicalGross,
    projectedGross,
    totalGross: historicalGross + projectedGross,
    isValid: true,
  };
}

/**
 * Plan 024: worked time with the part beyond the regular segments (the
 * overtime) scaled by the day's multiplier. 1 returns `totalMs` untouched.
 */
export function weightedOvertimeMs(
  totalMs: number,
  regularMs: number,
  multiplier: number
): number {
  if (multiplier === 1) return totalMs;
  const regular = Math.min(totalMs, regularMs);
  return regular + multiplier * (totalMs - regular);
}

/** The longest hours count a declaration may carry. */
export const MAX_COUNTED_OVERTIME_MS = 24 * 3_600_000;

/** Plan 024: the counted overtime as stored; null unless finite and 0...24h. */
export function normalizeCountedOvertimeMs(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  if (value < 0 || value > MAX_COUNTED_OVERTIME_MS) return null;
  return value;
}

/**
 * Plan 024: the factor that turns a day's measured overtime into its counted
 * overtime: counted / full measured length. 1 without a valid counted value
 * or when there is no measured overtime to scale.
 */
export function overtimeCountScale(fullMeasuredMs: number, countedMs: unknown): number {
  const counted = normalizeCountedOvertimeMs(countedMs);
  if (counted === null || !Number.isFinite(fullMeasuredMs) || fullMeasuredMs <= 0) return 1;
  return counted / fullMeasuredMs;
}

/**
 * Split recorded/corrected work from schedule estimates for one visible
 * period. One logical day can enter only one side; actual always wins.
 */
export function summarizeRecordsActualAndForecast(params: {
  days: RecordsActualForecastDay[];
  /** Every civil date in the visible period, including rest and absent days. */
  periodDayKeys?: string[];
  dailySalary: number | null;
  /**
   * An hourly wage: each day pays this for every effective hour, so a day's
   * rate follows its own planned hours and `dailySalary` is not used.
   */
  hourlyRate?: number | null;
  asOfMs: number;
  /**
   * The user's usual planned effective day, in ms. A day the plan leaves free
   * (rest-day overtime) has no planned length of its own; it is paid at the
   * hourly rate this day implies (daily rate / these hours), linearly.
   */
  normalPlannedMs?: number | null;
  salaryRules?: {
    salaryAmount: string;
    salaryType: SalaryType;
    monthlyWorkingDays?: number;
    workdays: number[];
    schedule?: WorkScheduleConfig | null;
    timeZoneIdentifier?: string | null;
    annualBonusMonths: number;
    /**
     * A monthly salary accrues per scheduled workday: each civil month is
     * divided by its own scheduled workdays. Omitted means `scheduledMonth`;
     * `fixed` divides by `monthlyWorkingDays` instead (an explicit override).
     */
    dailySalaryBasis?: DailySalaryBasis | null;
  };
}): RecordsActualForecastSummary {
  let actualDays = 0;
  let actualMs = 0;
  let actualOvertimeMs = 0;
  let actualPay = 0;
  let forecastDays = 0;
  let forecastMs = 0;
  let forecastPay = 0;

  const rules = params.salaryRules;
  const usesMonthlyPay = rules?.salaryType === "monthly";
  const monthlySalary: MonthBasisSalary | null = usesMonthlyPay && rules
    ? {
        amount: rules.salaryAmount,
        type: "monthly",
        monthlyWorkingDays: rules.monthlyWorkingDays ?? DEFAULT_MONTHLY_WORKING_DAYS,
        annualBonusMonths: rules.annualBonusMonths,
        basis: rules.dailySalaryBasis ?? "scheduledMonth",
      }
    : null;
  // A monthly salary accrues per scheduled workday, each day at its own
  // month's daily pay (monthly / that month's scheduled workdays).
  const monthlyDailyByMonth = new Map<number, number | null>();
  const monthlyDailyFor = (day: RecordsActualForecastDay): number | null => {
    if (!monthlySalary || !rules) return null;
    const zone = rules.timeZoneIdentifier?.trim() || undefined;
    const firstStart = [day.resolvedSegments, day.plannedSegments, day.overtimeSegments]
      .flat().map(segment => segment.startAtMs).filter(Number.isFinite).sort((a, b) => a - b)[0];
    const anchorMs = day.dayKey
      ? civilDateAtMs(day.dayKey, zone, "12:00")
      : firstStart;
    if (anchorMs === undefined || !Number.isFinite(anchorMs)) return null;
    const monthKey = civilMonthStartMs(anchorMs, zone, 0);
    if (!monthlyDailyByMonth.has(monthKey)) {
      monthlyDailyByMonth.set(monthKey, dailySalaryInMonth({
        salary: monthlySalary,
        anchorMs,
        workdays: rules.workdays,
        schedule: rules.schedule,
        timeZone: zone,
      }));
    }
    return monthlyDailyByMonth.get(monthKey) ?? null;
  };
  const hourlyRate = typeof params.hourlyRate === "number" && Number.isFinite(params.hourlyRate) && params.hourlyRate >= 0
    ? params.hourlyRate
    : null;
  // A rate present means hourly pay; an hourly setting without one has no
  // earnings, as with any missing salary.
  const usesHourlyPay = params.hourlyRate != null || rules?.salaryType === "hourly";
  const normalPlannedMs = typeof params.normalPlannedMs === "number"
    && Number.isFinite(params.normalPlannedMs) && params.normalPlannedMs > 0
    ? params.normalPlannedMs
    : 0;
  let hasSalary = usesMonthlyPay
    ? monthlySalary !== null && getDailySalary(
        monthlySalary.amount, "monthly", monthlySalary.monthlyWorkingDays, monthlySalary.annualBonusMonths,
      ) !== null
    : usesHourlyPay ? hourlyRate !== null : params.dailySalary !== null;
  for (const day of params.days) {
    if (day.resolvedSegments.length === 0 && day.overtimeSegments.length === 0) continue;
    const plannedMs = mergedSegmentDuration(day.plannedSegments);
    // What a full day pays is measured against the planned day; a day the plan
    // left free uses the user's usual planned day instead, so overtime on it
    // pays the hourly rate that day implies rather than a whole daily rate.
    const payBasisMs = plannedMs > 0 ? plannedMs : normalPlannedMs;
    // Hourly: the day is worth its own planned hours at the rate; a day with
    // no plan uses the usual planned day, else the hours it holds.
    const rate = usesHourlyPay
      ? hourlyRate === null
        ? null
        : hourlyRate * (payBasisMs > 0 ? payBasisMs : mergedSegmentDuration(day.resolvedSegments)) / 3_600_000
      : usesMonthlyPay ? monthlyDailyFor(day) : params.dailySalary;
    if (rate === null) hasSalary = false;
    const isActual = day.actualKind === "corrected" || day.actualKind === "observed" || day.actualKind === "scheduled";
    if (isActual) {
      const regularSegments = day.actualKind !== "observed"
        ? day.resolvedSegments
        : intersectSegments(
            observedWorkSegments(
              day.observations,
              params.asOfMs,
              day.isActiveAnchor,
              plannedEndAtMs(day),
            ),
            day.resolvedSegments,
          );
      const elapsedRegular = regularSegments.map(segment => ({
        ...segment,
        endAtMs: Math.min(segment.endAtMs, params.asOfMs),
      }));
      const elapsedOvertime = day.overtimeSegments.map(segment => ({
        ...segment,
        endAtMs: Math.min(segment.endAtMs, params.asOfMs),
      }));
      const measuredWorkedMs = mergedSegmentDuration([...elapsedRegular, ...elapsedOvertime]);
      const regularMs = mergedSegmentDuration(elapsedRegular);
      // Plan 024: counted hours replace the measured overtime length.
      const countScale = overtimeCountScale(
        Math.max(
          0,
          mergedSegmentDuration([...regularSegments, ...day.overtimeSegments]) -
            mergedSegmentDuration(regularSegments),
        ),
        day.overtimeCountedMs,
      );
      const overtimeMs = Math.max(0, measuredWorkedMs - regularMs) * countScale;
      const workedMs = countScale === 1 ? measuredWorkedMs : regularMs + overtimeMs;
      actualOvertimeMs += countScale === 1 ? Math.max(0, workedMs - regularMs) : overtimeMs;
      const multiplier = normalizeOvertimePayMultiplier(day.overtimePayMultiplier ?? 1);
      if (workedMs > 0) {
        actualDays += 1;
        actualMs += workedMs;
        const paidMs = weightedOvertimeMs(workedMs, regularMs, multiplier);
        actualPay += (rate ?? 0) * (payBasisMs > 0 ? paidMs / payBasisMs : 1);
      }
      if (day.isActiveAnchor || day.actualKind === "scheduled") {
        const futureAllMs = mergedSegmentDuration(
          [...day.resolvedSegments, ...day.overtimeSegments].map(segment => ({
            ...segment,
            startAtMs: Math.max(segment.startAtMs, params.asOfMs),
          })),
        );
        const futureRegularMs = mergedSegmentDuration(
          day.resolvedSegments.map(segment => ({
            ...segment,
            startAtMs: Math.max(segment.startAtMs, params.asOfMs),
          })),
        );
        const futureMs = countScale === 1
          ? futureAllMs
          : futureRegularMs + Math.max(0, futureAllMs - futureRegularMs) * countScale;
        if (futureMs > 0) {
          if (workedMs <= 0) forecastDays += 1;
          forecastMs += futureMs;
          const paidFutureMs = weightedOvertimeMs(futureMs, futureRegularMs, multiplier);
          forecastPay += (rate ?? 0) * (payBasisMs > 0 ? paidFutureMs / payBasisMs : (workedMs <= 0 ? 1 : 0));
        }
      }
      continue;
    }
    const forecastWorkMs = mergedSegmentDuration(day.resolvedSegments);
    if (forecastWorkMs <= 0) continue;
    forecastDays += 1;
    forecastMs += forecastWorkMs;
    // Half a day of leave or a shortened override is half a day of pay.
    forecastPay += (rate ?? 0) * (payBasisMs > 0 ? forecastWorkMs / payBasisMs : 1);
  }

  const actualEarnings = hasSalary && Number.isFinite(actualPay) ? actualPay : null;
  const forecastEarnings = hasSalary && Number.isFinite(forecastPay) ? forecastPay : null;
  const totalEarnings = actualEarnings === null || forecastEarnings === null
    ? null : actualEarnings + forecastEarnings;
  return {
    actualOvertimeHours: actualOvertimeMs / 3_600_000,
    actual: {
      days: actualDays,
      hours: actualMs / 3_600_000,
      earnings: actualEarnings,
    },
    forecast: {
      days: forecastDays,
      hours: forecastMs / 3_600_000,
      earnings: forecastEarnings,
    },
    total: {
      days: actualDays + forecastDays,
      hours: (actualMs + forecastMs) / 3_600_000,
      earnings: totalEarnings !== null && Number.isFinite(totalEarnings) ? totalEarnings : null,
    },
  };
}

function mergedSegmentDuration(segments: RecordsSummarySegment[]): number {
  const sorted = segments.flatMap(segment => {
    if (
      !Number.isFinite(segment.startAtMs) ||
      !Number.isFinite(segment.endAtMs) ||
      segment.endAtMs <= segment.startAtMs
    ) return [];
    return [{ start: segment.startAtMs, end: segment.endAtMs }];
  }).sort((left, right) => left.start - right.start || left.end - right.end);
  let total = 0;
  let start: number | null = null;
  let end: number | null = null;
  for (const segment of sorted) {
    if (start === null || end === null) {
      start = segment.start;
      end = segment.end;
    } else if (segment.start <= end) {
      end = Math.max(end, segment.end);
    } else {
      total += end - start;
      start = segment.start;
      end = segment.end;
    }
  }
  return start === null || end === null ? total : total + end - start;
}

function intersectSegments(
  left: RecordsSummarySegment[],
  right: RecordsSummarySegment[],
): RecordsSummarySegment[] {
  return left.flatMap(first => right.flatMap(second => {
    const startAtMs = Math.max(first.startAtMs, second.startAtMs);
    const endAtMs = Math.min(first.endAtMs, second.endAtMs);
    return endAtMs > startAtMs ? [{ startAtMs, endAtMs }] : [];
  }));
}

/** The shift's planned end: where a run nobody stopped is closed on a past day. */
function plannedEndAtMs(day: RecordsActualForecastDay): number | null {
  const segments = day.plannedSegments.length > 0 ? day.plannedSegments : day.resolvedSegments;
  const ends = segments.map(segment => segment.endAtMs).filter(Number.isFinite);
  return ends.length > 0 ? Math.max(...ends) : null;
}

/**
 * Started/stopped pairs as intervals. An unmatched start runs to `asOfMs` on
 * the day that owns the running shift; on any other day nobody stopped it, so
 * it closes at the shift's planned end instead of losing the day's pay.
 */
function observedWorkSegments(
  observations: RecordsSummaryObservation[],
  asOfMs: number,
  closesOpenObservation: boolean,
  plannedEndMs: number | null = null,
): RecordsSummarySegment[] {
  const sorted = observations
    .filter(value => Number.isFinite(value.occurredAtMs))
    .sort((left, right) => left.occurredAtMs - right.occurredAtMs);
  const result: RecordsSummarySegment[] = [];
  let startedAt: number | null = null;
  for (const observation of sorted) {
    if (observation.kind === "started") {
      if (startedAt === null) startedAt = observation.occurredAtMs;
    } else if (startedAt !== null) {
      if (observation.occurredAtMs > startedAt) {
        result.push({ startAtMs: startedAt, endAtMs: observation.occurredAtMs });
      }
      startedAt = null;
    }
  }
  if (startedAt !== null) {
    const closeAt = closesOpenObservation ? asOfMs : plannedEndMs;
    if (closeAt !== null && Number.isFinite(closeAt) && closeAt > startedAt) {
      result.push({ startAtMs: startedAt, endAtMs: closeAt });
    }
  }
  return result;
}

/** 一周的起点固定为周一（ISO 8601），与界面上工作日选择器的排列一致。 */
export function startOfWeek(date: Date): Date {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  // getDay(): 0=周日。周日应回退 6 天而非 -1 天。
  const offset = (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - offset);
  return d;
}

export function startOfYear(date: Date): Date {
  return new Date(date.getFullYear(), 0, 1);
}

/**
 * 统计 [from, to) 区间内的工作日数量，均按当地日期推进。
 *
 * 用 setDate 而非「加 86400000 毫秒」推进：夏令时切换那两天分别是 23 和 25
 * 小时，按毫秒加会错过或重复一天。
 */
export function countWorkdays(from: Date, to: Date, workdays: number[]): number {
  if (workdays.length === 0) return 0;

  const cursor = new Date(from);
  cursor.setHours(0, 0, 0, 0);
  const end = new Date(to);
  end.setHours(0, 0, 0, 0);

  let count = 0;
  while (cursor < end) {
    if (workdays.includes(cursor.getDay())) count += 1;
    cursor.setDate(cursor.getDate() + 1);
  }
  return count;
}

export function countScheduledWorkdays(
  from: Date,
  to: Date,
  workdays: number[],
  schedule?: WorkScheduleConfig | null,
  timeZone?: string
): number {
  if (!schedule?.extendedSchedule && schedule?.mode === "off") return 0;
  if (timeZone) {
    let cursor = startOfCivilDayMs(from.getTime(), timeZone);
    const end = startOfCivilDayMs(to.getTime(), timeZone);
    let count = 0;
    while (cursor < end) {
      if (isScheduledWorkdayInZone(cursor, workdays, schedule, timeZone)) count += 1;
      cursor = addCivilDaysMs(cursor, 1, timeZone);
    }
    return count;
  }
  const cursor = new Date(from);
  cursor.setHours(0, 0, 0, 0);
  const end = new Date(to);
  end.setHours(0, 0, 0, 0);
  let count = 0;
  while (cursor < end) {
    if (isScheduledWorkday(cursor, workdays, schedule)) count += 1;
    cursor.setDate(cursor.getDate() + 1);
  }
  return count;
}

/**
 * Scheduled workdays in the civil month containing `anchorMs`, in `timeZone`
 * (the runtime's zone when omitted). Same day test as `countScheduledWorkdays`,
 * so extended-schedule holidays and makeup days count, and manual (`off`)
 * mode has none.
 */
export function countScheduledWorkdaysInMonth(params: {
  anchorMs: number;
  workdays: number[];
  schedule?: WorkScheduleConfig | null;
  timeZone?: string | null;
}): number {
  const { anchorMs, workdays, schedule } = params;
  const timeZone = params.timeZone?.trim() || undefined;
  return countScheduledWorkdays(
    new Date(civilMonthStartMs(anchorMs, timeZone, 0)),
    new Date(civilMonthStartMs(anchorMs, timeZone, 1)),
    workdays,
    schedule,
    timeZone
  );
}

/** The salary fields the month-basis rules read. */
export interface MonthBasisSalary {
  amount: string;
  type: SalaryType;
  monthlyWorkingDays: number;
  annualBonusMonths: number;
  basis?: DailySalaryBasis | null;
}

/** Whether pay divides each civil month by its own scheduled workdays. */
export function usesScheduledMonthBasis(salary: MonthBasisSalary): boolean {
  return salary.basis === "scheduledMonth" && salary.type === "monthly";
}

/**
 * Daily pay for the civil month containing `anchorMs`. Daily salaries and the
 * `fixed` basis are exactly `getDailySalary`; `scheduledMonth` divides by that
 * month's scheduled workdays, falling back to the fixed setting without any.
 */
export function dailySalaryInMonth(params: {
  salary: MonthBasisSalary;
  anchorMs: number;
  workdays: number[];
  schedule?: WorkScheduleConfig | null;
  timeZone?: string | null;
}): number | null {
  const { salary, anchorMs, workdays, schedule, timeZone } = params;
  const count = usesScheduledMonthBasis(salary)
    ? countScheduledWorkdaysInMonth({ anchorMs, workdays, schedule, timeZone })
    : null;
  return getDailySalary(
    salary.amount,
    salary.type,
    salary.monthlyWorkingDays,
    salary.annualBonusMonths,
    count
  );
}

/**
 * Records income under the `scheduledMonth` basis: each month's completed
 * workdays at that month's own daily pay. `months` lists every civil month that
 * has completed days, by any instant inside it.
 */
export function completedWorkdayIncomeByMonth(params: {
  months: { anchorMs: number; count: number }[];
  salary: MonthBasisSalary;
  workdays: number[];
  schedule?: WorkScheduleConfig | null;
  timeZone?: string | null;
}): number | null {
  const { months, salary, workdays, schedule, timeZone } = params;
  if (months.length === 0) {
    return completedWorkdayIncome(
      0,
      getDailySalary(
        salary.amount,
        salary.type,
        salary.monthlyWorkingDays,
        salary.annualBonusMonths
      )
    );
  }
  let total = 0;
  for (const { anchorMs, count } of months) {
    const daily = dailySalaryInMonth({ salary, anchorMs, workdays, schedule, timeZone });
    if (daily === null) return null;
    const days = Number.isFinite(count) ? Math.max(0, Math.trunc(count)) : 0;
    total += days * daily;
  }
  return Number.isFinite(total) ? total : null;
}

/**
 * Where the earlier days end and today's live shift begins: the civil midnight
 * of the running shift's start day when that shift still covers the as-of day,
 * else the as-of day itself. `summarize` estimates, or a host with records
 * supplies (`completed`), the days from `periodStart` up to this instant.
 */
export function completedSummaryEndMs(params: {
  periodStart: Date;
  asOf: Date;
  currentShiftStart: Date;
  currentShiftEnd: Date;
  timeZone?: string;
}): number {
  const { timeZone } = params;
  const startOfDay = (date: Date) => {
    if (timeZone) return startOfCivilDayMs(date.getTime(), timeZone);
    const next = new Date(date);
    next.setHours(0, 0, 0, 0);
    return next.getTime();
  };
  const shiftDayMs = startOfDay(params.currentShiftStart);
  const shiftEndDayMs = startOfDay(params.currentShiftEnd);
  const periodDayMs = startOfDay(params.periodStart);
  const asOfDayMs = startOfDay(params.asOf);
  return shiftDayMs >= periodDayMs && shiftDayMs <= asOfDayMs && shiftEndDayMs >= asOfDayMs
    ? shiftDayMs
    : asOfDayMs;
}

/**
 * 汇总从 periodStart 到此刻的工作量。
 *
 * 当前班次单独计算：只有它的开班日是工作日、且落在当前周期时才计入，
 * 并按已完成比例折算，与界面上「今日已赚」的口径保持一致。
 */
export function summarize(params: {
  periodStart: Date;
  /** 汇总所处的当前日，只负责截断未来日期，不决定夜班归属。 */
  asOf: Date;
  workdays: number[];
  schedule?: WorkScheduleConfig | null;
  /** 当前班次按开始日期归属工作日；跨午夜后仍属于开始的那一天。 */
  currentShiftStart: Date;
  /** 用于判断该班次是否仍覆盖统计日；跨夜班次的结束日会晚于开始日。 */
  currentShiftEnd: Date;
  /** 当前设置下一个完整计划班次的有效工时，已经扣除午休。 */
  plannedDailyHours: number;
  /** 班次进度百分比 0–100，来自正在运行的倒计时。 */
  todayProgress: number;
  dailySalary: number | null;
  /**
   * With the `scheduledMonth` basis on a monthly salary, earnings are summed
   * month by month (completed days at each month's daily pay, then today's
   * ratio at today's month) and `dailySalary` is not used.
   */
  salary?: MonthBasisSalary | null;
  /** 当前班次实际有效工时；用于午休与加班，未提供时按计划有效时长。 */
  todayEffectiveHours?: number;
  /** 当前班次按原日薪线性外推的计薪比例；可因加班超过 1。 */
  todayPayRatio?: number;
  /** 记录时区。缺省时退回运行环境本地时区，iOS 必须传入。 */
  timeZone?: string;
  /**
   * An hourly wage. Earnings become the rate times the hours counted: every
   * completed day's planned effective hours, then today's pay ratio of its
   * planned hours (`todayPlannedHours`, else `plannedDailyHours`).
   */
  hourlyRate?: number | null;
  todayPlannedHours?: number;
  /**
   * A host that keeps per-day records (iOS) supplies the totals it already
   * shows for the civil days from `periodStart` up to, not including, the
   * running shift's day (`completedSummaryEndMs`). They replace the schedule
   * estimate for those days, so a past day keeps its recorded overtime, leave
   * and edits instead of being re-priced at today's plan. Only today's live
   * share is added here. Omitted, every earlier day is estimated.
   */
  completed?: PeriodSummary | null;
}): PeriodSummary {
  const {
    periodStart,
    asOf,
    workdays,
    schedule,
    currentShiftStart,
    currentShiftEnd,
    plannedDailyHours,
    todayProgress,
    dailySalary,
    salary,
    todayEffectiveHours,
    todayPayRatio,
    timeZone,
    hourlyRate,
    todayPlannedHours,
    completed: recordedCompleted,
  } = params;

  const startOfDay = (date: Date) => {
    if (timeZone) return startOfCivilDayMs(date.getTime(), timeZone);
    const next = new Date(date);
    next.setHours(0, 0, 0, 0);
    return next.getTime();
  };
  const shiftDayMs = startOfDay(currentShiftStart);
  const shiftEndDayMs = startOfDay(currentShiftEnd);
  const periodDayMs = startOfDay(periodStart);
  const asOfDayMs = startOfDay(asOf);
  // 同日班次在当天结束后仍由进度折算，跨夜班次在结束日也继续归属于开班日；
  // 一旦统计日越过班次结束日，activeShift 就只是 UI 留下的旧快照，不能再
  // 截断后续工作日。
  const currentShiftCoversAsOfDay =
    shiftDayMs >= periodDayMs && shiftDayMs <= asOfDayMs && shiftEndDayMs >= asOfDayMs;
  const endMs = currentShiftCoversAsOfDay ? shiftDayMs : asOfDayMs;
  const completed = recordedCompleted
    ? recordedCompleted.days
    : countScheduledWorkdays(new Date(periodDayMs), new Date(endMs), workdays, schedule, timeZone);
  // One call for both zones. `isScheduledWorkday` routes to the zoned helper
  // itself, and unlike that helper it keeps manual (`off`) mode counting — the
  // split here made an iOS week disagree with the same week on the Web.
  const todayCounts =
    currentShiftCoversAsOfDay &&
    isScheduledWorkday(new Date(shiftDayMs), workdays, schedule, timeZone);
  const todayFraction = todayCounts
    ? Math.min(100, Math.max(0, todayProgress)) / 100
    : 0;

  const days = completed + todayFraction;
  let completedHours = recordedCompleted ? recordedCompleted.hours : completed * plannedDailyHours;
  if (!recordedCompleted && schedule?.extendedSchedule) {
    completedHours = 0;
    for (let cursor = periodDayMs; cursor < endMs; cursor = addCivilDaysMs(cursor, 1, timeZone)) {
      const day = resolveScheduleDay(schedule.extendedSchedule, civilDateKey(cursor, timeZone));
      if (!day.isWorkday || !day.hours) continue;
      const noon = new Date(civilDateAtMs(civilDateKey(cursor, timeZone), timeZone, "12:00"));
      const timeline = buildShiftTimeline(day.hours.startTime, day.hours.endTime, noon, { extendedSchedule: schedule.extendedSchedule }, timeZone);
      completedHours += getPlannedShiftDurationMs(timeline) / 3_600_000;
    }
  }
  const hours =
    completedHours +
    (todayCounts
      ? (todayEffectiveHours ?? plannedDailyHours) * todayFraction
      : 0);
  const earningsFraction = todayCounts
    ? Math.max(0, todayPayRatio ?? todayFraction)
    : 0;

  // Today's live share of pay, at the daily pay of today's own month.
  let todayEarnings: number | null;
  if (hourlyRate != null) {
    const rate = Number.isFinite(hourlyRate) && hourlyRate >= 0 ? hourlyRate : null;
    todayEarnings = rate === null
      ? null
      : rate * earningsFraction * (todayPlannedHours ?? plannedDailyHours);
  } else if (salary && usesScheduledMonthBasis(salary)) {
    const todayDaily = dailySalaryInMonth({ salary, anchorMs: endMs, workdays, schedule, timeZone });
    todayEarnings = earningsForRatio(todayDaily, earningsFraction);
  } else {
    todayEarnings = earningsForRatio(dailySalary, earningsFraction);
  }

  let earnings: number | null;
  if (recordedCompleted) {
    earnings = recordedCompleted.earnings === null || todayEarnings === null
      ? null
      : recordedCompleted.earnings + todayEarnings;
  } else if (hourlyRate != null) {
    const rate = Number.isFinite(hourlyRate) && hourlyRate >= 0 ? hourlyRate : null;
    const total = rate === null ? null : rate * (completedHours + earningsFraction * (todayPlannedHours ?? plannedDailyHours));
    earnings = total !== null && Number.isFinite(total) ? total : null;
  } else if (salary && usesScheduledMonthBasis(salary)) {
    let total = 0;
    let missing = false;
    for (let cursor = periodDayMs; cursor < endMs; ) {
      const monthEnd = civilMonthStartMs(cursor, timeZone, 1);
      const count = countScheduledWorkdays(
        new Date(cursor),
        new Date(Math.min(endMs, monthEnd)),
        workdays,
        schedule,
        timeZone
      );
      const daily = dailySalaryInMonth({ salary, anchorMs: cursor, workdays, schedule, timeZone });
      if (daily === null) missing = true;
      else total += count * daily;
      cursor = monthEnd;
    }
    if (todayEarnings === null) missing = true;
    else total += todayEarnings;
    earnings = !missing && Number.isFinite(total) ? total : null;
  } else {
    earnings = earningsForRatio(dailySalary, completed + earningsFraction);
  }

  return { days, hours, earnings };
}
