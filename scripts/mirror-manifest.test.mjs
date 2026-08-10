import { describe, expect, it } from "vitest";
import { buildMirrorManifest, mirrorUrl, MIRROR_PREFIX } from "./mirror-manifest.mjs";

const manifest = {
  version: "3.0.4",
  notes: "Off Work Countdown desktop release.",
  pub_date: "2026-08-10T15:00:00Z",
  platforms: {
    "darwin-aarch64": {
      signature: "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZQ==",
      url: "https://github.com/ififi2017/Off-Work-Countdown/releases/download/desktop-v3.0.4/app_aarch64.app.tar.gz",
    },
    "windows-x86_64": {
      signature: "c2lnbmF0dXJl",
      url: "https://github.com/ififi2017/Off-Work-Countdown/releases/download/desktop-v3.0.4/app_x64-setup.exe",
    },
  },
};

describe("buildMirrorManifest", () => {
  it("prefixes every platform URL with the mirror", () => {
    const mirrored = buildMirrorManifest(manifest);
    for (const target of Object.keys(manifest.platforms)) {
      expect(mirrored.platforms[target].url).toBe(
        `${MIRROR_PREFIX}${manifest.platforms[target].url}`
      );
    }
  });

  it("keeps signatures byte-identical", () => {
    // 签名覆盖的是压缩包内容而非下载地址，改写 URL 后必须原样保留，
    // 否则客户端会拒绝安装镜像下来的包。
    const mirrored = buildMirrorManifest(manifest);
    for (const [target, entry] of Object.entries(manifest.platforms)) {
      expect(mirrored.platforms[target].signature).toBe(entry.signature);
    }
  });

  it("carries version and notes through untouched", () => {
    const mirrored = buildMirrorManifest(manifest);
    expect(mirrored.version).toBe(manifest.version);
    expect(mirrored.notes).toBe(manifest.notes);
    expect(mirrored.pub_date).toBe(manifest.pub_date);
  });

  it("does not mutate the source manifest", () => {
    const snapshot = structuredClone(manifest);
    buildMirrorManifest(manifest);
    expect(manifest).toEqual(snapshot);
  });

  it("throws when the manifest has no platforms", () => {
    // 空清单会让镜像通道永远报「没有可用更新」，必须在发版时就失败。
    expect(() => buildMirrorManifest({ version: "3.0.4", platforms: {} })).toThrow();
    expect(() => buildMirrorManifest({ version: "3.0.4" })).toThrow();
  });
});

describe("mirrorUrl", () => {
  it("is idempotent so re-running the step cannot double-prefix", () => {
    const once = mirrorUrl(manifest.platforms["windows-x86_64"].url);
    expect(mirrorUrl(once)).toBe(once);
  });

  it("mirrors the asset API URLs that tauri-action actually emits", () => {
    // latest.json 里是资产 API 地址，不是 releases/download 直链。这条用例
    // 用真实形态钉住，因为漏掉这个主机会让镜像清单静默退化成原样。
    const asset =
      "https://api.github.com/repos/ififi2017/Off-Work-Countdown/releases/assets/508158832";
    expect(mirrorUrl(asset)).toBe(`${MIRROR_PREFIX}${asset}`);
  });

  it("leaves non-GitHub hosts alone", () => {
    const url = "https://example.com/app.msi";
    expect(mirrorUrl(url)).toBe(url);
  });

  it("rejects a missing or malformed URL", () => {
    expect(() => mirrorUrl(undefined)).toThrow();
    expect(() => mirrorUrl("")).toThrow();
    expect(() => mirrorUrl("not a url")).toThrow();
  });
});
