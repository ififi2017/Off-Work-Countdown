# 功能对等表（T01）

源：`9252fdf`。Android 列定义目标；实际实现状态与验收证据统一记录在 [progress.md](progress.md)，本表不维护另一套进度。

## FR 总表

| ID | 源锚点 | Android 目标 | 子项 / 差异 |
|---|---|---|---|
| FR-01 | `FirstRunRecovery*`、`RecoveryStore`、Onboarding 页流 | 新建草稿 / JSON 恢复 / 系统备份恢复后直接进主界面（Drive 恢复为后续） | 无 Google 账号可用性假设 |
| FR-02 | `ScheduleRules`、`SyncedPreferences` 经典字段 | 上下班、工作日、午休、跨夜、时区 | 今天 / 从下一次 保存选项 |
| FR-03 | `ExtendedSchedule*`、`HolidayCalendar` | 班型、周期、手排、清空、冻结、节假日包 | 节假日不按定位自动启用 |
| FR-04 | `TimerVisualPhase`、`ShiftSessionStore`、`heroRemainingMs` | 八态 + 提前上下班/加班/撤销 | 5s 确认；加班 min=`max(plannedEnd,now)` |
| FR-05 | 薪资字段、`hideEarnings`、`BiometricGate` | 月/日薪、年终奖参数、隐藏+身份确认 | 计时 live vs 记录固定月薪两口径 |
| FR-06 | `RecordsQueries`、`RecordsAccess` | 日/周/月/年；免费窗；来源标记 | 锁定态零泄漏 |
| FR-07 | `RecordsActions`、`DayRecordResolver` | 确认/未工作/自定义/请假补班/清除 | 同事务；保留休息洞 |
| FR-08 | `LifeViewCalculator`、`LifeProfile` | 阶段、经历、空档、一次性未来比例 | 默认退休 60 非法定 |
| FR-09 | `FocusModels`/`Store`/`Planner` | 画布、模板、番茄、恢复、确定性 ID | SHA-256 UUID，见 02 §7.1 |
| FR-10 | `ReminderRules`、`NotificationService` | 绝对触发 + 权限降级 | 无全天 FGS |
| FR-11 | Live Activity / 持续通知 | 普通通知 + 可选 chronometer | 不承诺灵动岛 |
| FR-12 | `WidgetSnapshot*`、Glance | 小/中/大；无薪资 DTO | 不每秒刷新 |
| FR-13 | `shareURL`、`ShareCard` | Sharesheet；链接只含起止 | 用偏好起止（C-10） |
| FR-14 | `RecordJSON` schema 6 | 导入 1–6，导出 6 | 见 wire-contract |
| FR-15 | `RecordsCloudSync` | 首发：Auto Backup/设备转移换机恢复；后续：Drive 批次+墓碑（D-02 修订） | 无 iCloud 互通（D-03）；设置页首发无同步开关 |
| FR-16 | `PlusEntitlement`、`PaywallView` | 月/年/终身；首发客户端查询+签名校验，服务端后续（D-08 修订） | 价格未配；billingRetry 不授权 |
| FR-17 | 设置分组、About、评价 | 平台入口替换（Play 订阅；Drive 为后续） | 无评价预询问 |
| FR-18 | xcstrings / 19 locales | 原生 strings + 检查脚本 | T05 |
| FR-19 | 四 Tab、横屏 overlay、平板分栏 | NavigationSuite；同一 ViewModel | **按源四 Tab**（C-09） |
| FR-20 | 签名、Data safety、轨道 | AAB + 申报 | 账户 UNKNOWN |
| FR-21 | Watch* | 不做 | DEFERRED |

## 免费 / Plus（源行为）

| 行为 | 从未购买 | 有效 Plus/终身 | 失效后 |
|---|---|---|---|
| 基础计时/排班/收入 | 可用 | 可用 | 可用 |
| 新工作观测 | 采集 | 采集 | **停止** |
| 近 7 自然日记录 | 窗内可看 | 全看 | 数据保留，窗外锁定 |
| 图表/人生/记录编辑/Focus | 门禁 | 可用 | 门禁 |
| 开启同步（后续阶段）/ 周期总结开关 | 门禁 | 可开 | 已开同步不自动关 |
| 恢复备份 | 不要求先买 | 可用 | 恢复 ≠ 付费编辑 |
| 导出/删除自己的数据 | 可用 | 可用 | 可用 |
| 小组件基础投影 | 可用 | 可用 | 无薪资 |

## 设置与 FR 子项（源有、PRD 未单列）

| 子项 | 源 | Android |
|---|---|---|
| FR-04-a | 5 秒二次确认 | 必须 |
| FR-04-b | 休息日强制开始 / 取消手动 | 必须 |
| FR-10-a | 周期总结替换 100% milestone，不双响 | 必须 |
| FR-11-a | Live Activity 开关与提前分钟（本机 UD） | 改为通知渠道说明，不假装灵动岛 |
| FR-12-a | Focus 计划行仅 Plus 投影到小组件 | 必须 |
| FR-16-a | Ask to Buy 24h；pending 不授权 | Play pending 用 Play 生命周期，不抄 24h |
| FR-16-b | 年订试用资格来自商店，不硬编码天数 | 必须 |
| FR-17-a | iPhone 上 Apple Watch 说明行 | 首发可省略（D-05），保留关于 |
| FR-17-b | 计时工具栏快切主题 / 隐藏收入 | 必须，眼睛表示点击后动作 |
| FR-19-a | 第四主 Tab = Focus | 必须（C-09） |

## 测试映射（文件 → FR）

| 测试文件 | FR |
|---|---|
| FirstRunRecoveryTests | 01, 15 |
| ExtendedSchedule*（5） | 02, 03 |
| ScheduleRuleFixtureTests + generated | 02–05, 10, 12 |
| ShiftSession/ShiftAction/SceneTimer* | 04 |
| OffWorkStoreTests | 04–06, 10–13 |
| DayRecordResolver / DayOverrideProjection | 06, 07 |
| Records*（约 14） | 06–08, 14, 15 |
| PlusEntitlement / OnboardingPlusPages | 16 |
| Focus*（8） | 09 |
| Life*（4） | 08 |
| ShareCardRenderTests | 13 |
| AppReviewAndCycleSummaryTests | 10, 17 |
| LiveActivityWindowTests | 11 |
| WidgetFocusProjectionTests | 12, 09 |
| Watch*（6） | 21 延后 |
| CloudSync / RecordsSyncAdapter | 15 |
| SyncedPreferences / Preferences* | 05, 17 |
| RecordJSON / RecordSchemaCompatibility | 14 |
| NativeLocalizerPlural / AppText | 18 |
| PhoneLandscapePresentation | 19 |
| Launch/RecordsPerformance / ServiceConcurrency | 20 |

完整 XCTest 未在本机运行（NOT_RUN）。

## 工资隔离清单

禁止出现：小组件 DTO、通知正文/publicVersion、普通分享图与 URL、日志、分析。  
允许：用户确认后的备份/导出（可含薪资与人生；可排除人生）。
