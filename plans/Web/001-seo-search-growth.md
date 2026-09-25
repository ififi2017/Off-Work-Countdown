# Web 001 — 双域 SEO 优化计划（off.rainif.com + doneat.app）

- **Status**: DRAFT（附带需要拍板的决定，见 §7）
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
- [ ] **AI 爬虫**：两边文档都说 Cloudflare 屏蔽了 `GPTBot`、`Google-Extended` 等训练爬虫。核对线上 `robots.txt`，确认 `OAI-SearchBot`、`PerplexityBot`、`Claude-SearchBot`、`Bingbot` 这类**搜索检索**爬虫有没有被一起挡掉。挡不挡由产品决定（§7-4）。
- [ ] 把以上结果和本文 §1 的数字一起存成基线（放在 `docs/reviews/`），之后每月对照。

### P1 — 页面信号（1–2 周）

**产品仓（off.rainif.com）**

- [ ] **P1-1 标题换成「功能词在前、品牌在后」**（需要先拍板 §7-1）。只改 `seo.json` 的 `title`，`keywords` 只增不删。建议稿按真实查询来写，由母语审阅后定稿：

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
- [ ] **P1-2 H1 带上功能词**：只改 Web 构建。H1 改成「DoneAt + 本地化功能行」，功能行用已有的 `offWorkCountdown` 键（如 zh-TW「下班倒數計時」、de「Feierabend-Countdown」），做成可见的小字副标题，不新增翻译键，也不用 `sr-only` 塞关键词。（`landingTagline` 是品牌句，不用于这里。）Desktop 的单行标题不动。
- [ ] **P1-3 首屏下方加一段可见说明**：把现有 `seo.description` 显示在工具下方（不新增翻译键），再加上指向本语言预设页（仅 en / zh-CN）和官网 FAQ 的文字链。
- [ ] **P1-4 「9 to 5 / 9 to 6」页面直接给答案**：改 `public/locales/{en,zh-CN}/presets.json` 的 `metaTitle` / `metaDescription` / `intro`，例如：
  - title：`How many hours is 9 to 5? 8 hours (7–7.5 paid)`
  - description 第一句就是答案，然后是「一周 40 小时；午休不带薪时为 7 或 7.5 小时；可以直接用这组时间开始倒计时」。
  - 在 `facts` 下加一张小表：不扣午休 / 扣 30 分钟 / 扣 60 分钟。时长由 `lib/countdown.ts` 的 `getShiftLengthHours` 计算，不另写公式。
  - zh-CN 版同样处理（朝九晚五 / 朝九晚六 是几个小时）。
- [ ] **P1-5 根路径与 x-default**：根据 P0 结果二选一（§7-2）。
- [ ] **P1-6 实体信号对齐**：`buildWebAppJsonLd` 的 Organization 与官网使用同一个 `@id`（已经一致），`sameAs` 改成和官网相同的列表（GitHub + X）；WebApplication 保留 `alternateName: "Off Work Countdown"`。
- [ ] **P1-7 搜索引擎接入**：
  - Naver Search Advisor 验证 `off.rainif.com` 并提交 sitemap（韩国是第三大市场，Naver 份额高）；
  - 两个域都接 IndexNow（Bing / Yandex / Naver / Seznam 共用）：放 key 文件，部署后用 GitHub Action 推送 sitemap 里变更过的 URL；
  - Bing Webmaster 确认两个 sitemap 都已提交。

**官网仓（doneat.app）**

- [ ] **P1-8 门厅标题带功能词**：`homeTitle` 改成 `DoneAt: {functionalSubtitle} — iPhone, Mac & Windows`（中文「DoneAt：下班倒计时 App — iPhone、Mac、Windows」）。门厅可见的品牌句不变，只改 `<title>`。这和 009 G1「副标题 / SEO 解释 = Work Shift Countdown」、Microsoft Store 的 `DoneAt: Work Shift Countdown` 一致。
- [ ] **P1-9 WebSite 结构化数据**：在门厅加 `WebSite` 节点（`name: "DoneAt"`，`alternateName: ["Off Work Countdown", "下班倒计时"]`，`url: https://doneat.app/`），让 Google 显示正确的站点名，也帮助品牌词排名。
- [ ] **P1-10 外部链接统一指向官网**：App Store Connect 的营销网址、Microsoft Store listing 的网站、GitHub 仓库的 Website 字段、X 的个人简介链接都填 `https://doneat.app`。这些是官网最有分量的外链。
- [ ] **P1-11 下载页接住「App / 小组件」意图**：description 写明 iPhone、iPad、Mac、Windows 和 Apple Watch 能做什么。是否写小组件、实时活动要看 §7-3。

### P2 — 内容与功能（1–2 个月）

- [ ] **P2-1 工时计算（需要产品决定，§7-5）**：用户输入上班时间 + 工作时长 + 午休，得出下班时间，再一键开始倒计时。对应英文「how many hours is 9 to 5」、德国「Feierabendrechner / wann habe ich Feierabend」（现在排名 26–29）、韩国「퇴근시간 계산기」（55 次点击，CTR 79%）、「남은시간 계산기」（112 次展示，排名约 8）、日本「5時まであと何時間」。做成首页的一个模式，不另开一批页面；计算规则放在 `lib/countdown.ts`，不在组件里另写公式。
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

## 7. 需要拍板

1. **Web App 标题顺序**：009 P3 定的是「DoneAt — 功能解释」。数据显示用户搜的是功能词，品牌词只有约 100 次展示。建议只在 `off.rainif.com` 改成「功能词 — DoneAt」，官网继续品牌在前。这会改动 009 的一条锁定项。
2. **根路径 `/`**：
   - 方案甲（推荐）：`x-default` 改指 `/`。Google 文档把「按语言自动跳转的首页」列为 `x-default` 的典型用法。这会推翻 `docs/seo.md` 里「x-default 不能是会 307 的裸域」的规则。
   - 方案乙：维持 `x-default = /en`，接受 `/` 被单独收录。改动为零，但英文信号会继续分在两个网址上。
   - 不考虑把 `/` 改成固定跳到 `/en` 的永久跳转：那样非英语用户从根路径进来都会先看到英文。
   - 等 P0 的根路径数据出来再定。
3. **官网写不写小组件 / 实时活动 / Watch**：官网交接文档曾锁定「不写 Widget、灵动岛」；017 又把「官网与商店文案」列为待办。「下班倒计时组件」确实有搜索需求。
4. **AI 搜索爬虫**：继续挡训练爬虫的同时，是否放行 `OAI-SearchBot`、`PerplexityBot`、`Claude-SearchBot` 这类检索爬虫。放行后才可能在 ChatGPT / Perplexity / Claude 的搜索结果里被引用。
5. **工时计算功能**（P2-1）：这是产品功能，不只是 SEO，而且要进 `lib/countdown.ts`。是否只做 Web，还是 iOS / Android 同步。
