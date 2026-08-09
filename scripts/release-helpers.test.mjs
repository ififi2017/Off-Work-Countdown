import { describe, expect, it } from "vitest";
import { normalizeVersion, parseCommonOptions } from "./release-helpers.mjs";

describe("release script arguments", () => {
  it("normalizes supported desktop version forms", () => {
    expect(normalizeVersion("3.0.2")).toBe("3.0.2");
    expect(normalizeVersion("v3.0.2")).toBe("3.0.2");
    expect(normalizeVersion("desktop-v3.0.2")).toBe("3.0.2");
  });

  it("rejects unsafe tag-like values", () => {
    expect(() => normalizeVersion("3.0.2 && bad")).toThrow();
    expect(() => normalizeVersion("release/latest")).toThrow();
  });

  it("parses common flags without swallowing the version", () => {
    expect(parseCommonOptions(["3.1.0", "--dry-run", "--yes"])).toEqual({
      dryRun: true,
      help: false,
      positional: ["3.1.0"],
      skipChecks: false,
      yes: true,
    });
  });
});
