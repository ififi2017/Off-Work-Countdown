import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { locales } from "../i18n-config";

const loadTranslation = (locale: string): Record<string, unknown> =>
  JSON.parse(
    readFileSync(
      `${process.cwd()}/public/locales/${locale}/translation.json`,
      "utf8"
    )
  );

describe("UI locale resources", () => {
  it("keeps every user-facing key available in all 19 locales", () => {
    const referenceKeys = Object.keys(loadTranslation("en")).sort();

    for (const locale of locales) {
      expect(Object.keys(loadTranslation(locale)).sort(), locale).toEqual(
        referenceKeys
      );
    }
  });

  it("provides five rotating notification tones without salary placeholders", () => {
    for (const locale of locales) {
      const translation = loadTranslation(locale);
      const tones = translation.notificationToneMessages;
      expect(Array.isArray(tones), locale).toBe(true);
      expect(tones, locale).toHaveLength(5);
      expect(
        (tones as unknown[]).every(
          (item) => typeof item === "string" && item.length > 0
        ),
        locale
      ).toBe(true);

      for (const milestone of [50, 75, 90, 95]) {
        const message = translation[`notificationMilestone${milestone}`];
        expect(typeof message, `${locale} ${milestone}`).toBe("string");
        expect(String(message), `${locale} ${milestone}`).not.toContain("{{");
      }

      const completion = String(translation.notificationMilestone100);
      expect(completion, locale).toContain("{{today}}");
      expect(completion, locale).toContain("{{year}}");
      expect(completion, locale).not.toContain("{{salary}}");
      expect(completion, locale).not.toContain("{{earnings}}");
    }
  });
});
