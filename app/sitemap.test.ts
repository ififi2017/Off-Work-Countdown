import { describe, expect, it } from "vitest";
import sitemap from "./sitemap";
import { contentSlugs } from "@/lib/content-locales";

describe("web sitemap", () => {
  it("lists the Web App and presets, not official-site content pages", () => {
    const urls = sitemap().map((entry) => entry.url);

    expect(urls).toContain("https://off.rainif.com/en");
    expect(urls).toContain("https://off.rainif.com/zh-CN/996");
    expect(urls.every((url) => url.startsWith("https://off.rainif.com/"))).toBe(
      true
    );

    for (const slug of contentSlugs) {
      expect(urls.some((url) => url.endsWith(`/${slug}`))).toBe(false);
    }
  });

  it("points every x-default alternate at /en, not the bare host", () => {
    const defaults = new Set(
      sitemap().flatMap((entry) => {
        const languages = entry.alternates?.languages ?? {};
        return languages["x-default"] ? [languages["x-default"]] : [];
      })
    );

    expect([...defaults].every((url) => url.startsWith("https://off.rainif.com/en"))).toBe(
      true
    );
    expect(defaults.has("https://off.rainif.com")).toBe(false);
    expect(defaults.has("https://off.rainif.com/en")).toBe(true);
    expect(defaults.has("https://off.rainif.com/en/996")).toBe(true);
  });
});
