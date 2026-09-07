# 记录页 UI 走查与代码审查

日期：2026-09-05。代码基线：`bd3167e`，产品版本 3.1.9。以下审查记录保留原始证据；后续已按用户要求实施修复，当前状态见下节。

结论：优先修复月份收入范围和时间编辑器的时区问题，再处理手势与无障碍。发现 **2 项 P1、7 项 P2**；另有 3 项视觉打磨建议。没有发现此次可复现的崩溃或数据丢失，不能据此视为全面排除。

## 修复状态（同日）

已实施上述 9 项修复及视觉打磨，并处理补充反馈的重复触感：

- 触感只由主动日期选择、尺度切换和返回今天触发；删除尺度选择器重复反馈，数据加载与恢复选中日期保持静默。Tab 切换沿用根视图的一次反馈。
- 返回前台核对加载签名，保留尺度与选中日期；在记录页前台每分钟检查记录时区的日界线。后台及其它 Tab 不轮询；工资、语言和时区进入汇总失效签名。
- 收入限制在可见日格范围内，仍由共享 JS 规则计算；跨夜辅助日期仅参与工时。回归覆盖跨月、辅助前一天、带薪休假及排除今天。
- 编辑器局部注入记录 calendar / timeZone；年与人生画布改用 SpatialTapGesture；周图纵轴容纳全部加班，密集日期标签局部限制字号。
- 减少动态效果分支移除缩放与位移；日详情百分比提供 AX value；图例、轴及来源文字提高可读性，月纹理减淡，小圆点纹理裁切。
- 汇总标题自然换行并去掉挤占空间的装饰图标；性能用例使用授权、真实快照和跨夜含休息班次，断言非锁定且有来自两个班次的工作区间。

验证：`build:ios-native-rules`、`check:ios`、最终模拟器构建、`git diff --check` 通过。完整 iOS 测试 **370 项 / 4 个 suite，0 失败**；首次测试宿主启动停滞，重启专用模拟器后通过。最后的汇总图标精简另行编译通过。

- [最终测试日志](/private/tmp/records-fixes-final-tests.log)、[最终构建日志](/private/tmp/records-fixes-polish-build.log)。
- [375 pt 最大辅助字号](/private/tmp/records-fixes/small-week-accessibility.png)：30/31 完整显示，选中态无重叠。
- [主屏幕往返](/private/tmp/records-fixes/foreground-selection.png)：选中 8 月 31 日后回 Home 再打开，周视图与该日期均保留。
- [UTC 编辑器](/private/tmp/records-fixes/editor-utc.png)：设备北京时间下正确显示 09:00 / 18:00，Save 仍禁用；取消未保存编辑。
- 日详情实际 AX 树已确认结论节点含 `Value: 68.8%`；[手动横屏日详情](/private/tmp/records-fixes/day-landscape-dark.png) 布局正常。
- [横屏年份汇总](/private/tmp/records-fixes/year-summary-landscape.png)：QA 工资下九月 2,181.82、八月 11,454.55、全年 96,545.45，各自独立；最终去掉图标的长英文标题完整显示。
- 年图手势代码已替换，但自动注入拖动/滚轮的结果不稳定，本轮不把滚动交互列为已完成真机验收。
- [各尺度截图](/private/tmp/records-fixes/overview-shots/index.html)：保留自动走查结果。自动横屏 hook 仍有原先的 `still portrait` 问题；工具重启中断的日详情另外补跑，不计为通过。

新性能数据：历史索引 4.5 ms、年份解析缓存 0.2 ms、年份 metrics 5.3 ms、31 天日格 7.2 ms、含跨夜区间日画布 3.9 ms、人生投影冷加载 2323.8 ms / 暖缓存 0.1 ms。输入与原基准不同，不能直接称为性能提升；这些数字不等于主线程阻塞或真机帧率。

日详情补跑中 iPhone 明暗竖屏成功，iPad 仍遇到启动失败，不能视为日详情 iPad 验收通过。真实触感、跨午夜的实际设备验证、DST 时区保存往返及完整横屏验收仍需单独完成；不把模拟器或模型测试当作这些项目的通过证据。

## 范围与验证

- 重点阅读：周/月/年/人生主画布、日详情、日编辑、全部记录导航，以及对应的加载、统计、日期和性能测试代码。云同步后端、Production CloudKit、真实购买回流不是本轮完整覆盖范围。
- iPhone 17 Pro Max、iPad Pro 13-inch (M5)，iOS 26.5，五种场景、明暗模式自动截图；另用 375 pt 小屏 QA 模拟器检查交互、最大辅助字号和编辑器。
- 自动截图共 40 个目标，19 张成功。20 个横屏目标报告 `still portrait`，另 1 个年视图深色目标报告 `app not running`。没有找到对应的应用崩溃报告，因此未把这次启动失败列为产品 BUG。iPad 截图还存在画面倒置，不能只凭宽高判断方向正确。
- 手动补查了 iPad 横屏年视图、展开/收起和月份选择。其它横屏组合、完整 19 语言、真机触感、逐帧动效和 60 fps Instruments 测量仍未覆盖。
- 已重新生成 iOS 规则 bundle，模拟器构建成功；`npm run check:ios` 通过；完整 iOS 测试 **369 项 / 4 个 suite，0 失败**。这些主要是模型测试，并不覆盖下述 UI 问题。
- [截图联系表](/Users/zhengyuxuan/Off-Work-Countdown/scripts/ios-qa-shots/index.html)、[测试日志](/private/tmp/records-review/ios-tests.log)、[截图日志](/private/tmp/records-review/screenshot-sweep.log)、[本次性能数据](/private/tmp/records-review/performance.txt)。`/private/tmp` 中的附件是本轮本机审查证据；重新运行截图脚本会覆盖联系表。

## P1：优先修复

### 1. 选中某个月，收入仍使用全年累计

**证据：UI 复现 + 完整调用链。** iPad 年视图中，九月显示 4 天、32 小时；切换八月后变成 20 天、151 小时 10 分，但两个月的收入都为 **97,090.91**，并且与下方全年卡片一致。这是 QA 设置的模拟工资，不是用户真实工资。[八月截图](/private/tmp/records-review/ipad-august-income.png)

[RecordsDesignView.swift:666](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsDesignView.swift:666) 将月度 `cells` 与全年的 `days` 一起交给 `recordsHeadline`；[OffWorkStore.swift:3748](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/OffWorkStore.swift:3748) 却直接遍历全部 `days` 计算已结束排班工作日。工时限定在所选月，收入没有。周/月加载额外传入的前一天也可能被算进收入。

**建议：** 把统计窗口与跨夜所需的辅助日期分开。收入只计算显示窗口内、已经结束的基础排班工作日，继续调用现有 TypeScript 收入规则；不要改成只计算有打卡记录的日期，以免破坏现有带薪休假口径。补“全年中选月”和“窗口带前一天”的回归测试。

### 2. 日编辑器的显示时区与读写时区不一致

**证据：UI 复现 + 代码。** 在记录时区为 UTC、设备为北京时间的 QA 会话里，编辑器内部默认的 09:00 / 18:00 显示成了 **17:00 / 次日 02:00**。[编辑器截图](/private/tmp/records-review/editor-timezone.png)

[RecordDayEditView.swift:90](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordDayEditView.swift:90) 的两个 `DatePicker` 使用系统环境时区，但 [同文件:295](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordDayEditView.swift:295) 的 Date 构造与分钟提取均使用 `store.recordsCalendar`。如果用户按照记录时区把显示值改成期望时间，绑定会再次按另一时区提取分钟，保存错误时刻。原样打开再关闭不会因此自动改数据。

**建议：** 在编辑器局部明确提供与绑定一致的 calendar / timeZone，并让用户知道所编辑的记录时区。复测 UTC、上海与 DST 时区的显示—选择—保存往返。[Apple 的 timeZone 环境文档](https://developer.apple.com/documentation/swiftui/environmentvalues/timezone)

## P2：交互、无障碍与验证缺口

### 3. 年图内部上滑会选择月份，而不是正常滚动

**证据：年图 UI 复现；人生图为相同代码路径。** 在小屏年图内部向上拖动，标题和画布停留原位，选中月份却从九月变成落点对应的一月。图表占据首屏的大部分空间，误操作容易发生。

[RecordsCanvasViews.swift:763](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsCanvasViews.swift:763) 和 [同文件:1358](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsCanvasViews.swift:1358) 都用 `DragGesture(minimumDistance: 0)` 实现点击命中，并在结束时不区分点击与拖动。只加位移阈值能避免错误选择，但不足以解决手势争用。

**建议：** 使用能提供落点的点击手势（如 `SpatialTapGesture`），把纵向拖动留给外层 ScrollView；保留现有 VoiceOver 按钮表示。验收时分别从网格、月份按钮和图表外开始拖动。

### 4. 周视图在最大辅助字号下日期截断、重叠

**证据：小屏 UI 复现。** 最大辅助字号下，30/31 显示成省略号，日期与星期挤在一起，选中日期的橙色底也容纳不下文字。[大字号截图](/private/tmp/records-review/small-week-accessibility.png)

[RecordsCanvasViews.swift:615](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsCanvasViews.swift:615) 的文字跟随 Dynamic Type，但 [同文件:633](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsCanvasViews.swift:633) 把整个周图固定在 188 pt，仍然使用七等分列。月图已有针对密集标签的字号上限，周图没有相应处理。

**建议：** 为辅助字号提供能完整读出日期的布局，或对密集轴标签作与月图一致的局部限制，并验证小屏宽度下两位日期仍能显示。详情文本继续跟随完整字号，不要限制整页。

### 5. 常规工时达到 12 小时后，加班柱完全消失

**证据：确定性代码路径，未另造用户记录。** [RecordsCanvasViews.swift:678](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsCanvasViews.swift:678) 把常规工时先截到 12 小时，再把加班限制到剩余高度。12 小时常规工作加 2 小时加班时，`work = 1`、`overtime = 0`，图表与没有加班的 12 小时班次一样。11 小时加 3 小时也只画出 1 小时加班的比例。

**建议：** 七天使用同一个、能覆盖最长总工时的纵轴上限，然后按实际常规/加班时长拆分；或明确显示溢出状态，不能静默截掉加班。补 12+2、11+3 与普通短班次对比用例。

### 6. Reduce Motion 只改时长，仍保留位移和缩放

**证据：静态审查；未宣称完成真机减少动态效果验收。** [RecordsCanvasViews.swift:1453](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsCanvasViews.swift:1453) 的人生图例始终使用底部移入；年/人生 callout 和返回今天按钮也始终组合 scale transition。切换到 `OWCMotion.reduced` 只改变动画时间，不会删除这些 transform。

| 当前 | 建议 | 原因 |
| --- | --- | --- |
| `.move(edge: .bottom)` + reduced easing | 减少动态效果时使用 `.opacity` | 缩短运动不等于移除运动 |
| `.opacity.combined(with: .scale(scale: 0.92))` | 减少动态效果时只保留淡入淡出 | 避免剩余的空间缩放 |

正常动效的 0.18–0.26 秒本身没有明显超长问题。此项 **Block** 指减少动态效果分支不能验收通过，不是要求重写整套动效。保留 OWCMotion，改变实际参与过渡的属性。[Apple 的 Reduce Motion 文档](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)

### 7. 日详情的百分比对 VoiceOver 丢失

**证据：实际 AX 树与截图对照。** 页面显示 68.8%，辅助功能树中的合并结论却只有“Waking time that is yours, 16 h 30 m, Share of 24 hours …”，没有百分比。

[RecordsDayCanvasView.swift:169](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsDayCanvasView.swift:169) 用 `accessibilityLabel` 将百分比 Text 的默认朗读内容替换成了说明名，未另提供值。

**建议：** 给该节点补格式化后的 `accessibilityValue`，或让整张结论卡明确组合名称、时长和百分比。复查合并后的 AX 树，而不只检查代码里是否出现了 accessibility modifier。

### 8. 持续停留记录页跨过午夜，日格不会按新一天刷新

**证据：加载触发链审查；没有修改系统时钟进行 UI 复现。** [RecordsDesignView.swift:114](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsDesignView.swift:114) 只在出现、切标签、归档 revision 或 Plus 变化时加载。`currentLoadSignature` 虽然含 dayKey，但没有日界线事件触发它；普通 `Date.now` 也不是可观察状态。

在没有新记录写入的休息日，保持记录页可见跨过午夜，旧 `cells` 的 isToday、计划/历史标记和免费窗口可能继续保留，直到下一次交互触发加载。日详情已有分钟刷新逻辑，根画布没有。

**建议：** 增加低频、按记录时区判断的日界线失效触发，并在前台恢复时核对；不要引入每秒重建日历。补跨月、免费窗口移动和休息日用例。

### 9. 性能基准主要测到锁定占位，未覆盖真实日画布

**证据：测试输入与访问门禁。** [RecordsPerformanceTests.swift:102](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/AppTests/RecordsPerformanceTests.swift:102) 取全年最后 31 天，单日用例取最后一天；seededStore 没有授权 Plus。本轮时间为九月，十二月均不在免费窗口内，`recordsDayCanvas` 直接返回锁定模型，日格也跳过真实 allocation。

因此本轮“31 格 5.1 ms、单日 0.0 ms”不能作为真实记录画布性能合格的证据。现有测试只有数量和宽松时间门限，未断言模型已解锁、有班次、有区间。

**建议：** 明确授权测试账号，选含真实观察记录和跨夜班次的历史月份，并先断言非锁定、有工作区间，再计时。锁定快速路径可以单独保留。真实主线程成本和帧率仍需要单独测量。

## UI 打磨建议

这些属于可读性与视觉层级改进，不需要扩大卡片或推翻现有设计系统。

1. **提高图例、来源与轴标签的可读性。** 周/月图例、日详情说明大量使用 `.tertiary` + `.caption2`，浅色和深色截图里都明显偏淡。对解释数据含义的文字优先使用 secondary；tertiary 留给确实可略读的信息。本轮未进行完整像素对比度认证。
2. **避免汇总指标的长英文省略。** iPad 竖屏时，全年汇总的“Waking time that is yours”仍被三行限制截断，图标、帮助按钮与预留 padding 挤占了标题空间。优先减少指标内部占位，允许标题自然换行；不用再增加一个更高的固定卡片。
3. **减轻月图大面积预测网纹，并裁切日详情的小圆点纹理。** 月初几天真实记录与整月网纹相比过于安静；可以降低预测纹理的对比，同时保留事实/估算的区别。日详情的估算圆点在深色截图里可见斜线超出圆点，`RecordsDayIntervalRow` 的圆形纹理需要与形状一起裁切。

## 性能与实现评价

本轮测试最后一次输出：人生投影冷加载 172.3 ms，暖缓存约 0.0 ms；历史索引指标 4.1 ms，年份 metrics 6.4 ms。这些是本机模拟器、测试数据下的方法级耗时，包含相应异步等待；不能换算成主线程阻塞时间或“稳定 60 fps”。月格和单日数字的覆盖限制见第 9 项。

目前已有后台 schedule expansion、revision 缓存、日格统一来源、跨夜/DST 测试，未发现需要通过引入新框架来解决的问题。更有价值的是修正统计窗口、手势类型、局部环境和测试输入。

中途检查了工资设置/语言变化是否会导致汇总缓存陈旧。加载签名确实不包含这些输入，但导航返回会不会重新触发 `.task` 取决于 shell 和路径；本轮未获得稳定 UI 复现，因此不列入确定缺陷，也不据此断言工资开关失效。

## 建议修复顺序与验收

1. 月份收入范围、时间编辑器时区；补精确回归用例。
2. 年/人生图表点击与滚动分离、周图超长工时、辅助字号、百分比 AX 值。
3. 修正 Reduce Motion 的实际 transition，完成前台日界线刷新。
4. 修复性能基准输入后再测，并补齐失效的横屏截图、真机帧率与触感验收。
5. 最后做对比度、标题换行和纹理打磨。视觉微调不能替代前面的正确性修复。

本轮不把 plans/013 的真机、60 fps、完整无障碍和购买回流验收标为完成。
