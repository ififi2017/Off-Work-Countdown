import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  WORKING_PROGRESS_STEPS,
  createWidgetSnapshot,
  getWidgetTimelineEntry,
  serializeWidgetSnapshot,
} from "./widget-snapshot";

const fixturePath =
  "src-tauri/macos-widget/Tests/WidgetSnapshotContractTests/Fixtures/widget-snapshot-v1.json";

describe("WidgetSnapshotV1", () => {
  const shift = {
    segments: [
      { startAtMs: 1_000, endAtMs: 5_000 },
      { startAtMs: 7_000, endAtMs: 11_000 },
    ],
    plannedEndAtMs: 11_000,
    overtimeEndAtMs: null,
  };

  it("matches the Swift decoder fixture and freezes effective progress in gaps", () => {
    const snapshot = createWidgetSnapshot({
      running: true,
      shift,
      nextShift: null,
      locale: "en",
      generatedAtMs: 3_000,
      expiresAtMs: 13_000,
    });

    expect(serializeWidgetSnapshot(snapshot)).toBe(
      readFileSync(fixturePath, "utf8")
    );
    expect(snapshot.entries.map((entry) => entry.phase)).toEqual([
      "working",
      "break",
      "working",
      "done",
    ]);
    expect(snapshot.entries[1].remainingEffectiveMsAtDateMs).toBe(4_000);
    expect(snapshot.entries[1].progressAtDate).toBe(50);
    expect(snapshot.entries[2].remainingEffectiveMsAtDateMs).toBe(4_000);
    expect(snapshot.entries[2].progressAtDate).toBe(50);
  });

  it("produces an idle projection instead of leaking an invalid shift", () => {
    const snapshot = createWidgetSnapshot({
      running: true,
      shift: {
        segments: [],
        plannedEndAtMs: 0,
        overtimeEndAtMs: null,
      },
      nextShift: null,
      locale: "zh-CN",
      generatedAtMs: 10,
      expiresAtMs: 20,
    });

    expect(snapshot.shift).toBeNull();
    expect(snapshot.entries).toEqual([
      expect.objectContaining({ phase: "idle", labelKey: "countdownNotStarted" }),
    ]);
  });

  it("precomputes a before-shift entry and rejects stale snapshots", () => {
    const snapshot = createWidgetSnapshot({
      running: true,
      shift,
      nextShift: null,
      locale: "en",
      generatedAtMs: 0,
      expiresAtMs: 13_000,
    });

    expect(snapshot.entries[0]).toEqual(
      expect.objectContaining({
        phase: "before",
        countdownTargetAtMs: 1_000,
        nextBoundaryAtMs: 1_000,
      })
    );
    expect(getWidgetTimelineEntry(snapshot, 7_500)?.phase).toBe("working");
    expect(getWidgetTimelineEntry(snapshot, 13_000)).toBeNull();
  });

  it("extends progress and remaining time through frontend-supplied overtime", () => {
    const snapshot = createWidgetSnapshot({
      running: true,
      shift: {
        segments: [{ startAtMs: 1_000, endAtMs: 13_000 }],
        plannedEndAtMs: 11_000,
        overtimeEndAtMs: 13_000,
      },
      nextShift: null,
      locale: "en",
      generatedAtMs: 11_000,
      expiresAtMs: 14_000,
    });

    expect(snapshot.entries[0]).toEqual(
      expect.objectContaining({
        phase: "working",
        remainingEffectiveMsAtDateMs: 2_000,
        progressAtDate: 100 * (10 / 12),
      })
    );
  });

  it("keeps progress moving inside a long working segment", () => {
    const startAtMs = Date.UTC(2026, 7, 17, 1, 0);
    const lunchStartAtMs = Date.UTC(2026, 7, 17, 4, 0);
    const lunchEndAtMs = Date.UTC(2026, 7, 17, 5, 0);
    const endAtMs = Date.UTC(2026, 7, 17, 10, 0);
    const snapshot = createWidgetSnapshot({
      running: true,
      shift: {
        segments: [
          { startAtMs, endAtMs: lunchStartAtMs },
          { startAtMs: lunchEndAtMs, endAtMs },
        ],
        plannedEndAtMs: endAtMs,
        overtimeEndAtMs: null,
      },
      nextShift: null,
      locale: "en",
      generatedAtMs: startAtMs,
      expiresAtMs: endAtMs + 60 * 60 * 1000,
    });

    // 8 小时有效工时切成 100 步 ≈ 每 4.8 分钟一条，进度大约每 1% 刷新一次。
    const working = snapshot.entries.filter((entry) => entry.phase === "working");
    expect(working.length).toBeGreaterThan(90);
    expect(working.length).toBeLessThanOrEqual(WORKING_PROGRESS_STEPS + 2);

    // 上午整段不再是一个常数：进度必须严格单调上升。
    const morning = working.filter((entry) => entry.dateMs < lunchStartAtMs);
    expect(morning.length).toBeGreaterThan(30);
    for (let index = 1; index < morning.length; index += 1) {
      expect(morning[index].progressAtDate).toBeGreaterThan(
        morning[index - 1].progressAtDate
      );
    }
    expect(morning.at(-1)!.progressAtDate - morning[0].progressAtDate)
      .toBeGreaterThan(35);

    // 同一 segment 内 elapsed 与墙上时间 1:1，因此子 entry 换手时倒计时的绝对
    // 目标时刻必须保持不变，否则用户会看到秒数原地跳一下。
    expect(new Set(morning.map((entry) => entry.countdownTargetAtMs)).size).toBe(1);
    expect(morning[0].countdownTargetAtMs).toBe(endAtMs);

    // 细分只影响 working，边界语义不变。
    expect(
      snapshot.entries.filter((entry) => entry.phase === "break")
    ).toHaveLength(1);
    expect(morning.every((entry) => entry.nextBoundaryAtMs === lunchStartAtMs)).toBe(
      true
    );

    // 相邻 entry 的时间区间必须首尾相接、无空洞，否则 Swift 侧会取不到值。
    for (let index = 1; index < snapshot.entries.length; index += 1) {
      expect(snapshot.entries[index].dateMs).toBe(
        snapshot.entries[index - 1].validUntilMs
      );
    }
    expect(getWidgetTimelineEntry(snapshot, startAtMs + 90 * 60 * 1000)?.phase).toBe(
      "working"
    );
  });

  it("stays well inside the host's snapshot size limit", () => {
    const startAtMs = Date.UTC(2026, 7, 17, 0, 0);
    const endAtMs = Date.UTC(2026, 7, 18, 0, 0);
    const snapshot = createWidgetSnapshot({
      running: true,
      shift: {
        segments: [{ startAtMs, endAtMs }],
        plannedEndAtMs: endAtMs,
        overtimeEndAtMs: null,
      },
      nextShift: null,
      locale: "en",
      generatedAtMs: startAtMs,
      expiresAtMs: endAtMs + 60 * 60 * 1000,
    });

    // Rust 侧 write_widget_snapshot 的上限是 256 KiB。
    expect(Buffer.byteLength(serializeWidgetSnapshot(snapshot), "utf8")).toBeLessThan(
      64 * 1024
    );
  });

  it("counts down to the next shift once the current one is done", () => {
    const startAtMs = Date.UTC(2026, 7, 17, 1, 0);
    const endAtMs = Date.UTC(2026, 7, 17, 10, 0);
    const nextStartAtMs = Date.UTC(2026, 7, 18, 1, 0);
    // 下班后才生成——正是旧公式把有效期塌缩成 1 小时的那个时刻。
    const generatedAtMs = Date.UTC(2026, 7, 17, 12, 0);
    const snapshot = createWidgetSnapshot({
      running: true,
      shift: {
        segments: [{ startAtMs, endAtMs }],
        plannedEndAtMs: endAtMs,
        overtimeEndAtMs: null,
      },
      nextShift: {
        segments: [{ startAtMs: nextStartAtMs, endAtMs: nextStartAtMs + 3_600_000 }],
        plannedEndAtMs: nextStartAtMs + 3_600_000,
        overtimeEndAtMs: null,
      },
      locale: "zh-CN",
      generatedAtMs,
      expiresAtMs: nextStartAtMs,
    });

    expect(snapshot.entries).toHaveLength(1);
    const done = snapshot.entries[0];
    // 相位仍是「今日已下班」——标签和配色不变，只是大数字在倒数下次上班。
    expect(done.phase).toBe("done");
    expect(done.labelKey).toBe("offWorkToday");
    expect(done.countdownKind).toBe("shiftStarts");
    expect(done.countdownTargetAtMs).toBe(nextStartAtMs);
    expect(done.nextBoundaryAtMs).toBe(nextStartAtMs);
    expect(done.progressAtDate).toBe(100);
    expect(done.validUntilMs).toBe(nextStartAtMs);
    // 整段空窗期都取得到值，不会中途翻成空态。
    expect(
      getWidgetTimelineEntry(snapshot, nextStartAtMs - 60_000)?.phase
    ).toBe("done");
  });

  it("keeps a static zero when there is no known next shift", () => {
    const startAtMs = Date.UTC(2026, 7, 17, 1, 0);
    const endAtMs = Date.UTC(2026, 7, 17, 10, 0);
    const generatedAtMs = Date.UTC(2026, 7, 17, 12, 0);
    const snapshot = createWidgetSnapshot({
      running: true,
      shift: {
        segments: [{ startAtMs, endAtMs }],
        plannedEndAtMs: endAtMs,
        overtimeEndAtMs: null,
      },
      nextShift: null,
      locale: "en",
      generatedAtMs,
      expiresAtMs: generatedAtMs + 24 * 60 * 60 * 1000,
    });

    expect(snapshot.entries[0].countdownKind).toBe("complete");
    expect(snapshot.entries[0].countdownTargetAtMs).toBeNull();
  });

  it("ignores a next shift that already started", () => {
    const startAtMs = Date.UTC(2026, 7, 17, 1, 0);
    const endAtMs = Date.UTC(2026, 7, 17, 10, 0);
    const generatedAtMs = Date.UTC(2026, 7, 17, 12, 0);
    const snapshot = createWidgetSnapshot({
      running: true,
      shift: {
        segments: [{ startAtMs, endAtMs }],
        plannedEndAtMs: endAtMs,
        overtimeEndAtMs: null,
      },
      // 休眠后恢复出的陈旧 nextShift：倒数一个已经过去的时刻会显示成不动的 0。
      nextShift: {
        segments: [{ startAtMs: Date.UTC(2026, 7, 16, 1, 0), endAtMs: Date.UTC(2026, 7, 16, 10, 0) }],
        plannedEndAtMs: Date.UTC(2026, 7, 16, 10, 0),
        overtimeEndAtMs: null,
      },
      locale: "en",
      generatedAtMs,
      expiresAtMs: generatedAtMs + 60 * 60 * 1000,
    });

    expect(snapshot.entries[0].countdownKind).toBe("complete");
    expect(snapshot.entries[0].countdownTargetAtMs).toBeNull();
  });

  it("rejects a non-positive validity window", () => {
    expect(() =>
      createWidgetSnapshot({
        running: false,
        shift: null,
        nextShift: null,
        locale: "en",
        generatedAtMs: 10,
        expiresAtMs: 10,
      })
    ).toThrow("expire after");
  });
});
