// 微软商店渠道下替换 @tauri-apps/plugin-updater 的空实现。
//
// 理由与 analytics-stub 相同：条件渲染只是让分支不执行，模块仍会被打进产物。
// 而商店版**不允许**存在自行下载安装的代码路径——MSIX 的安装目录只读，装不上；
// 审核和审计的人也不会去逐行确认它没被调用。
//
// 因此在 next.config.mjs 里用 resolve.alias 把它整体换掉，让 msstore 渠道的
// 产物里压根没有更新器代码。见 docs/PLAN-MSSTORE.md 决策 2。
//
// 抛错而不是静默返回：这条路径在商店版里被调用即是 bug，应当在开发期就炸出来，
// 而不是表现成一次"检查不出更新"。

const UNREACHABLE =
  "updater is unavailable in the Microsoft Store build; updates are handled by the Store";

export function check(): never {
  throw new Error(UNREACHABLE);
}
