import { describe, expect, it } from "vitest";
import {
  emptyDesktopCountdownState,
  formatDesktopDuration,
  getDesktopCountdownView,
  hasAuthoritativeDesktopPreferences,
  normalizeDesktopCountdownState,
  shouldOfferBrandRenameNotice,
} from "./desktop-state";

describe("desktop countdown state", () => {
  it("keeps hidden earnings hidden in an idle snapshot", () => {
    const state = emptyDesktopCountdownState(
      "zh-CN",
      "倒计时未开始",
      { showEarnings: "显示薪资", hideEarnings: "隐藏薪资" },
      {
        showSalary: true,
        hideEarnings: true,
        miniSkin: "standard",
        woodfishSoundEnabled: true,
      }
    );

    expect(state).toMatchObject({
      preferencesVersion: 1,
      running: false,
      showSalary: true,
      hideEarnings: true,
      miniSkin: "standard",
      woodfishSoundEnabled: true,
    });
    expect(normalizeDesktopCountdownState(state).hideEarnings).toBe(true);
  });

  it("marks snapshots from older releases as legacy preferences", () => {
    const legacy = normalizeDesktopCountdownState({ running: false });
    expect(legacy).toMatchObject({
      preferencesVersion: 0,
      running: false,
    });
    expect(hasAuthoritativeDesktopPreferences(legacy)).toBe(false);
    expect(
      hasAuthoritativeDesktopPreferences(emptyDesktopCountdownState())
    ).toBe(true);
  });

  it("formats a language-neutral duration without wrapping at 24 hours", () => {
    expect(formatDesktopDuration(25 * 60 * 60 * 1000 + 61_000)).toBe(
      "25:01:01"
    );
    expect(formatDesktopDuration(-1)).toBe("0:00:00");
  });

  it("truncates sub-second remainders instead of rounding up", () => {
    // 小组件由系统渲染、取整方式改不了，主窗口也是向下取整；这里用 ceil 会让
    // 迷你窗与托盘恒定多显示一秒。现有用例都是整千毫秒，区分不出两种取整。
    expect(formatDesktopDuration(1_999)).toBe("0:00:01");
    expect(formatDesktopDuration(1_000)).toBe("0:00:01");
    expect(formatDesktopDuration(999)).toBe("0:00:00");
  });

  it("derives progress and earned salary from absolute timestamps", () => {
    const state = {
      ...emptyDesktopCountdownState(),
      segments: [{ startAtMs: 1_000, endAtMs: 11_000 }],
      plannedEndAtMs: 11_000,
      running: true,
      showSalary: true,
      dailySalary: 200,
    };

    expect(getDesktopCountdownView(state, 6_000)).toEqual({
      time: "0:00:05",
      progress: 50,
      earned: 100,
      phase: "working",
    });
  });

  it("returns an idle view when no countdown is active", () => {
    expect(
      getDesktopCountdownView(emptyDesktopCountdownState(), Date.now())
    ).toEqual({ time: "--:--:--", progress: 0, earned: null, phase: "idle" });
  });

  it("counts down to a future shift without starting progress or pay", () => {
    const state = {
      ...emptyDesktopCountdownState(),
      segments: [{ startAtMs: 11_000, endAtMs: 21_000 }],
      plannedEndAtMs: 21_000,
      running: true,
      showSalary: true,
      dailySalary: 200,
    };

    expect(getDesktopCountdownView(state, 1_000)).toEqual({
      time: "0:00:10",
      progress: 0,
      earned: 0,
      phase: "before",
    });
  });

  it("counts down to the end of the break, while progress and pay stay frozen", () => {
    const state = {
      ...emptyDesktopCountdownState(),
      segments: [
        { startAtMs: 1_000, endAtMs: 4_000 },
        { startAtMs: 6_000, endAtMs: 11_000 },
      ],
      plannedEndAtMs: 11_000,
      running: true,
      showSalary: true,
      dailySalary: 80,
    };

    // 休息期间显示的是「距休息结束」，不是冻住的下班倒计时——后者整段
    // 时间纹丝不动，看起来像应用卡死了。进度与计薪则确实是冻结的。
    expect(getDesktopCountdownView(state, 5_000)).toEqual({
      time: "0:00:01",
      progress: 37.5,
      earned: 30,
      phase: "break",
    });
    // 复工那一刻切回下班倒计时，且进度／计薪从休息前的位置无缝接上。
    expect(getDesktopCountdownView(state, 6_000)).toMatchObject({
      time: "0:00:05",
      progress: 37.5,
      earned: 30,
      phase: "working",
    });
  });

  it("shows the next-shift gap and pays overtime at the original hourly rate", () => {
    const state = {
      ...emptyDesktopCountdownState(),
      segments: [{ startAtMs: 1_000, endAtMs: 13_000 }],
      plannedEndAtMs: 11_000,
      overtimeEndAtMs: 13_000,
      nextShift: {
        segments: [{ startAtMs: 21_000, endAtMs: 31_000 }],
        plannedEndAtMs: 31_000,
        overtimeEndAtMs: null,
      },
      running: true,
      showSalary: true,
      dailySalary: 100,
    };
    expect(getDesktopCountdownView(state, 13_000)).toEqual({
      time: "0:00:08",
      progress: 100,
      earned: 120,
      phase: "between",
    });
  });

  it("offers the DoneAt rename notice only to existing desktop installs", () => {
    expect(
      shouldOfferBrandRenameNotice({
        noticeSeen: false,
        hadExistingCountdown: true,
      })
    ).toBe(true);
    expect(
      shouldOfferBrandRenameNotice({
        noticeSeen: true,
        hadExistingCountdown: true,
      })
    ).toBe(false);
    expect(
      shouldOfferBrandRenameNotice({
        noticeSeen: false,
        hadExistingCountdown: false,
      })
    ).toBe(false);
    expect(
      shouldOfferBrandRenameNotice({
        noticeSeen: true,
        hadExistingCountdown: false,
      })
    ).toBe(false);
  });

  it("migrates a 3.0 single-range snapshot without recalculating it", () => {
    const migrated = normalizeDesktopCountdownState({
      startAtMs: 1_000,
      endAtMs: 11_000,
      running: true,
      reminder: true,
      lang: "zh-CN",
    });

    expect(migrated.segments).toEqual([
      { startAtMs: 1_000, endAtMs: 11_000 },
    ]);
    expect(migrated.plannedEndAtMs).toBe(11_000);
    expect(migrated.overtimeEndAtMs).toBeNull();
    expect(migrated.running).toBe(true);
    expect(migrated.notificationMode).toBe("simple");
    expect(migrated.lang).toBe("zh-CN");
    expect(migrated).not.toHaveProperty("startAtMs");
    expect(migrated).not.toHaveProperty("endAtMs");
    expect(migrated).not.toHaveProperty("reminder");
  });
});
