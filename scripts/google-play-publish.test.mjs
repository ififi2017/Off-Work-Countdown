import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  gradleVersions,
  nextVersionCode,
  releasesWithDraft,
  usedVersionCodes,
} from "./google-play-publish.mjs";

// 发布工作流在 Play 上才会暴露的错：versionCode 撞号、草稿把正在发布的版本挤掉、
// 正则读不到 Gradle 里的版本。它们都是纯数据，放在单元测试里每个 PR 都跑。

describe("Google Play publishing", () => {
  it("reads the product version and default versionCode from Gradle", () => {
    const local = gradleVersions(readFileSync("src-mobile/android/app/build.gradle.kts", "utf8"));
    expect(local.versionName).toBe(JSON.parse(readFileSync("package.json", "utf8")).version);
    expect(Number.isInteger(local.versionCode)).toBe(true);
  });

  it("goes past every versionCode Play has seen, including bundles outside tracks", () => {
    const used = usedVersionCodes(
      [{ versionCode: 3 }, { versionCode: 7 }],
      [{ track: "alpha", releases: [{ status: "completed", versionCodes: ["5"] }] }],
    );
    expect(nextVersionCode(used, 5)).toBe(8);
  });

  it("keeps the Gradle default when Play has nothing newer", () => {
    expect(nextVersionCode([], 5)).toBe(5);
    expect(nextVersionCode([2, 3], 5)).toBe(5);
  });

  it("replaces an old draft but keeps live releases on the track", () => {
    const releases = releasesWithDraft(
      [
        { name: "3.2.0 (4)", status: "completed", versionCodes: ["4"] },
        { name: "3.2.1 (5)", status: "draft", versionCodes: ["5"] },
      ],
      { name: "3.2.1 (6)", versionCodes: ["6"] },
    );
    expect(releases).toEqual([
      { name: "3.2.0 (4)", status: "completed", versionCodes: ["4"] },
      { name: "3.2.1 (6)", status: "draft", versionCodes: ["6"] },
    ]);
  });
});
