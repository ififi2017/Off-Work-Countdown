# Plans

已完成或已归档的计划收在这里；仍在执行、且被代码注释当作决策依据引用的计划留在
`docs/`。

## 索引

| 编号 | 计划 | 起草 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| 001 | [统一并收敛全产品动效](001-motion-improvement.md) | 2026-08-24 | TODO | iOS 与 Web/Desktop 两条独立工作流，基准提交 `f10c7f9` |
| 002 | [工时留存、人生视图与专注](002-records-life-focus.md) | 2026-08-25 | DRAFT | 第一次引入持久化；基准提交 `feac4e9` |
| 003 | [桌面端实施（Tauri v2）](003-tauri-desktop.md) | 2026-08-08 | IN PROGRESS | 3.0.2 已发布；P2–P4 与安装说明待实机验收，P6 待办 |
| 004 | [班次模型重构与本地化补齐](004-shift-model-3.1.0.md) | 2026-08-12 | DONE | 3.1.0 已发布，当前 3.1.7 |
| 005 | [产品 3.0 升级](005-product-3.0.md) | 2026-08-08 | DONE | M1–M5 完成；M6 分发改由 MSIX 计划接管 |

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
