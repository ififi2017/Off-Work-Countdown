import { describe, expect, it } from "vitest";
import { getPublicPages, pageUrl } from "@/features/web-tools/catalog/pages";
import { presetSlugs } from "@/lib/presets";
import { GET } from "./route";

describe("llms.txt", () => {
  it("returns a short plain-text map of the two DoneAt hosts", async () => {
    const response = GET();
    const text = await response.text();

    expect(response.headers.get("content-type")).toMatch(/text\/plain/);
    expect(text).toContain("https://off.rainif.com/en");
    expect(text).toContain("https://doneat.app");
    expect(text).toContain("https://off.rainif.com/sitemap.xml");
    expect(text).toMatch(/iPhone, iPad and Android apps/);
    expect(text).not.toMatch(/<!DOCTYPE html/i);
  });

  it("follows llms.txt shape and lists every preset and published tool page", async () => {
    const text = await GET().text();

    expect(text.startsWith("# DoneAt web timer\n\n> ")).toBe(true);
    expect(text).toContain("https://doneat.app/llms.txt");
    for (const slug of presetSlugs) expect(text).toContain(`https://off.rainif.com/en/${slug}`);
    for (const page of getPublicPages()) expect(text).toContain(pageUrl(page));
  });
});
