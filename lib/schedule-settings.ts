import type { WorkScheduleConfig } from "./countdown";
import {
  civilDayNumber,
  isValidShiftType,
  minutesTime,
  resolveScheduleDay,
  type ExtendedSchedulePlan,
  type ShiftCycleRule,
  type ShiftType,
} from "./extended-schedule";

// Desktop schedule preferences and the editing steps of its schedule page,
// ported from iOS ExtendedScheduleEditing.swift. Every automatic pattern is a
// cycle of shift types; resolution stays in extended-schedule.ts.

export const SCHEDULE_STORAGE_KEY = "workScheduleSettings";
export const scheduleModes = ["weekly", "alternating", "rotation", "free", "manual"] as const;
export type ScheduleMode = (typeof scheduleModes)[number];
export const scheduleModeKeys: Record<ScheduleMode, string> = {
  weekly: "scheduleClassic",
  alternating: "scheduleAlternating",
  rotation: "scheduleRotation",
  free: "scheduleFreeCalendar",
  manual: "scheduleManualTimer",
};

export const MAX_CYCLE_LENGTH = 366;
export const REST_COLOR = "#8E8E93";
/** The iOS palette: system hues that stay legible as small marks. */
export const SHIFT_COLORS = ["#FF9500", "#007AFF", "#AF52DE", "#34C759", "#FF2D55", "#30B0C7", "#5856D6", "#A2845E"];

export type PatternMode = Exclude<ScheduleMode, "manual">;

/** What a pattern looked like when the user switched away from it. */
export interface SavedPattern {
  rule: ShiftCycleRule | null;
  /** Upcoming dates set by hand under that pattern. */
  handSetDays: Record<string, string>;
}

export interface ScheduleSettings {
  manual: boolean;
  /** Null keeps the main form's hours and workdays (fixed weekdays). */
  plan: ExtendedSchedulePlan | null;
  /** Names and colours of the fixed-weekday shift while `plan` is null. */
  fixedTypes?: ShiftType[];
  /** Switching patterns applies at once, so each one is kept to switch back to. */
  patterns?: Partial<Record<PatternMode, SavedPattern>>;
  /**
   * Holiday calendar region ("" = off, absent = never chosen). Kept outside
   * the plan so it also applies to fixed weekdays without turning them into a
   * plan; the overrides themselves are attached at resolution (lib/holidays.ts).
   */
  holidayRegion?: string;
}

/** The fixed-weekday schedule the main form edits. */
export interface FixedHours {
  startTime: string;
  endTime: string;
  workdays: number[];
  breakStartTime: string | null;
  breakDurationMinutes: number;
}

export function defaultScheduleSettings(): ScheduleSettings {
  return { manual: false, plan: null };
}

function isValidPlan(plan: ExtendedSchedulePlan): boolean {
  if (!plan || !Array.isArray(plan.shiftTypes) || !plan.shiftTypes.every(isValidShiftType)) return false;
  const known = new Set(plan.shiftTypes.map((type) => type.id));
  if (known.size !== plan.shiftTypes.length) return false;
  if (!plan.handSetDays || typeof plan.handSetDays !== "object") return false;
  if (Object.entries(plan.handSetDays).some(([key, id]) => civilDayNumber(key) === null || !known.has(id))) return false;
  if (plan.frozenShiftTypes && Object.entries(plan.frozenShiftTypes).some(([key, type]) => civilDayNumber(key) === null || !isValidShiftType(type))) return false;
  const rule = plan.rule;
  return !rule || (Array.isArray(rule.days) && rule.days.length >= 1 && rule.days.length <= MAX_CYCLE_LENGTH
    && civilDayNumber(rule.anchorDayKey) !== null && rule.days.every((id) => known.has(id)));
}

function isValidSavedPattern(saved: SavedPattern | undefined): boolean {
  if (!saved || !saved.handSetDays || typeof saved.handSetDays !== "object") return false;
  if (Object.entries(saved.handSetDays).some(([key, id]) => civilDayNumber(key) === null || typeof id !== "string")) return false;
  const rule = saved.rule;
  return rule === null || (Array.isArray(rule?.days) && rule.days.length >= 1 && rule.days.length <= MAX_CYCLE_LENGTH
    && rule.days.every((id) => typeof id === "string") && civilDayNumber(rule.anchorDayKey) !== null);
}

/** Missing or damaged data keeps the fixed-weekday behaviour. */
export function parseScheduleSettings(raw: string | null): ScheduleSettings {
  if (!raw) return defaultScheduleSettings();
  try {
    const value = JSON.parse(raw) as ScheduleSettings;
    if (typeof value.manual !== "boolean") return defaultScheduleSettings();
    if (value.plan !== null && !isValidPlan(value.plan)) return defaultScheduleSettings();
    const fixedTypes = Array.isArray(value.fixedTypes) && value.fixedTypes.every(isValidShiftType) ? value.fixedTypes : undefined;
    const patterns = value.patterns && typeof value.patterns === "object"
      ? Object.fromEntries(Object.entries(value.patterns).filter(([mode, saved]) =>
        (scheduleModes as readonly string[]).includes(mode) && mode !== "manual" && isValidSavedPattern(saved)))
      : undefined;
    const holidayRegion = typeof value.holidayRegion === "string" && /^([A-Z]{2})?$/.test(value.holidayRegion)
      ? value.holidayRegion : undefined;
    return {
      manual: value.manual,
      plan: value.plan,
      ...(fixedTypes ? { fixedTypes } : {}),
      ...(patterns && Object.keys(patterns).length ? { patterns } : {}),
      ...(holidayRegion !== undefined ? { holidayRegion } : {}),
    };
  } catch {
    return defaultScheduleSettings();
  }
}

export function workScheduleConfig(
  settings: ScheduleSettings,
  holidays?: { fixedPlan: ExtendedSchedulePlan; overrides: Record<string, boolean> | null },
): WorkScheduleConfig {
  if (settings.manual) return { mode: "off" };
  const region = settings.holidayRegion;
  if (region && holidays?.overrides) {
    // Fixed weekdays resolve through the equivalent weekly plan so the shared
    // resolver can apply the region's days off and makeup workdays.
    const plan = settings.plan ?? holidays.fixedPlan;
    return { mode: "classic", extendedSchedule: { ...plan, holidayRegionIdentifier: region, holidayOverrides: holidays.overrides } };
  }
  return settings.plan ? { mode: "classic", extendedSchedule: settings.plan } : { mode: "classic" };
}

export function scheduleMode(settings: ScheduleSettings): ScheduleMode {
  if (settings.manual) return "manual";
  return settings.plan ? planMode(settings.plan) : "weekly";
}

export function planMode(plan: ExtendedSchedulePlan): Exclude<ScheduleMode, "manual"> {
  switch (plan.rule?.preset) {
    case undefined: return "free";
    case "weekly": return "weekly";
    case "alternatingWeeks": return "alternating";
    default: return "rotation";
  }
}

// Civil day arithmetic on YYYY-MM-DD keys; day 0 is 1970-01-01, a Thursday.
export function dayKeyFromNumber(day: number): string {
  const date = new Date(day * 86_400_000);
  return `${String(date.getUTCFullYear()).padStart(4, "0")}-${String(date.getUTCMonth() + 1).padStart(2, "0")}-${String(date.getUTCDate()).padStart(2, "0")}`;
}

export function addDays(key: string, days: number): string {
  return dayKeyFromNumber((civilDayNumber(key) ?? 0) + days);
}

/** 0 = Sunday, matching Date#getDay and the stored workdays. */
export function weekdayOf(key: string): number {
  return (((civilDayNumber(key) ?? 0) + 4) % 7 + 7) % 7;
}

function mondayOf(key: string): string {
  return addDays(key, -((weekdayOf(key) + 6) % 7));
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

const clockMinutes = (time: string) => {
  const [hour, minute] = time.split(":").map(Number);
  return hour * 60 + minute;
};

export function activeTypes(plan: ExtendedSchedulePlan): ShiftType[] {
  return plan.shiftTypes.filter((type) => !type.isArchived);
}

export function nextColor(types: ShiftType[]): string {
  const used = new Set(types.filter((type) => !type.isArchived).map((type) => type.colorHex.toUpperCase()));
  return SHIFT_COLORS.find((color) => !used.has(color)) ?? SHIFT_COLORS[types.length % SHIFT_COLORS.length];
}

function newID(): string {
  return crypto.randomUUID().toUpperCase();
}

function restTypeID(plan: ExtendedSchedulePlan, name: string): [ExtendedSchedulePlan, string] {
  const rest = activeTypes(plan).find((type) => type.kind === "rest");
  if (rest) return [plan, rest.id];
  const type: ShiftType = {
    id: newID(), name, kind: "rest", startMinutes: 540, endMinutes: 1020,
    breakEnabled: false, breakStartMinutes: 720, breakDurationMinutes: 60, colorHex: REST_COLOR, isArchived: false,
  };
  return [{ ...plan, shiftTypes: [...plan.shiftTypes, type] }, type.id];
}

/** The work type a template fills its work days with: the first the rule uses. */
function primaryWorkType(plan: ExtendedSchedulePlan): string | undefined {
  const work = new Set(activeTypes(plan).filter((type) => type.kind === "work").map((type) => type.id));
  return plan.rule?.days.find((id) => work.has(id)) ?? [...work][0];
}

/** One cycle of each template, starting on `anchorDayKey`. */
function templatePattern(mode: "weekly" | "alternating" | "rotation", fixed: FixedHours, todayKey: string) {
  if (mode === "rotation") return { anchorDayKey: todayKey, workdays: [true, true, false, false] };
  const anchorDayKey = mondayOf(todayKey);
  const week = Array.from({ length: 7 }, (_, index) => fixed.workdays.includes((index + 1) % 7));
  // This week rests two days and the next one; the other week also works Saturday.
  return { anchorDayKey, workdays: mode === "weekly" ? week : [...week, ...week.map((work, index) => work || index === 5)] };
}

function filling(plan: ExtendedSchedulePlan, mode: "weekly" | "alternating" | "rotation", fixed: FixedHours, todayKey: string, workID: string, restName: string): ExtendedSchedulePlan {
  const [next, rest] = restTypeID(plan, restName);
  const pattern = templatePattern(mode, fixed, todayKey);
  const preset: ShiftCycleRule["preset"] = mode === "alternating" ? "alternatingWeeks" : mode;
  return { ...next, clearedFromDayKey: null, rule: { preset, anchorDayKey: pattern.anchorDayKey, days: pattern.workdays.map((work) => (work ? workID : rest)) } };
}

/**
 * The fixed-weekday schedule as a plan, so the page edits one model. Kept
 * shift types retain their names and colours; their hours follow the form.
 */
export function seedPlan(fixed: FixedHours, todayKey: string, names: { work: string; rest: string }, kept: ShiftType[] = []): ExtendedSchedulePlan {
  const keptWork = kept.find((type) => type.kind === "work");
  const work: ShiftType = {
    id: keptWork?.id ?? newID(),
    name: keptWork?.name ?? names.work,
    kind: "work",
    startMinutes: clockMinutes(fixed.startTime),
    endMinutes: clockMinutes(fixed.endTime),
    breakEnabled: fixed.breakStartTime !== null && fixed.breakDurationMinutes > 0,
    breakStartMinutes: fixed.breakStartTime ? clockMinutes(fixed.breakStartTime) : 720,
    breakDurationMinutes: fixed.breakDurationMinutes > 0 ? fixed.breakDurationMinutes : 60,
    colorHex: keptWork?.colorHex ?? SHIFT_COLORS[0],
    isArchived: false,
  };
  const rest = kept.find((type) => type.kind === "rest");
  const plan: ExtendedSchedulePlan = { shiftTypes: rest ? [work, rest] : [work], rule: null, handSetDays: {} };
  return filling(plan, "weekly", fixed, todayKey, work.id, names.rest);
}

/**
 * A weekly cycle of one work shift and one rest is exactly what the main form
 * shows. Saving it as hours and workdays keeps that form for most people.
 */
export function fixedHoursFromPlan(plan: ExtendedSchedulePlan): FixedHours | null {
  const rule = plan.rule;
  if (rule?.preset !== "weekly" || rule.days.length !== 7 || Object.keys(plan.handSetDays).length > 0) return null;
  if (plan.holidayRegionIdentifier) return null;
  const used = [...new Set(rule.days)].map((id) => plan.shiftTypes.find((type) => type.id === id));
  const work = used.filter((type) => type?.kind === "work");
  if (work.length !== 1 || used.length - work.length > 1 || used.some((type) => !type || type.isArchived)) return null;
  const type = work[0]!;
  const workdays = rule.days.flatMap((id, index) => (id === type.id ? [weekdayOf(addDays(rule.anchorDayKey, index))] : []));
  return {
    startTime: minutesTime(type.startMinutes),
    endTime: minutesTime(type.endMinutes),
    workdays: workdays.sort(),
    breakStartTime: type.breakEnabled ? minutesTime(type.breakStartMinutes) : null,
    breakDurationMinutes: type.breakEnabled ? type.breakDurationMinutes : 0,
  };
}

/** The settings to store for an edited plan, folding the plain weekly case back into the form. */
export function settingsForPlan(
  plan: ExtendedSchedulePlan,
  patterns?: ScheduleSettings["patterns"],
  holidayRegion?: string,
): { settings: ScheduleSettings; fixed: FixedHours | null } {
  // Holiday data is attached when resolving and never stored inside the plan.
  const { holidayOverrides: _overrides, holidayRegionIdentifier: _region, ...stored } = plan;
  plan = stored;
  const kept = {
    ...(patterns && Object.keys(patterns).length ? { patterns } : {}),
    ...(holidayRegion !== undefined ? { holidayRegion } : {}),
  };
  const fixed = fixedHoursFromPlan(plan);
  if (!fixed) return { settings: { manual: false, plan, ...kept }, fixed: null };
  const used = new Set(plan.rule!.days);
  return { settings: { manual: false, plan: null, fixedTypes: plan.shiftTypes.filter((type) => used.has(type.id)), ...kept }, fixed };
}

/**
 * Switches to a template. Switching to the free roster keeps what the pattern
 * gives this month and next, which later months then repeat by date.
 */
export function applyingMode(plan: ExtendedSchedulePlan, mode: Exclude<ScheduleMode, "manual">, fixed: FixedHours, todayKey: string, restName: string): ExtendedSchedulePlan {
  if (mode === "free") {
    const handSetDays = { ...plan.handSetDays };
    const [year, month] = todayKey.split("-").map(Number);
    for (const [y, m] of [[year, month], month === 12 ? [year + 1, 1] : [year, month + 1]]) {
      for (let day = 1; day <= daysInMonth(y, m); day += 1) {
        const key = `${y}-${String(m).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
        const resolved = resolveScheduleDay(plan, key);
        if (key >= todayKey && resolved.source === "rule" && resolved.shiftTypeID) handSetDays[key] = resolved.shiftTypeID;
      }
    }
    return { ...plan, rule: null, handSetDays, clearedFromDayKey: null };
  }
  const work = primaryWorkType(plan);
  if (!work) return plan;
  // The pattern takes over from today; days already past keep what they were.
  const handSetDays = Object.fromEntries(Object.entries(plan.handSetDays).filter(([key]) => key < todayKey));
  return filling({ ...plan, handSetDays }, mode, fixed, todayKey, work, restName);
}

/**
 * Leaves one pattern for another. The pattern left behind, with its upcoming
 * hand-set dates, is kept; a pattern used before comes back as it was.
 */
export function switchingPattern(
  plan: ExtendedSchedulePlan,
  patterns: ScheduleSettings["patterns"],
  from: PatternMode,
  to: PatternMode,
  fixed: FixedHours,
  todayKey: string,
  restName: string,
): { plan: ExtendedSchedulePlan; patterns: NonNullable<ScheduleSettings["patterns"]> } {
  const past = Object.fromEntries(Object.entries(plan.handSetDays).filter(([key]) => key < todayKey));
  const upcoming = Object.fromEntries(Object.entries(plan.handSetDays).filter(([key]) => key >= todayKey));
  const kept = { ...patterns, [from]: { rule: plan.rule, handSetDays: upcoming } };
  const saved = patterns?.[to];
  const active = new Set(activeTypes(plan).map((type) => type.id));
  const restorable = saved
    && (saved.rule === null) === (to === "free")
    && saved.rule?.days.every((id) => active.has(id)) !== false
    && Object.values(saved.handSetDays).every((id) => active.has(id));
  if (!restorable) return { plan: applyingMode(plan, to, fixed, todayKey, restName), patterns: kept };
  const handSetDays = { ...past, ...Object.fromEntries(Object.entries(saved.handSetDays).filter(([key]) => key >= todayKey)) };
  return { plan: { ...plan, rule: saved.rule, handSetDays, clearedFromDayKey: null }, patterns: kept };
}

export function assigningCycleDay(plan: ExtendedSchedulePlan, index: number, typeID: string): ExtendedSchedulePlan {
  if (!plan.rule || index < 0 || index >= plan.rule.days.length) return plan;
  const days = [...plan.rule.days];
  days[index] = typeID;
  return { ...plan, rule: { ...plan.rule, days } };
}

/** Lengthens the cycle with rest days, or drops days from its end. */
export function resizingCycle(plan: ExtendedSchedulePlan, length: number, restName: string): ExtendedSchedulePlan {
  if (!plan.rule) return plan;
  const size = Math.min(Math.max(1, length), MAX_CYCLE_LENGTH);
  const [next, rest] = restTypeID(plan, restName);
  const days = size < plan.rule.days.length
    ? plan.rule.days.slice(0, size)
    : [...plan.rule.days, ...Array<string>(size - plan.rule.days.length).fill(rest)];
  return { ...next, rule: { ...plan.rule, days } };
}

/** Today's one-based place in the cycle. */
export function cycleDayOf(rule: ShiftCycleRule, todayKey: string): number {
  const offset = (civilDayNumber(todayKey) ?? 0) - (civilDayNumber(rule.anchorDayKey) ?? 0);
  return ((offset % rule.days.length) + rule.days.length) % rule.days.length + 1;
}

/** Moves the cycle so today is day `position`. */
export function anchoringCycle(plan: ExtendedSchedulePlan, todayKey: string, position: number): ExtendedSchedulePlan {
  if (!plan.rule) return plan;
  return { ...plan, rule: { ...plan.rule, anchorDayKey: addDays(todayKey, -(position - 1)) } };
}

/** Sets or clears one date; a past date keeps the hours it had when set. */
export function settingRosterDay(plan: ExtendedSchedulePlan, key: string, typeID: string | null, todayKey: string): ExtendedSchedulePlan {
  const handSetDays = { ...plan.handSetDays };
  const frozenShiftTypes = { ...plan.frozenShiftTypes };
  delete frozenShiftTypes[key];
  if (typeID === null) delete handSetDays[key];
  else {
    handSetDays[key] = typeID;
    const type = plan.shiftTypes.find((candidate) => candidate.id === typeID);
    if (type && key < todayKey) frozenShiftTypes[key] = type;
  }
  return { ...plan, handSetDays, frozenShiftTypes };
}

/** Adds or replaces a shift type. Days already worked under it keep its old hours. */
export function upsertingShiftType(plan: ExtendedSchedulePlan, type: ShiftType, todayKey: string): ExtendedSchedulePlan {
  const old = plan.shiftTypes.find((candidate) => candidate.id === type.id);
  if (!old) return { ...plan, shiftTypes: [...plan.shiftTypes, type] };
  const frozenShiftTypes = { ...plan.frozenShiftTypes };
  for (const [key, id] of Object.entries(plan.handSetDays)) {
    if (id === old.id && key < todayKey && !frozenShiftTypes[key]) frozenShiftTypes[key] = old;
  }
  return { ...plan, frozenShiftTypes, shiftTypes: plan.shiftTypes.map((candidate) => (candidate.id === type.id ? type : candidate)) };
}

/** Whether removing the type would silently turn upcoming days into rest. */
export function shiftTypeInUse(plan: ExtendedSchedulePlan, id: string, todayKey: string): boolean {
  return plan.rule?.days.includes(id) === true
    || Object.entries(plan.handSetDays).some(([key, assigned]) => assigned === id && key >= todayKey);
}

/** Past days still name a removed type, so it is archived rather than dropped. */
export function removingShiftType(plan: ExtendedSchedulePlan, id: string): ExtendedSchedulePlan {
  const named = Object.values(plan.handSetDays).includes(id);
  return {
    ...plan,
    shiftTypes: named
      ? plan.shiftTypes.map((type) => (type.id === id ? { ...type, isArchived: true } : type))
      : plan.shiftTypes.filter((type) => type.id !== id),
  };
}

export function newShiftType(plan: ExtendedSchedulePlan, fixed: FixedHours): ShiftType {
  return {
    id: newID(), name: "", kind: "work",
    startMinutes: clockMinutes(fixed.startTime), endMinutes: clockMinutes(fixed.endTime),
    breakEnabled: false, breakStartMinutes: 720, breakDurationMinutes: 30,
    colorHex: nextColor(plan.shiftTypes), isArchived: false,
  };
}

/** One brush selection on the free roster; undo is per brush, like iOS. */
export interface PaintSession {
  brushID: string;
  /** What each painted date was before this brush touched it. */
  originals: Record<string, string | null>;
  /** Dates already changed by the current stroke. */
  visited: Set<string>;
}

export function startingPaint(brushID: string): PaintSession {
  return { brushID, originals: {}, visited: new Set() };
}

/**
 * Paints dates in stroke order. A date changes once per stroke; painting a
 * date that already has the brush puts back what it had before.
 */
export function paintingDays(plan: ExtendedSchedulePlan, keys: string[], paint: PaintSession, todayKey: string): ExtendedSchedulePlan {
  let next = plan;
  for (const key of keys) {
    if (paint.visited.has(key)) continue;
    paint.visited.add(key);
    const current = next.handSetDays[key] ?? null;
    if (current === paint.brushID) {
      const original = key in paint.originals ? paint.originals[key] : null;
      delete paint.originals[key];
      next = settingRosterDay(next, key, original, todayKey);
    } else {
      paint.originals[key] = current;
      next = settingRosterDay(next, key, paint.brushID, todayKey);
    }
  }
  return next;
}
