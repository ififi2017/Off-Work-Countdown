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
| T04 | DONE | `:core:designsystem`：`DoneAtColors`（浅/深两套完整 M3 配色，暖中性表面；浅色主色 `#C2410C`，品牌亮橙仅作装饰）、`DoneAtStateColors`、`DoneAtShapes`（14/22 与 iOS 一致；主操作按下时胶囊收成 12 dp）、`DoneAtMotion`（与 `OWCMotion` 同值，减少动态效果时退化）、`DoneAtType.countdown`（64 sp 等宽数字）、`DoneAtCountdown`（逐位数字翻页，对应 `.numericText(countsDown:)`）、`DoneAtProgressMeter`（浮动百分比气泡，几何与 `OWCProgressMeter` 相同）、`DoneAtTheme`（主题模式、可选动态配色）。对比度与气泡几何 8 条单测；Debug 专用 gallery。模拟器（API 36）检查浅色、深色、200% 字体、移除动画、阿拉伯语 RTL、数字翻页录屏。Release 依赖全为稳定版（Material3 1.4.0）。见 `design-tokens-adr.md`。 |
| T05 | DONE | `scripts/generate-android-strings.mjs`（`npm run generate:android-strings` / `check:android-strings`）把 `Localizable.xcstrings` 的 832 个 key 与 `app/i18n/android-strings.json` 的 Android 专有文案转成 19 个语言目录的 `strings_catalog.xml`、`xml/locales_config.xml`（清单已引用）、可逆的 `app/i18n/key-map.json` 与带命名参数的 `l10n/Strings.kt`。`{{name}}` 按英文顺序转为 `%N$s`；消息池转为 string-array 并保留 `{{name}}` 供共享规则替换；复数按各语言 CLDR 类别生成；Java/Kotlin 关键字 key 加下划线。生成时检查：19 语言齐全、各语言占位符与英文一致、Android 专有 key 不与目录重名、资源名合法且不碰撞、XML 非法字符。12 条 vitest 覆盖中文三变体、印地/马拉地语、阿语复数、德语长句占位符重排、转义与各类拒绝；`npm test` 与 Android CI 在资源过期时失败。Android 专有文案目前 2 条（精确提醒授权），19 语言齐全。aapt2 编译与 lint 通过，无新增告警（`localeConfig` 在 API 33 以下被忽略属预期）。 |
| T06 | IMPLEMENTED | `scripts/generate-android-rule-fixtures.mjs` → `src-mobile/android/core/domain/src/test/resources/shared-rule-fixtures.json`：5087 条 TS oracle 用例，与 iOS `ScheduleRuleFixtures` 数据逐字相同，另记 6 个输入文件哈希。`npm test` 内含 stale 检查（手改一条用例、给 `lib/countdown.ts` 加注释均使检查失败，已验证）；Kotlin `SharedRuleFixturesTest` 3 条通过。Swift 特有规则的 fixtures 属 T08。 |
| T07 | IMPLEMENTED | `core/domain/.../schedule`（`CivilZone`、`ScheduleRules`、模型）与 `salary/SalaryRules`。fixture 的 snapshots/widget/expansion/validateBreak/applyToday 共 2927 条全部精确通过；植入错误测试有效；算例测试 5 条。见 `rule-parity.md`。 |
| T08 | IMPLEMENTED | `ExtendedSchedule.kt`（解析器、计划、校验）、`HolidayCalendar.kt`、`CivilZone` 扩展路径。Swift 导出的 fixtures 共约 7200 条全部通过，4 项植入错误均被捕获。编辑器逻辑移到 T15/T16，`expandableHours` 叠加移到 T12。见 `rule-parity.md`。 |
| T09 | IMPLEMENTED | `summary/SummaryRules.kt`：五段 TS fixture 共 714 条全部通过；3 项植入错误均被捕获。`LifeViewCalculator` 移到 T12/T17。见 `rule-parity.md`。 |
| T10 | IMPLEMENTED | D-13：与 iOS 相同的单文件档案。`:core:domain` 的 `records/`（模型、`RecordJson` 编解码与合并、`FoundationCompat`）；`:core:data` 的 `RecordArchive`、`RecordStore`。Swift RecordJSON oracle 的 88 个用例全部通过（含 v1–v6、非法档案、逐实体拒绝、三种合并模式）；5 项植入错误均被捕获；文件系统测试 8 条（重启读回、写失败不提交、校验失败不落盘、损坏阻断与隔离、墓碑、并发串行）。 |
| T11 | IN_PROGRESS | 编解码、合并模式与冲突报告已随 T10 完成；待做：SAF 读写、25 MiB 上限、导入预检与报告 UI、`restoreErased` 的 UUID 重映射测试。 |
| T12 | IMPLEMENTED | `records/`：`DayRecordResolver`（三层链与来源标记）、`RecordHistory.expandableHours`（唯一的快照读取入口，含名册叠加与旧行边界）、`ScheduleHoursCodec`（与 Swift 字节一致，指纹相同；由 11 个 oracle 用例把关）、`DayOverrideProjection`、`RecordEdits`（盖戳 upsert、墓碑之上复活、首次写入播种、同日快照改写、日写入计划）、`DayEditDraft`。移植 iOS `DayRecordResolverTests` 17 条与 `DayOverrideProjectionTests` 的 9 条纯函数用例，另有 13 条编辑/历史测试；4 项植入错误均被捕获。`LifeViewCalculator` 移到 T17；依赖计时会话的 10 条投影用例移到 T16。 |
| T13 | DONE | **T13a**：`focus/FocusPlanner`（网格、可开始窗口、边界、结束原因、溢出）、`FocusSessionIdentity`（SHA-256 派生，与交接包两个向量一致）、`FocusEngine`（开始条件与互斥、计划块内开始、自然结束按计划终点结算、任务达预估才完成、自动休息与派生 id、跳过、收敛为一个进行中会话、冷启动恢复下一步）；13 条规划器用例与 18 条生命周期测试。**T13b**：`FocusCanvas`（画布模型、模板任务分组与整任务前缀、`FocusChain` 投影）与 `FocusPlanning`（分配/休息/清除、模板保存/编辑/应用/重排/默认/分离、收藏、任务编辑与缩放、清空当天、放置与再加一轮、由计划驱动的自动会话队列与恢复）；41 条测试对应 `FocusCanvasTests`、`FocusTaskEditingTests` 与 `FocusStoreTests` 的模板用例。Live Activity 接管休息移到 T14，时间线事件与实时链条的展示移到 T19。 |
| T14 | DONE | 领域：`schedule/ReminderRules`（`lib/reminders.ts` 的逐条移植，`ScheduleRules.reminders` 当前+下一班次，320 条共享 fixture 全部通过）、`reminders/CycleSummary`（周期末总结与申报加班段，后一天未解析不当作休息）、`focus/FocusReminders`（专注阶段两条提醒、计划接管健康提醒）、`reminders/ReminderPlanner`（当前班次仅在确在班时提醒、只取将来且有文案的、关键提醒优先 60 条上限、提前下班只留下一班次、稳定 ID 差量、重启不补发、健康提醒不用精确闹钟）。数据：`ReminderSync`（登记文件在调用系统前写入且不进备份；授权变化时全部重登；系统拒绝的下次重试；触发时只发登记中仍有效的一次）。应用：`Reminders`、`AndroidAlarms`（精确需用户授予 `SCHEDULE_EXACT_ALARM`，否则非精确并标记可能延迟；不声明 `USE_EXACT_ALARM`，无前台服务）、两个不导出的 receiver（触发；重启/更新/改时间/改时区/授予精确权限后恢复），回到前台时复查被撤销的精确授权。同结束点普通完成与周期总结只有一条（总结替换 100% 文案）。**未做**：设置页的权限行随 T15（文案走 T05）；由班次/专注状态调用 `Reminders.schedule` 随 T16；常驻通知随 T19；QA-083～086、089、094 需真机。 |
| T15 | DONE | **偏好**：`settings/PreferencesRules`（iOS 首启默认值、同内容不写、盖戳提交、最后一个工作日不可删、提醒页默认值；`AppLanguages` 映射系统语言与 iOS 一致，`in` 视为印尼语）；`:core:data` 的 `SettingsRepository`（完成设置前只写本机草稿、档案不落任何默认值；完成时一次提交；档案已有设置即视为已设置，覆盖系统备份恢复）与 `DeviceSettingsStore`（本机专属项，含当前设置页，任何中断都回到原页）。**外壳**：Navigation 3 的四个主入口各自独立返回栈，重新选中回到根；窄屏底栏，宽屏或横屏手机侧边栏；设置类页面限宽 720 dp。**设置**：与 iOS 相同的五组（班次、提醒、外观、记录与数据、关于），Plus 为标题动作；班次提醒（权限只请求一次，拒绝后回到不提醒并指向系统设置；无精确闹钟授权时提示可能延迟）、健康提醒、主题（Android 12+ 可选壁纸配色）、语言（Android 13+ 与系统应用语言双向同步，更早版本在 Compose 内切换）、关于与致谢（节假日数据署名直接读取 iOS 共享资源）。**首次启动**：欢迎 → 上班时间与排班方式 → 午休与提醒 → 隐私 → 完成，最后一步才写入档案；另有从备份文件恢复（只读预览、确认后仅写入空档案，带设置则直接进入主界面，否则保留记录继续设置）。新增 Android 专有文案 5 条（19 语言）。测试：偏好 7 条、设置仓库 5 条、首启恢复 4 条。模拟器（API 36）检查：首启全流程与一次提交、权限允许与拒绝、恢复备份、强制停止后回到原页、深色、日语/德语/阿拉伯语 RTL、系统语言双向同步、横屏侧边栏；临时强制旧版语言路径时发现并修复 Android 12 及以下的两处问题（语言资源未替换、权限启动器找不到 Activity 而崩溃）。**留给后续**：计时/专注/记录首页与排班、收入页属 T16–T18；Plus 页与引导中的 Plus 展示属 T20；记录与数据页（导出、导入合并、记录时区迁移）属 T11；完成页的品牌标志待品牌资源；Compose 仪器化 UI 测试未加（CI 无模拟器），以上为人工模拟器检查。 |
| T16–T20 | NOT_STARTED | — |
| T21 | DEFERRED | 服务端验证，首发后（D-08 修订） |
| T22 | DEFERRED | Drive 同步，首发后（D-02 修订） |
| T23–T26 | NOT_STARTED | — |
| T27 | DEFERRED | Wear，首发后（D-05） |

## 执行状态

| 项 | 状态 |
|---|---|
| Android 工程 | app、core:domain、core:data、core:designsystem |
| 自动化应用测试 | NOT_RUN（140 条；首发 126 条） |
| 真机 / 模拟器 | 模拟器：T03 启动探针、T04 设计 token 视觉检查；真机 NOT_RUN |
| Play Console | 未操作 |

## 下一任务

可并行：

- **T16 · 计时、收入与排班页面**（依赖 T07、T08、T15）。
- **T18 · 专注画布**（依赖 T13、T15）。
- **T20 · 权益与 Play Billing**（依赖 T03、T15）。
- **T11 剩余部分**（导入导出界面、合并与冲突中心），完成后可做 T17。

M1、M2 与 T15 已完成。

环境与命令见 `environment-lock.md`。候选默认（发布前冻结）：`applicationId=com.rainif.doneat`，minSdk 26，versionName 3.2.0，versionCode 1。

## 基线漂移记录

每个里程碑结束运行：

```text
git log --oneline 9252fdfdc66aab88b4acb7493684f11991fd773d..origin/main -- lib src-mobile/ios/App/App/Native/Models src-mobile/ios/Shared
```

| 日期 | 基线之后影响规则的提交 | 处理 |
|---|---|---|
| 2026-09-23 | 0 | 无需跟进 |
| 2026-09-23（M1/M2 结束） | 0 | 无需跟进 |

## 变更记录

- 2026-09-21：T00–T02 完成。
- 2026-09-23：T15 完成（偏好、外壳与导航、设置、首次启动与备份恢复）。
- 2026-09-23：T04 完成（设计 token、数字翻页、进度条）；T05 完成（翻译生成与检查）。M1、M2 结束，基线无漂移。
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
