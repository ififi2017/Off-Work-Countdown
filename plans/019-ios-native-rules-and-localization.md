# 019 · iOS 规则与本地化回到 iOS 工程

- **状态**：IN PROGRESS — R1（排班与快照）已实现并同版修改 `AGENTS.md`；R2–R4 与本地化迁移未开工。
- **目标**：iOS 的排班、提醒、汇总与收入规则由 Swift 实现，iOS 文案由 iOS 工程按 Apple 规范存放。TypeScript 继续服务 Web 与 Desktop，并作为两端共有行为的规格与差分预言机。
- **起因**：iOS 与 Web／Desktop 的功能越来越分化，直接触发点是 [018 P8 扩展排班](018-ios-3.2.0-architecture-remediation.md)（班次类型、预制规则、自由日历），这是只在 iOS 提供的功能。继续把 iOS 专属规则写进共享 TypeScript bundle，会让 Web 背负用不到的规则；把 iOS 专属文案放在 `public/locales`，也让两端的文案维护互相牵连。
- **依赖**：[002 关于 JS 桥的迁移扳机与契约](002-records-life-focus.md)、[004 班次模型](004-shift-model-3.1.0.md)、[017](017-apple-watch-plus.md)、[018](018-ios-3.2.0-architecture-remediation.md)。
- **交付方式**：feature branch → PR → main，按入口分批；本计划不代表授权发布。

## 1. 与现有规定的关系

`AGENTS.md` 目前规定规则不得移植到 Swift，并带着案发记录：“本周”一行曾因两套实现给出不同数字。002 规定了迁移扳机（批量展开实测不达标，或 Web／Tauri 不再是一等消费者），并要求扳机触发时同版更新 `AGENTS.md` 与相关 ADR。

本计划新增的扳机是**产品分化**：用户于 2026-09-13 决定 iOS 规则独立。Web／Desktop 仍是一等消费者，所以两端**共有**的行为必须继续一致，只有 iOS 独有的行为可以只在 Swift 中存在。

- [x] 第一批迁移的同一个 PR 内修改 `AGENTS.md`：写明 iOS 规则由 Swift 实现、TS 作为共有行为的规格与差分预言机、iOS 专属规则只在 Swift 中实现；更新 002 中“关于 JS 桥”的结论。不允许出现代码已迁移而文档仍禁止迁移的中间状态。

## 2. 规则迁移

### 现状

iOS 通过 `CountdownRules.js`（由 `lib/countdown.ts`、`lib/reminders.ts`、`lib/summary.ts` 生成）在 JavaScriptCore 中调用 13 个入口：`snapshot`、`reminders`、`summarize`、`expandScheduleRange`、`widgetShifts`、`watchProjection`、`recordsIncome`、`recordsActualForecast`、`lifetimeIncome`、`salaryMonthlyEquivalent`、`validateBreak`、`shouldPromptApplyToday`、`rulesLoad`。桥接隔离在主 actor 上，边界是无类型的字典。Watch 端已经有一个只做比较和求和的 Swift 求值器，并用 TS 生成的 fixture 做差分测试，这是本计划的现成范例。

### 契约

- 以现有 `lib/*.test.ts` 为规格。由 TS 生成大区间 fixture（多年逐日快照、提醒序列、汇总与收入结果），覆盖跨夜、单双周、轮班锚点、午休切分、加班延长、夏令时与时区；Swift 实现逐项对齐，并在本地检查与 Xcode Cloud 中校验 fixture 是否过期。
- 共有行为的差分 fixture 继续由 TS 生成；iOS 专属行为（018 P8 的扩展排班）只写 Swift 测试，不回写 TS。
- 收入与薪资计算迁移时，必须保留“本周”一行不一致事件对应的回归用例。
- 迁移完成一个入口，就删除该入口的 JS 调用路径，不长期保留双实现开关。

### 迁移顺序（按入口增量，每批独立 PR）

- [x] **R1 排班与快照**：`snapshot`、`expandScheduleRange`、`widgetShifts`、`watchProjection`、`validateBreak`。这是 018 P8 的前置条件。
- [ ] **R2 提醒**：`reminders`、`shouldPromptApplyToday`；iOS 预排通知的触发时刻与文案参数逐条对齐。
- [ ] **R3 汇总与收入**：`summarize`、`recordsIncome`、`recordsActualForecast`、`lifetimeIncome`、`salaryMonthlyEquivalent`。
- [ ] **R4 移除桥**：删除 `CountdownRules.js` 的生成、打包、`ci_post_clone.sh` 中的生成步骤、`check:ios` 的相关检查与 JavaScriptCore 依赖；更新 `docs/XCODE-CLOUD.md` 与 `docs/PLAN-MOBILE.md`。
- [ ] 每批：完整串行 iOS 回归、`RecordsPerformanceTests` 串行测量（不得靠放宽阈值通过）、Widget／实时活动／Watch 输出回归。

## 3. 本地化迁移

### 现状

iOS 在运行时通过 `NativeLocalizer` 读取 `public/locales/<locale>/translation.json`（工程内为文件夹引用），复数沿用 i18next 的 `_one`／`_other` 后缀。粗略统计（按代码中出现的字面键，2026-09-13）：en 共 1056 个键，约 654 个只被 iOS 使用，121 个两端共用，131 个只被 Web／Desktop 使用，另有约 150 个为动态拼接或未直接引用。依赖这些文件的还有 `scripts/generate-watch-localizations.mjs`、营销截图与 App Store Connect 同步脚本。

### 方向

- iOS 文案迁入 iOS 工程，采用 Apple 的 String Catalog（`.xcstrings`），覆盖现有 19 个 UI locale，复数使用系统的复数规则替代后缀约定。`InfoPlist.strings` 一并评估是否迁入。
- Web／Desktop 继续使用 `public/locales`，并删除迁移后只有 iOS 使用的键。
- 两端共用的约 121 个键各自保存，不做运行时共享；由一致性检查脚本发现措辞分歧。

### 2026-09-13 用户决定

1. iOS 文案采用 String Catalog（`.xcstrings`）。
2. 两端共用的键需要脚本检查措辞一致：同一个键在 `public/locales` 与 String Catalog 中的译文不一致时报出，供人工判断是否属于有意分化。
3. Watch 文案生成器改为从 String Catalog 读取。

- [x] 确认以上问题。
- [ ] 迁移脚本：从 `public/locales` 生成 `.xcstrings`，逐键校验 19 个 locale 的值、占位符与复数一致；迁移后 `NativeLocalizer` 改为系统本地化或薄封装。
- [ ] 19 个 locale 完整性检查改为读取 `.xcstrings`；Watch 文案生成器、营销截图与 ASC 同步脚本改接新来源。
- [ ] 修改 `AGENTS.md` 中“UI 键必须加入 `public/locales/*` 的每个 locale”的规定：iOS 键进入 String Catalog，Web／Desktop 键进入 `public/locales`，两者都要求 19 个 locale 完整。
- [ ] 清理 `public/locales` 中只剩 iOS 使用的键，并确认 Web 与 Desktop 构建验证通过。

## 4. 验收

- [ ] 规则：各批差分 fixture 全部通过；完整串行 iOS 回归通过；性能测试串行测量未退化；Widget、实时活动与 Watch 输出与迁移前一致。
- [ ] 文案：19 个 locale 在 iOS 与 Watch 上无缺失、无占位符错误；复数与 RTL 抽查通过；Web 与 Desktop 的构建与输出验证通过。
- [ ] 文档：`AGENTS.md`、002、`docs/PLAN-MOBILE.md`、`docs/XCODE-CLOUD.md` 与本计划同步更新。
- [ ] 模拟器视觉检查按 `AGENTS.md` 的授权规则执行；真机体验由用户确认。

## 5. 实施记录

### 2026-09-13 · R1 排班与快照

- `ScheduleRules.swift`：当前班次、快照、下一班与下一休息日、Widget 班次、Watch 投影、区间展开与午休校验。实现的是 TS 的**带时区路径**；输入没有时区时用 `TimeZone.current`。原 bundle 只有少数调用方会走无时区路径，它与带时区路径的差别只在夏令时跳变的缺口里，以及一个已在带时区路径修掉的跨夜锚点偏移。无效时区标识回落到当前时区，不再抛错。
- `SalaryRules.dailySalary` 随快照迁入，并按 ECMAScript `Number()` 解析薪资字符串（空白、`0x`／`0o`／`0b`、`Infinity`）；R3 复用它。
- `ScheduleExpansionCache` 接替原 `CountdownRules` 的展开缓存；后台预取由 `@concurrent` 完成，删除第二个 JSContext（`ScheduleRangeEngine`）。
- JS 侧：`build-ios-native-rules.mjs` 只保留提醒、汇总、收入与 `shouldPromptApplyToday`；迁出的五个入口原样移入 `scripts/ios-schedule-rule-oracle.mjs`，只用于生成 fixture 与测试。Watch fixture 改读 oracle，重新生成后数值无变化。
- 差分契约：`npm run generate:ios-rule-fixtures` 生成 `AppTests/ScheduleRuleFixtures.generated.json`（约 1.4 MB）。覆盖 40 组「钟点 × 排班 × 时区」（9 个时区含 Lord Howe 半小时夏令时、Santiago、Chatham、St Johns），样本落在 2026 年各区夏令时切换窗口，包含亚毫秒 `nowMs`、加班、强制上班日与 16 种薪资字符串：2127 个快照、1064 个 Watch 投影、240 个午休校验、40 组短区间展开与 Widget 班次，另以 SHA-256 摘要比对两年逐日展开与 120 天 Widget 班次。比较均为逐值相等。`npm test` 与 Xcode Cloud `ci_post_clone.sh` 检查 fixture 是否过期。
- 验证：完整串行 iOS 回归 702 个测试、43 个 suite 通过（含新增 6 个 fixture 测试）；`npm test` 382 通过；`check:ios`、`check:watch-fixtures`、lint、`git diff --check` 通过。串行性能：十年展开 38 ms、一年 3 ms；`recordsDayCanvas` 3.6 ms；冷启动整段职业生涯 `prepareLifeViewModel` 859 ms；一年 `recordsMetrics` 5.4 ms。未做模拟器视觉检查；Widget、实时活动与 Watch 的真机输出回归待用户确认。
