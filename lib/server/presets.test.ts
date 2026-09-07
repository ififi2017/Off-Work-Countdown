import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { contentLocales } from "@/lib/content-locales";
import { presetSlugs } from "@/lib/presets";

const loadPresets = (locale: string) =>
  JSON.parse(
    readFileSync(
      `${process.cwd()}/public/locales/${locale}/presets.json`,
      "utf8"
    )
  ) as {
    startCta: string;
    iosCta: string;
    webBoundary: string;
    items: Record<
      string,
      { metaTitle: string; metaDescription: string; intro: string; body: string[] }
    >;
  };

describe("preset landing copy", () => {
  it("keeps EN and zh-CN aligned on the web vs iOS boundary", () => {
    for (const locale of contentLocales) {
      const copy = loadPresets(locale);
      expect(copy.webBoundary.length).toBeGreaterThan(40);
      expect(copy.iosCta.length).toBeGreaterThan(0);
      expect(Object.keys(copy.items).sort()).toEqual([...presetSlugs].sort());

      for (const slug of presetSlugs) {
        const item = copy.items[slug];
        const text = [item.metaTitle, item.metaDescription, item.intro, ...item.body].join(
          "\n"
        );
        expect(text, `${locale} ${slug}`).not.toMatch(/网页排班|web roster|web scheduling/i);
        expect(item.body.length, `${locale} ${slug}`).toBeGreaterThanOrEqual(4);
      }
    }

    expect(loadPresets("en").webBoundary.toLowerCase()).toContain("ios");
    expect(loadPresets("zh-CN").webBoundary).toMatch(/iOS/);
    expect(loadPresets("zh-CN").startCta).toContain("网页");
    expect(loadPresets("en").startCta.toLowerCase()).toContain("web");
  });
});
