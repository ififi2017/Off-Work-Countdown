import {
  addCivilDaysMs,
  getDailySalary,
  isScheduledWorkday,
  isScheduledWorkdayInZone,
  startOfCivilDayMs,
  type WorkScheduleConfig,
} from "./countdown";

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
  /** Share of today's current salary at retirement, from 0 through 1. */
  retirementRatio: number;
}

export interface LifetimeIncomeSummary {
  /** Income before asOf, based only on salaries the user supplied. */
  historicalGross: number;
  /** Income from asOf to retirement at the salary covering that interval. */
  projectedGross: number;
  totalGross: number;
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
  actualKind?: "corrected" | "observed" | null;
  /** The final override/calendar/schedule-chain answer for this date. */
  resolvedSegments: RecordsSummarySegment[];
  /** Base schedule duration is the pay denominator for corrected work. */
  plannedSegments: RecordsSummarySegment[];
  /** Immutable declarations can overlap, so the shared rule unions them. */
  overtimeSegments: RecordsSummarySegment[];
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
  return Math.max(0, payRatio) * dailySalary;
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
    return { historicalGross: 0, projectedGross: 0, totalGross: 0 };
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
  for (const [index, period] of periods.entries()) {
    const start = civilDay(period.startsOn);
    const explicitEnd = period.endsOn ? civilDay(period.endsOn) : retirement;
    if (
      start === null || explicitEnd === null ||
      !Number.isFinite(period.salaryAmount) || period.salaryAmount <= 0
    ) continue;
    const end = explicitEnd.dayNumber <= retirement.dayNumber ? explicitEnd : retirement;
    if (end.dayNumber <= start.dayNumber) continue;
    validPeriods.push({
      period,
      start,
      end,
      isCurrentSalary: params.currentSalary != null && index === periods.length - 1,
    });
  }
  validPeriods.sort((left, right) => left.start.dayNumber - right.start.dayNumber);

  // Work history is sequential. Reject overlap rather than inventing which
  // salary wins or counting two full-time jobs for the same calendar day.
  if (validPeriods.some((value, index) =>
    index > 0 && value.start.dayNumber < validPeriods[index - 1].end.dayNumber
  )) {
    return { historicalGross: 0, projectedGross: 0, totalGross: 0 };
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
      projectedGross += proratedDecliningIncome(
        monthlySalary,
        { ...projectedStart, dayNumber: anchorDay },
        end,
        anchorDay,
        retirement.dayNumber,
        retirementRatio,
      );
    }
  }
  return {
    historicalGross,
    projectedGross,
    totalGross: historicalGross + projectedGross,
  };
}

function proratedDecliningIncome(
  monthlySalary: number,
  start: CivilDay,
  end: CivilDay,
  declineStartDay: number,
  retirementDay: number,
  retirementRatio: number,
): number {
  const ratioAt = (dayNumber: number) => {
    if (retirementDay <= declineStartDay) return 1;
    const progress = Math.max(0, Math.min(1,
      (dayNumber - declineStartDay) / (retirementDay - declineStartDay)
    ));
    return 1 - (1 - retirementRatio) * progress;
  };
  let cursor = start.dayNumber;
  let total = 0;
  while (cursor < end.dayNumber) {
    const date = new Date(cursor * DAY_MS);
    const monthStart = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1) / DAY_MS;
    const nextMonth = Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1) / DAY_MS;
    const segmentEnd = Math.min(end.dayNumber, nextMonth);
    const monthShare = (segmentEnd - cursor) / (nextMonth - monthStart);
    total += monthlySalary * monthShare * (ratioAt(cursor) + ratioAt(segmentEnd)) / 2;
    cursor = segmentEnd;
  }
  return total;
}

/**
 * Split recorded/corrected work from schedule estimates for one visible
 * period. One logical day can enter only one side; actual always wins.
 */
export function summarizeRecordsActualAndForecast(params: {
  days: RecordsActualForecastDay[];
  dailySalary: number | null;
  asOfMs: number;
  salaryRules?: {
    salaryAmount: string;
    salaryType: "monthly" | "daily";
    workdays: number[];
    schedule?: WorkScheduleConfig | null;
    timeZoneIdentifier?: string | null;
    annualBonusMonths: number;
  };
}): RecordsActualForecastSummary {
  let actualDays = 0;
  let actualMs = 0;
  let actualPay = 0;
  let forecastDays = 0;
  let forecastMs = 0;
  let forecastPay = 0;

  const monthRates = new Map<string, number | null>();
  const dailyRate = (day: RecordsActualForecastDay): number | null => {
    const rules = params.salaryRules;
    if (!rules || rules.salaryType === "daily") return params.dailySalary;
    const anchor = day.plannedSegments[0] ?? day.resolvedSegments[0];
    const civil = day.dayKey ? civilDay(day.dayKey) : null;
    if (!anchor || !civil) return null;
    const monthKey = day.dayKey!.slice(0, 7);
    if (!monthRates.has(monthKey)) {
      const zone = rules.timeZoneIdentifier || undefined;
      const start = addCivilDaysMs(
        startOfCivilDayMs(anchor.startAtMs, zone), 1 - civil.day, zone,
      );
      const daysInMonth = new Date(Date.UTC(civil.year, civil.month, 0)).getUTCDate();
      const end = addCivilDaysMs(start, daysInMonth, zone);
      const scheduledDays = countScheduledWorkdays(
        new Date(start), new Date(end), rules.workdays, rules.schedule, zone,
      );
      // Monthly pay is allocated across this calendar month's scheduled days,
      // never across the average-day setting used by the live timer.
      monthRates.set(monthKey, scheduledDays > 0
        ? getDailySalary(rules.salaryAmount, "monthly", scheduledDays, rules.annualBonusMonths)
        : null);
    }
    return monthRates.get(monthKey) ?? null;
  };
  let hasSalary = params.dailySalary !== null;
  for (const day of params.days) {
    if (day.resolvedSegments.length === 0 && day.overtimeSegments.length === 0) continue;
    const rate = dailyRate(day);
    if (rate === null) hasSalary = false;
    const plannedMs = mergedSegmentDuration(day.plannedSegments);
    const isActual = day.actualKind === "corrected" || day.actualKind === "observed";
    if (isActual) {
      const regularSegments = day.actualKind === "corrected"
        ? day.resolvedSegments
        : intersectSegments(
            observedWorkSegments(day.observations, params.asOfMs, day.isActiveAnchor),
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
      const workedMs = mergedSegmentDuration([...elapsedRegular, ...elapsedOvertime]);
      if (workedMs > 0) {
        actualDays += 1;
        actualMs += workedMs;
        actualPay += (rate ?? 0) * (plannedMs > 0 ? workedMs / plannedMs : 1);
      }
      if (day.isActiveAnchor) {
        const futureMs = mergedSegmentDuration(
          [...day.resolvedSegments, ...day.overtimeSegments].map(segment => ({
            ...segment,
            startAtMs: Math.max(segment.startAtMs, params.asOfMs),
          })),
        );
        if (futureMs > 0) {
          if (workedMs <= 0) forecastDays += 1;
          forecastMs += futureMs;
          forecastPay += (rate ?? 0) * (plannedMs > 0 ? futureMs / plannedMs : (workedMs <= 0 ? 1 : 0));
        }
      }
      continue;
    }
    const forecastWorkMs = mergedSegmentDuration(day.resolvedSegments);
    if (forecastWorkMs <= 0) continue;
    forecastDays += 1;
    forecastMs += forecastWorkMs;
    forecastPay += rate ?? 0;
  }

  const actualEarnings = hasSalary ? actualPay : null;
  const forecastEarnings = hasSalary ? forecastPay : null;
  return {
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
      earnings: actualEarnings === null || forecastEarnings === null
        ? null
        : actualEarnings + forecastEarnings,
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

function observedWorkSegments(
  observations: RecordsSummaryObservation[],
  asOfMs: number,
  closesOpenObservation: boolean,
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
  if (
    startedAt !== null &&
    closesOpenObservation &&
    Number.isFinite(asOfMs) &&
    asOfMs > startedAt
  ) {
    result.push({ startAtMs: startedAt, endAtMs: asOfMs });
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
  if (schedule?.mode === "off") return 0;
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
  /** 当前班次实际有效工时；用于午休与加班，未提供时按计划有效时长。 */
  todayEffectiveHours?: number;
  /** 当前班次按原日薪线性外推的计薪比例；可因加班超过 1。 */
  todayPayRatio?: number;
  /** 记录时区。缺省时退回运行环境本地时区，iOS 必须传入。 */
  timeZone?: string;
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
    todayEffectiveHours,
    todayPayRatio,
    timeZone,
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
  const completed = countScheduledWorkdays(
    new Date(periodDayMs),
    new Date(currentShiftCoversAsOfDay ? shiftDayMs : asOfDayMs),
    workdays,
    schedule,
    timeZone
  );
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
  const hours =
    completed * plannedDailyHours +
    (todayCounts
      ? (todayEffectiveHours ?? plannedDailyHours) * todayFraction
      : 0);
  const earningsFraction = todayCounts
    ? Math.max(0, todayPayRatio ?? todayFraction)
    : 0;

  return {
    days,
    hours,
    earnings: earningsForRatio(dailySalary, completed + earningsFraction),
  };
}
