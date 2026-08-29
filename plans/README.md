# Plans

带编号的产品计划收在这里，既包含归档记录，也包含仍在推进的路线图；需要长期按固定路径
被代码与架构说明引用的跨版本技术计划留在 `docs/`。

## 索引

| 编号 | 计划 | 起草 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| 001 | [统一并收敛全产品动效](001-motion-improvement.md) | 2026-08-24 | IN PROGRESS | iOS 动效地基随 007 落地；原计划中的逐秒数字策略需复议；Web/Desktop 尚未开始 |
| 002 | [工作占比、人生视图与专注](002-records-life-focus.md) | 2026-08-25 | DRAFT | 第一次引入持久化；排班是底图；007 今日标记已冻结，P0A 可另开分支 |
| 003 | [桌面端实施（Tauri v2）](003-tauri-desktop.md) | 2026-08-08 | IN PROGRESS | 已连续发布至 3.1.7；Windows 人工验收、真实升级回环与 P6 包管理器分发仍待办 |
| 004 | [班次模型重构与本地化补齐](004-shift-model-3.1.0.md) | 2026-08-12 | DONE | 3.1.0 已发布，当前 3.1.7 |
| 005 | [产品 3.0 升级](005-product-3.0.md) | 2026-08-08 | DONE | M1–M5 完成；M6 分发改由 MSIX 计划接管 |
| 006 | [免费下载、试用与订阅](006-free-trial-subscription.md) | 2026-08-26 | DRAFT | 从 002 拆出；通用购买把 iOS 与 Mac App Store 绑在一个价格上；等待 007 完成送审闭环 |
| 007 | [iOS 订阅前稳定版](007-ios-stable-before-subscription.md) | 2026-08-27 | IN PROGRESS | PR #82 已合入且主要真机界面已验收；Live Activity、截图与 3.1.7 TestFlight 待办 |
| 008 | [DoneAt 品牌换装与 iOS 外表面](008-brand-doneat.md) | 2026-08-27 | IN PROGRESS | 品牌母版和 iOS/PWA/Tauri 图标已合入；Web favicon、iOS 着色图标与 Live Activity 实拍待办 |
| 009 | [DoneAt 全平台品牌与双域分工](009-doneat-platform-brand-domain.md) | 2026-08-28 | TODO | Grill 已锁；官网仓 `doneat.app`（Astro）；`off.rainif.com` 留 Web App；拆 302 须与桌面 DoneAt 显示名同一窗口 |

## 仍在 `docs/` 的活计划

这两份还在执行，并且被 `next.config.mjs`、`config/site.ts` 和 `AGENTS.md` 当作
决策依据按路径引用，所以没有搬过来：

- [`docs/PLAN-MOBILE.md`](../docs/PLAN-MOBILE.md) — Apple 移动端与 Watch
- [`docs/PLAN-MSSTORE.md`](../docs/PLAN-MSSTORE.md) — 微软商店上架（MSIX）

## 状态定义

- `DRAFT`：已成文，尚未开始执行，可能还有未决问题。
- `TODO`：方案已定，尚未开始。
- `IN PROGRESS`：正在实现或等待设备验证。
- `BLOCKED`：实现完成但缺少明确的外部验证条件。
- `DONE`：机械检查和 feel check 都已通过。
- `WON'T DO`：真机/真实桌面确认没有收益，明确保留现状。

## 执行约定

1. iOS 必须由用户在 iPhone 和 iPad 真机确认；模拟器只负责机械构建验证。
2. Web/Desktop 必须检查浏览器 Reduced Motion、Windows Mini Timer 和真实 macOS
   菜单栏面板。
3. 不要修改计划明确列出的业务规则、导航手势和原生进度条保护边界。
4. 归档的计划保留成文时的原样，包括当时的链接——它们是记录，不是活文档。
