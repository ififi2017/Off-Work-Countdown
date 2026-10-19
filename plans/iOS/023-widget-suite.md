# 023 · 小组件全家桶：iOS / Apple Watch / macOS 与设置页小组件中心

- **状态**：DRAFT · v0.1（2026-10-19）。设计稿已经用户逐项评论并修订到「大致满意」；本文是结合源码的实现评估与分批计划。尚未实施、构建或真机验证。
- **目标版本**：待定（见 §9 D1）。建议拆成两个版本，免费部分先发。
- **设计稿**：[DoneAt 3.3 小组件设计](https://claude.ai/artifact/6ueGrptJyckueruobABQXz)（私有画布，共 8 块画板，需由所有者在页面里分享后其他人才能打开）。下文的 A、B 等编号与画板标题一致。
- **目标**：
  - 保留现有倒计时小组件的布局，只修问题；新样式作为小组件库里的额外选项。
  - 新增周/月/年汇总、人生进度、本周进度与排班、假期与请假、专注与控制中心。
  - Apple Watch 升级现有两种复杂功能，并新增 Corner、Inline 和四个矩形主题。
  - macOS 小组件按数据可得性同步一部分。
  - App 设置页新增「小组件」入口：预览、标出免费/Plus、引导添加。
- **依赖**：
  - [AGENTS.md](../../AGENTS.md) 的隐私边界（小组件不出现工资）与本地化规则。
  - [019 iOS 原生规则与本地化](019-ios-native-rules-and-localization.md)。
  - [017 Apple Watch](017-apple-watch-plus.md)。
  - [020 休假规划与周期报告](020-leave-planning-shift-alarms-cycle-reports.md)。
  - [iOS 工程规范](../../docs/agent-guides/ios.md)、[发布规范](../../docs/agent-guides/releases.md)。
- **源码核对基线**：`main` @ `e0e26849`（2026-10-19），并参考 3.2.3 修复分支 `fix/ios-notification-tap-crash`，即 [PR #322](https://github.com/ififi2017/Off-Work-Countdown/pull/322)。
- **交付方式**：feature branch → PR → main，按 §8 分批；每批独立可发。本计划不授权新增商品、外部服务或改变定价。

## 0. 结论摘要

1. **都能做，但不是同一种工作量。**
   - 倒计时新样式、本周进度、排班、Watch 升级只需在现有快照上「换画法」，或复用已有排班规则，风险低。
   - 周期汇总、人生、假期需要新的快照载荷，并且小组件需要知道用户是否订阅了 Plus。这条通路目前不存在。
   - 专注按钮和控制中心要从零接入 App Intents，App target 目前没有任何 App Intent。这是最大的未知数。
2. **小组件需要知道权益（P0 阻断项）。** 现有小组件全部免费，扩展进程完全不知道 Plus 状态。新的 Plus 小组件需要 App 写入权益和到期时间；未订阅时 App Group 里不写任何数据，只写「锁定」。
3. **「快速添加」做不到一键放到桌面。** 就目前所知，iOS 与 macOS 都没有让 App 直接把小组件放到主屏或控制中心的公开 API（W0 在 iOS 27 SDK 上复核）。设置页做成「实时预览 + 分步引导」。
4. **macOS 能跟进的**：倒计时新样式、本周进度与排班、周末与假期倒计时。周期汇总要等定价决定（D5）。人生、请假、专注、控制在桌面端没有数据来源，不做。
5. **共享规则成本。** 「本周还剩几天」「明天上什么班」「下个假期」若 iOS（Swift）和 macOS（TS）都要算，按 AGENTS.md 就是共享规则：需要 `lib/` 规格 + Swift + Kotlin 实现，并重新生成 fixture。Android 当期不做小组件，但 Kotlin 规则仍要对齐。

## 1. 范围与免费 / 付费

| 组 | 小组件 | iOS 尺寸 | 权益 | Watch | macOS |
|---|---|---|---|---|---|
| 倒计时 · 保留 | 现有样式；「接下来」不写「今天的班次」已在 #322 修复，其余只做核对（午休时各尺寸都倒计时到回来时刻，代码已如此） | S / M / L / XL / 锁屏圆形 / 矩形 | 免费 | 升级现有两种 | 现有 S / M 同步修复 |
| 倒计时 · 新样式 | 大数字、分段环形、今日时间轴、新 M / L / XL | 同上 | 免费 | — | S / M（L 视 §6） |
| 本周与排班 | 本周进度（含大小周、轮休）、明天上什么班（含固定班 / 未设置状态）、排班月历 | S / M / L / 锁屏矩形 | 免费（建议，D2 一并确认） | 本周、明天班次 | 可做 |
| A · 周期汇总 | 本周 / 本月 / 今年：时长、工作日、加班、和上期比较 | S / M / L / 锁屏 | **Plus** | 不做（需把记录送到手表，违反现有传输边界） | 待 D5 |
| B · 人生进度 | 今年进度、已度过天数、年月格、距离退休 | S / M / L / 锁屏 | **Plus**（与 App 内人生页 `RecordsAccess.life` 一致） | 不做 | 不做（桌面无人生资料） |
| 假期与请假 | 距离周末、下个假期、拼假建议与余额 | S / M / 锁屏 | **Plus**（D2：「距离周末」是否免费） | 下个假期 / 周末（D4） | 周末 / 假期可做；拼假不做 |
| 专注与控制 | 专注（加番茄 / 停止）、下一段专注、控制中心按钮、待机布局 | S / M / 控制 | **Plus**（D3：「上班打卡」「下班倒计时」两个控制是否免费） | 不做 | 不做 |
| 设置页小组件中心 | 全部小组件的预览、权益标记、添加引导 | App 内页面 | 入口免费 | Watch 页附复杂功能说明 | 桌面设置页可选（§7） |

所有小组件都不出现金额。周期汇总的数据源 `CycleReportFigures` 带有 `income`，投影时必须丢弃，并加测试（§3.6）。

## 2. 现状（源码核对）

**iOS 小组件**
- 只有一个 kind：`com.rainif.offworkcountdown.macappstore.widget`，用 `StaticConfiguration`。
- 界面与快照契约是两份源文件，以文件引用方式同时编进 iOS 小组件扩展：
  - `src-tauri/macos-widget/Sources/OffWorkCountdownWidgetUI/OffWorkCountdownWidget.swift`
  - `src-tauri/macos-widget/Sources/WidgetSnapshotContract/WidgetSnapshot.swift`
- 同一份界面代码也构成 macOS 小组件（Swift Package，只随 Mac App Store 渠道发布；GitHub 渠道编译时去掉）。

**同一扩展里的其他内容**：`OffWorkLiveActivityWidget` 和 `ShiftAlarmLiveActivityWidget`（AlarmKit）。

**快照**
- iOS：`WidgetSnapshotComposer` 写入 App Group `group.com.rainif.offworkcountdown.macappstore` 下的 `widget-snapshot-v1.json`。
- macOS：`lib/widget-snapshot.ts` 生成，经 Rust `write_widget_snapshot` 写入；Rust 会拒收含 `salary` / `income` / `earnings` 等键的载荷。
- 排班：`ScheduleRules.widgetShiftsInBackground` 已经算出最多 400 个、370 天内的未来班次。

**权益**：`PlusEntitlement` 只存在于 App 进程。小组件扩展不读权益，也没有缓存。

**App Intents**：App target 没有任何 App Intent。实时活动的「加番茄 / 停止」走 `offworkcountdown://focus?...` 深链打开 App。

**新组件的数据源**

| 需要的数据 | 现有来源 | 说明 |
|---|---|---|
| 周 / 月 / 年汇总 | `RecordsQueries.cycleReportSnapshot(for:now:)` → `CycleReportSnapshot` | 按日的工时与加班、`months`、`baseline`（与上期比较）都已具备；`figures.income` 必须剔除 |
| 人生 | `LifeProfile.bornOn` / `retirementOn` | 未填退休日时默认 60 岁；职业起点取最早的就业经历 |
| 假期 | `Shared/HolidayCalendar`（随包内置，iOS 与 Watch 共用），`HolidayDayAnnotation` | — |
| 请假 | `LeaveBalance`、休假规划 | 方案目前在 `LeaveViews` 里用 `Task.detached` 现算，需要抽到模型层，才能供快照生成器调用 |
| 排班 | `ShiftType` 的 `name`、`colorHex`，以及 `ShiftCycleRule` 的四种预设（weekly / alternatingWeeks / rotation / custom） | 月历用用户自己的班次名和颜色，不写死早、中、夜 |
| 专注 | `FocusStore`、`FocusLiveChain` | 已有实时活动所用的当前块和下一块 |

**Watch**
- kind 为 `DoneAtWatchWidget`，只有 circular 和 rectangular 两种，免费。
- `WatchScheduleV2` 携带完整的 `ScheduleRuleInput`，含扩展排班与节假日地区；配合 `ShiftRuleCore` 和 `HolidayCalendar`，可在手表上离线算出本周、明天班次和下个假期，**传输协议不用改**。

**桌面数据**
- `DesktopDayStats` 按日记录是否出勤、计划工时和加班，已能支撑周 / 月 / 年工时汇总。
- 另有 `lib/holidays.ts` 和 `lib/extended-schedule.ts`。
- 桌面端没有 Plus、记录归档、人生、请假或专注。

**设置页**：`SettingsSection` 现有 `shift`、`reminders`、`appearance`、`recordsData`、`about` 五组；`AppleWatchSettingsView` 是可参照的二级页。

**系统版本**：iOS / watchOS 最低 26.0，可交互小组件（17）、控制中心控制（18）、`AppIntentConfiguration` 都可直接用。

## 3. 架构方案

### 3.1 小组件 kind 划分

- **保留原 kind 不动**，避免已添加的小组件变样。
- 新样式各自是新 kind，在小组件库里另起条目，见 D6。
- 初定 kind：

  | kind | 内容 | 尺寸 / 配置 |
  |---|---|---|
  | `…widget.style` | 倒计时新样式 | 用 `AppIntentConfiguration` 选大数字 / 环形 / 时间轴；M、L、XL 是固定的新布局 |
  | `…widget.week` | 本周进度 | — |
  | `…widget.roster` | 明天班次 / 排班月历 | 按尺寸区分 |
  | `…widget.summary` | 周期汇总 | 配置项：本周 / 本月 / 今年 |
  | `…widget.life` | 人生进度 | — |
  | `…widget.holiday` | 假期与请假 | — |
  | `…widget.focus` | 专注 | — |
  | 控制 | 上班打卡、开始专注、下班倒计时 | 各一个 kind |

- W0 需核实单个 `WidgetBundle` 能放多少条，必要时嵌套 bundle。

### 3.2 快照载荷

**按 kind 拆成独立文件，不扩写现有 v1 文件。** 每个 provider 只读自己的那份，这与现有代码里对扩展内存预算的约束一致。

| 文件 | 写入方 | 内容 | 刷新时机 |
|---|---|---|---|
| `widget-snapshot-v1.json`（现有） | 两端 | 时间线；新样式需要的分段已在 `shift.segments` 里，无需改契约 | 现状不变 |
| `widget-calendar-v1.json` | 两端 | 从今天起 42 天，每天：上班 / 休息 / 节假日 / 调休、班次名与颜色、上下班时刻；本周有效工时边界 | 排班或节假日变化；跨午夜由时间线条目推进 |
| `widget-summary-v1.json` | iOS（Mac 待 D5） | 三种周期的工时、工作日、加班、按日或按月柱、与上期比较；`access` | 记录提交、权益变化；当天柱随时间线 15 分钟一档增长 |
| `widget-life-v1.json` | iOS | 出生日、退休日、职业起点（只存天数）；`access` | 资料变化；每天一个时间线条目，预排 30 天 |
| `widget-holiday-v1.json` | 两端（拼假只 iOS） | 下个周末起点、下个假期（名称、日期、天数）、拼假首选方案、余额；`access` | 节假日数据、请假、规划变化 |
| `widget-focus-v1.json` | iOS | 当前块与下一块（标题、起止、第几个）；`access` | 跟随专注会话 |

- **原子写入**：沿用 `WidgetSnapshotPublisher` 的临时文件 + 替换。
- **按 kind 刷新**：每个文件写完后调用 `reloadTimelines(ofKind:)`，只刷新对应 kind。

### 3.3 权益通路（Plus）

- Plus 载荷带 `access: { plus: Bool, validUntilMs: Int64? }`。`validUntilMs` 取订阅当前周期的到期时刻；终身购买为空。
- 未订阅时 App **只写 `access.plus = false`，不写任何数据**。扩展读不到数据就显示设计稿里的「未订阅」状态：灰色示意 + 「在 DoneAt 里了解 Plus」，点击打开 Plus 页。
- **扩展自己判断到期**：在 `validUntilMs` 那一刻插入一个锁定条目。这样即使用户到期后没再打开 App，小组件也会锁上。
- 到期或退款后，App 下次启动时清空这些文件里的数据。
- W0 评估扩展内直接读 StoreKit `Transaction.currentEntitlements` 作为兜底；默认不依赖，以免在扩展里做异步 I/O。

### 3.4 交互与控制（App Intents）

- **写入必须在 App 进程**，因为记录和专注都在 `RecordCoordinator` 的命令队列里。W0 实测、二选一：
  - **方案 a**：用 `LiveActivityIntent` / 系统在 App 进程执行的 Intent，直接调用 `FocusStore`。
  - **方案 b**：扩展把命令写进 App Group 队列，并用 `openAppWhenRun` 唤起 App 消费。
- **兜底**：沿用现在实时活动的深链。
- 控制中心「上班中」开关读取 `widget-snapshot-v1.json` 的状态，切换时调用 App 进程里的 `shifts.startCountdown` / 停止。
- 本批同时打下 App Intents 地基：`AppIntentsPackage`、target 成员关系、Intent 本地化。021 的 Siri / 快捷指令将来可直接复用。

### 3.5 计时与刷新

- 倒计时一律交给系统计时文本（`Text(_:style: .timer)` 或 `Text(timerInterval:)`）。
- 区间下界取段或班次的开始时刻，不用条目时刻。这是 3.2.3 修复实时活动快几秒、数字卡住时得到的结论，新组件必须遵守。
- 环形、柱状图沿用现有做法：在 36 小时的展示窗口内按 15 分钟加条目。
- 月历和人生用午夜条目推进，不靠重新加载。
- 待机（StandBy）：沿用 Small 布局，检查 `.widgetAccentable` 与夜间红色模式下的可读性；不单独做 kind。

### 3.6 隐私与安全

- iOS 新增单测：编码后的各载荷不含 `salary` / `income` / `earnings` / `wage` / `hourlyRate`，与 Rust `widget_snapshot_contains_sensitive_data` 同表。
- Rust 的 `write_widget_snapshot` 改为接收白名单内的文件类型，每种都过敏感键检查。
- 人生载荷只存日期，不存职业经历里的工资。
- 汇总只存时长和天数。
- 拼假只存日期和天数，不存请假原因。

### 3.7 本地化

- 新增文案全部覆盖 19 种语言，保留英文占位符。
- 每个 key 同时写入 `Localizable.xcstrings` 和 `public/locales/*`，因为小组件文案由 `WidgetCopy` 从扩展包里的 `translation.json` 读取。
- 改完 catalog 后重新生成 Watch 表和 Android 资源（`npm test` 会检查）。
- 文案遵守 AGENTS.md 的「先讲好处、平等、不说教」。设计稿里的「在 DoneAt 里了解 Plus」「少请几天假，多休几天」等需在 19 种语言里复审。

### 3.8 共享规则

以下三个值由 Swift（iOS / Watch）和 TS（macOS）各算一遍，按 AGENTS.md 属于共享规则：
- 本周剩余有效工时
- 明天的班次
- 下个周末 / 假期的起点

**做法**
- `lib/` 新增纯函数作为规格，直接组合现有的 `countdown.ts`、`extended-schedule.ts`、`holidays.ts`。
- Swift 侧放进 `ScheduleRules.swift`，Kotlin 侧放进 `core/domain`。
- 运行 `generate:ios-rule-fixtures` 和 `generate:android-rule-fixtures`，`ScheduleRuleFixtureTests` 必须通过。
- 不新写排班算法：只在已经解析好的班次列表上求和、取下一项。

## 4. 各小组件实现评估

| 小组件 | 主要工作 | 复用 | 风险 / 注意 |
|---|---|---|---|
| 倒计时 · 保留 | 不改布局。核对午休时 S / M / L / XL / 锁屏都走 `breakEnds` 的 `countdownTargetAtMs`（现状已是），`0:00:00` 占位只在没有目标时出现 | 现有 view | 不改契约；若核对发现问题，macOS 会自动同步修复 |
| 倒计时 · 新样式 | 新 kind + `AppIntentConfiguration`；分段环自绘（系统 `Gauge` 画不出缺口）；时间轴竖条 | `shift.segments` | 环形在 accented / vibrant 渲染下的颜色；XL 竖屏改为上下排列 |
| 本周进度 | 规则：本周各工作日有效工时 → 已完成比例与剩余天数；大小周、轮休、调休 | `widgetShifts`、节假日 | 共享规则（§3.8）；「还剩 1.4 天」按有效工时折算，需定义折算口径 |
| 明天班次 / 月历 | `widget-calendar-v1.json`；月历 42 格；固定班只分上班 / 休息，扩展排班用 `ShiftType` 的名称和颜色；未设置时显示空状态 | `widgetShifts`、`ShiftType` | 「今晚 20:00 后切到明天」的切换时刻定为实现默认，需标注；颜色对比度要过 4.5:1 |
| A · 周期汇总 | 在 App 侧把 `cycleReportSnapshot` 投影成无金额载荷；三种周期在一个文件里；按日、按月柱 | `CycleReportSnapshot` | 查询是 async 的，要在记录提交后去抖再生成；未订阅时只写锁定 |
| B · 人生进度 | 天数、百分比、年月格（每格一年、每点一月），全部在扩展里由三个日期算出 | `LifeProfile` | 只有出生年份（精度为年）时，天数要标「约」；未填出生年份时显示引导 |
| 假期与请假 | 下个周末 / 假期；拼假首选方案需先把 `LeaveViews` 里的现算逻辑抽到模型层 | `HolidayCalendar`、休假规划 | 公告未出的年份写「放假安排公布后自动更新」，不预测；免费三次查看规划与小组件的关系需定义（D2） |
| 专注 | 当前块、下一块；按钮 Intent（§3.4） | `FocusLiveChain` | 与实时活动同时存在时状态要一致；按钮执行失败时有反馈 |
| 控制中心 | 三个 `ControlWidget` | §3.4 | 控制的标题和图标会出现在系统设置里，需本地化 |
| 待机 | 不新增 kind，只做显示检查 | Small 布局 | 夜间红色模式 |

## 5. Apple Watch

- **升级现有两种**
  - 圆形改为「还剩时:分 + 下班时刻」，配分段环（午休是缺口）。
  - 矩形的标题行显示状态和下班时刻，主值用系统计时文本走秒（下界按 §3.5），下方分段条。
  - 午休、已下班、休息日各有专门状态。
- **新增**
  - `accessoryCorner`：曲线进度 + 剩余时间。
  - `accessoryInline`：「18:00 下班 · 剩 2:41」。
  - 矩形四个主题：本周、明天班次、下个假期 / 周末、接下来。
  - 「接下来」只放排班边界和午休；专注是 iPhone 上的 Plus 数据，不送到手表。
  - 智能叠放（Smart Stack）沿用现有的 `WidgetRelevanceAttribute` 做法，按事件时刻提高相关性。
- **数据**：全部由 `WatchScheduleV2` 配置加 `ShiftRuleCore`、`HolidayCalendar` 在手表上算出，不改传输协议，不送记录或工资。
- **权益**：AGENTS.md 写明「Watch App and both complications are free」。新增复杂功能是否全部免费，见 D4；确定后同步改写 AGENTS.md 这句。
- **kind**：不同内容用不同 kind，便于用户在表盘上分别选择。

## 6. macOS

| 项 | 可否 | 说明 |
|---|---|---|
| 倒计时保留样式的修复 | 可，自动 | 同一份 Swift 界面代码 |
| 倒计时新样式 | 可 | 同一份代码按 `#if os(macOS)` 调整；macOS 现在只支持 S / M，是否加 L 视桌面用户反馈（实现默认先不加） |
| 本周进度 / 明天班次 / 月历 | 可 | `lib/widget-snapshot.ts` 增加日历载荷，规则走 §3.8 |
| 周末 / 下个假期 | 可 | `lib/holidays.ts`；macOS 没有拼假 |
| 周期汇总 | 待 D5 | 数据可由 `DesktopDayStats` 得出；但桌面端没有 Plus，若在 Mac 上免费，会与 iOS 收费不一致 |
| 人生 / 请假 / 专注 / 控制 | 不做 | 桌面端没有数据来源；macOS 26 控制中心的控制不在本计划内 |

- 只有 Mac App Store 渠道带小组件。
- Rust 端按 §3.6 扩展白名单。
- 桌面设置子页可选加一行「小组件」，只在 MAS 渠道显示，内容为文字引导。

## 7. 设置页小组件中心（iOS）

**入口**：`SettingsSection.appearance` 里新增一行「小组件」，打开二级页 `WidgetGallerySettingsView`，参照 `AppleWatchSettingsView` 的结构。

**页面内容**
- 按 §1 分组列出：倒计时、本周与排班、汇总、人生、假期、专注与控制、Apple Watch。
- 每项有实时预览、可选尺寸和「免费」或「Plus」标记。
- **预览**：把小组件的 SwiftUI 视图同时编进 App target，用用户当前的真实数据渲染。目前 `OffWorkCountdownWidget.swift` 只在扩展里，需要调整 target 成员关系。预览只在 App 内存里，不写 App Group。
- **Plus 项**：未订阅时预览照常显示，示例数据会标明「示例」，配一个次要的「了解 Plus」入口。不弹窗，不挡住免费项。

**添加**
- 目前所知没有一键放到主屏的公开 API。每项提供「如何添加」分步说明（长按主屏 → 编辑 → 添加小组件 → 搜索 DoneAt → 选尺寸）以及控制中心与锁屏的对应步骤。
- 若 W0 在 iOS 27 SDK 中发现可用的添加 API，再改为按钮。

**其他入口**：小组件里的「了解 Plus」、首次添加任何小组件后的提示都可以跳到这一页（深链 `offworkcountdown://widgets`）。

## 8. 分批与验收

| 批次 | 内容 | 依赖 | 主要验收 |
|---|---|---|---|
| W0 实测与地基 | 核实：添加小组件 API、`WidgetBundle` 上限、Intent 执行进程（§3.4）、扩展内 StoreKit 兜底。小组件视图编进 App target；载荷文件框架与 `access`；隐私单测 | — | 实测记录写回本计划；单测 |
| W1 倒计时 | 保留样式核对；新样式 kind（S / M / L / XL / 锁屏）；macOS 同步 | W0 | `npm test`、iOS 模拟器构建、macOS 小组件构建；按要求做真机或模拟器视觉检查 |
| W2 本周与排班 | §3.8 共享规则（lib + Swift + Kotlin + fixtures）；日历载荷两端；iOS 三种组件；macOS | W0 | `ScheduleRuleFixtureTests`；大小周、轮休、调休、未设置四种 fixture |
| W3 Plus 数据组件 | 权益通路；A 周期汇总、B 人生、假期与请假（含拼假模型抽取） | W0 | 订阅、过期、退款、终身四种状态；锁定状态无数据 |
| W4 交互与控制 | App Intents 地基；专注小组件；三个控制；待机检查 | W0、W3（权益） | 按钮在 App 未运行、已运行、锁屏三种情况下都生效；失败有反馈 |
| W5 Apple Watch | 升级两种；Corner / Inline / 四个矩形主题；必要时改写 AGENTS.md 那句 | W2 规则 | `DoneAt Watch App` 测试；表盘与智能叠放真机 |
| W6 设置页小组件中心 | 入口、预览、权益标记、添加引导、深链；桌面 MAS 文字引导（可选） | W1–W5 中已完成的项 | 只列出已发布的小组件；19 种语言 |

**每批门禁**（AGENTS.md）
- `npm run lint`、`npm test`。
- 涉及 `lib/`、`public/locales` 或 `src-mobile/` 时：本地无界面 iOS 模拟器构建。
- 涉及 `src-mobile/ios` 时：`npm run check:ios`。
- 共享规则：Swift + Kotlin + fixtures。
- macOS 小组件：MAS 渠道构建与 `check:build:desktop`。
- UI：在对应系统上做真实视觉检查。按规范，iOS 模拟器视觉测试需要用户明确要求才做。

## 9. 待决问题

**2026-10-19 用户决定**（下列原问题保留作记录）：

| 编号 | 决定 |
|---|---|
| D1 | 全部做完一起发，不拆版本 |
| D2 | 距离周末、下个假期免费；拼假建议与年假余额仍属 Plus |
| D3 | 控制中心免费，只有「开始专注」仍需 Plus（专注本身是 Plus 功能）；与请假相关的内容不在免费范围 |
| D4 | Watch 新增复杂功能免费，不含请假相关内容 |
| D5 | 按建议，macOS 暂不做周期汇总 |
| D6 | 新样式做成新 kind |
| D7 | 采用「预览 + 分步引导」 |

- **D1 版本拆分**：建议 W0–W2 加 W5（全部免费）先发一个版本，W3、W4、W6 下一个版本。也可以等全部完成一起发。
- **D2 假期**：「距离周末」「下个假期」是否免费，只有「拼假建议与余额」属于 Plus？建议免费，因为它只用节假日模板，与 App 内免费的节假日显示一致。
- **D3 控制中心**：「上班打卡」「下班倒计时」两个控制是否免费（建议免费，属于倒计时核心功能），只有「开始专注」属于 Plus？
- **D4 Watch**：新增复杂功能是否全部免费？若假期类在 iOS 收费、在 Watch 免费，需要接受这一不一致，或在 Watch 上不做假期主题。
- **D5 macOS 周期汇总**：桌面端没有 Plus。三种选择：Mac 上免费提供；Mac 上不做；或等桌面端有权益方案再做。建议先不做。
- **D6 新样式的形态**：做成新 kind（推荐，已添加的小组件不变），还是在原 kind 上加样式配置（小组件库更干净，但老组件迁移有风险）。
- **D7 快速添加**：若确认没有系统 API，是否接受「预览 + 分步引导」作为最终方案。

## 10. 风险

- **App Intents 从零接入。** 执行进程、`RecordCoordinator` 的并发入口、错误反馈都需要实测，可能拖慢 W4。可先发 W1–W3。
- **扩展内存预算。** 现有代码注释记录过：扩展被系统杀掉时只会显示占位图，不报错。新 provider 必须只读自己的文件，时间线条目数要设上限（月历最多 42 天、人生每天一个条目、汇总按 15 分钟一档）。
- **共享规则扩散到 Kotlin。** 当期不做 Android 小组件，但规则对齐和 fixture 仍是硬门禁。
- **AGENTS.md 需同步的规则**：新增复杂功能的免费口径（D4），以及「小组件可显示 Plus 数据，但仍不含金额」这条澄清。隐私段本身不变。
