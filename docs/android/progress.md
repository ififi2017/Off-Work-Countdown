# Android 移植进度

**这是任务状态的唯一记录。** 交接包 `tasks.json` 只定义依赖、范围和验收，不记录状态。

更新：2026-10-07。交接包 1.2。原冻结源 SHA `9252fdfdc66aab88b4acb7493684f11991fd773d`。

## 任务状态

状态：NOT_STARTED → IN_PROGRESS → IMPLEMENTED → VERIFIED；另有 WAITING_OWNER、BLOCKED、DEFERRED。

| ID | 状态 | 证据 / 备注 |
|---|---|---|
| T00 | IMPLEMENTED | `baseline.md`。未 reset 工作区。QA-001 分支创建 NOT_RUN。 |
| T01 | IMPLEMENTED | `source-inventory.md`、`feature-parity.md`、`conflicts.md`。源读自固定 SHA。未跑 iOS XCTest。 |
| T02 | IMPLEMENTED | `wire-contract.md`、`synthetic-archives/`。检查：`node scripts/android-synthetic-archives.mjs --check`。Kotlin 导入 NOT_RUN。 |
| T03 | IMPLEMENTED | `environment-lock.md`；`src-mobile/android`；`.github/workflows/android.yml`。初始 T03 探针当时只有 domain 2 项测试、Debug/R8 Release/AAB 与模拟器冷启动；当前四模块与 448 项见下方执行状态。GitHub CI 运行证据另取，不以本地命令代替。 |
| T04 | IMPLEMENTED | `:core:designsystem`：`DoneAtColors`（浅/深两套完整 M3 配色，页面及卡片对齐 iOS 中性分组背景；默认强调色已按 2026-10-04 修正对齐 iOS：浅色 `#F2590A` / 深色 `#FF872E`，品牌亮橙仅作装饰）、`DoneAtStateColors`、`DoneAtShapes`（14/22 与 iOS 一致；主操作按下时胶囊收成 12 dp）、`DoneAtMotion`（与 `OWCMotion` 同值，减少动态效果时退化）、`DoneAtType.countdown`（64 sp 等宽数字）、`DoneAtCountdown`（逐位数字翻页，对应 `.numericText(countsDown:)`）、`DoneAtProgressMeter`（浮动百分比气泡，几何与 `OWCProgressMeter` 相同）、`DoneAtTheme`（主题模式、可选壁纸配色与自定义强调色）。对比度、气泡几何与强调色等 12 条单测；Debug 专用 gallery。模拟器（API 36）检查浅色、深色、200% 字体、移除动画、阿拉伯语 RTL、数字翻页录屏。Release 依赖全为稳定版（Material3 1.4.0）。见 `design-tokens-adr.md`。 |
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
| T20 | IMPLEMENTED | 首发纯客户端 Play Billing：`PlusAccess`、`PlayBillingRepository`、`PlaySignature`、`EntitlementEngine` 与 Plus 页接入价格查询、购买/恢复、签名核验、pending、确认与重试；本机证据和待确认标记放 `noBackupFilesDir`，Debug 解锁不进 Release。Play Console 商品与公钥已由用户提供，客户端接入年付 7 天试用；2026-10-04 Pixel / Play 111 的无收费月订阅购买、自动续订、取消后保留剩余权益及到期后前台查询回到免费已有实证；其他商品、退款、离线/恢复等矩阵未完成，见本日联调记录和 `play-console-preparation.md`。 |
| T21 | IN_PROGRESS | 2026-10-04 用户授权 Cloudflare Worker + D1（api.doneat.app）。Worker 与 Android 验签接入已实现；Worker/D1 已部署且真实 RTDN 测试通知接收通过；隐私已发布；Play 封闭测试包 111 已验证测试月订阅 RTDN、Google 精确到期、续订、取消和到期失效；115 真机签名回执授权、持续前台到期、到期后恢复，以及 USB 断网后的权益保留、到期前/后冷启动和前台离线到期已验证，其余购买矩阵待验，免费 CPU 预算尚未通过，见本日服务端验证记录。 |
| T22 | DEFERRED | Drive 同步，首发后（D-02 修订） |
| T23 | IN_PROGRESS | 首发 126 项 QA 的证据矩阵见 `preconsole-qa-2026-09-26.md`；自动化和部分 Pixel/模拟器检查已有证据，仍有设备、服务与 Console 阻塞项。 |
| T24 | IN_PROGRESS | 本地 lint、Debug/R8 Release/AAB、依赖和备份排除检查已有证据；本地版本/哈希及 16 KiB 对齐已核验；3.2.0 (2) 上传签名与 bundletool 校验通过，Play 预发布报告及完整设备回归待完成。 |
| T25 | IN_PROGRESS | 用户于 2026-09-28 确认 Console 已可上传、商家账号与商品配置完成；应用许可公钥已提供。`store-listing.md`、`privacy-policy-addition.md`、`play-console-preparation.md` 已备本地草稿；1024×500 横幅、512×512 图标和真实页面截图已备草稿；2026-10-04 正式隐私页与 Android 致谢已发布，月订阅商品查询和测试付款已有真机证据；Console 声明、素材审核与其余商品验收尚待完成。 |
| T26 | IN_PROGRESS | 用户已将 3.2.1 (111) 推上封闭测试，Pixel 的 Play 安装来源及无收费月订阅购买已核实。启用服务器回执的 115 已从 Play 安装并验证回执授权、前台到期、离线保留及到期前/后冷启动；完整 Play 验收待完成。 |
| T27 | DEFERRED | Wear，首发后（D-05） |

## 执行状态

| 项 | 状态 |
|---|---|
| Android 工程 | `:app`、`:core:domain`、`:core:data`、`:core:designsystem`；D-13 原子 JSON，无 Room |
| 自动化 | 自定义强调色整合后的四模块 448 项测试通过（domain 337、data 76、design 12、app 23），0 failure / error / skip；lint 0 error / 34 warning / 1 hint，Debug / R8 Release 通过。历史 AAB、测试与构建证据均保留在各自记录中。 |
| 跨端与仓库 | 真实 iOS→Kotlin→iOS v6 往返保留 12 类实体；Swift fixture、数字输入、Web/Desktop 构建及 iOS headless build 已有通过证据。本轮基于最新 main 再验证仓库与 Android 门禁。 |
| 设备 | 保留已有 Auto Backup、业务档案原子恢复及 Pixel 前后台验证；玻璃底栏及自定义强调色已在独立 Pixel Preview 包验收。真实云端换机、购买生命周期与完整无障碍矩阵仍待完成。 |
| Play Console | 用户于 2026-09-28 确认可上传，商家账号与商品配置完成，并提供许可公钥。许可测试购买和应用审核仍待完成；代理未操作 Console。 |

## 下一任务

Console 已具备上传条件，后续按以下事项推进：

QA-041/051 已同步修复并通过本地验收：非法金额不再被改成另一笔有效工资，历史职业结束日期和空档保持原样。

1. **继续性能与无障碍验收。** QA-019/023/062/067/077/140 本轮完成；下一批重点是大档案下 Records/Life 快速切换、取消过期计算与界面帧表现（QA-056），以及 TalkBack、最近任务和分享中的收入隐藏。真实云备份、物理换机和 Play 生命周期继续保留。
2. **继续代码审阅和远程 CI。** [PR #239](https://github.com/ififi2017/Off-Work-Countdown/pull/239) 已合并；[PR #240](https://github.com/ififi2017/Off-Work-Countdown/pull/240) 已合并 3.2.1 与 QA-041；本轮 Android 恢复修复使用 `codex/android-archive-recovery` 独立提交后续 PR。`63a05de1` 的全部远程检查已通过；新提交单独核对 CI。`ae0ec1f0` 和 `e2d874c` 的 Android、Web/Desktop、Rust macOS/Windows 和 Xcode Cloud iOS/watchOS 检查全部通过；后续修复追加独立提交，每次以对应提交的 CI 为准。
3. **完成发布资料的本地准备。** 将 Android 隐私补充落实到官网代码，定稿商店文案、素材选择和审核操作说明；正式发布页面、Console 填报和签名身份仍按发布流程处理。

应用 ID、商品标识与公钥已确认；下一步在 Play 测试轨道验证本地价格、试用资格和完整购买生命周期。用户自行进行 Console 上传和发布，代理尚未操作。账户具备上传条件不等于应用审核或购买验收通过。

126 项首发用例逐项状态以 [`preconsole-qa-2026-09-26.md`](preconsole-qa-2026-09-26.md) 为证据矩阵；本页只记录任务状态，不把单测通过数量写成 126 项全通过。

环境与命令见 `environment-lock.md`。当前源码配置：`applicationId=com.rainif.doneat`（用户已确认 Console 标识），minSdk 26，versionName 3.2.1，versionCode 5；此前已交付的 3.2.0 包体保留原身份，详见各次构建记录。

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

## 2026-09-28 · Play 商品配置与年付试用

- 用户确认订阅 `doneat_plus`、基础方案 `monthly` / `yearly`、年付优惠 `yearly-trial-7d`、终身商品 `doneat_plus_lifetime` / 购买选项 `lifetime` 均已配置并激活。年付优惠为 7 天免费，Play 资格为“从未订阅过此内容”。价格以 Play 返回为准。
- 已校验用户提供的许可公钥为 2048 位 RSA；七项公开构建配置保存在仓库外的本机 Gradle 配置。上传密钥保持使用首次 AAB 的 `doneat-upload`，密钥和密码均不入库。
- 客户端补齐年付试用选择、19 语言的试用后年费披露、指定终身购买选项，以及付款前重新查询和条款变化时重新确认。版本号保持 3.2.0，versionCode 升为 2。模拟价格只用于 Debug 设计图库，不提供购买或授权。
- 基线漂移检查：`f0ddbdb2`、`76d248e0`、`56817311`、`9f09fb43`、`63a05de1`、`e2d874cf`、`47fef18e`、`a6a6c382`。本轮仅处理 Android Play 购买接入，不推进冻结 iOS 基线。
- 自动检查：四模块 429 项测试、lint（0 error / 33 warning / 1 hint，无新增警告）、Debug / R8 Release / AAB、npm lint / 453 项测试、版本检查与 iOS headless build 通过。未做 iOS 视觉检查。
- Android 模拟器使用实际购买按钮组件和明确标记的示例价格检查英文浅色、中文深色、德文 200% 字体，试用后年费与取消说明未截断。最终构建再次检查中文深色；截图见 `build/android-play-internal/billing-v2/ui/`。未操作连接的真机，未发起交易。
- 交付 `build/android-play-internal/billing-v2/DoneAt-3.2.0-2-internal.aab`（9,425,548 字节），上传签名严格校验、bundletool 结构、包名与版本、Release 清单及 Release APK 16 KiB ZIP 对齐检查通过。SHA-256 为 `5a51801df2055e5de7ad18c4dd43cc7973ec3ddfc5c7bc027ae76432a9cafab8`；日志、清单与校验记录在同目录。
- 真实 Play 返回、购买／试用续费／恢复／撤销仍需要许可测试账户验收；本地测试不代表这些项目通过。

## 2026-09-28 · Google Play 英文商品详情与截图

- 英文文案改用仓库 ASC 3.2.0 元数据为底稿，按 Android 的小组件、常驻通知、系统备份和 Play 订阅／7 天年付试用调整；移除 Apple Watch、iCloud、Dynamic Island 和 Apple EULA。标题 28、简短说明 74、完整说明 2,358 字符。
- 复用 ASC 3.2.0 的字体、背景、标题与前两张连幅模板，重新拍摄 Android 工作中计时、排班月历、年度记录、有任务且运行中的 Focus、休息中计时。输出 6 张英文 1080 × 1920 不透明 RGB PNG，按编号上传；总览仅供检查。
- 截图来源为 API 36.1 只读临时模拟器，Android 3.2.0 / versionCode 2 Debug APK；全部为虚构数据。Plus 演示使用现有 Debug 开关，未修改应用源码或购买逻辑，未操作真机。原始截图、UI 树、素材哈希与来源说明在 `build/android-play-internal/store-listing/asc-style/`。
- 渲染脚本 ESLint、Node 语法、输出尺寸／透明度／文件大小检查通过，并实际查看原图、总览和成品。仓库版本检查通过（并行工作已将 Web／Desktop／iOS 对齐到 3.2.1；本次截图 APK 仍为上述 3.2.0 / 2）。本轮仅修改营销脚本和文档，未运行应用构建或 iOS 视觉测试。
- 本轮未调用 ASC 或 Play Console 写入接口，也未验证真实购买；素材可用于当前默认英文商品详情。

### 置顶大图重新排版

- 根据用户对旧紫色版本的反馈，改用 ASC 同款米白背景、衬线主标题、小品牌标识和真实 Android 倒计时裁切画面。主标题为 “After work, time for you.”。
- 输出 `build/android-play-internal/store-listing/feature-graphic-en-1024x500.png`，同步替换旧 PNG 路径并加入英文素材 ZIP。1024 × 500、不透明 RGB、文件大小检查、ESLint 和实际图片检查通过；未上传到 Play。

## 2026-09-29 · Play 边到边警告排查与 Release 启动修复

- 用已上传的 3.2.0 (2) AAB 内置 mapping 和实际 DEX 还原 Console 报告：`pg0.b` / `rg0.b` / `tg0.b` 分别为 AndroidX Activity 1.13.0 的 `EdgeToEdgeApi26/29/35.setUp`；`o1.l` 是 Api28 分支设置 `SHORT_EDGES` 的 R8 合成方法。Api30 及以上使用 `ALWAYS`，Api35 仍有被弃用的透明系统栏颜色调用。Activity 1.13.0 已是当前稳定版，没有为消除静态警告改写 Google 的兼容实现。
- 应用已经在 `MainActivity` 调用 `enableEdgeToEdge()`，主题切换同步系统栏图标，页面使用 `safeDrawingPadding` / Material3 导航组件。API 36.1 临时模拟器上的窗口实际为 `layoutInDisplayCutoutMode=always`；首启、计时/设置深浅色、手势/三键导航、横屏模拟刘海未发现系统栏遮挡；薪资输入框在数字键盘弹出后仍可见且可输入。Android 15 及更早版本、厂商真机尚未在本轮验证。
- 此轮安装与 AAB DEX 相同的非调试 Release APK 时，另行复现了启动崩溃：`WorkDatabase_Impl.<init>()` 被 R8 严格模式移除，WorkManager 在 Activity 之前初始化失败；清除临时应用数据后仍复现。Room 2.6.1 的 consumer rule 只保留类，新增精确规则仅保留数据库的无参构造方法，保持压缩和混淆开启。
- 新增 `scripts/check-android-release-startup.py`，要求显式设备序列号和非调试包，并检查冷启动后真实 UI 和存活进程；旧包失败，修复包干净首启和保留设置后的冷启动均通过，最终 crash buffer 为空。Release 启动检查补入发布 runbook，Debug 截图和编译通过不能替代它。
- 四模块 429 项测试通过（0 failure/error/skip），lint 0 error / 33 warning / 1 hint，Debug / Release / AAB、版本一致性和 iPhone 18 Pro 的 iOS headless build 通过。未做 iOS 视觉检查。验证只使用隔离 Android 模拟器，未操作真机。
- 新候选 `build/android-play-internal/release-v3/DoneAt-3.2.0-3-internal.aab`，沿用原上传密钥、3.2.0 / versionCode 3。9,634,314 字节；SHA-256 `57b414119ef2d73d4f45804d518ec1f061d23da68193607a9a6b47bdccc5ad45`。严格签名、bundletool 结构/清单、Release APK 16 KiB ZIP 对齐通过，受测 APK 与 AAB 的 DEX 一致。
- 证据：`build/android-play-internal/edge-to-edge-audit/`（旧包崩溃、mapping、构建日志、UI 截图/树/窗口信息）；包体与说明在 `release-v3/`。边到边静态警告可能继续存在；未上传新候选、未验证 Play 处理后的 split APK 或真实购买。

## 2026-09-29 · Android Plus 排版与 HyperOS 小组件排查

- 用户明确要求参照 iOS 订阅页，本轮打开 iPhone 18 Pro / iOS 27 模拟器确认实际页面。Android 改为标题与介绍、紧凑权益列表、年付/月付/终身选项卡、一个购买按钮；默认年付，价格与试用资格仍来自 Play。试用后年费在购买按钮前披露；无资格时不显示试用入口。小屏及大字号改为纵向卡片，不省略价格。Android 专用介绍覆盖 19 语言，不宣传尚未接入的 iCloud。
- Debug 图库复用完整 Plus 页面，用明确标记的示例价格检查选择和购买回调，不创建真实交易或赋予权益。Release 保持原 Billing 查询、签名校验和购买前重新确认逻辑。
- 设备反馈为 22041216C / HyperOS 2、Play 封测 3.2.0 (3)，用户确认选择器只显示 2×2。核对该版本 AAB 的最终清单，三个 provider 均存在；源码也已声明双向缩放与 2×2/4×2/4×4 默认尺寸。不能归因于旧包缺少入口，尚无这台手机的系统 provider 列表或桌面运行证据。
- 三个 receiver 的原 label 均为 DoneAt。现分别显示 DoneAt · 2×2 / 4×2 / 4×4，保留组件身份和尺寸/刷新逻辑，便于辨认和复测。小米规范确实说明同名 label 会聚合，但描述的是小米 Widget；尚未证明这就是本次标准 Android 小组件只显示一个的原因，不标记为 HyperOS 修复完成。
- 接入小米小部件中心所需的独立进程、刷新、尺寸、审核及 DoneAt 的 Glance/WorkManager 边界记录在 `docs/android/widget-compatibility.md`。本轮没有加入未验证的小米 metadata 或修改 widget 进程。
- 本轮基线漂移仍为 `f0ddbdb2`、`76d248e0`、`56817311`、`9f09fb43`、`63a05de1`、`e2d874cf`、`47fef18e`、`a6a6c382`；用户授权参照 iOS 视觉，不推进冻结行为基线。
- 自动检查：四模块 429 项测试（0 failure/error/skip）、lint（0 error / 33 warning / 1 hint）、Debug / R8 Release / AAB、npm lint / 453 项测试、版本检查、iOS headless build 通过。修改后的图库也已重新编译。
- API 36.1 隔离模拟器：实际 Plus 页面组件的英/中文深浅色、德文 200% 字体及 320 dp 宽度、三档选择与各自购买回调、无试用资格、离线和已有权益状态通过；示例价格均明确标记。切换语言时曾在应用尚未重启完成前读取到桌面，等待真实应用出现后重跑通过。Pixel 桌面选择器确认三个尺寸入口分别显示，不能替代 HyperOS 真机验收。
- 最终非调试 Release 冷启动检查通过，真实 Settings → Plus 页面及底部导航实际查看无重叠；该隔离环境不能连接已登录的 Play 商店，正确显示暂不可用、重试和恢复购买。AAB 与受测 Release APK 的 DEX 一致；严格上传签名、bundletool、清单版本及 16 KiB APK ZIP 对齐通过。
- 新候选 `build/android-play-internal/release-v4/DoneAt-3.2.0-4-internal.aab`：3.2.0 / versionCode 4，9,654,274 字节，SHA-256 `759c5cb405f0cb06c630de0dc4cb663009cb2a25dac0cd164df804833a7b65b5`。沿用原上传密钥，旧包保留。证据在 `build/android-play-internal/plus-redesign/`；本轮未上传 Play、未发起交易、未操作连接的真机。

## 2026-09-29 · Plus 已订阅彩蛋补齐

- 上一版只对齐了购买前页面，遗漏 iOS `PlusSubscriberThankYouView`。本轮按用户要求继续对照实际 iOS 已授权页，补品牌时钟、感谢文案、当前方案/终身卡片和订阅管理入口。复用既有 `CelebratingBrandMark` 与 19 语言文案，不新增图像资产或动效库。
- 刚获得权益时自动播放一次；已是会员时进入页面保持静止，点时钟直接重播。延续既有 1.8 秒、720° 品牌动效与系统触感，开启减少动态效果时保留轻淡反馈；后台、离页和动效设置变化取消播放及后续触感，繁忙时跳过错过的刻度。
- 修复 `PlusFor` 刚获得权益就自动离开页面的遗漏：初次获得权益后停留感谢页，点“继续使用 Plus”才恢复原功能；原本已有权益的入口继续直接通过。返回行为和权益校验仍由原路径处理。
- 方案展示额外保留“已有终身且仍有订阅”的事实，复用同一已验证订阅判断及离线有效期，避免误显示“没有需要管理的订阅”。新增 2 项回归，覆盖终身与订阅并存、待批准/暂停和离线过期。
- Debug 图库增加订阅/终身/二者并存及模拟购买成功预览，只改变图库界面，不授予真实权益、不调用 Play 交易。
- 冻结基线未推进；漂移命令仍得到 `f0ddbdb2`、`76d248e0`、`56817311`、`9f09fb43`、`63a05de1`、`e2d874cf`、`47fef18e`、`a6a6c382`。本轮是用户明确要求的 Plus 视觉/交互补齐。
- 验证：四模块 431 项测试（0 failure/error/skip）、lint（0 error / 33 warning / 1 hint）、Debug / R8 Release / AAB、版本检查及 iOS headless build 通过。API 36.1 隔离模拟器实际检查订阅/终身深浅色、二者并存、点按重播、后台中断、模拟购买后自动播放与继续、系统动画倍率 0、320 dp 德文 200% 字体。模拟交易仅用于图库，不替代真实 Play 交易；真机触感尚未验证。
- 非调试 Release 冷启动检查通过；crash buffer 仅含此前 UI 自动化 dump 的连接超时记录，未出现 DoneAt 崩溃。受测 APK 与 AAB 的 DEX 一致。上传签名、bundletool、清单版本和 16 KiB APK ZIP 对齐通过。新候选 `build/android-play-internal/release-v5/DoneAt-3.2.0-5-internal.aab`：3.2.0 / versionCode 5，9,675,876 字节，SHA-256 `f88784f16719eefc07c9cee9c0a5b41669299badbc97e6bfb765b7af9de8cec3`。证据及视频在 `build/android-play-internal/plus-celebration/`，双语版本说明在 `release-v5/`；未上传 Play。

## 2026-09-29 · 玻璃 Tab 栏与主题渐变（替换未上传 Build 5）

- 用户确认旧 Build 5 尚未上传，要求保留构建号 5；旧候选及校验资料已备份至 `build/android-play-internal/release-v5-before-glass/`。
- 用户授权接入 AndroidLiquidGlass，底栏参照 iOS 胶囊形状及选中态；固定 Backdrop 2.0.1 / Shapes 1.2.1，许可证随包附带并接入致谢页。主体卡片和 Android 导航行为保留。
- 滚动页面末尾及固定底部操作使用统一实测底栏间距，键盘显示时隐藏底栏；宽屏/矮屏仍使用导航侧栏。新增 Debug 玻璃底栏预览，复用生产组件。
- 主题切换增加既有 phase 280 ms 颜色过渡，保留页面状态并支持中断重定向；系统移除动画时直接切换。
- 冻结基线不推进；本轮漂移仍为 `f0ddbdb2`、`76d248e0`、`56817311`、`9f09fb43`、`63a05de1`、`e2d874cf`、`47fef18e`、`a6a6c382`。

- 用户进一步明确要按住 Tab 后出现可拖动的放大玻璃透镜。本轮参考上游 `LiquidBottomTabs` 的三层绘制实现按压放大、跟手移动、松手选择；拖动期间页面不切换，离开底栏取消或切后台收回。修复真机反馈的选中区域透明、放大透镜被底栏圆角裁切，以及 RTL 位置反向。隐藏采样层不提供触摸或读屏节点。
- 2026-09-30 真机验收：无线 ADB 连接 Pixel 10 Pro / Android 17，使用独立 `com.rainif.doneat.preview`，保留已安装的 Play 版及其数据。通过浅/深色、按住放大与松手选择、德文 200% 字体、阿拉伯语 RTL、减少动态效果、壁纸配色、真实四个主页面、设置子页返回栈、系统返回、远离底栏取消和后台恢复。减少动态效果时，静止与按住截图一致。只通过 Preview 自身首启流程建立测试设置，没有导入正式数据。
- 按用户要求停止使用模拟器做后续视觉检查；本轮已启动的 Android / iOS 模拟器均关闭。后续优先真机，现有无线连接用任务独立的 ADB 服务端口 5049。
- 自动检查：四模块 432 项测试（0 failure/error/skip）、lint（0 error / 33 warning / 1 hint）、Debug / R8 Release / AAB、稳定依赖、版本检查、diff whitespace 通过；本轮所需 iOS headless build 已通过。签名严格校验、bundletool、清单版本、内置许可证、16 KiB APK 对齐和生产 APK/AAB DEX 一致性通过。
- 独立包名的非调试 R8 Release Preview 在真机上通过保留设置的冷启动、Tab 拖动和按住时后台中断检查。它与生产 AAB 的 applicationId 不同，不把这项验收表述为已验证 Play 处理后的包体。旧系统、HyperOS 和真实交易仍需对应环境验收。
- 已替换 `build/android-play-internal/release-v5/DoneAt-3.2.0-5-internal.aab`，保留 3.2.0 / versionCode 5。9,751,050 字节，SHA-256 `601380489f60db01dfead659a4f44ccd2df56c27816e781c1b83c1eb729c2137`。旧包备份哈希复核通过。双语版本说明及 README 同步更新；真机截图、测试日志与 `phone-release-glass-drag.mp4` 位于 `build/android-play-internal/glass-tabs/`。未上传 Play。


## 2026-09-30 · Android 变更同步 PR

- 从 `origin/main` 的 `be4bce56` 创建独立分支 `codex/android-play-glass`，同步本轮 Play 优惠、Plus 页面及彩蛋、玻璃 Tab/主题过渡、Release 启动修复、小组件标签和商店素材脚本。原 `feat/promo-video` 工作区的 iOS、营销视频与本机 IDE 修改保持原样。
- 保留主分支已有档案恢复与计时性能修复；按最新 `Localizable.xcstrings` 重新生成 Android 19 语言资源。当前源码为 3.2.1 / versionCode 5，此前交付的 3.2.0 (5) AAB 未覆盖、未上传。
- 重新验证：四模块 443 项测试（domain 337、data 74、design 9、app 23，0 failure / error / skip）；lint 0 error / 34 warning / 1 hint；Debug / R8 Release / AAB 与稳定 Compose/Material3 依赖检查通过。npm lint、44 文件 / 453 项测试、版本检查、两份营销脚本的 Node 语法与启动检查脚本的 Python 语法通过。iOS 无界面模拟器编译通过，未进行 iOS 视觉检查。日志保存在本机 `build/android-pr-sync/`。
- 本轮无线真机未连接，没有对整合后的构建追加设备视觉或 Release 冷启动验收；上一节 Pixel Preview 验收属于当时的构建。真实 Play 交易、HyperOS 和旧系统仍待对应设备验收。
- 漂移命令新增 `94fefaa9`（iOS 日历涂色与年度班次范围），其余仍为 `f0ddbdb2`、`76d248e0`、`56817311`、`9f09fb43`、`63a05de1`、`e2d874cf`、`47fef18e`、`a6a6c382`。本轮不改排班业务规则、不推进冻结基线；新增排班移植由独立 PR #249 处理。


## 2026-09-30 · Android 自定义强调色与 iOS 背景对齐

- 在“设置 → 主题”增加八种常用色、恢复 DoneAt 橙色和自定义颜色。自定义对话框使用稳定 Material3 HSV 滑块与六位 HEX 输入；保存才应用，取消保留当前设置。选择颜色关闭壁纸配色，壁纸开关保留之前的颜色；沿用现有 280 ms 主题过渡与减少动态效果行为。
- 强调色仅保存到 Android 本机 `DeviceSettings.accentColor`，不修改 RecordJSON、同步协议或业务规则。旧设置及非法色值安全回退；按浅/深色调整用于文字的明度，通过 RGB 采样立方体的对比度检查。新增文案完整覆盖 19 语言并重新生成资源，无新依赖。
- 页面和卡片背景按 `OWCDesign.page/card` 对齐：浅色 `#F2F2F7` / `#FFFFFF`，深色 `#000000` / `#1C1C1E`。依据已有 iOS 27 浅色参考截图核对像素；本轮没有启动 iOS 模拟器进行视觉检查。自定义色和壁纸配色都保留中性背景。
- 自动检查：四模块 448 项测试（domain 337、data 76、design 12、app 23，0 failure / error / skip）；lint 0 error / 34 warning / 1 hint；Debug 与 R8 Release 构建通过。npm lint、44 文件 / 453 项测试、生成资源与版本检查通过；iOS 无界面模拟器编译通过。日志为本机 `build/android-pr-sync/accent-*`。
- 物理 Pixel 10 Pro / Android 17（API 37）通过无线 ADB 5037 使用独立 `com.rainif.doneat.preview` 验收：浅/深色背景、预设色、HSV 调节、HEX 输入与无效输入、取消、真实主界面保存与进程重启恢复、恢复默认色、壁纸开关保留颜色，以及玻璃底栏跟随强调色。微信输入法实测 A–F 直接输入成功；HEX 保持可见。德文实际系统 200% 字号下对话框可完整访问并可滚动，阿拉伯语布局镜像且 HEX 输入/格式提示保持正确顺序，减少动态效果探针通过。未启动 Android 模拟器。
- QA 截图和 UI 层级位于本机 `build/android-pr-sync/accent-qa/`。完成后 Preview 语言恢复为 `zh-CN`，系统字号恢复原值 1.0；正式 Play 应用及其数据保持原样。该设备验收针对 Debug Preview，不表述为 Play 处理后的包体验收；旧系统、HyperOS 与真实交易仍待对应环境验证。
- 基线漂移命令复核为 `94fefaa9`、`f0ddbdb2`、`76d248e0`、`56817311`、`9f09fb43`、`63a05de1`、`e2d874cf`、`47fef18e`、`a6a6c382`，冻结基线不推进。变更继续同步到 [PR #250](https://github.com/ififi2017/Off-Work-Countdown/pull/250)。当前源码仍为 3.2.1 / versionCode 5；此前交付的 3.2.0 (5) AAB 未覆盖，本轮未生成新的签名 AAB 或操作 Play Console。


## 2026-09-30 · Android 真机巡检与交互修复

- 按用户授权使用已连接的 Pixel 10 Pro / Android 17（API 37）巡检四个主页面、排班设置、专注编辑与 Plus 页面。继续使用独立 `com.rainif.doneat.preview` 和合成数据，正式 Play 应用保持原样。
- 用户报告订阅页出现 App Store；真机确认为 FREE 且未返回可购方案时误用 iOS `plusUnavailable`。改用 Android 专用 Google Play 提示，补齐 19 语言并重新生成资源；新增回归扫描实际 Android Kotlin 引用的字符串，阻止各语言混入 App Store 文案。没有改动 iOS 文案。
- 修复从记录或专注进入 Plus 后返回到设置的上下文丢失。受限功能触发的 Plus 页面现在留在来源 Tab 的返回栈，返回按钮读屏名称也指向来源；继续操作先弹出来源 Plus 页面，再恢复原功能。真机分别检查系统返回、页面返回和 Debug 权益变化后的“继续使用 Plus”，不发起真实交易。
- 专注任务草稿与番茄钟设置此前使用普通 remember，切换 Tab 后未保存编辑丢失。三个任务编辑入口使用同一原生 saveable saver，六个设置草稿值使用 rememberSaveable；不提前写入业务档案。真机确认任务标题/番茄数量跨 Tab 及系统字体变化引起的 Activity 重建保留，取消返回丢弃；番茄钟设置跨 Tab 保留未保存数值。新增一项单元回归覆盖全部任务草稿字段及可空标识。
- 自定义强调色补齐 Material3 secondary/container 前景角色，分段选择、tonal 按钮和滑块轨道跟随所选颜色，保留中性背景和语义状态色。专注休息标签/图标使用可读的中性前景，保留青色轨道和填充。无排班的专注页面移除重复提示，提供工作时间与排班入口；任务加减按钮读屏名称区分方向，图标触摸区域采用已有 48 dp token。
- 自动检查：四模块 449 项测试（domain 337、data 76、design 12、app 24，0 failure/error/skip），lint 0 error / 34 warning / 1 hint，Debug / R8 Release 构建通过。npm lint、44 文件 / 454 项测试、资源与版本检查通过；可用 iPhone 18 Pro 目的地的 iOS headless build 通过，没有启动模拟器进行视觉检查。日志及真机截图在本机 `build/android-pr-sync/phone-audit-2026-09-30/`。
- 真机追加确认专注示例的深浅色休息标签、英文 Google Play 提示、德文实际 200% 字号下滚动可访问提示/重试/恢复，以及阿拉伯语 RTL。测试后 Preview 恢复为中文、浅色、非会员，系统字号恢复原值 1.0。发现德文 200% 字号时底栏长标签换行较碎，记录为后续导航布局改进；本轮没有改变该布局。该检查针对 Debug Preview，真实 Play 交易、旧 Android 与 HyperOS 仍需对应环境验收。
- 冻结基线未推进，漂移仍为 `94fefaa9`、`f0ddbdb2`、`76d248e0`、`56817311`、`9f09fb43`、`63a05de1`、`e2d874cf`、`47fef18e`、`a6a6c382`。源码仍为 3.2.1 / versionCode 5，修复继续同步到 PR #250；此前签名的 3.2.0 (5) AAB 未覆盖，本轮未生成新的签名 AAB 或操作 Play Console。


## 2026-10-02 · 同步 iOS 计划 020：免费加班一行与请假规划

- 云端会话从最新 main 建分支 `claude/android-plan-020-dw7cnx`。此前 Mac 线程未推送的工作不可达，本轮从零移植。网络策略拒绝 `dl.google.com`，本地只能用仓库外的纯 JVM Gradle 根编译和测试 `:core:domain` 与 `:core:data`。
- **免费加班一行**（iOS PR #254）：`RecordsQueries.recordedOvertimeMs` 与 `lifetimeRecordedOvertimeMs`，免费用户在周/月/年显示一行已记录加班，人生尺度对所有人显示一生已记录加班（每天只计一次）。新增 1 条测试。
- **请假叠加与规划**（iOS PR #251/#252）：规则见 `rule-parity.md`。已采用的请假（包括从 iOS 导入的）在倒计时、提醒、小组件、汇总与 Records 中不再算作上班。界面：设置“班次”组新增“休假”（显示剩余天数）；休假页（规划入口、余额、已采用计划）、余额编辑（类型、自定义名称、额度与已用、有效期）、规划表单（至少休 N 天或最多用 N 个半天、日期范围限于滚动一年、余额选择）、方案列表、方案详情（日历以图标加底色标出休息/节假日/请假/半天，请假时间、余额剩余、前后班次、估算说明，整体采用）、已采用计划（单日取消、撤销整份）；Records 月视图“规划休假”入口（无余额时先引导建立）；排班日历在请假日加标记并可进入休假页；Plus 权益加入休假。免费用户每次打开方案消耗一次（本机计 3 次），用完进入 Plus 并在购买后回到该方案。所需文案此前已随 iOS 生成到 19 语言，本轮未新增文案。
- 自动检查：domain 370、data 76 项测试通过（0 failure/error/skip），其中请假 32 条移植自 iOS。云端无法下载 Android 依赖，`:app` 由 PR #264 的 GitHub Android CI（`fc32e1b`）完成单元测试、lint 与 Debug/Release 构建，全部通过。未运行模拟器或真机，界面视觉与交互仍待设备验收。


## 2026-10-03 · Android 3.2.1 授权增量与 Pixel 验收

### 范围与采用记录

- 工作分支 `codex/android-321-incremental`，从指定参考 `18129168acd23edc3a872cca3633a2831f60c6f2` 创建；原冻结基线 `9252fdfdc66aab88b4acb7493684f11991fd773d` 不整体推进。Watch scheme、本机 `.idea/`、营销视频未提交修改保留，不纳入本次。
- 核对已有 Android 提交：`1cb32775` 已含日历涂色/年度班次范围，`25f087e1` 已含免费周/月/年/人生加班，`a50e1903`/`fc32e1b8`/`ffbfde1c` 已含请假叠加、规划与 UI；本次继续修复与补验。
- 本次采用：`319adde5`/`932d0c7a` 报告与统计快照、`47efcb4e` 日历柱图转场、`a3882dde` 中性文案、`1152f263` 历史日期/加班/年报、`a10ffc7c` 暂停翻页；`46f08edb`/`c9e93e71`/`2107473d` 的闹钟规则与权益边界。`4684eb00` 的记录页性能原因按 Compose 查证，不复制 SwiftUI anchor 机制。
- 规定漂移命令得到 39 行（含合并记录），本机日志 `build/android-321/drift.txt`。只采用上述授权范围，未拉取或合并 main，Web/Desktop/analytics 增量不纳入。

### 已实现

- **报告 IMPLEMENTED**：周/月/年由 RecordsQueries 生成一份不可变快照，播放与文字简报共用；周期使用记录时区，周沿用现有 locale 周起始规则。历史连休以报告结束日为基准并显示具体日期，不带当前余额。加班直接表达总量、记录天数和最多一天。年报包括完整休息、最长连休、已休、专注及十二个月趋势，未来月份不计作已发生，无未来连休或年度同比。
- 收入默认遵循隐藏设置，主动显示仍调用 EarningsGate，只影响本次报告。全屏 Compose 原生绘制，统一设计与动效 token；日历圆点转为胶囊柱，休息章使用紫色与连休标记。按用户反馈对照本机既有 iPhone 真机截图重做层级、留白和光色；报告内不显示主导航，系统栏由现有主题路径统一控制。没有启动 iOS 模拟器做视觉检查，也没有上传 iPhone 私有截图。
- 播放、主动暂停、长按临时暂停、前后页、重播、文字简报、后台暂停均接入；暂停切页直接完成目标页。时钟只使 Canvas/进度条重绘，不重建统计。TalkBack 或关闭动画进入完整静态阅读，包含最长连休具体日期；阅读卡满宽，大字号可滚动，控制按钮可换行。
- **通知 IMPLEMENTED**：周/月/年独立设备开关，周期结束后首日 09:00，持久保存类型/边界/时区，年报打开上一年。旧静态总结迁移到周报，月/年默认关；旧预约由原前缀差量替换，未照搬 iOS 名额。冷进程重排原子保留每类最多一个待投递到期凭据，首次冷启动重登未来预约；不重发过去预约。购买查询未知时保留已有预约，关闭类型仍清理，确认免费时撤销。
- **休假/免费加班 IMPLEMENTED**：详情打开前原子扣次落盘，搜索不扣、重复打开也扣、总共三次；写失败不导航。新增后续手改排班不被撤销覆盖的回归。补齐免费单日加班一行，周/月复用已解析日期，避免二次展开。没有推算历史加班或解锁付费历史/收入。
- **记录页优化 IMPLEMENTED，性能仍有剩余项**：年展开仅为选中月份异步构建 headline，按页面快照/月缓存；手机普通/展开保持同一 chart 调用位置，避免替换整个页面分支。日历原本只登记选中日期的位置，年/人生绘制模型已有缓存。没有新增逐日全局坐标上报。
- **班次闹钟：纯规则 IMPLEMENTED，平台集成 BLOCKED**。12 项纯 JVM 测试覆盖最终排班、每班型提前量/静音、跨日、精确截止、滚动日历年、稳定 ID、差量、实际覆盖、末次成功 +10 分钟刷新与九分钟贪睡边界。产品没有起床闹钟开关或系统响铃实现。官方能力、冲突和选择见 [平台边界](shift-alarm-platform.md)：现有架构禁止前台服务，客户端 Billing 不给精确订阅到期，本轮又排除验证服务器。没有普通通知冒充闹钟、猜测期限、轮询或声称 iOS stopIntent 已自动补排。

### 自动验证

- 最终四模块 **535 项通过**：domain 400 / data 87 / design 12 / app 36，0 failure/error/skip；lint **0 error / 47 warning / 3 hint**；Debug、R8 Release 通过。最终日志 `build/android-321/gradle-delivery.log`。新增提示包含报告资源读取及窗口高度 API 建议，不作为错误忽略。
- `npm test` **47 文件 / 531 项通过**，包括规则 fixture 和生成翻译一致性；npm lint、check:version（3.2.1）、check:ios 通过。iPhone 18 Pro 目的地的 headless simulator build 通过，日志 `ios-build.log`。没有改动共享 TypeScript/Swift 规则，也没有通过重新生成 fixture 掩盖差异。
- 本地临时 Gradle init 为独立 QA 包注入通知探针，测试真实 AlarmManager → Receiver → Notification → Activity 路径；不属于生产源或提交内容。最初探针源码路径配置错误导致两次仅测试入口 ClassNotFound，修正后重测投递成功；不将这两次失败计为通过。

### 真机验证

设备：**Pixel 10 Pro，Android 17 / API 37.1，1280×2856，显示模式 120.00001 Hz（可变刷新率）**，无线 ADB 5049。全部使用新建的 `com.rainif.doneat.preview321` 与合成 schema 7 档案；正式应用和已有 Preview 数据未修改。按用户要求关闭闲置模拟器，后续只用 Pixel；构建单 worker、低优先级。

| 项目 | 实际结果 |
|---|---|
| 休假采用/撤销 | 搜索不扣；同一详情打开三次后计数 3，第四次进入 Plus，仍可浏览列表。采用 5 天使余额 10→5；取消单日后计划余 4 天；撤销余下计划后余额回到 10。进程重启保留计数。 |
| 休假视觉 | 浅/深色、200% 字号可滚动到采用、阿拉伯语 RTL 已实看。大字号主导航长标签折行仍是既有问题。 |
| 免费加班 | 日/周/月合成记录 2 小时，年/人生 12 小时；历史日/年度/人生其他内容仍锁定。单日验收临时新增的最近记录已还原。 |
| 报告交互 | 实看日历、工时、加班、连休、年报和十二个月静态趋势；暂停前后页完整，播放/重播、文字简报、前后台暂停通过。长按两次截图进度不变，松手后继续；主动暂停后按住再松手仍暂停。 |
| 无障碍/布局 | 德文 200% 字号动态报告、阿拉伯语 200% +关闭动画静态报告均可读可滚动；真实 TalkBack 开启后转静态并可聚焦统计。uiautomator 会临时接管无障碍服务，TalkBack 判断改用纯截图和实际聚焦，不以 dump 时状态误判。 |
| 收入保护 | 主动显示触发系统指纹/PIN，取消后全局 hideEarnings 仍 true；没有执行真实身份输入或购买。 |
| 通知迁移/开关 | 合成旧总结 true→false、周 true、月/年 false；分别开启后登记 2026-10-05、2026-11-01、2027-01-01 的 09:00 UTC，符合记录时区。通知和精确预约权限通过系统页面授权。 |
| 通知点击 | 实际投递后，热启动仍打开 2026-09 月报；测试进程确认退出后点击另一个通知，冷启动打开原定 2025 年空报告。当前日期已是 10 月，未改开当前周期。 |
| 起床闹钟设备矩阵 | **NOT_RUN**：响铃、锁屏、普通进程退出、重启、权限/排班变化、停止、贪睡、权益边界的系统集成均未实现，不能用纯规则测试替代。没有预约任何起床闹钟。 |

### 性能证据与剩余事项

使用 `dumpsys gfxinfo … framestats` 和 `atrace`，均为 Debug 隔离包。六组月历上下滚动最终样本 543 帧，10 帧 missed deadline（1.84%），p50/90/95/99 = **8/11/12/19 ms**。此前周样本 873 帧/2（0.23%），7/9/10/12 ms；人生 827 帧/0，7/9/9/11 ms。月/周选择日期、浮层滚动与进入明细通过。

年首次展开原样本 1 帧 109 ms；移出同步统计后 4 帧、p99 81 ms；保留图表位置后的最终首展开 7 帧/2 missed、p50/p99 26/81 ms，再展开 4 帧/1 missed、p99 101 ms。**仍有慢帧，没有证明年度展开已流畅或整体耗时降低**。atrace 捕获到主线程 measureAndLayout 84.86 ms、recompose 58.48 ms，说明剩余问题涉及 Compose 布局/重组。展开后内容不需要滚动的零帧样本已丢弃，不用于结论。

上述数据不能证明持续物理 120 fps；GPU 百分位也不能替代主线程与端到端帧时间。后续应在可测 Plus 年页的优化包中继续定位布局开销。旧 Android、HyperOS、真实 Play 交易没有追加验收。截图使用合成数据，保存在 `docs/android/qa/2026-10-03-321/`；原始日志/trace 留在本机 `build/android-321/`。

- **清理完成**：独立 QA 包已卸载，临时通知探针、合成数据、相关系统预约一并移除，活动测试通知为 0；字号恢复 1.0、动画倍率恢复原先未设置、辅助服务恢复未设置/关闭。正式应用及已有 Preview 保持原样。
- **提交**：代码与合成截图提交 `ff3874fb`，已推送 [PR #283](https://github.com/ififi2017/Off-Work-Countdown/pull/283)。本地验证结果如上；PR 不宣称闹钟平台集成或年度展开性能已经完成。

### 2026-10-04 真机预览与动画恢复补验

- 用户反馈减弱动态效果未恢复：此前仅删除 `animator_duration_scale`，不能据此声称实际动画已恢复。本次明确写回 `1.0`，读回窗口、转场、Animator 三项倍率均为 `1.0`，并在系统 Color & motion 页面确认 Remove animations 开关为关闭。
- 按用户要求重新构建并安装独立 `com.rainif.doneat.preview321`，不包含通知测试探针。使用合成 schema 7 数据，报告通知关闭；已打开 2026 年 9 月月报，保留安装供用户体验。正式应用数据未修改。Debug 构建成功，随后停止 Gradle daemon，未启动模拟器。

## 2026-10-04 · 对照完整 iOS 实现补齐报告与转场

### 复核与修正

- 用户指出此前只移植了外形、缺少功能与进出过渡。复核确认上一轮对报告完成度的判断过宽：通用章节时长、缺少真正的收尾页、标题/可选章节不完整，以及替换整个导航分支导致的生硬切换均需要修正。不能以自动测试通过或配色接近宣称达到 App Store 编辑推荐水准。
- 完整读取固定 `18129168` 的 `CycleReport`、`CycleReportInsights`、`RecordsQueries+CycleReport`、`ShiftSessionStore+CycleReports`、播放器/DisplayLink、两份报告 View、Art、OWCMotion 和对应规则/播放测试；这些报告源文件与当前本地 iOS 源无差异。结合已有 iOS 实际播放录像逐帧核对，没有新启动模拟器或上传私有 iPhone 图像。规定漂移检查仍是相同的 39 行，日志 `build/android-321/report-polish-drift.txt`；冻结源与授权增量均未推进。
- 报告改为覆盖原记录页的原生 Compose 上移进入/下移退出，退出结束才移除路由；原页面保持组合位置、选择与滚动状态。覆盖期间底层读屏节点隐藏；未解锁报告的“查看方案”在退出完成后导航到 Plus。
- 章节顺序、可选章节、事实标题、各章构建/停留时长对齐固定 iOS。补齐月报环形收尾、周/年报趋势收尾、三项摘要、重播与完成；没有加班时省略该章。完整表达基线范围、专注类别、休假余额比例及收入/加班收入关系，年报仍不加入未来连休或不可靠同比。
- 日期按对角线依次上移落入；月历到工时在固定画布内先缩点、移动至柱底、再逐柱生长。休息章回到日历、淡化工作日、点亮休息日、依次强调最长连休；柱内加班色裁切到胶囊形状。背景、图形、数值与进度共用可暂停的时钟，统计和绘图输入不随帧重算。使用 `DoneAtReportMotion` / `DoneAtMotion` token，没有新增动效库或位图资产。
- 暂停切页直接完成目标构建；播放中点上一页，超过 800 ms 先重播当前章，再点返回上一章。临时按住不改变主动暂停选择；末页结束停止，重播重置时钟。TalkBack/关闭动画时保留收入选择和文字简报入口，隐藏播放入口；播放中开启 TalkBack 自动转静态阅读。真机发现周报较长的第三项摘要被 FlowRow 挤掉，已改为普通字号等宽列、大字号纵排，并重新安装复验。

### 自动验证

- 最终四模块 **543 项通过**（domain 402 / data 87 / design 12 / app 42），0 failure/error/skip；lint **0 error / 46 warning / 3 hint**；Debug、R8 Release 通过。最后布局修正后再次执行全部 Gradle 检查，日志 `build/android-321/report-polish-delivery-gates.log`。
- `npm test` **47 文件 / 531 项通过**，规则 fixture、19 语言生成资源一致性通过；npm lint、check:version、check:ios 及 iPhone 18 Pro 目的地 headless iOS build 通过，日志 `report-polish-*.log`。本轮复用现有翻译，没有新增或手改生成资源，也未更改共享 TS/Swift 规则。
- 新增纯 JVM 标题选择和变形边界回归；播放器测试覆盖章节条件、构建/停留、跨章余量、两个时钟暂停、上一页重播、暂停完成帧与末页重播。这些测试不替代设备视觉验收。

### Pixel 补验与限制

- 仍使用上述 Pixel 10 Pro / Android 17、120 Hz 可变刷新显示模式、隔离预览包和合成档案。实际查看进出覆盖、日期入场、第一/二章变形、暂停前后翻页、周/月/年收尾、重播、后台暂停、文字简报与当前月余额；年报有“截至今天”和十二个月趋势。未解锁报告的方案入口已实际打开，再恢复原 Debug 权益。
- 长按期间两张画布截图像素相同，松手后画面继续变化；主动暂停后按住再松开仍保持暂停。真实 TalkBack 服务开启后从播放切到静态报告，未用 uiautomator 接管服务来冒充读屏验证。阿拉伯语 RTL + 200% 字号 + 关闭动画的年报已实际进入并滚动，读取完整统计与月度趋势。正常字号周报修复后第三项“最长连续休息 2 天”完整显示。
- 本轮报告 gfxinfo 样本 **1,150 帧，Janky frames 19（1.65%）**，p50/90/95/99 **8/12/15/25 ms**；同份输出的 legacy 指标是 **282（24.52%）**，口径不同，不能只挑较低数字代表流畅度。样本包含 Debug 播放与暂停导航，截图也有额外开销；没有证明持续 120 fps。前节记录页年度展开 81/101 ms 慢帧和起床闹钟平台限制仍未解决，本次不改写为完成。
- 截图与进出动画分镜保存在 `docs/android/qa/2026-10-04-report/`；完整原始录像 `build/android-321/report-polish-final-motion.mp4`、gfxinfo、设备设置读回与 UI 树保留本机。截图为合成记录，缩放压缩供 PR 查看；无真实收入或私有 iPhone 内容。
- **最终恢复**：字号 `1.0`，窗口/转场/Animator 三项动画倍率均 `1.0`，辅助服务 `null` / accessibility `0`，预览语言中文。没有创建起床闹钟，报告通知保持关闭，无真实购买或正式数据改动。保留无探针的 `com.rainif.doneat.preview321`，停在 2026 年 9 月报告入口供用户体验；本次不卸载。未启动模拟器，构建结束停止 Gradle daemon。


## 2026-10-04 · 周起始设置、记录入口与文字简报复验

### 实现与来源

- 用户并排截图指出 Android 月历报告入口脱离卡片、计划斜纹过重，并要求增加周日/周一起始设置；随后真机发现周报日期末尾的“日”孤立换行、文字简报结构偏离 iOS。逐段核对固定 `18129168` 的 `RecordsDesignView`、`RecordsMonthGrid`、`CycleReportView` 与 `ReportStripScene.State.settled` 后修正。
- 设置 → 记录与数据 → **每周第一天** 可选择星期日或星期一。统一应用到记录月历/周视图、新周报及未来周报通知、排班月历和休假方案日历。通过 SettingsRepository 写本机 DeviceSettings，重启保留；手选值不随语言改变。缺省继续使用原 locale 默认，非法值只回退该字段。交替排班规则、schema 7 档案和已保存报告 URI 的日期边界保持原契约。
- 周/月/年报告入口归入对应图表卡片；月历中与“规划休假”并列，补播放图标及箭头。月历计划斜纹补回 iOS 的淡化层，使用设计 token，避免深色斜纹压过日期与记录标记。
- 报告封面日期恢复 iOS 46 字号上限、最小 50% 和单行适配，使用稳定的 Compose `BasicText` / `TextAutoSize`；不截断范围。200% 字号时按两个完整日期分行，避免拆散日期。文字简报恢复整体滚动页头、紧凑统计卡、静态日历/十二个月趋势、说明及底部完成/播放按钮；去掉重复章节明细卡和顶部播放入口。常规字号数值按内容取宽、基线对齐，大字体改为上下排列。沿用同一统计快照及收入剥离；不在 UI 重算。
- 新增 Android 专用文案 `calendarWeekStart` 的全部 19 语言，从源生成资源；星期名称沿用对应 locale 的 java.time 文本。没有手改生成文件。
- 原 PR #283 已合并。本轮从其原提交新建 `codex/android-calendar-week-start`；为确认合并状态读取远端后，规定漂移输出从 39 增至 40 行，新增 `2f867539` 是 iOS 系统评价 API 调整，本轮不采用。未合并 main 或推进冻结源/授权增量。日志 `build/android-321/calendar-entry-drift-after-fetch.txt`。

### 自动验证

- 最终 Android 四模块 **545 项通过**（domain 402 / data 89 / design 12 / app 42），0 failure/error/skip；lint **0 error / 46 warning / 3 hint**；Debug、R8 Release 构建通过。日期和简报修正后已重跑完整 Gradle 门禁，日志 `calendar-reading-gates.log`。
- `SettingsRepositoryTest` 新增持久化、跨语言、月历补位、周报/通知日期、旧链接不变、档案不改及非法值回退回归。选择周日时 2026-10-03 的下一报告通知为 10-04 09:00 UTC，周一则为 10-05 09:00 UTC。
- `npm test` **47 文件 / 531 项通过**，含规则 fixture、19 语言及生成文件一致性；npm lint、check:version、check:ios 与本地 iPhone 18 Pro 目的地 headless iOS build 通过。日志 `calendar-entry-*.log`、`calendar-reading-*.log`。本轮未改 iOS/共享规则，未做 iOS 模拟器视觉测试。

### Pixel 实际验收

- Pixel 10 Pro / Android 17 API 37.1；继续使用隔离预览 `com.rainif.doneat.preview321` 和已有合成档案。实际选择周日后记录周视图及报告为 **10-04—10-10**；选择周一后为 **09-28—10-04**，月历相应重排。进程退出重开仍显示星期一；切回周日后，旧日期 URI 仍打开指定的 09-28—10-04 报告。
- 排班月历和休假方案详情均实际显示周日第一列，未保存排班或采用新方案。报告操作行已在月历卡片内，计划斜纹减淡，周报默认字号的完整日期已在一行显示。文字简报已实际滚动到完成/播放按钮，标题随内容滚动；中文 200% 字号两个完整日期和上下排列的统计值均可读。
- 阿拉伯语 RTL + 200% 字号 + 关闭动画的周报已实际打开并滚动到“完成”：两个日期完整，数值未挤压，静态路径没有播放按钮；恢复后读回字号与 Animator 均为 1.0。无线调试一度断连，失败的截图尝试不计作通过，重连稳定后的实际图片与 UI 树保存在 `build/android-321/calendar-week-rtl-large-*`。
- 历史月报简报与当前年报简报已实际查看，年报从 1 月滚动到 12 月和底部“完成/播放报告”；未来月份显示尚无已发生统计，收入隐藏时无收入行。当前周期继续有“截至今天”。本轮未重新做性能采样，不增加 120 fps 或慢帧已解决的结论；此前闹钟平台限制及年度展开慢帧仍按前节记录。
- 深色主题下的新设置弹窗和减淡后的月历斜纹已实际查看，随后恢复浅色。PR 截图保存在 `docs/android/qa/2026-10-04-calendar/`，来自独立预览的合成档案，无真实薪资或私有 iPhone 图像。
- **清理与交付**：本机周起始恢复验收前的未设置状态，记录尺度恢复月；试用计数未变。字号、窗口/转场/Animator 动画倍率全部读回 **1.0**，辅助服务 `null` / accessibility `0`，语言中文，主题浅色，息屏时间恢复原值。没有采用方案、创建测试闹钟或开启报告提醒，正式应用未改动。保留新版 `com.rainif.doneat.preview321` 并打开月历供体验；未启动模拟器，Gradle daemon 已停止。

## 2026-10-04 历史月报连休核查

- 用户反馈历史报告似乎从今天寻找连休。无线调试重连后，在 Pixel 10 Pro 的独立预览中实际读取其打开的 **2026 年 9 月月报**：文字简报显示 **5 天 · 10 月 3 日—10 月 7 日**。截图和 UI 树仅保留本机 `build/android-321/historical-report-observed.*`。
- 只读核对排班发现：中国节假日快照的 `effectiveFrom` 为 **2026-10-05**，此前快照为周一至周五工作、未启用节假日。故 10-01、10-02 仍为工作日，10-03、10-04 为周末，10-05—10-07 为新设置下的节假日。当前结果符合这份档案；查询和展示均已使用 09-30 为基准，本轮没有改动业务规则或回写历史排班。
- 新增三项领域回归，使用仓库真实 `HolidayTemplates.json`：节假日从 10-01 生效时，9 月月报包含完整 10-01—10-07；从 10-05 生效时，复现设备的 10-03—10-07；周日/周一起始的跨月周报分别从各自结束日的次日查找。将打开时间推进至 10-08、11-04，历史连休仍保持原日期，历史报告不带当前余额。
- Android 四模块 **548 项通过**（domain 405 / data 89 / design 12 / app 42），无失败、错误或跳过；lint 0 error / 46 warning / 3 hint；Debug、Release 构建通过。`npm test` 47 文件 / 531 项通过，npm lint、check:version、check:ios 和 iPhone 18 Pro 目的地 headless iOS build 通过。日志 `build/android-321/historical-break-*.log`。
- 设备证据仅限读到上述 9 月月报及排班数据；其他日期矩阵由 JVM 回归验证，不宣称在真机改日期验证。没有重新安装、修改排班/系统设置或创建闹钟；手机保持用户打开的报告。Gradle daemon 已停止，没有启动模拟器界面。
- 规定漂移命令仍为 40 行，见 `build/android-321/historical-break-drift.txt`。固定 iOS 参考仍为 `18129168`，没有推进基线或跟随 main。


## 2026-10-04 默认强调色对齐

- 用户提供 iOS / Android 计时页对照图，指出 Android 偏砖红。根因是初次 T04 将默认 `primary` 为统一 4.5:1 对比度调深为 `#C2410C`（深色 `#FF9A5C`），而固定 iOS `18129168` 的 `OWCDesign.accent` 使用浅色 RGB `(0.95, 0.35, 0.04)` / 深色 `(1, 0.53, 0.18)`。本次将默认 primary、surfaceTint 和 inversePrimary 统一为浅色 `#F2590A` / 深色 `#FF872E`。计时页收入/主题、记录页收入/全部记录按钮从灰色改为主题强调色。
- 调色对话框的默认草稿使用浅色强调色；品牌标志的装饰橙、自定义色和壁纸配色路径保留。自定义 RGB 采样的全部对比度回归继续通过。设计 ADR 明确默认浅色橙字/橙底白字与 iOS 一致的 3:1 边界，不宣称其满足普通小字 4.5:1；普通文字/状态色/自定义色仍按 4.5:1 验证。
- Pixel 10 Pro / Android 17 API 37.1，无线 ADB，独立 `com.rainif.doneat.preview321`：新版已安装并实际查看浅/深色计时页及记录页。主按钮、进度条、顶部操作和底栏均使用新的默认强调色。截图见 `docs/android/qa/2026-10-04-accent/`；只提交预览截图，用户 iPhone 对照图留在本机。将 iPhone 图的 Display P3 转换为 sRGB 后，其主按钮约 `(244,88,10)`，Pixel 为 `(242,89,10)`；代码色值以固定 iOS 源为准，不把截图色彩转换后的量化差异误作 UI 色值。
- 主题已通过界面从自动→浅色→深色→自动恢复，手机停在计时页供体验。读回显示自定义颜色、壁纸配色、隐藏收入等本机设置保留，仅当前 Tab 从记录变为计时；排班快照、名册、手改日和休假数据均与验收前一致。字号及三项动画倍率均为 1.0；没有创建闹钟或修改正式应用。未启动模拟器界面，Gradle daemon 已停止。
- Android 四模块 **548 项通过**（405 / 89 / 12 / 42），无失败、错误或跳过；lint **0 error / 46 warning / 3 hint**；Debug 与 R8 Release 构建通过。`npm test` **47 文件 / 531 项通过**，含翻译与规则生成一致性；npm lint、check:version、check:ios 与 headless iOS simulator build 通过。日志 `build/android-321/accent-*.log`。本轮未重做大字体/RTL/性能/闹钟矩阵，沿用此前证据，不增加帧率结论。
- 固定源及漂移范围不变，规定命令输出仍为 40 行，日志 `build/android-321/accent-drift.txt`；未跟随 main。


## 2026-10-04 Cloudflare Play 验证服务（T21）

### 授权与采用范围

- 用户先选择 Cloudflare / `api.doneat.app`，随后明确“现在开始做这个后端服务”。本次修订 D-08，启用原本延后的 T21。同一公开仓库内独立 `services/billing-api`，独立依赖、CI、Worker 部署；不加入账号、Drive、Wear、视频导出或工资上传。四模块、schema 7、原子 JSON 均保持现有架构。
- 从已合并 PR #285 的原提交 `eb858090` 创建 `codex/cloudflare-play-billing`。原 iOS 冻结 `9252fdfd` 与 Plan 020 增量 `18129168` 保持；规定漂移命令仍输出 40 行（`build/billing-api/drift.txt`）。只采用本次明确授权的 Google 服务端核验能力，没有合并或静默跟随 main。保留已有 iOS Watch scheme 改动、IDE 目录和宣传视频素材。

### 实现

- 两个 POST：购买核验调用 Google Publisher subscription/product v2；认证 Pub/Sub RTDN 重新查询购买状态。订阅使用 Google 精确 expiry，取消续订不抹去有效周期，pending/暂停/hold/到期不授予；终身检查实际购买、退款与消费状态。RSA 签名绑定包名、商品、令牌哈希、nonce、核验时刻和修订号。
- D1 保存购买令牌哈希及权益状态，原始令牌、Google 响应、工资/记录均不落库或应用日志。短租约与 D1 事务避免陈旧查询回写；linked token 的生效替换撤销旧凭据，pending 替换保留旧有效周期。RTDN 验 Google OIDC、audience、服务账号邮箱、subscription，并按 message ID 去重；失败依靠 Pub/Sub 重试。待退款审核通知只确认接收，不猜 purchaseToken、不提交退款决定。
- Android 继续 Play 查询/本地签名检查和客户端 acknowledge，配置公钥后再验证服务凭据。收据存 `noBackupFilesDir`，网络失败只保留仍有效签名证据；没有按购买日或商品周期猜到期。`PlusStoreState.shiftAlarmAuthorization(now)` 输出精确边界给现有领域规则。一次内存期限任务让常驻前台时的权益也在凭据到期后停止；没有网络轮询或新系统闹钟。Worker 不可用的重试复用现有一次性 WorkManager 路径。
- 公钥配置缺省为空，既有发布暂不启用服务器；生产公钥进入 APK 前须完成实际部署、官网隐私披露与许可测试。服务端续订/退款不会立即同步到离线手机，不声明离线即时撤销。
- 原生起床闹钟响铃、锁屏、停止、贪睡及重启恢复仍属待接入能力；本次没有新增普通通知来冒充起床闹钟，也没有宣称设备闹钟验收通过。

### 配置与验证进展

- 用户确认 `doneat.app` DNS 已在 Cloudflare、拥有 Play 权限管理；提供 Google 项目 `august-edge-217210` / 项目编号 `1007961080129` 与 `doneat-billing@august-edge-217210.iam.gserviceaccount.com`。按用户回复已配置 RTDN 主题、Play 主题名称、push 服务账号及 Pub/Sub Token Creator 授权；北京时间 13:16:37 实际收到并认证通过用户从 Play Console 发出的测试通知，D1 通知计数由 0 变为 1，购买计数仍为 0。由真实 Google OIDC → Worker → D1 验证了通知链路；未验证真实购买事件。
- 本机 Wrangler 已登录并核对 `doneat.app` 为该账号的 active zone；无同名 Worker、D1 或已有 Worker 域名/路由。已创建 `billing` D1（WNAM，`18e885f9-c9f1-4be9-aef9-e66669ec47c1`）并应用初始迁移，部署 `doneat-billing-api` / `api.doneat.app`（首次代码版本 `be31002d-2e99-4d5e-8393-3e756d6ab306`）。发现 Wrangler 非 TTY 会自动覆盖 DNS，故部署脚本要求交互终端；实际无冲突提示。Google 私钥来自用户指定的本地文件，仅读取验证账号后直接传到 Worker Secrets，未输出内容；独立收据私钥在忽略的 `.secrets` 中生成并上传。两份 secret 上传成功；生产公钥变量尚未设置。
- Worker 本地实际 workerd + D1：**37 项测试**与 TypeScript 检查、dry-run 打包通过；Google/OIDC HTTP 使用测试替身，不能当成生产 IAM 或购买成功。Android 最终四模块 **555 项通过**（405 / 89 / 12 / 49），lint **0 error / 46 warning / 3 hint**，Debug / R8 Release 通过；前台到期与重试连接补充后已重跑完整门禁。
- 根 `npm test` **47 文件 / 531 项通过**，包含翻译与规则一致性；lint、check:version、check:ios 通过。Web build + check:build:web、Desktop export + check:build:desktop，以及 iPhone 18 Pro 目的地 headless iOS build 均通过。独立服务也完成 npm 11 干净安装、类型检查、37 项测试与打包复核。日志在 `build/billing-api/`。没有安装真机应用、创建测试闹钟或启动模拟器界面；本轮无 UI 修改，不能引用以往截图当作购买设备验收。
- 线上 HTTPS 已验证：空核验请求返回 400 `invalid_request`，未认证通知返回 401 `unauthorized`，均 `Cache-Control: no-store`。明确无效的配置探针令牌返回 422 `purchase_unavailable`，没有生成购买记录。有效购买的签名返回与安卓端消费仍需许可测试；真实 RTDN 测试通知接收证据见上。Worker 部署输出 startup 2 ms 不是请求 CPU 时间，不能据此宣称符合免费 10 ms 限额。
- 部署、回滚、监控、密钥轮换和人工配置步骤见 `services/billing-api/README.md`；英文/中文官网隐私补充已更新到 `privacy-policy-addition.md`，并同步官网本地 `codex/android-privacy-policy` 的 privacy/About 草稿；官网仍按 2026-09-27 的“暂不上线”指示保留未发布。官网 check/build/seo:check 通过，具体发布另需确认此前暂停要求已解除。任务未达到 VERIFIED，下一阶段必须用 Play 许可测试支付方式验证状态流转与真实 RTDN，并测量实际 Worker CPU/配额；本地通过不等于免费 10 ms CPU 足够。


## 2026-10-04 封闭测试购买联调准备

- 官网 [PR #30](https://github.com/ififi2017/doneat.app/pull/30) 已合并发布，19 语言隐私/About 和两份 Apache 许可证线上验证通过；此前“暂不上线”状态已解除。Play Data safety 表单仍需与实际启用服务端验证的构建对照，未声称已修改 Console 表单。
- 用户确认 Android 已进入封闭测试。本轮 Pixel 10 Pro 无线连接成功，实际安装来源 `com.android.vending`，版本 **3.2.1 (111)**。对应成功发布工作流 `37180590462` / 合并提交 `3d136758`；包包含服务端接入代码，但仓库 `DONEAT_BILLING_API_PUBLIC_KEYS` 仍未设置，当前包不启用该服务。
- 当前 Plus 页显示终身权益；用户确认这是**真实付款订单**，且当前账号尚未加入许可测试。没有购买、退款、撤销、清数据、重装或修改该权益。已给出账户级许可测试和封闭测试名单配置指引；新购买/取消/退款矩阵等待独立测试账号，不以真实终身订单代替。
- 在已发布 111 对应提交 `3d136758` 上创建隔离工作树及 `codex/android-billing-license-test`，未切换或覆盖主工作区。相对原后端分支仅保留已随 111 发布的无用 iOS 评价文案生成资源删除；不移植新增 iOS 功能，固定基线 `9252fdfd` / `18129168` 不变。规定漂移命令现为 41 行。
- 为手动 Android Release 增加单次 `billing_api_public_keys` 输入，使联调 AAB 可启用验签，同时保持其他构建的仓库默认配置。现有 `upload=false` 仍只产出签名包，不上传 Play；不改变自动 alpha 发布策略。
- Cloudflare D1 只读查询：购买表为空，未观察到真实购买 RTDN。首次查询临时返回 7403；确认同一 OAuth 账号及 D1 数据库可见后重试成功，无账号/权限/安全设置变更。尚未验证客户端实际消费签名收据、订阅状态流转或 Worker 请求 CPU；T21 仍为 IN_PROGRESS。
- 本轮工作流 YAML 解析、公钥 RSA-2048/SPKI 读取、`check:version`、Android 生成文案一致性及 `git diff --check` 通过；未改 Android 业务代码或 UI。签名 AAB 与 CI 结果见下条。
- [PR #291](https://github.com/ififi2017/Off-Work-Countdown/pull/291) / 实现提交 `c3d04515` 的常规 CI、Rust macOS/Windows、Worker check 通过；Android 路径门禁因仅工作流/文档修改跳过，但独立 [Android Release 37183160962](https://github.com/ififi2017/Off-Work-Countdown/actions/runs/37183160962) 实际重跑四模块单元测试、R8 Release AAB 与签名检查并成功。产物 **3.2.1 (113)** 的 DEX 含预期 `billing-2026-01` 公钥和 API 地址，SHA-256 `26c62a708e74074d3d45392bc579b141dd9e33c510beef9b98c9c96a535ceede` 与 CI 一致。`upload=false`：未上传 Play，未创建发布 tag，未触发该任务的 Play 上传通知。没有本地编译或启动模拟器。
- 已只读取得 Cloudflare 最近 24 小时（截至 `2026-10-04T06:35:36.257Z`）本服务汇总：494 次请求、3 次子请求、运行时 errors=0；CPU p50 **0.391 ms**、p99 **1.085 ms**，字段单位经 GraphQL schema 确认为微秒后换算。该汇总混合所有路径与 HTTP 响应，且购买表仍为空；errors=0 不等于购买验证成功，低 CPU 分位数也不能证明真实购买签名链路符合免费 10 ms 限额。请求内容日志仍关闭，未额外存储用户数据。

### 2026-10-04 无收费月订阅与真实 RTDN 验收

- Pixel 10 Pro / Android 17 / Play 3.2.1 (111)。实际读取 Google Play 确认页：`Test card, always approves`、测试订阅 `HK$15.00/5 min` 和 `You will not be charged`；用户亲自完成最后订阅确认。原真实终身订单未由代理退款、撤销或修改，没有清数据/重装应用。
- 本轮只读查询 D1 的商品、状态、测试标记、验证时间、到期时间与 revision；未读取或输出原始 token、订单号、账号邮箱。以下时间均为北京时间（UTC+08:00），到期值直接来自 Google API，不由五分钟测试周期推算。

| 事件 | Google 查询完成时间 | 到期时间 | D1 结果 | 已处理通知总数 |
|---|---|---|---|---|
| 首次测试月订阅 | 14:48:22.593 | 14:53:20.232 | `active` / `test_purchase=1` / revision 1 | 2（含此前测试通知） |
| 自动续订 | 14:53:26.909 | 14:58:20.232 | `active` / `test_purchase=1` / revision 2 | 3 |
| 用户取消自动续订 | 14:55:14.466 | 14:58:20.232（保持） | `active` / `test_purchase=1` / revision 3 | 4 |
| 取消后到期 | 14:58:23.237 | 14:58:20.232（保持） | `inactive` / `test_purchase=1` / revision 4 | 5 |

- Play 管理页实际显示 `Test: DoneAt`、`Canceled`、测试卡及截止时间；界面使用 PDT，显示 10 月 3 日 23:58，与上表北京时间对应。14:57 回到应用后的 UI 树仍为 Plus，确认取消没有提前撤销已获周期；14:58:47 截图时已过期，111 持续前台仍显示旧 Plus，不能把这张图当作到期前证据。随后返回桌面再回应用，Play 查询后实际回到免费方案页。取消页和刷新后的免费页截图见 `qa/2026-10-04-billing/`。
- Cloudflare 购买/续订测试窗口 `06:48:00Z–06:55:02.104Z`：22 次请求、6 次子请求、运行时 errors=0，CPU p50 **0.479 ms** / p99 **14.293 ms**。该窗口仍混合不同路径，不能归因到某一个事件，也未覆盖客户端收据签名路径；但尾部已超过 [Workers Free 每请求 10 ms](https://developers.cloudflare.com/workers/platform/limits/#cpu-time)，不得以此前空库的低分位数承诺免费档足够。官方允许偶发超时余量，不能把本次未失败当作稳定容量保证；冷/热路径定位与复测、或由所有者选择付费方案仍需完成。没有更改套餐或启用请求日志。
- 以上已证明真实 Play RTDN → OIDC 认证 → Google purchase 查询 → D1 精确权益更新。111 未包含服务器回执公钥，手机 Plus 状态仅证明既有客户端 Billing；不能标为 Android 签名回执、离线到期或闹钟预排端到端通过。113 尚待 Play 安装，其他商品、pending、退款、恢复、离线、宽限/暂停与重复/迟到通知矩阵仍未完成；T21 保持 IN_PROGRESS。
- 本轮只补实测证据，没有改运行时代码或设备设置、建立测试闹钟、启动模拟器或执行真实付款。测试月订阅已取消并确认到期失效；保留真实终身购买和用户应用数据。变更并入现有 PR #291。

### 2026-10-04 通过现有 CI 自动上传验签联调包

- 用户要求沿用 main 自动打包流程，并明确授权本次自动上传及工作流现有飞书通知。PR #291 已于北京时间 15:09 合并为 `2ddf11b7`。PR #290 的 Android/共享资源变动触发普通发布 [37184920654](https://github.com/ififi2017/Off-Work-Countdown/actions/runs/37184920654)：**3.2.1 (114)** 已成功上传；PR #291 的工作流/文档改动本身不匹配自动发布的路径过滤。
- 从该 main 提交触发一次 [Android Release 37185249599](https://github.com/ififi2017/Off-Work-Countdown/actions/runs/37185249599)，使用 `billing_api_public_keys` 公开参数、`upload=true`、`track=alpha`、`status=draft`。**3.2.1 (115)** 已在北京时间 15:21 自动上传并提交 Play 编辑，上传后的现有飞书通知步骤通过；运行最终 SUCCESS。113 保留为此前未上传的产物，后续设备联调使用 115。仓库默认公钥变量未由本次操作启用。
- 本次运行通过版本/生成翻译检查、四模块单测、R8 Release AAB、签名检查。下载同一产物核对：DEX 含 `billing-2026-01`、完整预期 RSA 公钥及 `https://api.doneat.app`；存在上传签名，SHA-256 `d7c77340234f1b3dd03bc3417bdb8d726cb4c81c49bc9515754bed83adab9f58` 与 CI 日志相同。没有本地重编译或启动模拟器。
- 发布来源明确为当前 main，包含另一已合并 PR #290 的 en-GB / 拉美西语及英格兰银行假日更新。规定漂移命令现为 42 行，新增 `1db33515`；本任务的 iOS 规则移植冻结源仍为 `9252fdfd` / `18129168`，不将这次对已有主干的打包记录当作重新完成跨端规则移植验收。
- **后续步骤**：所有者在 Play Console 发布/提审 115 草稿，通过 Play 覆盖更新 Pixel 后继续 Android 签名回执、离线、精确到期和其余购买矩阵。草稿上传成功不等于审核通过或已安装。上节 CPU p99 14.293 ms 的免费档容量问题及起床闹钟平台集成仍未解决，T21 保持 IN_PROGRESS。

### 2026-10-04 · 115 签名回执真机验收与提示文案修正

- Pixel 10 Pro / Android 17 已通过 Google Play 更新到 **3.2.1 (115)**，安装来源 `com.android.vending`。从手机读取 APK 的公开代码，确认包含 `billing-2026-01`、预期 RSA 公钥和 API 地址；未读取应用私有购买缓存。验收源码对应已发布 `2ddf11b7`；修复分支基于随后仅补进度的 `85509062`，未跟随新 main 改动。规定漂移命令现为 44 行（新增 `310f8890` iOS 版本介绍及合并记录 `c5182d71`）；冻结规则源仍为 `9252fdfd` / `18129168`，本轮不移植这些增量。
- 新购买确认页再次实际显示测试卡、五分钟测试周期及“不会收费”；用户亲自点击最后订阅确认。115 随后显示 Plus；结合实际 APK 的强制服务器验签配置和客户端策略，这验证了真实购买 → 服务端签名 → Android 接受回执并授权的路径，不再只是 111 的客户端验证。
- 仅取消了详情页明确标注 `Test: DoneAt` / `Test card, always approves` 的本次月订阅自动续订，没有退款或修改真实终身订单。

| 本次测试事件 | Google 查询完成时间（北京时间） | 精确到期 | 后端状态 / revision | 通知总数 |
|---|---|---|---|---|
| 新测试购买 | 16:23:31.499 | 16:28:29.718 | active / 1 | 6 |
| 取消自动续订 | 16:27:20.214 | 16:28:29.718 | active / 2 | 7 |
| 到期 | 16:28:32.101 | 16:28:29.718 | inactive / 3 | 8 |

- **持续前台到期 PASS**：返回 Plus 后保持页面，期间不切后台、不点恢复。前截图采集于 `16:28:24.721–26.233`，仍显示 Plus；后截图采集于 `16:28:33.723–35.081`，不再显示会员权益。证据说明到期边界前后行为正确，不能据两张截图声称毫秒级画面切换。到期后点击“恢复购买”回到免费方案页，未重新授予已过期订阅。截图见 `qa/2026-10-04-billing/115-expiry-*.png`。
- 真机发现：已签名证据到期后，待确认状态沿用了“Google Play 不可用”提示，即使网络正常。现从 Android 专用文案源修改同一键的 19 种语言并重新生成资源：说明当前 Plus 权益暂时无法确认，引导重试/恢复；不推断 Play 故障或断网。权益判断、截止时刻及重试行为不变。
- Worker 实际联调窗口 `08:23:00Z–08:30:00Z`：45 请求 / 9 子请求，运行时 errors=0，CPU p50 **0.461 ms** / p99 **12.286 ms**。包含本轮客户端回执与 RTDN，但仍是混合路径汇总，未单独分离冷/热请求；尾部仍超过免费档 10 ms。此前 14.293 ms 证据保留，不能宣称免费档容量验收通过。
- 该阶段手机只有无线 ADB，离线保留/离线到期、离线冷启动尚未执行；后续用户接入 USB 后另行补齐，证据见下一节，不以本阶段联网前台测试代替。其他商品、pending、退款、宽限/暂停、替换与重复/迟到 RTDN 的完整矩阵仍待完成；起床闹钟平台实现仍未完成。T21 保持 IN_PROGRESS。
- 自动检查已通过：`npm test -- --maxWorkers=2` **50 文件 / 545 项**，包含规则与翻译一致性；lint、`check:ios`、`check:version`；本轮本地 headless iOS simulator build（201 秒，未启动模拟器界面）及单 worker 独立预览 Debug 构建（79 秒）。PR #296 的 Web build / Desktop export 与对应产物检查、Rust macOS / Windows 已通过；Android [CI 37189750874](https://github.com/ififi2017/Off-Work-Countdown/actions/runs/37189750874) 的四模块测试、lintDebug、Debug / R8 Release 构建及 stable Compose 检查全部通过（Gradle 5 分 2 秒）；没有把 CI 结果当作真机行为证据。
- **修正文案视觉 PASS**：Pixel 实际安装独立 `com.rainif.doneat.billingqa`，使用现有 Debug gallery 的模拟 OFFLINE 状态、真实 `PlusPage` 验证英文浅色/深色、简体中文、阿拉伯语 RTL，以及英文 200% 字号 + 三项系统动画关闭。提示完整、没有截断或重叠，大字体滚动后重试/恢复按钮可达；预览不执行购买，不能用它代替上述真实 115 验签证据。新截图为 `qa/2026-10-04-billing/receipt-copy-zh-light.png` 和 `receipt-copy-en-large.png`。
- 测试月订阅已取消并确认到期。视觉检查后已卸载本轮独立 `billingqa` 包、清理设备临时 UI XML，并返回 Play 版；字号与三项动画原值均为 `1.0`，已逐项恢复并读回确认。未修改网络或熄屏设置、清除正式数据、创建闹钟或启动模拟器。读取到的原熄屏超时为 `2147483647`，保持原值。

### 2026-10-04 · 115 USB 离线权益与冷启动验收

- 用户接入 USB，实际确认 Pixel 10 Pro 的 USB ADB 可用；继续同一 Google Play **3.2.1 (115)**，没有替换正式应用。再次读取 Play 确认页的测试卡、五分钟周期与 `You will not be charged`，由用户确认最后订阅按钮。随后只取消详情页明确标注 `Test: DoneAt` / 测试卡的本笔月订阅，Play 显示 Canceled；没有退款或触碰真实终身购买。

| 事件 | Google 查询完成时间（北京时间） | 精确到期 | 后端状态 / revision | 通知总数 |
|---|---|---|---|---|
| 第三笔测试月订阅 | 16:56:40.880 | 17:01:39.349 | active / 1 | 9 |
| 取消自动续订 | 16:58:42.978 | 17:01:39.349 | active / 2 | 10 |
| 到期 | 17:01:41.522 | 17:01:39.349 | inactive / 3 | 11 |

- 临时关闭 Wi-Fi 与默认移动数据，经 `dumpsys connectivity` 确认 `Active default network: none` / `mDefaultNetwork=null`；仅开关命令返回或状态栏图标不作断网证据。通过 USB 保持控制，未修改系统时间，也没有清除本地购买缓存。
- **到期前离线冷启动 PASS**：断网后 force-stop 正式进程，再次启动并从设置打开 Plus。16:59:45 仍显示 Your Plus plan / Plus，签名缓存没有因进程退出和无法联网提前失效。
- **持续前台离线到期 PASS**：保持同一 Plus 页不操作、不重启，截止前截图采集于 `17:01:34.354–35.643`，Plus 仍有效；截止后截图于 `17:01:43.354–44.334`，已不再授权并显示重试/恢复。两次采集同时确认无默认网络。到期来自 Google API 的 `1791104499349`，不是根据购买时间加五分钟推算。截图证明边界前后状态，不宣称测得毫秒级 UI 延迟。
- **到期后离线冷启动 PASS**：继续断网，再次 force-stop / 启动并打开 Plus，17:02:41 页面仍未授权；显示请求无法完成及重试/恢复，未从旧缓存复活已过期权益。115 的旧故障文案仍存在；前节 19 语言修复仅在独立预览验证，尚未安装进 115。
- 已恢复 Wi-Fi 和移动数据，读回均为原值 `1`、飞行模式仍为 `0`，默认网络重新出现。联网后点击恢复购买回到 Yearly / Monthly / Lifetime 免费方案页，未恢复已过期月订阅。字号、三项动画均为原值 `1.0`，熄屏超时仍为 `2147483647`；设备临时 UI 文件已清理。未创建闹钟、改动真实购买或用户记录。
- 设备截图：`qa/2026-10-04-billing/115-offline-expiry-before.png`、`115-offline-expiry-after.png`、`115-offline-cold-expired.png`。本轮仅补证据，源码与已通过完整 [Android CI 37190172604](https://github.com/ififi2017/Off-Work-Countdown/actions/runs/37190172604) / [主 CI 37190172586](https://github.com/ififi2017/Off-Work-Countdown/actions/runs/37190172586) 的 `2bcec6ae` 相同；没有重复宣称自动测试就是设备验证。
- T21 / T26 仍为 IN_PROGRESS：其他商品、pending、退款、宽限/暂停、替换与重复/迟到 RTDN 的完整矩阵、生产冷/热路径 CPU 余量，以及原生起床闹钟平台接入尚未完成。生产全局公钥变量未启用，未调整 Cloudflare 套餐。


## 2026-10-07 · Android 同步 iOS 3.2.1

### 授权与固定对照

- 用户明确授权完整同步 3.2.1、先用 iOS 模拟器截图确认 UI/动画，再在 USB Pixel 10 Pro 验证；允许拆 PR、由 agent 决策后集中汇报。用户明确禁止锁屏和设备闹钟测试，本轮未执行这些操作。
- 独立工作树 `codex/android-ios321-parity` 从 `035420377e4c762ba5556a3cc41fc9a94be4bc6e` 创建，保留原工作区未提交的 iOS 修改。此 SHA 是 agent 固定的 UI 对照点，不是用户指定的 SHA。另核对缓存 `origin/main=ea593050e9eebbaac6a95ec8444f87afe6123bc6` 的版本仍为 3.2.1，将 `170f62a1` / `d2532ab7` 的最终记录修复纳入；不自动跟随之后版本。原冻结源 `9252fdfd` / Plan 020 `18129168` 历史记录保留。提交后为消除 PR 基线分歧，已将实际 `origin/main=ecf4af29` 无冲突合入独立树；规定 model/shared drift 命令仍为 **52** 条，Android 同步代码未因合并变化，生成字符串与版本检查再次通过。收口时只读核对远端 `ecf4af29`（PR #304，仍 3.2.1）：新增 iOS 空优惠 toolbar 删除与到期刷新；Android 已按实际资格显示 toolbar 并在期限刷新，等效契约已包含，没有搬入该 iOS Views 修改。
- UI 开发前查看真实 iOS 3.2.1 模拟器的请假结果、日期表、首启、Plus、优惠、更新介绍和 Duo 展开/半折叠截图；使用该源构建的 iOS 模拟器，不生成产品 UI。iOS Duo SDK 27.1，Android Pixel 10 Pro / Android 17。物理 Pixel 不具备铰链，宽屏/折叠注入预览仅是视觉验收，不称为真折叠硬件测试。

### 本轮实现

- 请假完整搜索、覆盖方案去重、节假日/普通连休分组、多日期选择，42 格月历及按格弹簧入场；原生中/全高日期抽屉。预览和切日期不扣免费次数，详情按既有事务预留一次。
- 六步首启与持续计时衔接、品牌指针与分层入场；Plus 三阶段的延时播放、点击/滑动后停止、辅助功能退化；首启节假日草稿随最终设置一次提交。Android 小组件/持续通知替代 iOS 系统专属表面，不创建 Apple UI。
- 3.2.1 更新介绍、本机 seen 标记及失败重试、真实 Plus 入口；设备本机的一次 24h 终身优惠邀请。只有已验证免费用户符合邀请资格，商品恢复后仍保留未领取邀请；真实有效 Play 价格进入活跃前台视口后才开始期限，重开/时钟回拨不续期，付款前重新查价与资格。写入需显式 sync 与完整回读；无真实商品时不伪造优惠。
- 评分请求按三个不同完成日、版本与 120 天间隔门槛，并在合适的完成时刻延迟显示，离开/后台取消；不首启即请求评分。
- WindowManager 姿态与铰链避让、计时左右/上下分区、Focus 双画布、Records 58/42 分栏、Settings 分组两列、大字退单列、RTL 读序、普通手机短横屏原生时钟与返回、Timer 内设置快捷入口。布局复用同一数据和命令，保留各 tab/route/scroll。
- 未来时间线不误称“今天”；手动计时标签同步；休息日无工时不标 Recorded，保留无排班/加班声明记录；设置 arming 不写开始观察；取消休息日计时仅清理匹配的计时覆盖并写墓碑，保留 Records 独立编辑；导入重复首次打开事件只折叠展示，不删原始档案。
- 原生起床闹钟接入 AlarmManager 绝对预约、持久登记、通知停止/九分钟贪睡与响铃时的 mediaPlayback 服务；默认关闭，需明确权限与权益。原子登记失败关闭、权限重新授予重建、会话/节假日冷启动顺序和响铃 generation 竞态经架构复核及 fake 测试。没有 full-screen intent/自动唤醒界面。普通提醒仍不是此响铃服务。细节见 [平台契约](shift-alarm-platform.md)。
- 新增 Android 专用文案全 19 语；schema 7、备份边界、正式包 ID 与 Play 商品不变。

### 自动验证

- 最终隔离 Debug 126 的统一 Gradle gates 全部通过：domain **429**、data **94**、designsystem **12**、app **118**，共 **653** 项，0 failure/error/skip；lintDebug **0 errors / 54 warnings / 3 hints**，Debug 与 R8 Release 构建通过。警告并非清零，保留报告；未把 pure/fake 闹钟测试算作系统投递。
- Web `npm test` **50 文件 / 547 项 PASS**；ESLint、Android 19 语言生成检查、`check:ios`、`check:version`、Records/extended-schedule Swift fixture `--check` 全部通过。固定 UI 源的 iOS headless simulator build 通过。本轮未更改 Web、iOS 或共享版本。
- 本机最终日志：`/private/tmp/doneat321-final-126-gradle.log`、`doneat321-final-vitest.log`、`doneat321-final-eslint.log`、`doneat321-final-strings.log`、`doneat321-final-ioscheck.log`、`doneat321-final-version.log`；各模块 XML 已实际汇总，不按新增测试数猜测总数。远端检查见 [PR #305](https://github.com/ififi2017/Off-Work-Countdown/pull/305) 的 Checks；通过后更新 PR 描述，不以本地结果代替 CI。

### 真机与 UI 证据

- 独立 `com.rainif.doneat.parity321` Debug 包，未覆盖 Play 正式 3.2.1 (115)、未清正式数据、未操作购买。未修改网络、系统时间、熄屏超时；保持屏幕开启。
- 请假合成样例：35 组节假日、24 组普通连休、48 个日期，与 iOS 对照一致。Pixel 实际选择 Nov 14–22，列表关闭后保留日期；详情才将免费次数由 3 减为 2，返回后仍为 2。未采用方案。
- 首启 Welcome/Ready/Glance/Plus、完成设置、更新介绍→Explore Plus→Back→Continue、真实 Plus 当前商品不可用状态、自然完成计时已实际检查。真实折扣商品及购买不在本轮测试；独立数据样例优惠只渲染画面，不写邀请或购买。
- 已保存 [截图与录屏索引](../../qa/2026-10-07-android321/README.md)：Pixel 原生窄屏、200% 阿拉伯语深色／减少动态效果、简中更新介绍；注入宽屏的 Timer/Focus/Records/Settings、水平半折叠深色、垂直铰链 RTL 大字；实际物理横屏时钟和返回。折叠注入与优惠 sample 均明确标记，不能代表真实折叠硬件或 Play 交易。
- 真机发现并修复：200% 多行分组标签等高；px→dp 的一 ULP 浮点误差曾误拒绝全宽水平铰链，现仅允许四 ULP 边缘舍入并增加真实 Pixel 几何回归；横屏黑底统计采用显式内容色。最终 126 已重新安装并截图确认上下分区、铰链避让及白色统计值。
- 动效依据包括开发前真实 iOS Ready→Glance 录屏与源代码参数、Pixel 连续计时画面，以及下一方案日历弹簧/逐格入场录屏；已检查帧和完成态。未进行高速摄影或定量帧率/弹簧轨迹拟合，不宣称像素级或时间曲线完全相同。
- 只临时将 Pixel `user_rotation` 从 0 改为 1 检查实际横屏，两次均恢复并读回 0；`accelerometer_rotation=0` 和熄屏超时 `2147483647` 保持原值。字体、语言、明暗和减少动态效果使用隔离预览的本地参数，未改系统设置。收尾读回 `font_scale=1.0`、三项动画倍率均 `1.0`；设备临时 UI XML/录屏已移除，最终隔离 126 留在主页供用户查看，未卸载或操作正式应用。

### 决策与剩余验证

- 按 Android 原生权限与通知呈现接入闹钟，不复制 AlarmKit UI；由于用户禁止，设备响铃、锁屏、精确授权/撤销、重启投递矩阵保持 NOT_RUN。代码完成和 pure/fake 通过不代表系统已接受或实际响铃通过。
- 云同步、Wear OS 仍遵循既有明确 deferred 边界；本轮不新增账号或上传工作记录。既有完整 Play 生命周期、物理换机、生产验证服务 CPU 余量继续保留，不因 UI 同步宣布完成。
- 日常实现与 UI/测试协作实际使用 GPT-6.1 Sol / high；架构复核使用 GPT-6 Astra / xhigh，未虚构更高模型调用。

- 本轮实现与 QA 已提交 [草稿 PR #305](https://github.com/ififi2017/Off-Work-Countdown/pull/305)。保留草稿供所有者集中确认；没有合并 main、触发正式发布或上传 Play。

### 2026-10-07 首启反馈回归（候选 127–128）

- 修复星期 Chip 自然宽度造成的 Mon–Sat / Sun 分行，按 iOS 实际截图采用七个等宽控件；大字与窄视口采用 4+3 / 3+2+2 平衡行，保留完整读屏名称。
- Reminders→Ready 的持续计时使用同一页面 transition 的 alpha/位移，初次测量不再套用 Ready↔Glance 的 500ms 几何衔接。隐私/购买覆盖页采用不透明 Surface，并隔离底页像素、语义、键盘与触摸；返回保留滚动和计时状态。
- Glance 使用分别对应实际 Android 小组件、持续通知的原生布局；小组件显示状态/进度，通知倒计时至绝对班次结束，不再只是改变同一张卡的宽度。零进度移除 Material 默认终点圆点。
- 补齐遗漏的 post-onboarding PlusIntro→取消→等待新 Play 权益/商品检查→合资格才揭示优惠 sheet→关闭 mark seen 流程，移除首启阶段提前展示的 OnboardingOffer。普通 Plus 返回不创建新邀请。已有设置、带设置恢复、What's New 完成和已购买用户跳过额外介绍；noBackup 标记支持中断与失败退路，独立于档案、更新介绍和购买证明。
- 最终统一 gates：domain 429 / data 94 / designsystem 12 / app 127，共 **662 项，0 failure/error/skip**；Lint **0 errors / 54 warnings / 4 hints**，Debug/R8 Release PASS；`check:version`、Android strings、`check:ios` 与本地 iOS headless simulator build PASS。日志 `doneat321-followup-128-build.log`、`doneat321-followup-ios-build.log` 位于 `/private/tmp/`。首轮 Lint 发现的新 API 读取已改为 minSdk 支持的字节读取，最终重跑全部 gates；只读首启预览宿主缺失也已修复并真机复验。
- USB Pixel 实测七天同排、提醒到完成录屏、隐私打开/返回、不同系统表面、最终 200% RTL 控件、浅/深零进度、首启实际进入 Plus、取消以及冷启动不循环。回归后恢复用户 QA 备份，settings/records 逐字节一致，128 留在主页；正式 Play 包未动。设备中途锁屏由用户恢复，agent 未锁屏/解锁或测试闹钟。
- [补充截图和录屏](../../qa/2026-10-07-android321/followup/README.md) 已记录版本与环境。隔离 QA 的真实商品不可用；实价优惠 sheet/购买仍 **NOT_RUN**，需注册 Play 包与许可测试账号查询，不能因代码/样例或测试通过声称真价可用。
