# iOS 3.2.1 / Android 剩余差距核查

核查日期：2026-10-07。本文保留本轮实施前的初始审计快照，并记录随后完成的代码同步；旧差距表不代表当前未完成项，不替代唯一任务状态文件 [progress.md](progress.md)，也不推进既有 baseline。用户要求同步 iOS **3.2.1**，没有指定 Git commit。主 agent 选择 `035420377e4c762ba5556a3cc41fc9a94be4bc6e` 冻结 UI 源码与截图对照；模型修复另纳入已缓存、仍为 3.2.1 的 `origin/main=ea593050e9eebbaac6a95ec8444f87afe6123bc6`。没有 fetch 新引用，也没有纳入原产品工作区未提交的 iOS 修改。本文作者没有操作任何设备，没有锁屏、通知响铃或闹钟测试；主 agent 的实际 UI 验收由 progress 记录。

## 对照范围与漂移

- [baseline.md](baseline.md) 冻结 `9252fdfdc66aab88b4acb7493684f11991fd773d`，其后明确授权 Plan 020 源 `18129168acd23edc3a872cca3633a2831f60c6f2`；此次主 agent 用工作区原 HEAD `03542037` 冻结 UI 对照。用户的版本目标是 3.2.1，因此同版缓存模型修复也在范围内；不自动追随未来远端变化。
- prescribed drift：`git log --oneline 9252fdfdc66aab88b4acb7493684f11991fd773d..035420377e4c762ba5556a3cc41fc9a94be4bc6e -- lib src-mobile/ios/App/App/Native/Models src-mobile/ios/Shared` 共 **50** 条。同命令以本地 `origin/main` 为终点共 **52** 条，远端引用为 `ea593050e9eebbaac6a95ec8444f87afe6123bc6`。
- 多出的 `d2532ab7`（无排班的 observed days 保留为记录）与 `170f62a1`（无工时休息日不计 recorded days）在初始 UI freeze 审计中曾被排除，现按用户的 3.2.1 版本目标**纳入本轮模型同步**，以 `d2532ab7` 最终契约为准。缓存终点的 `MARKETING_VERSION` 仍为 3.2.1；`03542037..origin/main` 的 iOS 差异仅这两个修复涉及的七个文件。该 drift 命令没有覆盖 Views，因此初始审计另查 `18129168..03542037` 的 Native Views、Shared 和本地化资源差异；否则会漏掉 `43596972` 分栏／Duo 与 `8561af1c` SDK guard。
- [feature-parity.md](feature-parity.md) 是目标／映射，不是完成凭据；其中旧 schema 6 与旧 T21 deferred 表述不能覆盖当前 schema 7、10-04 已激活的独立验证服务。具体授权和数据架构以 [android guide](../agent-guides/android.md) 与 progress 为准。
- 初始审计时 onboarding、leave、review、lifetime offer 正由各 owner 实现，因此未重复列为新缺项。随后代码已同步的范围见下表；源码存在不等于 UI 已验收。报告播放／年报此前已有 Android 实现，不属于此次整项缺失。

## 初始审计快照：实施前确认的差距

本表的“当前 Android”均指本轮实施前快照，保留发现依据；**不要将其作为当前缺项清单**。本轮接线情况见后文，最终验证与剩余任务只看 progress。

| 优先级 | 固定 iOS 行为与源码 | 当前 Android 证据 | 建议与严格边界 |
| --- | --- | --- | --- |
| P1 | `Native/Views/FoldedTimerView.swift`、`TabletDesignView.swift`：水平折叠区域上方 hero、下方独立滚动 timeline/actions；展开宽度 >=620 且高度非 compact 时，hero 与 timeline/actions 两列，保留根导航状态。 | `ui/AppShell.kt` 只读取 adaptive windowSizeClass，600 宽或短窗口换 rail；源码无 FoldingFeature / hinge 几何。`ui/timer/TimerScreen.kt` 是单列并限宽680dp。 | 接 Android 系统提供的 folding bounds/posture，水平分区和垂直铰链都避让内容；平板／展开无铰链用双列。布局模式只是呈现输入，SessionStore、规则和四个 tab back stack 不迁移、不重建。阈值按 dp/字体/可用区域验证，不能把 iOS point 或 SDK reservedRegions 原样复制。 |
| P1 | `Native/Views/FocusCanvasView.swift`：展开且非辅助大字时隐藏 Today/Usual picker，Today 与 Usual 同时独立滚动，NowBand 顶部横跨；大字保持单列。 | `ui/focus/FocusScreen.kt` 有 fontScale>=1.5 的取消 pinning，但始终 picker + 单 canvas。 | 复用已有 focus 模型，增加两列呈现与独立滚动；状态、创建／编辑命令、Plus 锁和无工资投影不变。不能用左右两份 screen 复制副作用。 |
| P1 | `Native/Views/RecordsDesignView.swift`：展开手机两列、结论约42%；辅助大字退单列。 | `ui/records/RecordsScreen.kt` 已有 >=720dp 两列，所以不是“完全未适配”；但结论固定420dp，缺两列 fontScale gate，720 窗口时剩余图表很窄。 | 以可用宽度分配比例／最小宽度；fontScale>=1.5 或分区不足单列。继续只读 RecordsQueries 成品模型；绝不让未授权日期／工资为排版需要先建出来。 |
| P2 | `TabletDesignView.swift` AdaptiveSettingsColumns：展开手机或 >=720 时非辅助大字两列。 | `ui/settings/SettingsScreens.kt` SettingsHomeScreen 五组串行排列。 | 在同一 DoneAtPage 中对组分栏；大字单列，读序与 RTL 按语义顺序；不复制 settings repository 或改全局 tokens。 |
| P2 | `PhoneLandscapePresentation.swift`：普通手机横屏可自动 clock presentation；Duo/open 宽屏但 regular height 保持现有任务。Timer 内设置快捷入口仍在 Timer navigation path。 | Android 短窗口只是 rail；`AppShell.openSettings` 通常转 Settings tab。 | 区分“真正短横屏”和展开宽屏，提供 Android 原生时钟呈现／返回行为；若保留 rail + 跨 tab 的 Android 交互，需作为明确产品差异验收，不能宣称已同步自动 clock。不要只用 width>height 判断 folded device。 |
| P2 | `ShiftPreviewRow.swift`：辅助大字把时间放文本下方，去侧图标，允许多行。 | `TimerScreen.kt` coming-up row 仍 icon + weighted text + 尾侧时间，未见大字专用呈现。 | 大字／窄 pane 堆叠时间，合并语义读序，保留真实绝对事件时间。需在普通、展开／折叠分区和 RTL 验证。 |
| P1 / 平台独立任务 | `ShiftAlarmService.swift` + Shared shift-alarm rules：实际系统起床闹钟、停止／贪睡、权限、权益截止与覆盖管理。 | `core/domain/alarms/ShiftAlarmPlanner.kt` 及测试是纯规则。app 只有 `PlusAccess.shiftAlarmAuthorization` 提供 Lifetime / VerifiedUntil，没有 planner 调用方、setAlarmClock、响铃服务／界面／停止／贪睡接线。Manifest 只有普通 reminder/ongoing/widget 接收器，明确移除 FOREGROUND_SERVICE。`Reminders.kt` 投递后仅发普通通知。 | **仍未实现起床闹钟平台**；普通推送、exact reminder 或倒计时通知不能算替代响铃。必须另行处理 [shift-alarm-platform.md](shift-alarm-platform.md) 架构授权：原生绝对预约、响铃生命周期、停止／九分钟贪睡、系统权限／重启／撤销清理、持久登记与真实覆盖。10-04 验证服务已解决该旧文档“没有可信订阅期限”阻塞，不能继续引用作理由；但并未解决响铃平台。此审计不修改 Manifest、不注册预约、不做设备响铃测试。 |

Android 合理替代 API 是 Jetpack folding features 的 bounds/isSeparating/posture，而非 iOS reservedRegions；系统 [fold-aware Compose 文档](https://developer.android.com/develop/ui/compose/layouts/adaptive/foldables/make-your-app-fold-aware) 说明如何避开铰链。Android [AlarmManager 文档](https://developer.android.com/develop/background-work/services/alarms) 的绝对预约只负责投递，不替应用托管 iOS AlarmKit 的整套 UI 与响铃行为；具体服务与权限设计仍受本仓已批准架构约束。

## 本轮完成的代码同步

这是代码范围说明，**不是设备验收表，也不是新的任务 ledger**。各模块最终编译、测试、实际 UI 环境、截图和限制由主 agent 在 [progress.md](progress.md) 记录。

| 范围 | 本轮代码同步 | 验证边界 |
| --- | --- | --- |
| Fold / adaptive | `ui/adaptive` 纯几何策略、WindowManager 1.5.1 posture adapter、可复用 pane；Timer、Focus、Records、Settings 接入。大字单列，水平铰链上下避让，RTL 阅读顺序和独立滚动。 | 规则回归与编译/lint 有单独证据；真实 UI 验收仍以 progress 为准。 |
| 短横屏 clock / 导航 | `LandscapeClock` 与 AppShell 覆盖接线；Timer 根、短窗口、无 active fold、无阻挡呈现时启用；底层导航保留，Timer 快捷入口留在原 stack。 | 覆盖层触摸与下次班次时间标签已交由 main 修正；最终产物验收由 main 负责。 |
| Onboarding / Plus / lifetime / What's New | 六页 onboarding、真实 draft projection、原子完成、连续 clock、原生共享 Plus demo、真实 Plus route、offer slot；main 接 lifetime 与 release-notes surface。 | 不能因源码出现而宣称购买、优惠或 UI 已验收；以真实商品与 progress 证据为准。 |
| Leave | 分组、42 格月历、最终 alternatives 规则及原生 UI 已由对应 owner 同步。 | 不改变 schema 7；采用、锁定和布局验收看 progress。 |
| 起床闹钟平台 | 本轮已新增原生 absolute alarm、receiver、ringing service / UI、stop / snooze、权限与恢复接线及纯 fake-platform 测试；不再是“只有 planner”的代码状态。 | **没有设备响铃／锁屏测试声明**；纯假平台测试不证明真实系统已接受预约或可以响铃。 |
| 同版缓存模型修复 | `170f62a1` + `d2532ab7` 的最终 Records / session 契约已补入：休息日无工时、setup arming、取消投影和重复 first-open 展示。 | 本次新增测试未运行 Gradle；root 集中执行最终 gates，详见下一节。 |

## 同版模型修复：缓存 ea593050

- `RecordsQueries.dayCell` 仅在有明确排班、当天为休息、且没有 `OVERTIME_DECLARED` 时阻止观察把日期变成 Recorded。`layer=NONE` 的观察和声明加班仍 Recorded；手工 correction 仍优先。不按 `workMs == 0` 过滤，也不缩窄 `recordDayIndex`。
- `SessionCommands.finishSetup` 通过 `start(recordObservation=false)` arming；明确手动启动仍写开始观察，恢复／重复设置不重播。
- 取消休息日手动计时会捕获取消前投影，在同一个 session/archive 命令内复用 `ScheduleSave.replacingProjectedOverride`。仅清除内容仍匹配的投影，使用既有 tombstone；内容不同的 Records 编辑保留，原开始观察仍作为历史说明。
- `RecordsQueries.displayedObservations` 按原索引的时间顺序只显示最早 FIRST_SEEN。RecordsDayScreen 使用展示查询；原 archive、原始 observationIndex、指标和 schema 7 不变。两条日历入口已复用同宽图标 gutter，无需再次同步。
- 新增六个纯测试：已排休息日 start/stop 不变 Recorded、NONE 无排班观察仍 Recorded、休息日声明加班仍 Recorded、导入多条 FIRST_SEEN 仅折叠展示、取消保留不同内容手工编辑、设置在工作日／休息日无观察 arming 且明确手动开始仍记录。另扩展现有取消回归，移植 Swift `cancelledRestDayTimingLeavesNoRecordedDay` 的 archive/非 NONE layer/REST/0 工时断言，并检查 tombstone 与原观察保留。
- 本次只做源码与 `git diff --check` 静态检查，按主 agent 协调要求未运行 Gradle、未操作设备、未修改 progress。

## 已确认、可独立修正的文案

- `ShiftSessionStore+Preview.swift` 只在 countdown calendar 同一 civil day 的 start 行写 `todaysShift`；未来仅当前／下个月给状态，更远日期无状态。end 仅当前未提前结束、end>now、start 为今天时写它。`WidgetSnapshotPublisher.swift` 未来 shifts 的 start/end 不写 today。原 Android `ui/timer/TimelineWords.kt` 对所有 start/end 无条件套 today，`WidgetCoordinator` 同时复用 formatter，未来 widget rows 也受影响。**本次已按主 agent 授权修正 formatter，并新增 TimelineCivilCopy + 5 个纯测试**；已知未来 roster key 由 Timer caller 注入，widget 默认不注入。currentSnapshot 可复用 caller 已有结果，避免重复求规则。该接线与最终集成由 main 完成，不改事件时序或 rules，不由本地 weekday 猜测排班。
- `ShiftSessionStore+Labels.swift` 的 schedule off 现称 `scheduleManualTimer`。Android 排班页与 onboarding 已使用新标签；**本次已按授权把 SettingsLabels.schedule 的 off 分支改成同一标签**，不更改手动计时规则。

## 不应当重复搬运的变化

- 英式英语 `en-GB` 与拉美西语 `es-419`（目录／catalog code 为 es-MX）已在 Android locales_config、资源与 AppLanguages mapping 存在；本轮 owner 又补了 device language 选取测试，不是缺少第20/21种资源的任务。
- GB 节假日修订使用与 iOS 同一个 HolidayTemplates.json 的构建资源，不能另维护 Android 表。固定源明确撤回 Easter Monday / Summer bank holiday；必须对固定数据验 fixture，不追远端另一版。
- `CycleReportView/Player` Text(verbatim:) 等 Swift 本地化修复不是 Kotlin 新需求；iOS notification-center IPC 迁离 MainActor 是平台实现细节，不能机械要求 Android 复制。Android ReminderSync 仍须维持已有串行登记契约。
- 初始审计时 iOS 3.2.1 What's New 介绍 leave、alarms、reports，Android 尚无独立 release-notes surface。本轮 main 已实现该 surface；它不是 rules 缺失。其宣传边界和最终 UI 验收以本轮实现及 progress 为准。

## 明确 deferred 与 Android 等效边界

- CloudKit 不要求 Android 调用同 API。当前批准的是 Android Auto Backup／设备传输、schema 7 导入导出及恢复防重复；Drive T22 继续 deferred。账户云同步可成为未来独立 Android 项目，不为此次 UI parity 默认新增服务、登录或联网传输工作记录。
- Apple Watch 不要求 Android 支持 Apple Watch。Wear OS T27 继续 deferred；未来本机 Wear OS 伴侣负责只读／明确授权操作、断连与隐私验收。在 deferred 期间应写“未开放”，不能声称主机 widget 等同完整手表能力。
- Live Activity／Dynamic Island／StandBy 用 Android home widgets、持续倒计时通知与本轮原生横屏 clock 组合评估；没有 Dynamic Island 同 API 要求。widgets/ongoing 原已实现，clock 与折叠布局的初始差距现已进入本轮代码同步；实际验收看 progress。

## 初始建议的实施及验证范围

1. 本轮授权的两处 copy 修正：纯 civil helper 回归包含 countdown zone 与设备区不同、午夜／跨月、跨夜 current end、已提前结束、远未来／未知排班；不写 Android Resources 镜像测试。
2. 单独布局任务：定义一次 window/posture 输入，四根 screen 根据输入呈现；不重写规则、不跨 tab 搬 state、不读锁后 Records 数据。共享边距／颜色继续现有 design tokens，新 motion 若必要单独 token 文件。
3. UI 由 main 在实际环境核验：普通窄屏、展开 620/720 附近、水平/垂直 hinge、短横屏、大字200%、RTL、明暗、reduce motion；旋转／折叠前后保留 tab/route/scroll/草稿。源码审计不能替代这些截图／交互证据。
4. 闹钟独立批准与平台接线后再安排设备矩阵；当前用户禁止锁屏与闹钟测试，本轮不得运行。没有系统已接受预约的证据时，不报“覆盖成功／可响铃”。

此次授权 copy 修正的验证：`git diff --check` 通过；`JAVA_HOME='/Volumes/BACKUP/Applications/Android Studio.app/Contents/jbr/Contents/Home' ./gradlew :core:domain:test --tests com.rainif.doneat.core.domain.session.TimelineCivilCopyTest --offline` 五项通过；`:app:compileDebugKotlin --offline -PdoneatDebugApplicationIdSuffix=.parity321` 通过。编译仍报告主 agent 正在编辑的 TimerScreen.kt:219 条件恒真警告；没有设备/UI 完成声明。

收口补充（主 agent）：本地最终统一 gates 为 653 项 Android 与 547 项 Web 全通过，实际 Pixel/iOS 证据见 progress。只读核对远端 `ecf4af29` / PR #304 的 iOS 空优惠 toolbar 与期限刷新改动，Android 本轮的资格条件和 expiry ticker 已覆盖对应契约；未改变上述固定截图源或纳入未提交的 iOS 工作。
