import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { loadIapConfig, parseIapArgs, STORE_LOCALES, validateIapConfig } from "./iap-config.mjs";

describe("IAP config", () => {
  it("covers the same 17 App Store locales as the iOS listing", () => {
    const listing = JSON.parse(readFileSync("app-store-connect/ios/3.1.8.json", "utf8"));
    expect(STORE_LOCALES).toEqual(Object.keys(listing.localizations).sort());
    const config = JSON.parse(readFileSync("app-store-connect/iap.json", "utf8"));
    validateIapConfig(config);
    expect(Object.keys(config.groupLocalizations).sort()).toEqual(STORE_LOCALES);
    for (const product of Object.values(config.products)) {
      expect(Object.keys(product.localizations).sort()).toEqual(STORE_LOCALES);
    }
  });

  it("loads the committed screenshot when present", () => {
    const loaded = loadIapConfig("app-store-connect/iap.json", { requireScreenshot: false });
    expect(loaded.config.subscriptionGroup).toBe("plus");
    expect(loaded.config.products["com.rainif.offworkcountdown.plus.yearly"].kind).toBe("subscription");
  });

  it("parses plan as the default mode", () => {
    expect(parseIapArgs([])).toMatchObject({
      mode: "plan",
      configPath: "app-store-connect/iap.json",
      skipScreenshot: false,
      replaceScreenshot: false,
    });
  });
});
