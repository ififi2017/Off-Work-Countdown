import { execFileSync } from "node:child_process";
import { expect, it } from "vitest";

it("ships the pinned, complete holiday dataset and licenses without network generation", () => {
  const output = execFileSync(process.execPath, ["scripts/check-holiday-templates.mjs"], { encoding: "utf8" });
  expect(output).toContain("Holiday templates OK: 249 regions");
});
