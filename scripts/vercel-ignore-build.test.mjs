import { describe, expect, it } from "vitest";
import { affectsWeb } from "./vercel-ignore-build.mjs";

describe("affectsWeb", () => {
  it("skips desktop, extension, docs and store-only changes", () => {
    for (const file of [
      "src-tauri/src/lib.rs",
      "docs/agent-guides/releases.md",
      "plans/Web/001-seo-search-growth.md",
      ".github/workflows/release-desktop.yml",
      "src-extension/manifest.json",
      "app-store-connect/metadata/en-US/description.txt",
      "README_CN.md",
      "scripts/marketing-shots/promo-video/audio.mjs",
    ]) {
      expect(affectsWeb(file), file).toBe(false);
    }
  });

  it("builds Web sources, shared rules, config and unknown paths", () => {
    for (const file of [
      "app/[lang]/page.tsx",
      "components/Countdown.tsx",
      "lib/countdown.ts",
      "public/locales/en/translation.json",
      "package.json",
      "package-lock.json",
      "next.config.mjs",
      "vercel.json",
      "scripts/generate-desktop-holidays.mjs",
      "scripts/vercel-ignore-build.mjs",
      "middleware.ts",
      "something-new/file.txt",
    ]) {
      expect(affectsWeb(file), file).toBe(true);
    }
  });

  it("builds TypeScript anywhere, since next build type-checks it", () => {
    expect(affectsWeb("src-extension/popup.tsx")).toBe(true);
    expect(affectsWeb("src-tauri/windows/installer-hooks.test.ts")).toBe(true);
  });
});
