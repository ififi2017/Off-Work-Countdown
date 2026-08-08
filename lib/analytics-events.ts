// 埋点事件白名单。端点是公开的，只接受这里列出的名字——既防止任意字符串写入
// 存储，也把键的基数锁死在一个很小的集合里。
//
// 刻意只做聚合计数：不记录用户标识、不写 cookie、不存 IP 或 UA。这样 FAQ 里
// 「只收集匿名统计，不含个人信息」那句话依然成立，无需改口。

export const trackedEvents = [
  /** 通过分享链接落地（带 from=share）。 */
  "share_land",
  /** 分享落地后点了「换成我的时间」——分享转化的关键信号。 */
  "share_convert",
  /** 打开分享面板。 */
  "share_open",
  /** 从预设页的 CTA 进入并开始倒计时。 */
  "preset_start",
  /** 在表单里自己点了开始倒计时。 */
  "countdown_start",
] as const;

export type TrackedEvent = (typeof trackedEvents)[number];

export function isTrackedEvent(value: string): value is TrackedEvent {
  return (trackedEvents as readonly string[]).includes(value);
}
