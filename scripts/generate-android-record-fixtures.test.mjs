import { describe, expect, it } from "vitest";
import { androidRecordFixturePath, checkRecordSourceHashes } from "./generate-android-record-fixtures.mjs";

describe("Android record fixtures", () => {
  // Regenerating needs Xcode, so CI checks the recorded hashes of iOS
  // RecordJSON and its models (and the case list): a codec change on iOS must
  // be carried into the Kotlin port (regenerate on macOS, then :core:domain:test).
  it("were generated from the current Swift codec and cases", () => {
    expect(checkRecordSourceHashes(androidRecordFixturePath)).toBeNull();
  });
});
