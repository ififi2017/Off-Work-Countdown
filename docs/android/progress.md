# Android 移植进度

**这是任务状态的唯一记录。** 交接包 `tasks.json` 只定义依赖、范围和验收，不记录状态。

更新：2026-09-27。交接包 1.2。源 SHA `9252fdfdc66aab88b4acb7493684f11991fd773d`。

## 任务状态

状态：NOT_STARTED → IN_PROGRESS → IMPLEMENTED → VERIFIED；另有 WAITING_OWNER、BLOCKED、DEFERRED。

| ID | 状态 | 证据 / 备注 |
|---|---|---|
| T00 | IMPLEMENTED | `baseline.md`。未 reset 工作区。QA-001 分支创建 NOT_RUN。 |
| T01 | IMPLEMENTED | `source-inventory.md`、`feature-parity.md`、`conflicts.md`。源读自固定 SHA。未跑 iOS XCTest。 |
| T02 | IMPLEMENTED | `wire-contract.md`、`synthetic-archives/`。检查：`node scripts/android-synthetic-archives.mjs --check`。Kotlin 导入 NOT_RUN。 |
| T03 | IMPLEMENTED | `environment-lock.md`；`src-mobile/android`；`.github/workflows/android.yml`。初始 T03 探针当时只有 domain 2 项测试、Debug/R8 Release/AAB 与模拟器冷启动；当前四模块与 423 项见下方执行状态。GitHub CI 运行证据另取，不以本地命令代替。 |
| T04 | IMPLEMENTED | `:core:designsystem`：`DoneAtColors`（浅/深两套完整 M3 配色，暖中性表面；浅色主色 `#C2410C`，品牌亮橙仅作装饰）、`DoneAtStateColors`、`DoneAtShapes`（14/22 与 iOS 一致；主操作按下时胶囊收成 12 dp）、`DoneAtMotion`（与 `OWCMotion` 同值，减少动态效果时退化）、`DoneAtType.countdown`（64 sp 等宽数字）、`DoneAtCountdown`（逐位数字翻页，对应 `.numericText(countsDown:)`）、`DoneAtProgressMeter`（浮动百分比气泡，几何与 `OWCProgressMeter` 相同）、`DoneAtTheme`（主题模式、可选动态配色）。对比度与气泡几何 8 条单测；Debug 专用 gallery。模拟器（API 36）检查浅色、深色、200% 字体、移除动画、阿拉伯语 RTL、数字翻页录屏。Release 依赖全为稳定版（Material3 1.4.0）。见 `design-tokens-adr.md`。 |
| T05 | IMPLEMENTED | `scripts/generate-android-strings.mjs`（`npm run generate:android-strings` / `check:android-strings`）把 `Localizable.xcstrings` 的 832 个 key 与 `app/i18n/android-strings.json` 的 Android 专有文案转成 19 个语言目录的 `strings_catalog.xml`、`xml/locales_config.xml`（清单已引用）、可逆的 `app/i18n/key-map.json` 与带命名参数的 `l10n/Strings.kt`。`{{name}}` 按英文顺序转为 `%N$s`；消息池转为 string-array 并保留 `{{name}}` 供共享规则替换；复数按各语言 CLDR 类别生成；Java/Kotlin 关键字 key 加下划线。生成时检查：19 语言齐全、各语言占位符与英文一致、Android 专有 key 不与目录重名、资源名合法且不碰撞、XML 非法字符。12 条 vitest 覆盖中文三变体、印地/马拉地语、阿语复数、德语长句占位符重排、转义与各类拒绝；`npm test` 与 Android CI 在资源过期时失败。Android 专有文案已随记录、Plus、通知等页面扩充，19 语言由生成器检查。aapt2 编译与 lint 通过，无新增告警（`localeConfig` 在 API 33 以下被忽略属预期）。 |
| T06 | IMPLEMENTED | `scripts/generate-android-rule-fixtures.mjs` → `src-mobile/android/core/domain/src/test/resources/shared-rule-fixtures.json`：5087 条 TS oracle 用例，与 iOS `ScheduleRuleFixtures` 数据逐字相同，另记 6 个输入文件哈希。`npm test` 内含 stale 检查（手改一条用例、给 `lib/countdown.ts` 加注释均使检查失败，已验证）；Kotlin `SharedRuleFixturesTest` 3 条通过。Swift 特有规则的 fixtures 属 T08。 |
| T07 | IMPLEMENTED | `core/domain/.../schedule`（`CivilZone`、`ScheduleRules`、模型）与 `salary/SalaryRules`。fixture 的 snapshots/widget/expansion/validateBreak/applyToday 共 2927 条全部精确通过；植入错误测试有效；算例测试 5 条。见 `rule-parity.md`。 |
| T08 | IMPLEMENTED | `ExtendedSchedule.kt`（解析器、计划、校验）、`HolidayCalendar.kt`、`CivilZone` 扩展路径。Swift 导出的 fixtures 共约 7200 条全部通过，4 项植入错误均被捕获。编辑器逻辑移到 T15/T16，`expandableHours` 叠加移到 T12。见 `rule-parity.md`。 |
| T09 | IMPLEMENTED | `summary/SummaryRules.kt`：五段 TS fixture 共 714 条全部通过；3 项植入错误均被捕获。`LifeViewCalculator` 移到 T12/T17。见 `rule-parity.md`。 |
| T10 | IMPLEMENTED | D-13：与 iOS 相同的单文件档案。`:core:domain` 的 `records/`（模型、`RecordJson` 编解码与合并、`FoundationCompat`）；`:core:data` 的 `RecordArchive`、`RecordStore`。Swift RecordJSON oracle 的 88 个用例全部通过（含 v1–v6、非法档案、逐实体拒绝、三种合并模式）；5 项植入错误均被捕获；文件系统测试 8 条（重启读回、写失败不提交、校验失败不落盘、损坏阻断与隔离、墓碑、并发串行）。 |
| T11 | IMPLEMENTED | `RecordsTransfer` 支持 v1–v6 预览/合并、v6 导出、人生档案排除、25 MiB 上限与拒绝数反馈；文件选择器无存储权限。`RecordInputBounds` 对深度/容器/数值设界，`RecordJson.apply` 使用索引合并，重复身份不会使导入二次方增长。冲突候选只存本机档案、不进 v6 导出；冲突页展示本机/导入字段差异，整份保留或替换在存储锁内盖戳并原子提交，拒绝陈旧候选/当前编辑。隐藏收入时进入冲突页和选择结果都需设备本人认证；不同记录时区的导入偏好不能绕过专门迁移。`RecordsTimeZoneMigration` 连同偏好在一次档案写入中迁移，运行会话先锁定旧时区至本班结束。删除失败有反馈。合成 v6 档案经真实 iOS→Kotlin→iOS 往返比较，12 类实体身份和字段保留。真机文件选择器/认证/时区全矩阵仍列入 QA，不把 JVM 通过当作设备通过。 |
| T12 | IMPLEMENTED | `records/`：`DayRecordResolver`（三层链与来源标记）、`RecordHistory.expandableHours`（唯一的快照读取入口，含名册叠加与旧行边界）、`ScheduleHoursCodec`（与 Swift 字节一致，指纹相同；由 11 个 oracle 用例把关）、`DayOverrideProjection`、`RecordEdits`（盖戳 upsert、墓碑之上复活、首次写入播种、同日快照改写、日写入计划）、`DayEditDraft`。移植 iOS `DayRecordResolverTests` 17 条与 `DayOverrideProjectionTests` 的 9 条纯函数用例，另有 13 条编辑/历史测试；4 项植入错误均被捕获。`LifeViewCalculator` 移到 T17；依赖计时会话的 10 条投影用例移到 T16。 |
| T13 | IMPLEMENTED | **T13a**：`focus/FocusPlanner`（网格、可开始窗口、边界、结束原因、溢出）、`FocusSessionIdentity`（SHA-256 派生，与交接包两个向量一致）、`FocusEngine`（开始条件与互斥、计划块内开始、自然结束按计划终点结算、任务达预估才完成、自动休息与派生 id、跳过、收敛为一个进行中会话、冷启动恢复下一步）；13 条规划器用例与 18 条生命周期测试。**T13b**：`FocusCanvas`（画布模型、模板任务分组与整任务前缀、`FocusChain` 投影）与 `FocusPlanning`（分配/休息/清除、模板保存/编辑/应用/重排/默认/分离、收藏、任务编辑与缩放、清空当天、放置与再加一轮、由计划驱动的自动会话队列与恢复）；41 条测试对应 `FocusCanvasTests`、`FocusTaskEditingTests` 与 `FocusStoreTests` 的模板用例。Live Activity 接管休息移到 T14，时间线事件与实时链条的展示移到 T19。 |
| T14 | IMPLEMENTED | 领域：`schedule/ReminderRules`（`lib/reminders.ts` 的逐条移植，`ScheduleRules.reminders` 当前+下一班次，320 条共享 fixture 全部通过）、`reminders/CycleSummary`（周期末总结与申报加班段，后一天未解析不当作休息）、`focus/FocusReminders`（专注阶段两条提醒、计划接管健康提醒）、`reminders/ReminderPlanner`（当前班次仅在确在班时提醒、只取将来且有文案的、关键提醒优先 60 条上限、提前下班只留下一班次、稳定 ID 差量、重启不补发、健康提醒不用精确闹钟）。数据：`ReminderSync`（登记文件在调用系统前写入且不进备份；授权变化时全部重登；系统拒绝的下次重试；触发时只发登记中仍有效的一次）。应用：`Reminders`、`AndroidAlarms`（精确需用户授予 `SCHEDULE_EXACT_ALARM`，否则非精确并标记可能延迟；不声明 `USE_EXACT_ALARM`，无前台服务）、两个不导出的 receiver（触发；重启/更新/改时间/改时区/授予精确权限后恢复），回到前台时复查被撤销的精确授权。同结束点普通完成与周期总结只有一条（总结替换 100% 文案）。设置页权限行、会话重排与常驻通知分别在 T15/T16/T19 实现；QA-083～086、089、094 仍需设备证据。 |
| T15 | IMPLEMENTED | **偏好**：`settings/PreferencesRules`（iOS 首启默认值、同内容不写、盖戳提交、最后一个工作日不可删、提醒页默认值；`AppLanguages` 映射系统语言与 iOS 一致，`in` 视为印尼语）；`:core:data` 的 `SettingsRepository`（完成设置前只写本机草稿、档案不落任何默认值；完成时一次提交；档案已有设置即视为已设置，覆盖系统备份恢复）与 `DeviceSettingsStore`（本机专属项，含当前设置页，任何中断都回到原页）。**外壳**：Navigation 3 的四个主入口各自独立返回栈，重新选中回到根；窄屏底栏，宽屏或横屏手机侧边栏；设置类页面限宽 720 dp。**设置**：与 iOS 相同的五组（班次、提醒、外观、记录与数据、关于），Plus 为标题动作；班次提醒（权限只请求一次，拒绝后回到不提醒并指向系统设置；无精确闹钟授权时提示可能延迟）、健康提醒、主题（Android 12+ 可选壁纸配色）、语言（Android 13+ 与系统应用语言双向同步，更早版本在 Compose 内切换）、关于与致谢（节假日数据署名直接读取 iOS 共享资源）。**首次启动**：欢迎 → 上班时间与排班方式 → 午休与提醒 → 隐私 → 完成，最后一步才写入档案；另有从备份文件恢复（只读预览、确认后仅写入空档案，带设置则直接进入主界面，否则保留记录继续设置）。新增 Android 专有文案 5 条（19 语言）。测试：偏好 7 条、设置仓库 5 条、首启恢复 4 条。模拟器（API 36）检查：首启全流程与一次提交、权限允许与拒绝、恢复备份、强制停止后回到原页、深色、日语/德语/阿拉伯语 RTL、系统语言双向同步、横屏侧边栏；临时强制旧版语言路径时发现并修复 Android 12 及以下的两处问题（语言资源未替换、权限启动器找不到 Activity 而崩溃）。计时、专注、记录、Plus 与记录数据页已在 T11/T16–T20 实现；完成页品牌标志随 T16 补上。Compose 仪器化 UI 测试尚未加入无模拟器的 CI，上述设备结果为人工检查。 |
| T16 | IMPLEMENTED | **计时与收入**：`:core:domain` 的 `session/`——`ShiftSession`（iOS `ShiftSession` 的读取投影：当日保留时刻、提前上班、按设备/记录/会话时区取规则输入，扩展排班下固定当前班次那一天，冻结的提前下班快照，状态判定 `TimerPhase`，周/年估算，今日覆盖投影）、`SessionCommands`（开始/强制休息日计时、提前下班与撤销、提前上班与撤销、取消手动计时、停止、加班与清除、完成设置时启动、每日清理：过期标记、手动计时在结束日零点后复位、会话时区到期）、`SessionRecords`（观测记录与计时覆盖和命令同一次档案写入）、`UpcomingTimeline`、`ShiftReminderPlan`（当前班次仅在确在班且未结束时提醒，提前下班后只留下一班次）。`:core:data` 的 `SessionStore`（本机状态文件，含薪资的冻结快照不进档案；档案损坏时拒绝一切命令且不动本机状态；已设置的设备首次启动即启动计时）。应用：`TimerCoordinator`（会话或设置变化后重排班次提醒；设置完成时启动；启动、回前台与计时页每分钟清理），计时页七种状态（未排班、上班前、工作、午休、加班、已下班、休息日）与规则异常，提前上下班与取消手动计时需 5 秒内再按一次，加班对话框（不早于计划下班和现在，可跨零点），收入统一遮罩，显示需通过设备锁（生物识别或 PIN），无锁屏时直接显示并说明原因（新增 Android 专有文案 1 条，19 语言），完成时彩纸与触感（照搬 iOS `OWCConfettiOverlay` 的粒子与物理；减少动态效果时只有触感）。品牌：`DoneAtBrandMark`/`CelebratingBrandMark`（按 `assets/brand` 几何原生绘制，深浅色切换指针颜色，连点五下指针转两圈）用于未排班页、欢迎页、完成页、关于；自适应启动图标（前景环、指针、圆点，渐变背景，Android 13 单色主题图标）。测试：会话 25 条（移植 iOS `OffWorkStoreTests`/`ShiftActionTests` 的对应用例）、`SessionStore` 5 条。模拟器（API 36）检查：各状态、两次确认、撤销、加班、隐藏与 PIN 显示/取消/无锁屏、阿拉伯语 RTL、深色、200% 字体、横屏。顺带修复：`DoneAtCountdown` 在 RTL 下数字顺序颠倒（T04 遗漏）。**排班**：与 iOS 一样只有一个日历编辑器，固定排班以等价的扩展排班预览（种子 id 由内容派生，两页一致），保存前不写任何东西。`session/ScheduleChange.kt` 移植 `ScheduleFieldChange`（逐项与已存值比对后丢弃未变项）、`ExtendedScheduleEditing`（班型增改归档、周期长短与锚点、模板填充、手排与“跟随规律”、去掉规律时保留两个月、清空预计排班时保护已计时/已修正/进行中的日子）、`seededExtendedContent`/`schedulePattern`（由共享规则算出与固定排班相同的工作日）、`plannedPreview`（过去日期按 Records 显示），以及 `ScheduleSave`：偏好、扩展排班、手排日（盖戳、墓碑与复活）、Records 快照与今日覆盖一次写入，“仅从下一班次”保留今日时刻，“今天也改”清除提前上下班与加班、保留休息日手动计时。界面：月历、规律选择（固定/大小周/轮班/自由/手动，切换需确认）、周期格、轮班长度与“今天是第几天”、节假日地区选择（默认关闭，按 PRD 不自动启用；iOS 首启默认设备地区）、选中日的班型、班型列表与编辑页、保存时按规则询问是否影响今天、未保存离开确认。**薪资**：按设备锁解锁后显示，离开即重新上锁，Android 13+ 最近任务不显示缩略图；数字输入折叠各文字数字与小数点（`NumberInput`），空与 0 不混同，获得焦点全选；Android 版说明文案 2 条（19 语言，去掉 iCloud 与“实时活动”）。测试：排班保存 13 条（移植 iOS 对应用例）、数字输入 3 条。分享图与链接属 T19；周期总结提醒需 Plus（T20）；专注接管健康提醒与计时页专注事件随 T18。 |
| T17 | IMPLEMENTED | **T17a 周、月与单日**：`:core:domain` 的 `records/RecordsQueries`（iOS `RecordsQueries` 的读取投影：按快照一次展开整个区间再逐日走三层链，冻结名册在无快照时补位；日格外观与来源、夜班早段计入次日、已保存排班过去的日子视为已工作、今天之后为计划；人生档案对 Records 之前年份的内存估算，从不写入档案；期间汇总与实际/预计拆分沿用 `SummaryRules`，薪资只在开启时计入；免费窗口为今天及前六天，窗口外日格与单日只剩“已锁定”，无 Plus 不构造汇总）与 `RecordsPresentation`（`RecordsDayCanvasModel` 切出一天：工作、加班、班内休息、睡眠预算、自主时间、规则失败时为未分类，今天在整分钟处分出“之后为估算”）。测试：单日画布 15 条（移植 iOS `RecordsDayCanvasModelTests` 与加班强度用例）、查询 12 条；两项植入错误均被捕获。应用：记录页（周/月切换并记住、上一段/下一段/回到今天、月历与周柱、选中后再点或点说明进入当天、图例、汇总卡含已工作/加班/预计薪资/时间分配与说明、宽屏两栏）、单日页（24 小时色带与时间轴、属于你的清醒时间、时间段列表、应用注意到的事件）、全部记录（年、月、日三级，免费用户窗口外只显示一行“已锁定”）；设计系统新增 Records 六色（与 iOS 系统色一致，含深色）；眼睛按钮抽成共享组件。`PlusAccess` 当时先接免费判定，真实购买已在 T20 接入；仅调试版在“关于”页有“Plus unlocked”开关，发布包中不含该开关与字符串。模拟器（API 36）检查：免费与 Plus、周/月、选中与进入单日、深色、阿拉伯语 RTL + 200% 字体、全部记录。**T17b 年视图与单日编辑**：`RecordsYearSampler`（按网格格数切分一年，修正/已记录/估算/锁定的归并与 iOS 相同，深浅按已记录日的最大加班，估算工作画斜纹）与 `RecordsCanvasGrid`（格子尺寸、点按命中、选中月份按行合并为一块）；`:core:data` 的 `RecordsEditing`（一次写入，未获准或键不规范时档案不变）。界面：年视图（热力格、月份按钮、单击选月、双击或“打开所选月份”进入月视图、年度汇总；无 Plus 只显示锁且不计算）；单日页“改这一天”（两个班次触及同一天时先选班次，按各自时间命名）；编辑页（时间、五种类型、一次保存；离开前确认放弃；自己填的时间改成其他类型先确认；“清空我的修改”回到排班与节假日）。与 iOS 一致：没有汇总时不显示汇总卡（含无 Plus 时），T17a 的锁定汇总卡已去掉；iOS 在“清空我的修改”上方的“删除同步数据”标题因 Android 无同步而不显示。测试：年采样 4 条、保存 3 条。模拟器检查：年视图（Plus 与免费）、请假保存后单日即时更新、清空恢复、离开确认与替换工时确认。**T17c 人生**：`records/LifeRules`（`LifeDates` 只有年份时取 7 月 1 日；`LifeStageCalculator` 阶段、按“现在”拆分工作期且保持选中身份、时间轴不虚构寿命、格子采样；`LifeViewCalculator` 周格与出生到退休的六类时间分配，并集去重、详细经历只计在职区间、记录的加班单列；`LifeProfiles.edit` 盖戳写入、同内容不写、睡眠来源时间只随睡眠变化、墓碑之上复活）、`LifeProfileDraft` 与 `LifeEmploymentTimeline`（编辑器的读取、校验与保存，与 iOS 同规则）、`RecordsQueries.lifeModel`（整段职业生涯按同一三层链逐日解析，Records 之前的年份用人生档案的内存估算；一生收入走 `SummaryRules.lifetimeIncome`，未来收入可按固定比例下调）。界面：记录页“人生”尺度（距退休进度、阶段格子、阶段列表可选、未设退休时提示设置；一生时间分配卡含约合年数与一生税前收入；无 Plus 只显示锁）、月视图的“完善人生视图”邀请（可稍后）、人生档案编辑页（出生/入学/退休/睡眠，快速估算或详细经历，详细经历的起始日期用系统日期选择器并按相邻经历限制范围，未来收入保持或下调；收入隐藏时保存前确认本人）、“记录与数据”页的“人生档案”入口。设计系统加入 iOS 人生阶段五色。编辑页底部说明改为 Android 版（去掉 iCloud），新增文案 1 条（19 语言）。测试：人生规则 14 条（移植 iOS `LifeViewCalculatorTests` 的计算、阶段与收入用例）、档案草稿 7 条（含 `LifeEmploymentTimelineTests`）、职业生涯走查 1 条（约 1.3 万天 0.23 秒）。模拟器检查：设置档案、人生画布与分配卡（浅色与深色）、记录与数据入口。iOS 独立的 `LifeView`（周格页）没有任何入口，不移植。年视图展开（按月读汇总）与双指缩放切换尺度已补齐；单日页专注记录随 T18 完成。 |
| T18 | IMPLEMENTED | **T18a 今天与编辑**：`:core:domain` 的 `SessionFocusEnvironment`（计时会话即专注的班次来源：提前下班后无班次，强制工作日与手动计时视为工作日，设置取自档案的专注规划，缺省为 25/5/15/4）；`ShiftReminderPlan` 接受专注对健康提醒的接管。`:core:data` 的 `FocusStore`（iOS `FocusStore` 的命令面：开始、新建并开始、延长后开始、创建完成时间、停止、休息、跳过、到时收尾；启动与回前台时结转未完成、恢复已排计划、收尾离开期间结束的计时；已排计划队列存为本机文件；无 Plus 不开始任何计时）；`DeviceSettings` 加入专注通知开关与画布尺度。应用：`FocusCoordinator`（当前阶段开始时注册两条专注提醒；应用运行时在阶段结束或下一个已排计划开始时唤醒，不在后台轮询）；`TimerCoordinator` 随档案与 Plus 变化重排，并用计划中的休息替代固定健康提醒。界面：专注页“今天”尺度（当前格：锁定、进行中带倒计时与进度、当日完成、上班前、休息邀请、空闲；按比例绘制的班次色带，含标尺、现在指示、午休与装不下一格的尾段；200% 字体以上改为列表；今天的任务及其菜单；存为模板与清空当天）、新建任务（放进这一格或下一个空闲时段、立即开始、仅存为常用；选今天已有的任务；把这一格设为休息）、编辑任务、番茄钟设置（有模板时锁定时长）。测试：`FocusStoreTest` 5 条（离开期间结束后进入休息、手动停止不算完成、队列跨实例保留、无 Plus 不开始、队列编解码）。模拟器（API 36）检查：上班前与班内、放进一格、立即开始与停止、放入已有任务、编辑、改时长、无 Plus 锁定页、深色、200% 字体。与 iOS 一致：立即开始的计时不画在色带上；改时长后旧的计划格不再对应。**T18b 常用与模板**：`FocusPlanning.templateBlocks`/`templateDraftFromToday`（iOS `focusTemplateBlocks`/`focusTemplateDraftFromToday`：只取任务格的顺序与轮数，不带当天时刻，也不把手动设为休息的格子变成模板任务）、`FocusTemplates.remainingPomodoros`；“存为模板”改走与 iOS 相同的草稿路径。界面：专注页“今天/常用”切换（记在本机）；与 iOS 一样标题、切换与状态卡固定、只滚动画布（150% 以上字体时整页滚动），进入“今天”时滚到当前格；“常用”尺度（常用任务卡片，点按放进下一个空闲时段并回到“今天”，长按移除；常用的一天：从今天新建、编辑、用在今天、设为/取消每天自动使用、删除，装不下时提示；无 Plus 时为示例）；模板编辑页（名称、任务顺序可拖动把手，也可从菜单或无障碍操作上移/下移，三者走同一移动；装不下的任务标出；新增任务受剩余番茄数限制）与模板任务页（可设为常用，保存模板时一并写入）。专注提醒点开后进入专注标签页（冷启动与已在运行时均验证）。修正创建页预计结束时间：与开始同日只显示时刻，跨日才加日期（与 iOS 一致）。新增 Android 专有文案 2 条（上移/下移，19 语言）。测试：模板 3 条（移植 iOS `manualBreakStaysOnDayInsteadOfBecomingATemplateTask`、`remainingCapacity`，以及草稿保留顺序与轮数）。模拟器检查：新建模板、拖动与菜单排序、模板任务设为常用、设为每天自动使用、放置常用任务、当前格定位、有模板时时长锁定、无 Plus 示例、深色、200% 字体、通知入口。与 iOS 一致而未改：从常用任务放置会新建一个同名常用任务，常用列表出现两张同名卡片（两端共有，需一起改规则）。 |
| T19 | IMPLEMENTED | **T19a 备份与分享**：备份规则（`data_extraction_rules.xml` 与 Android 11 及以下的 `backup_rules.xml`）改为只包含 `records/` 与 `device/settings.json`：会话与专注队列（本机运行状态，会话还冻结了薪资）、提醒登记、调试开关与所有 SharedPreferences 都不进入云备份与设备转移，之后新增的文件默认也不进入。`session/ShareContent`（iOS `shareCopy`/`shareHeroText`/`shareProgress`/`shareURL`：只有时间与进度；链接为网页版 `off.rainif.com`，只带 `s=HHMM-HHMM`）。分享页（八种心情、按 iOS 固定尺寸 360×450 点 3 倍绘制的分享图，预览即同一张图；横屏与平板左右两栏，高度不够时只留文案；系统分享面板附图片与“文案 + 链接”，图片经仅限缓存 `share/` 的 FileProvider 临时授权）；计时页上班前/工作/午休/加班的操作栏与下班后页面加入分享（休息日与未排班无，与 iOS 一致）。测试：分享 4 条（移植 iOS `shareCopyBeforeClockInCountsToStart`、`shareURLStaysOnWebApp`，以及工作中进度与提前下班的完成态）。模拟器检查：工作中与提前下班后的分享图、换心情、系统分享面板的预览与文字、横屏两栏、深色。与 iOS 一致：分享链接打开网页版，应用不处理 https 链接，故不做 App Links。**T19b 桌面小组件**：`:core:domain` 的 `widget/`——`WidgetSnapshot`（共享 `WidgetSnapshotContract` schema 1 的 Kotlin 版：预先算好的区间，小组件只按时间挑选，区间内线性推进进度；过期或读不懂即为空）、`WidgetSnapshotComposer`（iOS `WidgetSnapshotComposer` 的移植：所有班次都来自 `ShiftSession.snapshot` 与 `ScheduleRules.widgetShifts`，排班下一次铺满一年：休息日倒计时、上班前、工作/午休/加班、今日已下班至零点；提前下班后当天剩余为已下班；手动计时只到结束日次日）与 `WidgetUpcoming`（“接下来”：当前班次沿用计时页的行，之后每个班次的上班、休息与下班，全程不含薪资）。应用：`WidgetCoordinator`（会话变化后重算，写入 `no_backup/widget/`，内容未变不重写不重绘；启动、回前台、改时间/时区时刷新；文案按应用语言生成，Android 12 及以下也一样）；Glance 1.2 小组件小/中/大三种尺寸（品牌标志、状态、系统自走秒的倒计时、进度条或进度环、下一时间点；大尺寸加“接下来”四行；无快照或已过期时提示打开应用），深浅色跟随系统，点按打开计时页；刷新用不唤醒设备的 RTC 闹钟，在区间结束时（进度变化中每 15 分钟）触发，已授予精确闹钟时准点，否则由系统放宽窗口。计时页“接下来”的文案抽成 `timelineWords` 与小组件共用。新增 Android 专有文案 3 条（取自 `public/locales` 的同名小组件文案，19 语言）。测试：小组件 13 条（移植 iOS `OffWorkStoreTests` 的小组件用例：午休、加班标签、休息日、接下来不含已过与 36 小时以后、休息日无虚构班次、以计划下班为目标、无需打开应用进入之后的班次、连续夜班、提前下班、进度推进、过期与编解码、不含金额）。模拟器检查：选择器、添加、小/中/大尺寸与改变尺寸、工作中与休息日、深色、点按打开计时页、刷新闹钟时间。与 iOS 一致：不对外开放 `offworkcountdown://`（只有小组件自己用显式 Intent 打开计时页）。**T19c 倒计时通知**（iOS 实时活动的 Android 对应，guide §8.3）：`session/OngoingPlan`（iOS `LiveActivityDecision` 与 `performReschedule` 的班次资格：进行中的专注或休息优先，其次仅在下班前 5/15/30 分钟窗口内显示班次；未设置/未计时、休息日、上班前、已提前下班或已下班不显示；下一次变化为窗口开启、阶段结束或下班）。应用：`OngoingCoordinator` 一条低重要度、静音、锁屏可见的常驻通知，系统计时器倒数到结束并由 `setTimeoutAfter` 自行消失；班次标题为“下班时间 17:00”（倒数的是钟面时间，不称为有效剩余），专注为任务名/短休息/长休息；点按打开计时或专注标签页；窗口开启与阶段结束用不唤醒的 RTC 闹钟（已授予精确闹钟时准点）；与 iOS 一样当天有已排专注时不单独显示下班倒计时。设置：班次提醒页“倒计时通知”（下班前显示，默认关，开始时间提前 5/15/30 分钟，默认 15；首次打开在 Android 13+ 请求通知权限，拒绝则关闭）；番茄钟设置“在通知中显示进行中的阶段”（默认开）；三项为本机设置。新增 Android 专有文案 4 条（19 语言，不使用“实时活动”说法）。测试：5 条（专注优先、窗口内外、窗口起止含加班、上班前/休息日/提前下班不显示、下一次变化）。模拟器检查：设置页、窗口内即显示、专注开始时切换为任务名、停止后回到下班倒计时、点按打开专注页、窗口前不显示且闹钟准点显示、下班时自动消失。首次设置流程中的倒计时通知开关、计时页与小组件“接下来”的专注计划行已补齐。锁屏 Chronometer、后台刷新与备份后重建仍需不同设备验证。 |
| T20 | IMPLEMENTED | 首发纯客户端 Play Billing：`PlusAccess`、`PlayBillingRepository`、`PlaySignature`、`EntitlementEngine` 与 Plus 页接入价格查询、购买/恢复、签名核验、pending、确认与重试；本机证据和待确认标记放 `noBackupFilesDir`，Debug 解锁不进 Release。Play Console 商品、公钥、许可测试购买、退款/续费与最终签名包验证尚未完成；见 `play-console-preparation.md`，不能据本地单测宣称实际购买通过。 |
| T21 | DEFERRED | 服务端验证，首发后（D-08 修订） |
| T22 | DEFERRED | Drive 同步，首发后（D-02 修订） |
| T23 | IN_PROGRESS | 首发 126 项 QA 的证据矩阵见 `preconsole-qa-2026-09-26.md`；自动化和部分 Pixel/模拟器检查已有证据，仍有设备、服务与 Console 阻塞项。 |
| T24 | IN_PROGRESS | 本地 lint、Debug/R8 Release/AAB、依赖和备份排除检查已有证据；本地版本/哈希及 16 KiB 对齐已核验；最终签名包、Play 预发布报告及完整设备回归待完成。 |
| T25 | WAITING_OWNER | 用户于 2026-09-26 同步：Play Console 的 KYC 身份验证仍在审核中。`store-listing.md`、`privacy-policy-addition.md`、`play-console-preparation.md` 已备本地草稿；1024×500 横幅、512×512 图标和真实页面截图已备草稿；正式隐私页与 Console 声明、素材审核、商品配置尚待完成。 |
| T26 | WAITING_OWNER | 实际 Play 测试轨道上传、签名、审核与发布需未来明确批准及 Console 条件；本轮未操作。 |
| T27 | DEFERRED | Wear，首发后（D-05） |

## 执行状态

| 项 | 状态 |
|---|---|
| Android 工程 | `:app`、`:core:domain`、`:core:data`、`:core:designsystem`；D-13 原子 JSON，无 Room |
| 自动化 | 最近完成的本地完整 Gradle：433 项通过（domain 336、data 74、design 8、app 15），lint 0 error / 34 warning / 1 hint，Debug、R8 Release 与 AAB 成功；`/tmp/doneat-boundary-final-gradle.log`。新增计时、专注合并与故障恢复回归；本轮无新增源码 lint 告警。 |
| 跨端与仓库 | 真实 iOS→Kotlin→iOS v6 往返保留 12 类实体；Swift fixture 12 项及数字输入 5 项、iOS headless build 通过。Web/Desktop build 与输出检查通过；npm lint、445 项测试、版本与 iOS 目录检查通过。字符串生成一致性检查通过。 |
| 设备 | API 36 上 Auto Backup 清除/恢复后记录与设置字节相同；系统文档化设备转移/重装路径恢复业务数据与设置字节相同，且排除了 device-local/no_backup 测试标记和 Debug Plus。`bmgr restore` 直接传输返回 -1000，不能算恢复成功。Pixel 已覆盖安装最新候选 APK，Records 各尺度往返与后台 90 秒后回前台已检查，业务档案字节未变；完整真机矩阵仍待完成。 |
| Play Console | 用户于 2026-09-26 确认 KYC 身份验证进行中，尚未通过。代理未登录核验；商品、公钥、许可测试、签名与应用审核尚无完成证据。 |

## 下一任务

KYC 等待期间继续推进以下工作；Pixel 已完成本轮导航/前后台回归，仍不等于完整真机验收：

QA-041/051 已同步修复并通过本地验收：非法金额不再被改成另一笔有效工资，历史职业结束日期和空档保持原样。

1. **继续性能与无障碍验收。** QA-019/023/062/067/077/140 本轮完成；下一批重点是大档案下 Records/Life 快速切换、取消过期计算与界面帧表现（QA-056），以及 TalkBack、最近任务和分享中的收入隐藏。真实云备份、物理换机和 Play 生命周期继续保留。
2. **继续代码审阅和远程 CI。** [PR #239](https://github.com/ififi2017/Off-Work-Countdown/pull/239) 已合并；[PR #240](https://github.com/ififi2017/Off-Work-Countdown/pull/240) 已合并 3.2.1 与 QA-041；本轮 Android 恢复修复使用 `codex/android-archive-recovery` 独立提交后续 PR。`63a05de1` 的全部远程检查已通过；新提交单独核对 CI。`ae0ec1f0` 和 `e2d874c` 的 Android、Web/Desktop、Rust macOS/Windows 和 Xcode Cloud iOS/watchOS 检查全部通过；后续修复追加独立提交，每次以对应提交的 CI 为准。
3. **完成发布资料的本地准备。** Android 隐私补充已落实到官网本地分支 `codex/android-privacy-policy`（`23ba61b`），英中页面 check/build/SEO 检查通过；用户 2026-09-27 要求暂不上线，未推送、提官网 PR 或发布。继续准备商店文案、素材与审核说明；正式页面发布留到 Android 准备上架时重新核对。Console 填报和签名身份仍按发布流程处理。

KYC 通过且 Console 具备相应操作条件后，再核对应用 ID、Play App Signing、商品/价格/公钥，完成测试轨道接入和真实购买生命周期测试。T26 的实际上传与发布按后续授权执行。KYC 验证进度不等于应用审核或购买验收结果。

126 项首发用例逐项状态以 [`preconsole-qa-2026-09-26.md`](preconsole-qa-2026-09-26.md) 为证据矩阵；本页只记录任务状态，不把 433 项单测写成 126 项全通过。

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
| 2026-09-26（本地收口） | `47fef18e` 计时秒边界刷新；`a6a6c382` Web 工时计算器 | 与上一轮相同；本轮不修改共享规则，也不推进 `9252fdfdc66aab88b4acb7493684f11991fd773d` 基线。秒边界刷新留在跨端计时回归，Web 工具不进入原生 UI。 |
| 2026-09-27（边界/恢复） | `63a05de1` 薪资校验；`e2d874cf` 职业区间；`9f09fb43` 性能标记、`56817311` 排班预览缓存、`76d248e0` 计时行缓存；另有 `47fef18e`、`a6a6c382` | QA-041/051 已包含；#241 的变化为 iOS 缓存、重复计算消除和性能测量，本轮不移植其实现、不移动固定基线。 |

## 2026-09-27 · 计时、专注合并与档案恢复

- 完成 QA-019/023/062/067/077/140：实际固定基线 Swift 方法核对显示取整；前台停顿/重新收集 90 秒后按当前绝对时间更新；午休和下班边界取消旧提醒且不虚构成果；两个独立档案经 v6 合并保留唯一会话及被替代历史；10,000 任务导入提交前/后杀掉独立 JVM 进程，重开只得到完整旧版或新版；并发备份读取完整提交版本。
- 修复此前只在数据层阻止写入、UI 仍显示空白记录的问题：损坏或较新版本本地档案在启动时显示恢复页，可重试；明确确认后将原件移为唯一 `.corrupt` 副本。复用现有 19 语言文案，不改归档协议。
- Android 四模块 433 项、lint、Debug/R8 Release/AAB、ZIP/ELF 16 KiB 检查通过；npm lint/445 项、版本与 iOS 检查、iOS headless build 通过。未做 iOS 视觉检查。日志 `doneat-boundary-*`、`doneat-recovery-*`，证据索引 `build/android-preconsole/README.md`。
- API 36 验证损坏/未来版本文件启动、重试/取消不覆盖、确认保留原字节、换回有效原件后重试恢复主界面；浅色正常字号、深色 320 dp / 200% 字号的页面与确认框已检查。测试后模拟器原文件逐字节还原。Pixel 最新 APK 的 Month/Week/Year/Life 往返及后台 90 秒后恢复通过，业务档案逐字节不变；精确倒计时跨下班状态由 JVM 测试证明，不把当前无分钟倒计时的真机页面当成该断言。
- QA 矩阵为 **79 PASS / 47 NOT_RUN**；KYC 仍按用户反馈处于验证中，真实 Play 与云端换机验收尚未完成。固定基线不移动。基于 #240/#241/#242 合并后的 main 单独提 PR；Android 源码与设备验收版本无差异。QA-041/051 已包含，新合入的 iOS 性能缓存与测量记录在上方漂移表，新 main 上仓库检查、445 项测试和 iOS headless build 已重新通过（`doneat-boundary-main-*`）。

## 2026-09-27 · 薪资输入与后续版本（QA-041）

- iOS/Kotlin 不再从非法输入中删掉负号、重复分隔符或超长尾数。草稿保留原文并显示 19 语言校验提示；仅规范的非负数写入薪资设置，空与零保持不同。逗号小数、阿拉伯小数分隔符和 Unicode 十进制数字仍可正常输入；人生薪资沿用必须大于零的规则。
- 打开从备份恢复的非法薪资原文本不会自动改写它；计算不把该文本当作有效金额。TS/Swift/Kotlin 同步拒绝日薪、收入比例、月薪折算与 Records 汇总的数值溢出。归档协议不变，规则 fixtures 已重新生成；原有排班样例保持不变，另加极值样例。
- Android 实际输入回归发现并修复离页丢失保存：薪资提交使用应用作用域，退出页时读取最新草稿，合法编辑可在返回或切换标签后保存。
- 验收：Android 423 项单测、lint（0 error / 33 warning / 1 hint）、Debug/R8 Release/AAB；npm 445 项、lint、Web/Desktop 构建与输出检查；iOS headless 构建、5 项数字输入与 12 项共享规则测试均通过。API 36 实际验证非法金额/年终奖不写入、逗号小数/零/清空正常保存、打开恢复值不改写；同页先完成、再改值并离页也保存最新输入；错误提示在 320 dp、200% 字号下完整显示。模拟器原 14 个文件逐字节恢复，应用停留关闭状态，本轮未改动 Pixel。日志为 `doneat-number-input-*`。未进行 iOS 手动视觉检查。
- QA 矩阵现为 73 PASS / 53 NOT_RUN，仍不能替代真机、云账户与 Play 许可测试。
- 用户确认 iOS 3.2.0 已发版，后续版本为 3.2.1；iOS/Watch 四个产物已核对为 3.2.1，Web/Desktop/Mac Widget 元数据按版本约定同步。Android 首发候选仍为 3.2.0 / versionCode 1。
- Play Console KYC 仍在验证中；本次跨端缺陷修复不移动冻结基线 `9252fdfd`。漂移结果仍为 `47fef18e`、`a6a6c382`。

## 2026-09-26 · PR 后续：保留人生职业区间（QA-051）

- 同步修复 iOS/Kotlin 编辑器：载入时保留明确的结束日期；已有空档不会在保存时被自动填满。原本相邻的经历继续随起始日期联动，新添经历沿用原先的自动衔接方式。
- 保存拒绝重叠、结束早于开始和多段未结束经历；显示 19 种语言的校验提示。明确删除一条无效经历后可继续编辑，未保存的旧档案不变。
- 回归：Android 420 项测试、lint 0 error / 33 warning / 1 hint、Debug/R8 Release/AAB 通过；Swift 7 项职业区间测试（其中一项含 3 组输入）、headless 编译通过；npm 442 项、lint、Web/Desktop 构建和输出检查、版本及 iOS/字符串检查通过。RecordJSON oracle 已按真实 Swift 重新生成；仅 LifeProfile 源码哈希改变，归档格式与 oracle 结果未改变。
- API 36 模拟器实际保存确认 `2020-01-01 → 2022-01-01` 的结束日期保持不变，下一份工作仍于 `2024-05-01` 开始；重叠样例显示提示并禁用保存。截图与日志在 `build/android-preconsole/life-*-edit-final.png`。未进行 iOS 手动视觉检查。
- QA 矩阵更新为 72 PASS / 54 NOT_RUN。Play Console KYC 仍按用户反馈处于验证中。本次是有记录的跨端缺陷修复，冻结基线仍为 `9252fdfd`；漂移命令结果仍为 `47fef18e`、`a6a6c382`。

## 2026-09-26 · Play Console 前的本地收口

- T11：导入拒绝数、删除失败、冲突候选持久化与双版本比较、陈旧选择拒绝、记录时区一次档案迁移均已实现。输入在解析前受 25 MiB、深度和容器数限制；真实 Swift 读取 Kotlin 导出的 v6 后，12 类实体完整一致。
- T17/T19：年展开、尺度切换、单日专注记录、首次设置倒计时通知开关及计时/小组件的专注“接下来”行已补齐。备份 include-list 已在 API 36 设备上验证清除/恢复与文档化转移/重装；不包含运行会话、SharedPreferences 与 `no_backup`。设备转移后新缓存可由应用/小组件重建，排除探针与 Debug Plus 没有恢复。真实 Google 云端账户与物理换机仍需验证。
- 视觉补漏：年度展开改用本地化月份缩写并随宽度/字号调整列数；320 dp、200% 字号下，设置值和薪资输入框换到标题下方，Plus 法律链接整项换行。班型名、薪资与专注任务均实测键盘弹出时可保存。模拟器真实双指验证 Week/Month/Year 缩放和 Life 不响应缩放。
- 首次设置验收：交替周草稿中途重启可恢复，最终确认前没有业务档案；拒绝通知后可完成设置并正常使用计时页，设置如实显示未授权，重入提醒页不会重复请求或误开常驻通知。中英文手机/平板、长德语与阿拉伯语 RTL 已做重点页面检查。模拟器原 14 个应用文件逐字节恢复，显示、语言、时区及备份测试设置已还原。
- T20：本地客户端 Billing 接入和状态机测试通过，真实商品和许可测试只能在 Play Console 配置后验证；不把模拟权益或 Debug 开关算作购买成功。
- T23/T24：完整四模块 417 项 JUnit、lint 0 error、Debug/R8 Release/AAB 和最近视觉修复后的重跑均通过；Web/Desktop build+输出检查、npm lint/442 项测试、check:version/check:ios、iOS headless build 与 12 项 Swift fixture 通过。对应日志和仍缺的逐项验收见环境锁与 126 项 QA 矩阵。Pixel 已覆盖安装候选 APK，解锁后的最终回归待完成。
- T25 的商店文案、隐私补充与 Console 准备为本地草稿；T26 未上传或发布。本地工件哈希见 `build/android-preconsole/artifact-hashes.txt`；Release APK/AAB 尚未配置正式签名，Play 处理结果待后续门禁。
- 本轮证据索引：`build/android-preconsole/README.md`；126 项首发验收中 71 项 PASS、55 项 NOT_RUN（其中包含已有部分证据的用例），不能据此宣布全量设备验收完成。免费导出/删除/恢复与恢复后权限隔离、精确提醒拒绝和撤权重建均已设备验证。
- 基线边界问题留在 QA-041/051：两端都会保留不可计算的薪资原文本；人生编辑器可能重连导入的重叠职业区间。本轮没有只改 Android 的归档/职业规则，当时保留待后续跨端处理；现已由上方 QA-041/051 补充记录完成修复与验收。

## 2026-09-26 · Android UI 反馈修正

- 首次设置：首屏补应用名；日程、提醒、隐私页补标准图标；短页居中、长页可滚动，末页放大标志。时间输入改用跟随应用主题的时分对话框（12/24 小时制、数字校验），午休时长改为步进控件。隐私页自动演示金额隐藏与锁定，并提供一次系统身份验证和跳过入口。页面切换与完成设置加入过渡，遵循减少动态效果设置。
- 导航与计时：主标签页直接切换并保留状态；子页和返回手势使用横向平移，关闭页面尺寸变换；数字滚动从 160 ms 调到 260 ms、位移从 60% 调到 30%，保留逐位模糊过渡。
- Focus / Settings：手机上的常用任务改为单列，宽屏自适应；Settings 与 Plus 同行。
- Records：尺度选择先更新画面，再在应用 scope 保存，避免离开页面取消写入；Month 始终可选，Year / Life 保留 Plus 门槛。月份点击不再等待双击窗口；Month / Year / Life 增加胶囊说明；跨尺度和跨标签返回 Life 保留已配置档案。
- 系统入口：Android 与 iOS 图标长按均提供计时、专注、记录；Android 冷/热启动路由消费待处理入口。Android 启动页采用与 iOS 一致的底部品牌组合；Android 12+ 的系统启动画面使用 branding 槽位。桌面图标确认已有前景、背景和 monochrome 三层 adaptive icon，无需替换为位图。
- 小组件：选择器独立展示 2×2、4×2、4×4，继续共用响应式渲染和刷新；提供 Android 15+ 生成式预览、Android 12+ XML 预览及旧版静态预览，包含深浅色。
- 自动检查：Android 全模块 340 项测试通过（domain 292、data 47、app 1），lint 无错误，Debug / Release 构建通过；`npm run lint`、`npm test`（442 项）、`check:android-strings`、`check:version`、`check:ios` 通过。iOS 本地 headless simulator build 与 2 项 `HomeQuickActionTests` 通过。未进行 iOS 视觉测试。
- 模拟器检查：英文首启流程、图标、时分输入、午休步进、锁定演示、末页；深色与 200% 字体；免费尺度反复切换、首次配置 Life 后重入、三种胶囊说明、Year 单击；排班修改后的返回手势录屏；计时滚动录屏；长按菜单和 Focus 路由；三种小组件预览及深色；冷启动品牌画面。使用隔离的模拟器数据，检查后恢复原数据和系统设置，未操作连接的真机。
- 仍未完成：真实 Play 购买仍属 T23/T25 的 Console 与许可测试；本轮 UI 检查不替代各厂商桌面、真机指纹/密码和商店购买验收。

### Pixel 真机补充：Records 无法返回首次尺度

- 真机复现后确认上一轮本地状态更新未解决根因：`RecordsScreen` 的局部函数引用捕获了首次组合的 `scale`，但 Kotlin `FunctionReference` 的相等性不比较这些捕获值。Compose 复用了旧点击回调，`next == scale` 把回到初始 Month 的操作当成重复选择；开启 Plus 也可复现。首次进入其他尺度时，同样可能无法回到该尺度。
- UI 回调改用普通捕获 lambda，令 Compose 在 `scale` / `anchor` 变化时更新点击处理；同屏的前后翻页、月份打开和人生编辑入口同步处理。保留重复选择保护，不改变权限或记录规则。
- 新增 `scripts/check-android-records-navigation.py`：使用显式设备序列号和英文 UI，直接点真实按钮并核对选中状态，覆盖返回初始尺度和 Week / Month / Year / Life 往返。只操作导航，不改记录、薪资或权益。Pixel 上旧 APK 实际失败为 `Tapped Month, but Year stayed selected`，用于确认回归能够捕获此问题。
- Android 全模块测试、lint、Debug / Release 构建以及本地无界面 iOS 模拟器构建通过。
- 覆盖安装修复 APK 后，同一台 Pixel 10 Pro 的相同脚本全部通过：Year → Life → Year → Month → Week → Month → Year → Month → Life → Month → Year。真机原有记录、薪资、人生档案和权益设置均未改动。
- 真机同时核对 Month 的实际日历内容和连续翻页：2026 年 9 月 → 10 月 → 11 月 → 10 月 → 9 月，均正确更新，验证结束后停留在 Month。


### 选中胶囊与预测性返回

- Records 的 Week / Month / Year / Life 胶囊改为随选中元素定位：优先上方，顶部空间不足时放到下方，并按实际文字尺寸避让图表边缘。Year / Life 保留具体点击格子的位置，同一月份或阶段内点击不同格子也会移动；点列表时使用对应月份或阶段的首个格子。
- 胶囊共用紧凑样式；文字立即更新，只有位置按现有 180 ms selection token 过渡，系统移除动画时直接定位。Life 的说明不拦截下方格子的点击。
- 预测性返回继续使用 Navigation 3 的 `predictivePopTransitionSpec`，明确启用系统回调，并根据 `NavigationEvent` 的左右边缘跟随手指。普通页面返回保持横向过渡。干净编辑页交给 NavDisplay 预览、取消和完成；需要放弃修改确认的编辑页仍保留确认。
- 编辑草稿在退出动画结束后清理；快速重开编辑页时保留新草稿，已离开的页面异步完成时不会再弹出上一页。
- 自动检查：Android 全模块 341 项测试通过（domain 292、data 47、app 2），包含胶囊边缘/大尺寸定位回归；lint、Debug / Release 构建及 iOS 无界面模拟器构建通过。未进行 iOS 视觉测试。
- Android 模拟器：中文免费 Month 胶囊三处日期位置不同，200% 字体不裁切，检查后恢复字体设置。
- Pixel 10 Pro：覆盖安装后，Month 的三处日期胶囊、Year 同月不同格子/跨月、Life 同阶段不同格子/跨阶段均随选中点移动。连续慢滑的中间帧确认左右边缘都会露出上一页；左边缘预览后取消仍停在 Hours & schedule，左右边缘完成均回到 Settings。另以临时排班草稿验证返回确认、继续编辑、丢弃与重新进入；原排班未写入任何变化。最终 Records 尺度导航脚本也全部通过，结束后停在 Month，并恢复 Pixel 原来的 60 秒熄屏设置。

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

## 2026-09-27 · 隐私草稿与性能检查

- 官网 Android 隐私补充已保存为本地提交 `23ba61b`，按用户最新指示暂不上线；本轮未操作 Play Console，KYC 状态不变。见 `privacy-policy-addition.md`。
- QA-056 仍未完成：`AllRecordsScreens.rememberVisible` 在 Compose 主线程首次读取 `recordDayIndex`，会遍历与排序档案；`RecordsQueries.walk` 为同步循环，目前没有协作式取消检查。已有 `withContext(Default)` 可阻止取消后的结果发布，但不证明 CPU 计算及时停止。下一轮应先补大档案与快速切换测量，再修复并验证。
- QA-124 保持未完成：D-09 在 decisions.json 中仍为 PROPOSED，现有薪资页会禁用最近任务截图；不能据此把所有敏感页面的截图与 TalkBack 保护记为已验收。QA 总数保持 79 PASS / 47 NOT_RUN。本轮未修改 Android 源码或 Pixel 数据。
