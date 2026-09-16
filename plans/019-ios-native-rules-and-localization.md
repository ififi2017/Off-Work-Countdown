# 019 · iOS 规则与本地化回到 iOS 工程

- **状态**：IN PROGRESS — 规则迁移 R1–R4 已完成（iOS 不再包含 JavaScriptCore 规则包）并同版修改 `AGENTS.md`；本地化迁移未开工。
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
- [x] **R2 提醒**：`reminders`、`shouldPromptApplyToday`；iOS 预排通知的触发时刻与文案参数逐条对齐。
- [x] **R3 汇总与收入**：`summarize`、`recordsIncome`、`recordsActualForecast`、`lifetimeIncome`、`salaryMonthlyEquivalent`。
- [x] **R4 移除桥**：删除 `CountdownRules.js` 的生成、打包、`ci_post_clone.sh` 中的生成步骤、`check:ios` 的相关检查与 JavaScriptCore 依赖；更新 `docs/XCODE-CLOUD.md` 与 `docs/PLAN-MOBILE.md`。
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
- [x] 迁移脚本：从 `public/locales` 生成 `.xcstrings`，逐键校验 19 个 locale 的值、占位符与复数一致；迁移后 `NativeLocalizer` 改为系统本地化或薄封装。—— 2026-09-16 L1，见下方实施记录。
- [ ] 19 个 locale 完整性检查改为读取 `.xcstrings`；Watch 文案生成器、营销截图与 ASC 同步脚本改接新来源。
- [x] 修改 `AGENTS.md` 中“UI 键必须加入 `public/locales/*` 的每个 locale”的规定：iOS 键进入 String Catalog，Web／Desktop 键进入 `public/locales`，两者都要求 19 个 locale 完整。—— 2026-09-16 L1。
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
- 差分契约：`npm run generate:ios-rule-fixtures` 生成 `AppTests/ScheduleRuleFixtures.generated.swift`（约 1.4 MB；JSON 以原始字符串编进测试二进制，因为 AppTests 没有资源构建阶段，Xcode Cloud 也在没有源码的主机上跑测试）。覆盖 40 组「钟点 × 排班 × 时区」（9 个时区含 Lord Howe 半小时夏令时、Santiago、Chatham、St Johns），样本落在 2026 年各区夏令时切换窗口，包含亚毫秒 `nowMs`、加班、强制上班日与 16 种薪资字符串：2127 个快照、1064 个 Watch 投影、240 个午休校验、40 组短区间展开与 Widget 班次，另以 SHA-256 摘要比对两年逐日展开与 120 天 Widget 班次。比较均为逐值相等。`npm test` 与 Xcode Cloud `ci_post_clone.sh` 检查 fixture 是否过期。
- 验证（R1）：完整串行 iOS 回归 702 个测试、43 个 suite 通过（含新增 6 个 fixture 测试）；`npm test` 382 通过；`check:ios`、`check:watch-fixtures`、lint、`git diff --check` 通过。串行性能：十年展开 38 ms、一年 3 ms；`recordsDayCanvas` 3.6 ms；冷启动整段职业生涯 `prepareLifeViewModel` 859 ms；一年 `recordsMetrics` 5.4 ms。未做模拟器视觉检查；Widget、实时活动与 Watch 的真机输出回归待用户确认。

### 2026-09-15 · R2 提醒

- `ReminderRules.swift` 移植 `buildShiftReminders`：五档里程碑（有效工时向上取整后逐段落点）、午休开始／结束的新鲜度窗口、按段重新计时的健康提醒（每段最多 240 条）、标题与文案池的兜底链，以及以班次结束时刻为种子的文案轮换。结束时刻带小数毫秒时，TS 取不到文案池下标而省略正文，Swift 同样返回无正文。
- `ScheduleRules.reminders` 复用 R1 的当前班次与下一班，按 `current:<end>:`／`next:<end>:` 重新编号后稳定排序；`ScheduleRules.shouldPromptApplyToday` 在当前或编辑后任一时间轴今天是排班日时返回 true。TS 版的 `kind` 与 `schedulePatternChanged` 两个分支本就同值，Swift 不再传入，`ScheduleFieldChange.changesSchedulePattern` 随之删除。
- 两个入口不再抛错，`shiftReminders` 与各调用方去掉 `try`；JS bundle 只剩汇总与收入，公共胶水移入 oracle。
- 差分契约：fixture 版本升到 2，新增 6 组提醒输入（空标题与空文案池、空模板、重复 `{{minutes}}`、修剪后为空的周期摘要、关闭／负数／1 分钟封顶／常规间隔）。320 个提醒用例逐条比对 SHA-256 摘要，其中 148 个带完整行（51 个为小数毫秒加班，16 个出现“有标题无正文”的里程碑）；400 个“是否询问今天”用例，true 343、false 57。
- 验证：完整串行 iOS 回归 705 个测试、43 个 suite 通过（含新增 2 个 fixture 测试）；`npm test` 382 通过；lint、`check:ios`、`check:ios-rule-fixtures`、`check:watch-fixtures`、`git diff --check` 通过。串行性能测试断言全部通过（一年 `recordsMetrics` 5.1 ms）。未做模拟器视觉检查；通知实际投递待真机确认。

### 2026-09-15 · R3 汇总与收入

- `SummaryRules.swift` 移植五个入口：`summarize`（显式区间起点优先，否则按时区的周一或元旦；按民用日数已完成排班日，当前班次按进度折算；手动模式不数已完成日、今天仍计入）、`recordsIncome`（`completedWorkdayIncome`）、`salaryMonthlyEquivalent`、`lifetimeIncome`（`YYYY-MM-DD` 按 `Date.UTC` 往返校验，100 年以前的年份同样拒绝；按当月实际天数折算；区间重叠整体返回 0；收入递减）与 `recordsActualForecast`（区间合并、开始／结束观测配对、固定月薪按当月天数逐日摊分）。五个入口都不再抛错。
- Swift 侧删除 JavaScriptCore 桥：`CountdownRules` 类、`CountdownRulesError`、启动时的预热、只为桥存在的 `NativeRecordsIncome`／`NativeRecordsIncomeInput`／`NativeMonthlySalaryEquivalent`，以及已无人写入也无人读取的 `ShiftSession.lastRulesError`。`CountdownRules.js` 仍生成并打包，但已无入口，由 R4 连同生成、打包与检查一起删除。
- 已知差异：固定月薪摊分遇到无效时区标识时，TS 的 `Intl` 抛错导致整期收入为空；Swift 按 R1 的约定回落到当前时区。应用只传入系统提供的时区标识，fixture 不覆盖这一情况。
- 差分契约：fixture 版本升到 3。322 个汇总用例，前两行是 fa927fb 的“本周”事件（周三下午班次过半应为 2.5 天、22.5 小时、2500，另一行为手动模式 0.5 天），其余由各 profile 的实时快照喂入，含过期两天的快照、年视图与显式起点；80 个记录收入与 32 个月薪等价（覆盖全部 16 种薪资字符串）；160 个终身收入（77 个非零，19 个经过收入递减，含非法日期、未补零日期与重叠区间）；120 个实际与推算区间（每种实际类型及未知类型、重叠加班、未配对观测、重复与不存在的日期键、小数毫秒 `asOf`，26 个为固定月薪）。原有的 `recordsIncomeUsesCompletedScheduledDays`、`recordsIncomeAbsentWithoutSalary` 与提前下班后的周汇总测试保留，现在直接跑 Swift 实现。
- 验证：完整串行 iOS 回归 709 个测试、43 个 suite 通过（含新增 4 个 fixture 测试）；`npm test` 382 通过；lint、`check:ios`、`check:ios-rule-fixtures`、`check:watch-fixtures`、`git diff --check` 通过。串行性能：一年 `recordsMetrics` 4.9 ms、记录列表 3.1 ms。未做模拟器视觉检查。

### 2026-09-15 · R4 移除桥

- 删除 `scripts/build-ios-native-rules.mjs` 与 `npm run build:ios-native-rules`；工程中 `CountdownRules.js` 的文件引用、构建文件与 Resources 阶段条目；`src-mobile/ios/.gitignore` 对应条目；`ci_post_clone.sh` 的生成步骤与存在性检查；`qa:ios-shots` 与 iOS 营销截图脚本的生成步骤。
- `createRulesScript` 移入 `scripts/ios-schedule-rule-oracle.mjs`，只服务 fixture 生成与测试；`build-ios-native-rules.test.mjs` 改名为 `ios-schedule-rule-oracle.test.mjs`，删掉只检查空 bundle 的一项。
- `check:ios` 改为要求 Xcode Cloud 脚本运行 `check:ios-rule-fixtures`，并在工程引用或磁盘上重新出现 `CountdownRules.js` 时失败（放入假文件实测会失败）。
- 文档：`AGENTS.md`（概述、规则边界、iOS 构建、归档与 Xcode Cloud 段落）、`docs/PLAN-MOBILE.md`、`docs/XCODE-CLOUD.md`（含路径过滤与本机等价命令）、`docs/IOS-TIMER-SURFACES.md`、002，并在 `docs/ADR-MOBILE-D0.md` 加注已被本计划取代。评审、交接等历史记录保持原文。
- 验证：完整串行 iOS 回归 709 个测试、43 个 suite 通过（全新 DerivedData），产物 `App.app` 中不含 `CountdownRules.js`；`npm test` 381 通过（少的一项即删除的 bundle 测试）；lint、`check:ios`、`check:ios-rule-fixtures`、`check:watch-fixtures`、`ci_post_clone.sh` 语法检查与 `git diff --check` 通过。串行性能：一年 `recordsMetrics` 4.9 ms。未做模拟器视觉检查；Xcode Cloud 上的实际运行以 PR 检查为准。

### 2026-09-16 · L1 String Catalog 迁移

- **生成器**（`scripts/generate-ios-xcstrings.mjs`，`npm run generate:ios-xcstrings` 与 `check:ios-strings`）：由 `public/locales` 生成 `src-mobile/ios/App/App/Localizable.xcstrings`，773 条、19 个 locale 无一缺失。`public/locales` 仍是唯一来源，catalog 不得手工编辑；vitest 与 `ci_post_clone.sh` 各有一道过期检查。
- **键的选法**：扫描 `src-mobile/ios/App/App` 的 Swift 字面量再与 en 的键取交集，而不是扫 `t("…")` 调用点——`legendKey`、`sourceKey`、`syncFailureKey` 这类键写在 `switch` 里、由别处交给 `t`，按调用点扫会整批漏掉。运行时拼出来的键静态发现不了，因此另设显式前缀白名单（目前只有 `focusIcon`，来自 `"focusIcon\(rawValue.capitalized)"`）。统计：App 用到 762 个键加 `focusIcon` 家族 8 个，其中 649 个 iOS 专属、134 个与 Web／Desktop 共用。Watch 专用键不入 catalog，Watch 生成器到 L3 之前继续读 JSON。
- **复数**：全仓只有 `recordsMonthWorkdays` 一个复数键（19 个语言各一条 `_one`），调用点也只有一处。按 2026-09-13 的决定改用系统 CLDR 规则：复数条目把 `{{count}}` 写成 `%lld` 交给 Foundation 选形，其余占位符仍是 `{{name}}` 由封装替换；手写的 19 语言 `NativePluralCategory` 表随之删除。
- **数组**：catalog 没有数组类型，`microBreakMessages` 展开成 `microBreakMessages.1…4` 再由封装收集回来；生成器强制各语言条数一致，不一致直接报错。`notificationToneMessages` 只有 Web 用，不进 catalog。
- **封装**：`NativeLocalizer` 改为按语言取 `.lproj` bundle 后 `localizedString`。不能直接用 `String(localized:)` 或 `Bundle.main`——它们跟随**系统**语言，会无视应用内的语言选择。
- **两个踩到的坑，都由保留下来的旧断言抓到**：
  - 38 条普通文案带字面 `%`（例如「Income after adjustment (%)」）。最初以「值里含 `%`」判断是否需要格式化，会把它们当成畸形格式符交给 `String(format:)`；改为只认 `%lld` 与 stringsdict 的 `%#@` 标记。
  - 复数键经 `localizedString` 返回的是 `%#@value@` 而不是选好的变体。不带 `count:` 的查询原样返回它，`{{count}}` 替换落空，格式符会直接显示在界面上；改为没有显式 `count:` 时从 `values["count"]` 取整数驱动选形，完全恢复旧行为。
- **打包**：`public/locales` 文件夹引用从 App 与 Widget 两个 target 移除（Widget 根本不查文案，那份资源是历史遗留），19 份 JSON 不再进包。`check:ios` 新增三条断言：catalog 存在、被复制进 App 资源、且 `locales` 引用不得回归。
- **验证**：iPhone 18 Pro / iOS 27 串行跑完整套件，45 个 suite 共 **734 个测试通过**。主干原为 732，本批把旧的 6 个复数测试换成 8 个，数目正好对上。新测试覆盖各语言单复数的具体译文、零的取形、无复数变化的语言逐数一致、每种语言都打进自己的 `.lproj`、字面百分号不被当格式符、消息池编号键能收集回来，以及应用内语言选择不受设备语言影响。
- `npm test` 34 个文件 389 项通过（含差分 fixture 未过期与新增的 8 项 catalog 测试）；`npm run lint`、`check:ios`、`check:ios-strings`、`git diff --check` 均通过。
- 串行性能与上一批持平：一年 `recordsMetrics` 4.7 ms（P8-b 为 4.8 ms）、记录列表 3.0 ms。
- **打包产物实测**：`App.app` 中已无 `locales` 目录、也搜不到任何 `translation.json`；20 个 `.lproj`（19 语言加 Base）齐全，抽查的 en、de、ja、ar、zh-CN、mr-IN 均同时有 `Localizable.strings` 与 `Localizable.stringsdict`。**体积不是收益**：编译后的文案合计约 1.3 MB，与原先约 1.2 MB 的 JSON 基本持平；这一批换来的是单一来源、过期检查与系统复数规则，不是包体。
- 本批没有界面改动，未做模拟器视觉检查。
