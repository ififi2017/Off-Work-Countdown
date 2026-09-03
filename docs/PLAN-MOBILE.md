# Apple 移动端与 Watch 开发计划

本文记录 Off Work Countdown 在 iPhone、iPad 和 Apple Watch 上的现状、技术边界与后续顺序。
Android 暂时搁置，不进入当前排期。

生产 iOS App 已经是纯 SwiftUI 原生实现，位于 src-mobile/ios；不嵌入 WebView，也不使用
已经归档的 Capacitor spike。排班、提醒和汇总规则仍以 lib/countdown.ts、
lib/reminders.ts 和 lib/summary.ts 为唯一实现，由构建脚本生成 CountdownRules.js，
iPhone/iPad 通过 JavaScriptCore 消费结果。Swift 和未来的 watchOS 代码都不得复制这些规则。

产品继续坚持本地优先：不增加账号、分析 SDK 或自有服务器，不上传排班与薪资。任何跨设备
能力都必须明确写出同步范围、失败方式和隐私变化，不能把“Apple 平台自动同步”当成默认事实。

## 1. 当前进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| D0 | iOS 26、iPhone+iPad、全方向、通用购买与 bundle id | 🟢 已定案 |
| P0 | 共享排班、提醒和汇总规则，生成原生规则包 | 🟢 已完成 |
| P1 | Capacitor / Mobile Web 技术 spike | ⚪ 已完成并归档，不进入发布包 |
| P2 | SwiftUI 原生 App、JavaScriptCore 规则桥、本地状态 | 🟢 已完成 |
| P3 | 本地通知、午休/健康提醒、预约与重排 | 🟢 核心链路完成，继续随 TestFlight 回归 |
| P4 | iPhone/iPad Widget、锁屏与灵动岛 Live Activity | 🟡 进度时间线已重构，等待新一轮实机回归 |
| P5 | iPhone/iPad 自适应 UI、设置导航、分享与欢迎页 | 🟡 首轮 CR 修复完成，继续做真机交互回归 |
| P6 | Xcode Cloud、TestFlight、商店截图与审核材料 | 🟡 3.1.8 截图/Preview 已上传，官网隐私已切 doneat.app；正式送审仍待人工 |
| W0–W3 | Apple Watch App、同步与表盘组件 | 🔵 下一个主要目标 |
| X1 | iPhone 与 iPad 的可选跨设备同步 | ⚪ 技术决策保留，当前不实施 |
| A0 | Android 原生客户端 | ⏸ 暂时搁置 |

当前执行顺序是：

1. **[007](../plans/007-ios-stable-before-subscription.md)**：在记录（002）和订阅（006）之前，把 iOS 倒计时本体做成可过审的稳定版。main 现为 TestFlight；已送审包偏早，正式审核候选以 007 为准。计时页口径见 [IOS-TIMER-SURFACES.md](IOS-TIMER-SURFACES.md)；
2. 保持 iPhone/iPad TestFlight 回归与 App Store 提交链路稳定；
3. 开始 Apple Watch 的契约和 target 建设；
4. 完成 Watch App、圆形与长方形表盘组件、双向状态联动；
5. Watch 稳定后再评估 iPhone/iPad iCloud 同步（002 的 CloudKit 仍排在 007 之后）；
6. Android 不设启动日期。

## 2. 2026-08-23 iPhone / iPad 收口记录

### 2.1 原生界面与导航

- iPhone 竖屏使用系统 TabView；iPhone 横屏使用紧凑侧栏；iPad 使用可收起侧边栏和独立
  NavigationStack，支持横竖屏与多任务宽度变化。
- 设置二级页恢复系统左边缘返回手势，同时限制空内容页面无意义的上下滚动；薪资设置只有在
  内容确实超出一屏时才滚动。
- 修复 iPhone 横屏设置页初始布局位移、按钮难以触发、不可点击版本行仍显示箭头、内容不居中
  等问题。
- 修复 iPad Mini 侧边栏展开时 NavigationLink 找不到 AppRoute destination、选项无法点击、
  收起侧边栏后布局改变，以及计时/设置切换顶部闪动。
- iPhone 横屏和 iPad 的计时/设置切换、欢迎页翻页与详情页进退场动画已统一并经多轮实机反馈
  调整；最终动效仍以真机手感为准，不以模拟器截图代替。

### 2.2 排班、午休与提醒

- 默认上下班时间为 09:00–17:00、周一至周五；午休默认 12:00、60 分钟。欢迎页把午休打开；
  未完成欢迎页前 store 里仍是关。
- 固定星期、大小周、上几休几和关闭自动排班均由共享 TypeScript 规则判定。
- 上几休几支持“从第 N 天开始”；例如上二休二提供四个周期位置，前两天为工作日、后两天为
  休息日。
- 上班时间和下班时间使用独立语义图标；非工作日开始计时采用二次确认。
- 午休支持开始提醒与结束提醒。欢迎页「午休和提醒」一次配齐午休、下班提醒、健康提醒和
  灵动岛；本地通知权限只在继续时、且确实有提醒需要时才申请。灵动岛只写偏好。
- Live Activity 的中文 AOD 倒计时、本地化完成文案、Dynamic Island 间距和生命周期已修正。

### 2.3 欢迎页、隐私与内容

- 欢迎页统一翻页动画，并完整介绍固定星期、大小周、轮班轮休、离线使用、提醒、系统表面、
  横屏/侧栏和隐私。
- 欢迎页顺序为首页、班次设置、午休和提醒、排班预览、隐私、系统表面、横屏/侧边栏和品牌收尾；
  先不排班跳过排班预览。最后一页复用可触发彩蛋的交互式 DoneAt mark，以「开始体验」进入计时页。
- 隐私页说明本 App 不依赖自有网络服务，不上传排班和薪资数据。
- 关于页删除开发者区块和桌面端推广说明，保留 GitHub、官网、Mac/Windows 下载与版本信息。
- 主题页“跟随系统”使用字面 A，避免本地化 SF Symbol 在中文环境显示成“字”。

### 2.4 分享与商店交付

- iPad 和 iPhone 横屏分享页采用双栏布局，减少右侧空白，并保持图片与操作区域的视觉重心。
- 分享图继续保持 salary-free，不把薪资写入图片、链接或分享元数据。
- iOS 分享页的八个心情选项改为运行时由系统 Emoji 字体渲染，原生 target 不再打包 Mood PNG。
- 商店图流水线在 `scripts/marketing-shots/ios`：模拟器截原片，官方机框按官网
  DeviceHero 方式叠层（框定盒子、截图铺屏洞、框叠上面），再压成不带 alpha 的
  1320×2868 / 2064×2752。当前竖图三张：计时、主屏幕小组件、午休。不要挖空边框或
  重画灵动岛。只改文案或排版时重跑 compose，不必重跑 Xcode。
- 截图与 App Preview 只上传 `en-US`、`zh-Hans`、`zh-Hant`，其余商店语言继承英文。
  iPhone 槽位是 `APP_IPHONE_67`（没有 `APP_IPHONE_69`）。替换后要删掉旧的
  `APP_IPHONE_65` 等闲置槽，否则 Connect 界面会继续展示旧图。
- Preview 是 `IPHONE_67` 竖版 886×1920，必须带音轨（无声立体声即可）。同步见
  `docs/APP-STORE-CONNECT-SYNC.md`。
- Info.plist 已声明 ITSAppUsesNonExemptEncryption = NO。
- Xcode Cloud 的 ci_post_clone.sh 会安装所需 Node.js、执行 npm ci、生成当前规则包并运行
  npm run check:ios；Archive 使用 Release，TestFlight 不包含 DEBUG 欢迎页和 QA 入口。

### 2.5 数据持久化复验

- 欢迎页完成状态、上下班时间、排班、午休、薪资、主题和通知设置当前由 OffWorkStore 写入
  iOS 本地持久化域。
- 已检查语言刷新、Release 编译条件和启动路径，没有按语言或重启主动清空设置的逻辑。
- 最新实机复测未再出现切换语言或重启后设置全空、重新显示欢迎页的问题。
- 该问题仍加入长期回归：后续每个 TestFlight 候选包都要至少验证普通终止、强制退出、重启、
  系统语言变化和 App 专属语言变化。若再次出现，优先增加版本化原子快照和恢复机制，而不是
  依赖 synchronize 或掩盖成默认值。

### 2.6 2026-08-24 SwiftUI CR 与组件时间线

- 完成首次排班设置或手动启动过一次后，固定星期、大小周和上几休几会保持自动计时状态跨日运行；
  旧版本中被每日重置的既有配置会一次性迁移为已启用，用户显式停止后仍保持停止。
- iOS Widget 快照现在通过一次 JavaScriptCore 批量调用预投影约一年的绝对班次，Widget Extension
  每 12 小时从快照重建未来 36 小时的轻量展示条目。「接下来」列表写入同一份快照的后续班次，
  而不是只写生成后 36 小时，所以 App 长期不打开时大号 / 超大号仍有下一班的上班、午休和下班；
  休息日不投影当天的名义窗口。组件仍可在后续工作日自动从“距离上班”切到工作倒计时；排班、
  跨夜、轮班和午休判断仍全部来自 TypeScript 规则束。
- “好好休息”只覆盖下一工作日之前的完整休息日；进入下一班所属工作日的零点后切回普通上班前
  倒计时。当前班次结束后的“今日已下班”保留到结束日的日界线，但遇到同日下一场跨夜班时会
  提前让位，避免两个班次状态重叠。
- iOS Home Screen 与锁屏组件不再依靠组件视图中的 TimelineView 驱动进度。WidgetKit 现在会在
  工作区间内生成定期进度条目；系统 timer 继续显示秒级倒计时，进度环和线性进度则按受控粒度
  前进，避免出现倒计时正常而百分比永久停在旧值的问题。
- `countdownTargetAtMs` 在 working 相位是墙上的下班时刻（有加班则到加班结束），不是
  「剩余有效工时贴到墙上」。圆形复杂功能用 `.time` 读这个字段：09:00–19:00 加 90 分钟
  午休时中心应是 19:00，不能是 17:30。主屏倒计时仍用 `dateMs + remainingEffectiveMs`
  跳过午休，两个字段不能混用。
- 上述密集时间线只用于 iOS。macOS 组件继续使用班次边界条目，防止移动端修复改变桌面组件的
  唤醒频率和既有行为；共享 WidgetSnapshotContract 已增加投影与边界测试。
- iOS Home Screen 小组件左上角和锁屏长方形复杂功能、灵动岛 compact / minimal、锁屏 Live
  Activity 共用透明 `BrandMark`，不再套灰色圆角底板。欢迎页系统表面预览与此对齐。
- iOS 另开放 `systemLarge`、`systemExtraLarge`（iPad 横向双栏）以及 iOS 27 的
  `systemExtraLargePortrait`（4×6 竖向，主屏幕 / 今日视图，iPad 今日视图亦可）。多出来的
  面积接入计时页同一份「接下来」列表（salary-free 投影进 snapshot，覆盖快照有效期内的后续
  班次，而不是只写生成后 36 小时）。macOS 没有「接下来」，大号 / 超大号 / 竖向 XL 不开放。
- 设置导航统一为 NavigationLink(value:) 与单一 AppRoute destination 注册，避免不同
  NavigationStack / NavigationSplitView 列之间找不到目标，并保留系统左边缘返回交互。
- 通知设置页与根视图共享同一个 NotificationService；App 从系统设置返回前台后重新读取授权
  状态并立即重建日程，后台切换前不再额外等待可能被系统挂起的延迟任务。
- 首轮可访问性和性能修复已落地：开关使用真实语义标签、工作日提供选中状态、Reduce Motion
  使用淡入淡出、设置页停留时暂停被遮挡计时页的一秒刷新，并逐步采用 Dynamic Type 字体。
- iOS targets 切换到 Swift 6，并加入默认值与持久化单元测试 target。后续继续拆分体积过大的
  SwiftUI 文件、扩大 Dynamic Type 覆盖，并为通知失败状态补充面向用户的反馈。

### 2.7 2026-09-03 锁屏复杂功能停在加载占位

用户在 3.1.8 报告 iPhone 锁屏的圆形和矩形复杂功能会偶发停在系统的灰色占位上。灰色占位不是
组件画出来的任何一种状态——它意味着 Widget Extension 没有把渲染好的时间线交出去，通常是
渲染过程中超出内存被系统回收。整条产出路径里没有强制解包、没有 `fatalError`，扩展也不加载
规则束，所以排查落在预算而不是崩溃上。

一次 getTimeline 原本的开销：

- 每读一句文案就重新打开并解析一遍该语言约 45 KB、800 多个 key 的 `translation.json`，没有
  任何缓存。WidgetKit 会提前渲染时间线里的每一个条目，所以这份解析按条目计费。
- 一个进程服务所有已放置的 family，同一份约 574 KB 的快照被逐个 family 重复解码。
- 工作区间按 5 分钟展开、窗口 36 小时，普通 9:00–18:00 排班在早晨可以产生约 200 个条目。
- 约一千行的「接下来」列表挂在每一个条目上，而只有大号 / 超大号 / 竖向 XL 会显示它。

对应的收口：

- 翻译按语言解析一次并缓存在进程内；快照按文件修改时间与大小缓存解码结果，同一进程内多个
  family 只解码一次。两处都用锁而不是 actor，因为调用方全是同步的 `View` body。
- 展示粒度从 5 分钟改为 15 分钟：同一窗口的条目数从 198 降到 70，进度环每条前进约 3%，比
  58pt 圆环上肉眼能分辨的粒度还细。**窗口仍保持 36 小时**——WidgetKit 只被要求每 12 小时
  重建，但可能因刷新预算推迟，多出来的一天是防止推迟后复杂功能停在最后一个条目的余量。
  缩短窗口是省条目的错误做法，`boundsTimelineSizeForAWorkingDay` 同时守住这两侧。
- 「接下来」只投给真正会画它的三个 family；锁屏 accessory 的容器背景换成 `Color.clear`，
  原来的渐变加 38pt 模糊在 vibrant 渲染下会被系统丢弃，却每个条目合成一次。
- `getSnapshot` 不再构建整条时间线再取第一个条目。
- 快照读不到或已过期时的重载策略从 `.never` 改为 `.after(30 分钟)`。`.never` 会让组件停在
  「未开始」实态直到 App 下次运行——这是与灰色占位不同的另一种卡住。间隔取 30 分钟而不是
  5 分钟：真正的恢复都是推的（App 写完快照就调 `WidgetCenter.reloadTimelines`），这个间隔
  只需要兜住 App 再也不运行的情况；WidgetKit 每天只发数十次刷新，申请 288 次不会拿到更多，
  只会把额度花在注定再次失败的读上。
- 新增一行 `com.rainif.offworkcountdown.widget` 的 `Logger` 输出：family、快照字节数、快照
  条目数、时间线条目数、耗时和 `phys_footprint`。`phys_footprint` 正是系统判定回收时看的
  数字，Console.app 或 sysdiagnose 里可直接读，不需要接调试器。

真机未复现属于预期：条目数随时刻变化（早晨约是傍晚的两倍），锁屏放几个复杂功能、当时的
内存压力都会改变触发概率。

## 3. 当前架构边界

### 3.1 共享业务规则

- lib/countdown.ts：班次、有效 segments、计划结束、加班与下一班的唯一规则。
- lib/reminders.ts：里程碑、下班、午休边界和健康提醒绝对触发时间的唯一规则。
- lib/summary.ts：周/年汇总和计薪口径的唯一规则。
- scripts/build-ios-native-rules.mjs：生成 iOS 使用的 CountdownRules.js。
- Swift 只传入设置并渲染绝对结果，不重新实现“今天是否上班”“轮班第几天”或薪资计算。

未来 Watch 不直接运行另一份 Swift 排班算法。iPhone 负责把当前规则结果投影为可离线渲染的
WatchSnapshot；Watch 只根据绝对时间、segments 和过期时间显示状态。

### 3.2 数据分层

| 数据 | iPhone/iPad 主 App | iOS Widget / Live Activity | Apple Watch / 表盘组件 |
|---|---|---|---|
| 排班参数 | 本地完整保存 | 不直接读取，仅消费投影 | 只接收显示所需投影 |
| 当前班次与进度 | 本地规则计算 | salary-free snapshot | salary-free WatchSnapshot |
| 薪资 | 仅主 App 私有存储 | 禁止 | 默认禁止 |
| 通知设置 | 主 App 配置 | 主 App 负责预约 | Watch 只显示必要状态 |
| 主题/语言 | 本机设置 | 投影必要显示值 | 投影紧凑显示值 |

iOS App Group 只承担同一台设备上主 App 与 extension 之间的 salary-free 文件投影。
App Group 不能用于 iPhone 和 iPad 跨设备同步，也不能让 iPad 与 Apple Watch 建立配对通信。

### 3.3 发布与 CI

- App 与 Widget Extension 使用同一 App Store Connect 记录和通用购买 bundle id。
  名称、副标题和隐私 URL 是 App 级共享信息：一侧版本在审核时 App Info 锁定，
  `asc:sync` 会跳过这些字段；可编辑的 iOS 版本仍可换截图和 Preview。
- 当前发布路径是 Xcode Cloud 的 main 分支变更触发、Release Archive 和 TestFlight Internal
  Testing；不创建 ios-v tag 自动上传路径。
- Xcode Cloud 必须在编译前生成未提交的 CountdownRules.js。
- CURRENT_PROJECT_VERSION 由 Xcode Cloud 或发布流程递增；MARKETING_VERSION 与产品版本保持
  一致。
- npm run check:ios 必须随着 Watch targets 扩展，验证 bundle id、App Group、嵌入关系、
  Release 条件、支持 family 和 salary-free 契约。

## 4. 下一个目标：Apple Watch

### 4.1 产品定位

Apple Watch 是 iPhone App 的随身状态表面，不是第二套完整设置中心。用户抬腕时应能立即看到：

- 当前是工作、午休、休息、加班还是已下班；
- 距离下班还有多久；
- 当前班次进度；
- 计划下班时间；
- 数据是否过期或仍在等待 iPhone 同步。

Watch 首版不提供完整排班、午休、通知或薪资编辑。相关页面使用简短说明，引导用户回到
iPhone App 配置。这样能避免在小屏幕上复制复杂设置，也能保持 iPhone 是唯一设置权威端。

Watch App 可以分阶段实现，也可以在同一开发周期一次交付；即使一次开发完，仍按 W0–W3
的验收门分层，不能跳过同步契约和断网状态。

### 4.2 应用形态

采用“带 iPhone companion 的 watchOS App”，而不是 watch-only 产品。首版允许依赖已安装的
iPhone App，因为业务规则、设置入口和数据权威都在 iPhone。

不在首版宣称 Watch 可完全独立配置。若未来改为独立 watchOS App，WatchConnectivity 不能再是
唯一数据来源，届时必须另行决定 CloudKit/iCloud 或在 Watch 上提供完整的本地规则资源和配置
流程；这会显著扩大范围和隐私说明。

### 4.3 WatchSnapshotV1

新增版本化、salary-free 的 WatchSnapshotV1，至少包含：

- schemaVersion、revision、generatedAtMs、expiresAtMs；
- locale、显示状态与必要的本地化短文案；
- 当前绝对 segments、plannedEndAtMs、overtimeEndAtMs；
- 当前状态、下一次状态边界和下一班简要投影；
- 表盘组件渲染所需的进度、结束时间与保守空态；
- countdownStarted 和必要的控制状态，但不含薪资字段。

iPhone 每次修改班次、开始/停止计时、进入/退出午休、应用加班、切换语言或前后台恢复时更新
snapshot。Watch 收到后原子写入自己的本地文件，再通知 WidgetCenter 刷新 Watch 组件。

Watch App 与 Watch Widget Extension 需要共享 Watch 侧 App Group，但不得假设它们能直接读取
iPhone 的 App Group 容器。iPhone → Watch 必须经过 WatchConnectivity 或未来明确批准的云同步。

### 4.4 WatchConnectivity 策略

按数据语义选择通道：

1. updateApplicationContext：发送“只需要最新一份”的 WatchSnapshot，是主通道。
2. sendMessage：两端都可达时发送即时命令和 ACK，例如开始/停止计时；不可达时不能假装成功。
3. transferUserInfo：为确实需要排队的命令或事件提供后台兜底，必须带 commandId 防止重复执行。
4. transferFile：仅在 snapshot 将来超过字典负担时使用；首版不传图片和大文件。

WatchConnectivity 是系统尽力传输，不保证即时到达。因此：

- Watch 必须使用本地最后一份 snapshot 离线显示；
- UI 必须区分“已同步”“等待同步”“数据已过期”；
- iPhone 是设置和冲突解决权威端；
- 每份 snapshot 和命令都有单调 revision、commandId 与 ACK；
- 旧 revision 不得覆盖新 revision；
- Watch 重新配对、换表、恢复备份或 companion 未安装时显示明确空态。

### 4.5 Watch 上的控制范围

W1 先完成只读联动，保证抬腕显示可靠。W2 再加入少量高价值操作：

- 开始计时；
- 停止计时；
- 非工作日的“今天也上班”二次确认；
- 可选的加班延长快捷操作。

这些操作发送命令给 iPhone，并等待 ACK。iPhone 不可达时，Watch 可以将命令标为待同步，但
不能立即把未确认状态写成最终事实。复杂排班、午休时长、薪资、通知模式和语言继续在 iPhone
配置。

若实际体验证明“排队后才生效”比没有按钮更令人困惑，首版可只保留只读状态；这属于 W2
产品验收决策，不影响 W1 和表盘组件交付。

## 5. Watch 表盘组件与小组件

Watch Widget Extension 必须支持以下两种 family：

### accessoryCircular（圆形）

- 进度环为主视觉；
- 中心显示整数百分比或紧凑剩余时间；
- 工作、午休、休息和完成态均有可辨识的符号；
- 在 AOD、accented/vibrant 和低亮度环境仍清晰；
- 数据过期时不继续伪造进度，显示保守占位。

### accessoryRectangular（长方形）

- 第一行显示当前状态和计划下班时间；
- 主区域显示剩余时间；
- 下方显示线性进度条或短进度文案；
- 长语言、窄表盘和 AOD 下不得截断关键信息。

accessoryInline 可作为 W3 的低成本增强，但不是首个验收门槛。accessoryCorner 只有在圆形和
长方形稳定后再评估。

组件不得每秒运行自定义 Timer。使用绝对日期文本、系统 timer 样式和预先生成的 timeline，
在午休开始/结束、下班、加班结束和 snapshot 过期等边界生成 entry。Watch App 收到新 snapshot
后调用 WidgetCenter 刷新，但不能假设刷新即时发生。

组件继续保持 salary-free，不显示工资、时薪、今日已赚或可反推薪资的数据。

## 6. Apple Watch 阶段与完成标准

### W0：工程与契约

- 在现有 Xcode project 中新增 watchOS App 与 Watch Widget Extension targets；
- 确定 deployment target、bundle id、App Group、签名和嵌入关系；
- 定义 WatchSnapshotV1 和 fixture；
- TypeScript/iPhone 生产者与 Watch Swift 解码器使用同一 fixture；
- 对最终 watch app、extension 和 snapshot 做 salary-free 负向检查；
- 扩展 npm run check:ios 和 Xcode Cloud 构建检查。

### W1：只读联动

- iPhone 通过 updateApplicationContext 发布最新 snapshot；
- Watch 原子保存并在离线状态继续显示；
- Watch 主界面显示状态、剩余时间、进度与下班时间；
- 配对、未安装 companion、首次同步、旧 revision、损坏 snapshot 和过期数据都有明确状态；
- Watch 不复制 TypeScript 排班算法。

### W2：表盘组件与轻量控制

- accessoryCircular 和 accessoryRectangular 均完成；
- light/dark、accented、vibrant、AOD、长英文、简中、繁中和 RTL 完成视觉检查；
- 组件在工作、午休、休息、加班、完成和过期状态下都正确；
- 根据 W1 实测决定是否启用开始/停止计时；启用时必须具备 commandId、ACK、重试和去重；
- Watch 上所有复杂设置均引导回 iPhone。

### W3：实机、发布与回归

- 至少一块支持 AOD 的 Apple Watch 和一块较小屏幕型号完成实机测试；
- 覆盖 iPhone 前台、后台、被系统终止、重启、蓝牙断开、Watch 仅 Wi-Fi、重新连接和换表；
- 覆盖夏令时/时区变化、跨午夜班次、午休、加班、轮休和非工作日；
- 验证 Watch App/组件的冷启动、耗电、刷新预算和 stale 状态；
- Xcode Cloud Release Archive 同时包含正确签名的 iPhone、iPad、Watch 与全部 extensions；
- TestFlight 完成 paired iPhone + Watch 回归后再进入 App Store 审核。

## 7. iPad 与 iPhone 数据同步决策

### 当前决定：继续独立运行

iPad 不能作为 Apple Watch 的 WatchConnectivity companion，因此 iPad 与 Watch 没有直接联动。
iPhone 和 iPad 虽然运行同一个 Universal App，但各自拥有独立沙盒；UserDefaults 和 App Group
不会自动跨设备同步。

首版继续让 iPad 独立运行，理由是：

- 当前产品承诺完全离线、无账号、无服务器；
- 排班和倒计时设置体量很小，但薪资属于敏感数据；
- 引入云同步会新增冲突处理、iCloud capability、失败状态、隐私说明和审核验证；
- Watch 项目本身已经带来一套新的同步与生命周期矩阵，不宜同时叠加第二套跨设备协议。

### 未来可选方案：NSUbiquitousKeyValueStore

如果用户明确需要 iPhone/iPad 同步，优先评估 Apple 的 iCloud key-value store，而不是自建账号
或服务器。它适合小型设置与配置，但不能保存敏感信息。

候选同步范围：

- 上下班时间、排班模式、工作日、午休时段；
- 通知和显示偏好；
- 是否开始计时及必要的绝对状态 revision。

默认排除：

- 薪资金额、时薪、累计收入；
- Widget/Live Activity 临时 payload；
- 可由共享规则重新生成的历史 timeline。

启用前必须完成：

- 明确的用户开关，不静默开启；
- versioned envelope、字段级 revision 和冲突规则；
- 离线修改、两台设备同时修改、初次 iCloud 下载和退出 iCloud 的测试；
- 更新欢迎页、隐私页和商店隐私说明，不能再笼统宣称“所有设置只在这一台设备”；
- 保证 iCloud 不可用时 iPhone/iPad 仍能独立工作。

CloudKit/SwiftData CloudKit 只在未来需要历史记录、复杂对象或更强查询时考虑；当前设置规模不值得
引入。此决策在 Watch W3 完成前不启动。

## 8. 可回流到 Windows / macOS 的设计

iPhone/iPad 已验证的产品设计可以回流桌面端，但只同步信息架构与业务体验，不直接照搬
SwiftUI、触摸尺寸或移动端导航。

优先候选：

1. 排班设置：固定星期、大小周、上几休几、“从第 N 天开始”的周期位置说明。
2. 提醒设置：把下班进度、午休开始/结束和健康提醒分组说明，权限状态与功能开关分离。
3. 主界面状态：工作、午休、休息、加班和完成态采用同一语义与文案。
4. 分享体验：4:5 心情图片、统一品牌信息、无薪资分享和更清晰的操作层级。
5. 设置隐私：列表摘要不直接暴露薪资金额；敏感信息只在薪资详情页出现。
6. 默认值与首次使用：09:00–17:00、午休默认关闭且首次为 60 分钟。
7. 关于与隐私文案：突出本地优先、离线可用和无账号，不展示与用户无关的实现细节。
8. 持久化回归：系统语言变化、重启、升级与配置迁移使用统一测试矩阵。

桌面端继续遵守自身约束：紧凑窗口高度、固定 footer、菜单栏/迷你计时器、Windows WebView2
与 macOS AppKit 的平台差异都不能为了“和 iPhone 一样”而破坏。

## 9. Android

Android 原生 App 继续暂时搁置：

- 不建立 Kotlin/Gradle target；
- 不承诺日期；
- 不因为 Watch 开发顺带启动 Android；
- Web/PWA 继续作为 Android 用户现有入口。

未来重新立项至少需要满足：

- Apple Watch W3 已完成并稳定；
- iPhone/iPad App Store 版本运行一段时间，没有高频数据丢失或通知可靠性问题；
- 移动端维护工时可控；
- 有明确 Android 用户需求足以承担通知政策、设备碎片化、Glance 和商店维护成本。

届时仍以系统 ongoing notification 和 Glance 组件为候选方向，Kotlin 不复制 TypeScript
排班规则；所有平台常驻表面继续 salary-free。具体 API 和商店政策必须在立项时重新核对。

## 10. 长期验收矩阵

每个影响 iOS/watchOS 的候选包至少覆盖：

- 全新安装、升级安装、普通终止、强制退出、设备重启；
- 系统语言和 App 专属语言变化；
- 前后台切换、时区与系统时间变化；
- iPhone/iPad 横竖屏、iPad 多任务与侧边栏展开/收起；
- 小屏 iPhone、Pro Max、iPad Mini 和常规 iPad；
- light/dark、AOD、Reduce Motion、Dynamic Type、VoiceOver、RTL 和长英文；
- 通知拒绝、Live Activities 关闭、Widget/Watch snapshot 过期；
- Watch 配对、断连、重连、companion 未安装和表盘刷新预算；
- 所有 App Group、Widget、Live Activity、通知和 Watch payload 的 salary-free 审计。

动效、手势、AOD、表盘和侧边栏交互以真机人工验收为准。模拟器适合编译、状态覆盖和确定性
截图，但不能替代最终手感判断。

## 11. 相关文档与时效性参考

- docs/ADR-MOBILE-D0.md：iOS 26、设备矩阵、通用购买和原生架构定案。
- docs/XCODE-CLOUD.md：Xcode Cloud 与 TestFlight 配置。
- AGENTS.md：共享规则、隐私、构建和发布边界。
- [Apple：设置 watchOS project](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project)
- [Apple：创建独立 watchOS App](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps)
- [Apple：WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [Apple：保持 watchOS 内容更新](https://developer.apple.com/documentation/watchos-apps/keeping-your-watchos-app-s-content-up-to-date)
- [Apple：WidgetFamily](https://developer.apple.com/documentation/widgetkit/widgetfamily)
- [Apple：支持更多 Widget 尺寸](https://developer.apple.com/documentation/widgetkit/supporting-additional-widget-sizes)
- [Apple：NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore)

Apple 的 watchOS、WidgetKit、WatchConnectivity、Xcode Cloud 和 App Store 规则会变化。开始
W0、X1 或 Android 立项时必须重新阅读官方文档，不把本计划中的摘要当成永久 API 契约。
