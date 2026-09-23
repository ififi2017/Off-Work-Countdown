# 源冲突与未代签行为（T01）

优先级：安全/平台强制 > 负责人对 Android 的明确决定 > **固定 SHA 的代码与测试** > 后续计划 > 旧 README / 交接 PRD 摘要。

编号 C-01～C-08 来自交接包 05。下面是本轮对照 `9252fdf` 后的增量。

## C-09 · PRD 写三个主 Tab，源码是四个

- 交接 01 §5：「维持三个主入口：计时、记录、设置。专注……不擅自增加第四个主 Tab。」
- 源 `SceneState.swift`：`AppTab` = `timer | focus | records | settings`。`TabletDesignView` 用 `.sidebarAdaptable` 四入口。
- **裁决**：Android 按源做四个主导航，除非负责人另批。PRD 这句话视为过期摘要，不是删 Focus Tab 的授权。
- 影响：FR-19、T15。
- 1.2（2026-09-23）：交接包 01_PRD 已按四入口更正。

## C-10 · 分享链接用偏好起止，不是当日实际班次

- 源 `ShiftSession.shareURL()`：`s` 来自 `preferences.startMinutes/endMinutes`。
- 测试强制例如 `s=0900-1800`，即使当天加班或提前下班。
- **裁决**：照搬；不要“改进”成实际/加班边界。

## C-11 · Widget 默认深链

- 源桌面小组件 / Live Activity 回退：`offworkcountdown://timer`。
- Focus 动作：`offworkcountdown://focus?action=&start=`。
- 此 SHA **没有** Universal Links / `associated-domains`。
- 有一处审计误记 `offworkcountdown://open`，**以源为准，作废**。

## C-12 · `SettingsDesignView` 在此 SHA 未被引用

- 设置根实际是 `TabletSettingsView` + `SettingsSectionCard`。
- 盘点设置行以 live 路径为准，不把未挂上的设计文件当缺失功能。

## C-13 · schemaVersion 2 从未被任何构建写出

- `RecordJSON.schemaVersion` 从 1 跳到 3。解码接受 2，测试假设形状=最后一版 v1。
- **裁决**：Android 同样接受 2，按 v1 缺省；不得声称存在真实 v2 样本。

## 必须原样保留的源行为（未代签不得改）

1. 免费窗口 = 今天 + 往前 6 个**记录时区自然日**（`freeLookbackDays = 6`），不是 168 小时。
2. `collectsObservations`：从未购买（snapshot 无 subscription/lifetime）继续采集；曾有权益现失效则停止新增。Ask to Buy 期间仍采集。
3. `billingRetry` **不授权**。
4. 已开启的同步不因 Plus 过期自动关闭；仅「开启」门控。
5. `cycleEndSummaryNotificationEnabled` 可保持 true，正文仍要 Plus。
6. StoreKit `.unverified` 保留 lifetime 缓存；只有 confirmed empty 可清授权。
7. 锁定日/年的 UiState 不得带被遮挡的真实工时或人数。
8. 提前下班视觉态为 `.completed`，可压过休息日。
9. 加班下限 = `max(plannedEnd, now)`，无最小时长。
10. 计时危险操作 5 秒二次确认，绑定 `TimerContext`。
11. Focus 改设置只影响下一会话。
12. 周期总结可含工时/加班时长，**不得含薪资**。
13. Watch App / 复杂功能在源中免费；Android 不得改成 Plus。Wear 首发不做。
14. `RecordCommand` 是队列原语；语义命令在 `RecordsActions`。

## 平台替代（不是删功能）

| iOS | Android 替代 | 批准 |
|---|---|---|
| CloudKit | 首发：Auto Backup/设备转移（业务库纳入）；后续：Drive appDataFolder | D-02 于 2026-09-23 修订 |
| StoreKit | 首发：纯客户端 Play Billing；后续：验证服务（D-01/D-08） | D-08 于 2026-09-23 修订；价格未配 |
| Live Activity / 灵动岛 | 普通通知 + 可选系统计时 | 允许差异；不承诺一比一 |
| `offworkcountdown://` | 同语义 intent / App Links（域名另配） | 链接预览不得自动覆盖 |
| 评价预询问 | Play 禁止卡片前询问（C-07） | 已记录 |
| Apple Watch 设置行 | 首发可无此行；改走关于/后续 Wear | D-05 |
