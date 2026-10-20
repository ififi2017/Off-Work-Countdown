import {
  calculateTimelineProgress,
  getShiftDurationMs,
  getShiftEndAtMs,
  getShiftRemainingMs,
  getShiftStartAtMs,
  isValidShiftTimeline,
  type ShiftTimeline,
} from "./countdown";
import type { ReminderNotificationMode, ShiftReminder } from "./reminders";

export const WIDGET_SNAPSHOT_SCHEMA_VERSION = 1 as const;

/**
 * working 段内再切分出多少条 entry。
 *
 * 每个 segment 只发一条 entry 的话，`progressAtDate` 在整段班次里是个常数——
 * 上午 9:00–12:00 的进度环会一动不动地停三个小时，而中间的 `.timer` 还在走，
 * 看起来就是坏了。WidgetKit 限的是 **reload 次数**，不是一条 timeline 里的
 * entry 数量，所以段内多铺 entry 是免费的。
 *
 * 取 100 是因为界面上进度只显示到整数百分比（见 Swift 侧 roundedProgress），
 * 每 1% 一条正好覆盖所有肉眼可见的变化，再密就是白写。
 */
export const WORKING_PROGRESS_STEPS = 100;

/**
 * 段内细分的时间下限。班次很短时 duration/100 会小到几秒，而 WidgetKit 实际
 * 也不会比分钟级更勤地换 entry，铺再密只是把 JSON 撑大。
 */
const MIN_WORKING_ENTRY_STEP_MS = 60 * 1000;

/**
 * working 段的细分步长：按有效工时均分，使进度大约每 1% 前进一次。
 *
 * 同一 segment 内 elapsed 与墙上时间是 1:1 的（见 countdown.ts 的
 * getShiftElapsedMs），因此每条子 entry 的下班时刻都是同一个绝对点——
 * 切换子 entry 不会让圆形复杂功能上的钟点跳一下。倒计时用 remaining
 * 推出来的锚点，不能把下班时刻当成「剩余工时贴到墙上」。
 */
function workingEntryStepMs(shift: ShiftTimeline): number {
  const durationMs = getShiftDurationMs(shift);
  return Math.max(
    MIN_WORKING_ENTRY_STEP_MS,
    Math.ceil(durationMs / WORKING_PROGRESS_STEPS)
  );
}

export type WidgetTimelinePhase =
  | "idle"
  | "before"
  | "working"
  | "break"
  | "done";

export type WidgetCountdownKind =
  | "none"
  | "shiftStarts"
  | "workRemaining"
  | "breakEnds"
  | "complete";

export interface WidgetTimelineEntry {
  /** WidgetKit TimelineEntry 的生效时间，使用 Unix epoch milliseconds。 */
  dateMs: number;
  /** 半开区间的结束；extension 不得在此时间之后继续使用本 entry。 */
  validUntilMs: number;
  phase: WidgetTimelinePhase;
  labelKey: string;
  countdownKind: WidgetCountdownKind;
  /** `dateMs` 时刻需要展示的数值；working 时是有效工时而非墙上时间。 */
  countdownValueAtDateMs: number;
  /** 供 SwiftUI 动态日期文本使用。working 是实际下班时刻；倒计时用
   *  `dateMs + remainingEffectiveMsAtDateMs`，不要把这个字段当剩余工时锚点。 */
  countdownTargetAtMs: number | null;
  remainingEffectiveMsAtDateMs: number;
  progressAtDate: number;
  /** 当前 entry 之后已由前端确定的下一处边界。 */
  nextBoundaryAtMs: number | null;
}

export interface WidgetSnapshotV1 {
  schemaVersion: typeof WIDGET_SNAPSHOT_SCHEMA_VERSION;
  generatedAtMs: number;
  expiresAtMs: number;
  locale: string;
  /** 仅用于诊断和未来展示；extension 不得从 segments 推导排班规则。 */
  shift: ShiftTimeline | null;
  entries: WidgetTimelineEntry[];
  /** 「接下来」列表；没有可显示的事项时省略，与 Swift 编码一致。 */
  upcoming?: WidgetUpcomingItem[];
}

/**
 * 「倒计时与接下来」小组件的一行。字段与 Swift 的 `WidgetUpcomingItem` 一一对应；
 * extension 只按 `dateMs` 过滤已过去的行并排版，不推导任何时刻。
 */
export interface WidgetUpcomingItem {
  /** 跨次生成稳定，用于去重。 */
  id: string;
  /** `shiftStart` / `lunchStart` / `lunchEnd` / `health` / `milestone` / `shiftEnd`，决定图标。 */
  kind: string;
  title: string;
  detail: string;
  dateMs: number;
}

/** 由界面按当前语言排好的文案；小组件只显示，不翻译。 */
export interface WidgetUpcomingLabels {
  shiftStart: string;
  shiftEnd: string;
  overtime: string;
  /** 午休，或扩展排班里的「中途休息」。 */
  breakTitle: string;
  breakStarts: string;
  breakBackAt: string;
  microBreak: string;
  /** 已代入间隔分钟数，例如「60 分钟」。 */
  microBreakDetail: string;
  milestone: string;
}

export interface BuildWidgetUpcomingOptions {
  shift: ShiftTimeline | null;
  nextShift: ShiftTimeline | null;
  /** `buildShiftReminders` 为当前班次算出的提醒（lib/reminders.ts）。 */
  reminders: ShiftReminder[];
  notificationMode: ReminderNotificationMode;
  /** 健康提醒开关。关闭时 reminders 里仍有无标题的静默条目，不能据此列行。 */
  microBreakEnabled: boolean;
  labels: WidgetUpcomingLabels;
  nowMs: number;
  expiresAtMs: number;
}

/**
 * 「接下来」：当前班次剩下的边界与提醒，加上下一班的边界。
 *
 * 与 iOS 的 `WidgetSnapshotPublisher.upcomingItems` 同一套取舍：
 * - 上下班与午休边界来自已解析的班次；
 * - 健康提醒只列最近的一次，带间隔，而不是每小时一行；
 * - 进度提醒仅在「按进度提醒」时列出，跳过没有标题的静默档位，以及与下班同刻的 100%；
 * - 上下班行不写「今天的班次」：快照会活过写入当天。
 * 提醒时刻全部取自 `reminders`，这里不重新推算。
 */
export function buildWidgetUpcoming({
  shift,
  nextShift,
  reminders,
  notificationMode,
  microBreakEnabled,
  labels,
  nowMs,
  expiresAtMs,
}: BuildWidgetUpcomingOptions): WidgetUpcomingItem[] {
  const items: WidgetUpcomingItem[] = [];
  const seen = new Set<string>();
  const add = (item: WidgetUpcomingItem) => {
    if (!(item.dateMs > nowMs && item.dateMs < expiresAtMs)) return;
    if (seen.has(item.id)) return;
    seen.add(item.id);
    items.push({ ...item, dateMs: Math.round(item.dateMs) });
  };

  const boundaries = (timeline: ShiftTimeline) => {
    const startAtMs = getShiftStartAtMs(timeline);
    const endAtMs = getShiftEndAtMs(timeline);
    const during = (atMs: number) => atMs > nowMs && atMs <= endAtMs;
    add({ id: `shift-start-${startAtMs}`, kind: "shiftStart", title: labels.shiftStart, detail: "", dateMs: startAtMs });
    timeline.segments.slice(0, -1).forEach((segment, index) => {
      const next = timeline.segments[index + 1];
      if (next.startAtMs <= segment.endAtMs) return;
      if (during(segment.endAtMs)) {
        add({ id: `lunch-start-${segment.endAtMs}`, kind: "lunchStart", title: labels.breakTitle, detail: labels.breakStarts, dateMs: segment.endAtMs });
      }
      if (during(next.startAtMs)) {
        add({ id: `lunch-end-${next.startAtMs}`, kind: "lunchEnd", title: labels.breakTitle, detail: labels.breakBackAt, dateMs: next.startAtMs });
      }
    });
    return { endAtMs, during };
  };

  if (shift && isValidShiftTimeline(shift)) {
    const { endAtMs, during } = boundaries(shift);
    const microBreak = microBreakEnabled
      ? reminders
          .filter((reminder) => reminder.kind === "microBreak" && during(reminder.atMs))
          .sort((a, b) => a.atMs - b.atMs)[0]
      : undefined;
    if (microBreak) {
      add({ id: microBreak.id, kind: "health", title: labels.microBreak, detail: labels.microBreakDetail, dateMs: microBreak.atMs });
    }
    if (notificationMode === "milestones") {
      for (const reminder of reminders) {
        if (reminder.kind !== "milestone" || reminder.title === null) continue;
        // 100% 与下班同刻，下班那一行已经说了。
        if (/(^|:)milestone:100$/.test(reminder.id) || !during(reminder.atMs)) continue;
        add({ id: reminder.id, kind: "milestone", title: labels.milestone, detail: reminder.title, dateMs: reminder.atMs });
      }
    }
    add({
      id: `shift-end-${endAtMs}`,
      kind: "shiftEnd",
      title: labels.shiftEnd,
      detail: shift.overtimeEndAtMs === null ? "" : labels.overtime,
      dateMs: endAtMs,
    });
  }

  if (nextShift && isValidShiftTimeline(nextShift)) {
    const { endAtMs } = boundaries(nextShift);
    add({
      id: `shift-end-${endAtMs}`,
      kind: "shiftEnd",
      title: labels.shiftEnd,
      detail: nextShift.overtimeEndAtMs === null ? "" : labels.overtime,
      dateMs: endAtMs,
    });
  }

  // 同一时刻：上班在前，下班在后，其余居中。
  const order = (kind: string) => (kind === "shiftStart" ? 0 : kind === "shiftEnd" ? 2 : 1);
  return items.sort((a, b) => a.dateMs - b.dateMs || order(a.kind) - order(b.kind));
}

export interface CreateWidgetSnapshotOptions {
  running: boolean;
  shift: ShiftTimeline | null;
  /**
   * 下一次班次。班次结束后用来倒数到下次上班，和主界面「距下次上班 10:10:52」
   * 那一行是同一件事——没有它，小组件下班后只能干等到期然后翻成空态。
   */
  nextShift: ShiftTimeline | null;
  locale: string;
  generatedAtMs: number;
  /** `buildWidgetUpcoming` 的结果；空列表不写进快照。 */
  upcoming?: WidgetUpcomingItem[];
  expiresAtMs: number;
}

const LABEL_KEYS: Record<WidgetTimelinePhase, string> = {
  idle: "countdownNotStarted",
  before: "nextShiftLabelShort",
  working: "widgetWorking",
  break: "lunchInProgress",
  done: "offWorkToday",
};

function createEntry(
  shift: ShiftTimeline,
  phase: Exclude<WidgetTimelinePhase, "idle">,
  dateMs: number,
  validUntilMs: number,
  nextBoundaryAtMs: number | null
): WidgetTimelineEntry {
  const remainingEffectiveMsAtDateMs = getShiftRemainingMs(shift, dateMs);
  const progressAtDate = calculateTimelineProgress(shift, dateMs);
  let countdownKind: WidgetCountdownKind;
  let countdownValueAtDateMs: number;

  switch (phase) {
    case "before":
      countdownKind = "shiftStarts";
      countdownValueAtDateMs = Math.max(0, getShiftStartAtMs(shift) - dateMs);
      break;
    case "working":
      countdownKind = "workRemaining";
      countdownValueAtDateMs = remainingEffectiveMsAtDateMs;
      break;
    case "break":
      countdownKind = "breakEnds";
      countdownValueAtDateMs = Math.max(
        0,
        (nextBoundaryAtMs ?? dateMs) - dateMs
      );
      break;
    case "done":
      // 已下班但知道下次上班时间时，倒数到下次上班——主界面在「今日已下班」
      // 底下显示的就是这个。相位仍然是 done：标签和配色要保持「已下班」，
      // 变的只是那个大数字在数什么。
      if (nextBoundaryAtMs !== null && nextBoundaryAtMs > dateMs) {
        countdownKind = "shiftStarts";
        countdownValueAtDateMs = nextBoundaryAtMs - dateMs;
      } else {
        countdownKind = "complete";
        countdownValueAtDateMs = 0;
      }
      break;
  }

  return {
    dateMs,
    validUntilMs,
    phase,
    labelKey: LABEL_KEYS[phase],
    countdownKind,
    countdownValueAtDateMs,
    countdownTargetAtMs:
      phase === "working"
        ? getShiftEndAtMs(shift)
        : countdownValueAtDateMs > 0
          ? dateMs + countdownValueAtDateMs
          : null,
    remainingEffectiveMsAtDateMs,
    progressAtDate,
    nextBoundaryAtMs,
  };
}

function createIdleEntry(
  generatedAtMs: number,
  expiresAtMs: number
): WidgetTimelineEntry {
  return {
    dateMs: generatedAtMs,
    validUntilMs: expiresAtMs,
    phase: "idle",
    labelKey: LABEL_KEYS.idle,
    countdownKind: "none",
    countdownValueAtDateMs: 0,
    countdownTargetAtMs: null,
    remainingEffectiveMsAtDateMs: 0,
    progressAtDate: 0,
    nextBoundaryAtMs: null,
  };
}

/**
 * 把已经解析完成的绝对班次投影成 WidgetKit 可直接消费的时间线。
 *
 * 这里可以读取 `segments`，因为它仍在前端业务层；Swift extension 只按 entry 的
 * 半开时间区间选值，不再判断午休、跨日、加班或工作日。
 */
export function createWidgetSnapshot({
  running,
  shift,
  nextShift,
  locale,
  generatedAtMs,
  expiresAtMs,
  upcoming = [],
}: CreateWidgetSnapshotOptions): WidgetSnapshotV1 {
  if (!Number.isFinite(generatedAtMs) || !Number.isFinite(expiresAtMs)) {
    throw new Error("widget snapshot timestamps must be finite");
  }
  if (expiresAtMs <= generatedAtMs) {
    throw new Error("widget snapshot must expire after it is generated");
  }

  if (!running || !shift || !isValidShiftTimeline(shift)) {
    return {
      schemaVersion: WIDGET_SNAPSHOT_SCHEMA_VERSION,
      generatedAtMs,
      expiresAtMs,
      locale,
      shift: null,
      entries: [createIdleEntry(generatedAtMs, expiresAtMs)],
    };
  }

  const entries: WidgetTimelineEntry[] = [];
  const shiftStartAtMs = getShiftStartAtMs(shift);
  const shiftEndAtMs = getShiftEndAtMs(shift);
  const stepMs = workingEntryStepMs(shift);
  // 只在下次上班确实还没到时才用它。过期的 nextShift（例如休眠后恢复的旧快照）
  // 会让 done 相位倒数一个已经过去的时刻，界面上就是一个不动的 0。
  const nextShiftStartAtMs =
    nextShift && isValidShiftTimeline(nextShift)
      ? getShiftStartAtMs(nextShift)
      : null;
  let cursor = generatedAtMs;

  if (cursor < shiftStartAtMs) {
    entries.push(
      createEntry(
        shift,
        "before",
        cursor,
        Math.min(shiftStartAtMs, expiresAtMs),
        shiftStartAtMs
      )
    );
    cursor = shiftStartAtMs;
  }

  for (const segment of shift.segments) {
    if (cursor >= expiresAtMs) break;
    if (segment.endAtMs <= cursor) continue;

    if (cursor < segment.startAtMs) {
      const gapStartAtMs = cursor;
      entries.push(
        createEntry(
          shift,
          gapStartAtMs < shiftStartAtMs ? "before" : "break",
          gapStartAtMs,
          Math.min(segment.startAtMs, expiresAtMs),
          segment.startAtMs
        )
      );
      cursor = segment.startAtMs;
    }

    if (cursor < segment.endAtMs && cursor < expiresAtMs) {
      const entryStartAtMs = Math.max(cursor, segment.startAtMs);
      const entryEndAtMs = Math.min(segment.endAtMs, expiresAtMs);
      // 段内按 stepMs 细分，让进度环和百分比在班次进行中持续刷新。
      // nextBoundaryAtMs 仍然指向 segment 的真实结束时刻——那是界面上「几点」
      // 那一行要显示的东西，不能跟着子 entry 走。
      for (
        let stepStartAtMs = entryStartAtMs;
        stepStartAtMs < entryEndAtMs;
        stepStartAtMs += stepMs
      ) {
        entries.push(
          createEntry(
            shift,
            "working",
            stepStartAtMs,
            Math.min(stepStartAtMs + stepMs, entryEndAtMs),
            segment.endAtMs
          )
        );
      }
      cursor = segment.endAtMs;
    }
  }

  if (cursor < expiresAtMs) {
    const doneAtMs = Math.max(cursor, shiftEndAtMs, generatedAtMs);
    if (doneAtMs < expiresAtMs) {
      entries.push(
        createEntry(shift, "done", doneAtMs, expiresAtMs, nextShiftStartAtMs)
      );
    }
  }

  // 生成时刻已晚于班次结束，或者有效期短到没有覆盖任何边界。
  if (entries.length === 0) {
    entries.push(
      createEntry(shift, "done", generatedAtMs, expiresAtMs, nextShiftStartAtMs)
    );
  }

  return {
    schemaVersion: WIDGET_SNAPSHOT_SCHEMA_VERSION,
    generatedAtMs,
    expiresAtMs,
    locale,
    shift: {
      segments: shift.segments.map((segment) => ({ ...segment })),
      plannedEndAtMs: shift.plannedEndAtMs,
      overtimeEndAtMs: shift.overtimeEndAtMs,
    },
    entries,
    ...(upcoming.length ? { upcoming } : {}),
  };
}

/** Swift extension 对应方法的 TypeScript 参考实现。 */
export function getWidgetTimelineEntry(
  snapshot: WidgetSnapshotV1,
  nowMs: number
): WidgetTimelineEntry | null {
  if (
    snapshot.schemaVersion !== WIDGET_SNAPSHOT_SCHEMA_VERSION ||
    nowMs < snapshot.generatedAtMs ||
    nowMs >= snapshot.expiresAtMs
  ) {
    return null;
  }
  return (
    snapshot.entries.find(
      (entry) => nowMs >= entry.dateMs && nowMs < entry.validUntilMs
    ) ?? null
  );
}

export function serializeWidgetSnapshot(snapshot: WidgetSnapshotV1): string {
  return `${JSON.stringify(snapshot, null, 2)}\n`;
}
