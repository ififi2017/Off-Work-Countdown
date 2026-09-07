import { describe, expect, it } from "vitest";
import { buildWebAppJsonLd } from "./metadata";

describe("web JSON-LD", () => {
  it("keeps the WebApplication on rainif and hangs it off doneat.app", () => {
    const graph = buildWebAppJsonLd({
      lang: "zh-CN",
      description: "浏览器里的下班倒计时。数据留在本机，不用注册。",
    });
    const byType = Object.fromEntries(
      graph["@graph"].map((node) => [node["@type"], node])
    );

    expect(byType.WebApplication.url).toBe("https://off.rainif.com/zh-CN");
    expect(byType.WebApplication.description).toBe(
      "浏览器里的下班倒计时。数据留在本机，不用注册。"
    );
    expect(byType.WebApplication.alternateName).toBe("Off Work Countdown");
    expect(byType.WebApplication.operatingSystem).toBe("Web browser");
    expect(byType.WebApplication.downloadUrl).toBe(
      "https://doneat.app/zh-CN/download"
    );
    expect(byType.WebApplication.sameAs).toContain("https://doneat.app");
    expect(byType.Organization.url).toBe("https://doneat.app");
    expect(byType.WebSite.isPartOf).toEqual({
      "@type": "WebSite",
      name: "DoneAt",
      url: "https://doneat.app",
    });
    expect(JSON.stringify(graph)).not.toMatch(/AggregateRating/);
    expect(JSON.stringify(graph)).not.toMatch(/多种班次|排班|shift planning/i);
  });
});
