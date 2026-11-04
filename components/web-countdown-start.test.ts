import { describe, expect, it } from "vitest";
import {
  buildShiftTimeline,
  extendShiftWithOvertime,
  getShiftEndAtMs,
  getShiftRemainingMs,
  getShiftStartAtMs,
  resolveOvertimeEndAtMs,
} from "@/lib/countdown";
import { decodeShift } from "@/lib/share";
import { buildWebCountdownStartShift } from "./web-countdown-start";

const at = (day: number, hour: number, minute = 0) => new Date(2026, 10, day, hour, minute);

describe("starting the Web countdown", () => {
  it("opens the overnight result after its planned end so the user can begin overtime", () => {
    const now = at(5, 7);
    const shift = buildWebCountdownStartShift("22:00", "06:00", now);
    expect(getShiftStartAtMs(shift)).toBe(at(4, 22).getTime());
    expect(getShiftEndAtMs(shift)).toBe(at(5, 6).getTime());
    expect(getShiftRemainingMs(shift, now.getTime())).toBe(0);
    const overtimeEnd = resolveOvertimeEndAtMs(shift, "08:00", now.getTime());
    expect(overtimeEnd).toBe(at(5, 8).getTime());
    expect(getShiftRemainingMs(extendShiftWithOvertime(shift, overtimeEnd!), now.getTime())).toBe(60 * 60 * 1000);
  });

  it("applies the same initial selection to an overnight shared URL", () => {
    const shared = decodeShift("2200-0600")!;
    const now = at(5, 7);
    const shift = buildWebCountdownStartShift(shared.start, shared.end, now);
    expect(getShiftEndAtMs(shift)).toBe(at(5, 6).getTime());
    expect(resolveOvertimeEndAtMs(shift, "09:15", now.getTime())).toBe(at(5, 9, 15).getTime());
  });

  it("still rejects starting a day shift before its start instead of reviving yesterday", () => {
    const now = at(5, 8);
    const shift = buildWebCountdownStartShift("09:00", "17:00", now);
    expect(getShiftStartAtMs(shift)).toBe(at(5, 9).getTime());
    expect(getShiftStartAtMs(shift)).toBeGreaterThan(now.getTime());
  });

  it.each([at(5, 5), at(5, 22), at(5, 23)])("keeps the currently open overnight timeline at %s", (now) => {
    expect(buildWebCountdownStartShift("22:00", "06:00", now)).toEqual(buildShiftTimeline("22:00", "06:00", now));
  });

  it("keeps manually entered overnight hours available after a rest-day run", () => {
    // Sunday morning follows a Saturday-night shift; Web manual starts are
    // allowed even when the visitor's estimate weekdays are Monday–Friday.
    const shift = buildWebCountdownStartShift("22:00", "06:00", at(8, 7));
    expect(getShiftStartAtMs(shift)).toBe(at(7, 22).getTime());
    expect(getShiftEndAtMs(shift)).toBe(at(8, 6).getTime());
  });

  it("selects the ended overnight exactly at its planned end", () => {
    const shift = buildWebCountdownStartShift("22:00", "06:00", at(5, 6));
    expect(getShiftStartAtMs(shift)).toBe(at(4, 22).getTime());
    expect(getShiftEndAtMs(shift)).toBe(at(5, 6).getTime());
  });

  it("leaves the completed same-day result unchanged", () => {
    const now = at(5, 18);
    expect(buildWebCountdownStartShift("09:00", "17:00", now)).toEqual(buildShiftTimeline("09:00", "17:00", now));
  });
});
