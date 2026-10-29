import { describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { unstable_doesMiddlewareMatch } from "next/experimental/testing/server";
import { config, middleware } from "./middleware";
import { locales } from "./i18n-config";

describe("locale middleware invocation boundary", () => {
  const matches = (url: string) => unstable_doesMiddlewareMatch({ config, nextConfig: {}, url });

  it.each(locales)("does not invoke middleware for %s pages", (locale) => {
    for (const suffix of ["", "/", "/996", "/work-hours-calculator", "/missing"]) {
      expect(matches(`https://off.rainif.com/${locale}${suffix}`)).toBe(false);
    }
  });

  it.each(["/", "/?s=0900-1800", "/faq", "/996", "/xx/faq", "/english", "/en-US"])(
    "still negotiates language for %s", (path) => {
      expect(matches(`https://off.rainif.com${path}`)).toBe(true);
    }
  );

  it.each(["/api/e", "/_next/static/a.js", "/_next/image?url=x", "/static/a", "/licenses/LICENSE", "/showcase/demo.MP4", "/fonts/GeistVF.woff", "/icon-maskable-512x512.png", "/manifest.json?lang=de", "/locales/en/translation.json"])(
    "does not invoke middleware for resource %s", (path) => {
      expect(matches(`https://off.rainif.com${path}`)).toBe(false);
    }
  );
});

describe("locale redirect", () => {
  it("sends the root to the browser language, keeps the query and declares Vary", () => {
    const response = middleware(
      new NextRequest("https://off.rainif.com/?s=0900-1800&from=share", {
        headers: { "accept-language": "de-DE,de;q=0.9,en;q=0.8" },
      })
    );

    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe(
      "https://off.rainif.com/de?s=0900-1800&from=share"
    );
    expect(response.headers.get("vary")).toBe("Accept-Language, Cookie");
  });

  it("leaves localized pages alone", () => {
    const response = middleware(
      new NextRequest("https://off.rainif.com/ko/work-hours-calculator")
    );
    expect(response.headers.get("location")).toBeNull();
  });

  it.each(["LICENSE", "LICENSES/MIT-legacy.txt", "source.txt"])(
    "serves the packaged licensing resource %s without a locale redirect",
    (file) => {
      const response = middleware(new NextRequest(`https://off.rainif.com/licenses/${file}`, {
        headers: { "accept-language": "zh-CN" },
      }));
      expect(response.headers.get("location")).toBeNull();
      expect(response.headers.get("x-middleware-next")).toBe("1");
    }
  );

});
