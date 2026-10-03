# 共享规则差分报告

Kotlin `:core:domain` 对 TypeScript oracle（`shared-rule-fixtures.json`，与 iOS `ScheduleRuleFixtures` 数据相同）的覆盖。比较方式与 Swift 一致：逐字段精确相等（IEEE `==`，不设公差）；长列表比 SHA-256 摘要。

规则对应说明更新：2026-10-03。执行结果与任务状态统一见 [progress.md](progress.md)。

## 覆盖

| fixture 段 | 用例数 | Kotlin | 状态 | 任务 |
|---|---|---|---|---|
| snapshots | 2127 | `ScheduleRules.snapshot` | 全部通过 | T07 |
| widgetShifts / widgetDigests | 40 / 40 | `ScheduleRules.widgetShifts` | 全部通过（含 120 天摘要） | T07 |
| expansions / expansionDigests | 40 / 40 | `ScheduleRules.expandScheduleRange` | 全部通过（含两年摘要） | T07 |
| validateBreak | 240 | `ScheduleRules.validateBreak` | 全部通过 | T07 |
| applyToday | 400 | `ScheduleRules.shouldPromptApplyToday` | 全部通过 | T07 |
| reminders | 320 | `ScheduleRules.reminders`（`ReminderRules`） | 全部通过（逐条 + 摘要） | T14 |
| summaries、recordsIncome、monthlyEquivalent、lifetimeIncome、actualForecast | 322 / 80 / 32 / 160 / 120 | `SummaryRules` | 全部通过 | T09 |
| watch | 1064 | — | 不在首发（Wear 延后，D-05） | T27 |

## 有效性验证

测试不是空转：两处人为错误均被捕获，恢复后全绿。

| 植入错误 | 结果 |
|---|---|
| `payRatio` 乘 1.0000001 | snapshots 失败 |
| DST 重叠时刻取较晚一侧（`minOrNull`→`maxOrNull`） | 2 个测试失败 |

`ShiftExamplesTest` 另外锁定计划 02 §4.2 的算例（12:30 午休：已工作 3h、剩余 5h、收入 30；加班到 20:00 的 19:00：进度 90%、payRatio 1.125、收入 90 而非 72）以及空 workdays、manual、0 长度轮班、同一时钟（24h 班）和非法时钟不崩溃、不死循环。

## 汇总与收入（T09）

`summary/SummaryRules.kt` 覆盖周期汇总（计时页"本周/本年"）、记录收入、月薪折算、人生收入和记录页实际/预测。两种工资口径分开且都只在这里计算：

- **计时页实时估算**（`summarize`）：日薪 × 已完成工作日 + 今日 payRatio。
- **记录页固定月薪**（`recordsActualForecast`，月薪时）：月薪按所在月份的自然日数分摊到可见日期，以 `asOfMs` 所在民用日分成实际/预测，请假不扣。日薪时按每天 `工作时长/计划时长` 计。

植入错误验证：固定月薪改按 30 天、接受重叠的职业区间、手动模式不计今天，各让 1 个测试失败。

**浮点与货币策略**：规则层与 TS/Swift 一样全程用 `Double`，按同样的运算顺序，测试逐位相等；不在中间步骤舍入。金额只在显示时按币种最小单位格式化（UI 任务负责），输入保留用户键入的文本并用 `JavaScriptNumber` 解析。

`LifeViewCalculator`（人生页的工作/生活时间分配）是 iOS 独有逻辑，依赖记录模型，随 T12/T17 移植，届时用 Swift 导出的 fixtures 校验。

## 与 Swift 的有意差异

- **时区必须显式传入。** Swift 在缺少标识时回退 `TimeZone.current`；Kotlin 的 `ScheduleRuleInput.zone` 是必填的 `ZoneId`，调用方传记录时区或设备时区，规则内部不读默认值。
- **扩展排班以 Swift 为规范。** Kotlin 已接入按日班型、节假日、冻结历史和年度范围，通过下文的 Swift oracle 校验。
- DST 策略沿用源规则（重叠取较早、空缺取其后第一分钟），不使用 `java.time` 自带的 gap/fold 选择。时区数据来自 JDK tzdb；fixture 覆盖的 9 个时区（含 Lord Howe、Chatham、Santiago）在 2026–2027 年与 ICU 结果一致。

## 扩展排班（T08，iOS 独有）

没有 TypeScript oracle，Swift 即规范。`npm run generate:android-extended-fixtures`（仅 macOS）用 `swiftc` 编译真实的 `src-mobile/ios/Shared` 与规则模型，加上 `scripts/android-extended-fixtures/main.swift`，把 Swift 的答案写成 `extended-schedule-fixtures.json`；iOS 测试目标不改。`npm test` 在任何平台检查文件头记录的 Swift 源文件哈希，Swift 一改即失败；`check:android-extended-fixtures` 在 macOS 上完整重算比对（已验证输出确定）。

| fixture 段 | 用例 | Kotlin | 状态 |
|---|---|---|---|
| days（14 个计划 × 3 段日期） | 3136 天 | `ExtendedScheduleResolver.day` | 全部通过 |
| snapshots | 1728 | `ScheduleRules.snapshot`（带扩展计划） | 全部通过 |
| widgetShifts / expansions | 48 / 48 | 同 T07 入口 | 全部通过 |
| validateBreak / applyToday | 192 / 240 | 同上 | 全部通过 |
| timelines（夜班后清晨的原始窗口） | 1764 | `CivilZone.shiftTimeline` | 全部通过 |
| plannedHours | 24 × 40 天 | `CivilZone.plannedHours` | 全部通过 |
| shiftTypeValidity / dayKeys / contentValidity | 22 / 19 / 14 | 校验函数 | 全部通过 |

计划覆盖：周规则（锚点前用 floorMod）、14 天轮换、手排（含未知类型、归档类型、无效类型、非法 key）、按日号沿用上月（短月 29–31、闰年 2 月）、已编辑月份的空白日、`clearedFromDayKey`（有无规则两种）、CN 节假日与调休、显式 overrides、关闭节假日、归档默认类型、历史冻结（含/不含旧行）、从 `ExtendedSchedule` 构建、`pinning`。时区：上海、柏林、纽约（含 3 月夏令时）。

植入错误验证：沿用月份取错、忽略 `clearedFromDayKey` 各让 6 个测试失败；去掉"昨夜夜班仍在进行"的回看、昨夜用今天的时钟，分别让 1 个和 3 个测试失败。第三项最初未被捕获（`resolveCurrentShift` 的结算回退掩盖了它），因此新增了 timelines 段。

### 优先级决策表

同一天由第一个命中的层决定（`ExtendedScheduleResolver.resolve`）：

| 顺序 | 层 | 条件 | 结果 |
|---|---|---|---|
| 1 | 冻结类型 | 该日有有效的 `assignedShiftType` | 按冻结类型；来源 handSet |
| 2 | 手排 | 该日在 `handSetDays`（含 `pinning` 的日） | 按类型；类型未定义或无效 → 未排 |
| 3 | 历史回退 | `fallsBackToBaseSchedule` | 未排；`CivilZone` 改用基础班次 |
| 4 | 清空 | 无规则且日期 ≥ `clearedFromDayKey` | 未排 |
| 5 | 规则 / 沿用 | 有规则且锚点有效 → 周期位置；否则按日号沿用最近的已编辑月份 | 基础结论 |
| 6 | 年度范围 | 基础结论为工作日，且命中活动工作类型的年度月／日范围 | 替换工作类型和时间；保留休息和未排日期 |
| 7 | 节假日 | 地区非空，且 overrides（若提供）或内置日历有该日 | 休：默认休息类型（无则无类型的休）；班：基础为工作日则保留、否则默认工作类型再应用年度范围 |

未排的日期保留调用方的时钟，因此补班日仍有形状可用；有扩展计划时，未排日一律不是工作日，只有历史回退计划才落回基础班次。

### 2026-09-30 年度范围兼容增量

`AnnualShiftDateRange` 支持包含首尾的年度月／日范围、跨年和闰日；活动工作类型的范围不可重叠。手排和冻结日期仍先返回，年度范围不改变休息日；移除规律时保留年度范围解析出的时间。

本次 Swift oracle 扩展至 18 个计划、2,376 个 snapshots、66 组 widgetShifts／expansions，覆盖季节边界、沿用月份、节假日、冻结历史和归档类型。`RecordJson` 与快照配置保留年度字段，记录 oracle 共 102 份文档，新增合法范围、无效日期、休息类型、重叠、缺少边界及冻结历史的导入／导出案例。两个 fixture 完整比对及 domain／data 回归通过；iOS 年度编辑入口不在本次 Android UI 范围内。

### 2026-10-02 请假叠加层（计划 020，已移植）

iOS 在 `ExtendedSchedulePlan` 上新增 `leaveDays`（民用日 → 整班／前半班／后半班）与 `baseHours`（回退计划下的固定时间），解析器在其余层之后叠加：整班改为休息，半班按有效工作分钟（去掉班内休息）换算为剩余一半的起止与休息，只作用于原本上班的日子；固定排班用户用只含请假的回退计划表达，`.leaveOverBase` 的上班与否仍由固定排班判断。记录层把请假作为 `DayRecordLookup` 的一层，排在人工修正之后、节假日与排班之前。计划编码在没有请假时与此前逐字节相同，因此两份 Swift fixture 只更新了源哈希，现有答案不变。

Kotlin 对应：`ExtendedSchedulePlan.applying`、`LeavePortion`、`ExtendedScheduleDayHours.remaining(after:)`、`CivilZone.plannedHours` 的回退分支；`DayRecordResolver` 的请假层；`ShiftSession.rulesInput` 与 `ScheduleChange.rulesInputApplying` 把已采用的请假叠加到倒计时、提醒、小组件与汇总，`hoursConfiguration` 仍读去掉请假的计划。规划器 `leave/LeavePlanner`、`LeavePlannerSchedule`（滚动一年、前后各 31 天上下文）与 `LeaveAdoption`（整体采用或拒绝、撤销整份计划、取消单日、余额增改与删除）逐条对应 Swift。

共享 fixture 没有请假用例（生成需 macOS 上的 Swift）。改为移植 iOS 测试：`LeavePlannerTest` 15 条、`LeaveAdoptionTest` 4 条、`LeaveOverlayTest` 13 条（含一条 Android 会话层用例），全部通过。未移植：Watch V2 编码（无 Kotlin 对应）、`UserDefaults` 试用次数持久化（Android 为 `DeviceSettings.leavePlannerTrialsUsed`）、`LeaveRecordsTests`（编解码已由 T10 覆盖）。

### 不在 T08 范围

- `ExtendedScheduleEditing.swift`（排班编辑器的建类型、改周期、填充月份等）依附 `ShiftSessionStore`，属于编辑 UI，随 T15/T16 移植。
- 读取快照时叠加实时手排的 `RecordCoordinator.expandableHours(for:)` 属于记录层，随 T12 移植。
- 应用运行时需要打包 `HolidayTemplates.json`（与 iOS 共用同一文件），在接入 UI 时由 app 模块把它作为 asset 引用。

## 记录档案编解码（T10，iOS 独有）

`RecordJSON`（v1–v6 解码、逐行校验、三种合并模式、v6 导出）没有 TS oracle。`npm run generate:android-record-fixtures`（macOS）编译真实的 `RecordJSON` 与 14 个模型文件，对 88 份文档给出答案：6 份合成档案、5 份非法档案、每类实体的拒绝与默认值、旧字段迁移、生命档案/专注计划被拒后的提前返回、12 个合并场景。Kotlin `RecordJsonFixtureTest` 比较结果类型、各项计数、拒绝/冲突/采纳列表，以及规范化后的整份 v6 导出，全部通过。

上段为 T10 初始差分记录；当前协议已扩展为 **schema 7，接受 1–7、导出 7**，假期余额与请假日随档案编解码。原子 `RecordLocalFile` 封装与备份文档保持分离，未引入 Room。

植入错误验证（均被捕获）：`UTC` 不改写为 `GMT`、去掉生命档案被拒后的提前返回、同 editCount 时 tie-break 反向、睡眠分钟改为四舍六入五成双、接受无填充 base64。其中睡眠用例起初取值 7.00833 小时不能区分舍入方式，已改为 2.875 小时（172.5 分钟）。

Foundation 行为（`FoundationCompat`）：`UTC`→`GMT`、`GMT+8`→`GMT+0800`、缩写（`EST`、`PST` 等）保留原样；UUID 严格 8-4-4-4-12、输出大写；日期键需 4-2-2 位且为真实公历日期；`PartialCivilDate` 的计算锚点按 `Calendar` 宽松进位（2 月 30 日 → 3 月 1 日）；`Double.rounded()` 为远离零的四舍五入；旧 `editedAt` 为 2001 年起的秒；base64 必须带填充。

与 iOS 的有意差异：民用日期在内存中保持 `YYYY-MM-DD` 标签而非 `Date`，对所有合法输入与 iOS 的"日期→标签"往返结果相同；行级时区无效时 iOS 导出可能退回设备时区，Android 始终保持标签不变。

## 日记录解析与编辑（T12）

- **解析**：`DayRecordResolver` 与 iOS 一一对应，`DayRecordResolverTests` 17 条逐条移植。顺序固定为：有效日修正 → 日历例外（用户优先，其次较新的内置数据集）→ 当日生效的快照（同日按 editCount、tie-breaker、id 排序）；`cleared` 一律向下落。`baseSchedule*` 保留快照原计划，供记录收入使用，请假和临时修改不改写薪资历史。
- **唯一入口**：`RecordHistory.expandableHours(state, snapshot, holidays)`。扩展快照保留当时的班型与规则，叠加当前手排（以及之后新建的班型）；固定快照叠加冻结的历史分配，且只在早于第一个扩展快照时才叠加旧行。直接解码 `configurationData` 会丢失这些叠加，因此其它代码不直接解码。
- **快照编码**：`ScheduleHoursCodec` 写出与 Swift `JSONEncoder(.sortedKeys)` 逐字节相同的 JSON，因此同样的班次在两端得到同一个 SHA-256 指纹。record oracle 新增 11 个用例；首次运行即发现 Kotlin 会把 `1767571200000.5` 写成 `1.7675712000005E12`，已改为普通小数。
- **编辑**：`RecordEdits` 是纯函数，由 `RecordStore.update` 执行，因此一次编辑涉及的所有层要么一起落盘，要么都不落盘。盖戳规则、相同内容不写、墓碑之上复活（editCount 高于被埋版本）、首次写入播种、同日快照改写均与 iOS 相同。与 iOS 的有意差异：写入失败时 iOS 在内存中保留修改，Android 不发布（T10 验收要求）。

植入错误验证：例外先于修正（2 条失败）、旧行叠加到所有固定快照（1 条）、复活忽略墓碑（1 条）、自定义工时丢掉午休（1 条）。第二项起初未被捕获，已补上"扩展之后再回到固定工时"的用例。

## 专注生命周期（T13a）

- **网格**：`FocusPlanner.workBlocks` 只由有效段与节奏决定（与时钟无关），轮次跨午休连续计数；放不下的阶段结束该段，不拉伸休息、不跨午休或下班。`FocusPlannerTests` 的 13 条纯函数用例逐条移植（Live Activity 相关用例属 iOS 专有）。与 iOS 的差异：块边界以整数毫秒保存，不经秒级浮点往返。
- **身份**：自动块 `owc.focus.block.v1|…`、自动休息 `owc.focus.recovery.v1|…`，SHA-256 前 16 字节并置版本/变体位；与交接包 `acceptance_examples.json` 的两个向量一致。
- **生命周期**（`FocusEngine`，纯函数，环境注入）：同时最多一个进行中会话；无空间、非工作时段、未授权、未到时间的任务均拒绝开始；计划块内开始不越过块终点。阶段在自身计划终点以计划原因结束，无论应用多晚醒来；完成块只计一次，边界截断与手动停止不计；任务在完成块数达到预估时才完成。完成后的休息从块的计划终点开始，但只有在应用返回时其窗口仍开着才开始，不回填；两台设备得到同一个派生 id。重启或同步后，最早（再按 id）的进行中会话胜出，其余以 `supersededBySync` 结束并保留为历史；冷启动从当天历史恢复下一步提示，新班次不沿用昨天的提示。

植入错误验证：休息用随机 id（1 条失败）、首块即完成任务（7 条）、回填已过窗口的休息（2 条）、收敛时反向排序（1 条）。编写测试时 7 条失败均属测试场景：iOS 测试所用班次的网格对齐不同，此处在 14:00 恰好是第 8 轮而应长休；已改为偏离网格并新增"网格决定休息类型"的用例。

## 专注计划与画布（T13b）

- **存储**：计划、模板、默认模板、已自动应用的日期与节奏都在档案的 `FocusPlanningConfiguration` 中，每次变化重新盖章；内容未变不写入。块以网格上的 `startAtMs` 寻址。任务只能进工作块；工作块可改为休息且可撤回；网格自带的休息不可编辑，但读取时总是休息（与 iOS `focusAssignment(for:)` 一致）。
- **画布**：`FocusPlanning.canvas` 一次解析块状态（过去/当前/未来）、午休与段尾空隙、任务行（已完成/已排/预估三个数分开）与溢出；下班后画下一个班次，写入也落在那一天。未授权时只有形状，不读任何分配、任务或会话。
- **模板**：保存时记录任务顺序与轮数，不记时钟；应用时只放能整块放下的任务前缀，不跳过放不下的任务去放后面的。重新应用未变的模板不产生任何写入。编辑模板只重排仍关联的日子（从今天起），已开始或进行中的块保留；手动编辑任意一块即分离当天。被移出的模板任务：有历史、收藏或仍被其他日子引用则转为普通任务，否则软删除，再次应用时复活同一行。模板任务的预估随计划变化，但不低于已完成轮数；手动任务的预估不变。存在模板时拒绝修改节奏。
- **放置**：创建与预览共用 `creationBlocks` 投影，跳过他人任务的块并跨过午休；再加一轮只取紧接的下一块，遇到他人任务或用户休息报冲突、遇到午休报无空间。
- **自动会话**：分配即授权。当天剩余的已分配块排队为派生 id 的会话（本地，不同步）；恢复时按块自身的开始时间记录，醒得晚不会重开，已被清除的块不记录，重复恢复不产生第二条。

植入错误验证：被其他计划引用的模板任务被删除、段尾空隙消失、再加一轮冲突报成无空间、重排不保留已开始的块、默认模板重复应用、自动会话以醒来时间开始、已清除块仍被记录、未授权画布泄露分配、有模板时仍可改节奏、投影覆盖他人任务、改名不按完成轮数抬高模板任务预估、整任务前缀跳过放不下的任务（后两项起初未被捕获，已补用例）。等价变异：去掉"未变模板直接返回"的短路（纯函数下结果本就相同，测试以 `assertSame` 断言）；投影中重复的用户休息判断。

## 提醒（T14）

- **规则**：`ReminderRules.buildShiftReminders` 逐条对应 `lib/reminders.ts`：里程碑阈值向上取整后落到有效段，恰好在段末时于段末触发；文案池以班次结束时刻为种子，结束时刻带小数时与 TS 一样取不到文案；健康提醒每段重新计数，单段上限 240 条；`{{minutes}}` 只替换第一处。ID 中的时刻按 JS `String(number)` 输出（整数不带小数点，小数取最短表示）。`selectDueReminders` 供桌面端逐拍消费，Android 与 iOS 一样一次性预约，不移植。
- **周期总结**：`ScheduleCycleSummaryCalculator` 与 iOS 一致：只有紧接一个已解析的休息日时才成立，周期内任一天未解析则不发。加班取当天最后一次申报，开始时刻不早于当天常规工作结束。
- **专注**：`FocusReminders.alerts` 对应 iOS `focusAlerts`（块结束与其后休息结束两条，固定槽位 ID）；计划接管只替换当前班次范围内的健康提醒，改为计划中的长休息，下一班次不动。
- **调度**：`ReminderPlanner` 对应 iOS `performReschedule` 的筛选（将来、有文案、提前下班只留下一班次、关键提醒优先、60 条上限），另加 Android 需要的差量、重启恢复与定时方式选择。

植入错误验证（25 项，全部被捕获）：规则 5 项（午休开始有效期不截断、小数结束时刻仍取文案、健康提醒跨段计数、替换全部占位符、总结不 trim）；规划 6 项（关键提醒不优先、提前下班不过滤、差量忽略内容变化、恢复时补发、闹钟时刻向下取整、休息日窗口照样提醒）；周期与专注 7 项（后一天未解析、加班与常规重叠、取最早申报、最后一块仍排休息、接管范围扩到下一班次、短休息也提醒、无任务的计划也接管）；登记 7 项（授权变化不重登、拒绝后不重试、重复触发、提前触发、过期仍发、覆盖其他前缀、前台每次都恢复）；另有 1 项等价变异（恢复时强制重登，与原逻辑结果相同）已删去冗余代码。起初未被捕获的 4 项已补用例。共享 fixture 中没有短于 2 分钟的午休，因此"午休开始有效期截断到午休结束"目前只由 Kotlin 单测锁定，建议日后在 TS oracle 中加入这类档案。

## 2026-10-03 · Android 3.2.1 增量规则对应

本节采用经授权的 iOS 固定提交 `18129168acd23edc3a872cca3633a2831f60c6f2`（[PR #281](https://github.com/ififi2017/Off-Work-Countdown/pull/281)），对应 Plan 020 与本轮暂停翻页修复；原冻结源 `9252fdfdc66aab88b4acb7493684f11991fd773d` 继续作为其余移植范围的基线。下面说明代码契约及测试入口，执行结果、设备证据和剩余工作仅记入 [progress.md](progress.md)。

### 动态周、月、年报

- `records/CycleReport` 对应 iOS `CycleReport`：周按调用方传入的周起始日，月、年按自然周期；周期保存首尾日期与记录时区。历史周报的邻接周期沿用已保存的周边界，语言改变不会重新定位原周期。API 26 使用已有 `java.time` 与字符串编码接口，不依赖较新的 `LocalDate.datesUntil`、Stream 收集或 Charset 编解码重载。
- `RecordsQueries.cycleReportSnapshot` 对应 `RecordsQueries+CycleReport` 与 `CycleReportInsights`：同一档案版本和参考时刻一次构造报告，工时、加班、收入复用 `SummaryRules.recordsActualForecast`。日图表按民用日裁切并截至参考时刻，未知或解析失败的日期不冒充完整休息日；未来工时、加班和尚未完成的当日请假时段不计为已发生。
- 历史周、月的后续连休以报告结束日为锚点，展示具体日期，不带当前余额。年报包含全年工时、加班、完整休息日、最长连休、已休假期及 12 个月趋势；专注按已完成的记录统计，年报没有后续连休或同比基线。年度解析结果供月度统计复用。
- `CycleReportSnapshot.withoutIncome` 同时剥离总收入、收入章节及 12 个月的收入。报告收入选择以全局隐藏设置为默认值，主动显示复用 `EarningsGate`，本次选择不写回全局设置。Compose 只格式化快照，不重新计算业务统计。
- `CycleReportPlayer` 对应 iOS 播放器：主动暂停和按住暂停分别保存；主动暂停后前后翻页立即展示完成帧，临时暂停保持播放时序。文字简报、TalkBack 和减少动画路径静态展示同一快照；动效复用 `DoneAtMotion`。

测试入口：领域 `CycleReportTest`、`RecordsQueriesTest`；应用 `CycleReportPlayerTest`。覆盖周期与闰年、未知日期、当日累计、收入剥离、历史连休、年度月度趋势、暂停导航及临时暂停语义。

### 报告通知与旧开关迁移

`CycleReportNotificationPlan` 分别规划周、月、年报告，触发点为周期结束后第一天记录时区 09:00；1 月 1 日年报指向上一年。首日上午 09:00 前重排保留刚结束的周期。`CycleReportCoordinator` 使用独立报告前缀，复用绝对预约与差量登记，不套用 iOS 待发通知容量预算。通知登记保存报告 URI 内的类型、周期首尾和时区，冷、热启动均经 `CycleReportPeriod.fromUrl` 校验后路由；正文和 URI 均不含薪资。

`SettingsRepository` 的迁移直接读取档案源，避免异步偏好流尚未追上恢复档案时丢失旧开关。旧静态周期总结迁到周报，月报和年报默认关闭；计时提醒停止构造旧静态总结，并由其原前缀差量更新预约。通知权限和精确提醒能力继续遵守已有 Android 授权与降级规则。

测试入口：`CycleReportTest` 的首日上午、独立开关与 URI 边界；`SettingsRepositoryTest` 的恢复档案先于派生流的迁移用例；既有 `ReminderSyncTest` 的登记、恢复和差量契约。设备通知点击、系统授权及后台送达证据见进度文档。

### 休假试用与免费加班入口

`LeavePlannerSchedule.rollingYear`、`LeaveShiftHalves`、`LeaveAdoption` 继续复用滚动一个日历年、有效段等分及整份原子采用规则。撤销按仍属于原计划的请假日删除，后来单独修改的日期与排班层保留，余额由现存请假使用量推导。

`DeviceSettingsStore.consumeLeavePlannerTrial` 在设备设置的同一锁内检查并持久化详情试用次数，成功后才导航；每次重开详情计一次，共三次。搜索和耗尽后的列表浏览不扣次数；写入失败保持次数与页面。计数不进入业务档案。`SettingsRepositoryTest` 覆盖并发请求、重启与写入失败；`LeaveAdoptionTest` 覆盖单日取消、整份撤销及后来替换的保留。

`RecordsQueries.recordedOvertimeMs`、`lifetimeRecordedOvertimeMs` 只向免费界面交付记录加班总量，日、周、月、年、人生入口不因此构造付费详情或收入。日详情仍遵守历史锁定；尚未发生的申报加班不计入。免费周、月页复用已经解析的日期窗口，避免重复展开排班。相关统计口径由 `RecordsQueriesTest` 锁定，不从人生投影推算历史加班。

### 班次闹钟纯规则与平台边界

`alarms/ShiftAlarmPlanner` 对应 iOS `ShiftAlarmPlanner`，输入为既有 `ScheduleRules` 最终排班（含手排、节假日、跨夜及请假叠加）、班次提前量和明确的权益边界。ID 使用与 iOS 相同的 SHA-256 派生 UUID；`ShiftAlarmReconciliation` 提供去重、差量、实际成功预约覆盖及最后成功闹钟后 10 分钟的刷新规则。九分钟贪睡也受精确到期边界约束。

授权输入明确分为无法验证、终身与已验证精确到期时刻；终身窗口按记录时区滚动一个日历年，订阅严格排除到期时刻及其后。取消自动续订本身不改变已付费周期。普通 Play Billing `Purchase` 不提供可供本规则使用的已验证精确到期时刻，因此现有活跃 Plus 布尔值不能代替该输入，也不从购买日期或商品周期猜算。

这些类是纯 JVM 规则，**没有开放 Android 起床闹钟的平台集成或产品开关**。它们不证明原生响铃、锁屏、后台、重启、权限变化、停止或贪睡已经可用。起床闹钟需要真正的响铃生命周期与系统预约接口，普通通知不可替代；须与现有 `SCHEDULE_EXACT_ALARM`、无轮询的架构约束一起解决。iOS `stopIntent` 自动补排仍未实现，不能作为 Android 已验证能力。

测试入口：`ShiftAlarmPlannerTest`，包含排班、节假日与调班、请假、跨夜提前量、精确到期、滚动日历年、稳定 ID、差量、成功覆盖、刷新时刻、关闭清理规则与贪睡边界。这些测试不等同平台预约或设备响铃验收。
