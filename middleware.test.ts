import { describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { middleware } from "./middleware";

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

  it.each(["LICENSE", "LICENSE-MIT-LEGACY", "source.txt"])(
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
