import { describe, expect, it } from "vitest";
import { locales } from "../i18n-config";
import { contentSlugs } from "./content-locales";
import {
  CONTENT_SLUGS,
  UI_LOCALES,
  buildOfficialContentRedirects,
} from "./official-content-redirects.mjs";

describe("official content redirects", () => {
  it("stays aligned with the TypeScript locale and slug lists", () => {
    expect(UI_LOCALES).toEqual([...locales]);
    expect(CONTENT_SLUGS).toEqual([...contentSlugs]);
  });

  it("sends every UI language to an existing official content locale", () => {
    const redirects = buildOfficialContentRedirects();

    expect(redirects).toHaveLength(locales.length * contentSlugs.length);

    const bySource = Object.fromEntries(
      redirects.map((item) => [item.source, item])
    );

    expect(bySource["/en/download"]).toMatchObject({
      destination: "https://doneat.app/en/download",
      statusCode: 301,
    });
    expect(bySource["/zh-CN/privacy"]).toMatchObject({
      destination: "https://doneat.app/zh-CN/privacy",
      statusCode: 301,
    });
    expect(bySource["/zh-TW/faq"]).toMatchObject({
      destination: "https://doneat.app/zh-CN/faq",
      statusCode: 301,
    });
    expect(bySource["/ja/how-it-works"]).toMatchObject({
      destination: "https://doneat.app/en/how-it-works",
      statusCode: 301,
    });

    expect(bySource["/en"]).toBeUndefined();
    expect(bySource["/en/996"]).toBeUndefined();
    expect(
      redirects.some((item) => item.destination.includes("/ja/"))
    ).toBe(false);
  });
});
