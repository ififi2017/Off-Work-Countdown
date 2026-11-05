# 024 · 按当月排班折算日薪与自订加班（三端规则 / iOS 界面）

- **状态**：IN PROGRESS · 2026-11-05 起草。
- **起因**：国区 App Store 评论（3.2.4，2026-11-02，id 14744606355）：希望按每月实际上班天数折算当月日薪；希望能自订加班时间和加班工时。设计稿：Canvas「按月折算日薪與自訂加班」。
- **范围**（2026-11-05 用户确认）：规则在 `lib/`、Swift、Kotlin 三端同步，并重新生成 fixtures；界面只做 iOS。Web/Desktop/Android 保留现有界面，但必须能读写并保留新增偏好字段，不能把 iOS 设置的值在备份或同步时丢掉。加班可选「不计薪」或自订倍数。
- **交付**：feature branch → PR → main，按下列阶段分 PR。先合入 #358（加班 Sheet 文案）。

## 共同约束

- 新字段一律可选，默认值与现有行为完全一致：旧存档、旧 CloudKit 行、旧版本写入者都必须能继续解码（`decodeIfPresent` / 可空读取），也不提升 `RecordJSON.schemaVersion`，除非必须。
- 公式只在 `lib/` 写一次，Swift `Models/` 与 Kotlin `core/domain` 逐一对应，并由 `scripts/ios-schedule-rule-oracle.mjs` 与两份 fixture 覆盖。不在界面层另算。
- 薪资不进小组件、Watch、URL、分析或分享元数据。
- 所有新文案 19 种语言；iOS 改 `Localizable.xcstrings` 后跑 `generate:android-strings`。

## 阶段 2 · 日薪按当月排班折算（`dailySalaryBasis`）

**偏好**：`dailySalaryBasis: "fixed" | "scheduledMonth"`，默认 `"fixed"`。只对月薪有意义。

**规则**
1. 某天所属的民用月份 M（按该班次的时区）。`scheduledMonth` 的除数为 M 内的排班上班日数：`countScheduledWorkdays(M 首日, 次月首日, workdays, schedule, timeZone)`，与现有判断一致（含扩展排班、节假日覆盖、调休）。
2. 除数 < 1（`off` 模式或该月无上班日）时退回固定 `monthlyWorkingDays`。
3. 年终奖系数、日薪计薪、非法输入的处理不变。
4. 计时快照的 `dailySalary` 用班次开始所在月份。
5. 周期汇总（`summarize`）与记录收入（`recordsIncome`）按月份分段：各月已完成上班日 × 该月日薪，再加上今天的比例部分。整年合计因此正好等于 12 个月薪。
6. `salaryMonthlyEquivalent` 在 `scheduledMonth` 时返回名义月薪 × 年终奖系数。
7. `recordsActualForecast` 不变：月薪本来就按民用日平摊整月。

**iOS 界面**
- 薪资设置的「每月计薪天数」菜单第一项为「按当月排班」，带本月天数；其后是 15…31。
- 「由此推算 › 每个工作日」注明月份和天数，并进入「每月日薪」页：本月日历加后三个月。

## 阶段 3 · 加班计薪方式（`overtimePayMultiplier`）

**偏好**：默认倍数 `overtimePayMultiplier`，默认 1。0 表示不计薪；其余允许 0.5–5，步长 0.1。

**状态（2026-11-05）**：规则（`lib/countdown.ts` 的 `normalizeOvertimePayMultiplier`、`calculateTimelinePayRatio(…, multiplier)`、`overtimeElapsedMs`、`overtimeRateComparison`；`lib/summary.ts` 的当日倍数）、Swift、Kotlin 与 iOS 界面已落地，fixtures 新增 `overtimePay` 段。网页端沿用 1（不读取新偏好），`webOvertimePresentation` 改为调用 `overtimeRateComparison`。Android 只读写并保留偏好、会话覆盖与声明里的 `payMultiplier`，不新增界面。

**按班次覆盖**：倍数随会话保存（iOS `ShiftSession`、Android `SessionState`、Web 会话快照），并写入 `overtimeDeclared` 观测的可选键 `payMultiplier`。

**规则**
1. `payRatio = (截至原定下班的已过有效时长 + m × 超出部分) / 原定有效时长`。m = 1 时与现在完全相同。
2. 新增 `overtimeElapsedMs`。网页端 `webOvertimePresentation` 的「已加班」和「若加班没有额外报酬」对比移入 `lib/` 作为共用规则，网页改为调用它。
3. 记录：加班段的实际收入乘以当天最新声明的 m（缺省为 1）。周期报告的 `overtimeExtra` 同样处理。

**iOS 界面**
- 计时页加班中新增「已加班」和「今日已赚」。附注：计薪时沿用网页端的假设对比句；不计薪时直接给出实际时薪；隐藏薪资时只显示已加班。
- 加班 Sheet 增加「这段加班：计薪 / 不计薪」和倍数（1×、1.5×、2×、自订）。
- 薪资设置增加「加班默认」。

## 阶段 4 · 加班开始时间与计入工时

**规则**
1. Sheet 可选「到几点 / 加多久」，以及「先休息」（无、15、30、45、60 分钟）。
2. `extendShiftWithOvertime(shift, endAtMs, startAtMs?)`：开始时间晚于原定下班时追加一段 `[start, end]`，否则延长最后一段。
3. 观测新增可选键 `overtimeStartAtMs`。

**记录**：某天的加班区块包括时段、「计入工时」覆盖和计薪方式。「计入工时」覆盖写入可选键 `countedMs`：工时统计、报告和收入用计入值，时间轴仍显示实际时段。

## 验证（每阶段）

`npm run lint`、`npm test`（含两份 fixture 检查与 `check:ios-strings`）、`generate:ios-rule-fixtures`、`generate:android-rule-fixtures`、Web/Desktop 构建与检查、`check:ios`、iOS 模拟器构建与 `ScheduleRuleFixtureTests`、Android Gradle 检查。iOS 界面截图仅在用户要求时进行（本次已获准）。
