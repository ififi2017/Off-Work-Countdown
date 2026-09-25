import { getShiftLengthHours } from "@/lib/countdown";

// 工时计算器（仅 Web）。和倒计时是两件事：这里只回答「几点下班」和
// 「这段班算几个小时」，结果可以一键带进倒计时。
//
// 班次跨度一律取自 lib/countdown.ts 的 getShiftLengthHours，跨零点口径与倒计时
// 相同；本模块只在其上扣除不计薪的休息时间，或从上班时刻推算下班时刻。

/** 工时计算器的路径段：`/{lang}/work-hours-calculator`，19 种界面语言都有。 */
export const WORK_HOURS_CALCULATOR_SLUG = "work-hours-calculator";

export const MINUTES_PER_DAY = 24 * 60;

const CLOCK_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/;

/** "HH:MM" → 当天第几分钟；不合法返回 null。 */
export function parseClockTime(value: string): number | null {
  const match = CLOCK_PATTERN.exec(value);
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

/** 当天第几分钟 → "HH:MM"，超过 24 小时的部分按次日折回。 */
export function formatClockTime(minutes: number): string {
  const wrapped =
    ((Math.round(minutes) % MINUTES_PER_DAY) + MINUTES_PER_DAY) %
    MINUTES_PER_DAY;
  const h = Math.floor(wrapped / 60);
  const m = wrapped % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

export interface HoursWorked {
  /** 从上班到下班的时钟时长（分钟），跨零点按次日计。 */
  spanMinutes: number;
  /** 扣掉的不计薪休息（分钟）。 */
  breakMinutes: number;
  /** 实际计薪时长（分钟）。 */
  paidMinutes: number;
  /** 下班在次日。 */
  overnight: boolean;
}

/**
 * 起止时刻 + 不计薪休息 → 每天实际工作多久。休息不短于整段班时返回 null，
 * 由界面提示用户调整。起止相同按 24 小时计，与 getShiftLengthHours 一致。
 */
export function calculateHoursWorked(
  start: string,
  end: string,
  breakMinutes: number
): HoursWorked | null {
  const startMinutes = parseClockTime(start);
  const endMinutes = parseClockTime(end);
  if (startMinutes === null || endMinutes === null) return null;
  if (!Number.isFinite(breakMinutes) || breakMinutes < 0) return null;

  const spanMinutes = Math.round(getShiftLengthHours(start, end) * 60);
  if (breakMinutes >= spanMinutes) return null;

  return {
    spanMinutes,
    breakMinutes,
    paidMinutes: spanMinutes - breakMinutes,
    overnight: endMinutes <= startMinutes,
  };
}

export interface FinishTime {
  /** 下班时刻 "HH:MM"。 */
  end: string;
  /** 下班落在上班之后的第几天（0 = 当天，1 = 次日）。 */
  dayOffset: number;
  /** 从上班到下班的时钟时长（分钟）= 工作 + 休息。 */
  spanMinutes: number;
}

/**
 * 上班时刻 + 要工作多久 + 不计薪休息 → 几点下班。整段不能达到 24 小时：
 * 那样下班时刻会和上班时刻重合，倒计时也无法表示。
 */
export function calculateFinishTime(
  start: string,
  workMinutes: number,
  breakMinutes: number
): FinishTime | null {
  const startMinutes = parseClockTime(start);
  if (startMinutes === null) return null;
  if (!Number.isFinite(workMinutes) || workMinutes <= 0) return null;
  if (!Number.isFinite(breakMinutes) || breakMinutes < 0) return null;

  const spanMinutes = Math.round(workMinutes + breakMinutes);
  if (spanMinutes >= MINUTES_PER_DAY) return null;

  const endMinutes = startMinutes + spanMinutes;
  return {
    end: formatClockTime(endMinutes),
    dayOffset: Math.floor(endMinutes / MINUTES_PER_DAY),
    spanMinutes,
  };
}

/** 分钟拆成小时和分钟，供各语言的时长模板使用。 */
export function splitMinutes(total: number): { hours: number; minutes: number } {
  const rounded = Math.max(0, Math.round(total));
  return { hours: Math.floor(rounded / 60), minutes: rounded % 60 };
}
