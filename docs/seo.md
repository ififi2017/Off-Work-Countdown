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
