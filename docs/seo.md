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
4. `robots.txt` 已声明上述 `sitemap.xml`。Cloudflare 层还封锁了 `Google-Extended` / `GPTBot` 等；与官网同一取向，改封锁需另开 PR。

## 能力边界（写进 title / description / 正文 / JSON-LD）

网页只有 **单次 start–end 倒计时**（`end < start` 视为跨夜）。**班次功能**（多种班次、排班 / 轮休等）是 **iOS 独有**。

- 大厅与预设页可以说「用这组时刻跑网页倒计时」。
- 提到班次 / 排班时必须写明 iOS，不能暗示网页能排班。
- 预设页（`/en/996` 等）走方案 A：保留索引，文案诚实，主 CTA 开始网页倒计时，次 CTA 去官网下载。

## hreflang

`x-default` 必须是 `https://off.rainif.com/en`（或 `/en/{preset}`），不能是会 307 的裸域。HTML 与 sitemap 共用 `webAppAlternates()`。

## 抽查

```bash
curl -sSL https://off.rainif.com/en | grep -o 'hreflang="x-default" href="[^"]*"'
# 期望: href="https://off.rainif.com/en"

curl -sS https://off.rainif.com/sitemap.xml | grep -o 'hreflang="x-default" href="[^"]*"' | sort -u

curl -sSIL https://off.rainif.com/llms.txt | head
# 期望: text/plain，不要 text/html
```
