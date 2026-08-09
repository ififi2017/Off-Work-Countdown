import { describe, expect, it } from "vitest";
import {
  emptyDesktopCountdownState,
  formatDesktopDuration,
  getDesktopCountdownView,
} from "./desktop-state";

describe("desktop countdown state", () => {
  it("formats a language-neutral duration without wrapping at 24 hours", () => {
    expect(formatDesktopDuration(25 * 60 * 60 * 1000 + 61_000)).toBe(
      "25:01:01"
    );
    expect(formatDesktopDuration(-1)).toBe("0:00:00");
  });

  it("derives progress and earned salary from absolute timestamps", () => {
    const state = {
      ...emptyDesktopCountdownState(),
      startAtMs: 1_000,
      endAtMs: 11_000,
      running: true,
      showSalary: true,
      dailySalary: 200,
    };

    expect(getDesktopCountdownView(state, 6_000)).toEqual({
      time: "0:00:05",
      progress: 50,
      earned: 100,
    });
  });

  it("returns an idle view when no countdown is active", () => {
    expect(
      getDesktopCountdownView(emptyDesktopCountdownState(), Date.now())
    ).toEqual({ time: "--:--:--", progress: 0, earned: null });
  });
});
