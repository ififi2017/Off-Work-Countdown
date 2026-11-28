import { describe, expect, it } from "vitest";
import { GET } from "./route";

const LINE = "google.com, pub-9912554861143289, DIRECT, f08c47fec0942fa0\n";

describe("ads.txt", () => {
  it("returns the single AdSense record as text/plain", async () => {
    const response = GET();
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/plain");
    expect(text).toBe(LINE);
    expect(text.trim().split("\n")).toEqual([LINE.trim()]);
  });
});
