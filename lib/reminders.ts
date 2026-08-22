// 班次提醒的唯一实现。给定一个班次时间轴和一组通知偏好，算出这次班次里所有
// 提醒的**绝对触发时刻**与最终文案。
//
// 为什么要有这个文件：3.1 之前，里程碑跨越、午休边界、健康提醒这三套判定都写在
// `src-tauri/src/lib.rs` 的每秒轮询里。那等于把班次派生规则复制进了 Rust——
// AGENTS.md 写明 Rust "只能比较和求和前端准备好的绝对时间戳"，而按
// `(now - segmentStart) / interval` 分桶显然已经越过了那条线。
//
// 换成绝对时刻之后有两个直接好处：
//   1. 桌面端 Rust 退化成「到点了没」的比较，规则重新只剩一份，且能进 vitest；
//   2. 移动端壳可以把这份列表**一次性预约**给系统（iOS UNUserNotificationCenter /
//      Android AlarmManager）。手机上进程随时会被杀，"每秒轮询到点即发"那套
//      在移动端根本不成立。
//
// 输出刻意是纯数据：消费方只需要比较时间、判断有效期，不需要理解班次概念。

import {
  getShiftDurationMs,
  getShiftEndAtMs,
  isValidShiftTimeline,
  type ShiftTimeline,
} from "./countdown";

/**
 * 提醒模型版本。
 *
 * 消费方（Rust 托盘计时器、将来的移动端壳）用它判断去重标记还能不能复用：
 * 版本不一致就重建基线，而不是拿旧语义去比对新列表。语义变化必须递增。
 */
export const REMINDER_MODEL_VERSION = 1;

/**
 * 午休边界提醒的有效窗口。错过这么久之后这条提示已经失去语境——设备睡到
 * 午休结束后才醒，再弹一条「午休开始了」只会让人困惑。
 */
const BREAK_FRESHNESS_MS = 2 * 60 * 1000;

/**
 * 健康提醒允许的最大跳拍间隔。与 `expiresAtMs` 不同，这个判据看的是
 * **消费方上一拍到现在的间隔**，而不是距计划时刻多久。
 *
 * 二者的区别在休眠场景下才显出来：设备从 09:50 睡到 10:01，一条 10:00 的
 * 健康提醒距计划时刻只过了 1 分钟，但用户这段时间根本没在工作，"该起来活动
 * 一下了"是错的。所以这里必须看跳拍间隔。
 */
const MICRO_BREAK_MAX_TICK_GAP_MS = 2 * 60 * 1000;

/**
 * 单个 segment 内生成健康提醒的条数上限。
 *
 * 间隔由用户设定，理论上可以小到 1 分钟；一段 12 小时的连续工作段就会铺出
 * 720 条，写进 Store 是白白撑大 JSON，在移动端更会直接顶爆系统的待发通知配额。
 * 240 条足够覆盖任何合理的班次长度与间隔组合。
 */
const MAX_MICRO_BREAKS_PER_SEGMENT = 240;

export const REMINDER_MILESTONES = [50, 75, 90, 95, 100] as const;
export type ReminderMilestone = (typeof REMINDER_MILESTONES)[number];

export type ReminderNotificationMode = "off" | "simple" | "milestones";

export type ShiftReminderKind =
  | "milestone"
  | "breakStart"
  | "breakEnd"
  | "microBreak";

/** 里程碑通知的标题，按档位分开。由调用方按当前语言排好版推进来。 */
export interface ReminderMilestoneTitles {
  milestone50: string;
  milestone75: string;
  milestone90: string;
  milestone95: string;
  milestone100: string;
}

/** 里程碑通知的文案池，同一档位内按班次稳定地轮换。 */
export interface ReminderMilestoneMessages {
  milestone50: string[];
  milestone75: string[];
  milestone90: string[];
  milestone95: string[];
  milestone100: string[];
}

export interface ShiftReminder {
  /** 跨进程稳定的去重键。同一份列表里唯一，重新生成时保持不变。 */
  id: string;
  kind: ShiftReminderKind;
  /** 绝对触发时刻。 */
  atMs: number;
  /**
   * 绝对失效时刻，有效区间是半开的 `[atMs, expiresAtMs)`；`null` 表示永不失效。
   *
   * 里程碑没有失效时刻：睡了一整个下午醒来，"还剩 5%" 依然是当下正确的信息。
   * 午休边界则相反，见 `BREAK_FRESHNESS_MS`。
   */
  expiresAtMs: number | null;
  /** 消费方上一拍到现在的最大允许间隔；`null` 表示不检查。 */
  maxTickGapMs: number | null;
  /**
   * 折叠分组。一拍里跨过同组的多条时只发**最后一条**，其余仅记为已发。
   *
   * 休眠一次跨过 50%、75%、90% 三档，连弹三条通知是噪音；用户只想知道
   * 「现在到哪儿了」。
   */
  collapseGroup: string | null;
  /** `null` 表示这条只推进去重标记、不发通知（对应开关关闭）。 */
  title: string | null;
  body: string | null;
}

export interface ShiftReminderInputs {
  mode: ReminderNotificationMode;
  /** 通用标题；档位标题缺失时的兜底，午休与健康提醒也用它。 */
  fallbackTitle: string;
  milestoneTitles: ReminderMilestoneTitles;
  milestoneMessages: ReminderMilestoneMessages;
  lunchStartEnabled: boolean;
  lunchStartBody: string;
  lunchEndEnabled: boolean;
  lunchEndBody: string;
  microBreakEnabled: boolean;
  microBreakIntervalMinutes: number;
  /** 轮换用的健康提醒文案；`{{minutes}}` 会被替换成已连续工作的分钟数。 */
  microBreakMessages: string[];
}

/** 通用标题的最终兜底。Store 里没有任何标题时也不能弹一条空标题的通知。 */
const DEFAULT_TITLE = "Off work reminder";

/** 文案池为空时的内置英文兜底，逐条与升级前的 Rust 实现保持一致。 */
const DEFAULT_MILESTONE_BODIES: Record<ReminderMilestone, string> = {
  50: "Halfway there.",
  75: "The hardest part is behind you.",
  90: "Almost there.",
  95: "Just a little longer.",
  100: "Off work time!",
};

const MILESTONE_KEYS = {
  50: "milestone50",
  75: "milestone75",
  90: "milestone90",
  95: "milestone95",
  100: "milestone100",
} as const;

/**
 * 把「已进行的有效工时」换算成墙上时钟的绝对时刻。
 *
 * 有效工时不含 segment 之间的空隙，所以不能直接用 `start + elapsed`：一段
 * 9:00-12:00 / 13:00-18:00 的班次里，第 4 小时有效工时落在 13:00 而不是 13:00
 * 之前的任何时刻。逐段扣减才能落到正确的那一段上。
 */
function absoluteAtElapsedMs(shift: ShiftTimeline, elapsedMs: number): number {
  let remaining = elapsedMs;
  for (const segment of shift.segments) {
    const duration = segment.endAtMs - segment.startAtMs;
    // `<=` 而不是 `<`：恰好落在段末的里程碑应当在该段结束那一刻触发，
    // 而不是推迟到下一段开始。
    if (remaining <= duration) return segment.startAtMs + remaining;
    remaining -= duration;
  }
  return shift.segments[shift.segments.length - 1].endAtMs;
}

function milestoneTitle(
  inputs: ShiftReminderInputs,
  milestone: ReminderMilestone
): string {
  const specific = inputs.milestoneTitles?.[MILESTONE_KEYS[milestone]];
  if (specific) return specific;
  return inputs.fallbackTitle || DEFAULT_TITLE;
}

/**
 * 从档位文案池里挑一条。
 *
 * 用 `endAtMs + percent` 当种子而不是随机数：同一次班次的同一档位每次算出来
 * 都是同一条。否则 Store 每写一次、消费方每重算一次，待发通知的正文就会变，
 * 移动端上表现为「预约好的提醒到点弹出时换了句话」。
 */
function milestoneBody(
  inputs: ShiftReminderInputs,
  milestone: ReminderMilestone,
  endAtMs: number
): string {
  const pool = inputs.milestoneMessages?.[MILESTONE_KEYS[milestone]];
  if (!pool || pool.length === 0) return DEFAULT_MILESTONE_BODIES[milestone];
  const seed = Math.abs(endAtMs) + milestone;
  return pool[seed % pool.length];
}

function microBreakBody(
  inputs: ShiftReminderInputs,
  bucket: number
): string | null {
  const pool = inputs.microBreakMessages;
  if (!pool || pool.length === 0) return null;
  const template = pool[bucket % pool.length];
  if (!template) return null;
  return template.replace(
    "{{minutes}}",
    String(bucket * inputs.microBreakIntervalMinutes)
  );
}

/**
 * 这份提醒列表的修订号。
 *
 * 消费方据此判断能否复用已有的去重标记：修订号变了说明换了一个班次，
 * 旧的「已发」记录必须作废，并以当下为基线，不补发此前越过的提醒。
 *
 * 只取班次结束时刻，不含通知偏好——中途改设置不该重置去重基线。改了之后
 * 已经过去的提醒本来就不会再触发（消费方按跨越判定），未来的那些则会带着
 * 新文案照常触发。
 */
export function shiftRemindersRevision(shift: ShiftTimeline | null): string {
  if (!shift || !isValidShiftTimeline(shift)) {
    return `${REMINDER_MODEL_VERSION}:idle`;
  }
  return `${REMINDER_MODEL_VERSION}:${getShiftEndAtMs(shift)}`;
}

/**
 * 算出一次班次里的全部提醒，按触发时刻升序。
 *
 * 开关关闭的提醒**仍然会出现在列表里**，只是 `title`/`body` 为 `null`。这是
 * 刻意的：消费方照样把它记为已发，于是班次进行到一半时才打开开关，不会立刻
 * 补弹一串早就越过的历史提醒。
 */
export function buildShiftReminders(
  shift: ShiftTimeline | null,
  inputs: ShiftReminderInputs
): ShiftReminder[] {
  if (!shift || !isValidShiftTimeline(shift)) return [];
  const durationMs = getShiftDurationMs(shift);
  if (durationMs <= 0) return [];

  const endAtMs = getShiftEndAtMs(shift);
  const reminders: ShiftReminder[] = [];

  for (const milestone of REMINDER_MILESTONES) {
    // 与升级前的 Rust 判定同口径：progress 取 floor 后与档位比较，等价于
    // 有效工时越过 `duration * percent / 100` 的那一刻。
    const thresholdMs = Math.ceil((durationMs * milestone) / 100);
    const audible =
      inputs.mode === "milestones" ||
      (inputs.mode === "simple" && milestone === 100);
    reminders.push({
      id: `milestone:${milestone}`,
      kind: "milestone",
      atMs: absoluteAtElapsedMs(shift, thresholdMs),
      expiresAtMs: null,
      maxTickGapMs: null,
      collapseGroup: "milestone",
      title: audible ? milestoneTitle(inputs, milestone) : null,
      body: audible ? milestoneBody(inputs, milestone, endAtMs) : null,
    });
  }

  const breakTitle = inputs.fallbackTitle || DEFAULT_TITLE;
  for (let index = 0; index < shift.segments.length - 1; index += 1) {
    const breakStartAtMs = shift.segments[index].endAtMs;
    const breakEndAtMs = shift.segments[index + 1].startAtMs;
    if (breakEndAtMs <= breakStartAtMs) continue;

    const startBody = inputs.lunchStartEnabled ? inputs.lunchStartBody : "";
    reminders.push({
      id: `breakStart:${breakStartAtMs}`,
      kind: "breakStart",
      atMs: breakStartAtMs,
      // 午休已经结束就不必再提示它开始了，因此还要被午休结束时刻截断。
      expiresAtMs: Math.min(breakStartAtMs + BREAK_FRESHNESS_MS, breakEndAtMs),
      maxTickGapMs: null,
      collapseGroup: "break",
      title: startBody ? breakTitle : null,
      body: startBody || null,
    });

    const endBody = inputs.lunchEndEnabled ? inputs.lunchEndBody : "";
    reminders.push({
      id: `breakEnd:${breakEndAtMs}`,
      kind: "breakEnd",
      atMs: breakEndAtMs,
      expiresAtMs: Math.min(
        breakEndAtMs + BREAK_FRESHNESS_MS,
        shift.segments[index + 1].endAtMs
      ),
      maxTickGapMs: null,
      collapseGroup: "break",
      title: endBody ? breakTitle : null,
      body: endBody || null,
    });
  }

  const intervalMs = Math.max(0, inputs.microBreakIntervalMinutes) * 60 * 1000;
  if (intervalMs > 0) {
    for (const segment of shift.segments) {
      // 每个 segment 从零重新计时：午休把班次切开，午休前没满的一轮不该
      // 被带到午休之后续上。
      for (
        let bucket = 1;
        bucket <= MAX_MICRO_BREAKS_PER_SEGMENT;
        bucket += 1
      ) {
        const atMs = segment.startAtMs + bucket * intervalMs;
        if (atMs >= segment.endAtMs) break;
        const body = inputs.microBreakEnabled
          ? microBreakBody(inputs, bucket)
          : null;
        reminders.push({
          id: `microBreak:${segment.startAtMs}:${bucket}`,
          kind: "microBreak",
          atMs,
          expiresAtMs: null,
          maxTickGapMs: MICRO_BREAK_MAX_TICK_GAP_MS,
          collapseGroup: `microBreak:${segment.startAtMs}`,
          title: body ? breakTitle : null,
          body,
        });
      }
    }
  }

  reminders.sort((left, right) => left.atMs - right.atMs);
  return reminders;
}

/**
 * 挑出 `(previousMs, nowMs]` 区间内应当发出的提醒。
 *
 * 桌面端 Rust 与移动端壳的判定必须一致，所以判据写在这里、用同一套测试锁住：
 * 消费方只要按 `atMs` 排程，再用这个函数复核，就不会两端不同。
 *
 * 返回的是**要发出的**那些；调用方仍需把 `crossed` 里的全部条目记为已发，
 * 否则被折叠或被有效期挡掉的那些下一拍会重新算进来。
 */
export function selectDueReminders(
  reminders: ShiftReminder[],
  previousMs: number,
  nowMs: number
): { crossed: ShiftReminder[]; due: ShiftReminder[] } {
  if (nowMs <= previousMs) return { crossed: [], due: [] };

  // 显式排序而不是依赖入参顺序：折叠规则是「同组留最晚的一条」，
  // 一旦调用方传进来的列表没排过序，留下的就是任意一条。
  const crossed = reminders
    .filter((reminder) => reminder.atMs > previousMs && reminder.atMs <= nowMs)
    .sort((left, right) => left.atMs - right.atMs);

  const audible = crossed.filter((reminder) => {
    if (!reminder.title || !reminder.body) return false;
    if (reminder.expiresAtMs !== null && nowMs >= reminder.expiresAtMs) {
      return false;
    }
    if (
      reminder.maxTickGapMs !== null &&
      nowMs - previousMs > reminder.maxTickGapMs
    ) {
      return false;
    }
    return true;
  });

  // 折叠：同组只留触发时刻最晚的一条。`crossed` 已按 atMs 升序，
  // 因此后写入的天然覆盖先写入的。
  const lastPerGroup = new Map<string, ShiftReminder>();
  const due: ShiftReminder[] = [];
  for (const reminder of audible) {
    if (reminder.collapseGroup === null) {
      due.push(reminder);
      continue;
    }
    lastPerGroup.set(reminder.collapseGroup, reminder);
  }
  due.push(...lastPerGroup.values());
  due.sort((left, right) => left.atMs - right.atMs);

  return { crossed, due };
}
