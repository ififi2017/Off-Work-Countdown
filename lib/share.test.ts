import { describe, it, expect } from "vitest";
import {
  buildShareUrl,
  buildShareText,
  formatShareDisplayUrl,
  platformShareUrl,
  SHARE_IMAGE_FILENAME,
  encodeShift,
  decodeShift,
  type SharePlatform,
} from "./share";
import { moods, defaultMood, getMood } from "./moods";
import { trackedEvents, isTrackedEvent } from "./analytics-events";

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

  it("lands on the Web App origin, never the official site", () => {
    const url = buildShareUrl("text", { start: "09:00", end: "18:00" });
    expect(url.startsWith("https://off.rainif.com/")).toBe(true);
    expect(url).not.toContain("doneat.app");
    expect(formatShareDisplayUrl(url)).toBe("off.rainif.com");
  });

  it("names the downloaded card after the current brand", () => {
    expect(SHARE_IMAGE_FILENAME).toBe("doneat.png");
    expect(SHARE_IMAGE_FILENAME).not.toMatch(/off-work/i);
  });
});

describe("encodeShift / decodeShift", () => {
  it("round-trips a shift through the compact form", () => {
    const shift = { start: "09:00", end: "18:00" };
    expect(encodeShift(shift)).toBe("0900-1800");
    expect(decodeShift(encodeShift(shift))).toEqual(shift);
  });

  it("round-trips an overnight shift", () => {
    const shift = { start: "22:30", end: "06:15" };
    expect(decodeShift(encodeShift(shift))).toEqual(shift);
  });

  it("rejects malformed input rather than guessing", () => {
    for (const bad of [
      null,
      undefined,
      "",
      "0900",
      "09:00-18:00",
      "0900_1800",
      "2500-1800", // 小时越界
      "0960-1800", // 分钟越界
      "0900-2400",
      "abcd-efgh",
      "0900-1800extra",
    ]) {
      expect(decodeShift(bad)).toBeNull();
    }
  });

  it("rejects a zero-length shift, which the app also refuses", () => {
    expect(decodeShift("0900-0900")).toBeNull();
  });
});

describe("buildShareUrl with a shift", () => {
  it("carries the shift and a share marker", () => {
    const url = buildShareUrl("text", { start: "09:00", end: "18:00" });
    expect(url).toContain("s=0900-1800");
    expect(url).toContain("from=share");
  });

  it("omits shift params when no shift is given", () => {
    const url = buildShareUrl("text");
    expect(url).not.toContain("s=");
    expect(url).not.toContain("from=");
  });

  it("never leaks salary-related params", () => {
    const url = buildShareUrl("image", { start: "22:00", end: "06:00" });
    for (const leak of ["salary", "amount", "monthly", "daily", "earn"]) {
      expect(url.toLowerCase()).not.toContain(leak);
    }
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

describe("analytics event allowlist", () => {
  it("accepts exactly the declared events", () => {
    for (const e of trackedEvents) expect(isTrackedEvent(e)).toBe(true);
  });

  it("rejects anything else, so the public endpoint cannot write arbitrary keys", () => {
    for (const bad of [
      "",
      " ",
      "share_land ",
      "SHARE_LAND",
      "share_land; DROP",
      "e:2026-08-08:x",
      "__proto__",
      "a".repeat(200),
    ]) {
      expect(isTrackedEvent(bad)).toBe(false);
    }
  });

  it("keeps event names low-cardinality and key-safe", () => {
    for (const e of trackedEvents) {
      expect(e).toMatch(/^[a-z_]+$/);
      expect(e.length).toBeLessThanOrEqual(32);
    }
    expect(new Set(trackedEvents).size).toBe(trackedEvents.length);
  });
});
