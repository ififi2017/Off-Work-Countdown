import { describe, expect, it } from "vitest";
import {
  buildShiftTimeline,
  calculateTimelinePayRatio,
  extendShiftWithOvertime,
  isValidShiftTimeline,
} from "@/lib/countdown";
import {
  existingOvertimeRestMinutes,
  nearestOvertimeDuration,
  nearestOvertimeRest,
  overtimeDurationChoices,
  overtimeMinimumEndMs,
  overtimePayChoice,
  overtimePayChoiceMultiplier,
  overtimeStartForSession,
  overtimeStartMs,
  withoutOvertime,
} from "./overtime-sheet-plan";

const MINUTE = 60_000;
const planned = 1_000_000_000;

describe("overtime dialog choices (plan 024, iOS OvertimeSheetPlan)", () => {
  it("starts overtime after the rest and needs a minute of it", () => {
    expect(overtimeStartMs(planned, 30)).toBe(planned + 30 * MINUTE);
    expect(overtimeStartForSession(planned, 0)).toBeNull();
    expect(overtimeStartForSession(planned, 15)).toBe(planned + 15 * MINUTE);
    expect(overtimeMinimumEndMs(planned, 0, planned - MINUTE)).toBe(planned);
    expect(overtimeMinimumEndMs(planned, 15, planned - MINUTE)).toBe(planned + 16 * MINUTE);
    expect(overtimeMinimumEndMs(planned, 15, planned + 40 * MINUTE)).toBe(planned + 40 * MINUTE);
  });

  it("offers lengths that still end now or later", () => {
    const retrospective = overtimeDurationChoices(planned, 0, planned + 50 * MINUTE);
    expect(retrospective[0]).toBe(60);
    expect(retrospective[retrospective.length - 1]).toBe(720);
    expect(overtimeDurationChoices(planned, 0, planned - 10 * MINUTE)[0]).toBe(15);
    expect(nearestOvertimeRest(28)).toBe(30);
    expect(nearestOvertimeDuration([15, 30, 45], planned, planned + 40 * MINUTE)).toBe(45);
  });

  it("maps pay choices to the shared multiplier rule", () => {
    expect(overtimePayChoiceMultiplier("unpaid", "")).toBe(0);
    expect(overtimePayChoiceMultiplier("1.5", "")).toBe(1.5);
    expect(overtimePayChoiceMultiplier("custom", "1,2")).toBe(1.2);
    expect(overtimePayChoiceMultiplier("custom", "0")).toBe(1);
    expect(overtimePayChoiceMultiplier("custom", "9")).toBe(1);
    expect(overtimePayChoice(0)).toBe("unpaid");
    expect(overtimePayChoice(2)).toBe("2");
    expect(overtimePayChoice(1.2)).toBe("custom");
  });

  it("replaces an overtime that began after a rest instead of stacking it", () => {
    const shift = buildShiftTimeline("09:00", "17:00", new Date(2026, 10, 5, 16));
    const restStart = overtimeStartForSession(shift.plannedEndAtMs, 30)!;
    const first = extendShiftWithOvertime(shift, shift.plannedEndAtMs + 120 * MINUTE, restStart);
    expect(first.segments).toHaveLength(2);
    expect(existingOvertimeRestMinutes(first)).toBe(30);
    expect(withoutOvertime(first)).toEqual(shift);
    const adjusted = extendShiftWithOvertime(withoutOvertime(first), shift.plannedEndAtMs + 90 * MINUTE, restStart);
    expect(adjusted.segments).toHaveLength(2);
    expect(isValidShiftTimeline(adjusted)).toBe(true);
    // The rest is a break: 60 minutes of overtime at 2× is 2 extra hours of pay over 8.
    expect(calculateTimelinePayRatio(adjusted, shift.plannedEndAtMs + 90 * MINUTE, 2)).toBeCloseTo(10 / 8, 12);
    const stretched = extendShiftWithOvertime(shift, shift.plannedEndAtMs + 60 * MINUTE);
    expect(existingOvertimeRestMinutes(stretched)).toBe(0);
    expect(withoutOvertime(stretched)).toEqual(shift);
  });
});
