import { describe, expect, it } from "vitest";
import { buildShiftTimeline, findNextShiftTimeline, isScheduledWorkday } from "./countdown";
import { projectWatchSnapshot } from "./watch-projection";

const zone = "Asia/Shanghai";
const workdays = [1, 2, 3, 4, 5];
const options = { breakStartTime: "12:00", breakDurationMinutes: 60 };

function projection(at: string, scheduleConfigured = true, sessionRunning = false) {
  const nowMs = new Date(at).getTime();
  const currentShift = buildShiftTimeline("09:00", "18:00", new Date(nowMs), options, zone);
  const nextShift = findNextShiftTimeline({
    startTime: "09:00", endTime: "18:00", workdays,
    schedule: { mode: "classic" }, afterMs: Math.max(nowMs, currentShift.plannedEndAtMs),
    options, timeZone: zone,
  });
  return projectWatchSnapshot({
    nowMs, scheduleConfigured, isRunning: sessionRunning, currentShift,
    currentIsActual: isScheduledWorkday(
      new Date(currentShift.segments[0].startAtMs), workdays, { mode: "classic" }, zone
    ),
    nextShift, timeZone: zone,
  });
}

describe("Watch rules projection", () => {
  it("keeps a rest weekend valid exactly until the next shift begins", () => {
    const result = projection("2026-08-22T10:00:00+08:00");
    const monday = new Date("2026-08-24T09:00:00+08:00").getTime();
    expect(result.shift).toBeNull();
    expect(result.nextShift).toEqual({ startAtMs: monday, validUntilMs: monday });
    expect(result.contentExpiresAtMs).toBe(monday);
  });

  it("emits rule-owned work, lunch and finish boundaries", () => {
    const result = projection("2026-08-21T10:00:00+08:00", true, true);
    expect(result.shift?.transitions.map(({ state }) => state)).toEqual([
      "working", "lunch", "working", "finished",
    ]);
  });

  it("keeps a manual running session when automatic scheduling is off", () => {
    const nowMs = new Date("2026-08-22T10:00:00+08:00").getTime();
    const currentShift = buildShiftTimeline("09:00", "18:00", new Date(nowMs), options, zone);
    const result = projectWatchSnapshot({
      nowMs, scheduleConfigured: false, isRunning: true, currentShift,
      currentShiftOverride: currentShift, currentIsActual: false,
      nextShift: null, timeZone: zone,
    });
    expect(result.scheduleState).toBe("scheduled");
    expect(result.shift?.isRunning).toBe(true);
  });

  it("keeps an overnight manual session valid through its settlement day", () => {
    const nowMs = new Date("2026-08-22T23:00:00+08:00").getTime();
    const currentShift = buildShiftTimeline("22:00", "06:00", new Date(nowMs), {}, zone);
    const result = projectWatchSnapshot({
      nowMs, scheduleConfigured: false, isRunning: true, currentShift,
      currentShiftOverride: currentShift, currentIsActual: false, nextShift: null, timeZone: zone,
    });
    expect(result.shift?.transitions.at(-1)?.atMs).toBe(new Date("2026-08-23T06:00:00+08:00").getTime());
    expect(result.contentExpiresAtMs).toBe(new Date("2026-08-24T00:00:00+08:00").getTime());
  });

  it("marks a retained manual session stopped when it is no longer running", () => {
    const nowMs = new Date("2026-08-22T10:00:00+08:00").getTime();
    const currentShift = buildShiftTimeline("09:00", "18:00", new Date(nowMs), options, zone);
    const result = projectWatchSnapshot({
      nowMs, scheduleConfigured: false, isRunning: false, currentShift,
      currentShiftOverride: currentShift, currentIsActual: false, nextShift: null, timeZone: zone,
    });
    expect(result.scheduleState).toBe("stopped");
    expect(result.shift?.isRunning).toBe(false);
  });

  it("uses the frozen early-finish boundary instead of the rebuilt plan", () => {
    const nowMs = new Date("2026-08-21T15:00:00+08:00").getTime();
    const finishedAtMs = new Date("2026-08-21T14:00:00+08:00").getTime();
    const currentShift = buildShiftTimeline("09:00", "18:00", new Date(nowMs), options, zone);
    const result = projectWatchSnapshot({
      nowMs, scheduleConfigured: true, isRunning: true, currentShift,
      currentShiftOverride: currentShift, finishedAtMs, currentIsActual: true,
      nextShift: null, timeZone: zone,
    });
    expect(result.shift?.plannedEndAtMs).toBe(new Date("2026-08-21T18:00:00+08:00").getTime());
    expect(result.shift?.segments.at(-1)?.endAtMs).toBe(new Date("2026-08-21T18:00:00+08:00").getTime());
    expect(result.shift?.finishedAtMs).toBe(finishedAtMs);
    expect(result.shift?.transitions.at(-1)).toEqual({ atMs: finishedAtMs, state: "finished" });
    expect(result.shift?.isRunning).toBe(false);
  });

  it("does not invent paid segments when clock-off happens during lunch", () => {
    const nowMs = new Date("2026-08-21T12:30:00+08:00").getTime();
    const currentShift = buildShiftTimeline("09:00", "18:00", new Date(nowMs), options, zone);
    const result = projectWatchSnapshot({
      nowMs, scheduleConfigured: true, isRunning: true, currentShift,
      currentShiftOverride: currentShift, finishedAtMs: nowMs,
      currentIsActual: true, nextShift: null, timeZone: zone,
    });
    expect(result.shift?.finishedAtMs).toBe(nowMs);
    expect(result.shift?.plannedEndAtMs).toBe(new Date("2026-08-21T18:00:00+08:00").getTime());
  });

  it("emits a scheduled empty state to replace stale running content", () => {
    const nowMs = new Date("2026-08-22T10:00:00+08:00").getTime();
    const currentShift = buildShiftTimeline("09:00", "18:00", new Date(nowMs), options, zone);
    const result = projectWatchSnapshot({
      nowMs, scheduleConfigured: true, isRunning: true, currentShift,
      currentIsActual: false, nextShift: null, timeZone: zone,
    });
    expect(result).toMatchObject({ scheduleState: "scheduled", shift: null, nextShift: null });
  });

  it("refreshes an unconfigured empty state at the next civil day", () => {
    const result = projection("2026-08-22T10:00:00+08:00", false);
    expect(result.scheduleState).toBe("notConfigured");
    expect(result.shift).toBeNull();
    expect(result.nextShift).toBeNull();
    expect(result.contentExpiresAtMs).toBe(new Date("2026-08-23T00:00:00+08:00").getTime());
  });

  it("does not leak the default workday before setup completes", () => {
    const nowMs = new Date("2026-08-21T10:00:00+08:00").getTime();
    const currentShift = buildShiftTimeline("09:00", "18:00", new Date(nowMs), options, zone);
    const result = projectWatchSnapshot({
      nowMs, scheduleConfigured: false, isRunning: false, currentShift,
      currentIsActual: true, nextShift: null, timeZone: zone,
    });
    expect(result).toMatchObject({ scheduleState: "notConfigured", shift: null, nextShift: null });
  });
});
