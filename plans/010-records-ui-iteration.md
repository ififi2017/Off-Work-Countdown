# 010 — 记录 UI 迭代

- **状态**：IN PROGRESS — Phase 2–6 UI 已落地，Phase 7 HealthKit 按计划延期，Phase 8 真机验收未完成
- **日期**：2026-08-30
- **进度（2026-09-01）**：单画布、锁定层、日期 sheet、19 locale 与人生档案已经接上；验收仍发现“全部记录”遗漏手动写入、免费列表泄露锁外年份 / 数量、导入导出静默失败、冲突不可知情选择、时区显示漂移、展开不沉浸和长文案拥挤。上述发布阻断与模拟器 / 真机验收统一转入 [011](011-ios-records-focus-release-remediation.md)。Phase 8 在 011 真机门槛完成前不得标完成。
- **范围**：iOS / iPadOS 原生 SwiftUI 的记录、人生视图、记录数据设置与专注入口
- **依赖**：[002](002-records-life-focus.md) 的记录与 CKSyncEngine 基础、[006](006-free-trial-subscription.md) 的 StoreKit 权益、[007](007-ios-stable-before-subscription.md) 的稳定性基线
- **目标**：移除记录首页的五个大入口，把记录重构为一张可在周、月、年、人生四个尺度间切换的主画布；默认月历，图在上、结论在下；把数据管理收进设置；保证免费预览、人生档案、CloudKit 冲突、跨夜班和长文案都有明确产品口径
- **不包含**：Tauri / Web 记录页、薪资规则重写、把共享排班规则移植到 Swift、把人生视图变成寿命倒计时、上传原始 HealthKit 睡眠样本

## 为什么另开 010

002 已经把记录、人生视图、CloudKit 与专注做成可运行的 P1，但当前记录首页先给用户五个并列的大入口，信息架构仍像功能目录，不像一段连续的回顾体验；人生视图又按一年一行、每周一格绘制，长到退休时容易成为密集的“马蜂窝”。

本计划不推翻 002 的记录事实、排班规则、时区和同步底座，只重做产品呈现与少量为新呈现服务的数据契约。与 002 / 006 冲突时，本计划对以下内容具有优先级：

1. 记录首页不再是周 / 月 / 年 / 人生 / 专注五行入口。
2. 新用户不再从 2000 年或任意历史日期自动铺出逐日工作底图。
3. 免费用户可使用周、月视图，但只显示“今天及之前 6 天”的真实记录；不能通过记录页编辑任何一天，但完整导入、导出和删除仍是数据权利。
4. 人生视图不再一周一个格，也不再一年一列或一行；点阵是响应式的比例采样，不是日历。
5. 人生档案增加首次入学日期，并把出生、入学、首次工作、退休统一为“仅年份或精确到日”的部分日期。
6. 专注从记录维度移出，改为计时页左上角的“添加待办”入口。
7. 导入、导出、清除、时区、iCloud 和人生档案进入“设置 → 记录与数据”；完整记录列表保留在记录页右上角。
8. 006 中“免费可查看全历史逐日列表”的口径由滚动 7 日预览取代；实施本计划时必须同步修订 002、006 和付费页文案，不能让三份计划同时声称不同权益。

## 已定产品原则

1. **一张主画布，四个尺度。** 页面一次只展示周、月、年、人生中的一个尺度，默认月；分段选择器是主入口，双指缩放只是增强手势。
2. **图在上，总结在下。** 所有尺度使用同一阅读顺序；展开图表时隐藏总结，本次会话内保持，重新启动后恢复默认。
3. **事实与推演分开。** 日历只把实际写下的记录称为记录；人生档案只生成视图模型，不生成过去数千条 DayOverride、DailyWorkSummary 或观察记录。
4. **人生只画到退休。** 不询问寿命，不显示“还剩多少周”，避免把产品变成寿命倒计时。
5. **少填、可跳过。** 人生档案不是简历；任意日期都可以不填，缺失阶段显示“未设置”，不偷偷推断。
6. **宏观图可以近似，底层统计不能漂。** 点阵数量可随屏幕变化，但阶段起止、时长、占比和汇总由同一份精确模型计算。
7. **修正使用 sheet，不跳页。** 周、月的日期详情留在主页面下方；编辑是短任务，用系统 sheet / form sheet，带取消、保存和未保存退出确认。
8. **隐私操作有第二道门。** 启用现有生物识别保护时，编辑人生档案、导出、覆盖式导入、清除和同步整库覆盖在确认后再走设备所有者认证；认证允许 Face ID、Touch ID 或设备密码回退。
9. **毛玻璃只是视觉，不是权限。** 锁定区域渲染专用占位内容，绝不先绘制真实数值再模糊；VoiceOver 也拿不到锁后数据。
10. **本地优先不变。** 未开启 iCloud 时全部输入只在本机；CloudKit 只同步可重建视图所需的原始输入，不同步点阵、聚合缓存或原始健康样本。

## 信息架构

```text
计时 Tab
└── 左上角 +
    └── 添加待办 sheet
        ├── 标题
        ├── 立即开始
        └── 安排在当前 / 下一班次的某个有效工作片段内

记录 Tab
├── 右上角：全部记录
│   └── 年 → 月 → 当月日期 → 日期详情
├── 周 / 月 / 年 / 人生尺度选择器
├── 主可视化（默认月历）
├── 选中对象详情（周 / 月是日期；年 / 人生是区间或阶段）
└── 四项总结 + 时间占比横线图

设置 Tab
└── 记录与数据
    ├── 人生档案
    ├── iCloud 同步与冲突
    ├── 记录时区
    ├── 导入完整数据
    ├── 导出完整数据
    └── 危险区：清除此设备 / iCloud 与所有设备
```

### 导航语义

| 入口 | 呈现 | 返回行为 |
| --- | --- | --- |
| 记录 Tab | Tab 根页面 | 再次点按当前 Tab 回到根并滚到顶部 |
| 全部记录 | `NavigationStack` push | 返回记录主画布并保留尺度、选中日期和滚动位置 |
| 年 → 月 → 日期 | 同一层级继续 push | 系统返回手势逐级返回，不自制返回按钮 |
| 日期编辑 | iPhone `.sheet` 中 / 大 detent；iPad form sheet | 取消或下滑退出；有未保存内容时确认丢弃 |
| 人生档案首次设置 | 非阻塞卡片触发的 modal / form sheet | 可跳过；保存后回到原月视图，不替换 Tab 根 |
| 人生阶段详情 | iPhone 中等 detent sheet；iPad 锚定 popover | 关闭后阶段仍保持选中 |
| 导入 / 导出 | 系统文件选择器 / 系统分享控制器 | 完成或取消后回到“记录与数据” |
| 删除确认 | 系统 confirmation dialog / alert | 取消留在原处；确认后认证，再执行 |

## 记录主页面

### 顶部结构

- 使用原生导航标题“记录”，右上角是 `calendar.badge.clock` 或 `list.bullet.rectangle` 的“全部记录”按钮；不再在内容区重复一个大标题和五行菜单。
- 标题下方是周 / 月 / 年 / 人生四档选择器。常规 Dynamic Type 使用原生 segmented picker；德语、法语、俄语等长标签或辅助功能字号放不下时，用 `ViewThatFits` 降级为显示当前尺度的原生 `Menu`，不得截断成难以识别的半个词。
- 选择器顺序固定为周、月、年、人生。选择后更新同一主画布，不 push 新页面。
- 双指张开从月进入周，捏合从月进入年、再进入人生；手势不是唯一入口，VoiceOver 与开关控制用户仍可完整操作。

### 首次进入

1. 首次打开记录 Tab 立即展示当前月，不先弹阻塞式问卷。
2. 不自动补写首次进入之前的排班日、DailyWorkSummary 或观察记录；已有的真实计时观察、用户导入数据和用户主动覆盖可以照常出现。
3. 月历下方展示一张可关闭的“完善人生视图”卡：说明只需要大概年份也可以，支持“现在设置”和“稍后”。
4. 用户选择设置时进入人生档案表单；保存只生成 / 更新 `LifeProfile`，人生点阵在读取时派生。
5. 关闭引导只记录 `lifeSetupPromptState = dismissed`，不创建空档案；人生尺度继续提供手动设置入口。

### 月视图（默认）

- 主体是原生日历语义的月网格：星期标题、当前月、今天、选中日、未记录、已记录、用户修正和锁定必须可区分。
- 默认选中今天；切月后优先选中该月最近的有记录日期，没有则不选中。
- “未记录”是明确状态，不等于休息日，也不拿当前排班回填为历史事实。
- 点按未锁日期后，月历下方原地更新当日详情：日期、记录来源、正常工作、加班、班中休息、睡眠来源、自由时间和观察事件。
- Plus 用户看到“编辑这一天”；点击打开编辑 sheet。免费用户详情只读，不显示一个点击后才失败的伪编辑按钮，改为紧邻详情的 Plus 说明。
- 编辑 sheet 只改原始输入：记录类型、上下班绝对时间、有效工作 / 休息片段、加班片段、当日排班覆盖、备注。工作总时长、自由时间、百分比和收入等派生值实时预览但不可手填。
- 未来日期可以显示排班 / 临时调班，但必须标成“计划”，不进入真实记录统计。

### 周视图

- 一次展示 7 个日列，支持前后周切换；横向空间不足时缩短星期标签，不横向滚动整张表。
- 每天使用分段条表示正常工作、加班、班中休息和清醒自由时间；观察只作小标记，不进入聚合。
- 点按某天后在图下展示同一套日期详情，编辑仍用同一个 sheet。
- 周视图对免费用户开放，仍遵守滚动 7 日窗口；切换到更早周不会扩窗，窗口外日期继续显示锁定占位。

### 年视图

- 年视图不是 365 个可点日期；它使用响应式点阵 / 密度块呈现全年工作节奏，主交互单位是月份或连续区间。
- 点按某块后展示该区间的开始、结束、工作日、工作时长、加班和自由时间；不提供精准到日的编辑入口。
- 底层仍按日聚合，显示层再映射成响应式桶；换设备只改变桶数和排布，不改变年度汇总。
- 可通过月份辅助列表或 VoiceOver 元素选择月份，不能把 8pt 小点暴露成数百个不可用的辅助功能焦点。

### 人生视图

- 右边界永远是用户填写的退休日期；未填写退休日期时，显示已知阶段和“设置退休日期”提示，不猜寿命。
- 阶段最小集合：出生到首次入学、学习、工作、退休边界；缺少任一日期时以“未设置”中性色连接已知区间。
- 点阵是“人生比例概览”：根据当前可用宽高计算列数、行数和桶数，再把出生到退休的时间轴等比例映射到桶。禁止一年固定一列 / 一行，也禁止把一格宣称为固定一年或一周。
- 阶段区间整体可点。Canvas 根据点击位置反算桶和阶段；同一阶段的所有色块都命中同一阶段详情，不要求用户精准点中某一颗小点。
- 阶段详情展示：用户输入口径下的开始 / 结束、历时年数与天数、占出生至退休区间的比例、日期精度（“按年份估算”或“精确日期”）以及数据来源。
- iPhone 使用 sheet，iPad 使用锚定 popover。图例是辅助入口而非主入口；色觉辅助、VoiceOver 和阶段过短不足 44pt 时，图例仍提供可达的阶段按钮。
- 已经历阶段使用实色；当前阶段用静态双描边；未来推演使用同色低透明度加纹理；未设置使用中性填充。不要使用循环呼吸动画。
- UI 交互强调色仍只有 DoneAt 橙色；人生阶段的分类色仅用于数据可视化，不扩散到按钮、链接或导航。

### 展开模式

- 只有年与人生尺度提供“展开 / 收起”，命中区至少 44pt；周与月不提供展开入口。
- 展开是记录页内部状态，不创建新 route：隐藏导航栏、Tab Bar、尺度选择、标题、总结、月份辅助选择与人生阶段图例，只保留画布和 44pt 收起入口，让图表占满安全区。
- 状态仅在当前会话保持；可以按尺度分别记住，App 重启统一恢复未展开。
- 横竖屏与 iPad 分栏都要重新计算点阵，不缓存旧设备的桶数。

## 免费预览与 Plus 权益

### 权益矩阵

| 能力 | 免费 | Plus / 试用 |
| --- | --- | --- |
| 本地持续写下真实计时记录 | 是 | 是 |
| 月视图 | 仅今天及之前 6 天 | 全历史 |
| 周尺度 | 仅今天及之前 6 天 | 全历史 |
| 年 / 人生尺度 | 锁定预览 | 完整 |
| 周期四项总结与占比条 | 锁定预览 | 完整 |
| 日期详情 | 仅滚动 7 日窗口，只读 | 全历史 |
| 日期编辑 | 否 | 周 / 月支持；年 / 人生不支持 |
| 全部记录层级列表 | 可进入；窗口外内容锁定 | 完整 |
| 完整 JSON 导入 / 导出 | 是 | 是 |
| 清除本机 / iCloud 数据 | 是 | 是 |
| 同步冲突处理 | 是，这是数据安全能力 | 是 |
| 配置人生档案 | 是 | 是 |
| 查看人生图 | 锁定 | 是 |
| 开启 iCloud 同步 | 沿用 006：需要权益 | 是；已开启后到期不强制关闭 |

### 滚动 7 日窗口

- 免费窗口严格定义为记录时区内 `[今天 - 6 天, 今天]`，不是自然周，也不会随用户点选而移动。
- 跨月时，两个相关月份都只解锁落在窗口内的日期；切到历史月份不会获得另一组 7 天。
- 免费用户可以继续产生记录，但不能从记录页编辑任何一天。导入是数据迁移权利，不等同于逐日编辑；导入前必须预览影响范围。
- 今天和未来的排班、请假、补班等计时运营输入继续在计时 / 排班设置链路按既有免费规则工作；“记录页不可编辑”不得误伤倒计时本体。

### 锁定视觉

- 锁定日期用不含真实值的专用占位层；总结卡同样只渲染固定骨架、`lock.fill` SF Symbol 和一条温和的 Plus 引导。
- 不使用 emoji 锁作为导航图标，不把玻璃效果铺到正常卡片。毛玻璃只服务“内容在这里但未解锁”的语义。
- 开启“降低透明度”时改为不透明次级背景和描边；“增强对比度”时提高边界与文字对比。
- VoiceOver 文案只说“此日期需要 Plus 才能查看”，不得读出被锁的工时、日期详情或汇总。
- 从锁定区域完成购买后，付费页关闭回到原尺度、原日期，原地解锁并重新计算，不跳回 Tab 根。

## 总结与时间占比

每个尺度只突出四项主指标：

1. 周期内工作日数。
2. 周期内正常工作总时长。
3. 周期内加班总时长。
4. 周期内清醒自由时间。

四项指标下方是一条 100% 堆叠横线图，分类固定为：正常工作、加班、班中休息、睡眠、其余清醒自由时间、无法分类。正常工作不含加班，避免重复；主指标“清醒自由时间”是“班中休息 + 其余清醒自由时间”的合计。

- 点按横线任一色段，显示时长和周期占比；色段的可点击区域扩到整条高度，不能只让 4pt 色条接收触摸。
- 工作日数按班次锚点日计数；时间占比按绝对时间与日历日窗口求交，二者是不同但明确的口径。
- 没有睡眠数据时，用人生档案的平均睡眠时长估算并标注“按设置估算”；有 HealthKit 数据时标“来自健康”。
- 睡眠、工作或结束时间不完整时，不硬凑 100%；缺口进入“无法分类”，并在详情给出可操作说明。

## 跨夜班、夏令时与自由时间算法

跨夜班可以计算，难点不在减法，而在“班次属于哪天”和“时间实际落在哪天”是两个坐标系。本计划统一如下：

1. 编辑、工作日计数和记录身份继续使用班次锚点日，遵守 002 的跨夜班规则。
2. 时间占比按记录时区中的真实日历日窗口计算。20:00–次日 04:00 的工作片段在两个日历日各占 4 小时，不把次日凌晨错误算成整天休息。
3. 使用共享规则给出的有效 `segments`，不能退回 `end - start`；午休等 gap 不算正常工作。
4. 加班先从工作并集中切出，正常工作与加班互斥。
5. 睡眠样本先做区间并集，避免 Apple Watch、iPhone 或多个来源的重叠样本被重复相加；睡眠与工作重叠时工作优先，重叠部分进入数据质量提示，不得相减两次。
6. 自由时间是日历日窗口减去工作并集和睡眠并集后的剩余；休息日没有工作片段，因此只扣睡眠。
7. 普通日期窗口是 24 小时；夏令时切换日按真实 23 / 25 小时作为分母，否则百分比无法真实合计 100%。UI 不必教育用户夏令时细节，但单元测试必须覆盖。
8. 时区迁移只通过“设置 → 记录与数据 → 记录时区”执行；旅行不会静默重算旧记录。

## 人生档案 v2

### 部分日期

每一个人生日期都可独立选择“只记年份”或“精确日期”，而不是一个全局精度开关：

```swift
enum CivilDatePrecision: String, Codable, Sendable {
    case year
    case day
}

struct PartialCivilDate: Codable, Equatable, Sendable {
    var year: Int
    var month: Int?
    var day: Int?
    var precision: CivilDatePrecision
}
```

- `.year` 不保存伪造的 1 月 1 日；展示永远只显示年份并带“约”。计算时使用该年中点作为稳定锚点，阶段详情必须声明“按年份估算”。
- `.day` 必须同时有合法 month / day，按记录档案时区解释，不使用 UTC 日期字符串制造偏移。
- 日期顺序校验：出生 ≤ 入学 ≤ 首次工作 ≤ 退休。字段缺失时只校验相邻已知值，不阻止保存部分档案。

### 模型

```swift
struct LifeProfileV2: Equatable, Sendable {
    static let schemaVersion = 2
    static let profileID = LifeProfile.profileID

    var bornOn: PartialCivilDate?
    var schoolStartedOn: PartialCivilDate?
    var workStartedOn: PartialCivilDate?
    var retirementOn: PartialCivilDate?
    var averageSleepMinutes: Int?
    var sleepSource: SleepSource       // manual / healthSuggested
    var sleepSourceUpdatedAt: Date?
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID
}
```

- 首次完成档案时平均睡眠为必填；四个日期仍可跳过。
- 旧 `birthYear` 迁到 `.year`；旧 `workStartedOn` 迁到 `.day`；`birthYear + retirementAge` 迁成 `.year` 的退休日期；旧 `hidesExactAges` 废弃，不再保留一个与输入精度重复的隐藏开关。
- 人生阶段、点阵桶、阶段天数与占比都是派生值，不进 JSON、SwiftData 或 CloudKit。
- 人生档案仍使用固定 recordName `profile`；CKSyncEngine 继续按字段三方合并，新字段必须进入 baseline 比较和 fixtures。

### 可选 HealthKit 睡眠

HealthKit 是增强能力，不阻塞本轮主 UI 上线：

1. 人生档案表单先允许用户手填平均睡眠，再提供“从健康建议”按钮；只有用户主动点击时请求 `.sleepAnalysis` 只读权限。
2. 查询最近 30 个有数据的夜晚，把 `.asleep*` 样本按绝对时间做并集，给出“近 30 夜平均 X 小时”的建议；用户确认后才写入 `averageSleepMinutes`。
3. 日 / 周 / 月精确统计可以在本机使用获授权的逐日睡眠并集；没有样本、仅授权有限窗口或不可用时回退到档案平均值。
4. 原始睡眠样本和逐日 HealthKit 派生缓存不进入 CloudKit、JSON 导出或 App Group；CloudKit 只同步用户确认过的平均分钟数及来源类型。
5. HealthKit 为保护隐私不会可靠告诉应用“用户拒绝读取”还是“没有可见样本”，UI 统一写“暂未获取到可用的睡眠数据”，不能指责用户没有授权。
6. 不同设备获得的 HealthKit 授权和可见样本可能不同，因此逐日精确睡眠与基于它的本机统计允许不同；UI 必须标明“此设备的健康数据”。没有健康数据的设备使用已同步的平均睡眠，不把差异误报成 CloudKit 冲突。
7. 增加 HealthKit capability、`NSHealthShareUsageDescription` 和隐私页说明前必须单独过 App Store 隐私审查；若该审查未完成，首版只发手填睡眠。

参考实现边界：[Apple HealthKit 数据类型](https://developer.apple.com/documentation/healthkit/data-types)、[睡眠分析类型](https://developer.apple.com/documentation/HealthKit/HKCategoryTypeIdentifier/sleepAnalysis)、[HealthKit 授权](https://developer.apple.com/documentation/HealthKit/authorizing-access-to-health-data)。

## 响应式点阵算法

### 几何

- 用 `GeometryReader` / `Layout` 获得主可视化实际尺寸；目标点边长、间距和最小行列数由设计 token 控制，不读取设备型号写分支。
- `columns = floor((availableWidth + gap) / (targetCell + gap))`，`rows` 由可用高度和展开状态决定，`bucketCount = columns × rows`。
- 年视图把该自然年的绝对区间等分为 `bucketCount` 个桶；人生视图把出生到退休的区间等分。每个桶保存开始、结束和分类占比，视觉选择主分类，详情读完整聚合。
- 屏幕旋转或分栏改变时重新采样，但四项总结和阶段详情只读底层聚合，不随桶数变化。
- 使用 SwiftUI `Canvas` 一次绘制点阵，避免为数百 / 数千个点创建独立 `View`；点击位置在 Canvas 坐标中反算桶索引。

### 命中与辅助功能

- 视觉上小点可以小于 44pt，但交互对象不是单点。人生按阶段合并，年按月份 / 连续区间合并；每个可交互语义对象提供至少 44pt 的命中代理。
- VoiceOver 暴露“学生阶段，约 12 年，占 18%”这样的阶段元素，不暴露每颗点。
- 开启“无需颜色区分”时，阶段同时使用纹理、描边和文字图例；不能只换一组更鲜艳的颜色。

## 全部记录列表

- 右上角进入后使用折叠层级：年份 → 月份 → 当月日期，不再把所有天平铺成无限长列表。
- 年行显示年份和该年记录天数；月行显示月份和四项汇总。免费用户在 7 日窗口外只显示锁定占位，不泄漏聚合值。
- 进入月份后才加载当月日期；大数据量使用懒加载列表和稳定 id，不一次展开十年数据。
- 日期行展示记录 / 未记录、正常工作、加班和用户修正标记；点按进入只读详情，Plus 用户可从详情打开同一编辑 sheet。
- 提供原生搜索 / 跳转：按年份和月份定位，不做任意全文搜索；选择器使用应用 locale 的日期格式。
- CloudKit 冲突日期在年、月、日三层都有克制的警示标记，点击进入冲突处理，不把冲突埋在日期编辑页底部。

## 记录与数据设置

新增 `SettingsSection.recordsData`，在设置首页显示一行“记录与数据”，进入独立设置子页。现有“排班”中的记录时区和“Plus”中的 iCloud 行迁入这里，避免同一领域散落三处。

### 普通区

1. 人生档案：显示完成度或“未设置”。
2. iCloud 同步与冲突：显示关闭、同步中、已同步或“有 N 项待处理”。
3. 记录时区：显示当前固定时区。
4. 导入完整数据：系统文件选择器，解析后先展示新增、相同、冲突、被擦除跳过的数量，再确认。
5. 导出完整数据：提供“完整备份”和“不含人生档案”的精简备份；两者都不含薪资和原始 HealthKit 数据。

### 危险区

- 清除此设备记录。
- 从 iCloud 与所有设备删除。
- 关闭同步但保留本机数据。

确认顺序固定为：解释影响 → 用户点破坏性确认 → 若生物识别保护已开启则调用设备所有者认证 → 执行 → 成功 / 失败触感与可读结果。认证失败或取消时不能改变任何本地、outbox、fence 或云端状态。

设备所有者认证使用 `LAPolicy.deviceOwnerAuthentication`，允许生物识别优先、设备密码回退；应用永远拿不到生物特征数据。参考 [Apple Local Authentication](https://developer.apple.com/documentation/localauthentication) 与 [`deviceOwnerAuthentication`](https://developer.apple.com/documentation/LocalAuthentication/LAPolicy/deviceOwnerAuthentication)。

## JSON 导入导出

- schema 升级到兼容 LifeProfile v2 的下一版本；解码器继续接受 v1，导出只写新版本。
- 完整导出包含真实记录、覆盖、例外、职业阶段、排班快照、人生档案、专注任务 / 会话和必要同步无关元数据；仍不含薪资、设备名、HealthKit 样本与派生点阵。
- 精简导出只排除人生档案及其来源字段，其余记录完整保留。
- 免费与到期用户均可全量导入导出，即使 UI 只展示最近 7 日。
- 导入永不静默覆盖：预览后提供“仅新增”“逐项处理冲突”；整库覆盖只用于明确的恢复流程，并进入认证门。
- 已擦除身份继续遵守 002 的 ErasedID 规则，不能因为新 UI 把旧删除记录复活。

## CloudKit 冲突体验

现有 `SyncConflictCopy` 只保存落败 payload，日期编辑页只能提供粗粒度找回。新设计分两层处理。

### 首次开启 / 恢复同步时的整库分歧

如果本机和 iCloud 都有非空数据：

1. 先比较实体身份与内容，不以文件时间决定胜负。
2. 默认推荐“合并并逐项检查冲突”。
3. 另提供“使用 iCloud 数据替换本机”和“使用本机数据覆盖 iCloud”；两者都必须展示实体数量、受影响日期范围、最后编辑时间，经过破坏性确认和设备所有者认证。
4. 覆盖过程中断不得留下半套数据库；沿用 generation / outbox / CKSyncEngine 状态机恢复，不新增墙钟排序。

### 单条并发冲突

- 冲突中心按年 → 月 → 日期分组；人生档案冲突单独归在“人生档案”。
- 每个冲突展示本机值、iCloud 值、双方最后用户编辑时间和逐字段差异；允许“保留本机”“保留 iCloud”或按字段合并。
- 选择结果是一笔新的本地编辑，`editCount = max(local, cloud) + 1`，重新生成 `editTieBreaker` 并入 outbox；不能直接改写系统字段。
- 冲突未处理时保留两份 payload，不阻塞无关记录继续同步；主 UI 使用当前确定性赢家，并显示“有另一版本待处理”。
- CloudKit 的 `serverRecordChanged` 提供客户端、服务器与祖先版本，仍以三方合并为基础。参考 [Apple `serverRecordChanged`](https://developer.apple.com/documentation/cloudkit/ckerror/serverrecordchanged)。

### “来自哪台设备”

CloudKit 不天然提供产生某条业务编辑的具体设备名。为了不新增可追踪设备标识：

- 本机显示“本机（iPhone / iPad / Mac）”。
- 远端显示“iCloud 版本”，可附 `editorPlatformFamily = iPhone / iPad / Mac`，但不保存 `UIDevice.name`、用户自定义设备名、稳定设备 UUID 或硬件型号。
- 必须显示业务 `editedAt` 和冲突检测时间；墙钟只供用户判断，不参与胜负。
- 如果平台类别也不可得，诚实显示“另一台 Apple 设备”，不伪造具体设备。

## 专注入口迁移

- 从 `RecordsRoute.focus` 和记录首页移除专注入口。
- 计时页导航栏左上角增加 `plus` SF Symbol，accessibility label 为“添加待办”，不是只有一个无解释的“+”。
- 点击只负责添加待办，打开单屏 sheet：标题必填；开始方式为“立即开始”或“安排时间”。
- 安排时间只能选择当前 / 下一有效班次的工作 `segments`，不能落在午休 gap、已结束班次或无效本地时间；跨夜班的次日凌晨片段仍属于该班次，可以选择。
- 保存“立即开始”时创建任务并进入现有单 Focus session；保存“安排时间”只创建任务，不自动启动后台计时。
- 非 Plus 用户点击入口时在原计时页上呈现付费页，购买后返回并继续未完成的添加动作。

## 视觉语言

### 版式

- 沿用 DoneAt 的 system grouped background、实色 group card、22pt 卡片圆角、14pt 控件圆角和橙色交互强调；不把人生点阵的分类色扩散到导航。
- 月历与点阵是页面唯一高密度区域，周围卡片减少描边与阴影，让视觉重心在时间图上。
- 数字使用等宽数字；日期、时长、百分比走应用 locale，不依赖系统语言偷换格式。
- 阶段详情与总结避免大段解释常驻；口径说明放在信息按钮或详情 footnote。

### 阶段颜色

- 至少提供童年、学习、工作、退休 / 未来、未设置五个经过浅色 / 深色对比验证的数据色 token。
- 已经历 / 未来的区别优先使用明度和纹理，不只依靠降低到难以辨认的透明度。
- 工作不使用警告红；红色只保留给错误和破坏性动作。
- 对比验收以小点真实尺寸测试，不能只在大色板上测通过。

### 拉丁长文案与 RTL

- 所有 19 个 UI locale 一次性补齐；不得先复制英文到其它 locale。
- 至少对 en、de、fr、es、pt、ru、tr、vi 做 2× 长标签伪本地化，对 ar 做 RTL 和数字 / 时间范围隔离测试。
- 月份、年份、阶段名称允许两行；导航栏按钮只使用 SF Symbol + accessibility label，避免把长动词塞入窄栏。
- 分段选择器不能使用 `minimumScaleFactor` 把文字缩到不可读；放不下就降级原生 Menu。
- Dynamic Type XL 与辅助功能字号下，日期详情和总结改为单列；四指标不能硬锁 2×2 导致截断。

## 动效、按压与触感

| 动作 | 视觉 | 触感 |
| --- | --- | --- |
| 切换尺度 | 约 200–220ms 的轻微交叉淡化与内容尺度衔接；数据数字不滚动乱跳 | 一次 selection |
| 双指缩放切档 | 画布跟手，越界有阻尼，释放按速度投影到最近档位；可中断 | 只在跨过档位时一次 selection |
| 选择日期 / 月份 / 阶段 | cell 高亮或静态描边，100–150ms | 一次 selection |
| 打开编辑 / 阶段详情 | 系统 sheet 动画，不自制转场 | sheet 落定由系统处理，不额外叠加 |
| 保存成功 | 内容原地更新，短淡入 | success |
| 普通按钮 / 卡片 | press-in 0.97；列表行使用背景高亮，不缩放整行 | 无或 light，按语义决定 |
| 删除确认 | 系统 dialog | 确认执行时 warning / medium，成功后 success；不能一击两次 |

- 任何触感都与视觉状态改变同帧，一次操作最多一次主要触感。
- 不在滚动、页面自动出现、循环“当前阶段呼吸”或每颗点上发触感。
- Reduce Motion 下自定义缩放改成交叉淡化；系统 push、sheet 和 picker 保持系统行为。
- Reduce Transparency 下玻璃锁定层改为实色。
- 点阵和图表动画只动 `opacity` / `transform`，不逐帧重排数百个 SwiftUI 子 View。

## 数据与迁移

### 停止虚构历史

当前 `RecordCoordinator.ensureSeeded` 会把首个 CareerPeriod 从 2000-01-01 开始，这是本计划必须移除的旧行为。

- 新增记录功能元数据 `recordsStartedOn`：新安装以第一次真实记录事件或第一次打开记录 Tab 的较早者为起点。
- 新 CareerPeriod / ScheduleSnapshot 只从真实生效日期开始，不为 `recordsStartedOn` 之前生成逐日底图。
- 现有 archive 中若发现“2000-01-01、无 label、由旧自动 seed 创建且没有用户历史配置”的默认 period，把起点迁到以下最早值：真实 observation、DayOverride、CalendarException、用户导入记录、或升级日；保留所有真实实体，不删除用户内容。
- 无法证明是自动 seed 的 period 不自动改写，进入迁移报告 / 测试 fixture，由用户数据优先。
- 人生档案可以描述首次工作以前和记录功能启用以前的人生阶段，但这些只服务人生图，不进入真实日历记录。

### 缓存

- DailyWorkSummary、年桶、人生桶均可重建；schema 变化后直接失效重算，不同步。
- 月 / 周优先按可见区间加载；人生与十年聚合在后台计算，主 actor 只接收完成模型。
- 共享 `CountdownRules.js` 仍是 schedule segments 的唯一规则来源；如果批量接口缺字段，应扩展 TS 生成桥，不在 Swift 复制排班算法。

## 实施顺序

### Phase 0 — 契约对齐

- 同步修订 002、006：权益、首次历史、LifeProfile v2、专注入口和设置 IA 与本计划一致。
- 写迁移 fixtures 与 entitlement matrix 测试后再改 UI，先锁住“哪些数据是真实、哪些只是人生推演”。
- 明确旧 PR / 分支上哪些 UI 变更保留，避免重写 CloudKit 基础设施。

### Phase 1 — 数据模型与迁移

- 新增 `PartialCivilDate`、LifeProfile v2、`recordsStartedOn`、JSON 新 schema 和 v1 → v2 迁移。
- 移除 2000 年自动 seed；补既有自动 period 的保守迁移。
- 扩展 CloudKit profile payload、三方字段合并、lastKnown baseline 和差分 fixtures。
- 落地自由时间的日历日求交算法与跨夜 / DST 单元测试。

### Phase 2 — 信息架构

- 重写 `RecordsDesignView` 为单画布；增加尺度状态、默认月视图、右上角全部记录。
- 新增“记录与数据”设置 section / route，迁移时区和 iCloud 行，移动导入导出与危险区。
- 从记录 routes 移除 Focus，计时页增加“添加待办” sheet。

### Phase 3 — 月 / 周 / 日期编辑

- 月历、滚动 7 日权限、未记录状态、图下日期详情。
- 周视图与统一日期选择模型。
- 把 `RecordDayEditView` 从 push 改为 sheet，保留原始字段编辑和未保存确认。
- 四指标与 100% 堆叠条，完成普通、空、缺失、错误、锁定状态。

### Phase 4 — 年 / 人生响应式点阵

- 使用 Canvas 实现响应式桶、点击反算和阶段整体命中。
- 人生阶段详情 sheet / popover、颜色与纹理 token、辅助功能代理。
- 展开模式、旋转 / iPad 重排、Reduce Motion / Transparency。

### Phase 5 — 权益与购买回流

- 锁定专用 view model，确保真实值不进入锁定视图树和 accessibility tree。
- 购买完成原地解锁，保持尺度、日期和滚动状态。
- 更新 Paywall benefit、19 locale 和 006 验收场景。

### Phase 6 — 冲突中心与安全操作

- 扩展冲突副本结构，保存本机 / 云端 / baseline、逐字段差异、平台类别和状态。
- 实现整库分歧预检、逐日冲突列表、手动合并和新编辑回写。
- 导入预览、完整 / 精简导出、确认 → 认证 → 执行的统一安全流水线。

### Phase 7 — HealthKit（可独立延期）

- 能力、授权文案、30 夜平均建议、逐日睡眠本地聚合和回退。
- 隐私页、App Store 标签与真机授权验证未完成时，不阻塞手填睡眠版本发出。

### Phase 8 — 真机与本地化验收

- 逐设备、主题、字号、语言、旋转、离线、购买、冲突和认证完整走查。
- 录制完整交互视频，正常速度和逐帧各看一遍；release 构建测 60fps，不能只看静态截图。

## 主要文件落点

| 范围 | 现有 / 建议文件 |
| --- | --- |
| 记录根与尺度容器 | `Native/Views/RecordsDesignView.swift`，建议拆 `RecordsScaleContainer.swift` |
| 月 / 周 / 年 | `Native/Views/RecordsChartViews.swift`，建议拆 `RecordsMonthView.swift`、`RecordsWeekView.swift`、`RecordsYearGridView.swift` |
| 日期编辑 | `Native/Views/RecordDayEditView.swift` |
| 人生图 | `Native/Views/LifeView.swift`、`Native/Models/LifeViewCalculator.swift` |
| 人生模型 / JSON | `Native/Models/LifeProfile.swift`、`Native/Models/RecordJSON.swift` |
| 记录生命周期 / 迁移 | `Native/Models/RecordCoordinator.swift`、`Native/Models/OffWorkStore.swift` |
| 自由时间聚合 | 新建纯模型 `Native/Models/TimeAllocationCalculator.swift`，输入必须是共享规则 segments |
| CloudKit | `Native/Models/RecordsCloudSync.swift`、`RecordsSyncAdapter.swift`，建议新增 `RecordsConflictCenter.swift` |
| 设置 | `SettingsSection.swift`、`SettingsSectionCard.swift`、`AppRouteDestination.swift`、`SettingsDetailDesignViews.swift`、`RecordsSyncSettingsView.swift` |
| 专注入口 | `TimerView.swift` / 计时设计页、`FocusModels.swift`、`FocusPlanner.swift` |
| 权益 | `PlusEntitlement.swift`、`PaywallView.swift` |
| 设计 token | `Native/DesignSystem/OWCDesignSystem.swift`，新增图表分类 token，不新增第二套 UI accent |
| 本地化 | `public/locales/*/translation.json` 与 `lib/locales.test.ts` |
| 测试 | `AppTests/OffWorkStoreTests.swift`、Records / Life / Cloud 新测试文件、UI test / screenshot fixture |

## 验收清单

### 信息架构

- [ ] 记录首页不再出现五行大入口；首屏是月历。
- [ ] 四个尺度在同一画布切换，返回栈不因切尺度增长。
- [ ] 导入、导出、清除、时区、iCloud 和人生档案全部位于“记录与数据”。
- [ ] 全部记录从记录页右上角进入，按年 → 月 → 日期懒加载。
- [ ] 专注只从计时页“添加待办”进入，记录页无残留 Focus 入口。

### 数据诚实性

- [ ] 全新安装首次进记录不会出现过去数年的伪记录。
- [ ] 人生设置不会生成任何逐日历史实体或 CloudKit 日记录。
- [ ] 未记录、真实记录、计划、推演和用户修正有不同文案与视觉。
- [ ] 年 / 人生换设备后点数可变，但阶段日期、天数、百分比和四项总结完全一致。
- [ ] 右边界只到退休，不出现寿命、死亡或“剩余人生”文案。

### 免费与付费

- [ ] 免费窗口永远只有记录时区中的今天及之前 6 天，切月份无法扩窗。
- [ ] 免费用户不能从记录页编辑任何日期，但计时 / 排班本体不受影响。
- [ ] 免费用户可以完整导入、导出、删除和处理同步冲突。
- [ ] 锁定视图树、VoiceOver 和日志中都没有真实锁后数值。
- [ ] 购买完成回到原画布原位置并立即解锁。

### 日期与计算

- [ ] 日班、跨夜班、午休 gap、多 segment、加班、休息日、缺结束时间全部有单元测试。
- [ ] 20:00–04:00 在两个日历日各计入实际落点时长，工作日仍按班次锚点计一次。
- [ ] 23 / 25 小时夏令时日的占比合计为 100%，没有负自由时间。
- [ ] 睡眠重叠样本先合并；睡眠与工作冲突不会双扣。
- [ ] 正常工作不含加班；主自由时间等于班中休息加其余清醒自由时间。

### 人生档案

- [ ] 出生、入学、首次工作、退休均可为空、仅年份或精确日期。
- [ ] 旧 birthYear / retirementAge / workStartedOn 无损迁移，旧 JSON 可导入。
- [ ] 年份精度不伪装成 1 月 1 日，详情明确“按年份估算”。
- [ ] 人生档案 CloudKit 冲突可逐字段合并。
- [ ] 编辑人生档案在已启用保护时需要设备所有者认证。

### 同步与导入

- [ ] 本机和 iCloud 都非空时先预检，不静默整库覆盖。
- [ ] 冲突页显示本机 / iCloud、编辑时间和逐字段差异，不显示用户设备名或稳定设备 id。
- [ ] 单个冲突的选择写成新的 editCount，不靠墙钟获胜。
- [ ] 冲突未处理不阻塞无关记录同步，两份 payload 都不会丢。
- [ ] 覆盖式导入、清除与云覆盖均为确认后认证；取消认证零副作用。

### UI 与无障碍

- [ ] iPhone SE 级别、最新 Pro、iPad 和 Apple Silicon Mac 窗口均无截断或不可达控件。
- [ ] 浅色、深色、Reduce Motion、Reduce Transparency、Increase Contrast、Differentiate Without Color 全部验收。
- [ ] Dynamic Type XL 和辅助功能字号不遮挡月历、总结、sheet 按钮。
- [ ] 19 locale 齐全；德 / 法 / 西 / 葡 / 俄 / 土 / 越长文案和阿拉伯 RTL 实机检查。
- [ ] 所有交互语义对象至少 44pt；Canvas 小点不作为独立小触控目标。
- [ ] 分类颜色在浅 / 深主题的小点真实尺寸下仍可区分，并有纹理 / 文字第二通道。

### 性能与构建

- [ ] 月 / 周切换和展开无主线程长停顿；Canvas 不为每个桶创建独立 SwiftUI View。
- [ ] 十年记录、出生到退休人生图和 10,000 条导入 fixture 有性能测试。
- [ ] release 构建完整流程录屏，主路径持续 60fps，无一帧错误主题、跳版或重复 sheet。
- [ ] `npm run build:ios-native-rules`、`npm run check:ios`、相关 Swift Tests 和 iPhone 模拟器 build 全部通过。
- [ ] 若改到共享 `lib/`，额外通过 `npm test` 并重新生成 iOS rules bundle。

## 完成定义

本计划完成不是“把五个按钮换成 segmented control”。完成必须同时满足：首次进入没有伪历史；月历成为默认工作面；周 / 月能选日并用 sheet 编辑；年 / 人生在不滚动的大画布中保持可读；人生阶段整片可点；四项总结与占比口径能解释跨夜班；免费 7 日预览既不泄漏又不阻塞导出；记录数据设置集中；CloudKit 冲突可以看见并逐项决定；19 种语言、两种主题、辅助功能和真机动效都经过真实走查。

## 2026-08-31 审查与本轮迭代记录

### 已修正

- 人生档案：退休输入由“退休年份”改为“退休年龄”；界面输入年龄，模型继续保存 `retirementAge`，并用出生年份推导 `retirementOn` 供人生边界、拟规划和 CloudKit 同步使用，旧档案按退休年份与出生年份之差无损回显。
- 免费权益：周、月尺度开放；逐日数据仍只揭示记录时区内 `[今天 - 6 天, 今天]`，年与人生继续由 Plus 解锁。19 个 locale 的 Plus 文案不再把周视图称为付费能力。
- 展开：月与周移除展开入口；年与人生展开时隐藏导航、Tab Bar、尺度选择、标题、月份按钮 / 阶段图例和总结，仅保留全屏画布与收起按钮。标准动效为 300ms 的 `0.23, 1, 0.32, 1` timing curve，Reduce Motion 使用 160ms 淡入淡出。
- 拟规划：月 / 年在人生档案同时有首次工作与退休边界时，复用生成的 TypeScript schedule range 和当前班次、午休、睡眠配置生成内存投影；真实观察与修正优先，投影使用低透明度和斜线纹理，并明确标记“按当前人生设置推算”。投影不写入 Records 或 CloudKit。
- Records 生命周期：浏览旧月份不再把 durable career period 的起点回填到旧日期；首次播种以当前时刻为准。
- Paywall：进入即加载商品，三种方案始终以一行一个方案展示；功能列表使用现有 SF Symbols；欢迎页到 Paywall 使用一次性底部进入动效；Reduce Motion 使用淡入。
- Focus：任务保存具体 slot 开始时刻；计划任务和活动 Pomodoro 进入“接下来”；计时页提供独立 Focus 入口；保存后进入任务页；旧 JSON / CloudKit payload 因新字段可选而保持兼容。
- CloudKit：数据 zone 通过 `CKSyncEngine.PendingDatabaseChange.saveZone` 建立，移除首批记录与 fire-and-forget zone save 的竞态；`zoneNotFound` 会重新排队 zone 和记录；普通批次最多 250 条，墓碑保存与原记录删除使用独立原子批次。
- StoreKit：月付、年付、买断 ID 与 `DoneAt.storekit` 一致；同一订阅组返回多条历史状态时，按有效状态与到期时间确定性选择，不再依赖异步返回顺序；新增运行时三商品加载测试。

### 本轮验证

- `npm run check:ios`：通过。
- `npm run build:ios-native-rules`：通过。
- iOS 26.5 `OWC iOS 26 QA` 模拟器：完整 Swift Testing 套件 218 项通过；新增 StoreKit、投影、Focus、CloudKit 批次测试均实际执行通过。
- `npm test`：25 个测试文件、296 项通过；`npm run lint`、`npm run check:version` 通过。
- `npm run build` + `npm run check:build:web`、`npm run build:desktop` + `npm run check:build:desktop`：通过。
- 中文 Paywall 在 StoreKit Configuration 下真实显示月付 `$1.99`、年付 `$9.99`（7 日试用）、买断 `$24.99`，无需二次点击。
- 月视图以真实 iPhone 17 Pro 尺寸检查：投影纹理、记录 / 修正优先级、详情与 Tab Bar 安全区正常；年 / 人生全屏画布和 Focus 待办列表也完成模拟器截图验收。

### 发布前仍需外部状态验证

- CloudKit Development / Production schema 是否已在 CloudKit Dashboard 部署、Production 容器是否有 `Fence`、`RecordRow`、`ErasedID` 类型，以及真实 Apple Account 的双设备上传、冲突、删除、恢复，无法仅凭仓库与模拟器证明。
- App Store Connect 中三个商品是否处于可销售状态、协议税务是否有效、订阅组 Production ID 是否与配置一致，仍需 TestFlight sandbox purchase / restore / expire / grace / revoke 全流程。
- Phase 8 仍需 iPhone SE 级别、iPad、深色、RTL、辅助功能字号、Reduce Transparency 与真机 haptic / 60fps 录屏验收。
