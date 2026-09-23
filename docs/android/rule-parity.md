# 共享规则差分报告

Kotlin `:core:domain` 对 TypeScript oracle（`shared-rule-fixtures.json`，与 iOS `ScheduleRuleFixtures` 数据相同）的覆盖。比较方式与 Swift 一致：逐字段精确相等（IEEE `==`，不设公差）；长列表比 SHA-256 摘要。

更新：2026-09-23（T07）。

## 覆盖

| fixture 段 | 用例数 | Kotlin | 状态 | 任务 |
|---|---|---|---|---|
| snapshots | 2127 | `ScheduleRules.snapshot` | 全部通过 | T07 |
| widgetShifts / widgetDigests | 40 / 40 | `ScheduleRules.widgetShifts` | 全部通过（含 120 天摘要） | T07 |
| expansions / expansionDigests | 40 / 40 | `ScheduleRules.expandScheduleRange` | 全部通过（含两年摘要） | T07 |
| validateBreak | 240 | `ScheduleRules.validateBreak` | 全部通过 | T07 |
| applyToday | 400 | `ScheduleRules.shouldPromptApplyToday` | 全部通过 | T07 |
| reminders | 320 | — | 未实现 | T14 |
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
- **扩展排班未接入。** `CivilZone` 目前只有固定班次路径；按日班型、节假日、冻结历史在 T08 加入，届时以 Swift 导出的 fixtures 校验。
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
| 6 | 节假日 | 地区非空，且 overrides（若提供）或内置日历有该日 | 休：默认休息类型（无则无类型的休）；班：基础为工作日则保留、否则默认工作类型 |

未排的日期保留调用方的时钟，因此补班日仍有形状可用；有扩展计划时，未排日一律不是工作日，只有历史回退计划才落回基础班次。

### 不在 T08 范围

- `ExtendedScheduleEditing.swift`（排班编辑器的建类型、改周期、填充月份等）依附 `ShiftSessionStore`，属于编辑 UI，随 T15/T16 移植。
- 读取快照时叠加实时手排的 `RecordCoordinator.expandableHours(for:)` 属于记录层，随 T12 移植。
- 应用运行时需要打包 `HolidayTemplates.json`（与 iOS 共用同一文件），在接入 UI 时由 app 模块把它作为 asset 引用。

## 记录档案编解码（T10，iOS 独有）

`RecordJSON`（v1–v6 解码、逐行校验、三种合并模式、v6 导出）没有 TS oracle。`npm run generate:android-record-fixtures`（macOS）编译真实的 `RecordJSON` 与 14 个模型文件，对 88 份文档给出答案：6 份合成档案、5 份非法档案、每类实体的拒绝与默认值、旧字段迁移、生命档案/专注计划被拒后的提前返回、12 个合并场景。Kotlin `RecordJsonFixtureTest` 比较结果类型、各项计数、拒绝/冲突/采纳列表，以及规范化后的整份 v6 导出，全部通过。

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

