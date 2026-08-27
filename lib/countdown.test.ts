import { describe, it, expect } from "vitest";
import {
  atTime,
  buildShiftTimeline,
  calculateTimelineProgress,
  calculateTimelinePayRatio,
  getShiftBounds,
  calculateProgress,
  getShiftDurationMs,
  getPlannedShiftDurationMs,
  getShiftElapsedMs,
  getShiftRemainingMs,
  getActiveBreakEndAtMs,
  isValidShiftTimeline,
  extendShiftWithOvertime,
  findNextShiftTimeline,
  findEndedShiftOnEndCalendarDay,
  getShiftStartAtMs,
  getShiftEndAtMs,
  resolveOvertimeEndAtMs,
  suggestOvertimeEndAtMs,
  getDailySalary,
  getShiftLengthHours,
  DEFAULT_MONTHLY_WORKING_DAYS,
  DEFAULT_WORKDAYS,
  parseWorkdays,
  serializeWorkdays,
  isWorkday,
  isScheduledWorkday,
  findNextRestDate,
} from "./countdown";
import { presets, getPreset, presetSlugs } from "./presets";

// Fixed reference date to keep tests deterministic
const day = (h: number, m = 0) => {
  const d = new Date(2026, 6, 3); // 2026-07-03 local time
  d.setHours(h, m, 0, 0);
  return d;
};

describe("atTime", () => {
  it("builds a date at the given HH:mm on the same day", () => {
    const d = atTime(day(15, 30), "09:05");
    expect(d.getHours()).toBe(9);
    expect(d.getMinutes()).toBe(5);
    expect(d.getDate()).toBe(3);
  });
});

describe("getShiftBounds", () => {
  it("keeps a normal day shift on the same day", () => {
    const { start, end } = getShiftBounds("09:00", "18:00", day(12));
    expect(start.getHours()).toBe(9);
    expect(end.getHours()).toBe(18);
    expect(start.getDate()).toBe(3);
    expect(end.getDate()).toBe(3);
  });

  it("extends an overnight shift's end into the next day (before midnight)", () => {
    const { start, end } = getShiftBounds("22:00", "06:00", day(23));
    expect(start.getDate()).toBe(3);
    expect(end.getDate()).toBe(4);
  });

  it("anchors an overnight shift's start to the previous day (after midnight)", () => {
    const { start, end } = getShiftBounds("22:00", "06:00", day(1));
    expect(start.getDate()).toBe(2); // started yesterday
    expect(end.getDate()).toBe(3);
    expect(start <= day(1)).toBe(true);
  });

  it("treats off-hours in an overnight schedule as the upcoming shift", () => {
    const { start, end } = getShiftBounds("22:00", "06:00", day(12));
    expect(start.getDate()).toBe(3);
    expect(end.getDate()).toBe(4);
    expect(start > day(12)).toBe(true); // start still in the future
  });
});

describe("calculateProgress", () => {
  it("is 50% at the midpoint of a day shift", () => {
    expect(calculateProgress("09:00", "17:00", day(13))).toBeCloseTo(50);
  });

  it("is 0% at shift start and 100% at shift end", () => {
    expect(calculateProgress("09:00", "17:00", day(9))).toBe(0);
    expect(calculateProgress("09:00", "17:00", day(17))).toBe(100);
  });

  it("clamps to 100 after the shift ends", () => {
    expect(calculateProgress("09:00", "17:00", day(20))).toBe(100);
  });

  it("handles overnight shifts after midnight", () => {
    // 22:00–06:00 shift, at 02:00 → 4h of 8h done
    expect(calculateProgress("22:00", "06:00", day(2))).toBeCloseTo(50);
  });
});

describe("segmented shift timeline", () => {
  const hour = 60 * 60 * 1000;
  const at = (hours: number, minutes = 0) =>
    new Date(2026, 6, 3, hours, minutes).getTime();

  it("builds the existing schedule as one segment", () => {
    const shift = buildShiftTimeline("09:00", "18:00", day(12));
    expect(shift).toEqual({
      segments: [{ startAtMs: at(9), endAtMs: at(18) }],
      plannedEndAtMs: at(18),
      overtimeEndAtMs: null,
    });
    expect(getShiftDurationMs(shift)).toBe(9 * hour);
  });

  it("does not count down or accrue progress between segments", () => {
    const shift = {
      segments: [
        { startAtMs: at(9), endAtMs: at(12) },
        { startAtMs: at(13), endAtMs: at(18) },
      ],
      plannedEndAtMs: at(18),
      overtimeEndAtMs: null,
    };

    expect(isValidShiftTimeline(shift)).toBe(true);
    expect(getShiftDurationMs(shift)).toBe(8 * hour);
    expect(getShiftElapsedMs(shift, at(12, 30))).toBe(3 * hour);
    expect(getShiftElapsedMs(shift, at(13))).toBe(3 * hour);
    expect(getShiftRemainingMs(shift, at(12, 30))).toBe(5 * hour);
    expect(getShiftRemainingMs(shift, at(13))).toBe(5 * hour);
    expect(calculateTimelineProgress(shift, at(12, 30))).toBeCloseTo(37.5);
  });

  it("keeps the planned end separate from an overtime end", () => {
    const shift = {
      segments: [{ startAtMs: at(9), endAtMs: at(20) }],
      plannedEndAtMs: at(18),
      overtimeEndAtMs: at(20),
    };

    expect(isValidShiftTimeline(shift)).toBe(true);
    expect(getShiftDurationMs(shift)).toBe(11 * hour);
    expect(getPlannedShiftDurationMs(shift)).toBe(9 * hour);
    expect(calculateTimelineProgress(shift, at(18))).toBeCloseTo(100 * 9 / 11);
    expect(calculateTimelinePayRatio(shift, at(18))).toBeCloseTo(1);
    expect(calculateTimelinePayRatio(shift, at(20))).toBeCloseTo(11 / 9);
  });

  it("rejects overlapping or inconsistent snapshots", () => {
    expect(
      isValidShiftTimeline({
        segments: [
          { startAtMs: at(9), endAtMs: at(13) },
          { startAtMs: at(12), endAtMs: at(18) },
        ],
        plannedEndAtMs: at(18),
        overtimeEndAtMs: null,
      })
    ).toBe(false);
    expect(
      isValidShiftTimeline({
        segments: [{ startAtMs: at(9), endAtMs: at(17) }],
        plannedEndAtMs: at(18),
        overtimeEndAtMs: null,
      })
    ).toBe(false);
    expect(
      isValidShiftTimeline({
        segments: [
          { startAtMs: at(9), endAtMs: at(12) },
          { startAtMs: at(13), endAtMs: at(18) },
        ],
        // 原定下班点不能藏在午休缺口里；否则前端与 Rust 会对计划工时产生
        // 不同解释，薪资比例也会失真。
        plannedEndAtMs: at(12, 30),
        overtimeEndAtMs: at(18),
      })
    ).toBe(false);
  });

  it("cuts an enabled lunch break out of effective work time", () => {
    const shift = buildShiftTimeline("09:00", "18:00", day(10), {
      breakStartTime: "12:00",
      breakDurationMinutes: 60,
    });
    expect(shift.segments).toEqual([
      { startAtMs: at(9), endAtMs: at(12) },
      { startAtMs: at(13), endAtMs: at(18) },
    ]);
    expect(getShiftDurationMs(shift)).toBe(8 * hour);
    expect(getShiftRemainingMs(shift, at(12, 30))).toBe(5 * hour);
    expect(calculateTimelinePayRatio(shift, at(12, 30))).toBeCloseTo(3 / 8);
  });

  it("places an overnight lunch time on the correct calendar day", () => {
    const now = new Date(2026, 6, 3, 23, 0, 0, 0);
    const shift = buildShiftTimeline("22:00", "06:00", now, {
      breakStartTime: "02:00",
      breakDurationMinutes: 30,
    });
    expect(new Date(shift.segments[0].endAtMs).getDate()).toBe(4);
    expect(new Date(shift.segments[0].endAtMs).getHours()).toBe(2);
    expect(new Date(shift.segments[1].startAtMs).getHours()).toBe(2);
    expect(new Date(shift.segments[1].startAtMs).getMinutes()).toBe(30);
    expect(getShiftDurationMs(shift)).toBe(7.5 * hour);
  });

  it("extends only the final segment when overtime is accepted", () => {
    const base = buildShiftTimeline("09:00", "18:00", day(10), {
      breakStartTime: "12:00",
      breakDurationMinutes: 60,
    });
    const extended = extendShiftWithOvertime(base, at(20));
    expect(extended.plannedEndAtMs).toBe(at(18));
    expect(extended.overtimeEndAtMs).toBe(at(20));
    expect(extended.segments[0]).toEqual(base.segments[0]);
    expect(extended.segments[1].endAtMs).toBe(at(20));
    expect(getShiftDurationMs(extended)).toBe(10 * hour);
  });

  it("suggests a future quarter-hour when overtime is added after work", () => {
    const shift = buildShiftTimeline("09:00", "18:00", day(12));
    expect(new Date(suggestOvertimeEndAtMs(shift, at(23, 52))).getHours()).toBe(1);
    expect(new Date(suggestOvertimeEndAtMs(shift, at(23, 52))).getMinutes()).toBe(0);
    expect(new Date(suggestOvertimeEndAtMs(shift, at(23, 52))).getDate()).toBe(4);
    expect(resolveOvertimeEndAtMs(shift, "01:00", at(23, 52))).toBe(
      new Date(2026, 6, 4, 1, 0).getTime()
    );
  });

  it("replaces an expired overtime end with a new future suggestion", () => {
    const base = buildShiftTimeline("09:00", "18:00", day(12));
    const extended = extendShiftWithOvertime(base, at(20));
    expect(suggestOvertimeEndAtMs(extended, at(19))).toBe(at(20));
    expect(suggestOvertimeEndAtMs(extended, at(20, 30))).toBe(at(21, 30));
  });

  it("rejects an overtime clock that already passed instead of adding 24 hours", () => {
    const shift = buildShiftTimeline("09:00", "18:00", day(12));
    expect(resolveOvertimeEndAtMs(shift, "18:00", at(18, 10))).toBeNull();
    expect(resolveOvertimeEndAtMs(shift, "18:30", at(19))).toBeNull();
  });

  it("requires overtime to end strictly after the planned shift", () => {
    const shift = buildShiftTimeline("09:00", "18:00", day(12));
    expect(resolveOvertimeEndAtMs(shift, "18:00", at(17))).toBeNull();
    expect(resolveOvertimeEndAtMs(shift, "18:30", at(17))).toBe(at(18, 30));
  });

  it("finds the next configured workday without moving schedule rules to Rust", () => {
    const fridayAfterWork = new Date(2026, 6, 3, 19, 0, 0, 0);
    const next = findNextShiftTimeline({
      startTime: "09:00",
      endTime: "18:00",
      workdays: DEFAULT_WORKDAYS,
      afterMs: fridayAfterWork.getTime(),
      options: { breakStartTime: "12:00", breakDurationMinutes: 60 },
    });
    expect(next).not.toBeNull();
    const start = new Date(next!.segments[0].startAtMs);
    expect(start.getDay()).toBe(1);
    expect(start.getDate()).toBe(6);
    expect(next!.segments).toHaveLength(2);
  });

  it("returns no next shift when every workday is disabled", () => {
    expect(
      findNextShiftTimeline({
        startTime: "09:00",
        endTime: "18:00",
        workdays: [],
        afterMs: day(19).getTime(),
      })
    ).toBeNull();
  });

  it("supports alternating single/double weekends from a reference week", () => {
    const referenceMonday = new Date(2026, 5, 29).getTime();
    const schedule = {
      mode: "alternating" as const,
      referenceWeekStartMs: referenceMonday,
      referenceWeekType: "single" as const,
      singleWeekendWorkday: 6 as const,
    };
    expect(isScheduledWorkday(new Date(2026, 6, 4), [], schedule)).toBe(true);
    expect(isScheduledWorkday(new Date(2026, 6, 5), [], schedule)).toBe(false);
    expect(isScheduledWorkday(new Date(2026, 6, 11), [], schedule)).toBe(false);
  });

  it("supports calendar-safe work/rest rotations and finds the next rest day", () => {
    const schedule = {
      mode: "rotation" as const,
      rotationAnchorMs: new Date(2026, 6, 1).getTime(),
      rotationWorkDays: 2,
      rotationRestDays: 2,
    };
    expect(isScheduledWorkday(new Date(2026, 6, 1), [], schedule)).toBe(true);
    expect(isScheduledWorkday(new Date(2026, 6, 2), [], schedule)).toBe(true);
    expect(isScheduledWorkday(new Date(2026, 6, 3), [], schedule)).toBe(false);
    expect(findNextRestDate({
      afterMs: new Date(2026, 6, 1, 12).getTime(),
      workdays: [],
      schedule,
    })?.getDate()).toBe(3);
  });

  it("turns off schedule gating and automatic next-shift projection", () => {
    expect(isScheduledWorkday(new Date(2026, 6, 5), [], { mode: "off" })).toBe(true);
    expect(findNextShiftTimeline({
      startTime: "09:00",
      endTime: "18:00",
      workdays: DEFAULT_WORKDAYS,
      afterMs: day(19).getTime(),
      schedule: { mode: "off" },
    })).toBeNull();
  });
});

describe("getDailySalary", () => {
  it("returns the amount as-is for daily salaries", () => {
    expect(getDailySalary("500", "daily")).toBe(500);
  });

  it("divides monthly salaries by the working-day count", () => {
    expect(getDailySalary("10000", "monthly", 20)).toBeCloseTo(500);
  });

  it("uses the default working days when none is given", () => {
    expect(getDailySalary("21750", "monthly")).toBeCloseTo(
      21750 / DEFAULT_MONTHLY_WORKING_DAYS
    );
  });

  it("returns null for empty or invalid input", () => {
    expect(getDailySalary("", "monthly")).toBeNull();
    expect(getDailySalary("abc", "daily")).toBeNull();
    expect(getDailySalary("500oops", "daily")).toBeNull();
    expect(getDailySalary("-1", "daily")).toBeNull();
    expect(getDailySalary("Infinity", "daily")).toBeNull();
    expect(getDailySalary("10000", "monthly", 0)).toBeNull();
    expect(getDailySalary("10000", "monthly", 32)).toBeNull();
  });

  it("allows a zero salary without treating it as missing", () => {
    expect(getDailySalary("0", "daily")).toBe(0);
  });

  it("annualizes bonus months for both monthly and daily salaries", () => {
    expect(getDailySalary("10000", "monthly", 20, 2)).toBeCloseTo(
      (10000 / 20) * (14 / 12)
    );
    expect(getDailySalary("500", "daily", 20, 2)).toBeCloseTo(
      500 * (14 / 12)
    );
  });

  it("accepts manually entered bonuses above twelve months", () => {
    expect(getDailySalary("10000", "monthly", 20, -1)).toBeNull();
    expect(getDailySalary("10000", "monthly", 20, 25)).toBeCloseTo(
      (10000 / 20) * (37 / 12)
    );
  });
});

describe("getShiftLengthHours", () => {
  it("measures a same-day shift", () => {
    expect(getShiftLengthHours("09:00", "18:00")).toBe(9);
    expect(getShiftLengthHours("09:00", "17:30")).toBe(8.5);
  });

  it("carries an overnight shift into the next day", () => {
    expect(getShiftLengthHours("22:00", "06:00")).toBe(8);
    expect(getShiftLengthHours("23:30", "07:15")).toBe(7.75);
  });

  it("treats an identical start and end as a full 24 hours", () => {
    expect(getShiftLengthHours("09:00", "09:00")).toBe(24);
  });
});

describe("presets", () => {
  it("exposes unique slugs that are URL-safe", () => {
    expect(new Set(presetSlugs).size).toBe(presetSlugs.length);
    for (const slug of presetSlugs) {
      expect(slug).toMatch(/^[a-z0-9-]+$/);
      expect(encodeURIComponent(slug)).toBe(slug);
    }
  });

  it("derives the documented daily and weekly hours", () => {
    const hours = (slug: string) => {
      const p = getPreset(slug)!;
      const perDay = getShiftLengthHours(p.shift.start, p.shift.end);
      return { perDay, perWeek: perDay * p.daysPerWeek };
    };
    expect(hours("996")).toEqual({ perDay: 12, perWeek: 72 });
    expect(hours("9-to-5")).toEqual({ perDay: 8, perWeek: 40 });
    expect(hours("9-to-6")).toEqual({ perDay: 9, perWeek: 45 });
    expect(hours("night-shift")).toEqual({ perDay: 8, perWeek: 40 });
  });

  it("returns undefined for an unknown slug rather than a default", () => {
    expect(getPreset("nope")).toBeUndefined();
  });

  it("every preset has a valid shift", () => {
    for (const p of presets) {
      expect(p.shift.start).toMatch(/^\d{2}:\d{2}$/);
      expect(p.shift.end).toMatch(/^\d{2}:\d{2}$/);
      expect(p.daysPerWeek).toBeGreaterThan(0);
      expect(p.daysPerWeek).toBeLessThanOrEqual(7);
    }
  });
});

describe("workdays", () => {
  it("round-trips through storage, sorted and de-duplicated", () => {
    expect(serializeWorkdays([5, 1, 1, 3])).toBe("1,3,5");
    expect(parseWorkdays("1,3,5")).toEqual([1, 3, 5]);
  });

  it("falls back to Mon-Fri only when nothing was ever stored", () => {
    expect(parseWorkdays(null)).toEqual(DEFAULT_WORKDAYS);
    expect(parseWorkdays(undefined)).toEqual(DEFAULT_WORKDAYS);
  });

  it("treats an empty string as 'no workdays', not as unset", () => {
    // 这两者必须区分：用户主动清空所有工作日是合法状态，不该被当成没设过
    expect(parseWorkdays("")).toEqual([]);
    expect(serializeWorkdays([])).toBe("");
  });

  it("discards out-of-range and malformed entries", () => {
    expect(parseWorkdays("1,7,-1,abc,3")).toEqual([1, 3]);
    expect(serializeWorkdays([1, 9, -2, 6])).toBe("1,6");
  });

  it("judges an overnight shift by the day it started, not by 'today'", () => {
    // 2026-07-03 是周五。22:00 开始、次日 06:00 结束的夜班，
    // 在周六凌晨两点查看时仍应算作周五那一班。
    const saturdayEarly = new Date(2026, 6, 4, 2, 0, 0, 0);
    const { start } = getShiftBounds("22:00", "06:00", saturdayEarly);
    expect(start.getDay()).toBe(5); // 周五
    expect(isWorkday(start, DEFAULT_WORKDAYS)).toBe(true);

    // 而周六晚上开始的那一班属于周六，默认设置下不是工作日
    const saturdayNight = new Date(2026, 6, 4, 23, 0, 0, 0);
    const later = getShiftBounds("22:00", "06:00", saturdayNight);
    expect(later.start.getDay()).toBe(6);
    expect(isWorkday(later.start, DEFAULT_WORKDAYS)).toBe(false);
  });

  it("respects a custom workday set", () => {
    const sunday = new Date(2026, 6, 5, 10, 0, 0, 0); // 2026-07-05 周日
    expect(isWorkday(sunday, DEFAULT_WORKDAYS)).toBe(false);
    expect(isWorkday(sunday, [0, 6])).toBe(true);
  });
});

describe("findEndedShiftOnEndCalendarDay", () => {
  const overnight = {
    startTime: "22:00",
    endTime: "06:00",
    workdays: DEFAULT_WORKDAYS,
  };

  it("keeps Friday night's overnight shift on Saturday after 06:00", () => {
    // 2026-07-03 周五 22:00 – 2026-07-04 周六 06:00
    const saturdayMorning = new Date(2026, 6, 4, 6, 30);
    const ended = findEndedShiftOnEndCalendarDay({
      ...overnight,
      nowMs: saturdayMorning.getTime(),
    });
    expect(ended).not.toBeNull();
    expect(new Date(getShiftStartAtMs(ended!)).getDay()).toBe(5);
    expect(new Date(getShiftEndAtMs(ended!)).getDate()).toBe(4);
    expect(getShiftRemainingMs(ended!, saturdayMorning.getTime())).toBe(0);
  });

  it("does not invent a settlement window on Sunday", () => {
    const sundayMorning = new Date(2026, 6, 5, 0, 30);
    expect(
      findEndedShiftOnEndCalendarDay({
        ...overnight,
        nowMs: sundayMorning.getTime(),
      })
    ).toBeNull();
  });

  it("does not fire while the overnight shift is still running", () => {
    const saturdayBeforeEnd = new Date(2026, 6, 4, 5, 0);
    expect(
      findEndedShiftOnEndCalendarDay({
        ...overnight,
        nowMs: saturdayBeforeEnd.getTime(),
      })
    ).toBeNull();
  });

  it("keeps a forced rest-day overnight on settlement after 06:00", () => {
    const sundayMorning = new Date(2026, 6, 5, 6, 30);
    const saturdayStart = new Date(2026, 6, 4).setHours(0, 0, 0, 0);
    expect(
      findEndedShiftOnEndCalendarDay({
        ...overnight,
        nowMs: sundayMorning.getTime(),
      })
    ).toBeNull();
    const ended = findEndedShiftOnEndCalendarDay({
      ...overnight,
      nowMs: sundayMorning.getTime(),
      forcedWorkdayStartMs: saturdayStart,
    });
    expect(ended).not.toBeNull();
    expect(new Date(getShiftStartAtMs(ended!)).getDay()).toBe(6);
    expect(getShiftRemainingMs(ended!, sundayMorning.getTime())).toBe(0);
  });
});

describe("getActiveBreakEndAtMs", () => {
  const shift = {
    segments: [
      { startAtMs: 1_000, endAtMs: 2_000 },
      { startAtMs: 3_000, endAtMs: 5_000 },
    ],
    plannedEndAtMs: 5_000,
    overtimeEndAtMs: null,
  };

  it("reports the end of the gap while inside it", () => {
    expect(getActiveBreakEndAtMs(shift, 2_000)).toBe(3_000);
    expect(getActiveBreakEndAtMs(shift, 2_999)).toBe(3_000);
  });

  it("returns null while working, and at the exact moment work resumes", () => {
    expect(getActiveBreakEndAtMs(shift, 1_500)).toBeNull();
    // 边界属于工作段：3_000 是下半场的第一毫秒，不能还算在午休里。
    expect(getActiveBreakEndAtMs(shift, 3_000)).toBeNull();
    expect(getActiveBreakEndAtMs(shift, 4_000)).toBeNull();
  });

  it("returns null before the shift and after it ends", () => {
    expect(getActiveBreakEndAtMs(shift, 500)).toBeNull();
    expect(getActiveBreakEndAtMs(shift, 9_000)).toBeNull();
  });

  it("returns null for a shift without gaps", () => {
    expect(
      getActiveBreakEndAtMs(
        { segments: [{ startAtMs: 0, endAtMs: 10 }], plannedEndAtMs: 10, overtimeEndAtMs: null },
        5
      )
    ).toBeNull();
  });
});
