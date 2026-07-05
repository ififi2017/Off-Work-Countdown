// Pure countdown/salary helpers, kept framework-free so they can be unit tested.

const DAY_MS = 24 * 60 * 60 * 1000;

// Build a Date on the same day as `base` at the given "HH:mm" time.
// Avoids `new Date(string)` parsing, which is inconsistent across browsers (notably Safari).
export function atTime(base: Date, time: string): Date {
  const [hours, minutes] = time.split(":").map(Number);
  const d = new Date(base);
  d.setHours(hours, minutes, 0, 0);
  return d;
}

export interface ShiftBounds {
  start: Date;
  end: Date;
}

// Resolve the concrete start/end of the shift containing (or nearest to) `now`.
// Overnight shifts (end <= start, e.g. 22:00–06:00) are anchored so that a
// time after midnight still belongs to the shift that started the day before.
export function getShiftBounds(
  startTime: string,
  endTime: string,
  now: Date
): ShiftBounds {
  let start = atTime(now, startTime);
  let end = atTime(now, endTime);

  if (end <= start) {
    if (now < end) {
      // e.g. 01:00 during a 22:00–06:00 shift: it started yesterday
      start = new Date(start.getTime() - DAY_MS);
    } else {
      end = new Date(end.getTime() + DAY_MS);
    }
  }

  return { start, end };
}

// Percentage of the shift already worked, clamped to [0, 100].
export function calculateProgress(
  startTime: string,
  endTime: string,
  now: Date
): number {
  const { start, end } = getShiftBounds(startTime, endTime, now);
  const totalDiff = end.getTime() - start.getTime();
  const currentDiff = end.getTime() - now.getTime();

  if (currentDiff <= 0) return 100;
  return Math.max(0, Math.min(100, ((totalDiff - currentDiff) / totalDiff) * 100));
}

export const DEFAULT_MONTHLY_WORKING_DAYS = 21.75;

export function getDailySalary(
  amount: string,
  type: "monthly" | "daily",
  monthlyWorkingDays: number = DEFAULT_MONTHLY_WORKING_DAYS
): number | null {
  if (!amount) return null;
  const parsed = parseFloat(amount);
  if (isNaN(parsed)) return null;
  if (type === "daily") return parsed;
  if (!monthlyWorkingDays || monthlyWorkingDays <= 0) return null;
  return parsed / monthlyWorkingDays;
}
