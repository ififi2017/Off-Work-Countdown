import { EventEmitter } from "node:events";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { spawn } = vi.hoisted(() => ({ spawn: vi.fn() }));
vi.mock("node:child_process", async (original) => ({ ...await original(), spawn }));

import { captureHtml } from "./chrome.mjs";

let directory;
let chrome;
let options;
const profile = () => spawn.mock.calls[0][1].find((arg) => arg.startsWith("--user-data-dir=")).split("=")[1];

beforeEach(() => {
  vi.useFakeTimers();
  spawn.mockReset();
  directory = mkdtempSync(join(tmpdir(), "owc-chrome-test-"));
  chrome = new EventEmitter();
  chrome.kill = vi.fn();
  spawn.mockReturnValue(chrome);
  options = {
    html: "<h1>DoneAt</h1>", htmlPath: join(directory, "shot.html"),
    width: 320, height: 240, scale: 1, outFile: join(directory, "shot.png"),
  };
});

afterEach(() => {
  vi.useRealTimers();
  rmSync(directory, { recursive: true, force: true });
});

describe("captureHtml process lifecycle", () => {
  it("waits for Chrome to stop before removing its profile, without forcing it", async () => {
    const finished = vi.fn();
    const capture = captureHtml(options).then(finished);
    writeFileSync(options.outFile, "image");
    await vi.advanceTimersByTimeAsync(500);
    expect(chrome.kill.mock.calls).toEqual([["SIGTERM"]]);
    expect(finished).not.toHaveBeenCalled();
    expect(existsSync(profile())).toBe(true);

    chrome.emit("exit", 0, null);
    await capture;
    expect(existsSync(profile())).toBe(false);
    expect(existsSync(options.outFile)).toBe(true);
    expect(chrome.kill.mock.calls).toEqual([["SIGTERM"]]);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("reports launch errors immediately and cleans up the profile", async () => {
    const capture = expect(captureHtml(options)).rejects.toThrow("ENOENT");
    chrome.emit("error", new Error("spawn ENOENT"));
    await capture;
    expect(existsSync(profile())).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("removes the old image and rejects a failed render", async () => {
    writeFileSync(options.outFile, "old image");
    const capture = expect(captureHtml(options)).rejects.toThrow("Chrome exited with 1");
    chrome.emit("exit", 1, null);
    await capture;
    expect(existsSync(options.outFile)).toBe(false);
    expect(existsSync(profile())).toBe(false);
  });

  it("rejects a successful exit that produced no image", async () => {
    const capture = expect(captureHtml(options)).rejects.toThrow("Chrome did not write");
    chrome.emit("exit", 0, null);
    await capture;
    expect(existsSync(profile())).toBe(false);
  });

  it("gives a timed-out Chrome five seconds to exit before forcing it", async () => {
    chrome.kill.mockImplementation((signal) => {
      if (signal === "SIGKILL") queueMicrotask(() => chrome.emit("exit", null, signal));
    });
    const capture = expect(captureHtml(options)).rejects.toThrow("Chrome timed out");
    await vi.advanceTimersByTimeAsync(60000);
    expect(chrome.kill.mock.calls).toEqual([["SIGTERM"]]);
    expect(existsSync(profile())).toBe(true);
    await vi.advanceTimersByTimeAsync(5000);
    await capture;
    expect(chrome.kill.mock.calls).toEqual([["SIGTERM"], ["SIGKILL"]]);
    expect(existsSync(profile())).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });
});
