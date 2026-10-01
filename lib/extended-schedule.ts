// The same cycle/roster model as iOS Shared/ExtendedSchedule.swift and Android.
// Resolution supplies civil clock readings; countdown.ts builds the timeline.
/** Inclusive month/day bounds repeating every year; an end before the start crosses New Year. */
export interface AnnualShiftDateRange {
  startMonth: number;
  startDay: number;
  endMonth: number;
  endDay: number;
}

export interface ShiftType {
  id: string;
  name: string;
  kind: "work" | "rest";
  startMinutes: number;
  endMinutes: number;
  breakEnabled: boolean;
  breakStartMinutes: number;
  breakDurationMinutes: number;
  colorHex: string;
  isArchived: boolean;
  /** Replaces the pattern's work hours during these dates each year (iOS). */
  annualDateRange?: AnnualShiftDateRange | null;
}

export interface ShiftCycleRule {
  preset: "weekly" | "alternatingWeeks" | "rotation" | "custom";
  anchorDayKey: string;
  days: string[];
}

export interface ExtendedSchedulePlan {
  shiftTypes: ShiftType[];
  rule: ShiftCycleRule | null;
  handSetDays: Record<string, string>;
  frozenShiftTypes?: Record<string, ShiftType>;
  clearedFromDayKey?: string | null;
  fallsBackToBaseSchedule?: boolean;
  holidayOverrides?: Record<string, boolean> | null;
  holidayRegionIdentifier?: string | null;
  pinnedDayKey?: string | null;
}

export interface ScheduleDay {
  isWorkday: boolean;
  hours: { startTime: string; endTime: string; breakStartTime: string | null; breakDurationMinutes: number } | null;
  shiftTypeID: string | null;
  source: "handSet" | "rule" | "annualRange" | "carriedOver" | "holiday" | "unassigned";
}

const unassigned: ScheduleDay = { isWorkday: false, hours: null, shiftTypeID: null, source: "unassigned" };

export function civilDayNumber(key: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return null;
  const [year, month, day] = key.split("-").map(Number);
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(0, 0, 0, 0);
  return year >= 1 && year <= 9999 && date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
    ? date.getTime() / 86_400_000 : null;
}

export function minutesTime(minutes: number): string {
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

const graphemes = typeof Intl.Segmenter === "function" ? new Intl.Segmenter(undefined, { granularity: "grapheme" }) : null;

// February 29 is valid and applies only in years that have it (checked against 2000).
function isValidMonthDay(month: number, day: number): boolean {
  if (!Number.isInteger(month) || !Number.isInteger(day) || month < 1 || month > 12 || day < 1) return false;
  return day <= new Date(Date.UTC(2000, month, 0)).getUTCDate();
}

export function isValidAnnualRange(range: AnnualShiftDateRange): boolean {
  return isValidMonthDay(range.startMonth, range.startDay) && isValidMonthDay(range.endMonth, range.endDay);
}

export function annualRangeContains(range: AnnualShiftDateRange, month: number, day: number): boolean {
  if (!isValidAnnualRange(range) || !isValidMonthDay(month, day)) return false;
  const start = range.startMonth * 100 + range.startDay;
  const end = range.endMonth * 100 + range.endDay;
  const date = month * 100 + day;
  return start <= end ? date >= start && date <= end : date >= start || date <= end;
}

export function isValidShiftType(type: ShiftType): boolean {
  return typeof type.id === "string" && type.id.length > 0
    && typeof type.breakEnabled === "boolean" && typeof type.isArchived === "boolean"
    && typeof type.name === "string" && type.name.trim().length > 0
    && (graphemes ? [...graphemes.segment(type.name.trim())] : Array.from(type.name.trim())).length <= 40
    && [type.startMinutes, type.endMinutes, type.breakStartMinutes, type.breakDurationMinutes].every(value => Number.isInteger(value) && value >= 0 && value < 1440)
    && (type.kind === "work" || type.kind === "rest")
    && (!type.breakEnabled || type.breakDurationMinutes > 0)
    && /^#[0-9a-f]{6}$/i.test(type.colorHex)
    && (type.annualDateRange == null || (type.kind === "work" && isValidAnnualRange(type.annualDateRange)));
}

function typeDay(type: ShiftType | undefined, source: ScheduleDay["source"], frozen = false): ScheduleDay {
  if (!type || (!frozen && !isValidShiftType(type))) return unassigned;
  return {
    isWorkday: type.kind === "work", shiftTypeID: type.id, source,
    hours: type.kind === "rest" ? null : {
      startTime: minutesTime(type.startMinutes), endTime: minutesTime(type.endMinutes),
      breakStartTime: type.breakEnabled && type.breakDurationMinutes > 0 ? minutesTime(type.breakStartMinutes) : null,
      breakDurationMinutes: type.breakEnabled ? type.breakDurationMinutes : 0,
    },
  };
}

/** Explicit days win. Untouched months copy the last authored month by date. */
// Plans are immutable snapshots. Cache repeated lookups while a timer's
// summary and editor are reading the same roster.
const dayCache = new WeakMap<ExtendedSchedulePlan, Map<string, ScheduleDay>>();
export function resolveScheduleDay(plan: ExtendedSchedulePlan, key: string): ScheduleDay {
  let cache = dayCache.get(plan);
  if (!cache) { cache = new Map(); dayCache.set(plan, cache); }
  const cached = cache.get(key);
  if (cached) return cached;
  const result = resolveDay(plan, key);
  cache.set(key, result);
  return result;
}

function resolveDay(plan: ExtendedSchedulePlan, key: string): ScheduleDay {
  const day = civilDayNumber(key);
  if (day === null) return unassigned;
  const frozen = plan.frozenShiftTypes?.[key];
  if (frozen && isValidShiftType(frozen)) return typeDay(frozen, "handSet");
  const type = (id: string, source: ScheduleDay["source"]) => typeDay(plan.shiftTypes.find(t => t.id === id && isValidShiftType(t)), source);
  // A day set to a type the plan no longer has says nothing about the day; the
  // pattern and holidays decide it instead (Swift ExtendedScheduleIndex).
  const known = new Set(plan.shiftTypes.map(t => t.id));
  const assigned = key === plan.pinnedDayKey ? "00000000-0000-0000-0000-00000000F1ED" : plan.handSetDays[key];
  if (assigned && (key === plan.pinnedDayKey || known.has(assigned))) return type(assigned, "handSet");
  if (plan.fallsBackToBaseSchedule) return unassigned;
  if (!plan.rule && plan.clearedFromDayKey && key >= plan.clearedFromDayKey) return unassigned;

  let result = unassigned;
  const rule = plan.rule;
  const anchor = rule && civilDayNumber(rule.anchorDayKey);
  if (rule && rule.days.length && anchor != null) {
    const index = ((day - anchor) % rule.days.length + rule.days.length) % rule.days.length;
    result = type(rule.days[index], "rule");
  } else {
    const month = key.slice(0, 7);
    const authored = Object.keys(plan.handSetDays).filter(k => civilDayNumber(k) !== null && known.has(plan.handSetDays[k]));
    if (!authored.some(k => k.startsWith(month))) {
      const previous = authored.map(k => k.slice(0, 7)).filter(m => m < month).sort().at(-1);
      const sourceKey = previous && `${previous}-${key.slice(8)}`;
      if (sourceKey && plan.handSetDays[sourceKey]) {
        const oldType = plan.frozenShiftTypes?.[sourceKey];
        result = oldType ? typeDay(oldType, "carriedOver", true) : type(plan.handSetDays[sourceKey], "carriedOver");
      }
    }
  }
  // Annual ranges swap a working day's hours for the seasonal shift.
  const annual = (base: ScheduleDay): ScheduleDay => {
    if (!base.isWorkday) return base;
    const [, month, dayOfMonth] = key.split("-").map(Number);
    const seasonal = plan.shiftTypes.find(t => t.kind === "work" && !t.isArchived && isValidShiftType(t)
      && t.annualDateRange && annualRangeContains(t.annualDateRange, month, dayOfMonth));
    return seasonal ? type(seasonal.id, base.source === "holiday" ? "holiday" : "annualRange") : base;
  };
  result = annual(result);
  const holiday = plan.holidayRegionIdentifier && plan.holidayOverrides?.[key.replaceAll("-", "")];
  if (typeof holiday !== "boolean") return result;
  if (holiday && result.isWorkday) return { ...result, source: "holiday" };
  const holidayType = plan.shiftTypes.find(t => t.kind === (holiday ? "work" : "rest") && !t.isArchived);
  if (!holidayType) return holiday ? result : { ...unassigned, source: "holiday" };
  return holiday ? annual(type(holidayType.id, "holiday")) : type(holidayType.id, "holiday");
}
