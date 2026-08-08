# M5 · 桌面端实施计划（Tauri v2）

> 状态：草案 · 起草于 2026-08-08 · 承接 [PLAN-3.0.md](PLAN-3.0.md) 的 M1–M4（均已合入 main）

---

## 0. 为什么这一步值得做

桌面端能交付一件 Web 端做不到的事：**关闭窗口后仍然收到下班提醒**。

M4 评估 Web Push 时否掉了它，理由是必须把每个人的下班时刻上传到服务端（推翻「数据不出浏览器」的承诺），且分钟级 cron 需要 Vercel Pro（约 $240/年）。桌面端不存在这两个问题——Rust 侧有一个真实的本地定时器，不需要服务端、不需要上传任何东西、不产生持续成本。

**同一个需求，换个载体，代价从「隐私卖点 + $240/年」变成「零」。** 这是 M5 最实的价值，也应当作为它的主打功能，而不是把「有个桌面版」本身当卖点。

次要价值是**常驻可见的倒计时**：macOS 放在菜单栏、点击弹出小面板，Windows 用一个可置顶的迷你窗。两个平台形态不同，理由与设计见决策 7。

## 1. 目标与非目标

**目标**

- macOS（Apple Silicon + Intel）与 Windows x64
- 主界面内容铺满窗口，不出现浏览器版那种四周留白
- 常驻可见的剩余时间：macOS 走菜单栏 + 点击弹出面板，Windows 走可置顶的迷你窗
- 窗口关闭后仍然按时提醒
- 开机自启、全局快捷键唤起
- 应用内自动更新

**非目标**

- Linux。Tauri 支持，但分发与签名是另一套工作，且用户基数最小，留待验证需求后再说
- 移动端。PWA 已覆盖，重复投入不划算
- 与 Web 端的账号或数据同步。保持本地优先，这是产品的既定立场

## 2. 技术选型回顾

结论沿用 [PLAN-3.0.md](PLAN-3.0.md) 的决策 B：**Tauri v2**。

需要重申一处常见误解：**Tauri 的后端是 Rust，不是 Go。** Go 对应的桌面框架是 Wails。

| | Electron | **Tauri v2 (Rust)** | Wails v3 (Go) |
|---|---|---|---|
| 安装包 | 90–150 MB | **5–15 MB** | 10–20 MB |
| 常驻内存 | 200–300 MB | **60–100 MB** | 70–110 MB |
| 渲染引擎 | 自带 Chromium（统一） | WebView2 / WKWebView（分裂） | 同 Tauri |
| 自动更新 | electron-updater（最成熟） | 官方 updater 插件 | 需自建 |
| 生态成熟度 | 最高 | 高，v2 已稳定 | 中，v3 仍 alpha |

决定性理由：**这是一个开一整天的常驻托盘应用**。Electron 为显示一行倒计时长期占用 200–300MB 内存，既是卸载理由，也和「轻量摸鱼工具」的定位自相矛盾。

## 3. 架构决策

### 决策 1：构建目标拆分

静态导出（`output: 'export'`）不支持 middleware、`redirects()` 与动态路由处理器。以下清单为 2026-08-08 对仓库的实测结果——**注意它比 PLAN-3.0 里写的更长，M2–M4 期间新增了三项**：

| 阻碍项 | 位置 | 桌面端处理 |
|---|---|---|
| middleware | [middleware.ts](../middleware.ts) | 排除。Tauri 直接加载 `dist/{lang}/index.html`，语言由本地设置决定，不需要基于 Accept-Language 的重定向 |
| `redirects()` | [next.config.mjs](../next.config.mjs) | 条件配置。那条 308 只为 Web 端的历史 URL 迁移服务 |
| `/api/e`（POST，force-dynamic） | [app/api/e/route.ts](../app/api/e/route.ts) | 排除，见决策 5 |
| `/api/e/stats`（force-dynamic） | app/api/e/stats/route.ts | 排除 |
| `/manifest.json`（force-dynamic） | app/manifest.json/route.ts | 排除。Tauri 不需要 PWA manifest |
| sitemap / robots / opengraph-image | — | 无害但无用，可一并排除以缩小产物 |

**已确认不构成阻碍**：项目未使用 `next/image` 组件（`app/sw.ts` 里只是缓存匹配路径），因此不需要 `images.unoptimized`；`lib/server/*` 的文件系统读取只发生在构建期的预渲染阶段，静态导出正常。

排除机制有两个候选，**都需要先做一次可行性验证再定**：

- **方案 A｜`pageExtensions`**：把 Web 专属路由命名为 `route.web.ts`，两个目标使用不同的 `pageExtensions`。干净、无文件移动。但 `middleware.ts` 不受 `pageExtensions` 影响，覆盖不到。
- **方案 B｜构建前脚本临时移走**：可靠、覆盖全部情况，但会在构建期改动工作区，中断时需要恢复。

初步倾向：**middleware 用方案 B，路由处理器用方案 A**。落地前先用一个最小实验确认 `output: 'export'` 在 middleware 文件存在但 matcher 为空时是否仍然报错——如果不报错，方案 B 可以省掉。

### 决策 2：倒计时的真相源留在前端，Rust 只接收一个绝对时刻

**这是本计划里最重要的一条。**

朴素做法是在 Rust 里复刻 `lib/countdown.ts`：解析 `HH:MM`、处理跨夜班次、判断工作日。**不要这么做。** 那会产生两份必然随时间漂移的实现，而这些逻辑恰恰是已经被单测反复打磨过的部分（跨夜归属、夏令时、工作日边界）。

正确的切分：

1. 前端用现有逻辑算出**本班结束的绝对时间戳**（一个数字）
2. 通过 IPC 交给 Rust
3. Rust 只做 `end - now`，格式化为 `H:MM:SS`

好处有两个。一是**零逻辑重复**——Rust 侧不需要知道什么是跨夜班次。二是**托盘不依赖 webview 存活**：窗口关闭或隐藏后，Rust 的定时器照常运行，托盘继续走字，提醒照常触发。若让 JS 每秒推送托盘标题，窗口一隐藏就会被系统节流，核心卖点当场失效。

托盘标题用 `H:MM:SS` 这种与语言无关的格式，Rust 侧因此也不需要接入 i18n。

### 决策 3：状态存储

- **localStorage 仍是 UI 的唯一真相源**，与 Web 端共用同一套组件代码，不做分叉
- 额外把「结束时间戳 + 提醒开关 + 是否在班」镜像到 `tauri-plugin-store`（一个 JSON 文件），使 Rust 在 webview 尚未加载时也能渲染托盘

镜像是单向的：前端写，Rust 只读。避免双写带来的一致性问题。

### 决策 4：通知走 `tauri-plugin-notification`

Web 的 `Notification` API 在 Tauri webview 里表现不一致。改用官方插件，由 Rust 侧的定时器在到点时直接发出——**这正是桌面端存在的理由**，不能依赖 webview。

现有的 [lib/notify.ts](../lib/notify.ts) 已经把通知发送抽象成一个函数，桌面端替换实现即可，调用方不用改。

### 决策 5：埋点在桌面端关闭

`/api/e` 在静态导出里不存在。可以让桌面端打到线上域名，但那会把「本地优先的桌面应用」变成会回传的应用，与既定立场冲突，且分享漏斗本身是 Web 端的概念。

处理：`lib/track.ts` 在 `BUILD_TARGET=desktop` 时整体 no-op。

### 决策 6：分享链接仍指向网站

分享出去的 URL 继续用 `siteConfig.baseUrl`——接收者多半没装桌面应用，链接必须能在浏览器里打开。桌面端只需把外部链接交给系统浏览器打开（`tauri-plugin-shell` 的 opener），而不是在应用内 webview 里导航。

### 决策 7：窗口形态与布局

Web 端的布局是「大片背景中间浮一张 `max-w-md` 卡片」，这在浏览器里合理，搬到一个 400px 宽的桌面窗口里就全是留白。桌面端要求**内容铺满窗口、无白边**。

#### 布局：复用已有的无边距分支，不新写一套

应用里已经有这条分支——PWA 独立窗口用的 `isPWA` 路径（[off-work-countdown.tsx](../components/off-work-countdown.tsx)）：

| | 浏览器 | `isPWA` 分支 |
|---|---|---|
| 外层容器 | `p-4` 居中 | `p-0`，`flex-col items-stretch` |
| 卡片 | `max-w-md`，圆角 + 阴影 + 玻璃 | `max-w-none min-h-screen rounded-none shadow-none bg-transparent` |
| 底部说明区与页脚 | 显示 | 隐藏 |

**这正是要的效果，桌面端直接走同一条分支。**

需要改的只有判定方式：`display-mode: standalone` 在 Tauri 的 webview 里不会命中。应当改为**构建期注入**（`NEXT_PUBLIC_BUILD_TARGET === 'desktop'`）而非运行时探测——构建期已知意味着首帧就是正确布局，不会出现「先渲染成浏览器版、再跳成桌面版」的闪烁。

顺带把这个概念改名：`isPWA` 表达的其实是「运行在无浏览器外壳的容器里」，PWA 与桌面端共享同一含义，叫 `isAppShell` 之类更贴切。

#### 窗口模型：主窗口 + 迷你窗

| 窗口 | 用途 | 形态 |
|---|---|---|
| **主窗口** | 设置班次、薪资、工作日，查看完整倒计时与周期汇总 | 约 380×560，内容铺满；macOS 用透明标题栏保留红绿灯按钮，Windows 保留原生标题栏 |
| **迷你窗** | 常驻可见的倒计时 | 约 220×72，无边框、无装饰，只有时间 + 进度条（薪资开启时加一行金额） |

迷你窗不要复用主界面组件——那会连带把表单、分享弹窗、汇总一起拉进来。应当是一个轻量组件，复用现有的 `CountdownDisplay` 与 `ProgressBar` 即可。

路由用 `app/[lang]/mini/page.desktop.tsx`，通过决策 1 的 `pageExtensions` 机制**只在桌面构建中存在**，Web 端不会多出一个可索引 URL。静态段 `mini` 优先于 `[preset]` 匹配，不会冲突。

#### 平台行为：同一个迷你窗，两套配置

**macOS —— 菜单栏 + 点击弹出**

- 托盘项用 `set_title` 常驻显示剩余时间（决策 2 已覆盖）
- 点击托盘图标切换迷你窗显示/隐藏，位置对齐到托盘图标下方（`tauri-plugin-positioner` 的 `TrayCenter`）
- 失焦自动隐藏，符合 macOS 菜单栏弹出面板的惯例
- 因此 macOS 上迷你窗**不需要置顶**——它是随叫随到的面板，不是常驻窗

Dock 图标是否保留是个取舍：隐藏（`activationPolicy: Accessory`）更像原生菜单栏工具，但设置窗口只能从托盘菜单进入，发现成本更高。**v1 建议保留 Dock 图标**，纯菜单栏模式作为后续偏好项。

**Windows —— 置顶迷你窗代替托盘文字**

这是对 §5 所述「Windows 托盘不支持文字标题」的正面解法：**不去和托盘较劲，改用一个小的置顶窗**。比在 16×16 图标里塞数字务实得多，信息量也大得多。

- 默认停靠在屏幕右下、任务栏上方；记住用户拖动后的位置
- `skipTaskbar: true`，不占用任务栏
- **置顶可开关**（用户明确要求）：迷你窗上一个小图钉按钮，状态持久化到 Tauri store
- 失焦不隐藏——Windows 上它是常驻小部件，不是弹出面板
- 可选增强：未悬停时降低不透明度，进一步减少存在感。列为 P3 的可选项，实机看效果再定

无边框窗口需要在顶部留一条 `data-tauri-drag-region` 区域才能拖动，这一点容易漏。

#### 迷你窗的数据来源

迷你窗自己跑一个每秒的 JS 定时器，从 Tauri store 里读「结束时间戳」做减法即可——与决策 2 同源，不重复班次逻辑，也不需要与主窗口通信。

## 4. 里程碑

| 阶段 | 内容 | 估时 | 可独立验证的产出 |
|---|---|---|---|
| **P0** | 构建目标拆分 | 1 周 | `npm run build:desktop` 产出可直接用浏览器打开的静态站点 |
| **P1** | Tauri 骨架 | 1 周 | 应用能启动、加载界面、单实例、关闭到托盘而非退出 |
| **P2** | 托盘倒计时 + 迷你窗 | 1.5 周 | macOS 菜单栏走字并可点击弹出；Windows 置顶迷你窗可拖动、可切换置顶；关闭主窗口后两者仍然走字 |
| **P3** | 原生能力 | 1 周 | 到点通知、开机自启、全局快捷键 |
| **P4** | 更新与签名 | 1–2 周 | 签名+公证后的安装包，能自更新到下一版本 |
| **P5** | 发布 CI | 3–5 天 | 打 tag 自动产出三平台安装包并发到 Release |

**P0 是唯一一个纯 Web 侧、且对 Web 端也有价值的阶段**（它会强制把服务端依赖梳理干净），可以先做，风险最低。

**P2 结束时应当停下来做一次判断**：常驻显示在两个平台的实际观感如何。macOS 的菜单栏文字有成熟先例，风险较低；Windows 的迷你窗则要看它在真实桌面上是否既看得见又不碍事——「不易察觉但需要时一眼能找到」是个需要实机调的平衡，纸面上定不了。若这一环达不到预期，后续的签名投入应当重新评估。

## 5. 平台差异与风险

### ⚠️ Windows 托盘不支持文字标题

**这是本计划里最需要提前知道的事实。** macOS 的菜单栏项可以直接显示文本（`set_title`），所以「菜单栏上一直走着的倒计时」在 macOS 上成立。**Windows 的系统托盘只有图标，没有文字标签。**

**已有解法（见决策 7）**：不去和托盘较劲，Windows 改用**置顶迷你窗**承担常驻显示。一个 220×72 的小窗能显示完整时间加进度条，信息量远大于 16×16 图标，也不需要每分钟重绘图标。托盘图标保留，但只负责菜单与显隐切换，不承担信息展示。

因此这条差异**不再是卖点缺口，而是两个平台各用符合自身惯例的形态**：macOS 是菜单栏文字 + 点击弹出面板，Windows 是可置顶的桌面小部件。

仍需注意的是，宣传材料中不要把「菜单栏实时倒计时」写成跨平台一致的能力——Windows 上它叫别的东西，长得也不一样。P2 结束时仍应实机评估两者的实际观感。

### WebView 差异

| 风险 | 状态 | 应对 |
|---|---|---|
| canvas emoji 光栅化 | **已解决** | [lib/moods.ts](../lib/moods.ts) 已用 `public/emoji/*.png` 绕开——当初为 iOS Safari 做的修复，WKWebView 同属 Safari 引擎家族，直接受益 |
| `ClipboardItem`（分享图复制） | 需处理 | 已有能力检测，WKWebView 下降级为「保存到文件」 |
| `backdrop-filter`（玻璃拟态） | 需实机验证 | 两个 webview 均支持，但渲染效果有差异 |
| framer-motion 掉帧 | 需实机验证 | 尊重 `prefers-reduced-motion`；托盘常驻态本就不该有动画 |
| `window.location.search`（分享落地） | 需确认 | [off-work-countdown.tsx:161](../components/off-work-countdown.tsx#L161) 读取查询串。Tauri 用 asset 协议加载本地文件，查询串行为需实测；桌面端本身不处理分享落地，必要时按目标关闭该分支 |

### 其他风险

| 风险 | 等级 | 应对 |
|---|---|---|
| Rust 学习曲线超预期 | 低 | 决策 2 已把 Rust 面积压到最小（定时器 + 托盘 + 插件配置）。若 P1 结束仍无进展，架构决策 1 对 Electron 同样适用，沉没成本仅限 P1 |
| 静态导出后 19 语言路由回归 | 中 | 桌面端直接加载 `dist/{lang}/index.html`，绕开 middleware；P0 需加冒烟检查 |
| 签名与公证流程卡壳 | 中 | 公证是 Apple 侧的异步流程，首次配置容易反复。P4 预留 2 周而非 1 周 |

## 6. 成本

| 项目 | 年费 | 不做的后果 |
|---|---|---|
| Apple Developer（macOS 公证） | $99 | Gatekeeper 拦截，用户需右键打开，安装转化大幅流失 |
| Windows 代码签名 | $200–400（Azure Trusted Signing 更低） | SmartScreen 红色警告 |
| Tauri 更新签名密钥 | **免费** | 自签密钥，与代码签名是两回事，不要混淆 |

**低成本过渡路径**：首个 Beta 可不签名，走 Homebrew Cask（对未签名应用较宽容）+ 文档说明绕过步骤，验证需求后再投入证书。**但不要在正式 1.0 上省这笔钱**——它直接换算成安装转化率。

## 7. 发布与分支策略

### 结论：同一个分支，两条独立的发布触发

**不为桌面端开长期分支。** 桌面端本质是「Web 应用 + 一个 Rust 外壳」，`components/`、`lib/`、`app/[lang]/` 与 19 份语言文件全部共用，独有的只有 `src-tauri/` 和构建配置。开两条长期分支意味着每个 UI 修复都要搬运一次，这个成本会随时间复利增长，最终两端必然漂移。决策 1 的构建目标拆分，正是让单分支成立的机制——同一份源码，两种产物。

但**发布节奏必须解耦**：Web 端合并即上线、用户无感知；桌面端每次发布都是一个需要用户下载或更新的签名产物，不该为一个错别字发一版。

| | 触发 | 产物 | 频率 |
|---|---|---|---|
| **Web** | 推送到 `main` | Vercel 生产部署 | 每次合并（现状即如此） |
| **桌面端** | 推送 tag `desktop-v*` | GitHub Release + 安装包 | 攒到有值得下载的内容时 |

### 版本号：各自独立

桌面端的版本写在 `src-tauri/tauri.conf.json`，更新器靠它比较新旧。Web 端没有用户可见的版本概念。**不要强行共用一个号**——否则要么为了对齐版本发一堆无意义的桌面版，要么号本身失去意义。

tag 用 `desktop-v1.2.0` 而非裸 `v1.2.0`，为将来可能出现的其他发布物留出命名空间。

### GitHub 上的最终形态

```
Releases
└── desktop-v1.0.0
    ├── Off Work Countdown_1.0.0_aarch64.dmg      macOS Apple Silicon
    ├── Off Work Countdown_1.0.0_x64.dmg          macOS Intel
    ├── Off Work Countdown_1.0.0_x64-setup.exe    Windows (NSIS)
    ├── Off Work Countdown_1.0.0_x64_en-US.msi    Windows (MSI)
    ├── latest.json                                更新器读取的清单
    └── *.sig                                      各产物的更新签名
```

应用内的自动更新指向 `https://github.com/ififi2017/Off-Work-Countdown/releases/latest/download/latest.json`，由 `tauri-plugin-updater` 定期拉取比对。

### 两条工作流

**① 扩展现有的 [ci.yml](../.github/workflows/ci.yml)**：在 lint / test / build 之外增加一步 `npm run build:desktop`。

这一步**不编译 Rust**，只跑静态导出，几十秒即可完成，且只需 ubuntu runner。它的价值在于：桌面端最常见的破坏方式是有人加了一个 `force-dynamic` 路由或改了 middleware——这类问题会在每个 PR 上几秒内暴露，而不是等到某天打 tag 时才在二十分钟的 Rust 构建里发现。

**② 新增 `release-desktop.yml`**：`on: push: tags: ['desktop-v*']`，用 `tauri-apps/tauri-action`，矩阵覆盖 macOS arm64 / macOS x64 / Windows x64。

必须**只在 tag 上触发**：来自 fork 的 PR 拿不到仓库 secrets，若让它跑发布流程只会得到一堆签名失败。

需要的 secrets：

| 用途 | Secret |
|---|---|
| 更新签名（免费自签） | `TAURI_SIGNING_PRIVATE_KEY`、`TAURI_SIGNING_PRIVATE_KEY_PASSWORD` |
| macOS 代码签名 | `APPLE_CERTIFICATE`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_SIGNING_IDENTITY` |
| macOS 公证 | `APPLE_ID`、`APPLE_PASSWORD`（应用专用密码）、`APPLE_TEAM_ID` |
| Windows 代码签名 | 取决于所选方案（证书文件或 Azure Trusted Signing） |

### 成本：Actions 这块是零

本仓库是**公开仓库**，GitHub Actions 免费额度不限量，**包括 macOS runner**。这点值得单独说明：私有仓库的 macOS runner 按 10 倍分钟数计费，若哪天转为私有，发布流程的成本结构会完全不同。

真正的成本仍然只有 §6 的证书与开发者账号。

### 需要接受的一个后果

桌面端会滞后于 Web 端——用户装的是 v1.0，而 Web 已经往前走了几周。这是解耦节奏的必然代价，缓解手段有两个：自动更新会把差距收敛；而分享链接按决策 6 本就指向网站，接收者用浏览器打开，不受桌面端版本影响。

真正需要留意的是**不要让桌面端独有的行为反过来影响 Web 端的数据契约**，比如分享 URL 的编码格式——那类改动应当始终以 Web 端为准。

## 8. 验收标准

1. `npm run build:desktop` 产出的静态站点可直接用浏览器打开，19 种语言均正常
2. Web 端构建不受影响：middleware、`/api/e`、`/manifest.json` 行为不变
3. **主窗口内容铺满，四周无留白**——不出现浏览器版那种「大片背景中间浮一张卡」的观感
4. macOS 菜单栏显示走字的剩余时间；点击图标弹出迷你窗并对齐到图标下方，失焦自动隐藏
5. Windows 迷你窗可拖动、位置被记住、置顶可开关、不占用任务栏
6. **关闭主窗口后，菜单栏／迷你窗仍在走字**
7. 到达下班时刻时发出系统通知，**主窗口处于关闭状态**
8. 开机自启可开关；全局快捷键可唤起/隐藏
9. 应用能从上一版本自动更新到下一版本
10. 两个平台的安装包均已签名，安装时无安全警告
11. 打 tag 后 CI 自动产出全部安装包

## 9. 未决问题

- 排除机制选方案 A 还是 B——需要一次最小可行性实验（P0 第一件事）
- Windows 托盘方案在实机上是否可接受（P2 结束时判断）
- 桌面端是否需要「多班次」（不同日期不同时间）。Web 端此项未做，桌面端若要做，两端的数据模型应当一致，不应分叉
- 是否发布 Linux 版本——建议等 macOS/Windows 有真实用户量后再定
- `dev` 分支目前无人使用，但 [ci.yml](../.github/workflows/ci.yml) 仍在监听它。近期流程都是「功能分支 → PR → main」。建议要么明确启用，要么删掉并从 CI 触发条件中移除，避免留一条谁都不看的分支
