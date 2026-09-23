# Android 移植进度

**这是任务状态的唯一记录。** 交接包 `tasks.json` 只定义依赖、范围和验收，不记录状态。

更新：2026-09-23。交接包 1.2。源 SHA `9252fdfdc66aab88b4acb7493684f11991fd773d`。

## 任务状态

状态：NOT_STARTED → IN_PROGRESS → IMPLEMENTED → VERIFIED；另有 WAITING_OWNER、BLOCKED、DEFERRED。

| ID | 状态 | 证据 / 备注 |
|---|---|---|
| T00 | IMPLEMENTED | `baseline.md`。未 reset 工作区。QA-001 分支创建 NOT_RUN。 |
| T01 | IMPLEMENTED | `source-inventory.md`、`feature-parity.md`、`conflicts.md`。源读自固定 SHA。未跑 iOS XCTest。 |
| T02 | IMPLEMENTED | `wire-contract.md`、`synthetic-archives/`。检查：`node scripts/android-synthetic-archives.mjs --check`。Kotlin 导入 NOT_RUN。 |
| T03 | IMPLEMENTED | `environment-lock.md`；`src-mobile/android`；`.github/workflows/android.yml`（CI 尚未在 GitHub 上运行）。domain 2 测试通过；Debug/R8 Release/AAB 成功；模拟器冷启动成功。 |
| T04–T05 | NOT_STARTED | — |
| T06 | IMPLEMENTED | `scripts/generate-android-rule-fixtures.mjs` → `src-mobile/android/core/domain/src/test/resources/shared-rule-fixtures.json`：5087 条 TS oracle 用例，与 iOS `ScheduleRuleFixtures` 数据逐字相同，另记 6 个输入文件哈希。`npm test` 内含 stale 检查（手改一条用例、给 `lib/countdown.ts` 加注释均使检查失败，已验证）；Kotlin `SharedRuleFixturesTest` 3 条通过。Swift 特有规则的 fixtures 属 T08。 |
| T07 | IMPLEMENTED | `core/domain/.../schedule`（`CivilZone`、`ScheduleRules`、模型）与 `salary/SalaryRules`。fixture 的 snapshots/widget/expansion/validateBreak/applyToday 共 2927 条全部精确通过；植入错误测试有效；算例测试 5 条。见 `rule-parity.md`。 |
| T08 | IMPLEMENTED | `ExtendedSchedule.kt`（解析器、计划、校验）、`HolidayCalendar.kt`、`CivilZone` 扩展路径。Swift 导出的 fixtures 共约 7200 条全部通过，4 项植入错误均被捕获。编辑器逻辑移到 T15/T16，`expandableHours` 叠加移到 T12。见 `rule-parity.md`。 |
| T09 | IMPLEMENTED | `summary/SummaryRules.kt`：五段 TS fixture 共 714 条全部通过；3 项植入错误均被捕获。`LifeViewCalculator` 移到 T12/T17。见 `rule-parity.md`。 |
| T10 | IMPLEMENTED | D-13：与 iOS 相同的单文件档案。`:core:domain` 的 `records/`（模型、`RecordJson` 编解码与合并、`FoundationCompat`）；`:core:data` 的 `RecordArchive`、`RecordStore`。Swift RecordJSON oracle 的 88 个用例全部通过（含 v1–v6、非法档案、逐实体拒绝、三种合并模式）；5 项植入错误均被捕获；文件系统测试 8 条（重启读回、写失败不提交、校验失败不落盘、损坏阻断与隔离、墓碑、并发串行）。 |
| T11 | IN_PROGRESS | 编解码、合并模式与冲突报告已随 T10 完成；待做：SAF 读写、25 MiB 上限、导入预检与报告 UI、`restoreErased` 的 UUID 重映射测试。 |
| T12 | IMPLEMENTED | `records/`：`DayRecordResolver`（三层链与来源标记）、`RecordHistory.expandableHours`（唯一的快照读取入口，含名册叠加与旧行边界）、`ScheduleHoursCodec`（与 Swift 字节一致，指纹相同；由 11 个 oracle 用例把关）、`DayOverrideProjection`、`RecordEdits`（盖戳 upsert、墓碑之上复活、首次写入播种、同日快照改写、日写入计划）、`DayEditDraft`。移植 iOS `DayRecordResolverTests` 17 条与 `DayOverrideProjectionTests` 的 9 条纯函数用例，另有 13 条编辑/历史测试；4 项植入错误均被捕获。`LifeViewCalculator` 移到 T17；依赖计时会话的 10 条投影用例移到 T16。 |
| T13 | DONE | **T13a**：`focus/FocusPlanner`（网格、可开始窗口、边界、结束原因、溢出）、`FocusSessionIdentity`（SHA-256 派生，与交接包两个向量一致）、`FocusEngine`（开始条件与互斥、计划块内开始、自然结束按计划终点结算、任务达预估才完成、自动休息与派生 id、跳过、收敛为一个进行中会话、冷启动恢复下一步）；13 条规划器用例与 18 条生命周期测试。**T13b**：`FocusCanvas`（画布模型、模板任务分组与整任务前缀、`FocusChain` 投影）与 `FocusPlanning`（分配/休息/清除、模板保存/编辑/应用/重排/默认/分离、收藏、任务编辑与缩放、清空当天、放置与再加一轮、由计划驱动的自动会话队列与恢复）；41 条测试对应 `FocusCanvasTests`、`FocusTaskEditingTests` 与 `FocusStoreTests` 的模板用例。Live Activity 接管休息移到 T14，时间线事件与实时链条的展示移到 T19。 |
| T14 | DONE | 领域：`schedule/ReminderRules`（`lib/reminders.ts` 的逐条移植，`ScheduleRules.reminders` 当前+下一班次，320 条共享 fixture 全部通过）、`reminders/CycleSummary`（周期末总结与申报加班段，后一天未解析不当作休息）、`focus/FocusReminders`（专注阶段两条提醒、计划接管健康提醒）、`reminders/ReminderPlanner`（当前班次仅在确在班时提醒、只取将来且有文案的、关键提醒优先 60 条上限、提前下班只留下一班次、稳定 ID 差量、重启不补发、健康提醒不用精确闹钟）。数据：`ReminderSync`（登记文件在调用系统前写入且不进备份；授权变化时全部重登；系统拒绝的下次重试；触发时只发登记中仍有效的一次）。应用：`Reminders`、`AndroidAlarms`（精确需用户授予 `SCHEDULE_EXACT_ALARM`，否则非精确并标记可能延迟；不声明 `USE_EXACT_ALARM`，无前台服务）、两个不导出的 receiver（触发；重启/更新/改时间/改时区/授予精确权限后恢复），回到前台时复查被撤销的精确授权。同结束点普通完成与周期总结只有一条（总结替换 100% 文案）。**未做**：设置页的权限行随 T15（文案走 T05）；由班次/专注状态调用 `Reminders.schedule` 随 T16；常驻通知随 T19；QA-083～086、089、094 需真机。 |
| T15–T20 | NOT_STARTED | — |
| T21 | DEFERRED | 服务端验证，首发后（D-08 修订） |
| T22 | DEFERRED | Drive 同步，首发后（D-02 修订） |
| T23–T26 | NOT_STARTED | — |
| T27 | DEFERRED | Wear，首发后（D-05） |

## 执行状态

| 项 | 状态 |
|---|---|
| Android 工程 | 最小工程（app、core:domain、core:designsystem） |
| 自动化应用测试 | NOT_RUN（140 条；首发 126 条） |
| 真机 / 模拟器 | 模拟器仅做 T03 启动探针；真机 NOT_RUN |
| Play Console | 未操作 |

## 下一任务

可并行，任选其一：

- **T04 · 稳定版 Material3 与 DoneAt 设计 token 探针**（依赖 T03）。
- **T05 · 翻译转换与质量检查**（依赖 T02+T03）。

规则核心与提醒（M2、T14）已完成。T15 依赖 T04+T05+T10，T16 依赖 T15，因此下一步是 T04 或 T05。

环境与命令见 `environment-lock.md`。候选默认（发布前冻结）：`applicationId=com.rainif.doneat`，minSdk 26，versionName 3.2.0，versionCode 1。

## 基线漂移记录

每个里程碑结束运行：

```text
git log --oneline 9252fdfdc66aab88b4acb7493684f11991fd773d..origin/main -- lib src-mobile/ios/App/App/Native/Models src-mobile/ios/Shared
```

| 日期 | 基线之后影响规则的提交 | 处理 |
|---|---|---|
| 2026-09-23 | 0 | 无需跟进 |

## 变更记录

- 2026-09-21：T00–T02 完成。
- 2026-09-23：T14 完成（提醒规则、周期总结、专注提醒与 AlarmManager 调度）。
- 2026-09-23：T13b 完成（专注计划、模板、放置与画布）。T13 完成。
- 2026-09-23：T13a 完成（专注规划器、派生身份与会话生命周期）。
- 2026-09-23：T12 完成（日记录解析、编辑命令、快照编码与 iOS 字节一致）。
- 2026-09-23：T10 完成（D-13 单文件档案与 RecordJSON 编解码）。
- 2026-09-23：T09 完成（汇总与收入）。M2 规则核心除提醒（T14）外完成。
- 2026-09-23：T08 完成（扩展排班，Swift 导出 fixtures）。
- 2026-09-23：T07 完成（固定班次核心，fixture 全通过）。
- 2026-09-23：T06 完成（共享规则 fixtures 与 stale 检查）。
- 2026-09-23：T03 完成（最小工程、CI、环境锁）。
- 2026-09-23：交接包 1.2（D-02/D-08 修订、新增 D-12），T21/T22 延后；进度只在本文件维护；本机 SDK 就绪。
