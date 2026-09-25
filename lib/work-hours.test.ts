import { describe, expect, it } from "vitest";
import {
  calculateFinishTime,
  calculateHoursWorked,
  formatClockTime,
  parseClockTime,
  splitMinutes,
} from "./work-hours";

describe("work hours calculator", () => {
  it("parses and formats clock times strictly", () => {
    expect(parseClockTime("09:30")).toBe(570);
    expect(parseClockTime("23:59")).toBe(1439);
    expect(parseClockTime("24:00")).toBeNull();
    expect(parseClockTime("9:30")).toBeNull();
    expect(formatClockTime(1530)).toBe("01:30");
    expect(formatClockTime(-30)).toBe("23:30");
  });

  it("answers how many hours 9 to 5 and 9 to 6 are", () => {
    expect(calculateHoursWorked("09:00", "17:00", 0)).toEqual({
      spanMinutes: 480,
      breakMinutes: 0,
      paidMinutes: 480,
      overnight: false,
    });
    expect(calculateHoursWorked("09:00", "17:00", 30)?.paidMinutes).toBe(450);
    expect(calculateHoursWorked("09:00", "18:00", 60)?.paidMinutes).toBe(480);
  });

  it("counts overnight shifts into the next day, like the countdown", () => {
    const night = calculateHoursWorked("22:00", "06:00", 30);
    expect(night?.spanMinutes).toBe(480);
    expect(night?.paidMinutes).toBe(450);
    expect(night?.overnight).toBe(true);
    expect(calculateHoursWorked("08:00", "08:00", 0)?.spanMinutes).toBe(1440);
  });

  it("rejects a break that fills the whole shift", () => {
    expect(calculateHoursWorked("09:00", "10:00", 60)).toBeNull();
    expect(calculateHoursWorked("09:00", "17:00", -5)).toBeNull();
  });

  it("works out the finish time from start, hours and break", () => {
    expect(calculateFinishTime("08:30", 480, 30)).toEqual({
      end: "17:00",
      dayOffset: 0,
      spanMinutes: 510,
    });
    expect(calculateFinishTime("07:45", 7 * 60 + 48, 45)?.end).toBe("16:18");
    expect(calculateFinishTime("20:00", 600, 60)).toEqual({
      end: "07:00",
      dayOffset: 1,
      spanMinutes: 660,
    });
  });

  it("refuses spans that reach a full day", () => {
    expect(calculateFinishTime("09:00", 1380, 60)).toBeNull();
    expect(calculateFinishTime("09:00", 0, 0)).toBeNull();
    expect(calculateFinishTime("9:00", 480, 0)).toBeNull();
  });

  it("splits minutes for duration templates", () => {
    expect(splitMinutes(450)).toEqual({ hours: 7, minutes: 30 });
    expect(splitMinutes(-3)).toEqual({ hours: 0, minutes: 0 });
  });
});
