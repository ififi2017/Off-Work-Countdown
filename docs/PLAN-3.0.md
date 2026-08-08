# Off Work Countdown 3.0 升级计划

> 状态：草案 · 起草于 2026-08-08 · 基线版本 `0.3.0`（[package.json](../package.json)）

---

## 0. 一句话目标

把一个「打开网页看倒计时」的单页工具，升级成**搜得到、留得住、传得出去、并且能常驻桌面**的产品。

3.0 是一次定位升级而不是功能堆叠。三个可量化的北极星指标：

| 指标 | 现状（估） | 3.0 目标 |
|---|---|---|
| 自然搜索月曝光 | ≈ 0（爬虫看到空页） | 有 19 语言 × 可索引页被收录 |
| 次周回访率 | 无数据 | 建立埋点并 > 15% |
| 分享链接回流转化 | 有 UTM 无落地 | 分享点击 → 启动倒计时 > 20% |

---

## 1. 现状诊断（实测，非推测）

### 1.1 致命项：服务端渲染产出为空

[components/off-work-countdown.tsx:378](../components/off-work-countdown.tsx#L378) 的 `if (!isMounted) return null;`，叠加 13 个组件全部 `"use client"`，导致：

```
线上 https://off.rainif.com/en
总响应        20931 字节
剥离 script/style 后正文  56 字符
<h1> 数量     0
JSON-LD       无
```

19 个语言 URL 全是空壳。Google 虽能执行 JS，但会推迟索引、降低权重；Baidu、社交预览抓取器、以及 GPTBot / ClaudeBot / PerplexityBot 这类 AI 检索爬虫基本不跑 JS，看到的就是白页。

**这一条同时卡住了 SEO 和桌面端**——`output: 'export'` 的静态导出同样会产出空 HTML。修一次，两处受益。

### 1.2 资源与配置缺陷

| 问题 | 位置 | 影响 |
|---|---|---|
| OG 图声明 1200×630，实际 894×1092 竖图 | [app/[lang]/layout.tsx](../app/[lang]/layout.tsx) | X/Telegram/Slack 大卡按 2:1 中心裁切，只露中间一条 |
| OG 图托管在 GitHub raw | 同上 | 外部依赖，抓取不稳定 |
| `icon-512x512.png` 实为 192×192（与 192 图 md5 相同） | [public/](../public/) | PWA 安装横幅、Android 启动图、iOS 主屏图标全是糊的 |
| `sitemap.ts` 无 `alternates.languages` | [app/sitemap.ts](../app/sitemap.ts) | hreflang 信号弱 |
| 另有一份手写 `hreflang-sitemap.xml` 做同样的事 | [app/hreflang-sitemap.xml/route.ts](../app/hreflang-sitemap.xml/route.ts) | 两份易不同步 |
| `lastModified: new Date()` | [app/sitemap.ts](../app/sitemap.ts) | 每次抓取都「刚更新」，信号会被忽略 |
| 无 JSON-LD 结构化数据 | — | 拿不到富摘要 |

### 1.3 产品缺口

- **病毒闭环是断的。** [lib/share.ts](../lib/share.ts) 认真做了 UTM，但分享链接落到的是一个空配置页，而不是「对方还有 2 小时 13 分下班，你呢？」的接力页。
- **URL 不承载状态。** 用户无法把自己的班次发给同事。
- **提醒只在页面开着时有效。** Serwist 已就位（[app/sw.ts](../app/sw.ts)）但未用于推送。
- **冷流量落地无解释。** 搜索进来第一眼是表单，没有一句话说明、没有截图。

### 1.4 工程与仓库

- `electron/`、`scripts/`、`types/` 三个空目录，未被 git 跟踪 —— 早期 Electron 尝试的残留，应清理。
- `out/` 是 5 月的静态导出残留，当前 `next.config.mjs` 已无 `output: 'export'`。
- CI（[.github/workflows/ci.yml](../.github/workflows/ci.yml)）有 lint + test + build，但**无发布自动化、无多平台矩阵**。
- 测试仅覆盖 [lib/countdown.test.ts](../lib/countdown.test.ts) 与 [lib/share.test.ts](../lib/share.test.ts)，纯函数层。
- GitHub 仓库 8 star、**0 个 topics**、Discussions 未开、无社交预览图。

---

## 2. 关键架构决策

### 决策 A：拆分 Web 与 Desktop 两个构建目标

桌面端需要 `output: 'export'`，而静态导出**不支持 middleware，也不支持 `force-dynamic` 路由处理器**。当前项目两样都在用：

- [middleware.ts](../middleware.ts) —— 基于 Accept-Language 的语言重定向
- [app/manifest.json/route.ts](../app/manifest.json/route.ts)、[app/robots.txt/route.ts](../app/robots.txt/route.ts) —— 均为 `force-dynamic`

**方案**：引入 `BUILD_TARGET` 环境变量。

| | `web`（Vercel） | `desktop`（Tauri 内嵌） |
|---|---|---|
| 输出 | 默认（含 middleware） | `output: 'export'` |
| 语言路由 | middleware 协商 | 直接加载 `/{lang}/index.html`，语言由 Tauri store 持久化 |
| manifest / robots | 动态路由 | 不打包 |
| Service Worker | Serwist 启用 | 关闭（Tauri 自带更新器） |

副产物：静态导出天然要求页面能在无服务端上下文时渲染，这会**倒逼 1.1 的修复真正做干净**。

### 决策 B：桌面端技术栈 = Tauri v2

选型对比与理由见本节末。核心判断：**这是一个开一整天的常驻托盘应用**，Electron 的 200–300MB 常驻内存与「轻量摸鱼工具」的定位直接冲突，也是用户卸载的常见理由。

Rust 侧职责边界（预计 ≈ 250 行，不含配置）：

```
src-tauri/src/
├── main.rs        # 应用引导、单实例、窗口生命周期
├── tray.rs        # 托盘图标 + 菜单栏标题秒级刷新（macOS set_title）
├── timer.rs       # 后台计时循环，窗口关闭后仍存活
└── settings.rs    # 班次/薪资配置读写（tauri-plugin-store）
```

业务逻辑**不下沉到 Rust**。[lib/countdown.ts](../lib/countdown.ts) 是 69 行纯函数、已有单测，继续作为唯一事实来源；Rust 只在托盘刷新时调用一次 IPC 拿格式化字符串，或直接接收前端 push 的字符串。

依赖的官方插件：`tray-icon`(core) / `notification` / `autostart` / `global-shortcut` / `updater` / `store` / `single-instance`。

**为什么不是 Electron**：唯一强论据是零新语言 + 单一渲染引擎（所见即所得）。若约束为「两周出货且绝不碰 Rust」则它成立，但与产品定位冲突。

**为什么不是 Wails (Go)**：v3 仍 alpha；自动更新需自建；macOS 菜单栏标题支持弱。Go 的并发与标准库优势对一个 UI 壳无价值。除非团队本身是 Go 栈，否则没有理由优先于 Tauri。

**WKWebView 兼容风险与缓解**：

| 风险 | 缓解 |
|---|---|
| canvas emoji 光栅化 | **已解决** —— [lib/moods.ts](../lib/moods.ts) 已用 `public/emoji/*.png` 绕过（同一 Safari 引擎家族） |
| `ClipboardItem`（[ShareDialog.tsx:198](../components/ShareDialog.tsx#L198)） | 已有能力检测；WKWebView 下降级为「保存到文件」 |
| `backdrop-filter` 玻璃拟态 | WebView2 与 WKWebView 均支持，需实机验收 |
| framer-motion 掉帧 | 尊重 `prefers-reduced-motion`，托盘常驻态降级为纯 CSS 动画 |

---

## 3. 里程碑

> 工时按**单人兼职**估算。M1–M4 为纯 Web，可独立发布；M5 依赖 M1 完成。

### M1 · 地基修复 —— 1.5 周 · P0

一切增长动作的前置条件。做完之前，任何引流都在漏水。

1. **消灭空壳 SSR** — ✅ 已完成（2026-08-08）
   - 移除 `off-work-countdown.tsx` 的 `if (!isMounted) return null`
   - **根因不止于此**：[i18n.ts](../i18n.ts) 明确不在服务端加载翻译，只删 `return null` 会输出 `offWorkCountdown` 这类原始 key。改为在 layout 中用 [lib/server/i18n.ts](../lib/server/i18n.ts) 读文件，经 `resources` prop 注入 [I18nProvider](../components/I18nProvider.tsx)，并在渲染期（非 effect）同步灌入，保证首帧与 SSR 一致
   - 服务端每次渲染新建 i18n 实例，避免 Node 进程内单例被并发请求改写导致语言串台
   - `app/layout.tsx` 合并进 `app/[lang]/layout.tsx`（Next 官方 i18n 结构），使 `<html lang>` / `<html dir>` 服务端渲染；顺带启用阿拉伯语 RTL，并把主流程的 `space-x-*` / `mr-*` / `right-*` 换成方向无关的 `gap` / `me-*` / `end-*`
   - 主题闪烁：`<head>` 内联脚本在首次绘制前给 `<html>` 打 class
   - 删除 `components/ManifestLink.tsx`（manifest link 现由服务端直接渲染）
   - 修掉 hreflang 重复输出（此前 metadata 与 root layout 各输出一份）
   - **验收结果**：19/19 语言预渲染 HTML 均含正确 `lang`/`dir`、`<h1>`、真实译文正文；构建通过、21 项测试通过、lint 干净；浏览器无 hydration 警告，深色主题无闪烁，软导航切换语言正常
   - **遗留**：正文仅 110–285 字符（页面目前只有表单标签）。要达到有竞争力的收录密度，依赖 M2 第 8 项的说明文案；`components/ui/*` 内 dialog/select 等 shadcn 组件的 RTL 适配也留待后续
2. **OG 图重做** — ✅ 已完成（2026-08-08）
   - 新增 [app/[lang]/opengraph-image.tsx](../app/[lang]/opengraph-image.tsx)，用 `ImageResponse` 生成 1200×630，19 个语言各一张，托管在自有域名
   - 删除 metadata 里写死的 GitHub raw 链接；`og:image` / `twitter:image` 现由 Next 自动注入
   - **设计取舍**：图片刻意做成语言中性（仅拉丁字母与数字）。satori 需内嵌字体才能渲染字形，19 种语言涉及 CJK/阿拉伯/天城体/泰文多套字形，全量打包代价过高；而 localized 标题与描述本就通过 `og:title` / `og:description` 交给平台用系统字体渲染，图片只承担视觉部分
   - 已知小瑕疵：satori 默认字体只有常规字重，`fontWeight` 不生效。观感仍佳（层级靠字号拉开），如需加粗需另行打包一套静态字重字体
3. **补齐真实 512×512 图标** — ✅ 已完成（2026-08-08）
   - 原 `icon-512x512.png` 实为 192×192（与 192 图 md5 相同）。以 ImageMagick 绘图基元按原设计重绘为真正的 512×512
   - **顺带修掉一个 PWA 反模式**：原 manifest 给两张图都标了 `purpose: "any maskable"`。maskable 图会被平台按自身形状（Android 圆形）裁切，需要满幅背景且内容落在 80% 安全区内，与保留透明圆角外形的 "any" 图无法共用。已拆为 `any`（192/512）+ 新增 `icon-maskable-512x512.png`（`maskable`，满幅白底，橙环半径 168 < 安全区 205）
   - 同步放宽 [middleware.ts](../middleware.ts) 的静态资源正则：原 `^\/icon-\d+x\d+\.png$` 匹配不到带 `maskable` 的新文件名，会被重定向成 404
4. **清理陈旧目录** — ✅ 已完成（2026-08-08）
   - `electron/`、`scripts/`、`types/` 三个空目录已不存在（git 不跟踪空目录，开发过程中的一次 `git stash -u` / `pop` 已将其清除）
   - 删除 `out/`（159 个文件，2026-05-17 的静态导出残留）。已确认：被 gitignore、当前 `next.config.mjs` 无 `output: 'export'` 故不会再生成、唯一引用是 eslint 的忽略规则
   - **保留** [eslint.config.mjs](../eslint.config.mjs) 中的 `out/**` 忽略项 —— M5 桌面端按决策 A 会重新启用静态导出，届时仍需要

**附带完成**：移除 [i18n.ts](../i18n.ts) 模块加载时的翻译预取（服务端已注入，属重复请求），并加上 `initImmediate: false`。后者是必需的：i18next 默认把 `init()` 内部的语言加载推迟到下一个 tick，那时 `changeLanguage` 包装器已装上、React 却尚未渲染注入资源，既会多发一次请求，拉回的译文还会在 hydration 之后替换文本，造成 hydration 不匹配。改为同步初始化后两个问题一并消失。

### M2 · 可被发现 —— 2 周 · P0

5. **JSON-LD** — ✅ 已完成（2026-08-08）
   - 在 [app/[lang]/layout.tsx](../app/[lang]/layout.tsx) 注入 `WebApplication` schema，含 `offers.price: 0`、`isAccessibleForFree`、`inLanguage`、`license`、`codeRepository`
   - 序列化时转义 `<`，防止译文里出现 `</script>` 截断脚本块
   - 19/19 语言的 JSON-LD 均可正确解析，`inLanguage` 与 `url` 逐一匹配
6. **sitemap 合并** — ✅ 已完成（2026-08-08）
   - 统一到 [app/sitemap.ts](../app/sitemap.ts)，补 `alternates.languages` + `x-default`；删除手写的 `app/hreflang-sitemap.xml/route.ts`
   - 产出 20 条 `<url>`、400 个 hreflang、20 个 x-default —— 每条 URL 都完整列出全部 alternates
   - `robots.txt` 只声明一份 sitemap；顺带移除其 `force-dynamic`，该路由无请求相关数据，现已变为静态预渲染
   - **迁移处理**：`/hreflang-sitemap.xml` 曾写在 robots.txt 中、搜索引擎大概率已收录。仅从 middleware 排除列表移除会导致它被加上语言前缀重定向到不存在的路径（307 → 404 链）。已在 [next.config.mjs](../next.config.mjs) 加 308 永久重定向指向 `/sitemap.xml`（next.config 的 redirects 先于 middleware 执行）
   - 关于 `lastModified`：原诊断说「每次抓取都变成刚更新」**不准确** —— `/sitemap.xml` 是静态预渲染的，时间戳在构建时即固化。真实的（较弱的）问题是每次部署会刷新全部条目。已收敛为单个构建期常量，待内容页有独立更新节奏后再改为按页维护
7. **内容层** — ✅ 已完成（2026-08-08）
   - 范围：2 个页面 × 2 种语言。`/about`、`/changelog` 暂缓——SEO 价值低于前两者，且 changelog 需持续维护，否则很快过期变成负资产
   - **内容页只做中英两版**（[lib/content-locales.ts](../lib/content-locales.ts)）。这是刻意取舍而非未译完：长文案的翻译质量与维护成本远高于 UI 字符串，铺到 19 种语言只会产出大量无人校对的稿子。应用界面本身仍是 19 种语言
   - 语言路由：中文界面（含 zh-TW / zh-HK）指向 `/zh-CN/*`，其余 16 种语言指向 `/en/*`，由界面直接生成正确链接，不经跳转重定向。内容页右上角提供 English / 中文 切换
   - 内容页是**纯服务端组件**，无客户端 i18n、无交互，全部文案随首屏 HTML 产出。文字量 799–3241 字符/页，对比主应用页的 110–285
   - FAQ 页附 `FAQPage` schema（10 组问答），Google 可在结果里折叠展示
   - `dynamicParams = false`：其余 17 种语言的内容页 URL 直接 404，而不是在该语言 URL 下渲染英文——后者会让搜索引擎收录语言与内容不符的页面
   - 返回链接指向 `/`，由 middleware 依据 `i18nextLng` cookie 把用户送回他自己的界面语言，而不是内容页所用的中英文
   - **补上内链**：应用首屏（服务端渲染的设置态）底部提供两个入口，文案按界面语言本地化，19 种语言均已验证。此前建了页面却没从应用链过去，会让它们成为孤儿页，抓取权重明显打折
   - **顺带修掉一个既有 bug**：middleware 会把非语言码的首段当作「写错的语言前缀」剥离，导致 `/faq` 重定向到 `/en` 而非 `/en/faq`。站内此前只有 `/[lang]` 一种路由所以未暴露。已改为统一补全语言前缀
8. **落地页说明区** —— 首屏表单下方加一句话价值主张 + 3 张截图 + 「为什么要用」。降低冷流量跳出率 —— 待办

### M3 · 分享闭环 —— 2 周 · P1

9. **预设路由**（同时吃搜索词与承载状态）
   ```
   /zh-CN/996        /zh-CN/朝九晚六     /zh-CN/双休
   /en/9-to-5        /en/night-shift     /en/4-day-week
   ```
   每个既是独立可索引落地页，又是可直接发给同事的链接
10. **可分享状态 URL** —— `/{lang}/{preset}?s=0900-1800`，落地页直接渲染对方倒计时
11. **接力落地页** —— 带 `?from=share` 时展示「TA 还有 2 小时 13 分下班」+「我也来」一键按钮。**这是当前病毒循环唯一缺失的一环**
12. **分享后回访埋点** —— 打通 `share → click → start` 漏斗

### M4 · 留存 —— 2 周 · P1

13. **Web Push** —— 基于已有 Serwist SW，实现关页也能收到的下班/15 分钟提醒。这是「用一次」到「每天用」的分水岭，也是安装 PWA 的真实理由
14. **周期性总结** —— 「本周摸鱼 X 小时」「今年已赚 ¥X」，天生具备分享欲，反哺 M3
15. **多班次配置** —— 支持工作日/周末不同班次，倒班制轮换

### M5 · 桌面端 —— 4–6 周 · P1

> 依赖 M1 完成（静态导出必须能产出真实 HTML）

16. **构建目标拆分** —— 落地决策 A 的 `BUILD_TARGET` 方案
17. **Tauri v2 骨架** —— `src-tauri/` 脚手架，加载静态导出产物，单实例守护
18. **菜单栏/托盘实时倒计时** —— **桌面端的核心卖点**。macOS 菜单栏直接显示 `2:13:45`，Windows 托盘悬浮显示；秒级刷新走 Rust 侧计时循环，与 webview 是否可见解耦
19. **原生能力** —— 系统通知、开机自启、全局快捷键（唤起/隐藏）、关闭到托盘而非退出
20. **窗口形态** —— 默认小尺寸常驻窗 + 「专注模式」置顶迷你悬浮窗
21. **自动更新** —— `tauri-plugin-updater`，更新源托管在 GitHub Releases
22. **签名与公证**（见 §4 成本）
23. **发布 CI** —— `tauri-action`，macOS(arm64 + x64) / Windows(x64) 矩阵，打 tag 自动出 Release

### M6 · 分发与增长 —— 持续

24. **仓库门面** —— 补 topics（`countdown` `pwa` `nextjs` `tauri` `productivity` `work-life-balance` `i18n`）、社交预览图、README 顶部 live demo 徽章 + 演示 GIF、开启 Discussions
25. **包管理器上架** —— Homebrew Cask、Scoop、winget
26. **中文渠道（主场）** —— 小红书 / 抖音 / B站 短视频演示、少数派、V2EX、即刻。「下班倒计时」「摸鱼」本身就是中文互联网的梗，传播成本最低
27. **英文渠道** —— Product Hunt、Show HN、r/productivity、alternativeto.net、awesome-nextjs / awesome-tauri 列表

---

## 4. 成本与风险

### 必要现金支出（桌面端）

| 项目 | 年费 | 不做的后果 |
|---|---|---|
| Apple Developer（macOS 公证） | $99 | Gatekeeper 拦截，用户需右键打开，安装转化大幅流失 |
| Windows 代码签名证书 | $200–400（Azure Trusted Signing 更低） | SmartScreen 红色警告 |

**低成本过渡**：首个 Beta 可不签名，走 Homebrew Cask（对未签名应用较宽容）+ 文档说明绕过步骤，验证需求后再投入证书。**但不要在正式 1.0 上省这笔钱**——它直接换算成安装转化率。

### 主要风险

| 风险 | 等级 | 应对 |
|---|---|---|
| 静态导出后 19 语言路由回归 | 中 | 桌面端直接加载 `/{lang}/index.html`，绕开 middleware；加 E2E 冒烟 |
| WKWebView 与 WebView2 渲染差异 | 中 | M5 早期即在两平台实机验收，不留到最后 |
| Rust 学习曲线超预期 | 低 | 面积仅 ≈250 行且官方插件覆盖；若两周内无进展，退回 Electron（架构决策 A 对两者通用，沉没成本低） |
| SSR 改造引入 hydration 不一致 | 中 | 补组件级测试；`suppressHydrationWarning` 只用于确需的节点 |
| 摊子铺太大，单人兼职做不完 | **高** | M1+M2 已能解决最大瓶颈。**若只能做一半，做前两个里程碑** |

---

## 5. 建议执行顺序

```
M1 地基 ──┬── M2 SEO ── M3 分享闭环 ── M4 留存
          │
          └── M5 桌面端（可与 M2–M4 并行）
                                              └── M6 分发（贯穿）
```

**如果时间有限，严格按 M1 → M2 → M3 推进。** 前面不修，后面引来的流量会大量流失在空壳页和断掉的分享闭环上。

M5 桌面端虽然是最有存在感的功能，但它服务的是**已有用户的留存深度**，而非拉新——在 M1/M2 打通获客之前做桌面端，是给一个还没有人来的房子装修。

---

## 6. 版本号说明

当前 [package.json](../package.json) 为 `0.3.0`。「3.0」是产品代际命名而非 semver 延续。建议在 M1 合并时直接跳到 `3.0.0-alpha.1`，M4 完成发 `3.0.0`（Web），M5 完成发 `3.1.0`（含桌面端），并在 `/changelog` 页对外解释这次跳版本的原因——这本身也是一条可传播的内容。
