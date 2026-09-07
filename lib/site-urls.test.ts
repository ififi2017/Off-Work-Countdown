import { describe, expect, it } from "vitest";
import { siteConfig } from "@/config/site";
import { locales } from "@/i18n-config";
import { contentLocales } from "@/lib/content-locales";
import {
  officialContentAlternates,
  officialHomeUrl,
  officialPageUrl,
  webAppAlternates,
  webAppPageUrl,
} from "./site-urls";

describe("site URLs", () => {
  it("keeps the web app on off.rainif.com", () => {
    expect(siteConfig.webAppUrl).toBe("https://off.rainif.com");
    expect(webAppPageUrl("ja")).toBe("https://off.rainif.com/ja");
    expect(webAppPageUrl("en", "996")).toBe("https://off.rainif.com/en/996");
  });

  it("maps hall home links onto the matching doneat.app locale", () => {
    expect(officialHomeUrl("zh-TW")).toBe("https://doneat.app/zh-TW");
    expect(officialHomeUrl("ja")).toBe("https://doneat.app/ja");
  });

  it("maps content links onto the official site's en / zh-CN pages", () => {
    expect(officialPageUrl("en", "download")).toBe(
      "https://doneat.app/en/download"
    );
    expect(officialPageUrl("zh-TW", "privacy")).toBe(
      "https://doneat.app/zh-CN/privacy"
    );
    expect(officialPageUrl("ja", "faq")).toBe("https://doneat.app/en/faq");
    expect(officialContentAlternates("about")).toEqual({
      en: "https://doneat.app/en/about",
      "zh-CN": "https://doneat.app/zh-CN/about",
      "x-default": "https://doneat.app/en/about",
    });
  });

  it("does not invent official URLs for hall languages without long-form pages", () => {
    expect(officialPageUrl("ko", "how-it-works")).not.toContain("/ko/");
  });

  it("points hreflang x-default at /en, not the bare host", () => {
    const hall = webAppAlternates(locales);
    expect(hall.en).toBe("https://off.rainif.com/en");
    expect(hall.ja).toBe("https://off.rainif.com/ja");
    expect(hall["x-default"]).toBe("https://off.rainif.com/en");

    const preset = webAppAlternates(contentLocales, "996");
    expect(preset["zh-CN"]).toBe("https://off.rainif.com/zh-CN/996");
    expect(preset["x-default"]).toBe("https://off.rainif.com/en/996");
  });
});
