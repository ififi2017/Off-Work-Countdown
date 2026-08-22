# 移动端选型与上线计划（iOS 优先）

在现有 Web 与 Tauri 桌面端之外，新增 iOS 客户端；Android 后置，等 iOS 上线跑
一段时间、确认维护负担扛得住再启动。壳用 Capacitor，前端复用现有源码与静态导出
机制，但生成独立的 Mobile 产物；小组件与提醒等原生表面用 Swift 直接写。

本文只覆盖「怎么选、怎么落地」。产品定位、隐私底线与文案原则仍以
[AGENTS.md](../AGENTS.md) 为准，移动端不引入例外。

## 当前进度与顺序

| 阶段 | 内容 | 状态 |
|---|---|---|
| **D0** | 定 spike 基线与决策期限；P1 实测后锁最低 iOS、设备范围、通用购买与降级矩阵 | 🟡 通用购买已定；最低 iOS 与设备矩阵待 P1b 后锁定 |
| **P0** | 里程碑、午休与健康提醒从 Rust 上移到 TS | 🟡 代码完成，macOS / Windows 平台验收待完成 |
| **P1a** | 最小 mobile 静态导出：根 `index.html`、语言入口、离线资源 | 🟢 技术启动验证完成，不作为产品 UI 验收 |
| **P1b** | 专用竖屏 UI + Capacitor：模拟器与至少一台真机实测 | 🟡 iPhone 真机安装、冷启动与前后台恢复已通过；屏幕侧交互确认待完成 |
| **P2** | 正式 `BUILD_TARGET=mobile`、隐私裁剪、`lib/mobile-state.ts` 桥接层 | ⬜ 未开始 |
| **P3** | App Group 最小投影 + 阈值规则归一 + 本地提醒预约器 | ⬜ 未开始 |
| **P4** | 共享 Swift 契约、无薪资小组件、阈值实时活动及旧系统降级 | ⬜ 未开始 |
| **P5** | UI、无障碍、深链接与前后台恢复适配 | ⬜ 未开始 |
| **P6** | 签名、TestFlight、截图、隐私清单与审核往返 | ⬜ 未开始 |

顺序是 `D0 基线 → P1a → P1b → D0 定案 → P2 → P3 → P4/P5 → P6`。P1 仍是硬性串行点，
但不能直接拿现有 Desktop `out/` 判断移动 UI：那份产物在构建期已经选中了
Desktop 分支，而且入口是 `en.html`；Capacitor 的 `webDir` 则要求根目录有最终
`index.html`。因此 P1a 只做足以产出真实 mobile 页面的一次性最小改动，P1b 再
判断 Capacitor 与现有 UI 是否值得继续。P2 才把 spike 整理成正式、可维护的构建目标。

### P1 执行记录（2026-08-22）

- 新增 `BUILD_TARGET=mobile` 的独立静态产物、根 `index.html` 语言入口与 19 份
  `<locale>.html`；根入口只读本地语言偏好，不转发 query/hash；
- Mobile 产物断言已确认不含 Web Route Handlers、Vercel Analytics、Speed Insights、
  Serwist / Workbox、Web Notification API、商店下载入口与 Desktop Mini Timer；
- Web、Desktop、Mobile 三种 build/check 以及 lint、单元测试均通过；
- 最初直接渲染 Web 主页面的 390×844 结果只证明功能能启动，因上下留白、Web 页头与
  卡片式结构不符合产品标准，已明确否决为正式 UI；
- 已实现第一版 Mobile 专用竖屏布局：edge-to-edge Timer/Settings 双页、44pt 时间与工作日
  控件、底部主操作、运行中大号计时区和 iOS grouped settings；浅色、深色、英文与简中
  已在 390×844 视口完成交互和截图检查，未来班次也已改用 macOS 商店版语义；
- iOS 工程使用真正的 `UITabBar` 驱动双页切换，Web fallback 只用于浏览器视觉回归；
  iOS 26 的 Liquid Glass 由系统控件渲染，不用 CSS 冒充；
- Mobile 语言切换使用同级 `<locale>.html` 本地导航，并在切换后保留 Settings 页；已实测
  English → العربية、RTL 与根入口冷启动恢复，不再落入 Web 的 `/<locale>` 404；
- App Icon 与浅色 / 深色 Launch Screen 复用现有 macOS 商店版橙色时钟品牌资产，不保留
  Capacitor 模板图标；App Icon 为 1024×1024、无 alpha；
- 已用 Capacitor 8.4.2 生成 iPhone portrait 的 iOS 26 工程并解析 SwiftPM 依赖；完整
  `xcodebuild` Simulator scheme 已通过，最终 `.app` 已核对 bundle id、3.1.6 版本、iPhone-only、
  portrait-only 与最低 iOS 26.0 声明；
- 已在 iOS 26.5 / iPhone 17 Pro Simulator 安装并启动真实 `.app`，检查 Dynamic Island、Home
  Indicator 安全区与浅色/深色主题。首轮截图发现原生 `UITabBar` 与 Web fallback 重叠、原生
  标签未本地化；修复 WKWebView 消息桥注册时机和 hydration 后的 native class 后重新构建，
  最终只保留系统 Liquid Glass 底栏，`计时 / 设置` 标签与主题均正常同步；
- 已在 iPhone 17 Pro（iOS 27.0 beta，有线配对且开启开发者模式）签名安装 3.1.6 Debug；
  两次冷启动都完成 `capacitor://localhost` 加载并进入 WebView，前后台往返保持同一进程，
  正常终止后也能重新冷启动；
- 当前 Mac 没有注册 `devices://` 设备镜像协议，因此安全区、软键盘输入与 Timer / Settings
  原生底栏切换仍需直接看手机屏幕完成最终人工确认；本地通知与 Live Activity 属 P3 原生
  预约链路，当前 no-op bridge 不具备可验收的提醒效果，不能把这部分计入 P1b 真机证据。

产品方向已进一步锁定：iOS 是现有 macOS App Store 商品的通用应用，不是 Web 页面装壳。
它复用 macOS 商店版的业务能力、班次/提醒规则和隐私边界，但 UI 使用 Mobile 专属页面：
竖屏 edge-to-edge 布局、Timer/Settings 双页导航、至少 44pt 触摸目标、底部系统 Tab Bar，
并在 iOS 26 上采用原生 Liquid Glass 外观。现有 Web 等价视口截图只作为反例与功能基线，
不再是 P1b 的 go 条件。

### 代码已完成、平台验收待完成（2026-08-21）：提醒算法上移

3.1.6 之前，里程碑跨越、午休边界与健康提醒这三套判定都写在
`src-tauri/src/lib.rs` 的每秒轮询里。那等于把班次派生规则复制进了 Rust——
AGENTS.md 写明 Rust「只能比较和求和前端准备好的绝对时间戳」，而按
`(now - segmentStart) / interval` 分桶显然已经越过了那条线。

现在触发时刻与文案都由前端一次算好：

| 交付物 | 位置 |
|---|---|
| 里程碑、午休与健康提醒的唯一实现 | `lib/reminders.ts` 的 `buildShiftReminders()` |
| 轮询消费判定（Desktop；移动端不把它当投递回执） | `lib/reminders.ts` 的 `selectDueReminders()` |
| 单元测试（同时是 Rust 侧验收标准） | `lib/reminders.test.ts`，29 个用例 |
| 落盘投影 | `lib/desktop-state.ts` 的 `projectReminders()` |
| Rust 侧消费 | `advance_reminders()` / `ReminderMarker` / `ShiftReminder` |

`src-tauri/src/lib.rs` 净减 311 行：`NotificationMode`、`NotificationMilestone`、
`BreakNotification`、`NotificationMarker` 四个类型，以及
`advance_notification_marker` / `advance_break_notification` /
`advance_micro_break_marker` / `micro_break_body` / `notification_title` /
`notification_body` 与三个 `send_*` 函数全部删除，换成一个
`advance_reminders` + 一个 `send_reminder`。

对移动端的意义：手机上进程随时会被杀，「每秒轮询、到点即发」那套根本不成立。
有了绝对时刻的列表，移动端壳可以把未来条目预约给系统。`lib/reminders.test.ts`
继续锁住班次派生、文案、失效和折叠语义；移动端还要另加一层预约器契约测试，覆盖
稳定 ID、容量、取消、重排与系统权限。纯函数正确不等于原生预约链路正确。

**本地已验证**：`npm run lint`、`npm test`（222 项）、`npm run build` +
`check:build:web`、`npm run build:desktop` + `check:build:desktop`、
`cargo fmt --check`、`cargo test`（16 项）、`cargo clippy -D warnings` 全部通过。

⚠️ **这次本地 Rust 编译验证是在 Linux 上做的**（容器里补装了
`libgtk-3-dev`、`libwebkit2gtk-4.1-dev`）。这覆盖了本次改动涉及的全部代码——
`advance_reminders` 与托盘循环里被改的那几行都不在任何 `cfg(target_os)` 分支
里——但 macOS 的原生面板、Windows 的迷你窗那些分支没有被编译到。因此 P0 暂不
标绿；在 macOS / Windows CI 通过后，仍需完成以下平台冒烟：

1. macOS 与 Windows 各跑一次 `npm run tauri:dev`，确认里程碑通知按 50/75/90/95/100 弹出且各一次；
2. 设一个带午休的班次，确认午休开始与结束各一条；
3. 合盖休眠跨过午休再唤醒，确认**不补发**午休提醒，但里程碑仍补发最高的那一条；
4. 用测试入口把健康提醒设为 1 分钟间隔，确认按段重新计时，午休不把未满的一轮带过去；
5. 班次进行到一半时打开通知开关，确认**不会**立刻补弹一串历史提醒。

第 3 与第 5 条是最容易在重构里悄悄丢掉的语义，`lib/reminders.test.ts` 里各有
对应用例，但那只证明纯函数对，不证明 Store 的读写链路对。

另有两处 clippy 告警（`OpenerExt` 未使用、`open_notification_settings` 的 `app`
未使用）是既有的 **Linux-only** 现象：那两处只在 macOS/Windows 分支里被用到，
而 CI 只为这两个平台编译 Rust，因此从未暴露。本次不处理，也不建议处理——在
Linux 上「修好」它们会动到另外两个平台真正在用的代码。

## 0. 核心判断：手机上原生表面才是产品

桌面端用户会把 Mini Timer 挂在菜单栏一整天；手机用户不会盯着一个倒计时页面看。
移动端的真实价值只有四处：

1. iOS 锁屏 / 灵动岛的实时活动；
2. iOS / Android 桌面小组件；
3. Android 可自走秒的常驻通知；
4. 交给系统按绝对时间调度的本地提醒（App 不运行时仍可由系统呈现）。

这四样**无论选哪个跨端框架都得写 Swift 和 Kotlin**。跨端框架只能省下设置页，
而设置页恰恰是这个产品里最不值钱的部分。下面所有决策都由这一条推出。

## 1. 目标与非目标

**目标**

- iOS 客户端，与 Web/桌面共用同一份前端与同一套班次规则；
- 一个能看状态、剩余时间与进度的锁屏 / 主屏小组件；
- 用户可设定阈值的下班提醒（含灵动岛形态）；
- 本地优先不变：班次、薪资、偏好只留在设备上。

**非目标**

- 账号、云同步、跨设备。移动端不是引入它们的借口。
- Android 首发（见决策 3）。
- 把移动端做成 Web 页面的复刻（见第 0 节与决策 5）。
- 为实时活动引入服务端推送（见决策 5 与「决策记录与待定项」）。
- 在小组件、实时活动或通知中展示薪资、时薪、累计收入。移动端与 PC 小组件保持一致，
  这些原生常驻表面只显示时间、状态与进度。

## 2. 架构决策

### 决策 0：先定系统与设备基线，再建 Xcode App

P1 前必须留下一个短 ADR，先记录用于 spike 的部署基线、设备范围、通用购买倾向与
每项最终决策期限；P1b 完成后、P2 开始前，再用真机结果锁定最终支持矩阵。ADR 至少回答
四件事：

当前临时基线与锁定条件见 [ADR-MOBILE-D0.md](ADR-MOBILE-D0.md)。

1. spike 用什么最低 iOS，首发最终最低版本是 16.1 还是 26；
2. 首发只支持 iPhone，还是同时把 iPad 当一等设备；
3. 支持哪些方向，iPad 多任务窗口是否在首发范围；
4. 与现有 macOS App 共用 App Store Connect 记录和 bundle id，还是独立销售。

最低版本会改变实时活动的主路径。iOS 26 的 ActivityKit 已支持在 App 前台时
**提前预约某个绝对日期启动 Live Activity**；系统到点可在 App 位于后台时启动，
不需要 push-to-start 或服务端。iOS 16.1–25 没有这条 API，只能用本地通知做可靠
主路径，用户点开或 App 再次前台时才增强成实时活动。

倾向保留两级实现，等 P1 真机结果后再决定是否值得为旧系统承担分支；这个结论必须在
P2 前定案，不能把两套架构一直并行做到 P4：

| 系统 | 阈值到点主路径 |
|---|---|
| iOS 26+ | 预先预约的 Live Activity；失败、被禁用或名额不足时退回本地通知 |
| iOS 16.1–25 | 本地通知；用户点开后启动短时 Live Activity |

这里所说的「系统到点」也不是绝对投递保证。通知权限、Live Activities 开关、专注
模式、通知摘要和系统资源都可能改变最终呈现，产品文案只承诺「为这次班次预约提醒」，
不承诺「一定准时响」或「一定自动出现在灵动岛」。

### 决策 1：同一个仓库，独立发布管线

移动端代码进本仓库，不新开 GitHub 仓库。

共享面太大：整个前端源码与静态导出机制、`lib/countdown.ts`、
`lib/reminders.ts`、`lib/widget-snapshot.ts` 与它的 Swift 契约包、19 份
`public/locales/*`。拆仓库意味着这些要变成 npm 包或 submodule，代价具体：

- 改一条班次规则要走「A 仓库 PR → 发包 → B 仓库升版本 → 第二个 PR」；
- `widget-snapshot-v1.json` 的双端 fixture 测试会失效——那套测试的全部意义
  就是「同一次 CI 里 TS 和 Swift 验同一份 fixture」，跨了仓库就退化成两个
  各自绿的测试，而 iOS 小组件正好要复用这份契约；
- `npm run check:version` 的五文件版本对齐够不着另一个仓库；
- AGENTS.md 那条「`lib/countdown.ts` 是班次规则唯一实现」从 CI 可强制降级为
  口头约定。

⚠️ **想要的隔离靠工作流实现，不是靠仓库。** `release-msstore.yml` 当初面对的
是一模一样的问题（外部审核、会过期的凭据、失败不该连累别人），
[PLAN-MSSTORE.md](PLAN-MSSTORE.md) §4 给的解法是「并行但完全独立的工作流，
同一仓库」。App Store 与 Play 就是第三、第四个同类渠道，照抄。

「每个 PR 都要开 macOS runner」这个成本用按 job 计算的路径过滤解决，同样不需要
拆仓库。不能在整个 workflow 上粗暴排除前端目录：`lib/countdown.ts`、
`lib/reminders.ts`、`lib/widget-snapshot.ts`、本地化与共享 Swift 契约变化仍必须触发
iOS/Swift 检查。

**什么时候才真该拆**（满足任意一条再考虑）：移动端 UI 彻底脱离 React 改走
SwiftUI/Compose，共享面缩到只剩语言包；移动端要闭源或换 license；移动端交给
别人独立维护，协作边界比代码复用更重要。

### 决策 2：壳用 Capacitor，不用 Tauri mobile

Tauri v2 确实支持 iOS/Android，`src-tauri/Cargo.toml` 里也早有
`cfg(not(any(target_os = "android", target_os = "ios")))` 的守卫。但：

**移动端的 Rust 层是净负担。** Rust 在桌面端的价值是托盘、菜单栏、窗口生命
周期——手机上没有窗口概念，这些全部归零。而所有移动端原生能力
（WidgetKit、ActivityKit、Glance、前台通知）都得包成 Tauri 插件，即
Swift/Kotlin → Rust FFI → JS，比直接写多一整层。Capacitor 的 iOS/Android
工程就是普通 Xcode / Gradle 工程，往里加 Widget Extension 是标准路径。

代价是引入第二套壳技术（桌面 Tauri / 移动 Capacitor）。接受，因为两边的原生
层本来就不共享任何代码。

⚠️ 如果将来改主意走 Tauri：`tauri-plugin-notification` 被误放在上面那段
non-mobile 守卫里，它其实支持 Android/iOS，必须移回 `[dependencies]`。同段里
的 `autostart` / `global-shortcut` / `single-instance` / `updater` 则确实是
桌面独有，位置是对的。

### 决策 3：iOS 优先，Android 后置

不并行。差异化表面（实时活动、灵动岛）在 iOS；Apple 开发者账号已有（Mac App
Store 上架过）；SwiftUI 小组件代码已经写好了。Android 的收益（常驻 chronometer
通知 + Glance 小组件）真实但不差异化，而 Play 政策变更与碎片化是**持续性**
负担，不是一次性的。

**iOS 上线跑三个月，再按量化门槛决定 Android。** 至少记录：三个月移动端维护工时、
崩溃与卡死率、App Review 往返次数、需要真机复现的支持请求数，以及每次系统大版本
升级造成的修复工时。只看下载量或主观感觉都不足以决定是否再背一套 Kotlin/Gradle 壳。

### 决策 4：提醒从「轮询即发」改为「一次算好、批量预约」

P0 已完成里程碑、午休边界与健康提醒的绝对时刻，但现有 Web「下班前 15 分钟」仍由
`off-work-countdown.tsx` 中的 `REMINDER_LEAD_MS` 和每秒 tick 单独判定。P3 开始前先补齐
这个缺口：在 `lib/reminders.ts` 增加 `threshold` 类型及启用状态、提前分钟数和最终文案
输入，让 `buildShiftReminders()` 直接产出它的绝对 `atMs`；随后删除组件里的固定 15 分钟
判定。Web tick、本地通知降级和预约 Live Activity 都消费同一个条目，阈值不在 Swift
里重新计算。

当前班次与 `nextShift` 的合并、优先级、revision 和命名空间也应由一个 TS 纯函数形成
最终预约投影，并用 fixture 锁住。原生端只接受铺平后的列表，不能自己拼第二班或推导
工作日。完成这两项后，P3 再实现一个窄的 iOS 预约器。
它不理解班次，只接受前端投影，并负责：

1. 过滤过去、静音（`title` / `body` 为 `null`）或原生端不支持的条目；
2. 把字符串 reminder id 映射成稳定、无碰撞的原生 identifier；
3. 按 `modelVersion + shiftRevision + reminderId` 取消和替换**本产品当前投影**里的请求；
4. 读取系统 pending 列表进行对账，确认预约成功并把错误返回给前端；
5. 在权限、班次、语言、时区或系统时间变化后重新投影和预约。

不要在每次状态变化时调用「取消 App 的全部通知」。那会删掉未来可能加入的非班次
通知，也无法证明旧请求已经被新请求完整替换。先提交新投影、核对成功，再删除不再
属于新修订号的旧 identifier；失败时保留仍然正确的旧请求。

`selectDueReminders()` 仍是桌面轮询消费语义的验收函数，**不是 iOS 的投递回执**。
App 回到前台时无法仅凭 `(previousMs, nowMs]` 判断系统有没有呈现过某条通知；盲目
补发会把已经进过通知中心、后来被用户清掉的提醒再弹一次。移动端回前台只做 pending
请求与当前投影的对账，不补发历史本地通知。前台到点时由
`UNUserNotificationCenterDelegate` 明确决定是否展示当前那一条。

Apple 旧文档记录过「只保留最近 64 条待发本地通知」的限制；当前 UserNotifications
文档没有稳定地把数字写进 API 契约，因此实现按 **64 条保守上限**做容量测试，并在
P3 真机复核。现有 UI 的健康提醒最短 30 分钟，连续 12 小时也只有约 24 条，加上
里程碑和午休边界仍明显低于上限；首版不需要依赖「未来 N 小时、等 App 醒来再续排」
这种不可靠滚动窗口。

容量策略固定为：

1. 先保证当前班次和已由前端准备好的 `nextShift` 的下班、阈值、里程碑与午休边界；
2. 再用剩余额度预约当前班次的健康提醒，按触发时刻由近到远填充；
3. 超限只裁健康提醒，绝不裁下班和阈值提醒；
4. 首版可靠性承诺止于「当前班次 + 已预计算下一班」。第三班及之后必须在 App 再次
   前台、由 TS 产生新快照后才能预约，原生层不得自行推导工作日。

`MAX_MICRO_BREAKS_PER_SEGMENT`（240）继续是 TS 防御性上限；原生 64 条容量测试是
另一层约束，两者不能互相替代。

### 决策 5：不做长时实时活动，改成用户设定阈值

**这是本计划里最重要的产品决策。**

直觉方案是班次一开始就起一个实时活动，让它在灵动岛里走完整班。这条路有两个
问题：

1. **撞时长天花板。** 实时活动活跃约 8 小时，之后锁屏残留最多再 4 小时
   （共约 12 小时，需按当前 iOS 版本复核）。而 996（9:00–21:00）正好是 12 小时，
   压在边界上——首页明确列出的预设场景里就有它。
2. **更根本的：灵动岛是被争抢的资源。** 一个占着 8 小时的实时活动，用户要么
   嫌它挡视线自己划掉，要么被别的 App 顶掉。做出来也活不到下班。

**改成：用户设定在下班前多久收到实时活动提醒**，可选 1 小时 / 30 分钟 /
15 分钟 / 10 分钟 / 5 分钟 / 1 分钟。到点才起一个实时活动，从此只活到下班。

这样时长天花板**从根上不存在**（1 小时的活动远在 8 小时以内），灵动岛只在
用户真正关心的那段时间占用，胜率高得多。加班时可以再起一个新的短活动，同样
不触碰上限。

而且它不是新概念：产品本来就有「下班前 15 分钟提醒」，这只是把那个固定值变成
可选档位，并给它一个更好的呈现形态。

ActivityKit 在 iOS 26 增加了带 `start` 日期的预约 API，所以实现按系统能力分层：

- **iOS 26+ 主路径**：用户开始/修改班次时，由 App 在前台预约一条 `pending` Live
  Activity，`start` 就是阈值时刻，内容只带绝对结束时间、状态、进度所需字段和本地化
  copy key。系统要求同时提供 `AlertConfiguration`，阈值到点由系统启动并提醒。
- **旧系统或降级路径**：预约一条阈值本地通知。用户点开后 App 进入前台，再启动剩余
  时长内的短 Live Activity；App 前台时若已在阈值窗口，也可以补起。
- **失败路径**：Live Activities 被关闭、预约名额不足、API 抛错或预约对账失败时，
  自动退回本地通知，并在设置页显示中性的能力状态和打开系统设置入口。
- **不采用**：`BGTaskScheduler` 定时唤醒，也不为此引入 APNs 服务端。系统调度不保证
  BGTask 时机，而 push-to-start 会扩大网络、token 与隐私边界。

班次、阈值、语言或加班结束时间变化时，必须取消旧的 pending activity；已经 active
的则更新或结束后重建。下班时用预先预约的本地通知兜底，并让 Live Activity 的动态
日期文本自然走到零；App 下次前台时清理仍处于 active / stale / ended 的遗留实例。

实时活动活跃约 8 小时、锁屏最多再残留 4 小时的限制仍需在最低系统与当前系统上复核，
但阈值最长只有 1 小时，不再压时长边界。还要真机验证三种状态：App 在后台、被系统
终止、用户手动强退；文案只说「已预约阈值提醒」，不能把某一种系统呈现写成保证。

AlarmKit 能在 iOS 26 上提供会突破专注模式和静音的显著闹钟，但这比普通下班提醒强得
多，还需要单独授权。首版不采用；只有未来增加用户明确选择的「闹钟模式」时再立项。

### 决策 6：完整状态留在主应用，App Group 只放无薪资投影

Web 用 localStorage，桌面用 Tauri Store。移动端完整状态——包括班次、薪资与偏好——
放在主应用自己的持久化容器，通过 `lib/mobile-state.ts` 读写；它不是小组件的数据库。
原生预约器只接收前端准备好的绝对提醒列表，不需要从 App Group 读取完整产品状态。

`widget-snapshot-v1.json` 正是现成的载体——它已经是「前端投影出的、供原生侧
只读消费的快照」，Mac App Store 版就是这么用的。前端把它原子写进 App Group，
写成功后调用 `WidgetCenter.reloadTimelines`；主状态写入成功不因小组件同步失败而回滚。

首版与 PC 小组件保持一致，继续使用 salary-free V1：

- 小组件、实时活动和本地通知均不包含工资、时薪、日薪、累计收入或可反推出它们的值；
- App Group 里只放 schema version、生成/过期时间、绝对班次投影、时间线 entry、locale
  和渲染必需的非敏感显示偏好；
- Widget extension schema 不兼容或快照过期时显示保守空态，不读取主应用私有状态，也不
  自行推导工作日、午休、加班或下一班；
- 针对 App Group 文件和最终 `.appex` 做字符串/fixture 审计，工资字段一旦混入就让 CI
  失败。

`WidgetSnapshotContract` 的数据模型是平台无关的，可以原样共享；Swift 的 loader、
TimelineProvider、widget family、可用性判断、深链接和边距处理仍是平台适配层，不能把
「解析代码可复用」夸大成「整个 iOS 小组件不需要改」。

### 决策 7：把 `swift/` 从 `src-tauri/macos-widget/` 里提出来

现在 `WidgetSnapshotContract` 埋在 `src-tauri/macos-widget/Sources/` 底下，
名字和位置都在暗示「这是 macOS 专用的」，而它其实平台无关。iOS 小组件复用同一份
契约；SwiftUI 视图只逐段验证、提取真正能跨平台编译的部分，不预设“大部分都能复用”。

目标结构：

```
swift/
  ├── WidgetSnapshotContract/   macOS + iOS 共用的 JSON 契约
  └── WidgetSharedUI/           只放确认能跨平台编译的视图片段与设计 token
src-tauri/macos-widget/         macOS loader/provider、Extension 与 xcodeproj
src-mobile/ios/                 Capacitor Xcode 工程、iOS provider、Widget 与 Live Activity
```

⚠️ 这一步会动 `Package.swift`、`xcodeproj` 的引用路径、
`scripts/build-macos-widget.sh` 与 `npm run test:widget-contract` 的
`--package-path`，**必须在 Mac 上验证**，Linux 容器里做不了。

**它不依赖移动端是否最终上线**，但不应抢在 P1 硬门槛之前扩大改动面。P1 证明路线
成立后，把「契约提取」作为独立 PR；先只移动 Contract 与 fixture 测试，再按编译结果
逐个提取共享 View。每一步都同时编译 macOS 与 iOS，避免为了目录好看制造条件编译泥团。

## 3. UI 适配清单

代码结构说明主界面有较好的手机宽度基础，但在 P1b 真机跑完之前不锁死工期。当前
暂估 1.5–2.5 周，范围包括 UI、输入、无障碍、深链接和生命周期，而不只是 CSS。

依据：`components/off-work-countdown.tsx` 共 3445 行，**响应式断点数量为 0**；
全项目断点 29 处，全在 `ShareDialog`、`download` 页、内容页这些外围。主界面
一直是 `w-full max-w-md`（448px）单列——它本来就是手机布局，只是一直在大屏上看。

三个已经就位的东西：

- `isAppShell` 抽象已存在（`off-work-countdown.tsx:399`），其中「去掉浏览器边距、
  内容铺满窗口」可以复用；但它只是起点，不能继续同时代表 Desktop 的紧凑密度和
  Mobile 的触摸密度；
- 主界面 ↔ 设置页的 `w-[200%]` 横滑转场用的是 `cubic-bezier(0.32, 0.72, 0, 1)` /
  340ms——本来就是 iOS 的 push 曲线；
- **macOS 上的 Tauri 用的就是 WKWebView，和 iOS 同一个引擎**。
  `app/globals.css` 里 `-webkit-user-select` 前缀、橡皮筋回弹、
  `-webkit-user-drag` 那几条注释，都是已经在 WKWebView 上踩过并修好的坑。
  反倒是 Windows 的 WebView2 是 Chromium，和 iOS 不是一路。

`WheelPicker` 用原生滚动 + `scroll-snap`，明确不接管指针事件，是正向信号；仍要在
VoiceOver、放大字体、减弱动态效果与软键盘场景真机验证，不能仅凭实现方式判定开箱即用。

真正要写的活：

| 项 | 现状 | 估时 |
|---|---|---|
| 安全区 | `.pwa-safe-area` 在 `globals.css` 里定义了，但**全项目零使用**；且挂在 `@media (display-mode: standalone)` 下，Capacitor 的 WKWebView 未必命中 | 半天 |
| 顶部系统占位 | `hasOverlayTitleBar`（macOS 交通灯）/ `hasWindowsTitleBar` 已把这个抽象好，三处消费点。iOS 只是加第三种情况：状态栏 + 灵动岛 | 1 天 |
| 视口高度 | `h-screen` 类共 7 处，键盘弹出会出问题，换 `dvh` | 半天 |
| 触摸目标 | `h-9`(36px) 13 处、`h-10` 4 处、`h-8` 2 处、`h-7` 2 处；Apple 要求 44pt | 2–3 天 |
| hover 依赖 | 12 处，触摸端退化为「点了才有反馈」通常可接受 | 半天 |
| Dynamic Type / 放大字体 | 当前 Tailwind 固定字号和固定高度较多，200% 字体可能截断或顶出固定 footer | 1–2 天 |
| VoiceOver / 焦点 | 自定义 picker、开关、进度与图标按钮要补 label、value、顺序和状态播报 | 1–2 天 |
| RTL / 长文案 | 19 locale 中包含 RTL；返回方向、横滑动画、固定宽 Select 与截断都要实测 | 1 天 |
| 生命周期 | 前后台切换、系统时间/时区变化、被杀后冷启动要重算显示并对账原生预约 | 1–2 天 |
| 深链接与外链 | Widget / Live Activity / 通知冷启动到正确页面；Web 下载和外站链接交给系统浏览器 | 1–2 天 |

触摸目标是最明显的两端冲突：AGENTS.md 明确规定桌面窗口高度不能增加，所以那
13 处 `h-9` 不能全局调大。这里不能继续用一个笼统 `isAppShell` 同时代表 Desktop
与 Mobile；应以 `IS_MOBILE_BUILD` 或移动设计 token 分支，改完回归确认桌面高度没变。
固定 footer、overflow 和导航手势也有同类差异。

高风险项：

1. **软键盘。** `h-screen` 容器 + `overflow-hidden` 的组合下，薪资与时间输入框
   被键盘顶住又滚不动，是 WKWebView 的经典坑，需要真机反复调。
2. **手势冲突。** iOS 左边缘返回手势会抢走约 20pt，和 `w-[200%]` 的横滑切换
   设置页直接打架。要么设置页改成从右边缘进、让出左边缘，要么放弃滑动只留按钮。
   **这是设计决策，越早定越好。**
3. **冷启动路由。** Capacitor 根入口、系统语言、通知 action、Widget URL 与 Live
   Activity URL 最终都要汇入同一套路由；不能让每个原生入口自己拼 locale 路径。
4. **审核风险。** App Store 指南 4.2 看的是是否超越重打包网站并提供足够效用，
   小组件与阈值实时活动能明显降低风险，但不能保证通过。首个提审包应带上二者，
   审核备注提供不用账号即可复现的班次、通知、Widget 与 Live Activity 步骤。

P5 真机矩阵至少覆盖：最低 iOS 与当前 iOS、一个小屏 iPhone、一个 Dynamic Island
iPhone；若 D0 决定支持 iPad，再加 iPad 分屏。每台都测 light/dark、系统字体 100% /
200%、VoiceOver、Reduce Motion、英文长标签、简体中文和一个 RTL locale。

## 4. 仓库与发布机制的具体改动

- **构建目标**：把 `BUILD_TARGET` 当枚举解析成 `web | desktop | mobile`，并派生
  `isWeb` / `isDesktop` / `isMobile` / `isStaticShell`。Desktop 与 Mobile 都静态导出，
  但页面和原生适配器不同；任何未知值直接让构建失败，不能静默退回 Web。
- **路由选择**：Mobile 只使用
  `pageExtensions: ['mobile.ts', 'mobile.tsx']`；Web/Desktop 共用的 layout 使用
  `.shell.tsx`，普通 `.tsx` 与标准 `route.ts` 留给 Web/Desktop；
  静态壳不把 Route Handler、manifest、robots、sitemap 和 Web 专属页面带进产物。仅有
  `pageExtensions` 不足以证明普通 `.tsx` 的 Web 专属页已被排除；要为这类页面建立明确的
  目标文件约定或构建期排除机制，并由产物断言验证实际结果。
- **根入口**：`build:mobile` 必须生成 Capacitor 可加载的根 `out/index.html`。它只负责
  读取 OS / 已持久化语言并进入对应静态 locale 页面，不包含薪资、班次或 query 参数，
  也不依赖网络重定向。
- **条件分支审计**：全仓库逐个处理 `!IS_DESKTOP_BUILD`。Web、Desktop、Mobile 使用
  正向常量，禁止继续用「非桌面等于 Web」表达。重点覆盖 analytics、PWA manifest、
  Desktop 下载邀请、未来班次限制、固定 15 分钟 Web 提醒、分享和更新入口。
- **隐私裁剪**：Mobile 与 Desktop 一样在 webpack 解析层替换 Vercel Analytics /
  Speed Insights，并剔除 Serwist 注册、Web Notification 发送路径和下载推广。仅靠条件
  渲染不足以证明第三方模块没有进 `.ipa`。
- **桥接层**：新增 `lib/mobile-state.ts`、`lib/mobile-notifications.ts`、
  `lib/mobile-live-activity.ts` 及 Web/Desktop stub，沿用现有「适配器 + webpack 模块
  替换」模式。React 只依赖接口，不在组件里直接 import Capacitor 或 ActivityKit 细节。
- **构建断言**：新增 `npm run build:mobile` 与 `check:build:mobile`，检查根入口、19 个
  locale、离线资源、无 Route Handler、无 analytics/Serwist/Web Notification 标记，
  并验证生成包不含 updater、镜像端点或薪资 Widget 字段。
- **tag**：`ios-v*`，与 `desktop-v*` 并列。
- **workflow**：新增 `release-ios.yml`，独立完成 Web 资产构建、`cap sync`、Swift tests、
  archive、签名、导出与 TestFlight 上传。tag 只产出/上传候选构建，不自动提交 App
  Review；TestFlight 真机验收通过后再人工选择 build 提审。
- **CI**：用路径分类决定 job，而不是给整个 `ci.yml` 一个粗粒度 `paths`。iOS Xcode
  job 必须在 `src-mobile/ios/**`、`swift/**`、mobile adapter、`countdown.ts`、
  `reminders.ts`、`widget-snapshot.ts`、locale 或构建配置变化时运行；纯 Web 内容页可跳过。
- **版本对齐**：`npm run check:version` 检查所有 iOS App / Widget / Live Activity target
  的 `MARKETING_VERSION`，并验证 `ios-v*` 与产品版本一致。`CURRENT_PROJECT_VERSION`
  是单独、单调递增的 App Store build number，不能拿 `Info.plist` 里的变量占位当版本源。

⚠️ **monorepo 的一个真实代价是发布说明会串台。** `.github/release.yml` 只按
`enhancement` / `bug` / `documentation` 三个 label 分组，而 GitHub 自动生成的
变更日志是和「上一个 release」比。三端 tag 交错之后，iOS release 会把比较区间内
的桌面 PR 也卷进去。平台 label 放进 category 只能**分类**，不能按当前 release 动态
过滤，现有 `"*"` 兜底还会收走所有未匹配项。

处理方式：

1. release workflow 显式指定同前缀的 `previous_tag`，只解决比较范围；
2. `label-pr.yml` 从 Conventional Commit scope 派生 `ios-only` / `desktop-only` /
   `web-only` / `shared`，标题改动时同步清理旧平台 label；
3. 为 Desktop 与 iOS 使用独立 release 配置或生成脚本，对 `*-only` 做目标相关排除，
   `shared` 则进入所有相关渠道；
4. 加 fixture 测试，用一组混合平台 PR 验证 iOS 与 Desktop 输出都只包含该出现的条目。

不要把这项再估成固定半天；先用 GitHub `generate-notes` API 的
`configuration_file_path` 做 spike，若它不能表达目标相关过滤，就直接用脚本读取 PR
labels 生成 Markdown，避免在全局 `.github/release.yml` 上堆互相冲突的 category。

## 5. 已知硬限制

- **签名与账号**：iOS 强制 Apple Developer 会员（已有）。桌面端那套「不购买
  代码签名证书」的策略在移动端行不通。主 App、Widget Extension 和 provisioning
  profile 的 App Group entitlement 必须完全匹配；CI 凭据按最小权限保存并设置轮换说明。
- **通知与实时活动授权**：本地通知、Live Activities 和 AlarmKit（若未来采用）是不同
  能力状态。设置页不能用一个总开关假装三者都已授权；被拒后提供状态说明和系统设置入口，
  首次系统弹窗只在用户明确开启相应功能时请求。
- **隐私清单**：每个 executable / extension 及包含的第三方 SDK 都要审计
  `PrivacyInfo.xcprivacy`。标准、仅主 App 可读的 `UserDefaults` 对应 CA92.1；使用
  App Group suite 在 App 与 extension 间共享则对应 1C8F.1。若 App Group 只写文件而不
  用 suite defaults，就按实际调用的 Required Reason API 申报，不能为了方便照抄代码。
  最终以 Xcode archive 生成的隐私报告为验收物，而不是只检查仓库里有一个 plist。
- **敏感数据边界**：完整薪资仅在主应用私有存储。Widget、Live Activity、通知、深链接、
  日志、崩溃信息和 App Group fixture 都必须 salary-free；CI 对常见字段名与 fixture 做
  负向断言。
- **商店素材**：`scripts/marketing-shots/macos/` 的截图流水线与
  `docs/msstore-listing-titles.csv` 的多语言列表元数据是现成先例，可扩展复用。
- **PWA 仍在**：Serwist 已就绪，`lib/notify.ts` 甚至已处理了 Android Chrome
  只能走 `registration.showNotification()` 的坑。它是过渡形态，不因为 iOS
  客户端上线而下线，但 Serwist 与 Web Notification 代码不能进入 Mobile 静态包。

## 6. 决策记录与待定项

| # | 决策项 | 需要在什么之前定 | 当前结论 / 倾向 |
|---|---|---|---|
| A | iOS 定价与是否与 macOS 做通用购买 | 已定；首次上传前核对现有记录与 capability | **通用购买**：作为 macOS 商店版新增 iOS 平台，沿用 `com.rainif.offworkcountdown.macappstore` |
| B | 最低 iOS：16.1 双路径还是 26 单主路径 | P1 前定 spike 基线；P2 前锁最终版本 | 先在 iOS 26 真机验证预约 Live Activity，再按旧系统用户价值决定是否保留 16.1–25 降级 |
| C | iPhone-only 还是 iPhone + iPad；方向与分屏范围 | P1 前定 spike 设备；P2 前锁正式矩阵 | 首发 iPhone portrait；若 App Store 记录或产品承诺要求 iPad，再把 iPad 当正式验收目标，不靠兼容模式糊过去 |
| D | 设置页横滑 vs iOS 左边缘返回手势，二选一 | P5 开始之前 | 让出左边缘，设置页改从右边缘进，或只保留显式按钮导航 |
| E | 阈值档位的默认值 | P4 | 15 分钟，与现有「下班前 15 分钟提醒」对齐 |
| F | 能力不可用时的状态与兜底文案 | P4 | 只承诺已为班次预约提醒；分别说明通知被拒、Live Activities 被关闭和系统未能预约 |

A、B、C 都会改变 Xcode project、bundle capability、截图矩阵或代码分支。P1a 已把
spike 基线与最终期限写入 D0 ADR；A 已确定为通用购买，B、C 必须在 P1b 取得模拟器和
真机证据后、P2 开始前定案。A 真正锁死的节点仍是 App Store Connect 记录与首次 build
的 bundle id，因此首次上传前还要核对现有记录与 capability，不能另建同名 App 记录。

**已定：首版 iOS Widget、Live Activity 与通知均不显示薪资，与 PC 小组件保持一致。**

## 7. Android（后置）

不在本轮范围，只保留候选方向，不把 2026 年的政策判断当作未来实现结论：

- 候选主表面是 ongoing notification + `setUsesChronometer(true)` /
  `setChronometerCountDown(true)`，让系统 UI 自己走秒；进程不靠每秒 timer 保活。
- 关键节点若用 AlarmManager，立项时必须重新核对目标 Android 版本的 exact alarm 权限、
  用户可撤销状态、Play 政策与通知权限。不能把「AlarmManager 能唤醒」直接写成「一定准时」。
- 前台服务类型与 `specialUse` 的可接受范围按当时政策重新评估；首选不用前台服务，
  但不在现在留下「绝对不可能」的过期断言。
- 小组件用 Glance，消费 salary-free `widget-snapshot-v1.json` 或其向后兼容版本，继续由
  TS 预计算时间线，Kotlin 不复制班次规则。

Android 只有同时满足这些门槛才立项：iOS 已稳定运行三个月；移动端月均维护工时在
可接受预算内；没有尚未解决的高频崩溃/通知可靠性问题；iOS 大版本升级没有连续两次
造成超预算返工；并且 Android 的明确用户需求足以覆盖新增商店、Gradle、Kotlin、设备
矩阵和政策维护成本。

## 8. 各阶段完成标准

### D0

- P1 前把 spike 最低系统、设备/方向、通用购买倾向、bundle id 方案和最终期限写成 ADR；
- P1b 完成后、P2 开始前锁定最低 iOS、正式设备矩阵、通用购买和 iOS 26 预约 Live
  Activity / 旧系统降级矩阵；
- 明确首版所有系统常驻表面 salary-free。

### P1a / P1b

- `out/index.html` 可在完全离线的 Capacitor 壳启动并进入正确 locale；
- Mobile 产物不含 analytics、Speed Insights、Serwist、Web Notification 或 Desktop
  下载邀请；
- 模拟器验证 19 locale 页面可加载，至少一台真机验证安全区、软键盘、前后台恢复、
  外链与根入口；
- 在支持的真机上做最小预约 Live Activity spike，记录后台、系统终止和手动强退结果；
- 输出 go/no-go 结论和实测 UI 差距，未通过就停在 P1，不先提取大批 Swift 代码。

### P2

- `npm run build` / `check:build:web`、Desktop build/check 与 Mobile build/check 同时通过；
- `BUILD_TARGET` 未知值会失败，Mobile 不再落入任何 `!desktop == web` 分支；
- 主应用状态可从私有持久化恢复，首次加载无明显闪烁，写入失败有可恢复错误路径；
- Mobile archive 的网络字符串与依赖审计符合本地优先承诺。

### P3

- App Group 只收到原子写入的 salary-free WidgetSnapshot；同步失败不回滚主应用私有状态，
  也不会把完整班次设置或薪资复制进共享容器；
- `threshold` 提醒进入 `lib/reminders.ts`，固定 15 分钟组件判定被删除；Web、本地通知与
  Live Activity 对相同输入得到同一个绝对触发时刻；
- TS 预约投影测试覆盖 current + nextShift 的唯一 ID、revision、优先级、过去条目与变更重排；
- 预约器的 fixture 测试覆盖稳定 ID、静音条目、修订替换、部分失败、64 条容量、时区/
  时间变化、权限拒绝和 current + nextShift 范围；
- 当前班次的下班与阈值提醒永远优先于健康提醒，超限只裁健康提醒；
- 真机验证 App 前台、后台、系统终止、手动强退、修改班次、修改语言与关闭权限；
- 回到前台不盲目补发历史通知，不删除不属于当前班次投影的请求。

### P4

- TypeScript 与 Swift 继续用同一 fixture 验证 WidgetSnapshot；未知 schema、过期、午休、
  加班、nextShift 和长文案均有测试；
- App Group、Widget `.appex`、Live Activity payload 与通知 fixture 均通过 salary-free
  负向断言；
- Widget 覆盖决定支持的全部 family、light/dark、系统着色、19 locale 与 VoiceOver；
- Live Activity 覆盖 Lock Screen、Dynamic Island compact/minimal/expanded、被关闭、
  预约失败、阈值变化、加班和下班清理；
- iOS 26 主路径与旧系统降级路径分别有真机记录。

### P5

- 完成第 3 节真机矩阵；软键盘不遮挡任何输入或保存操作；
- 200% 字体、VoiceOver、Reduce Motion、RTL、长英文均可完成核心任务；
- Widget、通知和 Live Activity 的冷/热启动深链接进入正确页面；
- Web 与 Desktop 的 light/dark、长英文、固定 footer 和窗口高度没有回归。

### P6

- lint、全部单测、三种前端 build/check、Swift contract tests 与 Xcode archive 通过；
- codesign、entitlements、provisioning profile、App Group、嵌套 extension、架构与最低
  系统版本检查通过；
- Xcode 隐私报告、最终 `.ipa` 依赖/字符串/网络审计与 App Privacy 申报一致；
- TestFlight 安装包完成最低系统与当前系统真机回归，再人工选择 build 提审；
- 截图、多语言列表、隐私政策、支持 URL 与审核备注齐全，备注提供无需账号的复现步骤。

## 9. 时效性参考（2026-08-22 复核）

以下是会随系统与商店政策变化的外部依据。每次开始对应阶段时重新打开原文，不把本计划
里的摘要当永久 API 契约：

- [ActivityKit：启动、预约、更新与结束 Live Activity](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [ActivityKit 更新记录](https://developer.apple.com/documentation/updates/activitykit)
- [User Notifications：系统尽力及时投递，但不保证](https://developer.apple.com/documentation/usernotifications)
- [AlarmKit：显著闹钟、倒计时与授权](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)
- [Required Reason API：UserDefaults 的 CA92.1 / 1C8F.1](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)
- [App Store Connect：添加平台与通用购买](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/)
- [App Review Guidelines 4.2](https://developer.apple.com/app-store/review/guidelines/)
- [Capacitor 配置：`webDir` 必须包含最终 `index.html`](https://capacitorjs.com/docs/config)
- [GitHub 自动发布说明：比较 tag、分类与排除规则](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes)
