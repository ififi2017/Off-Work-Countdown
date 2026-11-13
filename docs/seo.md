# Web 计时器 SEO（off.rainif.com）

本仓的可索引面是 **Web 产品页**，不是品牌官网。

| 域 | 角色 |
|---|---|
| `https://doneat.app/` | 官网：品牌、下载、FAQ、隐私、关于 |
| `https://off.rainif.com/` | 网页倒计时：设起止时刻、看剩余时间与进度 |

不要把整站 301 到 `doneat.app`。两域各自保留 canonical。

## Search Console

1. 验证属性 **`off.rainif.com`**（与 `doneat.app` 分开）。
2. 只提交这一份 sitemap：

   `https://off.rainif.com/sitemap.xml`

3. **不要**提交 `https://off.rainif.com/sitemap-index.xml`。该路径不是 sitemap，现网曾返回 locale HTML。
4. `robots.txt` 已声明上述 `sitemap.xml`。AI 爬虫规则在 Cloudflare 层，不在本仓：继续封锁训练爬虫（`Google-Extended`、`GPTBot` 等），放行搜索检索爬虫（`OAI-SearchBot`、`PerplexityBot`、`Claude-SearchBot` 等）。2026-09-25 用户确认 Cloudflare 已按此设置（plans/Web/001 §7-4）；与官网同一取向。

## 能力边界（写进 title / description / 正文 / JSON-LD）

网页只有 **单次 start–end 倒计时**（`end < start` 视为跨夜）。**班次功能**（多种班次、排班 / 轮休等）是 **iOS 独有**。

- 大厅与预设页可以说「用这组时刻跑网页倒计时」。
- 提到班次 / 排班时必须写明 iOS，不能暗示网页能排班。
- 预设页（`/en/996` 等）走方案 A：保留索引，文案诚实，主 CTA 开始网页倒计时，次 CTA 去官网下载。

## hreflang

- **首页**：`x-default` 指向 `https://off.rainif.com/`。根路径由 middleware 按 `Accept-Language` 与语言 cookie 307 到 `/{lang}`（保留查询串，响应带 `Vary: Accept-Language, Cookie`），正是 Google 文档里「按语言自动跳转的首页」这一 `x-default` 用法。2026-09-25 前这里指向 `/en`，结果 `/` 被当作单独的英文页收录，拿走了全站最多的展示（见 [plans/Web/001](../plans/Web/001-seo-search-growth.md) §7-2）。上线 4 周后按该计划的基线复核；英文页总点击下降超过 15% 就改回 `/en`。
- **其他页**（预设页、工时计算器）：`x-default` 仍是 `/en/{path}`，因为 `/{path}` 没有对应的按语言跳转页。
- HTML 与 sitemap 共用 `webAppAlternates()`，不要各写一份。

## 页面标题

Web App 标题是「功能词 — DoneAt」：用户搜的是「下班倒數計時器」「Feierabend Countdown」这类功能词，品牌词展示量很小。按 Search Console 数据重写过的语言：en、zh-CN、zh-TW、zh-HK、de、ko、ja、vi；其余仍是「DoneAt — 功能解释」，重写前先看该语言的查询数据。`keywords` 只增不删。官网 `doneat.app` 继续品牌在前。

## 工时计算器

`/{lang}/work-hours-calculator`，19 种语言，仅 Web 构建（`page.web.tsx`），在 sitemap 里互为 alternate。它和倒计时是两个工具：回答「几点下班」「做了几个小时」，结果可以一键带进倒计时（`?s=…&from=calculator`，计为 `calculator_start`）。页内有一张 DoneAt App 推荐卡片，点击计为 `calculator_app_open`，链到官网对应语言门厅并带 `utm_campaign=work-hours-calculator`。

## 广告（AdSense）

Web 构建在浏览器标签页里加载（`lib/ads.ts` + `components/AdSenseLoader.tsx`），计时主页 `/{lang}` 也包括在内：想要无广告就用客户端（PWA、桌面、扩展、iOS、Android 都不加载）。`/{lang}/mini`、根路径 `/`（只做跳转）、预览域名和 localhost 不加载。已安装 PWA 的判断：standalone / fullscreen / minimal-ui / window-controls-overlay 的 display-mode、iOS `navigator.standalone`、`android-app://` 来源。页内固定广告位 `AdSenseUnit`（广告单元 off-timer-inline，`ADSENSE_INLINE_SLOT`）：计时页首屏以下一个、设置态的 App 展示与下载区之间一个；预设页（`ContentPage`）、工时计算器和工资工具（`ToolPageFrame`）正文末尾各一个。宽屏（≥1024×720）首屏卡片左右各一个竖幅 `variant="rail"`（≥1280 宽为 300×600，否则 160×600），跟着页面滚动、不吸附：AdSense 不允许内容两侧对称的吸附广告，手动吸附广告整个视口也只能有一个。竖幅上方有关闭按钮（AdSense 允许访客点框关闭广告单元），与广告留出间距、不压住广告和 AdChoices 图标；关闭只对本次打开有效，重新打开网页恢复。关掉后右下角出现一次 `AdFreeInvite`（「不想被广告打扰？」，指向客户端下载页；桌面版下载邀请还在时不出现），埋点 `ad_free_invite_view` / `ad_free_invite_open`。卡片本身和窄屏首屏不放，卡片不被挤动；不预留高度，Google 返回 unfilled 时整块收起，被拦截时也不留空白。锚定广告由加载脚本的 `data-overlays="collapsed-bottom"` 固定为 Google 的普通底部矮条（可关闭，下次打开网页重新出现）：不出现在顶部，也不出现可折叠锚定广告（它先以大尺寸展开，曾给 body 加约 456px 底部留白）。这个属性会覆盖后台的锚定广告开关，所以只在宽度 < 1024px 时加；更宽的屏幕沿用后台设置（关闭），免得底部条压住两侧竖幅。Google 在访客第一次滚动后才把它滑出来。手机上不能自己做吸附广告位：AdSense 的吸附广告规则只允许桌面端。锚定条在屏幕上的高度写进 `<html>` 的 `--ad-anchor-h`，底部固定的界面（「获取 App」、返回顶部、桌面版下载邀请）都加上这个偏移，不压住广告，也不被广告压住。自动广告的其余位置和密度在 AdSense 后台控制；欧盟/英国/瑞士的同意弹窗用后台「隐私和消息」里 Google 的同意消息，代码里没有 CMP。

## llms.txt

`/llms.txt`（`app/llms.txt/route.ts`）是给 AI 搜索 / 问答引擎的 Markdown 地图，按 llmstxt.org 格式：摘要、关键事实、工具与预设页链接。预设页和工资工具页直接取自 `lib/presets.ts` 与 `features/web-tools/catalog/pages.ts`，新页面自动出现；关键事实是手写的，改功能时同步核对（尤其「网页不能排班」）。官网 `https://doneat.app/llms.txt` 与本文件互相链接。

## 抽查

```bash
curl -sSL https://off.rainif.com/en | grep -o 'hreflang="x-default" href="[^"]*"'
# 期望: href="https://off.rainif.com/"

curl -sSI -H 'Accept-Language: de' https://off.rainif.com/ | grep -iE '^(location|vary)'
# 期望: location: …/de，vary 含 Accept-Language

curl -sS https://off.rainif.com/sitemap.xml | grep -o 'hreflang="x-default" href="[^"]*"' | sort -u

curl -sSIL https://off.rainif.com/llms.txt | head
# 期望: text/plain，不要 text/html
```
