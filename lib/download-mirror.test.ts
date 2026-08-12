import { describe, expect, it } from "vitest";
import { mirroredDownloadUrl, DOWNLOAD_MIRROR_HOST } from "../lib/download-mirror";

describe("download mirror", () => {
  it("wraps GitHub release URLs", () => {
    const url = "https://github.com/ififi2017/Off-Work-Countdown/releases/download/desktop-v3.1.2/x.dmg";
    expect(mirroredDownloadUrl(url)).toBe(`https://${DOWNLOAD_MIRROR_HOST}/${url}`);
  });
  it("is idempotent", () => {
    const once = mirroredDownloadUrl("https://github.com/a/b/releases/download/v1/x.exe");
    expect(mirroredDownloadUrl(once)).toBe(once);
  });
  it("leaves unrelated hosts alone", () => {
    const url = "https://example.com/x.dmg";
    expect(mirroredDownloadUrl(url)).toBe(url);
  });
  it("survives a malformed URL", () => {
    expect(mirroredDownloadUrl("not a url")).toBe("not a url");
  });
});
