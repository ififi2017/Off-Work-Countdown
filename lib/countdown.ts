// Pure countdown/salary helpers, kept framework-free so they can be unit tested.

function addCalendarDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

// Build a Date on the same day as `base` at the given "HH:mm" time.
// Avoids `new Date(string)` parsing, which is inconsistent across browsers (notably Safari).
export function atTime(base: Date, time: string): Date {
  const [hours, minutes] = time.split(":").map(Number);
  const d = new Date(base);
  d.setHours(hours, minutes, 0, 0);
  return d;
}

export interface ShiftBounds {
  start: Date;
  end: Date;
}

/**
 * 一段连续的有效工作时间。所有值都是 Unix 毫秒时间戳，方便前端计算后原样
 * 写入 Tauri Store；Rust 只消费这些绝对时间戳，不重新解释班次规则。
 */
export interface ShiftSegment {
  startAtMs: number;
  endAtMs: number;
}

/**
 * 3.1 起的班次核心模型。
 *
 * `plannedEndAtMs` 保留原定下班时间；发生加班时 `overtimeEndAtMs` 才有值，
 * segments 的最后一段则延伸到实际结束时间。午休等非工作时间不出现在 segments
 * 中，因此剩余时间、进度和薪资天然使用同一套有效工时口径。
 */
export interface ShiftTimeline {
  segments: ShiftSegment[];
  plannedEndAtMs: number;
  overtimeEndAtMs: number | null;
}

// Resolve the concrete start/end of the shift containing (or nearest to) `now`.
// Overnight shifts (end <= start, e.g. 22:00–06:00) are anchored so that a
// time after midnight still belongs to the shift that started the day before.
export function getShiftBounds(
  startTime: string,
  endTime: string,
  now: Date
): ShiftBounds {
  let start = atTime(now, startTime);
  let end = atTime(now, endTime);

  if (end <= start) {
    if (now < end) {
      // e.g. 01:00 during a 22:00–06:00 shift: it started yesterday
      start = addCalendarDays(start, -1);
    } else {
      end = addCalendarDays(end, 1);
    }
  }

  return { start, end };
}

export interface ShiftBuildOptions {
  breakStartTime?: string | null;
  breakDurationMinutes?: number;
  overtimeEndAtMs?: number | null;
}

export type WorkScheduleMode = "classic" | "alternating" | "rotation" | "off";

/**
 * Mobile schedule configuration. Dates are local calendar anchors represented
 * as Unix milliseconds; callers must not advance them by fixed 24-hour spans.
 */
export interface WorkScheduleConfig {
  mode: WorkScheduleMode;
  referenceWeekStartMs?: number | null;
  referenceWeekType?: "single" | "double";
  singleWeekendWorkday?: 0 | 6;
  rotationAnchorMs?: number | null;
  rotationWorkDays?: number;
  rotationRestDays?: number;
}

function localDay(date: Date): Date {
  const day = new Date(date);
  day.setHours(0, 0, 0, 0);
  return day;
}

function localWeekStart(date: Date): Date {
  const day = localDay(date);
  day.setDate(day.getDate() - ((day.getDay() + 6) % 7));
  return day;
}

function calendarDayDifference(from: Date, to: Date): number {
  // Date.UTC over local Y/M/D components avoids DST making a calendar day 23
  // or 25 hours long.
  const fromUTC = Date.UTC(from.getFullYear(), from.getMonth(), from.getDate());
  const toUTC = Date.UTC(to.getFullYear(), to.getMonth(), to.getDate());
  return Math.round((toUTC - fromUTC) / 86_400_000);
}

/** Resolve all supported work patterns without duplicating them in Swift. */
export function isScheduledWorkday(
  shiftStart: Date,
  workdays: number[],
  schedule?: WorkScheduleConfig | null
): boolean {
  const mode = schedule?.mode ?? "classic";
  if (mode === "off") return true;
  if (mode === "classic") return isWorkday(shiftStart, workdays);

  if (mode === "alternating") {
    const weekday = shiftStart.getDay();
    if (weekday >= 1 && weekday <= 5) return true;
    const anchor = localWeekStart(
      new Date(schedule?.referenceWeekStartMs ?? shiftStart.getTime())
    );
    const week = localWeekStart(shiftStart);
    const weeksFromAnchor = Math.floor(calendarDayDifference(anchor, week) / 7);
    const anchorIsSingle = schedule?.referenceWeekType === "single";
    const isSingleWeek = Math.abs(weeksFromAnchor) % 2 === 0
      ? anchorIsSingle
      : !anchorIsSingle;
    return isSingleWeek && weekday === (schedule?.singleWeekendWorkday ?? 6);
  }

  const workLength = Math.max(1, Math.floor(schedule?.rotationWorkDays ?? 1));
  const restLength = Math.max(1, Math.floor(schedule?.rotationRestDays ?? 1));
  const anchor = localDay(
    new Date(schedule?.rotationAnchorMs ?? shiftStart.getTime())
  );
  const offset = calendarDayDifference(anchor, localDay(shiftStart));
  const cycleLength = workLength + restLength;
  const cycleDay = ((offset % cycleLength) + cycleLength) % cycleLength;
  return cycleDay < workLength;
}

export function findNextRestDate(params: {
  afterMs: number;
  workdays: number[];
  schedule?: WorkScheduleConfig | null;
}): Date | null {
  const { afterMs, workdays, schedule } = params;
  if (schedule?.mode === "off") return null;
  const cursor = localDay(new Date(afterMs));
  for (let offset = 0; offset <= 366; offset += 1) {
    const day = addCalendarDays(cursor, offset);
    if (!isScheduledWorkday(day, workdays, schedule)) return day;
  }
  return null;
}

function buildTimelineFromBounds(
  start: Date,
  end: Date,
  options: ShiftBuildOptions
): ShiftTimeline {
  const plannedEndAtMs = end.getTime();
  let segments: ShiftSegment[] = [
    { startAtMs: start.getTime(), endAtMs: plannedEndAtMs },
  ];

  const breakDurationMs = Math.floor(options.breakDurationMinutes ?? 0) * 60_000;
  if (options.breakStartTime && breakDurationMs > 0) {
    let breakStart = atTime(start, options.breakStartTime);
    if (breakStart < start) breakStart = addCalendarDays(breakStart, 1);
    const breakStartAtMs = breakStart.getTime();
    const breakEndAtMs = breakStartAtMs + breakDurationMs;
    if (
      breakStartAtMs > start.getTime() &&
      breakEndAtMs < plannedEndAtMs
    ) {
      segments = [
        { startAtMs: start.getTime(), endAtMs: breakStartAtMs },
        { startAtMs: breakEndAtMs, endAtMs: plannedEndAtMs },
      ];
    }
  }

  const overtimeEndAtMs =
    options.overtimeEndAtMs && options.overtimeEndAtMs > plannedEndAtMs
      ? options.overtimeEndAtMs
      : null;
  if (overtimeEndAtMs !== null) {
    segments = segments.map((segment, index) =>
      index === segments.length - 1
        ? { ...segment, endAtMs: overtimeEndAtMs }
        : segment
    );
  }

  return { segments, plannedEndAtMs, overtimeEndAtMs };
}

/** 将开始/结束设置解析为分段班次。未提供选项时保持 3.0 的单段行为。 */
export function buildShiftTimeline(
  startTime: string,
  endTime: string,
  now: Date,
  options: ShiftBuildOptions = {}
): ShiftTimeline {
  const { start, end } = getShiftBounds(startTime, endTime, now);
  return buildTimelineFromBounds(start, end, options);
}

export function extendShiftWithOvertime(
  shift: ShiftTimeline,
  overtimeEndAtMs: number
): ShiftTimeline {
  if (!isValidShiftTimeline(shift) || overtimeEndAtMs <= shift.plannedEndAtMs) {
    return shift;
  }
  return {
    ...shift,
    segments: shift.segments.map((segment, index) =>
      index === shift.segments.length - 1
        ? { ...segment, endAtMs: overtimeEndAtMs }
        : segment
    ),
    overtimeEndAtMs,
  };
}

export function suggestOvertimeEndAtMs(
  shift: ShiftTimeline,
  nowMs: number
): number {
  if (shift.overtimeEndAtMs && shift.overtimeEndAtMs > nowMs) {
    return shift.overtimeEndAtMs;
  }
  const raw = Math.max(shift.plannedEndAtMs, nowMs) + 60 * 60 * 1000;
  return Math.ceil(raw / (15 * 60 * 1000)) * 15 * 60 * 1000;
}

export function resolveOvertimeEndAtMs(
  shift: ShiftTimeline,
  overtimeEndTime: string,
  nowMs: number
): number | null {
  // 先以原定下班日解释钟点：小于原定下班时间的选择表示跨到次日，例如
  // 18:00 下班后加班到 01:00。若这样解析后仍早于“现在”，它就是已经过去的
  // 时间，不能再偷偷多加一天——否则 19:00 时误选 18:30 会变成近 24 小时加班。
  let resolved = atTime(new Date(shift.plannedEndAtMs), overtimeEndTime);
  if (resolved.getTime() < shift.plannedEndAtMs) {
    resolved = addCalendarDays(resolved, 1);
  }
  const resolvedAtMs = resolved.getTime();
  return resolvedAtMs > Math.max(nowMs, shift.plannedEndAtMs)
    ? resolvedAtMs
    : null;
}

/**
 * The shift that still belongs on `now`'s calendar day after live bounds have
 * jumped. `getShiftBounds` uses the planned `endTime`, so a Monday 09:00–17:00
 * run that overtime'd to Tuesday 01:00 looks like Tuesday's 09:00 window at
 * 01:30; a Friday 22:00–Saturday 06:00 run looks like Saturday night after 06:00.
 *
 * Uses each candidate's effective end (`getShiftEndAtMs`), so overtime that
 * crosses midnight still settles on the end calendar day. Callers should ignore
 * a result whose start matches the live snapshot. Live windows that have
 * already opened win at the call site (`liveIsOpen`).
 */
export function findEndedShiftOnEndCalendarDay(params: {
  startTime: string;
  endTime: string;
  nowMs: number;
  workdays: number[];
  schedule?: WorkScheduleConfig | null;
  options?: ShiftBuildOptions;
  /** Midnight of a start calendar day that counts as work even if the pattern says rest. */
  forcedWorkdayStartMs?: number | null;
}): ShiftTimeline | null {
  const now = new Date(params.nowMs);
  const today = localDay(now);
  const options = params.options ?? {};
  const forcedMs = params.forcedWorkdayStartMs;
  const forcedDay =
    typeof forcedMs === "number" && Number.isFinite(forcedMs)
      ? localDay(new Date(forcedMs)).getTime()
      : null;

  const startIsWorkday = (start: Date) =>
    isScheduledWorkday(start, params.workdays, params.schedule) ||
    (forcedDay != null && localDay(start).getTime() === forcedDay);

  // Today, yesterday, and the day before: a day shift plus overtime past
  // midnight, or an overnight then extended another night, both land here.
  for (let offset = 0; offset <= 2; offset += 1) {
    const day = addCalendarDays(today, -offset);
    const start = atTime(day, params.startTime);
    let end = atTime(day, params.endTime);
    if (end.getTime() <= start.getTime()) {
      end = addCalendarDays(end, 1);
    }
    if (!startIsWorkday(start)) continue;
    const timeline = buildTimelineFromBounds(start, end, options);
    const startAtMs = getShiftStartAtMs(timeline);
    const endAtMs = getShiftEndAtMs(timeline);
    if (params.nowMs >= startAtMs && params.nowMs < endAtMs) {
      return timeline;
    }
    if (
      params.nowMs >= endAtMs &&
      localDay(new Date(endAtMs)).getTime() === today.getTime()
    ) {
      return timeline;
    }
  }
  return null;
}

export function findNextShiftTimeline(params: {
  startTime: string;
  endTime: string;
  workdays: number[];
  afterMs: number;
  schedule?: WorkScheduleConfig | null;
  options?: Omit<ShiftBuildOptions, "overtimeEndAtMs">;
}): ShiftTimeline | null {
  const { startTime, endTime, workdays, afterMs, schedule, options = {} } = params;
  if (schedule?.mode === "off") return null;
  if ((schedule?.mode ?? "classic") === "classic" && workdays.length === 0) return null;

  const cursor = new Date(afterMs);
  cursor.setHours(0, 0, 0, 0);
  for (let offset = 0; offset <= 366; offset += 1) {
    const day = addCalendarDays(cursor, offset);
    const start = atTime(day, startTime);
    if (!isScheduledWorkday(start, workdays, schedule) || start.getTime() <= afterMs) {
      continue;
    }
    let end = atTime(day, endTime);
    if (end <= start) end = addCalendarDays(end, 1);
    return buildTimelineFromBounds(start, end, options);
  }
  return null;
}

export function getShiftEndAtMs(shift: ShiftTimeline): number {
  return shift.overtimeEndAtMs ?? shift.plannedEndAtMs;
}

export function getShiftStartAtMs(shift: ShiftTimeline): number {
  return shift.segments[0]?.startAtMs ?? 0;
}

/**
 * 校验一个已经解析好的班次快照。这里不修补或重排输入，避免错误状态被静默
 * 接受后让前端与原生端产生不同结果。
 */
export function isValidShiftTimeline(shift: ShiftTimeline): boolean {
  if (shift.segments.length === 0) return false;
  if (!Number.isFinite(shift.plannedEndAtMs)) return false;
  if (
    shift.overtimeEndAtMs !== null &&
    (!Number.isFinite(shift.overtimeEndAtMs) ||
      shift.overtimeEndAtMs <= shift.plannedEndAtMs)
  ) {
    return false;
  }

  let previousEnd = Number.NEGATIVE_INFINITY;
  for (const segment of shift.segments) {
    if (
      !Number.isFinite(segment.startAtMs) ||
      !Number.isFinite(segment.endAtMs) ||
      segment.endAtMs <= segment.startAtMs ||
      segment.startAtMs < previousEnd
    ) {
      return false;
    }
    previousEnd = segment.endAtMs;
  }

  const startAtMs = getShiftStartAtMs(shift);
  const endAtMs = getShiftEndAtMs(shift);
  const lastSegment = shift.segments[shift.segments.length - 1];
  return (
    shift.plannedEndAtMs > startAtMs &&
    shift.plannedEndAtMs > lastSegment.startAtMs &&
    shift.plannedEndAtMs <= lastSegment.endAtMs &&
    endAtMs === shift.segments[shift.segments.length - 1].endAtMs
  );
}

/** 班次包含的有效工作时长；午休等 segments 间隙不计入。 */
export function getShiftDurationMs(shift: ShiftTimeline): number {
  if (!isValidShiftTimeline(shift)) return 0;
  return shift.segments.reduce(
    (total, segment) => total + segment.endAtMs - segment.startAtMs,
    0
  );
}

/** 原定班次的有效工时。加班延长最后一个 segment 后仍以 plannedEnd 为界截断。 */
export function getPlannedShiftDurationMs(shift: ShiftTimeline): number {
  if (!isValidShiftTimeline(shift)) return 0;
  return shift.segments.reduce((total, segment) => {
    const endAtMs = Math.min(segment.endAtMs, shift.plannedEndAtMs);
    return total + Math.max(0, endAtMs - segment.startAtMs);
  }, 0);
}

/** 截止某时刻已经过去的有效工作时长；位于间隙时数值保持不变。 */
export function getShiftElapsedMs(
  shift: ShiftTimeline,
  nowMs: number
): number {
  if (!isValidShiftTimeline(shift)) return 0;
  return shift.segments.reduce((total, segment) => {
    const duration = segment.endAtMs - segment.startAtMs;
    const elapsed = Math.min(duration, Math.max(0, nowMs - segment.startAtMs));
    return total + elapsed;
  }, 0);
}

/**
 * 当前时刻若落在两个 segment 之间的休息区间，返回该区间的结束时间；否则返回 null。
 *
 * 休息区间是 segments 之间的空隙——午休本来就不进 segments，所以这里不需要
 * 知道「午休」这个业务概念，只看时间轴上的洞。
 */
export function getActiveBreakEndAtMs(
  shift: ShiftTimeline,
  nowMs: number
): number | null {
  for (let index = 0; index < shift.segments.length - 1; index += 1) {
    const gapStart = shift.segments[index].endAtMs;
    const gapEnd = shift.segments[index + 1].startAtMs;
    if (gapEnd > gapStart && nowMs >= gapStart && nowMs < gapEnd) {
      return gapEnd;
    }
  }
  return null;
}

export function getShiftRemainingMs(
  shift: ShiftTimeline,
  nowMs: number
): number {
  return Math.max(
    0,
    getShiftDurationMs(shift) - getShiftElapsedMs(shift, nowMs)
  );
}

export function calculateTimelineProgress(
  shift: ShiftTimeline,
  nowMs: number
): number {
  const duration = getShiftDurationMs(shift);
  if (duration <= 0) return 0;
  return Math.max(
    0,
    Math.min(100, (getShiftElapsedMs(shift, nowMs) / duration) * 100)
  );
}

/**
 * 按原时薪线性外推的计薪比例。正常班次结束为 1；发生加班时可以大于 1。
 * 午休不在 segments 内，所以休息期间 elapsed 保持不变。
 */
export function calculateTimelinePayRatio(
  shift: ShiftTimeline,
  nowMs: number
): number {
  const plannedDuration = getPlannedShiftDurationMs(shift);
  if (plannedDuration <= 0) return 0;
  return Math.max(0, getShiftElapsedMs(shift, nowMs) / plannedDuration);
}

// Percentage of the shift already worked, clamped to [0, 100].
export function calculateProgress(
  startTime: string,
  endTime: string,
  now: Date
): number {
  return calculateTimelineProgress(
    buildShiftTimeline(startTime, endTime, now),
    now.getTime()
  );
}

// 班次时长（小时）。跨零点的班次按次日结束计算，与 getShiftBounds 的口径一致。
// 与具体日期无关，因此不需要 `now`——预设页在构建期就要算出每日/每周工时。
export function getShiftLengthHours(startTime: string, endTime: string): number {
  const [sh, sm] = startTime.split(":").map(Number);
  const [eh, em] = endTime.split(":").map(Number);
  let minutes = eh * 60 + em - (sh * 60 + sm);
  if (minutes <= 0) minutes += 24 * 60;
  return minutes / 60;
}

// 工作日。用 JS 的 getDay() 口径：0 = 周日，6 = 周六。默认周一至周五。
export const DEFAULT_WORKDAYS = [1, 2, 3, 4, 5];

export function serializeWorkdays(days: number[]): string {
  return [...new Set(days)].filter((d) => d >= 0 && d <= 6).sort().join(",");
}

// 解析存储值。空字符串是合法输入，表示「一天都不上班」，必须与「没存过」
// 区分开——后者才回落到默认值。
export function parseWorkdays(raw: string | null | undefined): number[] {
  if (raw === null || raw === undefined) return DEFAULT_WORKDAYS;
  if (raw.trim() === "") return [];
  const parsed = raw
    .split(",")
    .map((s) => Number(s.trim()))
    .filter((n) => Number.isInteger(n) && n >= 0 && n <= 6);
  return [...new Set(parsed)].sort();
}

/**
 * 判断某个班次是否落在工作日。
 *
 * 注意传入的应当是班次的**开始时刻**而非「现在」：22:00–06:00 的夜班，
 * 凌晨两点时「今天」已经是周六，但这一班属于周五。用 getShiftBounds 解析出
 * 的 start 判断才符合直觉。
 */
export function isWorkday(shiftStart: Date, workdays: number[]): boolean {
  return workdays.includes(shiftStart.getDay());
}

export const DEFAULT_MONTHLY_WORKING_DAYS = 21.75;

export function getDailySalary(
  amount: string,
  type: "monthly" | "daily",
  monthlyWorkingDays: number = DEFAULT_MONTHLY_WORKING_DAYS,
  annualBonusMonths: number = 0
): number | null {
  if (!amount.trim()) return null;
  const parsed = Number(amount);
  if (!Number.isFinite(parsed) || parsed < 0) return null;
  if (!Number.isFinite(annualBonusMonths) || annualBonusMonths < 0) {
    return null;
  }
  const annualizedMultiplier = 1 + annualBonusMonths / 12;
  if (type === "daily") return parsed * annualizedMultiplier;
  if (
    !Number.isFinite(monthlyWorkingDays) ||
    monthlyWorkingDays <= 0 ||
    monthlyWorkingDays > 31
  ) {
    return null;
  }
  return (parsed / monthlyWorkingDays) * annualizedMultiplier;
}

export interface ScheduleDayExpansion {
  dayKey: string;
  shiftAnchorStartAtMs: number;
  isWorkday: boolean;
  segments: ShiftSegment[];
}

function localDayKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/**
 * Expand every local calendar day in `[fromMs, throughMs]` through the shared
 * shift rules. Rest days still carry the planned segments so a makeup-day
 * exception can reuse them. Callers must not pass overtime or salary.
 *
 * Noon is the probe time so an overnight 22:00–06:00 shift keys as that
 * calendar day's start, not the previous night.
 */
export function expandScheduleRange(params: {
  startTime: string;
  endTime: string;
  workdays: number[];
  schedule?: WorkScheduleConfig | null;
  breakStartTime?: string | null;
  breakDurationMinutes?: number;
  fromMs: number;
  throughMs: number;
}): ScheduleDayExpansion[] {
  const from = localDay(new Date(params.fromMs));
  const through = localDay(new Date(params.throughMs));
  if (through < from) return [];

  const options: ShiftBuildOptions = {
    breakStartTime: params.breakStartTime ?? null,
    breakDurationMinutes: params.breakDurationMinutes ?? 0,
  };
  const days: ScheduleDayExpansion[] = [];
  for (let day = new Date(from); day <= through; day = addCalendarDays(day, 1)) {
    const noon = new Date(day);
    noon.setHours(12, 0, 0, 0);
    const timeline = buildShiftTimeline(
      params.startTime,
      params.endTime,
      noon,
      options
    );
    const shiftAnchorStartAtMs = getShiftStartAtMs(timeline);
    const shiftStart = new Date(shiftAnchorStartAtMs);
    days.push({
      dayKey: localDayKey(shiftStart),
      shiftAnchorStartAtMs,
      isWorkday: isScheduledWorkday(
        shiftStart,
        params.workdays,
        params.schedule
      ),
      segments: timeline.segments,
    });
  }
  return days;
}
