import { describe, it, expect } from "vitest";
import {
  buildShiftReminders,
  selectDueReminders,
  shiftRemindersRevision,
  REMINDER_MODEL_VERSION,
  type ShiftReminder,
  type ShiftReminderInputs,
} from "./reminders";
import type { ShiftTimeline } from "./countdown";

// 这份测试同时是 Rust 侧 `advance_reminders` 的验收标准：升级前那三套判定
// （里程碑跨越、午休边界、健康提醒）的语义逐条固定在这里，Rust 只负责按
// 这些字段做比较。改动这里的期望值等于改动桌面端的通知行为。

const inputs: ShiftReminderInputs = {
  mode: "milestones",
  fallbackTitle: "下班提醒",
  milestoneTitles: {
    milestone50: "还剩 50%",
    milestone75: "还剩 25%",
    milestone90: "还剩 10%",
    milestone95: "还剩 5%",
    milestone100: "下班了",
  },
  milestoneMessages: {
    milestone50: ["一半了"],
    milestone75: ["最难的过去了"],
    milestone90: ["快到了"],
    milestone95: ["再撑一下"],
    milestone100: ["下班时间到"],
  },
  lunchStartEnabled: true,
  lunchStartBody: "午休开始",
  lunchEndEnabled: true,
  lunchEndBody: "午休结束",
  microBreakEnabled: true,
  microBreakTitle: "健康提醒",
  microBreakIntervalMinutes: 1,
  microBreakMessages: ["已经坐了 {{minutes}} 分钟了"],
};

/** 单段班次，0 到 1000ms，便于直接读出里程碑的绝对时刻。 */
const simpleShift: ShiftTimeline = {
  segments: [{ startAtMs: 0, endAtMs: 1_000 }],
  plannedEndAtMs: 1_000,
  overtimeEndAtMs: null,
};

/** 带午休的班次：0-3000 工作，3000-4000 午休，4000-9000 工作。 */
const lunchShift: ShiftTimeline = {
  segments: [
    { startAtMs: 0, endAtMs: 3_000 },
    { startAtMs: 4_000, endAtMs: 9_000 },
  ],
  plannedEndAtMs: 9_000,
  overtimeEndAtMs: null,
};

function withoutMicroBreaks(overrides: Partial<ShiftReminderInputs> = {}) {
  return { ...inputs, microBreakIntervalMinutes: 0, ...overrides };
}

function byId(reminders: ShiftReminder[], id: string): ShiftReminder {
  const found = reminders.find((reminder) => reminder.id === id);
  if (!found) throw new Error(`missing reminder: ${id}`);
  return found;
}

describe("buildShiftReminders 里程碑", () => {
  it("把百分比换算成绝对时刻", () => {
    const reminders = buildShiftReminders(simpleShift, withoutMicroBreaks());
    expect(byId(reminders, "milestone:50").atMs).toBe(500);
    expect(byId(reminders, "milestone:75").atMs).toBe(750);
    expect(byId(reminders, "milestone:90").atMs).toBe(900);
    expect(byId(reminders, "milestone:95").atMs).toBe(950);
    expect(byId(reminders, "milestone:100").atMs).toBe(1_000);
  });

  it("跨过午休空隙时按有效工时折算，而不是按墙上时钟", () => {
    // 有效工时共 8000ms，一半是 4000ms：前段用掉 3000ms，剩下 1000ms 落在
    // 第二段开始之后 —— 也就是 5000，而不是墙上时钟的中点 4500。
    const reminders = buildShiftReminders(lunchShift, withoutMicroBreaks());
    expect(byId(reminders, "milestone:50").atMs).toBe(5_000);
    expect(byId(reminders, "milestone:100").atMs).toBe(9_000);
  });

  it("恰好落在段末的里程碑在该段结束那一刻触发", () => {
    // 3000/8000 = 37.5%，取 37.5% 的档位不存在；换一个班次让 50% 正好压线。
    const shift: ShiftTimeline = {
      segments: [
        { startAtMs: 0, endAtMs: 4_000 },
        { startAtMs: 5_000, endAtMs: 9_000 },
      ],
      plannedEndAtMs: 9_000,
      overtimeEndAtMs: null,
    };
    const reminders = buildShiftReminders(shift, withoutMicroBreaks());
    // 有效工时 8000，一半 4000，正好是第一段末尾：应当是 4000 而不是 5000。
    expect(byId(reminders, "milestone:50").atMs).toBe(4_000);
  });

  it("加班延长后 100% 跟着推到实际结束时刻", () => {
    const overtime: ShiftTimeline = {
      segments: [{ startAtMs: 0, endAtMs: 1_500 }],
      plannedEndAtMs: 1_000,
      overtimeEndAtMs: 1_500,
    };
    const reminders = buildShiftReminders(overtime, withoutMicroBreaks());
    expect(byId(reminders, "milestone:100").atMs).toBe(1_500);
  });

  it("simple 模式只让 100% 出声，其余仍在列表里占位", () => {
    const reminders = buildShiftReminders(
      simpleShift,
      withoutMicroBreaks({ mode: "simple" })
    );
    expect(byId(reminders, "milestone:90").body).toBeNull();
    expect(byId(reminders, "milestone:100").body).toBe("下班时间到");
  });

  it("off 模式下全部静音，但条目一条不少", () => {
    const reminders = buildShiftReminders(
      simpleShift,
      withoutMicroBreaks({ mode: "off" })
    );
    const milestones = reminders.filter(
      (reminder) => reminder.kind === "milestone"
    );
    expect(milestones).toHaveLength(5);
    expect(milestones.every((reminder) => reminder.body === null)).toBe(true);
  });

  it("缺档位标题时退回通用标题，通用标题也缺时退回内置英文", () => {
    const partial = buildShiftReminders(
      simpleShift,
      withoutMicroBreaks({
        milestoneTitles: {
          milestone50: "",
          milestone75: "",
          milestone90: "",
          milestone95: "",
          milestone100: "",
        },
      })
    );
    expect(byId(partial, "milestone:90").title).toBe("下班提醒");

    const bare = buildShiftReminders(
      simpleShift,
      withoutMicroBreaks({
        fallbackTitle: "",
        milestoneTitles: {
          milestone50: "",
          milestone75: "",
          milestone90: "",
          milestone95: "",
          milestone100: "",
        },
        milestoneMessages: {
          milestone50: [],
          milestone75: [],
          milestone90: [],
          milestone95: [],
          milestone100: [],
        },
      })
    );
    expect(byId(bare, "milestone:90").title).toBe("Off work reminder");
    expect(byId(bare, "milestone:90").body).toBe("Almost there.");
  });

  it("同一班次重复生成时文案不变", () => {
    const pool = withoutMicroBreaks({
      milestoneMessages: {
        milestone50: ["a", "b", "c"],
        milestone75: ["a", "b", "c"],
        milestone90: ["a", "b", "c"],
        milestone95: ["a", "b", "c"],
        milestone100: ["a", "b", "c"],
      },
    });
    const first = buildShiftReminders(simpleShift, pool);
    const second = buildShiftReminders(simpleShift, pool);
    expect(byId(first, "milestone:90").body).toBe(
      byId(second, "milestone:90").body
    );
  });
});

describe("buildShiftReminders 午休边界", () => {
  it("在 segment 空隙两端各生成一条，并被空隙本身截断", () => {
    const reminders = buildShiftReminders(lunchShift, withoutMicroBreaks());
    const start = byId(reminders, "breakStart:3000");
    const end = byId(reminders, "breakEnd:4000");

    expect(start.atMs).toBe(3_000);
    expect(start.body).toBe("午休开始");
    // 两分钟的新鲜度窗口比这段午休还长，因此被午休结束时刻截断：
    // 午休都过完了就不该再提示它开始。
    expect(start.expiresAtMs).toBe(4_000);

    expect(end.atMs).toBe(4_000);
    // 同理被下一段的结束时刻截断：班次都下班了就不该再提示午休结束。
    // 这段班次很短，两分钟的窗口整个落在班次之外。
    expect(end.expiresAtMs).toBe(9_000);
  });

  it("班次足够长时用的才是两分钟的新鲜度窗口", () => {
    const minute = 60 * 1000;
    const shift: ShiftTimeline = {
      segments: [
        { startAtMs: 0, endAtMs: 60 * minute },
        { startAtMs: 120 * minute, endAtMs: 300 * minute },
      ],
      plannedEndAtMs: 300 * minute,
      overtimeEndAtMs: null,
    };
    const reminders = buildShiftReminders(shift, withoutMicroBreaks());
    expect(byId(reminders, `breakStart:${60 * minute}`).expiresAtMs).toBe(
      60 * minute + 2 * minute
    );
    expect(byId(reminders, `breakEnd:${120 * minute}`).expiresAtMs).toBe(
      120 * minute + 2 * minute
    );
  });

  it("开关关闭时静音但仍占位", () => {
    const reminders = buildShiftReminders(
      lunchShift,
      withoutMicroBreaks({ lunchStartEnabled: false })
    );
    expect(byId(reminders, "breakStart:3000").body).toBeNull();
    expect(byId(reminders, "breakEnd:4000").body).toBe("午休结束");
  });

  it("单段班次没有午休提醒", () => {
    const reminders = buildShiftReminders(simpleShift, withoutMicroBreaks());
    expect(
      reminders.some(
        (reminder) =>
          reminder.kind === "breakStart" || reminder.kind === "breakEnd"
      )
    ).toBe(false);
  });
});

describe("buildShiftReminders 健康提醒", () => {
  const minute = 60 * 1000;
  const longShift: ShiftTimeline = {
    segments: [
      { startAtMs: 0, endAtMs: 3 * minute },
      { startAtMs: 10 * minute, endAtMs: 13 * minute },
    ],
    plannedEndAtMs: 13 * minute,
    overtimeEndAtMs: null,
  };

  it("每个 segment 从零重新计时，午休不把未满的一轮带过去", () => {
    const reminders = buildShiftReminders(longShift, inputs).filter(
      (reminder) => reminder.kind === "microBreak"
    );
    expect(reminders.map((reminder) => reminder.atMs)).toEqual([
      1 * minute,
      2 * minute,
      11 * minute,
      12 * minute,
    ]);
  });

  it("文案里的 {{minutes}} 是本段内的连续工作分钟数", () => {
    const reminders = buildShiftReminders(longShift, inputs);
    expect(byId(reminders, `microBreak:${10 * minute}:1`).title).toBe(
      "健康提醒"
    );
    expect(byId(reminders, `microBreak:${10 * minute}:1`).body).toBe(
      "已经坐了 1 分钟了"
    );
  });

  it("恰好落在段末的那一条不生成", () => {
    // 3 分钟的段、1 分钟的间隔：第 3 分钟正是下班/午休时刻，
    // 此时提醒「该起来活动一下」已经没有意义。
    const reminders = buildShiftReminders(longShift, inputs);
    expect(
      reminders.some((reminder) => reminder.id === "microBreak:0:3")
    ).toBe(false);
  });

  it("间隔为 0 时不生成", () => {
    const reminders = buildShiftReminders(
      longShift,
      withoutMicroBreaks()
    ).filter((reminder) => reminder.kind === "microBreak");
    expect(reminders).toHaveLength(0);
  });

  it("条数有上限，极小的间隔不会撑爆列表", () => {
    const marathon: ShiftTimeline = {
      segments: [{ startAtMs: 0, endAtMs: 1_000 * minute }],
      plannedEndAtMs: 1_000 * minute,
      overtimeEndAtMs: null,
    };
    const reminders = buildShiftReminders(marathon, inputs).filter(
      (reminder) => reminder.kind === "microBreak"
    );
    expect(reminders).toHaveLength(240);
  });

  it("关闭开关时静音但仍占位", () => {
    const reminders = buildShiftReminders(longShift, {
      ...inputs,
      microBreakEnabled: false,
    }).filter((reminder) => reminder.kind === "microBreak");
    expect(reminders).toHaveLength(4);
    expect(reminders.every((reminder) => reminder.body === null)).toBe(true);
  });
});

describe("buildShiftReminders 边界输入", () => {
  it("班次无效或为空时返回空列表", () => {
    expect(buildShiftReminders(null, inputs)).toEqual([]);
    expect(
      buildShiftReminders(
        { segments: [], plannedEndAtMs: 0, overtimeEndAtMs: null },
        inputs
      )
    ).toEqual([]);
  });

  it("按触发时刻升序返回", () => {
    const reminders = buildShiftReminders(lunchShift, inputs);
    const times = reminders.map((reminder) => reminder.atMs);
    expect(times).toEqual([...times].sort((left, right) => left - right));
  });
});

describe("shiftRemindersRevision", () => {
  it("跟随班次结束时刻变化", () => {
    expect(shiftRemindersRevision(simpleShift)).toBe(
      `${REMINDER_MODEL_VERSION}:1000`
    );
    expect(shiftRemindersRevision(null)).toBe(
      `${REMINDER_MODEL_VERSION}:idle`
    );
  });

  it("改通知设置不会改修订号", () => {
    // 修订号变化会让消费方重建去重基线。中途开关一个提醒不该有这个副作用，
    // 否则「打开开关」会顺带把当天已发过的提醒重新算成未发。
    const before = shiftRemindersRevision(simpleShift);
    const after = shiftRemindersRevision(simpleShift);
    expect(before).toBe(after);
  });
});

describe("selectDueReminders", () => {
  const reminders = buildShiftReminders(simpleShift, withoutMicroBreaks());

  it("只取 (previous, now] 区间内跨过的条目", () => {
    expect(selectDueReminders(reminders, 0, 500).due.map((r) => r.id)).toEqual([
      "milestone:50",
    ]);
    // 同一时刻再问一次不会重复触发。
    expect(selectDueReminders(reminders, 500, 500).due).toEqual([]);
  });

  it("一拍跨过多档时只发最高的一条，其余全部记为已发", () => {
    const { crossed, due } = selectDueReminders(reminders, 400, 960);
    expect(due.map((reminder) => reminder.id)).toEqual(["milestone:95"]);
    expect(crossed.map((reminder) => reminder.id)).toEqual([
      "milestone:50",
      "milestone:75",
      "milestone:90",
      "milestone:95",
    ]);
  });

  it("里程碑没有有效期，长时间休眠后仍然补发最高的一条", () => {
    const { due } = selectDueReminders(reminders, 0, 999);
    expect(due.map((reminder) => reminder.id)).toEqual(["milestone:95"]);
  });

  it("静音的条目进 crossed 但不进 due", () => {
    const muted = buildShiftReminders(
      simpleShift,
      withoutMicroBreaks({ mode: "off" })
    );
    const { crossed, due } = selectDueReminders(muted, 0, 1_000);
    expect(crossed).toHaveLength(5);
    expect(due).toEqual([]);
  });

  it("过了有效期的午休提醒不发，但仍记为已发", () => {
    const lunch = buildShiftReminders(lunchShift, withoutMicroBreaks());
    // 设备从午休前一直睡到午休结束之后：跨过了「午休开始」，
    // 但那一刻早已过去，补一条已经没有语境。
    const { crossed, due } = selectDueReminders(lunch, 2_900, 4_500);
    expect(crossed.map((reminder) => reminder.id)).toContain("breakStart:3000");
    expect(due.map((reminder) => reminder.id)).not.toContain("breakStart:3000");
    // 同一拍里「午休结束」还在窗口内，应当照常发出。
    expect(due.map((reminder) => reminder.id)).toContain("breakEnd:4000");
  });

  it("跳拍过大时健康提醒不发：那段时间用户并没有在工作", () => {
    const minute = 60 * 1000;
    const shift: ShiftTimeline = {
      segments: [{ startAtMs: 0, endAtMs: 30 * minute }],
      plannedEndAtMs: 30 * minute,
      overtimeEndAtMs: null,
    };
    const all = buildShiftReminders(shift, inputs).filter(
      (reminder) => reminder.kind === "microBreak"
    );

    // 正常节拍：照常发。
    const normal = selectDueReminders(all, 5 * minute - 1_000, 5 * minute);
    expect(normal.due.map((reminder) => reminder.id)).toEqual([
      "microBreak:0:5",
    ]);

    // 休眠 11 分钟后醒来：跨过的几条都记为已发，但一条也不弹。
    const woke = selectDueReminders(all, 5 * minute, 16 * minute);
    expect(woke.crossed.length).toBeGreaterThan(1);
    expect(woke.due).toEqual([]);
  });

  it("系统时钟回拨时什么都不发", () => {
    const { crossed, due } = selectDueReminders(reminders, 900, 100);
    expect(crossed).toEqual([]);
    expect(due).toEqual([]);
  });
});
