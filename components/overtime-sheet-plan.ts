import { normalizeOvertimePayMultiplier } from "@/lib/countdown";

/**
 * The overtime dialog's choices (plan 024; iOS `OvertimeSheetPlan`). The
 * overtime starts at the planned clock-off plus an optional rest, and ends at
 * a clock time or after a length. The shift itself is still built by
 * `extendShiftWithOvertime`; this only turns the choices into instants.
 */
export const OVERTIME_REST_MINUTES = [0, 15, 30, 45, 60] as const;
export const OVERTIME_DURATION_STEP_MINUTES = 15;
export const OVERTIME_MAXIMUM_DURATION_MINUTES = 12 * 60;
/** Offered directly; anything else is a custom multiple. */
export const OVERTIME_PAY_PRESETS = [1, 1.5, 2, 3] as const;

const MINUTE_MS = 60_000;

/** When the overtime starts: the planned clock-off plus the rest. */
export function overtimeStartMs(plannedEndAtMs: number, restMinutes: number): number {
  return plannedEndAtMs + restMinutes * MINUTE_MS;
}

/**
 * The earliest valid end: not before the overtime's start or now, and after a
 * rest at least a minute of overtime to count.
 */
export function overtimeMinimumEndMs(plannedEndAtMs: number, restMinutes: number, nowMs: number): number {
  const start = overtimeStartMs(plannedEndAtMs, restMinutes);
  return Math.max(restMinutes > 0 ? start + MINUTE_MS : start, nowMs);
}

/** Lengths that still end now or later, 15 minutes apart. */
export function overtimeDurationChoices(plannedEndAtMs: number, restMinutes: number, nowMs: number): number[] {
  const step = OVERTIME_DURATION_STEP_MINUTES;
  const elapsed = Math.max(0, (nowMs - overtimeStartMs(plannedEndAtMs, restMinutes)) / MINUTE_MS);
  const first = Math.max(step, Math.ceil(elapsed / step) * step);
  const choices: number[] = [];
  for (let minutes = first; minutes <= Math.max(first, OVERTIME_MAXIMUM_DURATION_MINUTES); minutes += step) {
    choices.push(minutes);
  }
  return choices;
}

/** The choice closest to `minutes`, for prefilling from an existing overtime. */
export function nearestOvertimeRest(minutes: number): number {
  return OVERTIME_REST_MINUTES.reduce((best, choice) =>
    Math.abs(choice - minutes) < Math.abs(best - minutes) ? choice : best
  );
}

/** The duration choice closest to an end instant, for switching modes. */
export function nearestOvertimeDuration(choices: number[], startMs: number, endMs: number): number {
  const minutes = (endMs - startMs) / MINUTE_MS;
  return choices.reduce(
    (best, choice) => (Math.abs(choice - minutes) < Math.abs(best - minutes) ? choice : best),
    choices[0] ?? OVERTIME_DURATION_STEP_MINUTES
  );
}

/** The session receives a start only when a rest moved it. */
export function overtimeStartForSession(plannedEndAtMs: number, restMinutes: number): number | null {
  return restMinutes > 0 ? overtimeStartMs(plannedEndAtMs, restMinutes) : null;
}

/**
 * The pay a dialog choice saves: "unpaid" is 0; a preset or custom value is
 * normalised by the shared rule (an invalid custom entry becomes 1).
 */
export function overtimePayChoiceMultiplier(choice: string, customText: string): number {
  if (choice === "unpaid") return 0;
  if (choice === "custom") {
    const value = Number(customText.replace(",", "."));
    return normalizeOvertimePayMultiplier(value) === 0 ? 1 : normalizeOvertimePayMultiplier(value);
  }
  return normalizeOvertimePayMultiplier(Number(choice));
}

/** The dialog choice that shows a saved multiplier. */
export function overtimePayChoice(multiplier: number): string {
  if (multiplier === 0) return "unpaid";
  return (OVERTIME_PAY_PRESETS as readonly number[]).includes(multiplier) ? String(multiplier) : "custom";
}

/**
 * The shift before any overtime: segments clipped back to the planned
 * clock-off, so adjusting an overtime that began after a rest replaces its
 * segment instead of stacking another.
 */
export function withoutOvertime<T extends { segments: { startAtMs: number; endAtMs: number }[]; plannedEndAtMs: number; overtimeEndAtMs: number | null }>(shift: T): T {
  if (shift.overtimeEndAtMs === null) return shift;
  const segments = shift.segments
    .filter((segment) => segment.startAtMs < shift.plannedEndAtMs)
    .map((segment) => ({ ...segment, endAtMs: Math.min(segment.endAtMs, shift.plannedEndAtMs) }));
  return { ...shift, segments, overtimeEndAtMs: null };
}

/** The rest before an existing overtime that began after one, in minutes. */
export function existingOvertimeRestMinutes(shift: { segments: { startAtMs: number }[]; plannedEndAtMs: number; overtimeEndAtMs: number | null }): number {
  const last = shift.segments[shift.segments.length - 1];
  if (shift.overtimeEndAtMs === null || !last || last.startAtMs <= shift.plannedEndAtMs) return 0;
  return nearestOvertimeRest((last.startAtMs - shift.plannedEndAtMs) / MINUTE_MS);
}
