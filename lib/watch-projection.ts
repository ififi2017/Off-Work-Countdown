import {
  addCivilDaysMs,
  getActiveBreakEndAtMs,
  getShiftEndAtMs,
  getShiftStartAtMs,
  startOfCivilDayMs,
  type ShiftTimeline,
} from "./countdown";

export type WatchTransitionState = "working" | "lunch" | "overtime" | "finished";

export interface WatchRulesProjection {
  scheduleState: "notConfigured" | "stopped" | "scheduled";
  shift: {
    segments: { startAtMs: number; endAtMs: number }[];
    plannedEndAtMs: number;
    overtimeEndAtMs: number | null;
    finishedAtMs: number | null;
    isRunning: boolean;
    transitions: { atMs: number; state: WatchTransitionState }[];
  } | null;
  nextShift: { startAtMs: number; validUntilMs: number } | null;
  contentExpiresAtMs: number;
}

export function projectWatchSnapshot(input: {
  nowMs: number;
  scheduleConfigured: boolean;
  isRunning: boolean;
  currentShift: ShiftTimeline;
  currentShiftOverride?: ShiftTimeline | null;
  finishedAtMs?: number | null;
  currentIsActual: boolean;
  nextShift: ShiftTimeline | null;
  timeZone?: string | null;
}): WatchRulesProjection {
  const nextStartAtMs = input.nextShift ? getShiftStartAtMs(input.nextShift) : null;
  const nextCivilDayAtMs = input.timeZone?.trim()
    ? addCivilDaysMs(startOfCivilDayMs(input.nowMs, input.timeZone), 1, input.timeZone)
    : localNextDayAtMs(input.nowMs);
  const hasSession = input.currentShiftOverride != null;
  const currentShift = input.currentShiftOverride ?? input.currentShift;
  const sessionSettlementAtMs = hasSession
    ? (input.timeZone?.trim()
      ? addCivilDaysMs(startOfCivilDayMs(getShiftEndAtMs(currentShift), input.timeZone), 1, input.timeZone)
      : localNextDayAtMs(getShiftEndAtMs(currentShift)))
    : nextCivilDayAtMs;
  const contentExpiresAtMs = input.scheduleConfigured && nextStartAtMs != null
    ? nextStartAtMs
    : sessionSettlementAtMs;
  return {
    scheduleState: input.scheduleConfigured || hasSession
      ? (input.isRunning ? "scheduled" : "stopped")
      : "notConfigured",
    shift: ((input.scheduleConfigured && input.currentIsActual) || hasSession)
      ? projectShift(currentShift, input.isRunning && input.finishedAtMs == null, input.finishedAtMs)
      : null,
    nextShift: input.scheduleConfigured && nextStartAtMs != null
      ? { startAtMs: nextStartAtMs, validUntilMs: nextStartAtMs }
      : null,
    contentExpiresAtMs,
  };
}

function projectShift(
  shift: ShiftTimeline,
  isRunning: boolean,
  finishedAtMs?: number | null,
): WatchRulesProjection["shift"] {
  const segments = shift.segments.map(({ startAtMs, endAtMs }) => ({ startAtMs, endAtMs }));
  const transitions: { atMs: number; state: WatchTransitionState }[] = [];
  for (let index = 0; index < segments.length; index += 1) {
    const segment = segments[index];
    transitions.push({
      atMs: segment.startAtMs,
      state: shift.overtimeEndAtMs != null && segment.startAtMs >= shift.plannedEndAtMs
        ? "overtime"
        : "working",
    });
    if (index < segments.length - 1 && getActiveBreakEndAtMs(shift, segment.endAtMs) != null) {
      transitions.push({ atMs: segment.endAtMs, state: "lunch" });
    }
  }
  if (finishedAtMs != null) {
    transitions.push({ atMs: finishedAtMs, state: "finished" });
  } else if (shift.overtimeEndAtMs != null) {
    transitions.push({ atMs: shift.plannedEndAtMs, state: "overtime" });
  }
  if (finishedAtMs == null) transitions.push({ atMs: getShiftEndAtMs(shift), state: "finished" });
  transitions.sort((left, right) => left.atMs - right.atMs);
  const visibleTransitions = finishedAtMs == null
    ? transitions
    : transitions.filter(({ atMs }) => atMs <= finishedAtMs);

  return {
    segments,
    plannedEndAtMs: shift.plannedEndAtMs,
    overtimeEndAtMs: shift.overtimeEndAtMs,
    finishedAtMs: finishedAtMs ?? null,
    isRunning,
    transitions: visibleTransitions.filter((transition, index) =>
      index === visibleTransitions.length - 1 || transition.atMs !== visibleTransitions[index + 1].atMs
    ),
  };
}

function localNextDayAtMs(nowMs: number): number {
  const next = new Date(nowMs);
  next.setHours(0, 0, 0, 0);
  next.setDate(next.getDate() + 1);
  return next.getTime();
}
