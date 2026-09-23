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
| summaries、recordsIncome、monthlyEquivalent、lifetimeIncome、actualForecast | 322 / 80 / 32 / 160 / 120 | — | 未实现 | T09 |
| watch | 1064 | — | 不在首发（Wear 延后，D-05） | T27 |

## 有效性验证

测试不是空转：两处人为错误均被捕获，恢复后全绿。

| 植入错误 | 结果 |
|---|---|
| `payRatio` 乘 1.0000001 | snapshots 失败 |
| DST 重叠时刻取较晚一侧（`minOrNull`→`maxOrNull`） | 2 个测试失败 |

`ShiftExamplesTest` 另外锁定计划 02 §4.2 的算例（12:30 午休：已工作 3h、剩余 5h、收入 30；加班到 20:00 的 19:00：进度 90%、payRatio 1.125、收入 90 而非 72）以及空 workdays、manual、0 长度轮班、同一时钟（24h 班）和非法时钟不崩溃、不死循环。

## 与 Swift 的有意差异

- **时区必须显式传入。** Swift 在缺少标识时回退 `TimeZone.current`；Kotlin 的 `ScheduleRuleInput.zone` 是必填的 `ZoneId`，调用方传记录时区或设备时区，规则内部不读默认值。
- **扩展排班未接入。** `CivilZone` 目前只有固定班次路径；按日班型、节假日、冻结历史在 T08 加入，届时以 Swift 导出的 fixtures 校验。
- DST 策略沿用源规则（重叠取较早、空缺取其后第一分钟），不使用 `java.time` 自带的 gap/fold 选择。时区数据来自 JDK tzdb；fixture 覆盖的 9 个时区（含 Lord Howe、Chatham、Santiago）在 2026–2027 年与 ICU 结果一致。
