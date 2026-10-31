# PR 预发布检查 — 2026-10-31

用户授权创建 PR 与 Vercel 预览，明确要求不上线。本批基于 `origin/main` 的 `0dba48ef8c715d6ca81d9076ff1a408ca3fda5f6` 建立 `codex/web-tools-cn-us-preview`，只迁入 Web 工具与对应证据。原产品目录及其未提交改动、本地3100预览保留。

## 已完成

- 临时安装 Node **24.22.2**，在干净检出执行 `npm ci`。
- Node 24 下 `npm test`：**56 文件、677 项通过**；`npm run lint`、`npm run check:version` 通过。版本保持主分支3.2.4，未改客户端版本。
- `VERCEL_ENV=production WEB_TOOLS_PREVIEW=1 npm run build` 与 `check:build:web` 通过；本机实际请求 `/en/tools`、`/zh-CN/salary/cn` 返回404，sitemap无草稿工具。
- `VERCEL_ENV=preview npm run build:desktop` 与 `check:build:desktop` 通过，桌面没有salary/tools路由。
- `VERCEL_ENV=preview npm run build` 与 `check:build:web` 通过，未手工设置预览开关即可生成十个审核页。
- 草稿开关优先拒绝production；Vercel Preview自动启用，本地显式开关保留；retired条目不进入预览。新增环境隔离测试覆盖这些组合。
- 独立只读审查未发现阻止预览的问题；修正CN通知落款（2025-01-01）与政府网页发布日期（2025-01-02）的区别，生效日期仍为null，未虚构人工审核。
- 本机同源请求观察：186个请求，全部GET，无请求正文，无测试金额命中；英文工资/奖金输入阶段无新增同源请求。跳转后URL不带工资，刷新恢复默认值，元数据没有输入。见 [记录](review/pre-release-request-audit.json)。

## 预览与生产边界

十个新页面全部保持draft/contentReviewedAt:null。预览noindex/nofollow、不进sitemap、不把不同市场当语言互译。不会合并main、不会部署生产，也不改Vercel域名或DNS。

Vercel部署状态、预览链接及远程访问验收追加到PR讨论区，避免把本机成功当作远程成功。旧的 [首次验收](VERIFICATION.md) 与截图是原实现的历史记录，本文件补充本轮基于最新main的Node24和请求检查证据。

## 仍需后续

- 人工中英文文案与地区适用范围审校；本轮代码/算术审查不替代人工签核。
- GSC上线前28天基线尚未取得，不填零；没有可用大陆网络探测点，尚未声称大陆可达或百度收录。
- 请求观察限本机同源流量，没有抓取直接外部流量，也没有复现生产Vercel分析端点。未新增事件或声称完成生产统计入库。
- 完整19语及日期、轮班、offer比较能力不属于本批已完成内容。

本轮两名辅助Agent均实际使用GPT-6.1 Sol / High，分别负责预览环境隔离与只读发布审查；主Agent集成、测试并创建PR。未调用Claude。

## 2026-10-31 下拉菜单调整

- 工资工具的计算口径、收入类型、显示币种统一复用现有 Radix Select 自建菜单，菜单匹配输入框宽度，提供选中勾、橙色焦点反馈和深色样式；未修改共享 Select 或计算规则。
- macOS 内置浏览器实测桌面与390×844窄屏中英文菜单；验证方向键+Enter选择、Escape关闭、币种更新、收入类型切换清空金额与恢复示例。深色样式已实现，本轮未切换系统配色做视觉验收。
- Node 24：lint、677项测试、Web预览构建及检查、Desktop导出及检查均通过。生产发布边界不变。
