import { describe, expect, it } from "vitest";
import { formatNotes, noteLine, prTitle } from "./android-release-notes.mjs";

describe("android release notes", () => {
  it("reads the PR title from merge and squash commits", () => {
    expect(prTitle("Merge pull request #264 from a/b", "\nfeat(android): x\n")).toBe("feat(android): x");
    expect(prTitle("fix(android): y (#12)", "")).toBe("fix(android): y");
    expect(prTitle("Merge branch 'main'", "")).toBeNull();
  });

  it("keeps only user-facing Android changes", () => {
    expect(noteLine("feat(android): add the focus page (T18a)")).toBe("Add the focus page");
    expect(noteLine("fix(lib): shared rule", ["src-mobile/android/app/A.kt"])).toBe("Shared rule");
    expect(noteLine("ci(android): add the release workflow")).toBeNull();
    expect(noteLine("feat(ios): add alarms", ["src-mobile/android/app/res/values/strings.xml"])).toBeNull();
    expect(noteLine("Untyped title")).toBeNull();
  });

  it("stays within Play's limit without cutting a line", () => {
    const lines = Array.from({ length: 30 }, (_, i) => `Change number ${i} with some words`);
    const text = formatNotes(lines);
    expect(text.length).toBeLessThanOrEqual(500);
    expect(text.split("\n").every((line) => lines.includes(line.slice(2)))).toBe(true);
    expect(formatNotes([])).toBe("Bug fixes and improvements.");
  });
});
