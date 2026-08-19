import {
  calculateTimelineProgress,
  getShiftDurationMs,
  getShiftEndAtMs,
  getShiftRemainingMs,
  getShiftStartAtMs,
  isValidShiftTimeline,
  type ShiftTimeline,
} from "./countdown";

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
 * getShiftElapsedMs），因此每条子 entry 算出的 `countdownTargetAtMs` 都是同一个
 * 绝对时刻——切换子 entry 不会让倒计时跳数。
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
  /** 供 SwiftUI 动态日期文本使用；working 时可能是合成锚点，不是实际下班时间。 */
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
      countdownValueAtDateMs > 0
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
