# 011 — iOS 记录与番茄钟发布阻断收口

- **状态**：READY FOR DEVICE VALIDATION
- **日期**：2026-09-01
- **范围**：iOS / iPadOS 原生 SwiftUI 的记录、数据迁移、CloudKit 冲突、番茄钟、通知与 Live Activity
- **依赖**：[002](002-records-life-focus.md)、[006](006-free-trial-subscription.md)、[010](010-records-ui-iteration.md)
- **目标**：修完本轮验收中的全部 P1、番茄钟阻断项和已列 P2；完成自动检查、模拟器截图 feel check 与底层逻辑自我 CR 后，再交付真机验收

## 发布结论与完成标准

记录与番茄钟当前都不得按正式功能发布。本计划不是重做 002 / 010，而是收口其已经落地但未通过验收的部分。

只有同时满足以下条件，状态才能改为 `DONE`：

1. 记录的日期回找、免费遮蔽、导入导出、时区与冲突处理全部通过测试和模拟器验收。
2. 番茄钟形成“专注 → 短休 / 长休 → 下一轮”的完整闭环，所有阶段由用户手动开始。
3. 未来计划、跨夜班、跨午夜恢复、模板幂等和双设备重复会话均有确定性测试。
4. 通知失败可见、带声音；单一 Live Activity 遵守“工作优先，专注其次”。
5. 深浅色、RTL、德语长文案、超大字体、iPhone / iPad 的关键页面完成截图 feel check。
6. 两台真机 iCloud、Production CloudKit schema、冲突合并回写仍必须由真机验收确认；未完成时可标为 `READY FOR DEVICE VALIDATION`，若发现阻断则回到 `IN PROGRESS`，不能写 `DONE`。

## 一、记录数据契约

### 1. 记录日期索引

新增 `RecordDayIndexEntry`，作为“全部记录”的唯一数据源，按稳定 civil `dayKey` 分组。它必须收录：

- 真实的工作计时观察；
- 非 cleared 的 `DayOverride`，包括手动工时、请假及其他用户修正；
- 有效的用户 `CalendarException`，包括补班和休息日。

它必须排除：

- 仅由排班 / 人生档案生成的计划或推算；
- 只打开计时器、但没有产生工作会话的观察；
- 内置节假日数据源。

保留 `recordedWorkDays()` 当前“真实工作观察日”语义，避免请假或休息日进入工作日统计；“全部记录”改用新的日期索引。

列表标题、年月分组与辅助功能文案从 `dayKey` 的年月日组件生成，不把锚点 `Date` 放进当前时区重新格式化。

### 2. 免费窗口完全遮蔽

免费窗口严格为记录时区内 `[今天 - 6 天, 今天]`。免费用户的列表视图模型只能构造窗口内的年份、月份、日期和计数；窗口外数据不得先生成后模糊，也不得进入 VoiceOver。

免费根层只显示：

- 窗口内可见年月和记录；
- 一条不含日期、年份、月份或数量的通用锁定提示。

### 3. 导入导出错误模型

新增统一 `RecordsOperationError`，覆盖：

- 文件选择取消以外的 picker 错误；
- security-scoped 访问失败；
- 文件读取失败；
- JSON 损坏或结构非法；
- schema 版本不支持；
- 导入预览、原子写盘、导出编码或分享失败；
- 设备所有者认证失败。

用户触发路径不得使用 `try?` 或静默 `guard` 吞错。错误界面说明“数据没有改变”、原因和下一步，并允许重试或重新选择文件。

### 4. 冲突副本与合并

`SyncConflictCopy` 升级为可解释冲突：

- 稳定冲突 ID、实体类型、逻辑 key、来源；
- local / incoming / baseline payload；
- 双方 `editedAt`、当前胜者及产生冲突时间；
- 对可编辑实体生成字段差异；时间段等复合字段必须整体选择；
- 观察、会话、排班快照等不可安全逐字段拆分的实体只允许整版本选择。

旧冲突副本继续可读；缺少双侧元数据时使用中性的“当前版本 / 另一版本”，不得虚构本机或云端来源。

合并写回必须使用 `max(local.editCount, incoming.editCount) + 1` 和新的 `editTieBreaker`。本地持久化与 dirty outbox 登记成功后才能消费冲突；写回失败时保留冲突并显示错误。

用户日历例外的逻辑 key 需要统一去掉或解析 `#user` 后缀，使日历冲突标记按 civil dayKey 稳定命中。

### 5. JSON 兼容

完整记录 JSON 升级到 schema v3，并接受 v1 / v2：

- 旧专注会话按 25 分钟 focus 会话迁移；
- 旧计划块按 25 分钟迁移；
- 新增 session kind、原时区、计划结果、模板 provenance 等同步字段；
- 番茄钟设置只保存在本机，不进入 CloudKit；
- CloudKit record type 和稳定 recordName 不因本次升级改变。

## 二、番茄钟产品与状态机

### 1. 可配置节奏

新增 `FocusTimerSettings`：

| 配置 | 默认值 | 允许范围 |
| --- | ---: | ---: |
| 专注 | 25 分钟 | 10–60 分钟 |
| 短休息 | 5 分钟 | 1–15 分钟 |
| 长休息 | 15 分钟 | 5–30 分钟 |
| 长休轮次 | 4 | 2–6 |

所有阶段手动开始。自然完成后只给出 `FocusNextAction`：开始短休、开始长休、跳过休息或开始下一轮；不得自动开始下一阶段。

`FocusSessionKind` 至少包含 `focus`、`shortBreak`、`longBreak`。会话持久化 kind、开始时区、实际时长、绝对 `plannedEndAt` 和计划结束原因。休息完成不增加任务番茄数；被排班边界截短的专注也不计完整轮次。

设置变更只影响未来新会话和新计划，不改变正在运行的会话或已保存计划块。

### 2. 排班边界

`FocusPlanner` 接收共享 TypeScript 规则已经生成的绝对 `segments`、午休、微休、下班与加班边界，不在 Swift 重写排班规则。

规划结果：

- 任何 focus / break 都不得跨越有效片段、午休、微休、下班或加班边界；
- 距离边界不足 60 秒时不能开始；
- 返回绝对结束时间和预期结果；
- 能展示无法排入的 `focusOverflow()`，给用户温和的调整建议；
- 足够长的午休可重置连续轮次，但不会自动开始休息计时。

计划页明确为 focus 块预留短休 / 长休；用户留出的空档优先于自动插入休息。

### 3. 日期、恢复与双设备收敛

- 未来日期或未到开始时间的计划任务不可在今天启动，界面显示何时可用。
- 会话锚点由 `startedAt` 和保存时区计算，不能使用当前自然日。
- 前后台恢复按绝对 `plannedEndAt` 和持久化结果判断；不能因为 anchor 早于今天就把跨午夜完成会话判为 abandoned。
- 启动、回前台、导入和 CloudKit batch 后统一检查多个 open session。按 `(startedAt, id)` 确定唯一 winner，其余写为 `supersededBySync`、同步回云端且永不计数。
- 在归一化前，`activeFocusSession()` 也必须使用相同确定性排序，不能依赖数组顺序。

### 4. 模板与估算

- 对同一模板、内容未改变时重复应用为 no-op。
- 模板创建的任务保存 provenance；再次应用时复用对应任务。
- 清除模板计划时，只有无会话、无收藏、无其他引用的孤立模板任务可软删除；其余任务解除模板关系并保留。
- 用户手动创建任务的 `estimatedPomodoros` 不被计划块数量自动膨胀；界面单独显示已计划块数。
- 模板任务在清除计划后重新计算估算，最低不小于 1，也不小于已完成轮次。
- 过去计划块不可启动，不回填历史；VoiceOver 明确说明已过期。

### 5. 纯视图读取

`focusTasksForFocusPage()` 必须是纯读取。跨日 carry、过期清理与 open session 归一化放到启动、回前台、日期变化、导入和云同步批次等生命周期边界执行，不能从 SwiftUI `body` 触发写盘。

## 三、通知与 Live Activity

### 1. 本地通知

`NotificationService` 统一管理 focus / break 请求：

- 开始新会话前移除旧 focus / break 请求；
- 首次开始时请求权限；
- 通知使用系统默认声音；
- 权限被拒、请求排程失败或系统返回错误时向 UI 暴露可恢复状态；
- 用户可进入系统设置或重试，不出现“什么都没发生”。

### 2. 单一 Live Activity

继续只保留一个 Live Activity：

1. 进入工作倒计时配置的显示窗口时，工作状态优先；
2. 不在工作显示窗口且 focus / break 运行时，显示专注或休息；
3. 状态切换串行执行，先结束旧内容再启动新内容，避免两个活动短暂并存；
4. state 扩展保持旧 payload 可解码；
5. 锁屏、灵动岛与 deep link 使用正确状态和目的页面。

## 四、SwiftUI 与可访问性收口

### 1. 记录沉浸画布

年 / 人生“展开”使用顶层全屏分支：隐藏导航栏、Tab Bar、尺度控件、标题、总结、辅助列表、图例和外层 `ScrollView`，只保留画布及至少 44×44 的收起按钮。

移除下滑或滚动导致的误收起。横竖屏和 iPad 分栏按当前可用尺寸重新计算点阵。

### 2. 长文案与动态字体

日期详情的来源标签使用 `ViewThatFits`：优先横排，空间不足时转为纵向。使用自适应圆角矩形而非强迫单行的 Capsule；德语、RTL、超大字体下不得挤压标题或截断状态。

### 3. 专注入口与状态

- 计时页专注入口使用可本地化 `Label`，点击区域至少 44×44，并在首次使用时解释用途；
- 番茄钟设置有明确入口；
- 过去计划块不可交互并有辅助功能说明；
- overflow、通知失败、下一阶段建议和未到开始时间都必须在页面可见。

## 五、实施顺序

1. 固化数据契约和失败测试；同步修订 002 / 006 / 010 的冲突口径。
2. 修复记录 P1：日期索引、免费遮蔽、导入导出、冲突与时区。
3. 修复番茄钟核心：设置、状态机、排班边界、恢复、模板与双设备收敛。
4. 接入系统表面：通知、Live Activity、入口和沉浸画布。
5. 跑自动检查、模拟器截图 feel check 和底层逻辑 CR；发现问题后重复修复与验收。
6. 输出真机验收清单，只把真机 / Production CloudKit 无法在本地证明的项目交给用户。

## 六、自动验证

### 记录测试

- 新索引覆盖自动会话、手动工时、请假、补班、休息日，且排除推算、仅打开观察与内置节假日。
- 免费窗口跨月 / 跨年仍不泄露锁外年份、月份、日期、数量与辅助功能文本。
- 损坏文件、不支持版本、读写失败与认证失败都有可见错误，且数据不变。
- 冲突迁移、字段 diff、整版本选择、失败保留、写回 edit stamp 和 `#user` 标记全部覆盖。
- 原时区日期、夏令时 23 / 25 小时与旅行换区覆盖。

### 番茄钟测试

- 25 → 5、第四轮 → 15、跳过休息、设置变化不改活动会话。
- 未来计划、跨夜班、跨午夜恢复、边界不足 60 秒、截短不计轮次。
- 同模板重复应用不重复，清计划后估算回落。
- 双 open session 确定性收敛且 loser 不计数。
- 微休边界、overflow、通知排程失败与 Live Activity 优先级覆盖。

### 命令门禁

```bash
npm run lint
npm test
npm run check:version
npm run build:ios-native-rules
npm run check:ios
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
npm run build
npm run check:build:web
npm run build:desktop
npm run check:build:desktop
```

共享规则、locale 或构建配置发生变化时，Web 与 Desktop 验证不可省略。

## 七、模拟器与截图 feel check

至少覆盖：

- iPhone 17 Pro、较小 iPhone 与 iPad；
- 浅色 / 深色、RTL、德语、辅助功能超大字体；
- 降低动态效果、降低透明度、增强对比度、无颜色区分；
- 免费 7 日窗口、锁外历史、手动记录回找、损坏导入、冲突详情；
- 年 / 人生沉浸展开与收起；
- 专注、短休、长休、下一阶段、未来不可用、overflow、通知失败；
- 锁屏 / 灵动岛 / 跨午夜，以及工作倒计时接管 Live Activity。

每张关键截图按用户视角回答：

1. 我一眼知道这里是什么、下一步能做什么吗？
2. 我写过的数据找得到、来源看得懂吗？
3. 免费限制是否诚实且没有泄露或诱导？
4. 异常发生时，我知道数据有没有改变、如何恢复吗？
5. 长文案、字体、颜色、命中区和层级是否让我感到拥挤或不可信？

## 八、真机交付门槛

模拟器和代码 CR 通过后，交付用户验证：

- 两台真实设备同一 iCloud 账户的增删改、双 open session 与冲突收敛；
- Production CloudKit schema 和完整删除 fence；
- 后台通知声音、锁屏与灵动岛；
- 工作倒计时与专注 Live Activity 的优先级切换；
- iPhone / iPad 真机的深浅色、RTL、超大字体、旋转与分屏。

真机失败必须回到本计划继续修复，不能以“模拟器已通过”签收。

## 九、本地收口结果（2026-09-01）

本轮代码修复、三轮底层逻辑 CR、自动化门禁和模拟器 feel check 已完成。最终独立复核未发现剩余 P0 / P1 / P2 本地交付阻断，因此进入 `READY FOR DEVICE VALIDATION`。在第八节外部验收完成前仍不建议正式发布，也不把计划标为 `DONE`。

### 已完成修复

- “全部记录”改用统一日期索引，能回找真实计时、手动工时、请假、补班和休息日；列表日期按记录原时区的 civil dayKey 呈现。
- 免费用户只获得滚动 7 日窗口内的视图模型，窗口外年份、日期和数量不进入界面或辅助功能树。
- 导入、导出、文件访问、认证和分享失败改为可见且可恢复的错误；取消操作保持安静。
- 冲突中心展示双方版本、修改时间和全部可编辑字段差异，复合字段保持原子选择；写回使用更高版本戳并保留失败冲突。
- 番茄钟支持可配置专注 / 短休 / 长休节奏、手动开始闭环、模板幂等、未来计划锁定、跨午夜恢复和多设备 open session 确定性收敛。
- 规划和下一阶段动作遵守共享排班片段；不足以容纳完整休息时不再显示无效休息入口。
- 通知排程增加当前会话校验，旧异步任务不能删除新会话通知；通知失败可见且使用系统默认声音。
- 外部导入、CloudKit batch 和冲突写回现在统一执行“跨日任务 carry → open session 收敛 → 系统表面即时重排”，不会让昨天导入的任务暂时消失，也不会让旧通知或 Live Activity 继续运行。
- 冲突三种写回都返回明确结果；写盘失败时冲突和原数据保持不变，当前页显示原因并提供重试。
- 单一 Live Activity 覆盖“专注先结束、稍后才进入工作显示窗口”与“工作窗口先到”的两种顺序；短休 / 长休使用正确本地化文案。
- iPad 改为单一动态导航栈，Focus 深链与 Records 四级导航均由同一栈承载，不再出现侧栏选中项与详情错位或路径类型崩溃。
- 年 / 人生展开成为真正的沉浸画布；冲突字段、德语超大字体和 RTL / 深色界面完成针对性收口。

### 自动验证证据

- `npm run lint`：通过。
- `npm test`：25 个测试文件、296 项测试通过。
- `npm run check:version`：版本 3.1.8 一致。
- `npm run build:ios-native-rules`：共享规则 bundle 生成通过。
- `npm run check:ios`：iPhone / iPad、WidgetKit、ActivityKit 与 Universal Purchase 配置通过。
- `xcodebuild ... test-without-building -parallel-testing-enabled NO`：284 项 iOS 测试通过、0 失败、0 跳过；结果位于 `/tmp/owc-011-release-gate-20260901-0450.xcresult`。
- `npm run build`、`npm run check:build:web`、`npm run build:desktop`、`npm run check:build:desktop`：通过。
- `git diff --check`：通过。

### 模拟器 feel check 证据

- iPhone 免费全部记录：`/tmp/owc-011-qa/iphone-free-all-records.png`。
- iPad 深色付费全部记录：`/tmp/owc-011-qa/ipad-paid-all-records-clean.png`。
- iPhone 番茄钟与设置：`/tmp/owc-011-qa/iphone-focus-populated.png`、`/tmp/owc-011-qa/iphone-focus-settings.png`。
- 小尺寸 iPhone 番茄钟：`/tmp/owc-011-qa/iphone-se-focus-overflow-final.png`。
- 短休、长休与下一轮：`/tmp/owc-011-qa/iphone-focus-short-break-offer-final.png`、`/tmp/owc-011-qa/iphone-focus-long-break-offer-final.png`、`/tmp/owc-011-qa/iphone-focus-nextFocus-final.png`。
- 未来精确时间锁定与当班容量不足：`/tmp/owc-011-qa/iphone-focus-future-final.png`、`/tmp/owc-011-qa/iphone-focus-overflow.png`。
- iPad 长休与通知权限恢复：`/tmp/owc-011-qa/ipad-focus-long-break-final.png`。
- 年视图沉浸画布：`/tmp/owc-011-qa/iphone-year-expanded-final.png`。
- 阿拉伯语 RTL / 深色人生画布：`/tmp/owc-011-qa/iphone-life-expanded-ar-dark-final.png`。
- 德语辅助功能超大字体：`/tmp/owc-011-qa/iphone-records-de-axxxl-fixed.png`。
- 冲突中心：`/tmp/owc-011-qa/iphone-conflict-center-final.png`。
- 损坏导入的“数据未改变”提示：`/tmp/owc-011-qa/iphone-records-invalid-import-final.png`。
- iPad 全部记录与四级导航：`/tmp/owc-011-qa/ipad-paid-all-records-after-nav-final.png`、`/tmp/owc-011-qa/ipad-records-deep-navigation-final.png`。
- iPad 深色增强对比度：`/tmp/owc-011-qa/ipad-records-high-contrast-final.png`。

截图与真实点击检查未再发现日期泄漏、原始字段 key、不可操作入口、阻断性截断或导航错位。当前 `simctl ui` 可验证深浅色、增强对比度和动态字体；降低动态效果、降低透明度与无颜色区分没有稳定的命令行开关，代码路径已复核，但最终手感保留给以下真机批次。

### 待真机 / Production 验证

- 两台真实设备在同一 iCloud 账户下验证增删改、冲突合并回写、双 open session 收敛和删除 fence。
- 核对 Production CloudKit schema、record type、索引和权限均与当前兼容契约一致。
- 验证后台通知声音、锁屏、灵动岛、跨午夜恢复，以及通知权限拒绝后的恢复路径。
- 验证工作倒计时与专注 / 休息 Live Activity 的单实例优先级切换。
- 在 iPhone 与 iPad 真机完成深浅色、RTL、超大字体、降低动态效果、降低透明度、无颜色区分、旋转和分屏复核。
