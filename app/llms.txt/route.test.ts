import { describe, expect, it } from "vitest";
import { GET } from "./route";

describe("llms.txt", () => {
  it("returns a short plain-text map of the two DoneAt hosts", async () => {
    const response = GET();
    const text = await response.text();

    expect(response.headers.get("content-type")).toMatch(/text\/plain/);
    expect(text).toContain("https://off.rainif.com/en");
    expect(text).toContain("https://doneat.app");
    expect(text).toContain("https://off.rainif.com/sitemap.xml");
    expect(text).toMatch(/iOS/);
    expect(text).not.toMatch(/<!DOCTYPE html/i);
  });
});
