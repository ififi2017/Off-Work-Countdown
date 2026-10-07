import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { staleDesktopHolidayFiles } from "../scripts/generate-desktop-holidays.mjs";
import { holidayCoverageWarning, holidayDay, holidayOverrides, holidayRegionName, suggestedHolidayRegion, type HolidayIndex, type HolidayRegion } from "./holidays";

const read = <T,>(name: string) => JSON.parse(readFileSync(`public/holidays/${name}`, "utf8")) as T;

describe("desktop holiday calendars", () => {
  it("are generated from the current iOS dataset", () => {
    expect(staleDesktopHolidayFiles()).toEqual([]);
  });
  it("reads China's 2026 National Day week and its makeup workday", () => {
    const cn = read<HolidayRegion>("CN.json");
    expect(holidayDay(cn, "2026-10-01", "zh-CN")).toEqual({ isWorkday: false, name: "国庆节" });
    // Unknown languages fall back to the English entry, as on iOS.
    expect(holidayDay(cn, "2026-10-01", "xx")?.name).toBe(cn.names[cn.days["20261001"][1]].en);
    const overrides = holidayOverrides(cn);
    expect(Object.values(overrides)).toContain(true);
    expect(overrides["20261001"]).toBe(false);
    expect(holidayDay(cn, "2026-10-20", "zh-CN")).toBeNull();
  });
  it("warns where the data stops, like iOS", () => {
    const cn = read<HolidayRegion>("CN.json");
    expect(holidayCoverageWarning(cn, 2026, 11)).toBeNull();
    expect(holidayCoverageWarning(cn, 2026, 12)).toEqual({ key: "holidayEstimatedYearWarning", year: 2027 });
    expect(holidayCoverageWarning(cn, 2027, 1)).toEqual({ key: "holidayEstimatedYearWarning", year: 2027 });
    expect(holidayCoverageWarning(cn, 2027, 12)).toEqual({ key: "holidayEstimatedYearWarning", year: 2027 });
    expect(holidayCoverageWarning(cn, 2028, 1)).toEqual({ key: "holidayCoverageYearWarning", year: 2028 });
    // Removing prediction metadata when official data replaces it removes its warning.
    const official = { ...cn, estimatedYears: [] };
    expect(holidayCoverageWarning(official, 2027, 1)).toBeNull();
    expect(holidayCoverageWarning(official, 2026, 12)).toBeNull();
    expect(holidayCoverageWarning(official, 2027, 12)).toEqual({ key: "holidayCoverageNextYearWarning", year: 2028 });
  });
  it("applies the predicted calendar and all five makeup days without extending National Day", () => {
    const cn = read<HolidayRegion>("CN.json");
    const overrides = holidayOverrides(cn);
    expect(cn.estimatedYears).toEqual([2027]);
    for (const date of ["20270131", "20270214", "20270508", "20270926", "20271009"]) {
      expect(overrides[date]).toBe(true);
    }
    for (const date of ["20270101", "20270205", "20270213", "20270405", "20270505", "20270609", "20270915", "20271007"]) {
      expect(overrides[date]).toBe(false);
    }
    expect(overrides["20271008"]).toBeUndefined();
    expect(overrides["20271010"]).toBeUndefined();
  });
  it("suggests the system region and names it in the app language", () => {
    const index = read<HolidayIndex>("index.json");
    expect(Object.keys(index.regions)).toHaveLength(249);
    expect(suggestedHolidayRegion(index, "zh-CN")).toBe("CN");
    expect(suggestedHolidayRegion(index, "en-GB")).toBe("GB");
    expect(suggestedHolidayRegion(index, "ja")).toBe("JP");
    expect(holidayRegionName("TW", "zh-TW")).toBe("台灣");
    expect(holidayRegionName("DE", "zh-CN")).toBe("德国");
  });
});
