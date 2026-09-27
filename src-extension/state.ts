import {
  buildShiftTimeline,
  DEFAULT_MONTHLY_WORKING_DAYS,
  DEFAULT_WORKDAYS,
  findEndedShiftOnEndCalendarDay,
  findNextShiftTimeline,
  getShiftEndAtMs,
  getShiftStartAtMs,
  isWorkday,
  type ShiftBuildOptions,
} from "@/lib/countdown";
import {
  defaultLocale,
  getBaseLanguage,
  locales,
  type Locale,
} from "@/i18n-config";

export const STORAGE_KEY = "doneat.popup.v1";

export interface Preferences {
  startTime: string;
  endTime: string;
  workdays: number[];
  lunchEnabled: boolean;
  lunchStartTime: string;
  lunchDurationMinutes: number;
  showSalary: boolean;
  salaryType: "monthly" | "daily";
  salaryAmount: string;
  monthlyWorkingDays: number;
  hideEarnings: boolean;
  running: boolean;
  lang: Locale;
}

export function preferredLocale(language: string): Locale {
  const locale = getBaseLanguage(language);
  return locales.includes(locale as Locale)
    ? (locale as Locale)
    : defaultLocale;
}

export function readPreferences(
  raw: string | null,
  language: string,
): Preferences {
  const defaults: Preferences = {
    startTime: "09:00",
    endTime: "18:00",
    workdays: [...DEFAULT_WORKDAYS],
    lunchEnabled: false,
    lunchStartTime: "12:00",
    lunchDurationMinutes: 60,
    showSalary: false,
    salaryType: "monthly",
    salaryAmount: "",
    monthlyWorkingDays: DEFAULT_MONTHLY_WORKING_DAYS,
    hideEarnings: false,
    running: false,
    lang: preferredLocale(language),
  };
  let saved: Record<string, unknown>;
  try {
    const value: unknown = JSON.parse(raw ?? "null");
    if (!value || typeof value !== "object" || Array.isArray(value))
      return defaults;
    saved = value as Record<string, unknown>;
  } catch {
    return defaults;
  }

  const result = { ...defaults };
  for (const key of ["startTime", "endTime", "lunchStartTime"] as const) {
    if (
      typeof saved[key] === "string" &&
      /^([01]\d|2[0-3]):[0-5]\d$/.test(saved[key])
    ) {
      result[key] = saved[key];
    }
  }
  for (const key of [
    "lunchEnabled",
    "showSalary",
    "hideEarnings",
    "running",
  ] as const) {
    if (typeof saved[key] === "boolean") result[key] = saved[key];
  }
  if (
    Array.isArray(saved.workdays) &&
    saved.workdays.every((day) => Number.isInteger(day) && day >= 0 && day <= 6)
  ) {
    result.workdays = [...new Set(saved.workdays)];
  }
  if (
    typeof saved.lunchDurationMinutes === "number" &&
    Number.isInteger(saved.lunchDurationMinutes) &&
    saved.lunchDurationMinutes > 0 &&
    saved.lunchDurationMinutes < 1440
  ) {
    result.lunchDurationMinutes = saved.lunchDurationMinutes;
  }
  if (
    typeof saved.monthlyWorkingDays === "number" &&
    saved.monthlyWorkingDays > 0 &&
    saved.monthlyWorkingDays <= 31
  ) {
    result.monthlyWorkingDays = saved.monthlyWorkingDays;
  }
  if (saved.salaryType === "daily") result.salaryType = "daily";
  if (
    typeof saved.salaryAmount === "string" &&
    saved.salaryAmount.length <= 24 &&
    Number.isFinite(Number(saved.salaryAmount)) &&
    Number(saved.salaryAmount) >= 0 &&
    Number(saved.salaryAmount) <= 999_999_999_999
  ) {
    result.salaryAmount = saved.salaryAmount;
  }
  if (typeof saved.lang === "string" && locales.includes(saved.lang as Locale))
    result.lang = saved.lang as Locale;
  if (result.startTime === result.endTime) result.running = false;
  return result;
}

export function breakOptions(preferences: Preferences): ShiftBuildOptions {
  return preferences.lunchEnabled
    ? {
        breakStartTime: preferences.lunchStartTime,
        breakDurationMinutes: preferences.lunchDurationMinutes,
      }
    : {};
}

// The popup has no background clock. Resolve from wall time every time it opens,
// using the same scheduling core as Desktop, including overnight/rest days.
export function resolvePopupShift(preferences: Preferences, nowMs: number) {
  if (
    preferences.startTime === preferences.endTime ||
    !preferences.workdays.length
  )
    return null;
  const options = breakOptions(preferences);
  const now = new Date(nowMs);
  const candidate = buildShiftTimeline(
    preferences.startTime,
    preferences.endTime,
    now,
    options,
  );
  const candidateWorks = isWorkday(
    new Date(getShiftStartAtMs(candidate)),
    preferences.workdays,
  );
  const next = findNextShiftTimeline({
    ...preferences,
    afterMs: nowMs,
    options,
  });
  if (
    candidateWorks &&
    getShiftStartAtMs(candidate) <= nowMs &&
    getShiftEndAtMs(candidate) > nowMs
  ) {
    return { shift: candidate, next };
  }
  const ended = findEndedShiftOnEndCalendarDay({
    ...preferences,
    nowMs,
    options,
  });
  const shift =
    ended ??
    (candidateWorks && getShiftStartAtMs(candidate) > nowMs ? candidate : next);
  return shift ? { shift, next } : null;
}
