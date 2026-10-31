import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { pageRegistry, getBuildPages, getPublicPages, getSalaryPage, getDirectoryPage, getPageAlternates } from "./pages";
import sitemap from "@/app/sitemap";

beforeEach(() => {
  vi.stubEnv("VERCEL_ENV", "");
  vi.stubEnv("WEB_TOOLS_PREVIEW", "");
});
afterEach(() => vi.unstubAllEnvs());

describe("Web tool publication boundary", () => {
  it("keeps unreviewed pages out of normal routes and the public sitemap", () => {
    vi.stubEnv("WEB_TOOLS_PREVIEW", "");
    expect(getBuildPages()).toEqual(getPublicPages());
    for (const page of pageRegistry.filter((item) => item.status === "draft")) {
      expect(getBuildPages()).not.toContain(page);
      expect(sitemap().some((entry) => entry.url.endsWith(page.path))).toBe(false);
      expect(getPageAlternates(page)).toEqual({});
    }
    expect(getSalaryPage("en", "us")).toBeUndefined();
    expect(getDirectoryPage("zh-CN")).toBeUndefined();
  });

  it.each([
    { vercelEnv: "preview", flag: "" },
    { vercelEnv: "preview", flag: "0" },
    { vercelEnv: "preview", flag: "1" },
    { vercelEnv: "development", flag: "1" },
    { vercelEnv: "", flag: "1" },
  ])("exposes only review candidates without indexing them for $vercelEnv / flag=$flag", ({ vercelEnv, flag }) => {
    vi.stubEnv("VERCEL_ENV", vercelEnv);
    vi.stubEnv("WEB_TOOLS_PREVIEW", flag);
    // Next production-mode builds are also used for Vercel previews.
    vi.stubEnv("NODE_ENV", "production");
    expect(getBuildPages()).toHaveLength(10);
    expect(getBuildPages().filter((page) => page.kind === "salary")).toHaveLength(8);
    expect(getSalaryPage("en", "us", ["hourly-to-annual"])?.path).toBe("/en/salary/us/hourly-to-annual");
    expect(getSalaryPage("zh-CN", "cn", ["workdays-21-75"])?.path).toBe("/zh-CN/salary/cn/workdays-21-75");
    expect(getSalaryPage("en", "cn")).toBeUndefined();
    expect(getSalaryPage("ja", "us")).toBeUndefined();
    expect(getSalaryPage("en", "us", ["nonexistent"])).toBeUndefined();
    expect(getPublicPages()).toHaveLength(0);
    for (const page of getBuildPages()) {
      expect(sitemap().some((entry) => entry.url.endsWith(page.path))).toBe(false);
      expect(getPageAlternates(page)).toEqual({});
    }
  });

  it.each(["", "0", "1"])("never exposes drafts in Vercel production with flag=%s", (flag) => {
    vi.stubEnv("VERCEL_ENV", "production");
    vi.stubEnv("WEB_TOOLS_PREVIEW", flag);
    expect(getBuildPages()).toEqual(getPublicPages());
    expect(getBuildPages()).toHaveLength(0);
    expect(getSalaryPage("en", "us")).toBeUndefined();
    expect(getDirectoryPage("zh-CN")).toBeUndefined();
    for (const page of pageRegistry) {
      expect(sitemap().some((entry) => entry.url.endsWith(page.path))).toBe(false);
      expect(getPageAlternates(page.id)).toEqual({});
    }
  });

  it.each(["preview", "development"])("excludes retired entries from %s builds", (vercelEnv) => {
    vi.stubEnv("VERCEL_ENV", vercelEnv);
    vi.stubEnv("WEB_TOOLS_PREVIEW", "1");
    const page = pageRegistry[0];
    const previousStatus = page.status;
    try {
      page.status = "retired";
      expect(getBuildPages()).not.toContain(page);
      expect(getBuildPages()).toHaveLength(pageRegistry.length - 1);
      expect(getSalaryPage(page.lang, page.market!, page.slug)).toBeUndefined();
    } finally {
      page.status = previousStatus;
    }
  });

  it("registers unique IDs and canonical paths rather than a locale-market cross product", () => {
    expect(new Set(pageRegistry.map((page) => page.id)).size).toBe(pageRegistry.length);
    expect(new Set(pageRegistry.map((page) => page.path)).size).toBe(pageRegistry.length);
    for (const page of pageRegistry) {
      expect(page.path).toMatch(/^\/(en|zh-CN)\/(tools|salary\/(cn|us)(\/[-a-z0-9]+)?)$/);
      expect(page.status).toBe("draft");
      expect(page.contentReviewedAt).toBeNull();
    }
  });
});
