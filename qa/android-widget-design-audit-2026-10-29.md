# Android 小组件设计静态核对（2026-10-29）

依据：用户提供的「DoneAt 3.3 小组件设计.html」及本机解包的
`design-0/1/2/4/6/7.html`，交叉检查当前 iOS WidgetKit 实现与 Android
snapshot。原始 HTML、脚本、图片和整份设计内容不进入仓库。

这是**源文件静态审计和待验收清单**，不是视觉验收通过记录；本次未运行构建、
浏览器或 ADB。稿内日期、工时、任务和假期数值都是示例，不是业务默认值。

## 通用视觉基线

- 参考画布的组件尺寸：Small **170×170**、Medium **364×170**、Large
  **364×382**；倒计时另有 iPad XL **715×338**。这是稿的 pt/CSS 基准，
  Android 按 launcher 实际 dp 尺寸适配，不能把 iOS 尺寸直接声明成 Android 格数。
- 白底卡、约 22 圆角、16 内边距；层级为 12–13 的标题/副文、20–26 的统计值、
  28–44 的主要数字；大数字专用样式约 60。实际落地继续使用 Android 既有字体/
  token，不能为了 SF Pro 外观引入 Apple 字体。
- 默认品牌橙、深色主字、灰副字/轨道；完成/当前/未来必须有明确色阶。稿只有浅色，
  暗色要按当前产品色板单独验收，不能反转整张图或照搬白底阴影。
- 每种 size 有自己的信息组织；不能把 Small 的“标题+数字+一条进度”统一放大到
  Medium/Large。时间、百分比、列单位共用基线，数字等宽，不因秒数更新跳动。
- 参考尺寸可完整显示；launcher 的更窄/更矮尺寸可缩减次要信息，但不截断主值、
  不把必需列挤出界、不把图表当可选装饰删掉。长翻译、RTL、200% 字体另测。
- 画廊与 launcher 使用同一渲染路径和同一真实/示例状态模型；解锁预览必须明确
  是示例，不能为了预览绕过实际权限。无数据、未设排班、Plus 失效各有独立状态。

## 各类 / size 视觉验收清单

以下均待实际截图核验；括号中的数值是设计布局依据，不能硬编码成用户数据。

| 类型 / size | 可核验的构图要求 | Android 现有数据与边界 |
| --- | --- | --- |
| 经典倒计时 S | 品牌行 → 有色状态胶囊 → 约33的大计时 → 底部渐变进度 → 左百分比/右目标时间；午休状态另色，目标是回来时间 | `WidgetEntry` 的 phase/label/countdownKind/target/progress 足够；午休不能仍计到下班 |
| 经典倒计时 M | 左侧状态、约38计时、目标；右侧约76环及居中百分比，不是上下堆叠 | 同上；保留既有 receiver/用户放置 |
| 经典倒计时 L | 顶部品牌/状态/约40计时/进度；下半“接下来”4行，图标+双层文案+右对齐时间 | `WidgetSnapshot.upcoming` 已有 kind/title/detail/date；按 kind 映射现有图标，当前行不重复“今天的班次” |
| 大数字 S | 一眼可读的时:分约60；上方短语/状态小图标，下方目标时间；留白主导 | 当前条目足够；不是经典样式增大字号 |
| 分段环 S | 约128环围绕中间状态/时:分/目标；真实午休成为环缺口，过去/未来分明 | `countdownSegments` + `countdownTimeZoneIdentifier` + entry 足够；不可套稿里固定弧长/固定午休 |
| 今日时间轴 S | 左侧窄竖向工作段/间隔；右侧上班、休息、现在、下班节点；“现在”较深 | segments 提供起终点/间隙；超出可读节点时压缩辅助行，不能发明休息时段 |
| 详情倒计时 M | 左半状态/约34计时/目标百分比/分段条；竖分隔；右半3条带图标的近期事项 | entry、segments、upcoming 足够；左/右栏是真布局，不用单列卡冒充 |
| 详情倒计时 L | 顶部状态+日期；约44主值、右侧百分比；分段条下标起点/休息区间/终点；分隔后约5行接下来 | 同上；跨天事项明确“明天”，所有时间使用对应 countdown zone |
| 周末 S | 标题；大“天”与较小余时共基线；休息起点副文；底部工作日分段条 | `weekendStartMs` 提供目标、calendar提供已解析工作段；稿写有效工时，实际 iOS 用墙钟相对时间，不能混用两种口径不标明 |
| 假期 S | 标题/假期名对齐；约40天数；具体日期/假期长度；预测数据说明置底 | `nextHoliday` 的 name/start/dayCount/isEstimated 足够；只使用已覆盖模板，不能声称联网自动获取公告 |
| 请假 M | 顶部假期/距开始与余额；中间约20的“请几天、连休几天”；下方连续日期色块+日期号+三色图例 | `nextLeave` 可呈现**已记录或采纳**请假连休；目前不是智能推荐首选方案。无请假时保持空态；失效后余额/连休/真实色块不能残留 |
| Focus M（运行） | 顶部状态和右上轮次；左侧任务名/约34剩余时间；右侧两个约44圆形动作；下方分段进度/下一阶段副文 | title/start/end/round/rounds/isBreak/isRunning 足够绘制；真实运行才计时。回调必须重新校验当前session起点/权益/可执行性，不能仅凭图上按钮 |
| Focus S（计划） | “下一段”标题 → 约30开始时间 → 时长+任务；底部动作/打开入口 | planned block 足够；计划到时不等于真的开始。“现在开始”会改变生命周期，不能只按稿画一个无真实资格判断的按钮 |
| 汇总 S | 本周+周数；约34工时，底部今日突出色的小柱图和星期标签；锁态是灰色示意柱 | period.WEEK 和 bars/liveSegments 足够。稿的“/40小时”不是通用固定目标；现payload无 plannedHours 字段 |
| 汇总 M | 本月/副标题、右上剩余工作日；三列工时/工作日分子分母/加班；底部横条与周期标注 | period.MONTH 三项/起终日/进度均有；不能继续把周、月、年串成几行事实列表 |
| 汇总 L | 年份/剩余工作日；上方三指标；主体12个月柱图；底部分隔后比较文案 | period.YEAR/month bars 足够；比较字段是上一周期**总工时**，不是“同比少加班” |
| 年进度 S | 顶部年份与剩余天数；居中约104环；中间大百分比+短单位 | `WidgetCalendarProgress.year/daysLeftInYear` 可供；保持免费年进度与付费Life区分 |
| Life S | 人生/可选年龄副文；已度过的大天数、约占寿命；底部求学/职业/退休三段及年龄节点 | life日期/精度/隐龄/寿命 + `WidgetLifeFigures` 足够；年精度显示约数，隐龄按已有规则处理 |
| Life M | 上方进度与日期时间；今天/本周/本月/今年四条整齐对齐条，固定标签列/百分比列 | CalendarProgress为自然周期；稿额外写“今天按有效工时”，需读取现有countdown进度并约定工作/休息态，不能谎称已与iOS算法相同 |
| Life L | 上方寿命与可选年龄；主体8个十年行×10年、每年12个月点；当前月独立深色，职业过去/未来不同橙；底部工作/退休跨度两列 | born/career/retirement/lifeYears + LifeFigures足够；不能用通用进度条代替年月格。不要把稿里的22/60/80硬编码到真实profile |
| 本周 M（固定/大小周） | 标题/日期或下周安排；约26分数天数+收工时间；7个下向填充日块和星期；休息/节假日淡色，今日强调 | `WidgetWeekProgress` 的 remainingDays/fill/finish、calendar日kind足够；周六调休应计入，分数天不能改成整数工作日计数 |
| 轮休 M | 上N休M/周期第几天；“再上几天休息”+休息日；14个连续班/休色块与星期，不与自然周强行对齐 | calendar scheduleKind/cycleDay/cycleLength + `WidgetRotationOutlook` 可供；目前只给cycleLength，未必能还原任意自定义规则的“上N休M”名称，未知就不编 |
| 排班 S | 今天/明天+星期；独立班别色签；约20起终时刻；下方下一组休息说明 | calendar title/color/segments/kind足够；应按实际班次结束切换，不把20点设成新规则，夜班跨午夜仍正确 |
| 排班 M | 稿是紧凑月历：标题/排班模式/本月工作日数；7列小日期格，工作浅橙、休息灰、今日反色 | calendar月内days/isWork/firstDayOfWeek足够；实际iOS M是未来7天排班条，不能说其当前实现已与这张稿相同 |
| 排班 L | 标题/本月统计；7列星期行+5或6周日期格，每格日期号+真实班签；今日底色；不以抽象圆点替代班签 | calendar够绘图；没有shiftTypeID/夜班类别字段，不能从“夜”字或颜色推断“本月夜班次数”。可用现有真实工作日总数 |
| 未设排班 S | 图标+排班标题、两行说明、底部设置入口；不能显示示例工作日为真实排班 | scheduleKind.NONE/无days已有；手动计时不等于已配置排班 |
| 付费锁态 S/M/L | 小Plus徽记、简短好处、灰色图形示意、了解Plus入口；无真实任务/出生/余额/统计，也无动作按钮 | snapshot.redacted + 当前权益交集已有；过期/撤销、读取/重绘均重新执行。示意图不能复用真实付费图形再调灰 |

## 当前数据缺口 / 不应凭设计扩大的功能范围

| 稿件描述 | 当前实际来源 / 结论 |
| --- | --- |
| 所有假期Plus，未订阅不显示真实假期 | iOS HolidayWidget 明确保留免费 nextHoliday；只有请假/余额上锁。Android现契约相同。视觉重做不等于授权修改权益边界 |
| 智能拼假首选、最划算建议 | 当前 WidgetSuiteComposer.nextLeave 仅从已有leaveDays拼接休息/假期；未暴露leave-planner候选/排名。只能诚实展示“已安排请假”或空态；若要推荐另接真实planner结果，不能填示例 |
| 小汇总“已工作 / 计划40小时” | 无plannedHours。可在domain通过已解析的周工作段做特定周目标投影，再加字段/测试；不能渲染层用plannedWorkdays×8 |
| 年汇总“同比少加班18小时” | comparison目前是上周/月/年总工作时长，缺去年同期加班对照。沿用真实既有比较，或后续增加真实对照字段/计算 |
| 长按编辑周期、自定义结算周期 | 实际iOS SummaryWidget是StaticConfiguration，按size选周/月/年；Android契约也只有WEEK/MONTH/YEAR。不能由UI稿凭空加结算规则 |
| 20点切明天 | 实际iOS RosterFocusDay在今日work结束后转明天；否则保留今日。现calendar足够实现该规则；固定20点会误报夜班 |
| 月历点某天进那天、智能规划入口 | payload有dayKey，但当前整张bitmap只提供单一点击区域；要逐日点击需要独立Glance点击单元与已支持的路由，不是画出格子就完成交互 |
| 实时秒计时 / 今日柱继续长高 | endMs/liveSegments已存在，但烘焙bitmap不会自行每秒改变；倒计时应使用现有系统计时能力，柱图要明确重绘节奏。计划阶段必须保持非运行态 |
| 放假公布后自动更新 | 模板是随应用打包的覆盖数据+isEstimated；不能从稿件许诺新增联网/后台获取/自动更新服务 |

## iOS 平台专属，不直接作为 Android 新功能指令

- `design-3/5` 的 Watch 表盘、复杂功能、配对与常亮：本轮不移植，Wear OS 仍是
  既定延期范围。
- `accessoryCircular/Rectangular/Inline`、iOS锁屏小组件、iOS18 Controls、StandBy
  横放充电放大/夜间红色是 Apple 系统入口。可以借鉴排字，不能据此增加 Android
  锁屏、Quick Settings Tile、常驻后台或绕过省电策略，也不能声称 Android 支持这些入口。
- XL明确标为iPad：Android平板宽卡可按实际可用空间适配三栏/竖排，但不是照搬
  `.systemExtraLarge`，更不是所有手机都要提供额外大号。
- 稿说“不打开App”的Focus操作；实际iOS FocusWidget使用 `Link` 跳App动作URL，
  Small则是打开专注。Android当前已有动作回调仍需用其真实校验路径；不要把稿的
  App Intents技术描述当成新增跨平台行为授权。
- 稿未完整描述所有锁态、空态、休息/下班/加班态或暗色；以真实产品规则补齐，
  不复制示例文案来掩盖缺数据。

## 可核验的源码锚点

- Android：`core/domain/.../widget/WidgetSnapshot.kt`（条目、目标、状态、近期事件）；
  `WidgetSuiteSnapshot.kt`（只含薪资以外投影、付费redaction）；
  `WidgetSuiteFigures.kt`（周剩余分数天、轮休、DST自然周期、Life标量）；
  `WidgetFocusComposer.kt`（真实运行/恢复/计划区分）。实际工程根目录为
  `src-mobile/android/`。
- iOS：`src-mobile/ios/App/App/Native/Widgets/SummaryLifeHolidayWidgets.swift`
  的 `SummaryWidgetView.kind`、`CalendarProgress`、`LifeFiguresView`、
  `HolidayWidgetView.medium`；`WeekRosterWidgets.swift` 的 `RosterFocusDay`、
  `RosterStripView`、`RosterMonthView`；`FocusControlWidgets.swift` 的
  `FocusWidgetView.running/upcoming`；`Native/Services/WidgetSuiteComposer.swift`
  的 `nextLeave`、`summaryPayload`。

## 后续截图验收最小矩阵

在实际launcher与应用画廊各取同一状态，按S/M/L及实际最窄尺寸核验上述表格；
画廊不能与桌面采用另一种简化布局。至少涵盖：浅/深、英文/简中/长译文/RTL、
当前周含调休与休假、五/六行月历、跨夜分段/午休、真实Focus与仅计划Focus、
Plus有效/到期/撤销、出生年精度/隐龄、未知假期地区/超出模板覆盖、未设排班。
不把本文件的未勾选设计清单或源代码推导当成已完成的视觉验收。
