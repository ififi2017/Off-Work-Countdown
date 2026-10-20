import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildShiftReminders, type ShiftReminderInputs } from "./reminders";
import {
  WORKING_PROGRESS_STEPS,
  buildWidgetUpcoming,
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

describe("buildWidgetUpcoming", () => {
  const hour = 3_600_000;
  const day = Date.UTC(2026, 9, 20, 0, 0);
  // 09:00–12:00, 13:00–18:00 UTC today; tomorrow the same.
  const shiftOn = (offset: number, overtimeEndAtMs: number | null = null) => ({
    segments: [
      { startAtMs: day + offset + 9 * hour, endAtMs: day + offset + 12 * hour },
      { startAtMs: day + offset + 13 * hour, endAtMs: overtimeEndAtMs ?? day + offset + 18 * hour },
    ],
    plannedEndAtMs: day + offset + 18 * hour,
    overtimeEndAtMs,
  });
  const today = shiftOn(0);
  const tomorrow = shiftOn(24 * hour);
  const labels = {
    shiftStart: "Start",
    shiftEnd: "End",
    overtime: "Overtime",
    breakTitle: "Lunch",
    breakStarts: "Starts",
    breakBackAt: "Back at",
    microBreak: "Health reminder",
    microBreakDetail: "60 min",
    milestone: "Off work reminder",
  };
  const reminderInputs = (mode: ShiftReminderInputs["mode"], microBreakEnabled: boolean): ShiftReminderInputs => ({
    mode,
    fallbackTitle: "Off work reminder",
    breakTitle: "Break reminder",
    milestoneTitles: {
      milestone50: "50% left",
      milestone75: "25% left",
      milestone90: "10% left",
      milestone95: "5% left",
      milestone100: "Off work time!",
    },
    milestoneMessages: {
      milestone50: ["a"],
      milestone75: ["b"],
      milestone90: ["c"],
      milestone95: ["d"],
      milestone100: ["e"],
    },
    lunchStartEnabled: true,
    lunchStartBody: "Lunch",
    lunchEndEnabled: true,
    lunchEndBody: "Back",
    microBreakEnabled,
    microBreakIntervalMinutes: 60,
    microBreakMessages: ["Stretch"],
  });
  const kinds = (items: { kind: string }[]) => items.map((item) => item.kind);

  it("lists the rest of today and tomorrow's boundaries, in order", () => {
    const nowMs = day + 10 * hour;
    const items = buildWidgetUpcoming({
      shift: today,
      nextShift: tomorrow,
      reminders: buildShiftReminders(today, reminderInputs("simple", false)),
      notificationMode: "simple",
      microBreakEnabled: false,
      labels,
      nowMs,
      expiresAtMs: day + 48 * hour,
    });
    expect(kinds(items)).toEqual([
      "lunchStart", "lunchEnd", "shiftEnd",
      "shiftStart", "lunchStart", "lunchEnd", "shiftEnd",
    ]);
    expect(items[0]).toEqual({
      id: `lunch-start-${day + 12 * hour}`,
      kind: "lunchStart",
      title: "Lunch",
      detail: "Starts",
      dateMs: day + 12 * hour,
    });
    expect(items.every((item, index) => index === 0 || items[index - 1].dateMs <= item.dateMs)).toBe(true);
    // 已过去的今天上班不再列出；上下班行不写「今天的班次」。
    expect(items.some((item) => item.id === `shift-start-${day + 9 * hour}`)).toBe(false);
    expect(items.filter((item) => item.kind === "shiftEnd").map((item) => item.detail)).toEqual(["", ""]);
  });

  it("adds one micro-break row and the titled milestones from lib/reminders", () => {
    const nowMs = day + 9 * hour + 5 * 60_000;
    const reminders = buildShiftReminders(today, reminderInputs("milestones", true));
    const items = buildWidgetUpcoming({
      shift: today,
      nextShift: null,
      reminders,
      notificationMode: "milestones",
      microBreakEnabled: true,
      labels,
      nowMs,
      expiresAtMs: day + 24 * hour,
    });
    const health = items.filter((item) => item.kind === "health");
    expect(health).toHaveLength(1);
    const firstMicroBreak = reminders
      .filter((reminder) => reminder.kind === "microBreak" && reminder.atMs > nowMs)
      .sort((a, b) => a.atMs - b.atMs)[0];
    expect(health[0]).toMatchObject({ id: firstMicroBreak.id, title: "Health reminder", detail: "60 min", dateMs: firstMicroBreak.atMs });
    const milestones = items.filter((item) => item.kind === "milestone");
    expect(milestones.map((item) => item.detail)).toEqual(["50% left", "25% left", "10% left", "5% left"]);
    expect(milestones.every((item) => item.title === "Off work reminder")).toBe(true);
  });

  it("leaves milestones out unless reminders follow progress", () => {
    const items = buildWidgetUpcoming({
      shift: today,
      nextShift: null,
      reminders: buildShiftReminders(today, reminderInputs("simple", false)),
      notificationMode: "simple",
      microBreakEnabled: false,
      labels,
      nowMs: day + 9 * hour,
      expiresAtMs: day + 24 * hour,
    });
    expect(kinds(items)).toEqual(["lunchStart", "lunchEnd", "shiftEnd"]);
  });

  it("marks overtime and drops rows past the snapshot's expiry", () => {
    const overtime = shiftOn(0, day + 20 * hour);
    const items = buildWidgetUpcoming({
      shift: overtime,
      nextShift: tomorrow,
      reminders: [],
      notificationMode: "off",
      microBreakEnabled: false,
      labels,
      nowMs: day + 19 * hour,
      expiresAtMs: day + 24 * hour + 10 * hour,
    });
    expect(items.map((item) => [item.kind, item.detail])).toEqual([
      ["shiftEnd", "Overtime"],
      ["shiftStart", ""],
    ]);
  });

  it("is written into the snapshot only when there is something to show", () => {
    const options = {
      running: true,
      shift: today,
      nextShift: tomorrow,
      locale: "en",
      generatedAtMs: day + 10 * hour,
      expiresAtMs: day + 33 * hour,
    };
    expect("upcoming" in createWidgetSnapshot(options)).toBe(false);
    const upcoming = buildWidgetUpcoming({
      shift: today,
      nextShift: tomorrow,
      reminders: [],
      notificationMode: "off",
      microBreakEnabled: false,
      labels,
      nowMs: options.generatedAtMs,
      expiresAtMs: options.expiresAtMs,
    });
    const snapshot = JSON.parse(serializeWidgetSnapshot(createWidgetSnapshot({ ...options, upcoming })));
    expect(snapshot.upcoming).toEqual(upcoming);
    expect(Object.keys(snapshot.upcoming[0]).sort()).toEqual(["dateMs", "detail", "id", "kind", "title"]);
  });
});
