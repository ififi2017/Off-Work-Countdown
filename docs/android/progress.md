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
| T11 | IN_PROGRESS | 编解码、合并模式与冲突报告已随 T10 完成。**记录与数据页**：`:core:data` 的 `RecordsTransfer`（v6 导出，可不含人生档案；导入先在副本上预检，报告新增/不变/冲突/已删除跳过，确认后在存储锁内按当前档案重新合并、一次写入，同键冲突保留本机；超过 25 MiB 不读；v7 等更新版本提示升级，v0 与非备份提示无效；删除本机记录保留设置）。页面：系统文件选择器导入与创建文档导出（无存储权限），导出说明备份包含的个人内容（Android 专有文案 2 条，19 语言）。测试 7 条（v1–v6 逐版导入、v7/v0/非 JSON/超限、重复导入不重复、失败不改档案、导出往返、排除人生档案、删除保留设置）。模拟器检查：导出后再导入为 0 新增、导入样例 v6、v7 拒绝、删除。收入隐藏时，导入确认、导出、删除前先经 `EarningsGate` 确认本人（取消则提示且档案不变；无锁屏时直接进行，与 iOS 一致），模拟器已检查三种情况。**待做**：冲突中心（Android 无同步，需先设计冲突存放）；记录时区迁移页。 |
| T12 | IMPLEMENTED | `records/`：`DayRecordResolver`（三层链与来源标记）、`RecordHistory.expandableHours`（唯一的快照读取入口，含名册叠加与旧行边界）、`ScheduleHoursCodec`（与 Swift 字节一致，指纹相同；由 11 个 oracle 用例把关）、`DayOverrideProjection`、`RecordEdits`（盖戳 upsert、墓碑之上复活、首次写入播种、同日快照改写、日写入计划）、`DayEditDraft`。移植 iOS `DayRecordResolverTests` 17 条与 `DayOverrideProjectionTests` 的 9 条纯函数用例，另有 13 条编辑/历史测试；4 项植入错误均被捕获。`LifeViewCalculator` 移到 T17；依赖计时会话的 10 条投影用例移到 T16。 |
| T13 | DONE | **T13a**：`focus/FocusPlanner`（网格、可开始窗口、边界、结束原因、溢出）、`FocusSessionIdentity`（SHA-256 派生，与交接包两个向量一致）、`FocusEngine`（开始条件与互斥、计划块内开始、自然结束按计划终点结算、任务达预估才完成、自动休息与派生 id、跳过、收敛为一个进行中会话、冷启动恢复下一步）；13 条规划器用例与 18 条生命周期测试。**T13b**：`FocusCanvas`（画布模型、模板任务分组与整任务前缀、`FocusChain` 投影）与 `FocusPlanning`（分配/休息/清除、模板保存/编辑/应用/重排/默认/分离、收藏、任务编辑与缩放、清空当天、放置与再加一轮、由计划驱动的自动会话队列与恢复）；41 条测试对应 `FocusCanvasTests`、`FocusTaskEditingTests` 与 `FocusStoreTests` 的模板用例。Live Activity 接管休息移到 T14，时间线事件与实时链条的展示移到 T19。 |
| T14 | DONE | 领域：`schedule/ReminderRules`（`lib/reminders.ts` 的逐条移植，`ScheduleRules.reminders` 当前+下一班次，320 条共享 fixture 全部通过）、`reminders/CycleSummary`（周期末总结与申报加班段，后一天未解析不当作休息）、`focus/FocusReminders`（专注阶段两条提醒、计划接管健康提醒）、`reminders/ReminderPlanner`（当前班次仅在确在班时提醒、只取将来且有文案的、关键提醒优先 60 条上限、提前下班只留下一班次、稳定 ID 差量、重启不补发、健康提醒不用精确闹钟）。数据：`ReminderSync`（登记文件在调用系统前写入且不进备份；授权变化时全部重登；系统拒绝的下次重试；触发时只发登记中仍有效的一次）。应用：`Reminders`、`AndroidAlarms`（精确需用户授予 `SCHEDULE_EXACT_ALARM`，否则非精确并标记可能延迟；不声明 `USE_EXACT_ALARM`，无前台服务）、两个不导出的 receiver（触发；重启/更新/改时间/改时区/授予精确权限后恢复），回到前台时复查被撤销的精确授权。同结束点普通完成与周期总结只有一条（总结替换 100% 文案）。**未做**：设置页的权限行随 T15（文案走 T05）；由班次/专注状态调用 `Reminders.schedule` 随 T16；常驻通知随 T19；QA-083～086、089、094 需真机。 |
| T15 | DONE | **偏好**：`settings/PreferencesRules`（iOS 首启默认值、同内容不写、盖戳提交、最后一个工作日不可删、提醒页默认值；`AppLanguages` 映射系统语言与 iOS 一致，`in` 视为印尼语）；`:core:data` 的 `SettingsRepository`（完成设置前只写本机草稿、档案不落任何默认值；完成时一次提交；档案已有设置即视为已设置，覆盖系统备份恢复）与 `DeviceSettingsStore`（本机专属项，含当前设置页，任何中断都回到原页）。**外壳**：Navigation 3 的四个主入口各自独立返回栈，重新选中回到根；窄屏底栏，宽屏或横屏手机侧边栏；设置类页面限宽 720 dp。**设置**：与 iOS 相同的五组（班次、提醒、外观、记录与数据、关于），Plus 为标题动作；班次提醒（权限只请求一次，拒绝后回到不提醒并指向系统设置；无精确闹钟授权时提示可能延迟）、健康提醒、主题（Android 12+ 可选壁纸配色）、语言（Android 13+ 与系统应用语言双向同步，更早版本在 Compose 内切换）、关于与致谢（节假日数据署名直接读取 iOS 共享资源）。**首次启动**：欢迎 → 上班时间与排班方式 → 午休与提醒 → 隐私 → 完成，最后一步才写入档案；另有从备份文件恢复（只读预览、确认后仅写入空档案，带设置则直接进入主界面，否则保留记录继续设置）。新增 Android 专有文案 5 条（19 语言）。测试：偏好 7 条、设置仓库 5 条、首启恢复 4 条。模拟器（API 36）检查：首启全流程与一次提交、权限允许与拒绝、恢复备份、强制停止后回到原页、深色、日语/德语/阿拉伯语 RTL、系统语言双向同步、横屏侧边栏；临时强制旧版语言路径时发现并修复 Android 12 及以下的两处问题（语言资源未替换、权限启动器找不到 Activity 而崩溃）。**留给后续**：计时/专注/记录首页与排班、收入页属 T16–T18；Plus 页与引导中的 Plus 展示属 T20；记录与数据页（导出、导入合并、记录时区迁移）属 T11；完成页的品牌标志已随 T16a 补上；Compose 仪器化 UI 测试未加（CI 无模拟器），以上为人工模拟器检查。 |
| T16 | DONE | **计时与收入**：`:core:domain` 的 `session/`——`ShiftSession`（iOS `ShiftSession` 的读取投影：当日保留时刻、提前上班、按设备/记录/会话时区取规则输入，扩展排班下固定当前班次那一天，冻结的提前下班快照，状态判定 `TimerPhase`，周/年估算，今日覆盖投影）、`SessionCommands`（开始/强制休息日计时、提前下班与撤销、提前上班与撤销、取消手动计时、停止、加班与清除、完成设置时启动、每日清理：过期标记、手动计时在结束日零点后复位、会话时区到期）、`SessionRecords`（观测记录与计时覆盖和命令同一次档案写入）、`UpcomingTimeline`、`ShiftReminderPlan`（当前班次仅在确在班且未结束时提醒，提前下班后只留下一班次）。`:core:data` 的 `SessionStore`（本机状态文件，含薪资的冻结快照不进档案；档案损坏时拒绝一切命令且不动本机状态；已设置的设备首次启动即启动计时）。应用：`TimerCoordinator`（会话或设置变化后重排班次提醒；设置完成时启动；启动、回前台与计时页每分钟清理），计时页七种状态（未排班、上班前、工作、午休、加班、已下班、休息日）与规则异常，提前上下班与取消手动计时需 5 秒内再按一次，加班对话框（不早于计划下班和现在，可跨零点），收入统一遮罩，显示需通过设备锁（生物识别或 PIN），无锁屏时直接显示并说明原因（新增 Android 专有文案 1 条，19 语言），完成时彩纸与触感（照搬 iOS `OWCConfettiOverlay` 的粒子与物理；减少动态效果时只有触感）。品牌：`DoneAtBrandMark`/`CelebratingBrandMark`（按 `assets/brand` 几何原生绘制，深浅色切换指针颜色，连点五下指针转两圈）用于未排班页、欢迎页、完成页、关于；自适应启动图标（前景环、指针、圆点，渐变背景，Android 13 单色主题图标）。测试：会话 25 条（移植 iOS `OffWorkStoreTests`/`ShiftActionTests` 的对应用例）、`SessionStore` 5 条。模拟器（API 36）检查：各状态、两次确认、撤销、加班、隐藏与 PIN 显示/取消/无锁屏、阿拉伯语 RTL、深色、200% 字体、横屏。顺带修复：`DoneAtCountdown` 在 RTL 下数字顺序颠倒（T04 遗漏）。**排班**：与 iOS 一样只有一个日历编辑器，固定排班以等价的扩展排班预览（种子 id 由内容派生，两页一致），保存前不写任何东西。`session/ScheduleChange.kt` 移植 `ScheduleFieldChange`（逐项与已存值比对后丢弃未变项）、`ExtendedScheduleEditing`（班型增改归档、周期长短与锚点、模板填充、手排与“跟随规律”、去掉规律时保留两个月、清空预计排班时保护已计时/已修正/进行中的日子）、`seededExtendedContent`/`schedulePattern`（由共享规则算出与固定排班相同的工作日）、`plannedPreview`（过去日期按 Records 显示），以及 `ScheduleSave`：偏好、扩展排班、手排日（盖戳、墓碑与复活）、Records 快照与今日覆盖一次写入，“仅从下一班次”保留今日时刻，“今天也改”清除提前上下班与加班、保留休息日手动计时。界面：月历、规律选择（固定/大小周/轮班/自由/手动，切换需确认）、周期格、轮班长度与“今天是第几天”、节假日地区选择（默认关闭，按 PRD 不自动启用；iOS 首启默认设备地区）、选中日的班型、班型列表与编辑页、保存时按规则询问是否影响今天、未保存离开确认。**薪资**：按设备锁解锁后显示，离开即重新上锁，Android 13+ 最近任务不显示缩略图；数字输入折叠各文字数字与小数点（`NumberInput`），空与 0 不混同，获得焦点全选；Android 版说明文案 2 条（19 语言，去掉 iCloud 与“实时活动”）。测试：排班保存 13 条（移植 iOS 对应用例）、数字输入 3 条。分享图与链接属 T19；周期总结提醒需 Plus（T20）；专注接管健康提醒与计时页专注事件随 T18。 |
| T17 | IN_PROGRESS | **T17a 周、月与单日**：`:core:domain` 的 `records/RecordsQueries`（iOS `RecordsQueries` 的读取投影：按快照一次展开整个区间再逐日走三层链，冻结名册在无快照时补位；日格外观与来源、夜班早段计入次日、已保存排班过去的日子视为已工作、今天之后为计划；人生档案对 Records 之前年份的内存估算，从不写入档案；期间汇总与实际/预计拆分沿用 `SummaryRules`，薪资只在开启时计入；免费窗口为今天及前六天，窗口外日格与单日只剩“已锁定”，无 Plus 不构造汇总）与 `RecordsPresentation`（`RecordsDayCanvasModel` 切出一天：工作、加班、班内休息、睡眠预算、自主时间、规则失败时为未分类，今天在整分钟处分出“之后为估算”）。测试：单日画布 15 条（移植 iOS `RecordsDayCanvasModelTests` 与加班强度用例）、查询 12 条；两项植入错误均被捕获。应用：记录页（周/月切换并记住、上一段/下一段/回到今天、月历与周柱、选中后再点或点说明进入当天、图例、汇总卡含已工作/加班/预计薪资/时间分配与说明、宽屏两栏）、单日页（24 小时色带与时间轴、属于你的清醒时间、时间段列表、应用注意到的事件）、全部记录（年、月、日三级，免费用户窗口外只显示一行“已锁定”）；设计系统新增 Records 六色（与 iOS 系统色一致，含深色）；眼睛按钮抽成共享组件。`PlusAccess`：发布版恒为免费（购买随 T20）；仅调试版在“关于”页有“Plus unlocked”开关，发布包中不含该开关与字符串。模拟器（API 36）检查：免费与 Plus、周/月、选中与进入单日、深色、阿拉伯语 RTL + 200% 字体、全部记录。**T17b 年视图与单日编辑**：`RecordsYearSampler`（按网格格数切分一年，修正/已记录/估算/锁定的归并与 iOS 相同，深浅按已记录日的最大加班，估算工作画斜纹）与 `RecordsCanvasGrid`（格子尺寸、点按命中、选中月份按行合并为一块）；`:core:data` 的 `RecordsEditing`（一次写入，未获准或键不规范时档案不变）。界面：年视图（热力格、月份按钮、单击选月、双击或“打开所选月份”进入月视图、年度汇总；无 Plus 只显示锁且不计算）；单日页“改这一天”（两个班次触及同一天时先选班次，按各自时间命名）；编辑页（时间、五种类型、一次保存；离开前确认放弃；自己填的时间改成其他类型先确认；“清空我的修改”回到排班与节假日）。与 iOS 一致：没有汇总时不显示汇总卡（含无 Plus 时），T17a 的锁定汇总卡已去掉；iOS 在“清空我的修改”上方的“删除同步数据”标题因 Android 无同步而不显示。测试：年采样 4 条、保存 3 条。模拟器检查：年视图（Plus 与免费）、请假保存后单日即时更新、清空恢复、离开确认与替换工时确认。**待做**：T17c 人生页、档案编辑与人生汇总；年视图展开（按月读汇总）与双指缩放切换尺度；单日页的专注记录随 T18。 |
| T18–T20 | NOT_STARTED | — |
| T21 | DEFERRED | 服务端验证，首发后（D-08 修订） |
| T22 | DEFERRED | Drive 同步，首发后（D-02 修订） |
| T23–T26 | NOT_STARTED | — |
| T27 | DEFERRED | Wear，首发后（D-05） |

## 执行状态

| 项 | 状态 |
|---|---|
| Android 工程 | app、core:domain、core:data、core:designsystem |
| 自动化应用测试 | NOT_RUN（140 条；首发 126 条） |
| 真机 / 模拟器 | 模拟器：T03 启动探针、T04 设计 token、T15 外壳与首启、T16 计时/排班/薪资、T11 记录与数据、T17a 记录页；真机 NOT_RUN |
| Play Console | 未操作 |

## 下一任务

可并行：

- **T18 · 专注画布**（依赖 T13、T15）。
- **T20 · 权益与 Play Billing**（依赖 T03、T15）。
- **T17c**：人生页。
- **T11 剩余部分**：冲突中心与记录时区迁移页。

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
- 2026-09-24：T16 完成（排班编辑器、薪资设置）。
- 2026-09-23：T16a 完成（会话领域、计时页、收入隐藏与身份确认、班次提醒接入）。
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
