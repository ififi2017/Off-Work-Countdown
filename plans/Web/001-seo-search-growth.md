# Web 001 — 双域 SEO 优化计划（off.rainif.com + doneat.app）

- **Status**: IN PROGRESS — 2026-09-25 §7 五项均已拍板；产品仓 P1-1、P1-2、P1-4、P1-5、P1-6、P2-1 与官网 P1-8、P1-9、P1-11 已于 2026-09-25 合并到两仓 `main`；P1-12 由用户在 Cloudflare 完成
- **起草**: 2026-09-25
- **数据来源**: Google Search Console 导出（两个属性，最近 3 个月，截至 2026-09-22）；Bing Webmaster 概览（两个属性，2026-09-09 至 09-22，只有每日汇总）
- **代码对照**: 产品仓 `main` @ `e3c231f`；官网仓 `ififi2017/doneat.app` `main` @ `0b36f81`
- **未做**: 线上抓取实测（本次环境无法访问两个域名）。凡是写「先查」的条目，都需要在 GSC / 线上核对后再改代码。
- **相关**: [009 双域分工](../iOS/009-doneat-platform-brand-domain.md)（锁定项不在这里重开）；[`docs/seo.md`](../../docs/seo.md)；官网仓 `docs/seo.md`、`docs/seo-intent-backlog.md`

## 0. 结论

1. **搜索资产几乎都在 `off.rainif.com`**：3 个月 2,835 次点击；`doneat.app` 上线 4 周 20 次点击。009 定下的双域分工不动，本计划只让两个域各自吃准自己的搜索意图，并把品牌信号接起来。
2. **核心词很健康，CTR 下滑是结构性的**：点击稳定在约 30 次/天，但展示翻了 2.5 倍，CTR 从 27% 掉到 12–15%。新增的展示主要来自 `/en/9-to-5`、`/en/9-to-6`（合计 2,056 次展示、0 点击）和「時間倒數」「퇴근시간」这类泛词。核心词在第 1 位时 CTR 有 80% 左右。
3. **最大的三个机会**：
   - 按真实搜索词重写 Web App 的 `<title>`，功能词放前面、品牌放后面，并补上 H1；
   - 把「9 to 5 是几小时」这类有展示没点击的流量变成点击（答案直接写进标题和首段，后续可以做一个真正的工时计算器）；
   - 让品牌词 `doneat` 排到第 1 位（现在两个域平均都在第 2.7–3.0 位）。
4. **Bing 不能忽略**：同期 Bing 点击约等于 Google 的 30%（126 次 vs 421 次）；`doneat.app` 在 Bing 的展示是 Google 的 3.4 倍。

## 1. 现状

### 1.1 两个域的分工（代码现状）

| 域 | 可索引页面 | 标题模式 | 结构化数据 |
|---|---|---|---|
| `off.rainif.com` | `/{19 语}`（Web App），`/{en,zh-CN}/{996,9-to-5,9-to-6,night-shift}`（预设页）；五页长文已 301 到官网 | `DoneAt — {本地化功能解释}`（`public/locales/*/seo.json`） | Organization + WebSite + WebApplication（`lib/server/metadata.ts`）；Organization `sameAs` 只有 GitHub |
| `doneat.app` | `/{19 语}` 门厅，`/{en,zh-CN}/{download,faq,about,how-it-works,privacy}` | 门厅 `DoneAt — {品牌句}`（`src/lib/config.ts` `homeTitle`），长文 `{页名} — DoneAt` | Organization（`sameAs` GitHub + X）、SoftwareApplication、WebApplication、FAQPage；**没有 WebSite 节点** |

另外：Web App 的 H1 只有 `DoneAt`（`components/off-work-countdown.tsx`），页面上没有功能词。根路径 `/` 307 到语言页，hreflang `x-default` 指向 `/en`（`docs/seo.md` 的规则）。

### 1.2 off.rainif.com — Google（2026-06-23 至 09-22）

合计：**2,835 次点击 / 16,358 次展示 / CTR 17.3%**。

| 月份 | 点击 | 展示 | CTR | 平均排名 |
|---|---:|---:|---:|---:|
| 6 月（8 天） | 231 | 846 | 27.3% | 6.7 |
| 7 月 | 975 | 3,889 | 25.1% | 8.3 |
| 8 月 | 944 | 6,107 | 15.5% | 8.5 |
| 9 月（22 天） | 685 | 5,516 | 12.4% | 5.9 |

**查询意图**（只算导出中可见的查询，约占总展示的 41%）：

| 意图 | 点击 | 展示 | CTR |
|---|---:|---:|---:|
| 倒计时 / 下班工具（下班倒數計時器、feierabend countdown、퇴근 카운트다운…） | 1,241 | 4,683 | 26.5% |
| 「9 to 5 / 9 to 6 是几小时」 | 0 | 1,412 | 0% |
| 品牌 `doneat` | 16 | 100 | 16%（排名 2.96） |
| 其他泛词 | 5 | 557 | 0.9% |

**头部查询**（第 1 位时 CTR 很高，说明标题和摘要本身有效）：

- 下班倒數計時器 289 / 350，下班倒數 236 / 288，下班計時器 75 / 83（均为第 1 位，CTR 80–90%）
- 下班倒计时 167 / 513，排名 **2.44**，CTR 32.5%（简中核心词还没拿到第 1）
- feierabend countdown 131 / 342（排名 1.73）；feierabend timer 35 / 66；feierabend uhr 4 / 45（排名 3.07，CTR 8.9%）
- 퇴근시간 계산기 55 / 70（CTR 78.6%）；퇴근 카운트다운 46 / 56；퇴근시간 1 / 301（排名 7.0）
- off work countdown 42 / 63；shift countdown 22 / 72（排名 4.28）；work countdown 13 / 71（排名 4.18）

**市场**：台湾 1,062（37%）、德国 407（14%）、韩国 387（14%），三地合计占点击的 65%。美国展示最多（3,350），但 CTR 只有 6.75%，主要是「9 to 5」类查询。香港 1,234 次展示，平均排名 13.7。

**页面**：

| 页面 | 点击 | 展示 | CTR | 排名 | 说明 |
|---|---:|---:|---:|---:|---|
| `/zh-TW` | 1,124 | 3,314 | 33.9% | 6.3 | 主力 |
| `/de` | 414 | 1,692 | 24.5% | 5.2 | |
| `/ko` | 394 | 1,668 | 23.6% | 5.3 | |
| `/`（307 根路径） | 347 | 3,717 | 9.3% | 8.0 | **展示最多**，和 `/en` 分走了英文信号 |
| `/zh-CN` | 188 | 928 | 20.3% | 4.8 | |
| `/en` | 105 | 973 | 10.8% | 4.0 | |
| `/zh-HK` | 96 | 1,069 | 9.0% | **16.2** | 排名明显偏低 |
| `/en/9-to-5` | 0 | 1,042 | 0% | 11.8 | |
| `/en/9-to-6` | 0 | 1,014 | 0% | 10.2 | |
| `/it` `/pt` `/id` | 22 | 606 | 3.6% | 10–14 | 意大利语多为「mezzanotte」等不相关查询 |

**设备**：桌面 2,412 / 9,263（CTR 26.0%）；移动 417 / 6,992（CTR **6.0%**）。移动端 CTR 只有桌面的四分之一。

### 1.3 doneat.app — Google（2026-08-28 起）

20 次点击 / 345 次展示。可见查询只有品牌词：`doneat` 14 / 121，**排名 2.74**；`done at` 0 / 19（排名 7.6）。页面展示主要是 `/en`（151）、`/en/download`（100）、`/en/faq`（100）、`/en/about`（88），CTR 都低于 6%。说明 Google 目前只把官网当作品牌词的结果，而且还没排到第一。

### 1.4 Bing（2026-09-09 至 09-22）

| 属性 | Bing 点击 / 展示 / CTR | 同期 Google |
|---|---|---|
| off.rainif.com | 126 / 1,867 / 6.7% | 421 / 2,868 / 14.7% |
| doneat.app | 28 / 549 / 5.1% | 17 / 160 / 10.6% |

Bing 的 CTR 只有 Google 的一半左右。本次只有每日汇总，没有查询和页面，所以 Bing 上排的是什么词还不知道。

## 2. 问题清单（按影响排序）

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| A | Web App 标题品牌在前，功能词没有对准各地真实搜索词；H1 只有 `DoneAt` | 核心词都是功能词；`doneat` 全站只有 100 次展示；韩国「계산기」、德国「Feierabend-Uhr」、日本「あと何時間」没进标题 | 核心词排名与 CTR |
| B | 「9 to 5 是几小时」有展示没点击 | 2,056 次展示，0 点击，排名 10–12 | 美国市场的主要流量入口 |
| C | 根路径 `/` 和 `/en` 分走英文信号 | `/` 3,717 次展示、CTR 9.3%；`/en` 973 次 | 英文排名被稀释 |
| D | 品牌词没排第一，两个域的实体信号没对齐 | `doneat` 排名 2.7–3.0；官网没有 WebSite 节点；两个域的 Organization `sameAs` 不一致 | 品牌搜索、SERP 站点名 |
| E | `/zh-HK` 排名 16 | 展示 1,069，香港平均排名 13.7 | 香港用户可能拿到别的语言版本 |
| F | 移动端 CTR 6% | 移动端展示占 43% | 手机搜索者多半想要 App 或小组件 |
| G | Bing 与其他搜索引擎利用不足 | Bing 点击约为 Google 的 30%；韩国（Naver）、中国（百度）数据未纳入 | 少了一部分稳定流量 |
| H | 官网门厅标题没有功能词 | 门厅是 `DoneAt — Know when your time is yours` | 官网只能吃品牌词 |

## 3. 两个域的关键词分工

为避免两个域争同一个词，按意图分开：

| 意图 | 目标域 | 示例查询 |
|---|---|---|
| 马上用：网页 / 在线 / 计时器 | `off.rainif.com/{lang}` | 下班倒數計時器、下班倒计时、feierabend countdown、퇴근 카운트다운、đếm giờ tan ca、work countdown timer |
| 算时间：几小时 / 计算器 | `off.rainif.com`（预设页、将来的计算器） | how many hours is 9 to 5、퇴근시간 계산기、Feierabendrechner、5時まであと何時間 |
| 要装：App / 小组件 / iPhone / Mac / Windows | `doneat.app/{lang}`、`/download` | 下班倒计时 app、下班倒计时组件、feierabend app、퇴근 앱 |
| 品牌 | `doneat.app` 第一，`off.rainif.com` 第二 | doneat、done at、off work countdown（旧名） |

例子：「下班倒计时组件」现在落在 `off.rainif.com`（31 次展示，排名 2.5），它应该由官网下载页来接。

## 4. 执行阶段

### P0 — 先查清楚（本周，不改代码）

- [ ] **改名前后对比**：在 GSC 里对比 DoneAt 标题上线前（8/1–8/29）和上线后（8/31–9/22），看头部 10 个查询在 `/zh-TW`、`/de`、`/ko`、`/en` 上的 CTR 和排名。如果核心词的 CTR 下降，P1-1 就是最高优先级。
- [ ] **根路径**：GSC 按页面筛选 `https://off.rainif.com/`，导出它的查询和国家；用 URL 检查看 Google 为 `/` 选的规范网址。
- [ ] **zh-HK**：URL 检查 `/zh-HK`，看 Google 选的规范网址是不是 `/zh-TW`；按国家「香港」筛选，看点击都落在哪个页面。
- [ ] **移动端**：按「设备 × 查询」拆分，确认移动端的低 CTR 主要是「9 to 5」和泛词，还是核心词也偏低。
- [ ] **Bing**：两个属性都导出「搜索性能 → 查询 / 页面」；看 `doneat.app` 那 549 次展示是哪些词。
- [ ] **百度**：产品仓已经做了百度验证（`layout.shell.tsx`），导出百度统计 / 站长平台的简中关键词，补进本计划的数据基线。
- [ ] **AI 爬虫**：两边文档都说 Cloudflare 屏蔽了 `GPTBot`、`Google-Extended` 等训练爬虫。核对两个域线上的 `robots.txt` 和 Cloudflare「AI 爬虫」托管规则，确认 `OAI-SearchBot`、`PerplexityBot`、`Claude-SearchBot`、`Bingbot` 这类**搜索检索**爬虫有没有被一起挡掉。已决定放行检索爬虫（§7-4），改法见 P1-12。
- [ ] 把以上结果和本文 §1 的数字一起存成基线（放在 `docs/reviews/`），之后每月对照。

### P1 — 页面信号（1–2 周）

**产品仓（off.rainif.com）**

- [x] **P1-1 标题换成「功能词在前、品牌在后」**（§7-1 已同意）。只改 `seo.json` 的 `title`，`keywords` 只增不删。建议稿按真实查询来写，由母语审阅后定稿：

  | 语言 | 现在 | 建议 |
  |---|---|---|
  | zh-TW | DoneAt — 瀏覽器裡的下班倒數 | 下班倒數計時器｜網頁直接用 — DoneAt |
  | zh-CN | DoneAt — 浏览器里的下班倒计时 | 下班倒计时｜网页版，打开就能用 — DoneAt |
  | zh-HK | DoneAt — 瀏覽器裏的放工倒數 | 放工倒數・下班倒數計時器 — DoneAt |
  | de | DoneAt — Feierabend-Countdown im Browser | Feierabend-Countdown & Feierabend-Uhr im Browser — DoneAt |
  | ko | DoneAt — 브라우저에서 퇴근 카운트다운 | 퇴근 카운트다운 · 퇴근시간 계산기 — DoneAt |
  | en | DoneAt — Work shift countdown in your browser | Work Countdown Timer — off-work & shift countdown — DoneAt |
  | ja | DoneAt — ブラウザで退勤カウントダウン | 退勤カウントダウン｜定時まであと何分 — DoneAt |
  | vi | DoneAt — Đếm ngược tan ca trong trình duyệt | Đếm giờ tan ca — đếm ngược giờ tan làm — DoneAt |

  其余语言等 P0 数据出来再改。ko 的「계산기」要等 P2-1 真有计算能力再写进标题，在那之前可以先用「퇴근시간」。
- [x] **P1-2 H1 带上功能词**：只改 Web 构建。H1 改成「DoneAt + 本地化功能行」，功能行用已有的 `offWorkCountdown` 键（如 zh-TW「下班倒數計時」、de「Feierabend-Countdown」），做成可见的小字副标题，不新增翻译键，也不用 `sr-only` 塞关键词。（`landingTagline` 是品牌句，不用于这里。）Desktop 的单行标题不动。
- [x] **P1-3 首屏下方加一段可见说明**（核对后发现 Web 首页已有说明区：品牌句 + `landingBody` + 三条特性，均在首屏 HTML 里。不再重复加。）：把现有 `seo.description` 显示在工具下方（不新增翻译键），再加上指向本语言预设页（仅 en / zh-CN）和官网 FAQ 的文字链。
- [x] **P1-4 「9 to 5 / 9 to 6」页面直接给答案**（四个预设页都加了「扣掉不计薪午休后」对照表和工时计算器链接）：改 `public/locales/{en,zh-CN}/presets.json` 的 `metaTitle` / `metaDescription` / `intro`，例如：
  - title：`How many hours is 9 to 5? 8 hours (7–7.5 paid)`
  - description 第一句就是答案，然后是「一周 40 小时；午休不带薪时为 7 或 7.5 小时；可以直接用这组时间开始倒计时」。
  - 在 `facts` 下加一张小表：不扣午休 / 扣 30 分钟 / 扣 60 分钟。时长由 `lib/countdown.ts` 的 `getShiftLengthHours` 计算，不另写公式。
  - zh-CN 版同样处理（朝九晚五 / 朝九晚六 是几个小时）。
- [x] **P1-5 根路径与 x-default**（产品仓已改；官网仓见 P1-8 同批改动）（§7-2，按推荐方案）：
  - 上线前先在 GSC 导出 `/` 的查询、国家和页面数据，作为对照基线。
  - 产品仓：`webAppAlternates()` 的 `x-default` 改成 `https://off.rainif.com/`（首页）；预设页的 `x-default` 仍指 `/en/{preset}`，因为 `/{preset}` 不存在对应的自动跳转页。HTML 和 sitemap 继续共用这一个函数。
  - 产品仓 `middleware.ts`：补语言跳转响应头 `Vary: Accept-Language, Cookie`，说明这次跳转取决于语言和已保存的语言设置。跳转状态码保持 307，查询参数照旧保留（分享链接依赖它）。
  - 官网仓：门厅的 `x-default` 同样改成 `https://doneat.app/`，根路径的 302 同样补 `Vary`。
  - 同步改两个仓的 `docs/seo.md`，删掉「x-default 不能是会 307 的裸域」这条旧规则，写清新规则和原因。
  - 验收：4 周后对比基线。`/` 的展示应该下降，`/en` 和各语言页的展示应该上升；如果英文页的总点击下降超过 15%，就改回 `x-default = /en`。
- [x] **P1-6 实体信号对齐**：`buildWebAppJsonLd` 的 Organization 与官网使用同一个 `@id`（已经一致），`sameAs` 改成和官网相同的列表（GitHub + X）；WebApplication 保留 `alternateName: "Off Work Countdown"`。
- [ ] **P1-7 搜索引擎接入**：
  - Naver Search Advisor 验证 `off.rainif.com` 并提交 sitemap（韩国是第三大市场，Naver 份额高）；
  - 两个域都接 IndexNow（Bing / Yandex / Naver / Seznam 共用）：放 key 文件，部署后用 GitHub Action 推送 sitemap 里变更过的 URL；
  - Bing Webmaster 确认两个 sitemap 都已提交。

**官网仓（doneat.app）**

- [x] **P1-8 门厅标题带功能词**（官网仓 `locales/chrome.json` 的 `homeTitle`，19 语）：`homeTitle` 改成 `DoneAt: {functionalSubtitle} — iPhone, Mac & Windows`（中文「DoneAt：下班倒计时 App — iPhone、Mac、Windows」）。门厅可见的品牌句不变，只改 `<title>`。这和 009 G1「副标题 / SEO 解释 = Work Shift Countdown」、Microsoft Store 的 `DoneAt: Work Shift Countdown` 一致。
- [x] **P1-9 WebSite 结构化数据**：在门厅加 `WebSite` 节点（`name: "DoneAt"`，`alternateName: ["Off Work Countdown", "下班倒计时"]`，`url: https://doneat.app/`），让 Google 显示正确的站点名，也帮助品牌词排名。
- [ ] **P1-10 外部链接统一指向官网**：App Store Connect 的营销网址、Microsoft Store listing 的网站、GitHub 仓库的 Website 字段、X 的个人简介链接都填 `https://doneat.app`。这些是官网最有分量的外链。
- [x] **P1-11 下载页接住「App / 小组件」意图**（§7-3 已同意，需要用 3.2.0 营销截图更新 iOS 介绍）（2026-09-25 完成：官网 [doneat.app#18](https://github.com/ififi2017/doneat.app/pull/18) 换上 3.2.0 review 录屏、iPhone 功能区四张商店图轮播 + 可见说明、对照表与两条 FAQ；网页版首屏以下也加了原生 App 展示，见 [#231](https://github.com/ififi2017/Off-Work-Countdown/pull/231)。3.2.0 已于此前上架，所以没有等上架日）：
  - 素材：3.2.0 的 8 张 iPhone 商店图（倒计时、倒计时详情、Apple Watch、月历、记录、专注、小组件、午休），英文用 `en-iphone-0{1–8}-*.png`，简中用 `zh-CN-iphone-0{1–8}-*.png`。这些文件是 `scripts/marketing-shots/ios/out/creative-3.2.0/` 的生成产物，目录被 `.gitignore` 忽略，不在仓库里；需要从本机复制到官网仓，转成 WebP 或 AVIF 并控制体积后再放进 `assets/`。
  - 替换下载页里 3.1.8 时期的 iOS 介绍；首页机位仍用现有的真机录屏（官网交接规则要求首页不用商店合成图），除非另外决定。
  - 商店图里的标题是图片上的文字，搜索引擎读不到。每张图都要配一段页面上的文字说明，写清这个功能能做什么（小组件、实时活动、免费 Apple Watch App、月历排班、节假日），并给图片写具体的 `alt`。
  - FAQ 可以增加「有没有小组件 / Apple Watch」这类问题，只写 en / zh-CN。
  - **时间点**：3.2.0 还没上架（见 `docs/reviews/2026-09-19-3.2.0-release-readiness.md`）。官网这部分可以先在分支上做好，**等 3.2.0 在 App Store 上线当天再合并**，免得用户看到还下载不到的功能。
- [x] **P1-12 放行 AI 搜索检索爬虫**（2026-09-25 用户确认已在 Cloudflare 设置好）（§7-4 已同意）：继续屏蔽 `GPTBot`、`Google-Extended`、`CCBot` 等训练爬虫；放行 `OAI-SearchBot`、`ChatGPT-User`、`PerplexityBot`、`Claude-SearchBot`、`Claude-User`。两边文档都写明线上的 AI 爬虫规则来自 Cloudflare，不是仓库里的文件，所以要在 Cloudflare 后台两个域分别检查「托管 robots.txt」和「阻止 AI 机器人」两项设置（后者在防火墙层拦截，不看 `robots.txt`），改完再用 `curl` 核对线上 `robots.txt`。同步更新两个仓 `docs/seo.md` 里关于 AI 爬虫的说明。`llms.txt` 已存在，保持不变。

### P2 — 内容与功能（1–2 个月）

- [x] **P2-1 工时计算**（§7-5：只做 Web，独立小工具，带 DoneAt 推荐位）：`/{lang}/work-hours-calculator`，19 种语言，仅 Web 构建。两种模式：「几点下班」（上班时刻 + 工作时长 + 不计薪休息）和「做了几个小时」（起止 + 休息 + 每周天数）；结果可一键带进倒计时（`from=calculator`，计为 `calculator_start`）；下方 DoneAt App 推荐卡片链到官网对应语言门厅（`calculator_app_open`）。计算在 `lib/work-hours.ts`，跨度复用 `getShiftLengthHours`，不进共享规则、不涉及 Swift / Kotlin。原始设想：对应英文「how many hours is 9 to 5」、德国「Feierabendrechner / wann habe ich Feierabend」（现在排名 26–29）、韩国「퇴근시간 계산기」（55 次点击，CTR 79%）、「남은시간 계산기」（112 次展示，排名约 8）、日本「5時まであと何時間」。做成首页的一个模式，不另开一批页面；计算规则放在 `lib/countdown.ts`，不在组件里另写公式。
- [ ] **P2-2 官网下载页扩写**：现在只有约 270 个英文词。给每个平台补一段具体用法和截图说明，对准「下班倒计时 app」「feierabend app」这类词。仍然只写 en / zh-CN。
- [ ] **P2-3 意大利语、葡语、印尼语**：展示主要来自不相关的「mezzanotte / 午夜倒计时」类查询。先不追，等 P0 查询数据确认有真实需求再改文案。
- [ ] **P2-4 夜班**：`night-shift` 页排名 15–21，而跨夜是产品的差异点。可以按官网 backlog 的规则补一段 FAQ，不新开页面。

### P3 — 持续

- [ ] 每月做一次 GSC + Bing 对照（同一组查询、页面、国家、设备），结果追加到基线记录。
- [ ] 每次改标题只动一个变量，至少观察 3–4 周再判断。
- [ ] 任何新 URL 都先按官网 `docs/seo-intent-backlog.md` 的规则看 SERP，再决定做不做。

## 5. 目标（90 天，到 2026-12 下旬复盘）

| 指标 | 现在 | 目标 |
|---|---|---|
| off.rainif.com Google 点击 | 约 30 次/天 | 40 次/天 |
| `/en/9-to-5` + `/en/9-to-6` | 0 点击，排名 10–12 | 排名 ≤ 6，CTR ≥ 3% |
| `doneat` 品牌词 | 排名 2.7–3.0 | 官网排名 ≤ 1.3 |
| doneat.app Google 点击 | 20 次 / 4 周 | 100 次 / 4 周 |
| 移动端 CTR（off） | 6.0% | 9% |
| `/zh-HK` 平均排名 | 16.2 | ≤ 8 |
| 下班倒计时（简中） | 排名 2.44 | ≤ 1.5 |

这些是方向性的目标，不是承诺；P0 基线出来后可以再调。

## 6. 不做

- 不把 `off.rainif.com` 迁到 `doneat.app`，不做 Change of Address（009 已锁定；Web 用户的本地数据和 PWA 都在旧域，而且 99% 的点击也在旧域）。
- 不为长文或预设页生成 19 语未审译文；不为每种「9 to X」组合批量开页面（门页风险，见 `lib/presets.ts` 注释）。
- 不删现有 `keywords`，不把品牌句塞进功能行。
- 不指望 FAQ 富媒体结果：Google 自 2023 年 8 月起只给少数权威政府 / 医疗网站展示 FAQ 富媒体结果。`FAQPage` 可以保留，但不当作目标。
- 不买链接，不做 Indexing API 批量提交。
- 不用隐藏文字或 `sr-only` 堆关键词。

## 7. 决定记录

| # | 问题 | 结论（2026-09-25） |
|---|---|---|
| 1 | Web App 标题顺序 | **同意**。`off.rainif.com` 改成「功能词 — DoneAt」；官网继续品牌在前。这一条替换 009 P3 的「DoneAt — 功能解释」。 |
| 2 | 根路径与 `x-default` | **按推荐方案**：`x-default` 指向会按语言跳转的首页 `/`，跳转响应补 `Vary`，4 周后对照基线，不达标就改回。理由见下。 |
| 3 | 官网写小组件 / 实时活动 / Watch | **同意**，条件是用 3.2.0 的营销截图更新 iOS 介绍（现在是 3.1.8）。3.2.0 上架当天再合并，见 P1-11。 |
| 4 | AI 搜索检索爬虫 | **同意放行**，训练爬虫继续屏蔽，见 P1-12。 |
| 5 | 工时计算功能 | **只做 Web**，做成独立于倒计时的小工具，界面要精致，并植入 DoneAt 产品推荐。已实现，见 P2-1。 |

**§7-2 为什么选 `x-default = /`**

- Google 的 hreflang 文档把「按用户语言自动跳转的首页」列为 `x-default` 的典型用法。现在 `/` 已经在按语言跳转，只是没有在 hreflang 里说明它的角色，于是 Google 把它当作一个单独的英文页收录，这就是 `/` 拿到 3,717 次展示、CTR 只有 9.3% 的原因。
- 这个改动不改变用户看到的任何东西，分享链接的查询参数也不受影响，而且只改一个函数，随时可以改回。
- 其他两个办法都更差：`/` 固定永久跳到 `/en` 会让非英语用户先看到英文；在 `/` 直接输出一份英文页面会造成和 `/en` 重复的内容。
- 风险：部分第三方 SEO 工具会把「hreflang 指向跳转网址」标成错误，这类提示可以忽略；Google 最终怎么选规范网址仍由它决定，所以要用 4 周数据验证。
