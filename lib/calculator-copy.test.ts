import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { locales } from "@/i18n-config";

// 工时计算器的界面文案 19 种语言都要齐：同一组键、同样的占位符，
// 而且不能把英文原样留在别的语言里（与 lib/locales.test.ts 同一个哨兵思路）。

type Copy = Record<string, string | string[]>;

const load = (locale: string): Copy =>
  JSON.parse(
    readFileSync(
      `${process.cwd()}/public/locales/${locale}/calculator.json`,
      "utf8"
    )
  );

// 与英文相同也合理的键：单位缩写、只有占位符的时长模板，以及目标语言
// 本来就借用的英文词（德语的 Countdown）。
const SAME_AS_ENGLISH_ON_PURPOSE: Record<string, readonly string[]> = {
  hoursUnit: ["fr", "es", "it", "pt"],
  minutesUnit: ["fr", "es", "it", "pt"],
  breakMinutes: ["fr", "es", "it", "pt"],
  durationHM: ["fr", "es", "it", "pt"],
  durationH: ["fr", "es", "it", "pt"],
  durationM: ["fr", "es", "it", "pt"],
  backToApp: ["de"],
};

const placeholders = (value: string | string[]): string[] =>
  [...JSON.stringify(value).matchAll(/\{\{(\w+)\}\}/g)]
    .map((match) => match[1])
    .sort();

describe("work hours calculator copy", () => {
  const english = load("en");

  it("has every key, with the same placeholders, in all 19 locales", () => {
    expect(locales).toHaveLength(19);
    for (const locale of locales) {
      const copy = load(locale);
      expect(Object.keys(copy), locale).toEqual(Object.keys(english));
      for (const [key, value] of Object.entries(english)) {
        expect(placeholders(copy[key]), `${locale} ${key}`).toEqual(
          placeholders(value)
        );
        expect(String(copy[key]).trim().length, `${locale} ${key}`).toBeGreaterThan(0);
      }
      expect(copy.howBody, locale).toHaveLength(2);
    }
  });

  it("does not leave English copy in other locales", () => {
    for (const locale of locales) {
      if (locale === "en") continue;
      const copy = load(locale);
      for (const [key, value] of Object.entries(english)) {
        if (key === "adEyebrow") continue; // 以品牌名 DoneAt 开头，逐语另写
        if (SAME_AS_ENGLISH_ON_PURPOSE[key]?.includes(locale)) continue;
        expect(copy[key], `${locale} ${key}`).not.toEqual(value);
      }
    }
  });

  it("keeps the brand at the end of the title and out of the heading", () => {
    for (const locale of locales) {
      const copy = load(locale);
      expect(copy.metaTitle, locale).toMatch(/— DoneAt$/);
      expect(copy.heading, locale).not.toContain("DoneAt");
    }
  });
});
