/**
 * Formatting for the iPhone screens.
 *
 * Times the user typed (09:00) stay in the 24-hour form they were entered and
 * stored in, matching the pickers. Durations and counts go through `Intl` so
 * plurals, decimal separators and unit spelling come from the locale instead of
 * from 19 hand-written strings.
 */

const HOUR_MS = 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

/** `HH:MM` for a timestamp, in the same form the shift settings use. */
export function clockAt(atMs: number): string {
  const date = new Date(atMs);
  return `${date.getHours().toString().padStart(2, "0")}:${date
    .getMinutes()
    .toString()
    .padStart(2, "0")}`;
}

/** Interpolation values for the `timeLeft` string. */
export type DurationParts = {
  [part in "hours" | "minutes" | "seconds"]: string;
};

/**
 * Split a duration for the `timeLeft` string.
 *
 * `padHours` follows the shift length rather than the current value, so the
 * digits do not jump a column when the countdown crosses ten hours.
 */
export function durationParts(
  durationMs: number,
  padHours: boolean
): DurationParts {
  const total = Math.max(0, durationMs);
  const hours = Math.floor(total / HOUR_MS);
  const minutes = Math.floor((total % HOUR_MS) / MINUTE_MS);
  const seconds = Math.floor((total % MINUTE_MS) / 1000);
  return {
    hours: padHours ? hours.toString().padStart(2, "0") : hours.toString(),
    minutes: minutes.toString().padStart(2, "0"),
    seconds: seconds.toString().padStart(2, "0"),
  };
}

function unitFormatter(
  lang: string,
  unit: "hour" | "minute" | "day",
  maximumFractionDigits = 0
): Intl.NumberFormat {
  const options: Intl.NumberFormatOptions = {
    style: "unit",
    unit,
    unitDisplay: "short",
    maximumFractionDigits,
  };
  try {
    return new Intl.NumberFormat(lang, options);
  } catch {
    return new Intl.NumberFormat(undefined, options);
  }
}

/**
 * A duration in words, rounded up to the minute: "2 hr 13 min", "45 min".
 * Used where the exact second is noise — "in 33 min", "1 h lunch".
 */
export function approximateDuration(lang: string, durationMs: number): string {
  const totalMinutes = Math.max(0, Math.ceil(durationMs / MINUTE_MS));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  const parts: string[] = [];
  if (hours > 0) parts.push(unitFormatter(lang, "hour").format(hours));
  if (minutes > 0 || hours === 0) {
    parts.push(unitFormatter(lang, "minute").format(minutes));
  }
  return parts.join(" ");
}

/** Shift lengths need the half hour; period totals do not. */
export function formatHours(lang: string, hours: number, digits = 1): string {
  return unitFormatter(lang, "hour", digits).format(hours);
}

export function formatDays(lang: string, days: number): string {
  return unitFormatter(lang, "day", 1).format(days);
}

export function formatMinutes(lang: string, minutes: number): string {
  return unitFormatter(lang, "minute").format(minutes);
}

export function formatMoney(lang: string, amount: number, precise = false): string {
  const options: Intl.NumberFormatOptions = precise
    ? { minimumFractionDigits: 2, maximumFractionDigits: 2 }
    : { maximumFractionDigits: 0 };
  try {
    return new Intl.NumberFormat(lang, options).format(amount);
  } catch {
    return new Intl.NumberFormat(undefined, options).format(amount);
  }
}

/** Short weekday names in the locale, indexed the way `Date.getDay()` is. */
export function weekdayNames(lang: string): string[] {
  const format = (() => {
    try {
      return new Intl.DateTimeFormat(lang, { weekday: "short" });
    } catch {
      return new Intl.DateTimeFormat(undefined, { weekday: "short" });
    }
  })();
  // 2024-01-07 is a Sunday, so offsetting by the weekday index lands on it.
  return Array.from({ length: 7 }, (_, day) =>
    format.format(new Date(2024, 0, 7 + day))
  );
}

/** Monday-first order, matching the workday grid and the week summary. */
export const WEEKDAY_ORDER = [1, 2, 3, 4, 5, 6, 0];

/**
 * "Mon – Fri" when the workdays are one unbroken Monday-first run, otherwise
 * the days listed. Empty when nothing is selected.
 */
export function describeWorkdays(lang: string, workdays: number[]): string {
  const names = weekdayNames(lang);
  const selected = WEEKDAY_ORDER.filter((day) => workdays.includes(day));
  if (selected.length === 0) return "";
  if (selected.length === 1) return names[selected[0]];

  const firstIndex = WEEKDAY_ORDER.indexOf(selected[0]);
  const isRun = selected.every(
    (day, index) => WEEKDAY_ORDER[firstIndex + index] === day
  );
  if (isRun) {
    return `${names[selected[0]]} – ${names[selected[selected.length - 1]]}`;
  }
  return selected.map((day) => names[day]).join(" · ");
}

/**
 * "Tomorrow" only when it really is tomorrow; otherwise the weekday.
 *
 * A Friday evening shows the next shift on Monday — calling that "tomorrow"
 * because it is simply the next one would be wrong.
 */
export function relativeDayLabel(
  lang: string,
  atMs: number,
  nowMs: number,
  tomorrowLabel: string
): string {
  const target = new Date(atMs);
  const today = new Date(nowMs);
  const startOfDay = (date: Date) =>
    new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const days = Math.round(
    (startOfDay(target) - startOfDay(today)) / (24 * 60 * 60 * 1000)
  );
  if (days === 1) return tomorrowLabel;
  try {
    return new Intl.DateTimeFormat(lang, { weekday: "long" }).format(target);
  } catch {
    return new Intl.DateTimeFormat(undefined, { weekday: "long" }).format(target);
  }
}
