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
