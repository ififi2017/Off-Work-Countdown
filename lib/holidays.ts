// National holiday calendars for the desktop schedule, from the same bundled
// dataset as iOS HolidayCalendar.swift (split per region by
// scripts/generate-desktop-holidays.mjs). Plans store only the region; the
// day-by-day overrides are attached when resolving, never persisted, so an app
// update with new data takes effect without rewriting anyone's schedule.

export interface HolidayIndex {
  datasetVersion: string;
  /** Region code → [first covered year, last covered year]. */
  regions: Record<string, [number, number]>;
}

export interface HolidayRegion {
  datasetVersion: string;
  coveredFromYear: number;
  coveredThroughYear: number;
  /** Localized names, keyed like public/locales. */
  names: Record<string, string>[];
  /** YYYYMMDD → [1 for a makeup workday / 0 for a day off, name index]. */
  days: Record<string, [0 | 1, number]>;
}

export interface HolidayDay {
  isWorkday: boolean;
  name: string;
}

const cache = new Map<string, Promise<unknown>>();

function load<T>(path: string): Promise<T | null> {
  if (!cache.has(path)) {
    cache.set(path, fetch(path).then((response) => (response.ok ? response.json() : null)).catch(() => null));
  }
  return cache.get(path) as Promise<T | null>;
}

export function loadHolidayIndex(): Promise<HolidayIndex | null> {
  return load<HolidayIndex>("/holidays/index.json");
}

export function loadHolidayRegion(region: string): Promise<HolidayRegion | null> {
  return /^[A-Z]{2}$/.test(region) ? load<HolidayRegion>(`/holidays/${region}.json`) : Promise.resolve(null);
}

/** The overrides the shared resolver reads, keyed YYYYMMDD. */
export function holidayOverrides(region: HolidayRegion): Record<string, boolean> {
  return Object.fromEntries(Object.entries(region.days).map(([date, [work]]) => [date, work === 1]));
}

/** Matches HolidayCalendar.Day.name(language:): exact, language only, then English. */
export function holidayDay(region: HolidayRegion | null, dayKey: string, lang: string): HolidayDay | null {
  const entry = region?.days[dayKey.replaceAll("-", "")];
  if (!entry) return null;
  const names = region!.names[entry[1]] ?? {};
  const name = names[lang] ?? names[lang.slice(0, 2)] ?? names.en ?? Object.values(names)[0] ?? "";
  return { isWorkday: entry[0] === 1, name };
}

/** The coverage note iOS shows under a month, if any. */
export function holidayCoverageWarning(
  region: Pick<HolidayRegion, "coveredFromYear" | "coveredThroughYear"> | null,
  year: number,
  month: number,
): { key: "holidayCoverageYearWarning" | "holidayCoverageNextYearWarning"; year: number } | null {
  if (!region) return null;
  const covers = (y: number) => y >= region.coveredFromYear && y <= region.coveredThroughYear;
  if (!covers(year)) return { key: "holidayCoverageYearWarning", year };
  if (month === 12 && !covers(year + 1)) return { key: "holidayCoverageNextYearWarning", year: year + 1 };
  return null;
}

/** The region of the system locale, when the dataset has it. */
export function suggestedHolidayRegion(index: HolidayIndex | null, locale: string): string | null {
  try {
    const region = new Intl.Locale(locale).maximize().region;
    return region && index?.regions[region] ? region : null;
  } catch {
    return null;
  }
}

/** iOS keeps the Traditional Chinese name for TW tied to the app language. */
export function holidayRegionName(region: string, lang: string): string {
  if (region === "TW" && (lang === "zh-TW" || lang === "zh-HK")) return "台灣";
  try {
    return new Intl.DisplayNames([lang], { type: "region" }).of(region) ?? region;
  } catch {
    return region;
  }
}
