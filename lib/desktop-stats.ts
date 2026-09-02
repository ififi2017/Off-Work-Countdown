const DATE_KEY = /^\d{4}-\d{2}-\d{2}$/;

/** 本地日历日。用 UTC 会让跨天时点在时区偏移处对不上用户的「今天」。 */
export function localDateKey(date = new Date()): string {
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${month}-${day}`;
}

export function monthKeyFromDateKey(dateKey: string): string {
  return dateKey.slice(0, 7);
}

export function shiftMonthKey(monthKey: string, delta: number): string {
  const [yearText, monthText] = monthKey.split("-");
  const year = Number(yearText);
  const month = Number(monthText);
  if (!Number.isInteger(year) || !Number.isInteger(month)) return monthKey;
  const next = new Date(year, month - 1 + delta, 1);
  return `${next.getFullYear()}-${String(next.getMonth() + 1).padStart(2, "0")}`;
}

export interface DesktopDayStats {
  attended: boolean;
  plannedMs: number;
  overtimeMs: number;
  woodfishCount: number;
}

export interface DesktopStatsState {
  days: Record<string, DesktopDayStats>;
}

export function emptyDesktopStats(): DesktopStatsState {
  return { days: {} };
}

function finiteNonNegative(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : 0;
}

function normalizeDay(value: unknown): DesktopDayStats | null {
  if (!value || typeof value !== "object") return null;
  const record = value as Partial<DesktopDayStats>;
  const plannedMs = finiteNonNegative(record.plannedMs);
  const overtimeMs = finiteNonNegative(record.overtimeMs);
  const woodfishCount = Math.floor(finiteNonNegative(record.woodfishCount));
  const attended = record.attended === true || plannedMs > 0 || overtimeMs > 0;
  if (!attended && woodfishCount <= 0) return null;
  return { attended, plannedMs, overtimeMs, woodfishCount };
}

export function normalizeDesktopStats(value: unknown): DesktopStatsState {
  const days: Record<string, DesktopDayStats> = {};
  const source =
    value && typeof value === "object" && "days" in value
      ? (value as { days?: unknown }).days
      : value;
  if (!source || typeof source !== "object") return { days };
  for (const [date, day] of Object.entries(source)) {
    if (!DATE_KEY.test(date)) continue;
    const normalized = normalizeDay(day);
    if (normalized) days[date] = normalized;
  }
  return { days };
}

export function recordAttendanceDay(
  stats: DesktopStatsState,
  input: { date: string; plannedMs: number; overtimeMs: number }
): DesktopStatsState {
  if (!DATE_KEY.test(input.date)) return stats;
  const plannedMs = finiteNonNegative(input.plannedMs);
  const overtimeMs = finiteNonNegative(input.overtimeMs);
  const existing = stats.days[input.date];
  return {
    days: {
      ...stats.days,
      [input.date]: {
        attended: true,
        plannedMs,
        overtimeMs,
        woodfishCount: existing?.woodfishCount ?? 0,
      },
    },
  };
}

export function setWoodfishDay(
  stats: DesktopStatsState,
  date: string,
  count: number
): DesktopStatsState {
  if (!DATE_KEY.test(date)) return stats;
  const woodfishCount = Math.max(0, Math.floor(finiteNonNegative(count)));
  const existing = stats.days[date];
  const nextCount = Math.max(existing?.woodfishCount ?? 0, woodfishCount);
  if (nextCount <= 0 && !existing?.attended) {
    if (!existing) return stats;
    const { [date]: _removed, ...days } = stats.days;
    return { days };
  }
  return {
    days: {
      ...stats.days,
      [date]: {
        attended: existing?.attended ?? false,
        plannedMs: existing?.plannedMs ?? 0,
        overtimeMs: existing?.overtimeMs ?? 0,
        woodfishCount: nextCount,
      },
    },
  };
}

export function mergeWoodfishSeed(
  stats: DesktopStatsState,
  date: string,
  count: number
): DesktopStatsState {
  return setWoodfishDay(stats, date, count);
}

export function workedMsForDay(day: DesktopDayStats): number {
  if (!day.attended) return 0;
  return day.plannedMs + day.overtimeMs;
}

export interface DesktopMonthSummary {
  monthKey: string;
  daysWorked: number;
  workedMs: number;
  woodfishCount: number;
  days: Array<{ date: string } & DesktopDayStats>;
}

export function summarizeMonth(
  stats: DesktopStatsState,
  monthKey: string
): DesktopMonthSummary {
  const days = Object.entries(stats.days)
    .filter(([date]) => monthKeyFromDateKey(date) === monthKey)
    .map(([date, day]) => ({ date, ...day }))
    .sort((left, right) => (left.date < right.date ? 1 : -1));

  return {
    monthKey,
    daysWorked: days.filter((day) => day.attended).length,
    workedMs: days.reduce((total, day) => total + workedMsForDay(day), 0),
    woodfishCount: days.reduce((total, day) => total + day.woodfishCount, 0),
    days,
  };
}

export function recordedMonthKeys(
  stats: DesktopStatsState,
  today = new Date()
): string[] {
  const current = monthKeyFromDateKey(localDateKey(today));
  const months = new Set(
    Object.keys(stats.days).map((date) => monthKeyFromDateKey(date))
  );
  months.add(current);
  return [...months].sort();
}

export function neighboringMonthKey(
  monthKey: string,
  delta: number,
  stats: DesktopStatsState,
  today = new Date()
): string | null {
  const months = recordedMonthKeys(stats, today);
  const index = months.indexOf(monthKey);
  const nextIndex = index + delta;
  if (index < 0 || nextIndex < 0 || nextIndex >= months.length) return null;
  return months[nextIndex];
}

export function clampMonthKey(
  monthKey: string,
  stats: DesktopStatsState,
  today = new Date()
): string {
  const months = recordedMonthKeys(stats, today);
  if (months.includes(monthKey)) return monthKey;
  return months[months.length - 1];
}

export function canShiftMonth(
  monthKey: string,
  delta: number,
  stats: DesktopStatsState,
  today = new Date()
): boolean {
  return neighboringMonthKey(monthKey, delta, stats, today) !== null;
}

export function formatWoodfishCountLabel(count: number): string {
  return String(Math.max(0, Math.floor(count)));
}

export function formatStatsDuration(ms: number, lang: string): string {
  const totalMinutes = Math.max(0, Math.round(ms / 60_000));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  const make = (options: Intl.NumberFormatOptions) => {
    try {
      return new Intl.NumberFormat(lang, options);
    } catch {
      return new Intl.NumberFormat(undefined, options);
    }
  };
  const hoursFmt = make({
    style: "unit",
    unit: "hour",
    unitDisplay: "short",
    maximumFractionDigits: 0,
  });
  const minutesFmt = make({
    style: "unit",
    unit: "minute",
    unitDisplay: "short",
    maximumFractionDigits: 0,
  });
  if (hours === 0) return minutesFmt.format(minutes);
  if (minutes === 0) return hoursFmt.format(hours);
  return `${hoursFmt.format(hours)} ${minutesFmt.format(minutes)}`;
}
