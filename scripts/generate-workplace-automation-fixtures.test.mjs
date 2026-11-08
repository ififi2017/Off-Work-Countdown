import { describe, expect, it } from "vitest";
import { checkWorkplaceAutomationFixtures } from "./generate-workplace-automation-fixtures.mjs";

describe("workplace automation fixtures", () => {
  // The iOS tests compile a copy of the shared JSON; editing one without the
  // other would let the platforms test different cases.
  it("match the shared JSON", () => {
    expect(checkWorkplaceAutomationFixtures()).toBeNull();
  });
});
