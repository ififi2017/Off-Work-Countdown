import { describe, it, expect } from "vitest";
import {
  buildShareUrl,
  buildShareText,
  platformShareUrl,
  type SharePlatform,
} from "./share";
import { moods, defaultMood, getMood } from "./moods";

describe("buildShareUrl", () => {
  it("appends UTM params for attribution", () => {
    const url = buildShareUrl("text");
    expect(url).toContain("utm_source=share");
    expect(url).toContain("utm_medium=text");
    expect(url).toContain("utm_campaign=countdown");
  });

  it("distinguishes text vs image medium", () => {
    expect(buildShareUrl("image")).toContain("utm_medium=image");
  });

  it("produces a valid absolute URL", () => {
    expect(() => new URL(buildShareUrl("text"))).not.toThrow();
  });
});

describe("buildShareText", () => {
  it("combines emoji, message and url", () => {
    const text = buildShareText({
      emoji: "🔥",
      message: "I'm off work in 2h!",
      url: "https://example.com/?utm_source=share",
    });
    expect(text).toBe("🔥 I'm off work in 2h! https://example.com/?utm_source=share");
  });
});

describe("platformShareUrl", () => {
  const text = "off work in 2h 🔥";
  const url = "https://example.com/?utm_source=share";
  const platforms: SharePlatform[] = [
    "x",
    "facebook",
    "whatsapp",
    "telegram",
    "line",
    "reddit",
    "weibo",
  ];

  it("returns a valid URL carrying the encoded site link for every platform", () => {
    for (const p of platforms) {
      const built = platformShareUrl[p](text, url);
      expect(() => new URL(built)).not.toThrow();
      expect(built).toContain(encodeURIComponent(url));
    }
  });

  it("targets the expected hosts", () => {
    expect(platformShareUrl.x(text, url)).toContain("twitter.com/intent/tweet");
    expect(platformShareUrl.facebook(text, url)).toContain("facebook.com/sharer");
    expect(platformShareUrl.whatsapp(text, url)).toContain("wa.me");
    expect(platformShareUrl.telegram(text, url)).toContain("t.me/share");
    expect(platformShareUrl.line(text, url)).toContain("line.me");
    expect(platformShareUrl.reddit(text, url)).toContain("reddit.com/submit");
    expect(platformShareUrl.weibo(text, url)).toContain("weibo.com/share");
  });
});

describe("moods", () => {
  it("every mood has an emoji, label key and >=2 gradient stops", () => {
    for (const m of moods) {
      expect(m.emoji.length).toBeGreaterThan(0);
      expect(m.labelKey).toMatch(/^mood/);
      expect(m.gradient.length).toBeGreaterThanOrEqual(2);
    }
  });

  it("getMood falls back to the default for unknown ids", () => {
    expect(getMood("nope")).toBe(defaultMood);
    expect(getMood(null)).toBe(defaultMood);
    expect(getMood("firedUp").emoji).toBe("🔥");
  });
});
