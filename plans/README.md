# Plans

带编号的产品计划收在这里，既包含归档记录，也包含仍在推进的路线图；需要长期按固定路径
被代码与架构说明引用的跨版本技术计划留在 `docs/`。

## 索引

| 编号 | 计划 | 起草 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| 001 | [统一并收敛全产品动效](001-motion-improvement.md) | 2026-08-24 | IN PROGRESS | iOS 动效地基随 007 落地；原计划中的逐秒数字策略需复议；Web/Desktop 尚未开始 |
| 002 | [工作占比、人生视图与专注](002-records-life-focus.md) | 2026-08-25 | IN PROGRESS | P0A 在 [PR #94](https://github.com/ififi2017/Off-Work-Countdown/pull/94)；P1 / P0B / P2 与 [006](006-free-trial-subscription.md) 同在 [PR #96](https://github.com/ififi2017/Off-Work-Countdown/pull/96) 等 CR。实现已交，真机同步与 TestFlight 未过。免费 Tab 只列实际上下班 |
| 003 | [桌面端实施（Tauri v2）](003-tauri-desktop.md) | 2026-08-08 | IN PROGRESS | 已连续发布至 3.1.8（2026-08-31）；Windows 人工验收、真实升级回环与 P6 包管理器分发仍待办 |
| 004 | [班次模型重构与本地化补齐](004-shift-model-3.1.0.md) | 2026-08-12 | DONE | 3.1.0 已发布；桌面端最新发布 3.1.8，仓库开发版本 3.1.9 |
| 005 | [产品 3.0 升级](005-product-3.0.md) | 2026-08-08 | DONE | M1–M5 完成；M6 分发改由 MSIX 计划接管 |
| 006 | [免费下载、试用与订阅](006-free-trial-subscription.md) | 2026-08-26 | IN PROGRESS | ASC 上月 / 年 / 终身已 Ready to Submit；TestFlight 沙盒只验过双设备权益同步一条。发版前要做逐行 CR 与完整验收矩阵；商店隐私页仍待 |
| 007 | [iOS 订阅前稳定版](007-ios-stable-before-subscription.md) | 2026-08-27 | IN PROGRESS | 3.1.8 素材与真机 Live Activity 已齐，待选 build 人工送审 |
| 008 | [DoneAt 品牌换装与 iOS 外表面](008-brand-doneat.md) | 2026-08-27 | IN PROGRESS | 品牌母版和 iOS 外表面已合入；真机 Live Activity 已看过；Web favicon 与着色图标仍待 |
| 009 | [DoneAt 全平台品牌与双域分工](009-doneat-platform-brand-domain.md) | 2026-08-28 | IN PROGRESS | 官网 2026-08-30 已验收；产品仓 Web P3 已落地；Desktop 升级回环与商店邮箱仍待 |
| 010 | [记录 UI 迭代](010-records-ui-iteration.md) | 2026-08-30 | IN PROGRESS | 单画布与记录 IA 已落地；数据 P1、沉浸画布和真机验收由 011 收口 |
| 011 | [iOS 记录与番茄钟发布阻断收口](011-ios-records-focus-release-remediation.md) | 2026-09-01 | READY FOR DEVICE VALIDATION | TestFlight 双真机已验证记录与番茄钟的正常传播；冲突回写、双 open session、删除 fence、Production schema、通知 / Live Activity 仍未验。番茄钟排布另需重做 |
| 012 | [iOS 评价引导、周期总结通知与 iPad 入口修复](012-ios-retention-and-cycle-notifications.md) | 2026-09-01 | IMPLEMENTED | 模拟器与自动化验收已通过；订阅成功触感、系统评价弹窗和真实通知投递仍待真机 / TestFlight 终验 |
| 013 | [记录日画布、视觉语法与单一结论](013-records-day-canvas-and-visual-language.md) | 2026-09-01 | IN PROGRESS | Phase 0–4 已随 [PR #111](https://github.com/ififi2017/Off-Work-Countdown/pull/111) / [#112](https://github.com/ififi2017/Off-Work-Countdown/pull/112) 合入 `main`（3.1.9）；自动化门禁与模拟器截图已过。仍缺无障碍分支、60fps 测量、流程录屏、人生文案复审与真机终验 |
| 014 | [番茄钟画布重排：现在 / 今天 / 常用](014-ios-focus-canvas-redesign.md) | 2026-09-04 | DRAFT | 只出方案未动代码；现状地图、三尺度原则与九项结构性问题已成文，时间带 / 放进下一个空格 / 格子优先三个分叉已拍板。实现前须确认 011 的番茄钟行为验收已签收 |

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
