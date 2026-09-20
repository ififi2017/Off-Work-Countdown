import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

it("ships the pinned, complete holiday dataset and licenses without network generation", () => {
  const output = execFileSync(process.execPath, ["scripts/check-holiday-templates.mjs"], { encoding: "utf8" });
  expect(output).toContain("Holiday templates OK: 249 regions");
});

it("shows Brazilian holidays in Portuguese when the source uses a regional locale", () => {
  const dataset = JSON.parse(readFileSync("src-mobile/ios/Shared/Resources/HolidayTemplates.json", "utf8"));
  const independenceDay = dataset.regions.BR.days.find(([date]) => date === 20260907);
  expect(independenceDay[1]).toBe(0);
  expect(dataset.names[independenceDay[2]].pt).toBe("Independência do Brasil");
});
