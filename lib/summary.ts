// 周期性汇总。**完全由配置推算，不依赖任何历史记录。**
//
// 这是刻意的选择：用户不会把页面挂满整个工作日，也不会每天都来。真去记录
// 「实际累计时长」，只能记到他碰巧打开的那几天、那几个小时，算出来的
// 「今年已赚」会比真实值低一个数量级——那不是诚实的数据，是个坏掉的指标。
// 按配置推算则不需要积累期，新用户第一次打开就能看到有意义的数字，
// 代价是必须如实标注「按当前设置推算」。

export interface PeriodSummary {
  /** 已过去的工作日数，当前班次按完成比例计入小数。 */
  days: number;
  hours: number;
  /** 未配置薪资时为 null。 */
  earnings: number | null;
}

/** 一周的起点固定为周一（ISO 8601），与界面上工作日选择器的排列一致。 */
export function startOfWeek(date: Date): Date {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  // getDay(): 0=周日。周日应回退 6 天而非 -1 天。
  const offset = (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - offset);
  return d;
}

export function startOfYear(date: Date): Date {
  return new Date(date.getFullYear(), 0, 1);
}

/**
 * 统计 [from, to) 区间内的工作日数量，均按当地日期推进。
 *
 * 用 setDate 而非「加 86400000 毫秒」推进：夏令时切换那两天分别是 23 和 25
 * 小时，按毫秒加会错过或重复一天。
 */
export function countWorkdays(from: Date, to: Date, workdays: number[]): number {
  if (workdays.length === 0) return 0;

  const cursor = new Date(from);
  cursor.setHours(0, 0, 0, 0);
  const end = new Date(to);
  end.setHours(0, 0, 0, 0);

  let count = 0;
  while (cursor < end) {
    if (workdays.includes(cursor.getDay())) count += 1;
    cursor.setDate(cursor.getDate() + 1);
  }
  return count;
}

/**
 * 汇总从 periodStart 到此刻的工作量。
 *
 * 当前班次单独计算：只有它的开班日是工作日、且落在当前周期时才计入，
 * 并按已完成比例折算，与界面上「今日已赚」的口径保持一致。
 */
export function summarize(params: {
  periodStart: Date;
  /** 汇总所处的当前日，只负责截断未来日期，不决定夜班归属。 */
  asOf: Date;
  workdays: number[];
  /** 当前班次按开始日期归属工作日；跨午夜后仍属于开始的那一天。 */
  currentShiftStart: Date;
  /** 用于判断该班次是否仍覆盖统计日；跨夜班次的结束日会晚于开始日。 */
  currentShiftEnd: Date;
  /** 当前设置下一个完整计划班次的有效工时，已经扣除午休。 */
  plannedDailyHours: number;
  /** 班次进度百分比 0–100，来自正在运行的倒计时。 */
  todayProgress: number;
  dailySalary: number | null;
  /** 当前班次实际有效工时；用于午休与加班，未提供时按计划有效时长。 */
  todayEffectiveHours?: number;
  /** 当前班次按原日薪线性外推的计薪比例；可因加班超过 1。 */
  todayPayRatio?: number;
}): PeriodSummary {
  const {
    periodStart,
    asOf,
    workdays,
    currentShiftStart,
    currentShiftEnd,
    plannedDailyHours,
    todayProgress,
    dailySalary,
    todayEffectiveHours,
    todayPayRatio,
  } = params;

  const shiftDay = new Date(currentShiftStart);
  shiftDay.setHours(0, 0, 0, 0);
  const shiftEndDay = new Date(currentShiftEnd);
  shiftEndDay.setHours(0, 0, 0, 0);
  const periodDay = new Date(periodStart);
  periodDay.setHours(0, 0, 0, 0);
  const asOfDay = new Date(asOf);
  asOfDay.setHours(0, 0, 0, 0);
  // 同日班次在当天结束后仍由进度折算，跨夜班次在结束日也继续归属于开班日；
  // 一旦统计日越过班次结束日，activeShift 就只是 UI 留下的旧快照，不能再
  // 截断后续工作日。
  const currentShiftCoversAsOfDay =
    shiftDay >= periodDay && shiftDay <= asOfDay && shiftEndDay >= asOfDay;
  const completed = countWorkdays(
    periodDay,
    currentShiftCoversAsOfDay ? shiftDay : asOfDay,
    workdays
  );
  const todayCounts =
    currentShiftCoversAsOfDay && workdays.includes(shiftDay.getDay());
  const todayFraction = todayCounts
    ? Math.min(100, Math.max(0, todayProgress)) / 100
    : 0;

  const days = completed + todayFraction;
  const hours =
    completed * plannedDailyHours +
    (todayCounts
      ? (todayEffectiveHours ?? plannedDailyHours) * todayFraction
      : 0);
  const earningsFraction = todayCounts
    ? Math.max(0, todayPayRatio ?? todayFraction)
    : 0;

  return {
    days,
    hours,
    earnings:
      dailySalary === null
        ? null
        : (completed + earningsFraction) * dailySalary,
  };
}
