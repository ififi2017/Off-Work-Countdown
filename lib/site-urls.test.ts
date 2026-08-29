import { describe, expect, it } from "vitest";
import { siteConfig } from "@/config/site";
import {
  officialContentAlternates,
  officialHomeUrl,
  officialPageUrl,
  webAppPageUrl,
} from "./site-urls";

describe("site URLs", () => {
  it("keeps the web app on off.rainif.com", () => {
    expect(siteConfig.webAppUrl).toBe("https://off.rainif.com");
    expect(webAppPageUrl("ja")).toBe("https://off.rainif.com/ja");
    expect(webAppPageUrl("en", "996")).toBe("https://off.rainif.com/en/996");
  });

  it("maps content links onto the official site's en / zh-CN pages", () => {
    expect(officialHomeUrl("zh-TW")).toBe("https://doneat.app/zh-CN");
    expect(officialHomeUrl("ja")).toBe("https://doneat.app/en");
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
});
