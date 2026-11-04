import { describe, expect, it } from "vitest";
import {
  buildShiftTimeline,
  calculateTimelinePayRatio,
  calculateTimelineProgress,
  extendShiftWithOvertime,
  resolveOvertimeEndAtMs,
} from "@/lib/countdown";
import { webOvertimePresentation } from "./web-overtime-presentation";

const hourMs = 60 * 60 * 1000;
const at = (day: number, hour: number, minute = 0) => new Date(2026, 10, day, hour, minute).getTime();
const dayShift = () => buildShiftTimeline("09:00", "17:00", new Date(at(5, 16)));
const paid = (shift: ReturnType<typeof dayShift>, nowMs: number) => 80 * calculateTimelinePayRatio(shift, nowMs);

describe("Web overtime presentation and earned salary", () => {
  it("does not lower earned salary when extending the future end lowers displayed progress", () => {
    const base = dayShift();
    const extended = extendShiftWithOvertime(base, at(5, 19));
    const now = at(5, 16);
    expect(calculateTimelineProgress(extended, now)).toBeLessThan(calculateTimelineProgress(base, now));
    expect(paid(extended, now)).toBe(paid(base, now));
    expect(paid(extended, now)).toBe(70);
    expect(webOvertimePresentation(extended, now, 80, false)).toEqual({
      elapsedOvertimeMs: 0,
      unpaidHourlyRate: null,
      unpaidRateDecreasePercent: null,
    });
  });

  it("includes effective overtime at the original rate when started after the planned end", () => {
    const base = dayShift();
    const extended = extendShiftWithOvertime(base, at(5, 19));
    const now = at(5, 18);
    expect(paid(base, now)).toBe(80);
    expect(paid(extended, now)).toBe(90);
  });

  it("keeps both paid income and the conditional unpaid comparison unchanged when adjusting a future end", () => {
    const extended = extendShiftWithOvertime(dayShift(), at(5, 19));
    const later = extendShiftWithOvertime(extended, at(5, 21));
    const earlier = extendShiftWithOvertime(later, at(5, 18, 30));
    const now = at(5, 18);
    expect(paid(extended, now)).toBe(paid(later, now));
    expect(paid(later, now)).toBe(paid(earlier, now));
    expect(webOvertimePresentation(extended, now, 80, false)).toEqual(webOvertimePresentation(later, now, 80, false));
    expect(webOvertimePresentation(later, now, 80, false)).toEqual(webOvertimePresentation(earlier, now, 80, false));
    expect(resolveOvertimeEndAtMs(later, "17:30", now)).toBeNull();
  });

  it("keeps the paid estimate distinct from a conditional fixed-pay effective hourly rate", () => {
    const shift = extendShiftWithOvertime(dayShift(), at(5, 19));
    const now = at(5, 18);
    const info = webOvertimePresentation(shift, now, 80, false)!;
    expect(info.elapsedOvertimeMs).toBe(hourMs);
    expect(paid(shift, now)).toBe(90);
    expect(info.unpaidHourlyRate).toBeCloseTo(80 / 9);
    expect(info.unpaidRateDecreasePercent).toBeCloseTo((1 - 8 / 9) * 100);
    // Actual estimated pay still earns 10 per effective hour.
    expect(paid(shift, now) / 9).toBe(10);
  });

  it("excludes lunch from elapsed overtime and the hypothetical effective hourly rate", () => {
    const base = buildShiftTimeline("09:00", "18:00", new Date(at(5, 16)), {
      breakStartTime: "12:00",
      breakDurationMinutes: 60,
    });
    const shift = extendShiftWithOvertime(base, at(5, 21));
    const info = webOvertimePresentation(shift, at(5, 19), 80, false)!;
    expect(info.elapsedOvertimeMs).toBe(hourMs);
    expect(info.unpaidHourlyRate).toBeCloseTo(80 / 9);
    expect(paid(shift, at(5, 19))).toBe(90);
    expect(webOvertimePresentation(shift, at(5, 12, 30), 80, false)!.elapsedOvertimeMs).toBe(0);
  });

  it("uses the absolute overnight timeline after midnight", () => {
    const base = buildShiftTimeline("22:00", "06:00", new Date(at(6, 5)));
    const shift = extendShiftWithOvertime(base, at(6, 8));
    const info = webOvertimePresentation(shift, at(6, 7), 80, false)!;
    expect(info.elapsedOvertimeMs).toBe(hourMs);
    expect(info.unpaidHourlyRate).toBeCloseTo(80 / 9);
    expect(paid(shift, at(6, 7))).toBe(90);
  });

  it("stops elapsed overtime and hypothetical dilution at the effective end", () => {
    const shift = extendShiftWithOvertime(dayShift(), at(5, 19));
    const ended = webOvertimePresentation(shift, at(5, 19), 80, false)!;
    expect(ended.elapsedOvertimeMs).toBe(2 * hourMs);
    expect(ended.unpaidHourlyRate).toBe(8);
    expect(ended.unpaidRateDecreasePercent).toBeCloseTo(20);
    expect(webOvertimePresentation(shift, at(6, 8), 80, false)).toEqual(ended);
    expect(paid(shift, at(6, 8))).toBe(100);
  });

  it.each([null, 0, -80, Number.NaN, Number.POSITIVE_INFINITY])("keeps elapsed overtime visible without a positive configured salary (%s)", (salary) => {
    const shift = extendShiftWithOvertime(dayShift(), at(5, 19));
    expect(webOvertimePresentation(shift, at(5, 18), salary, false)).toEqual({
      elapsedOvertimeMs: hourMs,
      unpaidHourlyRate: null,
      unpaidRateDecreasePercent: null,
    });
  });

  it("keeps elapsed overtime visible while omitting all salary-derived values when earnings are hidden", () => {
    const shift = extendShiftWithOvertime(dayShift(), at(5, 19));
    expect(webOvertimePresentation(shift, at(5, 18), 80, true)).toEqual({
      elapsedOvertimeMs: hourMs,
      unpaidHourlyRate: null,
      unpaidRateDecreasePercent: null,
    });
  });

  it("omits overtime context without an overtime session or a valid timeline", () => {
    expect(webOvertimePresentation(null, at(5, 18), 80, false)).toBeNull();
    expect(webOvertimePresentation(dayShift(), at(5, 18), 80, false)).toBeNull();
    const shift = extendShiftWithOvertime(dayShift(), at(5, 19));
    expect(webOvertimePresentation({ ...shift, segments: [] }, at(5, 18), 80, false)).toBeNull();
    expect(webOvertimePresentation(shift, Number.NaN, 80, false)).toBeNull();
  });
});
