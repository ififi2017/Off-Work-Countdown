import {
  buildShiftTimeline,
  findEndedShiftOnEndCalendarDay,
  getShiftStartAtMs,
  type ShiftBuildOptions,
  type ShiftTimeline,
} from "@/lib/countdown";

/** A manually opened Web run may still refer to the overnight shift that
 * finished this morning. Prefer that result while the next run is in the
 * future; a day shift before its start still stays in the future. */
export function buildWebCountdownStartShift(
  startTime: string,
  endTime: string,
  now: Date,
  options: ShiftBuildOptions = {},
): ShiftTimeline {
  const live = buildShiftTimeline(startTime, endTime, now, options);
  if (getShiftStartAtMs(live) <= now.getTime()) return live;
  return findEndedShiftOnEndCalendarDay({
    startTime,
    endTime,
    nowMs: now.getTime(),
    // Web starts explicitly entered hours on any day. Saved weekdays affect
    // estimates; they do not forbid a manual run on a rest day.
    workdays: [0, 1, 2, 3, 4, 5, 6],
    options,
  }) ?? live;
}
