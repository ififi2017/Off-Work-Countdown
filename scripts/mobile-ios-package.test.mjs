import { describe, expect, it } from "vitest";
import { normalizeCapacitorIOSPackageManifest } from "./mobile-ios-package.mjs";

describe("Capacitor iOS Package.swift normalization", () => {
  it("uses the PackageDescription 5-compatible custom version form", () => {
    const source = "platforms: [.iOS(.v26)],";
    expect(normalizeCapacitorIOSPackageManifest(source, "26.0")).toBe(
      'platforms: [.iOS("26.0")],'
    );
  });

  it("is idempotent and rejects an unexpected generated manifest", () => {
    const normalized = 'platforms: [.iOS("26.0")],';
    expect(normalizeCapacitorIOSPackageManifest(normalized, "26.0")).toBe(
      normalized
    );
    expect(() =>
      normalizeCapacitorIOSPackageManifest("platforms: []", "26.0")
    ).toThrow(/does not contain/);
  });
});
