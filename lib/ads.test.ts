import { describe, expect, it } from "vitest";
import { ADSENSE_SRC, isAdEligiblePath, shouldLoadAds } from "./ads";

const base = {
  pathname: "/en/996",
  hostname: "off.rainif.com",
  productionHostname: "off.rainif.com",
  installedApp: false,
};

describe("isAdEligiblePath", () => {
  it("allows the timer and content pages", () => {
    for (const p of ["/en", "/zh-CN", "/en/", "/en/996", "/en/work-hours-calculator", "/zh-CN/salary/cn/monthly-to-daily", "/en/tools"]) {
      expect(isAdEligiblePath(p)).toBe(true);
    }
  });
  it("skips the redirecting root and the mini timer", () => {
    for (const p of ["/", "/en/mini", "/zh-CN/mini"]) {
      expect(isAdEligiblePath(p)).toBe(false);
    }
  });
});

describe("shouldLoadAds", () => {
  it("loads in a normal production browser tab", () => {
    expect(shouldLoadAds(base)).toBe(true);
  });
  it("never loads inside an installed PWA", () => {
    expect(shouldLoadAds({ ...base, installedApp: true })).toBe(false);
  });
  it("never loads on previews or localhost", () => {
    expect(shouldLoadAds({ ...base, hostname: "owc-git-x.vercel.app" })).toBe(false);
    expect(shouldLoadAds({ ...base, hostname: "localhost" })).toBe(false);
  });
  it("loads on the timer in a browser tab but not in the installed app", () => {
    expect(shouldLoadAds({ ...base, pathname: "/en" })).toBe(true);
    expect(shouldLoadAds({ ...base, pathname: "/en", installedApp: true })).toBe(false);
  });
});

describe("ADSENSE_SRC", () => {
  it("targets the approved publisher", () => {
    expect(ADSENSE_SRC).toContain("client=ca-pub-9912554861143289");
  });
});
