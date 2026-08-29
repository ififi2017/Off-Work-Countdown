# 009 — DoneAt 全平台品牌与双域分工

- **Status**: IN PROGRESS — 2026-08-29 官网已独立运作；产品仓 Web P3 正在落地
- **Reviewed against**: 2026-08-28 工作区；[007 Grill](007-ios-stable-before-subscription.md#grill-locked)；[008](008-brand-doneat.md)；2026-08-28 域名响应头实测；2026-08-28 第二至八轮 Grill
- **Severity**: HIGH（双域 canonical 配错会稀释既有 SEO；桌面改包身份会切断升级与用户状态）
- **Category**: 品牌 / Web 主域 / Desktop 外表面 / 商店与发布
- **Estimated scope**: 产品仓 `config/site.ts`、内容页 301、Web metadata / manifest / sitemap / 分享链路、19 份 UI 与 SEO 文案、Tauri / MSIX / macOS 本地化、Microsoft Store listing、README；官网仓 [`ififi2017/doneat.app`](https://github.com/ififi2017/doneat.app)（Astro + TypeScript + Tailwind）+ 独立 Vercel 项目；Cloudflare 域名；`hello@doneat.app`
- **相关**: 007 / 008 先完成 iOS DoneAt 外表面与品牌资产；本计划不重做图标，不改变 002 / 006 的产品功能节奏。007 不等本计划

## 一句话

让 **DoneAt** 成为 Web、Windows、macOS 和商店里的唯一品牌；`doneat.app` 做官方品牌与商店下载入口，`off.rainif.com` 继续承载可直接使用的 Web App 和既有搜索资产。两域各守自己的 canonical，不搬 Web 本地数据，不在官网上放 GitHub 直装。

## Grill 锁定（2026-08-28）

<a id="grill-locked"></a>

未写进这里的旧口头约定和本文上一稿里的「待答」作废。尤其作废：同一 Next 应用按 Host 分流、官网放 GitHub 直装、品牌句进 19 份翻译、安装后显示名可以晚于商店 listing 再改。

### G1 — DoneAt 是全产品唯一品牌

| 层级 | 英文 | 简中 |
| --- | --- | --- |
| 品牌 / App 显示名 | **DoneAt** | **DoneAt** |
| 副标题或 SEO 解释 | Work Shift Countdown | 下班倒计时 |
| 功能名 | countdown, shift timer | 下班倒计时、班次计时 |
| 品牌句 | Know when your time is yours | 几点下班，心里有数（台湾／香港各写当地用词；不是英文直译） |

品牌名不随系统语言翻译。Finder、开始菜单、菜单栏、窗口标题、托盘、安装器显示名一律 `DoneAt`，不再从 `offWorkCountdown` 生成本地化 App 名。界面里的「下班倒计时」「设置」「今日已赚」仍是中文。

`offWorkCountdown` 继续做功能行：en 从 `Off Work Countdown` 改成 `Work Shift Countdown`；zh-CN / ja / ko 等已经是功能词的保留。品牌句不进 19 份 `translation.json`。`again` 仍留给 002。

英文门厅：DoneAt + 品牌句 + Work Shift Countdown。中文门厅：DoneAt + 原创品牌句 + 功能行。过渡版本可写一次「Off Work Countdown 现为 DoneAt」，之后不长期双品牌并列。

### G2 — 双域按职责并存

| 域名 | 固定职责 | 不承担 |
| --- | --- | --- |
| `https://off.rainif.com` | 19 语言可交互 Web App、PWA、班次分享链接、预设页 `/{lang}/{preset}` | 下载主站、正式隐私与支持入口、品牌门厅 |
| `https://doneat.app` | 品牌门厅、商店下载、隐私、支持、About / FAQ / How it works | 第二份 Web App、第二个 PWA、本地排班或薪资、GitHub 直装入口 |

- `https://www.doneat.app/*` 永久跳到裸域，完整保留 path + query。
- 拆除 Cloudflare 现在这条指向 `off.rainif.com/`、且丢 path/query 的临时 302。
- 分享、PWA、WebApplication JSON-LD 用 `webAppUrl`；下载、隐私、支持、SoftwareApplication / Organization 用 `officialSiteUrl`。
- 不能声明全站唯一 canonical origin。每条路由只认职责域；另一域要么不提供，要么永久跳到职责域。
- Search Console 不做整站 Change of Address。
- **Web App 上的 App 下载营销全部指向 `doneat.app`**（与官网同一天切，不要提前指到仍在 302 的门厅）：`/{contentLang}/download` 301；设置态上的 Mac App Store / Microsoft Store badge、「更多版本」、About 页的商店入口都改成去官网，不再在 Web App 里直达商店或弹出 GitHub 直装。GitHub 直装只留在产品仓 README / Releases。分享落地和 PWA「加到主屏幕」不是下载营销，仍留在 `off.rainif.com`。

产品仓把含义模糊的单一 `baseUrl` 拆开：

```ts
brandName: "DoneAt"
webAppUrl: "https://off.rainif.com"
officialSiteUrl: "https://doneat.app"
```

### G3 — 五页长文全部归官网

| 路由 | `off.rainif.com` | `doneat.app` | canonical |
| --- | --- | --- | --- |
| `/{lang}` | 可交互 Web App | 品牌门厅 | 内容不同，各认自己的域 |
| `/{lang}/{preset}` | 保留 | 不复制 | `off.rainif.com` |
| `/{contentLang}/download` | 永久跳转 | 正式页面 | `doneat.app` |
| `/{contentLang}/privacy` | 永久跳转 | 正式页面 | `doneat.app` |
| `/{contentLang}/about` | 永久跳转 | 品牌 / 开源说明 | `doneat.app` |
| `/{contentLang}/faq` | 永久跳转 | 跨平台 FAQ | `doneat.app` |
| `/{contentLang}/how-it-works` | 永久跳转 | 统一原理说明 | `doneat.app` |

长文仍只有 `en` / `zh-CN`。门厅壳层 19 语。其他 UI 语言的长文链接按现有 `content-locales.ts` 落到英文或简中。旧 URL 必须保留语言、path、query；不存在的语言版本不能 301 到假 URL。

FAQ 按现有问题骨架重写：改掉「网页工具、不用下载」这类口径，把 iOS / 桌面写成正式用法；不写 Widget、灵动岛、007 计时态。301 必须等这版重写上线。

内容页「返回倒计时」指向 `off.rainif.com` 的 Web App。

### G4 — 稳定技术身份一律不改

即使含有旧品牌，也当作兼容 ID 保留：

- `com.rainif.offworkcountdown` 与 `com.rainif.offworkcountdown.macappstore`
- Widget bundle id 与 `group.com.rainif.offworkcountdown.macappstore`
- MSIX `Identity Name="finiaRStudio.OffWorkCountdown"`、Application Id、StartupTask Id
- **Windows exe 文件名** `Off Work Countdown.exe`
- Rust package / library 名、Tauri store 的 `desktop-state.json`
- Web / Desktop 现有 localStorage 键与 Tauri Store 字段
- 产品仓 slug `ififi2017/Off-Work-Countdown` 及 updater 的 `latest.json` / `latest-cn.json`

`productName` / DisplayName / 窗口标题 / 开始菜单 / 托盘 / 安装器显示名要改成 DoneAt。GitHub 产物文件名会跟着变成 `DoneAt_{version}_{arch}…`。升级靠 identifier 认回原数据，不要求用户重装。

### G5 — 拆 302 的那天必须同一窗口落地

007 不等 009。iOS 店内 About / 隐私在 007 仍指 `off.rainif.com`；域名活了之后的下一次 iOS 再改硬编码。

官网仓是 **`ififi2017/doneat.app`**（公开，和产品仓放进同一个 GitHub Project），另接一个 Vercel 项目。技术栈：**Astro + TypeScript + Tailwind CSS**，静态输出；长文用 Content Collections（`en` / `zh-CN` Markdown/MDX）；门厅 19 语走 Astro i18n 路由。亮暗只跟 `prefers-color-scheme`。不要用产品仓的 Next App Router、Serwist、`next-i18next` 或倒计时组件，不注册 Service Worker / 可安装 manifest。五页长文迁移时拷贝到新仓，之后以新仓为准；产品仓对应路径只 301。门厅 19 语文案由官网仓自己维护一份薄目录。

**同一天切的内容：**

1. `doneat.app` 品牌门厅上线；Cloudflare 只做 DNS 和 www→裸域 301。
2. 五页内容 301 到官网（FAQ 已按 G3 重写）。
3. 产品仓 Web UI / PWA `name` `short_name` / SEO `siteName` 改为 DoneAt；keywords 只增不删。
4. 下一发桌面包：logo、DisplayName、窗口 / 开始菜单 / 托盘 / 安装器显示名 = DoneAt；Microsoft Store listing 为 `DoneAt: Work Shift Countdown`（其他语言 `DoneAt: {该语功能副标题}`）。GitHub 渠道照发，只供 updater。
5. 下载页只放 App Store（iPhone / iPad / Mac）、Microsoft Store、Web App。
6. 隐私页和商店材料改成 `hello@doneat.app`；`offwork@rainif.com` 只做转发，不再展示。**邮箱能收信之前，隐私页不准切。**
7. 产品仓 README / Release 说明写清品牌升级，口径对齐 iOS。

官网**长期**不把 GitHub 直装当一等入口；直装只留在产品仓 README / Releases。桌面包具体版本号实现时再定。

## 为什么必须单独立项

008 的「全平台」只覆盖图标位图；短名只落在 iOS 外表面。007 又明确把 Web、Desktop、
共享文案和 Tauri `productName` 排除在 3.1.7 外。因此当前是同一产品的分裂身份：

| 表面 | 当前状态 |
| --- | --- |
| iOS 主屏幕、启动页、Widget、Live Activity、App Store Connect 3.1.7 材料 | **DoneAt** |
| Mac App Store 商店主名 | 因 Universal Purchase 与 iOS 同一记录，跟随 **DoneAt** |
| Web UI、SEO、PWA、内容页 | **Off Work Countdown / 下班倒计时** |
| GitHub 版 Windows / macOS、Microsoft Store 包与 listing | **Off Work Countdown / 本地化旧名** |
| GitHub 仓库与 Release / updater | `ififi2017/Off-Work-Countdown` |
| `doneat.app` | 只是去旧站的临时跳转，不是 canonical 主域 |

用户可见品牌可以改；功能描述不应消失；稳定技术身份不改。

## 2026-08-28 现状实测

### 域名

对 `http://doneat.app/`、`https://doneat.app/` 和 `https://www.doneat.app/` 执行
`curl -sSIL`：

1. 三者都先由 Cloudflare 返回临时 `302` 到 `https://off.rainif.com/`；
2. 旧站根路径再由应用返回 `307 /en`；
3. `doneat.app` 上的原路径与查询参数没有保留；
4. HTTPS 证书和最终 Vercel 页面可用，但方向与目标品牌相反。

这条跳转在 3.1.7 只当商店 URL 垫片可以接受，不能作为正式迁移方案。分享链接带
`?s=...&from=share&utm_*`；迁移时丢查询参数会直接破坏分享闭环。

**2026-08-29 更新：** `doneat.app` 已完成开发并独立运作。产品仓 Web 可以按本计划
P3 做 301 和改链；Cloudflare 上指向 `off.rainif.com/` 且丢 path/query 的旧 302
仍属域名侧 G5，不在这次 Web 改代码里动。

### 双域分工避开 Web 数据迁移

Web 的排班、午休、提醒、薪资、隐藏状态和主题保存在 `off.rainif.com` origin 的
`localStorage`。可交互 Web App 继续留在这个 origin，因此：

- 不需要跨域搬排班或薪资；
- 已安装 PWA 的 origin、scope、Service Worker 和本地设置保持原样；
- 新旧分享链接都继续指向 `off.rainif.com`，接收者打开就是可用的倒计时；
- `doneat.app` 不复制一份 Web App，不制造第二份 localStorage 和第二个 PWA 身份。

## 不变量

1. 这是一套品牌与入口迁移，不改倒计时、提醒、摘要或薪资算法。
2. 不增加账号，不把排班或薪资上传到服务器。
3. 分享 URL 仍只编码开始与结束时刻；绝不因迁移夹带薪资或整份设置。
4. 改名后仍是同一个安装包升级链和同一份本地数据，不要求 Desktop 用户卸载重装。
5. Web 与 Desktop 仍共用 React tree；iOS 仍是原生 SwiftUI，不把网页品牌壳搬进 iOS。
6. OS 级 Desktop 表面的**品牌词**固定为 DoneAt；功能菜单继续本地化。
7. 产品仓新增 UI copy 进 19 份 `translation.json`；官网仓自维护门厅 19 语薄目录；长文只审英文和简中。
8. `assets/brand` 和三端图标以 008 为准，不在这里再造第二套 mark。
9. `hello@doneat.app` 能收信、`offwork@rainif.com` 已转发之前，不切换隐私页上的地址。

## 拟执行阶段

P0 可先做。P1–P5 的**对外发布**必须落在 G5 的同一窗口；对内可以并行准备。

### P0 — 身份、路由与 SEO 基线

- [ ] 给每个表面标记「品牌名 / 功能描述 / 稳定 ID / canonical 域」，与上方 Grill 锁定一致。
- [ ] 把 19 份 `public/locales/*/seo.json` 当前的 title、description、keywords、siteName 和
  imageAlt 保存为评审基线；现有 keywords 只能保留或新增，不能在改名时顺手重写、翻译或删词。
- [ ] 把产品仓 `siteConfig.baseUrl` 的每个调用点归类为 Web App、官网、商店或 GitHub，确认替换目标。
- [ ] 锁定双域 sitemap、robots、hreflang、Open Graph、JSON-LD 与 redirect 矩阵。
- [ ] 明确 Search Console / Bing / 百度的双站点观察指标；不提交整站迁址。

### P1 — 官网仓与域名

- [ ] 建立公开仓 `ififi2017/doneat.app`，与产品仓放进同一个 GitHub Project；接到独立 Vercel 项目。
- [ ] Astro + TypeScript + Tailwind；静态输出。不引用产品仓倒计时树，不注册 Service Worker / 可安装 PWA manifest。
- [ ] 把 `doneat.app` / `www.doneat.app` DNS 指到官网 Vercel；确认 TLS。
- [ ] 移除 Cloudflare 当前指向旧站根路径的临时 302；`www` 永久规范到裸域并保留路径查询。
- [ ] 两域分别生成正确的 canonical、robots 与 sitemap，互不把对方整站声明为镜像。
- [ ] 增加域名响应头测试，覆盖 `http/https`、裸域/`www`、根路径/内容页、分享 query 与循环。
  分享 query 的保留验收仍在 `off.rainif.com` 上做。

### P2 — 官方首页与五页长文

- [ ] 从产品仓拷贝 `en` / `zh-CN` 的 about / faq / how-it-works / download / privacy，之后以官网仓为准。
- [ ] `doneat.app/{lang}` 品牌门厅：DoneAt mark、英文品牌句（仅 en）、功能行走各语言
  `offWorkCountdown` 语义、App Store、Microsoft Store、Web App。**不放 GitHub 直装。**
- [ ] 官网不把实现架构当卖点；先解释用户何时下班、排班与隐私收益，再给平台选择。
- [ ] FAQ 按 G3 重写后再标 canonical。
- [ ] 下载页只放商店级入口 + Web；直装区不出现。
- [ ] 内容页返回 Web App 的 CTA 指 `off.rainif.com`，不形成来回跳转。
- [ ] 长内容仍只提供英文和简中。

### P3 — 产品仓 Web 品牌、301 与 SEO

- [x] `siteConfig.name` 改为 DoneAt；`baseUrl` 拆为 `webAppUrl` 与 `officialSiteUrl`。
- [x] 19 份 UI 里作为产品名出现的地方改为 DoneAt；`offWorkCountdown` 仅保留功能词语义，en 改为
  Work Shift Countdown。
- [x] 19 份 SEO `siteName` 改为 DoneAt；title 采用 `DoneAt — {本地化功能解释}`；keywords 原样保留并可新增 `DoneAt`。
- [x] PWA manifest `name` / `short_name` 改为 DoneAt；`id` / `start_url` / `scope` 仍在 `off.rainif.com`。
- [x] Web App 的 metadata、Open Graph、WebApplication JSON-LD、sitemap、robots、hreflang 与生成图片仍指 `off.rainif.com`。
- [x] 五页旧内容 URL 在产品仓做逐路径永久跳转；产品仓不再编译这五页正文。Web App 主路由永不纳入这条跳转。
- [x] 页脚 FAQ/原理/关于/隐私改指官网；设置态下载区改成单一「获取 App」入口指向 `doneat.app`，拿掉 Web App 上的 Mac App Store badge、Microsoft Store badge 和 GitHub 直装对话框。页脚与标题栏补「访问官网」。
- [x] 分享链接继续使用 `off.rainif.com`。语言重定向保留 query 的行为未改。
- [ ] 验证原 origin 上的倒计时、主题、工资隐藏状态和离线 PWA 无需迁移且全部保留。
- [x] Tauri opener 允许名单补上 `doneat.app`（iOS About 硬编码的改写放到域名活了之后的下一次 iOS）。

### P4 — Desktop 用户可见品牌

- [x] Tauri `productName`、主窗口标题、安装器显示名与产物文件名改为 DoneAt；identifier 与
  Windows exe 名不改（`mainBinaryName` 仍为 `Off Work Countdown`）。
- [x] Windows Mini Timer、托盘、About 回退文案与 MSIX 自启动 DisplayName 改为 DoneAt。
- [x] MSIX 的 `Properties/DisplayName`、`uap:VisualElements` 与 StartupTask DisplayName 改为
  DoneAt；`Identity Name`、Application Id 与 executable 不改。升级回环仍待真机验证。
- [x] macOS Finder / Dock / Launchpad、应用菜单、About、托盘与 Widget 画廊统一 DoneAt；
  `.lproj` 继续由脚本生成，但品牌名固定为 DoneAt，不再读取 `offWorkCountdown`。
- [x] 桌面设置「关于此项目」跳转官网 About；其下增加「下载移动端」到下载页；GitHub 仓库
  按钮上方增加「访问官网」到 `doneat.app`。Web 页脚与标题栏同步。
- [x] Web favicon / PWA 图标与 Tauri 安装器、托盘图标从同一套品牌母版重出。
- [x] GitHub 渠道 NSIS 认回旧卸载项 `Off Work Countdown`：原地覆盖原目录，把开始菜单、
  卸载列表和 Run 键迁到 DoneAt，不新建第二份安装。identifier 与 exe 名不改。真机升级
  回环仍待验证。
- [x] 桌面存量用户更新后首次打开弹一次改名说明（班次还在，应用现在叫 DoneAt）；
  新装不弹，看过即写入 `desktop-state.json`，不再出现。
- [ ] Mac App Store、Microsoft Store、GitHub 三渠道分别构建；商店渠道继续裁掉 updater，
  GitHub 渠道继续从旧仓库 endpoint 更新。
- [ ] 升级安装必须复用原 identifier / 数据目录并读回 `desktop-state.json`，验证排班、薪资、
  mini timer 位置、开机自启与隐藏金额不丢。
- [ ] 截图必须重拍，不得出现旧窗口标题。

### P5 — 商店、邮箱与开源外表面

- [ ] Microsoft Store 各语言 listing 主名为 `DoneAt: {该语功能副标题}`；Apple 仍按 007 拆成主名 DoneAt + 副标题，不把两段合并进一个字段。
- [ ] 商店截图与说明不得展示旧名的新包错配。
- [ ] 隐私页和三商店后台的支持邮箱改为 `hello@doneat.app`；确认收信与从 `offwork@rainif.com` 的转发后再切页面。
- [ ] 产品仓 README 标题、仓库 description、Release 模板、截图脚本、安装说明、Gatekeeper / SmartScreen 文案统一为 DoneAt。
- [ ] 文档写明：内部旧名、仓库 slug 和 exe 名不等于第二款产品。
- [ ] 版本更新说明只在一个过渡版本写「Off Work Countdown 现为 DoneAt」。

### P6 — 同一窗口验收

- [ ] Web App：19 语言 UI、light/dark、PWA 首装与旧 PWA、分享 query、离线和本地设置原地保留；
  Web build 与 Desktop export 都过。
- [ ] 官网：19 语门厅、英中长文、Apple + Microsoft Store + Web 三条 CTA、隐私/支持、移动/桌面布局和 light/dark；确认没有 GitHub 直装按钮、没有可安装 PWA。
- [ ] 双域：逐路由核对 status、Location、canonical、hreflang、robots、sitemap、Open Graph、
  JSON-LD；任何同内容双 canonical、重定向环或 query 丢失都挡发布。
- [ ] macOS：GitHub 与 Mac App Store 包实装升级、Finder / Dock / 菜单 / About / Widget / mini timer 显示 DoneAt。
- [ ] Windows：GitHub x64/ARM64 与 MSIX 的安装、升级、开始菜单、托盘、通知、自启动、卸载项显示 DoneAt；exe 名仍为旧名。
- [ ] 发布后核对 `latest.json` / `latest-cn.json`、旧客户端更新检查与新安装器资产名。
- [ ] 在两个站点属性分别观察抓取、索引、旧 keyword 排名与内容页 redirect；保留发布前基线。
- [ ] `off.rainif.com/{lang}` 与 PWA 是长期产品入口，不设置停服或迁到官网的退出条件。

## 机械检查基线

产品仓实现阶段至少需要：

```bash
npm run lint
npm test
npm run check:version
npm run build
npm run check:build:web
npm run build:desktop
npm run check:build:desktop
npm run check:lproj
cargo fmt --manifest-path src-tauri/Cargo.toml --check
cargo test --manifest-path src-tauri/Cargo.toml
```

涉及三渠道打包、商店 listing 或 iOS 共享材料时，再按 `AGENTS.md` 分别补 release build、MSIX、
Mac App Store 和 iOS simulator / 真机检查。域名切换必须在 production 上用响应头、页面 canonical、
分享链接和真实 PWA 逐项验证，预览部署不能代替。官网仓用它自己的构建与响应头测试，不编进产品仓的
`BUILD_TARGET`。

## 明确不做

- 不借品牌迁移重写倒计时 UI、排班模型或订阅方案。
- 不创建新 bundle id、新 Partner Center 产品或第二个 App Store Connect 记录。
- 不把薪资放入 URL、跨域存储服务、analytics 或错误日志。
- 不为了把内部名字变漂亮而重命名所有源码符号、localStorage 键、Cargo crate、exe 或数据库字段。
- 不把 `off.rainif.com` 的 Web App 主路由重定向到 `doneat.app`，也不做不需要的本地数据迁移。
- 不在 `doneat.app` 复制第二份 Web App / PWA，也不让官网仓注册可安装 manifest。
- 不把产品仓做成按 Host 分流的双站；官网是独立仓库、独立 Vercel 项目。
- 不在官网门厅或下载页放 GitHub 直装。
- 不因品牌更新删除现有 19 语言 SEO keywords，也不让两域同时索引相同内容。
- 不等待 007 上架才开始准备；也不把 009 的域名切换塞进 007 送审包。
