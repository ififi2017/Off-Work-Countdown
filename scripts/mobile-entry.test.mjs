import { describe, expect, it } from "vitest";
import { createMobileEntryHtml } from "./mobile-entry.mjs";

const html = createMobileEntryHtml({
  locales: ["en", "zh-CN", "zh-HK"],
  defaultLocale: "en",
  languageMapping: { zh: "zh-CN", "zh-Hant-HK": "zh-HK" },
  preferredLanguageStorageKey: "desktopPreferredLanguage",
});

describe("mobile root entry", () => {
  it("selects a persisted or OS locale without carrying URL data", () => {
    expect(html).toContain('localStorage.getItem("desktopPreferredLanguage")');
    expect(html).toContain('localStorage.getItem("i18nextLng")');
    expect(html).toContain("navigator.languages");
    expect(html).toContain('locale + ".html"');
    expect(html).not.toContain("location.search");
    expect(html).not.toContain("location.hash");
  });

  it("contains locale aliases and no external resources", () => {
    expect(html).toContain('"zh-hant-hk":"zh-HK"');
    expect(html).toContain('data-build-target="mobile"');
    expect(html).not.toMatch(/https?:\/\//);
  });
});
