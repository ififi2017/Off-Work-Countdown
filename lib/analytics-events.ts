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
  /** 倒计时自然走到下班时间。 */
  "countdown_complete",
  /** 用户真正执行了一次分享、复制或图片下载。 */
  "share_action",
  /** Web 首页展示了客户端下载邀请。 */
  "desktop_invite_view",
  /** 从邀请进入客户端下载页。 */
  "desktop_invite_open",
  /** 用户主动关闭客户端下载邀请。 */
  "desktop_invite_dismiss",
  /** 下载页的微软商店入口点击。与直链分开计数，用来看商店渠道的分流。 */
  "desktop_download_msstore",
  /** Mac App Store：推荐浮窗打开、以及从浮窗真正跳转商店，分开计数。 */
  "desktop_macappstore_dialog_open",
  "desktop_download_macappstore",
  /** 下载页的各平台安装包与 GitHub Releases 点击。 */
  "desktop_download_windows_intel",
  "desktop_download_windows_arm",
  "desktop_download_macos_apple",
  "desktop_download_macos_intel",
  "desktop_download_linux_intel",
  "desktop_download_github",
] as const;

export type TrackedEvent = (typeof trackedEvents)[number];

export function isTrackedEvent(value: string): value is TrackedEvent {
  return (trackedEvents as readonly string[]).includes(value);
}
