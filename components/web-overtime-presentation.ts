import { overtimeRateComparison, type ShiftTimeline } from "@/lib/countdown";

export interface WebOvertimePresentation {
  elapsedOvertimeMs: number;
  unpaidHourlyRate: number | null;
  unpaidRateDecreasePercent: number | null;
}

/** A conditional comparison only: the actual earnings estimate continues to
 * pay effective overtime at the original hourly rate through the shared rules
 * (`overtimeRateComparison` in lib/countdown.ts). */
export function webOvertimePresentation(
  shift: ShiftTimeline | null,
  nowMs: number,
  dailySalary: number | null,
  hideEarnings: boolean,
): WebOvertimePresentation | null {
  return overtimeRateComparison(shift, nowMs, hideEarnings ? null : dailySalary);
}
