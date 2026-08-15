import { describe, expect, it } from "vitest";
import { isWindowsUserAgent } from "./user-agent";

describe("isWindowsUserAgent", () => {
  it("recognizes current Windows browsers", () => {
    expect(
      isWindowsUserAgent(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140 Safari/537.36"
      )
    ).toBe(true);
  });

  it("does not show the badge on other platforms", () => {
    expect(isWindowsUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"))
      .toBe(false);
    expect(isWindowsUserAgent("Mozilla/5.0 (X11; Linux x86_64)"))
      .toBe(false);
    expect(isWindowsUserAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0)"))
      .toBe(false);
  });
});
