import { describe, expect, it } from "vitest";
import {
  androidExtendedFixturePath,
  checkExtendedSourceHashes,
} from "./generate-android-extended-fixtures.mjs";

describe("Android extended-schedule fixtures", () => {
  // Regenerating needs Xcode, so CI checks the recorded Swift source hashes:
  // a change to extended scheduling in src-mobile/ios/Shared must be carried
  // into the Kotlin port (run the generator on macOS, then :core:domain:test).
  it("were generated from the current Swift sources", () => {
    expect(checkExtendedSourceHashes(androidExtendedFixturePath)).toBeNull();
  });
});
