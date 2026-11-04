import {
  calculateTimelinePayRatio,
  getPlannedShiftDurationMs,
  getShiftElapsedMs,
  type ShiftTimeline,
} from "@/lib/countdown";

export interface WebOvertimePresentation {
  elapsedOvertimeMs: number;
  unpaidHourlyRate: number | null;
  unpaidRateDecreasePercent: number | null;
}

/** A conditional comparison only: the actual earnings estimate continues to
 * pay effective overtime at the original hourly rate through the shared rules. */
export function webOvertimePresentation(
  shift: ShiftTimeline | null,
  nowMs: number,
  dailySalary: number | null,
  hideEarnings: boolean,
): WebOvertimePresentation | null {
  if (!shift?.overtimeEndAtMs || !Number.isFinite(nowMs)) return null;
  const plannedMs = getPlannedShiftDurationMs(shift);
  if (!Number.isFinite(plannedMs) || plannedMs <= 0) return null;
  const elapsedMs = getShiftElapsedMs(shift, nowMs);
  if (!Number.isFinite(elapsedMs)) return null;
  const elapsedOvertimeMs = Math.max(0, elapsedMs - plannedMs);
  const result: WebOvertimePresentation = {
    elapsedOvertimeMs,
    unpaidHourlyRate: null,
    unpaidRateDecreasePercent: null,
  };
  if (elapsedOvertimeMs === 0 || hideEarnings || dailySalary === null ||
    !Number.isFinite(dailySalary) || dailySalary <= 0) return result;

  // If the entire day paid only the planned daily amount, spread that fixed
  // amount over the effective hours actually elapsed. Lunch is already excluded
  // and elapsedMs already stops at the effective end, including overnight runs.
  const hourlyRate = dailySalary / (elapsedMs / (60 * 60 * 1000));
  const decreasePercent = (1 - 1 / calculateTimelinePayRatio(shift, nowMs)) * 100;
  if (!Number.isFinite(hourlyRate) || !Number.isFinite(decreasePercent)) return result;
  result.unpaidHourlyRate = hourlyRate;
  result.unpaidRateDecreasePercent = decreasePercent;
  return result;
}
