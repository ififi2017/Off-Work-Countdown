# 移动端选型与上线计划（iOS 优先）

在现有 Web 与 Tauri 桌面端之外，新增 iOS 客户端；Android 后置，等 iOS 上线跑
一段时间、确认维护负担扛得住再启动。壳用 Capacitor，前端复用现有静态导出，
小组件与提醒等原生表面用 Swift 直接写。

本文只覆盖「怎么选、怎么落地」。产品定位、隐私底线与文案原则仍以
[AGENTS.md](../AGENTS.md) 为准，移动端不引入例外。

## 当前进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0** | 提醒算法从 Rust 上移到 TS，成为两端共用的唯一实现 | 🟢 已完成（2026-08-21），见下一节 |
| **P1** | Capacitor spike：现有 `out/` 装进空壳跑到 iOS 模拟器，实测 UI 差距 | ⬜ 未开始 |
| **P2** | `BUILD_TARGET=mobile` 构建目标 + `lib/mobile-state.ts` 桥接层 | ⬜ 未开始 |
| **P3** | 持久化落到 App Group，提醒改为批量预约 | ⬜ 未开始 |
| **P4** | iOS 小组件（移植 macOS 那份）+ 阈值实时活动 | ⬜ 未开始 |
| **P5** | UI 适配清单（安全区、视口高度、触摸目标、手势冲突） | ⬜ 未开始 |
| **P6** | 上架：截图、多语言列表、隐私清单、审核往返 | ⬜ 未开始 |

P1 是硬性串行点，而且很便宜（两小时）。**在它跑出结果之前不要开 P2**：P5 那张
清单是读代码估出来的，模拟器上跑一次就能证伪或坐实，比继续估算划算得多。

### 已完成（2026-08-21）：提醒算法上移

3.1.6 之前，里程碑跨越、午休边界与健康提醒这三套判定都写在
`src-tauri/src/lib.rs` 的每秒轮询里。那等于把班次派生规则复制进了 Rust——
AGENTS.md 写明 Rust「只能比较和求和前端准备好的绝对时间戳」，而按
`(now - segmentStart) / interval` 分桶显然已经越过了那条线。

现在触发时刻与文案都由前端一次算好：

| 交付物 | 位置 |
|---|---|
| 提醒的唯一实现 | `lib/reminders.ts` 的 `buildShiftReminders()` |
| 消费判定（两端共用语义） | `lib/reminders.ts` 的 `selectDueReminders()` |
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
有了绝对时刻的列表，移动端壳可以把它**一次性预约**给
`UNUserNotificationCenter` / `AlarmManager`，而判定语义与桌面端由同一份
vitest 锁住。

**已验证**：`npm run lint`、`npm test`（222 项）、`npm run build` +
`check:build:web`、`npm run build:desktop` + `check:build:desktop`、
`cargo fmt --check`、`cargo test`（16 项）、`cargo clippy -D warnings` 全部通过。

⚠️ **但 Rust 的编译验证是在 Linux 上做的**（容器里补装了
`libgtk-3-dev`、`libwebkit2gtk-4.1-dev`）。这覆盖了本次改动涉及的全部代码——
`advance_reminders` 与托盘循环里被改的那几行都不在任何 `cfg(target_os)` 分支
里——但 macOS 的原生面板、Windows 的迷你窗那些分支没有被编译到。真机验收清单：

1. macOS 与 Windows 各跑一次 `npm run tauri:dev`，确认里程碑通知按 50/75/90/95/100 弹出且各一次；
2. 设一个带午休的班次，确认午休开始与结束各一条；
3. 合盖休眠跨过午休再唤醒，确认**不补发**午休提醒，但里程碑仍补发最高的那一条；
4. 开健康提醒设 1 分钟间隔，确认按段重新计时，午休不把未满的一轮带过去；
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
4. 到点准时的本地通知（App 被杀死也要响）。

这四样**无论选哪个跨端框架都得写 Swift 和 Kotlin**。跨端框架只能省下设置页，
而设置页恰恰是这个产品里最不值钱的部分。下面所有决策都由这一条推出。

## 1. 目标与非目标

**目标**

- iOS 客户端，与 Web/桌面共用同一份前端与同一套班次规则；
- 一个能看时间与收入的锁屏 / 主屏小组件；
- 用户可设定阈值的下班提醒（含灵动岛形态）；
- 本地优先不变：班次、薪资、偏好只留在设备上。

**非目标**

- 账号、云同步、跨设备。移动端不是引入它们的借口。
- Android 首发（见决策 3）。
- 把移动端做成 Web 页面的复刻（见决策 0 与 5）。
- 为实时活动引入服务端推送（见决策 5 与「待定决策」）。

## 2. 架构决策

### 决策 1：同一个仓库，独立发布管线

移动端代码进本仓库，不新开 GitHub 仓库。

共享面太大：整个前端（`out/` 静态导出）、`lib/countdown.ts`、
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

「每个 PR 都要开 macOS runner」这个成本用 `paths` 过滤解决，同样不需要拆仓库。

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

**iOS 上线跑三个月，确认维护负担扛得住，再决定 Android。**

### 决策 4：提醒从「轮询即发」改为「一次算好、批量预约」

已在 P0 完成，见前文。移动端壳的职责只剩三件：

1. 状态变更时取 `buildShiftReminders()` 的输出；
2. 取消全部已预约的通知，按新列表重排；
3. App 回到前台时用 `selectDueReminders()` 复核一次，补上系统没送到的。

⚠️ **iOS 待发本地通知有 64 条上限**（需按当前 Apple 文档复核）。健康提醒按
30 分钟一次、12 小时班次就是 24 条，叠加里程碑与午休边界后逼近上限。因此
移动端**不能**把 `buildShiftReminders()` 的结果整份预约，必须按「只排未来 N
小时、App 每次唤醒时续排」的滚动窗口切片。`lib/reminders.ts` 已经把条目按
`atMs` 升序返回，切片就是一次 `filter`。

`MAX_MICRO_BREAKS_PER_SEGMENT`（240）是 TS 侧的兜底，防止极小的间隔把列表撑爆，
不能替代滚动窗口。

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

⚠️ **ActivityKit 有一个必须先解决的约束：App 不在前台时无法可靠地自行起一个
实时活动。** 被杀死的状态下基本起不来，后台状态下表现不稳定；Apple 为此在
iOS 17.2 引入了 push-to-start，但那需要服务端推送通道，会打破「客户端除更新外
不联网」的克制传统。可行的落地路径：

- **可靠路径**：阈值到点先发一条**本地通知**（这条是系统级调度，App 死着也准
  时）。用户点开通知 → App 进前台 → 起实时活动。
- **尽力路径**：App 每次进前台时，若已进入阈值窗口且没有活跃的实时活动，就补
  起一个。
- **不采用**：`BGTaskScheduler` 定时唤醒后台起活动。系统调度不保证时机，不能
  作为主路径。

所以阈值提醒的**主体是本地通知，实时活动是它的增强形态**，而不是反过来。这一点
在写文案时要想清楚：不能承诺「到点自动出现在灵动岛」。

以上时长与 API 行为**都需要在真机上复核**，并按复核结果回来更新本节。

### 决策 6：持久化落到小组件读得到的地方，复用 WidgetSnapshot 契约

Web 用 localStorage，桌面用 Tauri Store。移动端必须放在**小组件进程能读到**
的位置：iOS 走 App Group 容器，Android 走 SharedPreferences / DataStore。

`widget-snapshot-v1.json` 正是现成的载体——它已经是「前端投影出的、供原生侧
只读消费的快照」，Mac App Store 版就是这么用的。iOS 侧连 Swift 解析代码都不用
改：`WidgetSnapshotContract` 是平台无关的。

### 决策 7：把 `swift/` 从 `src-tauri/macos-widget/` 里提出来

现在 `WidgetSnapshotContract` 埋在 `src-tauri/macos-widget/Sources/` 底下，
名字和位置都在暗示「这是 macOS 专用的」，而它其实平台无关。iOS 小组件要复用
同一份契约与大部分 SwiftUI 代码。

目标结构：

```
swift/
  ├── WidgetSnapshotContract/   macOS + iOS 共用的 JSON 契约
  └── WidgetUI/                 共用的 SwiftUI 视图，各平台补自己的 family
src-tauri/macos-widget/         只留 macOS 的 Extension 与 xcodeproj
src-mobile/ios/                 Xcode 工程 + Widget Extension + Live Activity
```

⚠️ 这一步会动 `Package.swift`、`xcodeproj` 的引用路径、
`scripts/build-macos-widget.sh` 与 `npm run test:widget-contract` 的
`--package-path`，**必须在 Mac 上验证**，Linux 容器里做不了。

**它不依赖移动端立不立项**：提取之后，将来 iOS 立项那天小组件部分基本是白送的；
即便 iOS 最终不做，`swift/` 也比现在的位置更诚实。建议作为独立 PR 先做掉。

## 3. UI 适配清单

先说结论：**UI 适配是这条路上最不麻烦的部分**，读代码估约 1–1.5 周。

依据：`components/off-work-countdown.tsx` 共 3445 行，**响应式断点数量为 0**；
全项目断点 29 处，全在 `ShareDialog`、`download` 页、内容页这些外围。主界面
一直是 `w-full max-w-md`（448px）单列——它本来就是手机布局，只是一直在大屏上看。

三个已经就位的东西：

- `isAppShell` 抽象已存在（`off-work-countdown.tsx:399`），语义正是「去掉浏览器
  边距、内容铺满窗口」，移动端要的就是它；
- 主界面 ↔ 设置页的 `w-[200%]` 横滑转场用的是 `cubic-bezier(0.32, 0.72, 0, 1)` /
  340ms——本来就是 iOS 的 push 曲线；
- **macOS 上的 Tauri 用的就是 WKWebView，和 iOS 同一个引擎**。
  `app/globals.css` 里 `-webkit-user-select` 前缀、橡皮筋回弹、
  `-webkit-user-drag` 那几条注释，都是已经在 WKWebView 上踩过并修好的坑。
  反倒是 Windows 的 WebView2 是 Chromium，和 iOS 不是一路。

`WheelPicker` 用原生滚动 + `scroll-snap`，明确不接管指针事件，触摸开箱即用。

真正要写的活：

| 项 | 现状 | 估时 |
|---|---|---|
| 安全区 | `.pwa-safe-area` 在 `globals.css` 里定义了，但**全项目零使用**；且挂在 `@media (display-mode: standalone)` 下，Capacitor 的 WKWebView 未必命中 | 半天 |
| 顶部系统占位 | `hasOverlayTitleBar`（macOS 交通灯）/ `hasWindowsTitleBar` 已把这个抽象好，三处消费点。iOS 只是加第三种情况：状态栏 + 灵动岛 | 1 天 |
| 视口高度 | `h-screen` 类共 7 处，键盘弹出会出问题，换 `dvh` | 半天 |
| 触摸目标 | `h-9`(36px) 13 处、`h-10` 4 处、`h-8` 2 处、`h-7` 2 处；Apple 要求 44pt | 2–3 天 |
| hover 依赖 | 12 处，触摸端退化为「点了才有反馈」通常可接受 | 半天 |

⚠️ 触摸目标是**唯一一处两端诉求真冲突**的地方：AGENTS.md 明确规定桌面窗口
高度不能增加，所以那 13 处 `h-9` 不能全局调大，必须走 `isAppShell` 分支，
改完还要回归确认桌面高度没变。

真正麻烦的三件事都不是 CSS：

1. **软键盘。** `h-screen` 容器 + `overflow-hidden` 的组合下，薪资与时间输入框
   被键盘顶住又滚不动，是 WKWebView 的经典坑。唯一需要真机反复调的。
2. **手势冲突。** iOS 左边缘返回手势会抢走约 20pt，和 `w-[200%]` 的横滑切换
   设置页直接打架。要么设置页改成从右边缘进、让出左边缘，要么放弃滑动只留按钮。
   **这是设计决策，越早定越好。**
3. **审核不看 CSS。** App Store 指南 4.2「最低功能要求」判的是有没有原生表面，
   不是像不像原生。化解方式是小组件与阈值实时活动**必须在首次提审时就在包里**，
   不能「先上壳再迭代」。这意味着 iOS 的最小可上架版本比想象中大。

## 4. 仓库与发布机制的具体改动

- **构建目标**：`BUILD_TARGET=mobile` + `pageExtensions: ['mobile.tsx', 'tsx']`，
  与现有 desktop 目标完全对称（见 `next.config.mjs`）。
- **桥接层**：新增 `lib/mobile-state.ts` + `lib/mobile-*-stub.ts`，沿用
  `desktop-state.ts` 那套「适配器 + webpack 模块替换」的既有模式。
- **tag**：`ios-v*`，与 `desktop-v*` 并列。
- **workflow**：新增 `release-ios.yml`，独立于 `release-desktop.yml`，理由见决策 1。
- **CI**：`ci.yml` 加 `paths` 过滤，前端改动不触发 Xcode 构建。
- **版本对齐**：`npm run check:version` 扩展到 iOS 的 `Info.plist`。

⚠️ **monorepo 唯一的真实代价是发布说明会串台。** `.github/release.yml` 只按
`enhancement` / `bug` / `documentation` 三个 label 分组，而 GitHub 自动生成的
变更日志是和「上一个 release」比。三端 tag 交错之后，iOS 的 release 会把中间
那些桌面端 commit 全卷进去。两个动作解决：

1. release workflow 里**显式指定 `previous_tag`**，只和同前缀的上一个 tag 比；
2. `label-pr.yml` 现在只从标题前缀取 type，scope 被丢掉了（脚本注释里的例子
   恰好就是 `feat(desktop)!: xxx -> feat`）。扩展成同时读 scope，贴上
   `ios` / `android` / `desktop` 标签，再在 `release.yml` 里加平台类目。

两处加起来半天，一次性。

## 5. 已知硬限制

- **签名与账号**：iOS 强制 Apple Developer 会员（已有）。桌面端那套「不购买
  代码签名证书」的策略在移动端行不通，必须接受。Android 另需 Play Console
  $25 一次性。
- **隐私合规**：iOS 需要 `PrivacyInfo.xcprivacy` 声明必要理由 API——读写
  `UserDefaults` 属于 CA92.1。本地优先、无账号、不上传薪资的现状让这份声明
  很好填。
- **商店素材**：`scripts/marketing-shots/macos/` 的截图流水线与
  `docs/msstore-listing-titles.csv` 的多语言列表元数据是现成先例，可扩展复用。
- **PWA 仍在**：Serwist 已就绪，`lib/notify.ts` 甚至已处理了 Android Chrome
  只能走 `registration.showNotification()` 的坑。它是过渡形态，不因为 iOS
  客户端上线而下线。

## 6. 待定决策

| # | 待定项 | 需要在什么之前定 | 倾向 |
|---|---|---|---|
| A | iOS 定价与是否与 macOS 做通用购买 | **建 iOS App 之前**——通用购买要求两端 bundle id 一致，事后改不了。macOS 现在是 `com.rainif.offworkcountdown.macappstore` | 未定 |
| B | 设置页横滑 vs iOS 左边缘返回手势，二选一 | P5 开始之前 | 让出左边缘，设置页改从右边缘进 |
| C | 阈值档位的默认值 | P4 | 15 分钟，与现有「下班前 15 分钟提醒」对齐 |
| D | 实时活动起不来时的兜底文案 | P4 | 见决策 5：文案不能承诺「自动出现在灵动岛」 |

A 是最紧的：它是一个**建完 App 就锁死**的决定。

## 7. Android（后置）

不在本轮范围，只记两条将来会用到的结论，免得重新查：

- **别用前台服务。** Android 14 起前台服务必须声明类型，倒计时套不进任何合适
  的类型。更干净的做法是常驻通知 + `setUsesChronometer(true)` /
  `setChronometerCountDown(true)`：**通知自己走秒，进程完全不用活着**，再用
  AlarmManager 在关键节点唤醒刷新。省电、合规、实现更简单。
- 小组件用 Glance，读同一份 `widget-snapshot-v1.json`。
