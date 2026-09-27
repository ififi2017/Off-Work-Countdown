import { describe, expect, it } from "vitest";
import {
  calculateTimelinePayRatio,
  getActiveBreakEndAtMs,
  getShiftEndAtMs,
  getShiftRemainingMs,
  getShiftStartAtMs,
} from "@/lib/countdown";
import { locales } from "@/i18n-config";
import { readPreferences, resolvePopupShift } from "./state";
import copy from "./copy.json";
import { loadTranslation, translationLocales } from "./translations";
import translationKeys from "./translation-keys.json";
import { readFileSync } from "node:fs";

const time = (day: number, hour: number, minute = 0) =>
  new Date(2026, 8, day, hour, minute).getTime();

describe("extension popup persistence and shared scheduling", () => {
  it("validates stored data without discarding valid preferences or an empty workweek", () => {
    expect(readPreferences("broken", "zh-Hant-HK").lang).toBe("zh-HK");
    const preferences = readPreferences(
      JSON.stringify({
        startTime: "25:00",
        workdays: [],
        salaryAmount: "Infinity",
        monthlyWorkingDays: 0,
        hideEarnings: true,
        lang: "ar",
      }),
      "en",
    );
    expect(preferences).toMatchObject({
      startTime: "09:00",
      workdays: [],
      salaryAmount: "",
      monthlyWorkingDays: 21.75,
      hideEarnings: true,
      lang: "ar",
    });
    expect(resolvePopupShift(preferences, time(28, 10))).toBeNull();
    expect(
      readPreferences(
        '{"startTime":"09:00","endTime":"09:00","running":true}',
        "en",
      ).running,
    ).toBe(false);
  });

  it("reopens during lunch with frozen earnings, then advances using wall time", () => {
    const saved = JSON.stringify({
      ...readPreferences(null, "en"),
      running: true,
      lunchEnabled: true,
    });
    const preferences = readPreferences(saved, "en");
    const lunch = resolvePopupShift(preferences, time(28, 12, 30))!.shift;
    expect(getActiveBreakEndAtMs(lunch, time(28, 12, 30))).toBe(time(28, 13));
    expect(getShiftRemainingMs(lunch, time(28, 12, 30))).toBe(5 * 3_600_000);
    expect(calculateTimelinePayRatio(lunch, time(28, 12, 30))).toBe(3 / 8);
    const reopened = resolvePopupShift(
      readPreferences(saved, "en"),
      time(28, 15),
    )!.shift;
    expect(getShiftRemainingMs(reopened, time(28, 15))).toBe(3 * 3_600_000);
    expect(calculateTimelinePayRatio(reopened, time(28, 15))).toBe(5 / 8);
    const nextDay = resolvePopupShift(preferences, time(29, 10))!.shift;
    expect(getShiftStartAtMs(nextDay)).toBe(time(29, 9));
  });

  it("keeps Friday's overnight shift on Saturday and skips the rest days", () => {
    const preferences = {
      ...readPreferences(null, "en"),
      startTime: "22:00",
      endTime: "06:00",
      running: true,
    };
    const active = resolvePopupShift(preferences, time(26, 1))!;
    expect(getShiftStartAtMs(active.shift)).toBe(time(25, 22));
    expect(getShiftEndAtMs(active.shift)).toBe(time(26, 6));
    const ended = resolvePopupShift(preferences, time(26, 7))!;
    expect(getShiftStartAtMs(ended.shift)).toBe(time(25, 22));
    expect(getShiftStartAtMs(ended.next!)).toBe(time(28, 22));
    const rest = resolvePopupShift(preferences, time(27, 12))!;
    expect(getShiftStartAtMs(rest.shift)).toBe(time(28, 22));
  });

  it("bundles every UI locale and every extension-specific string", async () => {
    expect(Object.keys(copy).sort()).toEqual([...locales].sort());
    expect([...translationLocales].sort()).toEqual([...locales].sort());
    for (const locale of locales) {
      expect(Object.keys(copy[locale]).sort()).toEqual(
        Object.keys(copy.en).sort(),
      );
      const translation = await loadTranslation(locale);
      expect(translation.extensionSave).toBeTruthy();
      expect(translation.offWorkCountdown).toBeTruthy();
      for (const key of translationKeys) {
        expect(translation[key], `${locale}: ${key}`).toBeTruthy();
      }
    }
  });

  it("keeps required shared copy in the filtered production bundle", async () => {
    const included = new Set(translationKeys);
    const en = await loadTranslation("en");
    for (const path of [
      "src-extension/popup.tsx",
      "components/ThemeToggle.tsx",
    ]) {
      const source = readFileSync(path, "utf8");
      // Includes literal keys selected through arrays/ternaries as well as t().
      for (const [, key] of source.matchAll(/"([A-Za-z][A-Za-z0-9]+)"/g)) {
        if (key in en && !(key in copy.en)) {
          expect(included.has(key), `Missing bundled key: ${key}`).toBe(true);
        }
      }
    }
  });
});
