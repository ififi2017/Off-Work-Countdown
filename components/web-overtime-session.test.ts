import { describe, expect, it } from "vitest";
import {
  buildShiftTimeline,
  calculateTimelinePayRatio,
  extendShiftWithOvertime,
  getDailySalary,
  getShiftEndAtMs,
  getShiftRemainingMs,
  resolveOvertimeEndAtMs,
} from "@/lib/countdown";
import { buildShareUrl } from "@/lib/share";
import {
  WEB_OVERTIME_STORAGE_KEY,
  clearWebOvertimeSession,
  readWebOvertimeSession,
  webOvertimeExpiresAtMs,
  webOvertimeStorageKey,
  writeWebOvertimeSession,
  type WebOvertimeSession,
  type WebOvertimeStorage,
} from "./web-overtime-session";

const at = (day: number, hour: number, minute = 0) => new Date(2026, 10, day, hour, minute).getTime();
const ownHours = { start: "09:00", end: "17:00" };

function memoryStorage() {
  const values = new Map<string, string>();
  const storage = {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => { values.set(key, value); },
    removeItem: (key: string) => { values.delete(key); },
  };
  return { values, storage: () => storage };
}

function dayOvertime(endHour = 19): WebOvertimeSession {
  const shift = buildShiftTimeline("09:00", "17:00", new Date(at(5, 16)));
  return {
    startTime: "09:00",
    endTime: "17:00",
    shift: extendShiftWithOvertime(shift, at(5, endHour)),
  };
}

describe("Web overtime session", () => {
  it("resumes the exact effective timeline on reload or locale navigation and preserves the hourly salary rate", () => {
    const { storage } = memoryStorage();
    const session = dayOvertime();
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, session);
    const restored = readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 18), ownHours)!;
    expect(restored).toEqual(session);
    expect(getShiftRemainingMs(restored.shift, at(5, 18))).toBe(60 * 60 * 1000);
    // 8 planned hours; the ninth earned hour remains at the same daily rate.
    const daily = getDailySalary("1600", "monthly", 20)!;
    expect(daily * calculateTimelinePayRatio(restored.shift, at(5, 18))).toBe(90);
    const adjustedEnd = resolveOvertimeEndAtMs(restored.shift, "20:07", at(5, 18))!;
    const adjusted = { ...restored, shift: extendShiftWithOvertime(restored.shift, adjustedEnd) };
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, adjusted);
    expect(getShiftEndAtMs(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 19))!.shift)).toBe(at(5, 20, 7));
  });

  it("keeps an overnight shift absolute after the configured end hour passes", () => {
    const { storage } = memoryStorage();
    const shift = buildShiftTimeline("22:00", "06:00", new Date(at(6, 5)));
    const session = { startTime: "22:00", endTime: "06:00", shift: extendShiftWithOvertime(shift, at(6, 8)) };
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, session);
    const restored = readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(6, 7))!;
    expect(restored.shift.segments[0].startAtMs).toBe(at(5, 22));
    expect(getShiftRemainingMs(restored.shift, at(6, 7))).toBe(60 * 60 * 1000);
    expect(calculateTimelinePayRatio(restored.shift, at(6, 7))).toBe(9 / 8);
  });

  it("keeps a completed same-day result adjustable, then removes it on the next day", () => {
    const { storage, values } = memoryStorage();
    const session = dayOvertime();
    expect(webOvertimeExpiresAtMs(session.shift)).toBe(at(6, 0));
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, session);
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 23))).toEqual(session);
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(6, 0))).toBeNull();
    expect(values.has(WEB_OVERTIME_STORAGE_KEY)).toBe(false);
  });

  it("restores overtime crossing midnight until its actual end, then expires it", () => {
    const { storage } = memoryStorage();
    const session = dayOvertime();
    session.shift = extendShiftWithOvertime(session.shift, at(6, 1));
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, session);
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(6, 0, 30))).toEqual(session);
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(6, 1))).toBeNull();
  });

  it("isolates URL sessions from the visitor's own session and from other shared shifts", () => {
    const own = memoryStorage();
    const shared = memoryStorage();
    const ownSession = dayOvertime();
    const sharedHours = { start: "10:00", end: "18:00" };
    const sharedKey = webOvertimeStorageKey(sharedHours);
    const sharedSession = {
      startTime: sharedHours.start,
      endTime: sharedHours.end,
      shift: extendShiftWithOvertime(buildShiftTimeline("10:00", "18:00", new Date(at(5, 16))), at(5, 21)),
    };
    writeWebOvertimeSession(own.storage, webOvertimeStorageKey(null), ownSession);
    writeWebOvertimeSession(shared.storage, sharedKey, sharedSession);
    expect(readWebOvertimeSession(shared.storage, sharedKey, at(5, 19), sharedHours)).toEqual(sharedSession);
    expect(readWebOvertimeSession(shared.storage, webOvertimeStorageKey(ownHours), at(5, 19))).toBeNull();
    clearWebOvertimeSession(shared.storage, sharedKey);
    expect(readWebOvertimeSession(shared.storage, sharedKey, at(5, 19))).toBeNull();
    expect(readWebOvertimeSession(own.storage, webOvertimeStorageKey(null), at(5, 19), ownHours)).toEqual(ownSession);
  });

  it("a return/reset clears the saved run so the next visit does not auto-start it", () => {
    const { storage } = memoryStorage();
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, dayOvertime());
    clearWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY);
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 18))).toBeNull();
  });

  it("discards an old session after the visitor changes their saved hours elsewhere", () => {
    const { storage, values } = memoryStorage();
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, dayOvertime());
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 18), { start: "10:00", end: "18:00" })).toBeNull();
    expect(values.size).toBe(0);
  });

  it("serializes only timing fields, and sharing still includes only the original configured hours", () => {
    const { storage, values } = memoryStorage();
    const session = { ...dayOvertime(), salaryAmount: "secret", hideEarnings: false };
    Object.assign(session.shift, { salaryAmount: "secret" });
    Object.assign(session.shift.segments[0], { salaryAmount: "secret" });
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, session);
    const raw = values.get(WEB_OVERTIME_STORAGE_KEY)!;
    expect(raw).not.toMatch(/salary|secret|hideEarnings/);
    const url = new URL(buildShareUrl("text", ownHours));
    expect(url.searchParams.get("s")).toBe("0900-1700");
    expect(url.href).not.toMatch(/salary|secret|overtime/);
  });

  it.each([
    "{broken",
    "null",
    "{}",
    JSON.stringify({ version: 2, ...dayOvertime() }),
    JSON.stringify({ version: 1, ...dayOvertime(), startTime: "99:99" }),
    JSON.stringify({ version: 1, ...dayOvertime(), shift: { ...dayOvertime().shift, segments: [null] } }),
    JSON.stringify({ version: 1, ...dayOvertime(), shift: { ...dayOvertime().shift, overtimeEndAtMs: null } }),
    JSON.stringify({ version: 1, ...dayOvertime(), shift: { ...dayOvertime().shift, overtimeEndAtMs: at(5, 16) } }),
  ])("discards malformed or incompatible snapshots safely (%#)", (raw) => {
    const { storage, values } = memoryStorage();
    values.set(WEB_OVERTIME_STORAGE_KEY, raw);
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 18))).toBeNull();
    expect(values.size).toBe(0);
  });

  it("does not restore a future session when the device clock has moved backwards", () => {
    const { storage } = memoryStorage();
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, dayOvertime());
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 8))).toBeNull();
  });

  it("tolerates denied storage getters and failed read/write/remove operations", () => {
    const denied: WebOvertimeStorage = () => { throw new Error("SecurityError"); };
    const failures: WebOvertimeStorage = () => ({
      getItem: () => { throw new Error("SecurityError"); },
      setItem: () => { throw new Error("QuotaExceededError"); },
      removeItem: () => { throw new Error("SecurityError"); },
    });
    for (const storage of [denied, failures]) {
      expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 18))).toBeNull();
      expect(() => writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, dayOvertime())).not.toThrow();
      expect(() => clearWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY)).not.toThrow();
    }
  });

  it("keeps this overtime's pay multiple and reads older sessions as the usual rate", () => {
    const { storage, values } = memoryStorage();
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, { ...dayOvertime(), payMultiplier: 1.5 });
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 18), ownHours)!.payMultiplier).toBe(1.5);
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, { ...dayOvertime(), payMultiplier: 0 });
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 18), ownHours)!.payMultiplier).toBe(0);
    writeWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, { ...dayOvertime(), payMultiplier: 1 });
    expect(values.get(WEB_OVERTIME_STORAGE_KEY)).not.toContain("payMultiplier");
    expect(readWebOvertimeSession(storage, WEB_OVERTIME_STORAGE_KEY, at(5, 18), ownHours)!.payMultiplier).toBeUndefined();
  });
});
