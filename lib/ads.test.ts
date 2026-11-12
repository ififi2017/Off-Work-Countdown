import { describe, expect, it } from "vitest";
import { ADSENSE_SRC, isAdEligiblePath, shouldLoadAds } from "./ads";

const base = {
  pathname: "/en/996",
  hostname: "off.rainif.com",
  productionHostname: "off.rainif.com",
  installedApp: false,
};

describe("isAdEligiblePath", () => {
  it("allows content pages", () => {
    for (const p of ["/en/996", "/en/work-hours-calculator", "/zh-CN/salary/cn/monthly-to-daily", "/en/tools"]) {
      expect(isAdEligiblePath(p)).toBe(true);
    }
  });
  it("keeps the timer and mini timer clean", () => {
    for (const p of ["/", "/en", "/en/", "/zh-CN", "/en/mini"]) {
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
  it("never loads on the timer", () => {
    expect(shouldLoadAds({ ...base, pathname: "/en" })).toBe(false);
  });
});

describe("ADSENSE_SRC", () => {
  it("targets the approved publisher", () => {
    expect(ADSENSE_SRC).toContain("client=ca-pub-9912554861143289");
  });
});
