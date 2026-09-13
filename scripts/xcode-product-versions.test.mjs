import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { xcodeProductVersionErrors } from "./xcode-product-versions.mjs";

const project = readFileSync("src-mobile/ios/App/App.xcodeproj/project.pbxproj", "utf8");
const version = JSON.parse(readFileSync("package.json", "utf8")).version;

describe("Xcode product configuration coverage", () => {
  it("checks every shipping configuration and excludes the test host", () => {
    expect(xcodeProductVersionErrors(project, version)).toEqual([]);
  });
  it("rejects one omitted version even when every remaining version matches", () => {
    expect(xcodeProductVersionErrors(project.replace(/MARKETING_VERSION\s*=\s*[^;]+;/, ""), version))
      .toEqual([expect.stringContaining("found missing")]);
  });
  it("rejects an incomplete new product and its stale version", () => {
    const watch = `isa = XCBuildConfiguration;
      buildSettings = {
        PRODUCT_BUNDLE_IDENTIFIER = example.watch;
        MARKETING_VERSION = 0.0.0;
      };
      name = Debug;`;
    const errors = xcodeProductVersionErrors(project + watch, version);
    expect(errors).toContain("example.watch has no Release configuration");
    expect(errors.some((error) => error.includes("example.watch / Debug"))).toBe(true);
  });
  it("requires every named shipping target", () => {
    expect(xcodeProductVersionErrors(project, version, ["missing.watch.product"]))
      .toContain("Missing shipping product missing.watch.product");
  });
});
