import {
  normalizeOvertimePayMultiplier,
  getShiftEndAtMs,
  getShiftStartAtMs,
  isValidShiftTimeline,
  type ShiftTimeline,
} from "@/lib/countdown";
import type { Shift } from "@/lib/share";

export const WEB_OVERTIME_STORAGE_KEY = "webOvertimeSession:v1";

type SessionStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;
export type WebOvertimeStorage = () => SessionStorage;

export interface WebOvertimeSession {
  startTime: string;
  endTime: string;
  shift: ShiftTimeline;
  /** Plan 024: this overtime's pay multiple (0 = unpaid). Older sessions read as 1. */
  payMultiplier?: number;
}

// Shared/preset runs are scoped to their URL and tab; they never overwrite the
// visitor's own session in localStorage. Locale is deliberately absent.
export function webOvertimeStorageKey(urlShift: Shift | null): string {
  return urlShift
    ? `${WEB_OVERTIME_STORAGE_KEY}:${urlShift.start}-${urlShift.end}`
    : WEB_OVERTIME_STORAGE_KEY;
}

function isTime(value: unknown): value is string {
  return typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
}

/** Keep today's completed result adjustable, but never revive it tomorrow.
 * An extension past midnight remains restorable until its actual end. */
export function webOvertimeExpiresAtMs(shift: ShiftTimeline): number {
  const nextDay = new Date(shift.plannedEndAtMs);
  nextDay.setHours(24, 0, 0, 0);
  return Math.max(nextDay.getTime(), getShiftEndAtMs(shift));
}

export function clearWebOvertimeSession(storage: WebOvertimeStorage, key: string): void {
  try {
    storage().removeItem(key);
  } catch {
    // Storage denial never prevents returning to the form.
  }
}

export function readWebOvertimeSession(
  storage: WebOvertimeStorage,
  key: string,
  nowMs: number,
  expectedHours?: Shift,
): WebOvertimeSession | null {
  try {
    const raw = storage().getItem(key);
    if (!raw) return null;
    const value = JSON.parse(raw);
    const shift = value?.shift;
    if (
      value?.version !== 1 || !isTime(value.startTime) || !isTime(value.endTime) ||
      value.startTime === value.endTime ||
      (expectedHours && (value.startTime !== expectedHours.start || value.endTime !== expectedHours.end)) ||
      !shift || !Array.isArray(shift.segments) ||
      !shift.segments.every((segment: unknown) => segment !== null && typeof segment === "object") ||
      !isValidShiftTimeline(shift) || shift.overtimeEndAtMs === null ||
      getShiftStartAtMs(shift) > nowMs ||
      !Number.isFinite(webOvertimeExpiresAtMs(shift)) ||
      nowMs >= webOvertimeExpiresAtMs(shift)
    ) {
      clearWebOvertimeSession(storage, key);
      return null;
    }
    // Pick only session fields; no preferences or salary enter this snapshot.
    return {
      startTime: value.startTime,
      endTime: value.endTime,
      shift: {
        segments: shift.segments.map(({ startAtMs, endAtMs }: ShiftTimeline["segments"][number]) => ({ startAtMs, endAtMs })),
        plannedEndAtMs: shift.plannedEndAtMs,
        overtimeEndAtMs: shift.overtimeEndAtMs,
      },
      ...(normalizeOvertimePayMultiplier(value.payMultiplier ?? 1) === 1
        ? {}
        : { payMultiplier: normalizeOvertimePayMultiplier(value.payMultiplier) }),
    };
  } catch {
    clearWebOvertimeSession(storage, key);
    return null;
  }
}

export function writeWebOvertimeSession(
  storage: WebOvertimeStorage,
  key: string,
  session: WebOvertimeSession,
): void {
  try {
    const { startTime, endTime, shift, payMultiplier } = session;
    storage().setItem(key, JSON.stringify({
      version: 1,
      startTime,
      endTime,
      shift: {
        segments: shift.segments.map(({ startAtMs, endAtMs }) => ({ startAtMs, endAtMs })),
        plannedEndAtMs: shift.plannedEndAtMs,
        overtimeEndAtMs: shift.overtimeEndAtMs,
      },
      ...(payMultiplier === undefined || payMultiplier === 1 ? {} : { payMultiplier }),
    }));
  } catch {
    // Continue the countdown in memory when storage is full or unavailable.
  }
}
