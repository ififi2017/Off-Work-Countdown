# Android 3.2.2 对照 iOS 3.2.2 验收（2026-10-16）

参照：iOS 固定源 `ea3144896caf6595509a8a6fef932d1ac835409a`，Debug 构建运行于 iPhone 18 Pro Max 模拟器（同时只开一台），英文、浅色，用 DEBUG 启动参数打开各页面。Android：Pixel 10 Pro 隔离 Debug 32212（parity322，同 PR313 代码），英文、浅色、系统字号 1.0。每张图左 iOS、右 Android。两端样例数据不同，只比较结构、样式、文案格式和动效；数据值的差异不算缺陷。动效依据两端源码对照（iOS `OWCMotion` 与使用处、Android `DoneAtMotion`/各页面），未录屏逐帧比较。

## 结论

欢迎页、付费墙结构、休假结果页与方案列表已基本对齐。**记录页与休假详情未达到 iOS 3.2.2 的设计**，主要是配色、人生视图、选中日卡片、详情页结构和几处动效，建议修完再作为送审候选。

## 发现（按严重度）

### 高

1. **记录分类配色仍是 3.2.2 之前的版本**（`records-month-summary.jpg`）。iOS 3.2.2：睡眠浅灰（`recordsSleep` 0.82/0.82/0.84，深色 0.28/0.28/0.29）、自有时间 systemGreen、工作中休息 systemIndigo 38%（深色 45%）。Android `DoneAtRecordsColors`：睡眠蓝 `#007AFF`、自有时间紫 `#AF52DE`、休息青 `#30B0C7`。影响时间分配卡、人生“时间去向”卡等。
2. **人生视图未按 3.2.2 重做**（`life.jpg`）。iOS 顶部是“距离退休进度 57%”的进度条与说明，阶段色为琥珀/青/靛/绿，下方是带年份范围的阶段列表和选中格卡片（“2026 · age 34 / Work · Now · Work year 12”）。Android 仍是标题 + 普通图例，阶段色为蓝灰/绿/棕/灰，没有进度条和阶段年份列表。
3. **日历下的选中日/选中月卡片缺失**（`records-month.jpg`、`week.jpg`、`year.jpg`）。iOS 周/月下方有可点按的“Fri, Oct 16 · Today · Planned 7 h ›”，年视图有“October 2026 · Days recorded… ›”。Android 三处都没有。
4. **休假方案详情结构与 iOS 不同**（`leave-detail.jpg`、`leave-detail-23.jpg`）。iOS：顶部“最后一班结束 → 15 d → 返岗”卡，随后“需请假”列表，每行有公文包图标和右侧天数，标题右侧显示“5 d in all”，底部是“Add to my schedule”。Android：重复了结果页的摘要卡和日历；摘要卡没有铺满宽度；请假行没有图标和天数，也没有合计；“最后一班/返岗”卡放在最底部的“Leave to draw on”标题下，中间的“15 days off in a row”折成三行。

### 中

5. **动效缺失**（源码对照）。iOS 记录页：切换到年/人生时图表淡入淡出 `recordsScaleChange`（0.20 s，cubic 0.23,1,0.32,1；周↔月不做动画）、展开/收起 `recordsExpansion`（0.26 s）、回到今天 easeOut 0.2 s、紧凑标题栏淡入 0.16 s、汇总数字 `.numericText()` 滚动；休假目标大数字 `.numericText()`。Android `ui/records`、`ui/leave` 只有标注位置动画、周期报告切换和结果页的错落进场（后者与 iOS 一致：先等 340 ms，每项间隔 60 ms，420 ms），以上几项都没有。
6. **非工作日与锁定日没有变暗**（`records-month.jpg`、`week.jpg`、`free.jpg`、`leave-results.jpg`）。iOS 把休息日、周末，以及免费用户窗口外和未来的日期显示为次要灰色；Android 多数仍是正文黑色，免费用户 18–31 日也是黑色。
7. **休假日期行缺节日名并多了年份**（`leave-results.jpg`、`leave-plans.jpg`）。iOS 写“Sep 23 – Oct 7 · 中秋节”，Android 写“Sep 23, 2026 – Oct 7, 2026”。
8. **免费用户锁定提示样式不同**（`free.jpg`）。iOS 是带锁图标的灰底圆角块，正文次要色，只有“See them with Plus”是橙色链接；Android 整句橙色，没有容器和图标。
9. **汇总数字格式不同**（`records-month-summary.jpg`）。iOS 时间分配每行右侧是加粗的“233h”和小号百分比，结论里写“about 70 h”；Android 是标签下的“232 h 30 m · 31.2%”，结论里写“about 71 h 13 m”。周视图 iOS 的大数字是“28”加小号“h”，并有“7h”目标线标签。

### 低

10. 加班图例：iOS 是工作条加橙点，Android 是橙色短条；年视图图例顺序 iOS 为 已记录/加班/计划，Android 为 已记录/计划/加班。
11. 休假色带里的节假日绿：iOS 用 `recordsHoliday`（浅色模式下是较深的文字级绿），Android 偏亮。
12. 方案列表的选中态：iOS 是橙色实心勾选圆，Android 是整行浅色底加勾。属平台差异，可以保留，但需要确认。
13. 付费墙报告预览的单位：iOS 写“2h / 41h”，Android 写“2 hr / 41 hr”（`plus.jpg`）。
14. 画廊休假详情显示“01:00 – 09:00”：画廊样例按 Asia/Shanghai 计算，界面却按档案的记录时区格式化，所以是 QA 工具问题。真实流程两端用同一时区，但本次的合成档案是轮班，尚未在 9–17 固定班上直接确认。
15. `countdownTick`：iOS 0.16 s，Android 260 ms（不属于 3.2.2 范围，顺带记录）。

## 一致或属有意差异

- 欢迎页的品牌标志、标题层级、页码点、主按钮一致；“Restore from a backup file”是 iCloud 入口在 Android 上的对应项（`welcome.jpg`）。
- 付费墙的标签、功能演示卡、样例数据说明一致；隔离包无法从 Play 读取方案，所以价格区没有比较（`plus.jpg`）。
- What's New：iOS 固定源的 `ReleaseNotes.current` 仍是 3.2.1，Android 新增 3.2.2 介绍，属计划 B4 的有意决定（`whatsnew.jpg`）。
- 分段控件、返回箭头、隐藏收入的眼睛图标、导航外观按 Material/Android 习惯。
- 休假结果页：摘要、日历色带、最宽一周上的连休标签、图例、“查看详情”一致。Android 多一个“Adjust conditions”入口，需确认这是否与 iOS 1ff56361 把筛选移到方案列表的做法冲突。
- 共享动效常量与 iOS 一致：press/selection/stateEnter/stateExit/phase、欢迎页 900 ms 指针与 70 ms 错落、优惠浮动/探出、报告 500 ms。

## 未覆盖

深色、RTL、200% 字号、TalkBack；欢迎后续页、首启设置与介绍页；带价格的付费墙和终身优惠；补班“Work”短标签与锁居中（样例月份里没有补班日）；动效未录屏逐帧比较。
