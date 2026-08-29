import { describe, expect, it } from "vitest";
import { parseLatestRelease, type GitHubRelease } from "./github-release";

const asset = (name: string) => ({
  name,
  browser_download_url: `https://github.com/ififi2017/Off-Work-Countdown/releases/download/desktop-v3.0.0/${encodeURIComponent(name)}`,
  size: 42,
});

describe("parseLatestRelease", () => {
  it("maps versioned Tauri assets to their platform and architecture", () => {
    const release: GitHubRelease = {
      tag_name: "desktop-v3.0.0",
      html_url: "https://github.com/ififi2017/Off-Work-Countdown/releases/tag/desktop-v3.0.0",
      published_at: "2026-08-09T00:00:00Z",
      assets: [
        asset("Off Work Countdown_3.0.0_x64-setup.exe"),
        asset("Off Work Countdown_3.0.0_x64_en-US.msi"),
        asset("Off Work Countdown_3.0.0_aarch64.dmg"),
        asset("Off Work Countdown_3.0.0_x64.dmg"),
        asset("Off Work Countdown_3.0.0_amd64.AppImage"),
        asset("Off Work Countdown_3.0.0_aarch64.dmg.sig"),
      ],
    };

    const result = parseLatestRelease(release);

    expect(result.version).toBe("3.0.0");
    expect(result.downloads.windowsX64?.name).toMatch(/setup\.exe$/);
    expect(result.downloads.windowsArm64).toBeNull();
    expect(result.downloads.macosAppleSilicon?.name).toMatch(/aarch64\.dmg$/);
    expect(result.downloads.macosIntel?.name).toMatch(/x64\.dmg$/);
    expect(result.downloads.linuxX64?.name).toMatch(/AppImage$/);
  });

  it("also recognizes Windows ARM installers when they are published", () => {
    const release: GitHubRelease = {
      tag_name: "v3.1.0",
      html_url: "https://example.com/release",
      published_at: null,
      assets: [asset("Off Work Countdown_3.1.0_arm64-setup.exe")],
    };

    expect(parseLatestRelease(release).downloads.windowsArm64?.name).toContain(
      "arm64"
    );
  });

  it("still maps assets after the installer prefix becomes DoneAt", () => {
    const release: GitHubRelease = {
      tag_name: "desktop-v3.1.8",
      html_url: "https://example.com/release",
      published_at: null,
      assets: [
        asset("DoneAt_3.1.8_x64-setup.exe"),
        asset("DoneAt_3.1.8_aarch64.dmg"),
      ],
    };

    const result = parseLatestRelease(release);
    expect(result.downloads.windowsX64?.name).toBe("DoneAt_3.1.8_x64-setup.exe");
    expect(result.downloads.macosAppleSilicon?.name).toBe(
      "DoneAt_3.1.8_aarch64.dmg"
    );
  });
});
