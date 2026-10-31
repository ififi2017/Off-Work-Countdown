# 首批本地验收 — 2026-10-31

## 交付与范围

本批为 P0 工程准备及 P1 可审阅实现：独立 Web 工资计算引擎、8 个 CN/US 工资页、2 个工具目录、发布注册表、已有工时计算器互链。代码位于 `features/web-tools/` 和 `.web.tsx` 路由。没有修改原生规则、原生页面或官网；没有提交、推送、创建 PR 或部署。工作区原有未提交修改保留。

全部新页面保持 `draft`、`contentReviewedAt: null`。未开预览时访问新页面返回 404；开启预览时输出 noindex/nofollow，无 draft hreflang，也不进入 sitemap。Next 会为父级语言参数生成部分 404 HTML，它们不是可用的草稿内容页。页面正文、默认答案、固定示例与链接均可从 HTML 读取；静态数值示例与交互共用同一算法。CN 通知日期与未明确的生效日期分开：`sourcePublishedAt=2025-01-01`、`effectiveFrom=null`。

## 自动检查

环境：macOS 27.0.1；Next.js 15.5.20；本机 Node 22.22.3。仓库声明 Node 24.x，本轮未重现 CI 的 Node 24 环境。

| 检查 | 结果 |
| --- | --- |
| `npm run lint` | 通过 |
| `npm test` | 53 文件、604 测试通过；其中新增工具 50 测试 |
| 普通 `npm run build` + `npm run check:build:web` | 通过；本机 HTTP 请求 `/en/tools` 和 `/en/salary/us` 均返回 404 |
| `WEB_TOOLS_PREVIEW=1 npm run build` + Web 产物检查 | 通过；10 份完整工具 HTML，静态内容/canonical/noindex/无草稿 alternate 检查通过 |
| `WEB_TOOLS_PREVIEW=1 npm run build:desktop` + `npm run check:build:desktop` | 通过；无 salary/tools 导出，即使开启预览也不进入 Desktop |
| `git diff --check` | 通过 |

浏览器发现新 features 目录未进入 Tailwind 扫描，已补齐仅 Web 的扫描路径；修复后重新运行 lint、604 项测试、Desktop 导出和预览 Web 构建。桌面图标编译第一次受本机服务访问限制失败，允许访问后完整构建通过，未启动 iOS 视觉验收。

[静态 HTML 检查记录](review/html-checks.json)；[浏览器尺寸检查记录](review/browser-checks.json)。这些结果是本次本机检查，不等于生产/Vercel 预览验收。

## 实际浏览器检查

使用 macOS 上的 Codex 内置浏览器。10 页 × 390×844 / 1280×800 × 浅色 / 深色，共 40 组 DOM 宽度检查，没有横向溢出；主题通过既有 Web App 控件切换。实际查看中英代表页截图，未声称逐页进行完整视觉或屏幕阅读器审查。结束时恢复系统主题和浏览器尺寸，停止本机服务。

实测交互：

- 时薪37.5、每周40小时、每年50付薪周，年收入75,000、月均6,250。
- 月薪10,000、13薪、额外奖金5,000，年收入135,000、月均11,250，基础月薪仍10,000。
- 切到已含奖金的年收入135,000，没有再加入先前的5,000奖金。
- 中文输入21,750，21.75×8参考得到日1,000、小时125；实际工时与计薪参考可切换。
- 每周0小时、月工作32天显示错误；恢复示例正常。
- 输入改变后 URL 不变；刷新恢复默认金额。
- 工具目录与21.75页面链接可点；从重置按钮按 Tab 可到计算口径选择。
- 最后检查的中文页面无控制台 error。

代表截图：

- [英文桌面浅色](review/en-desktop-light.jpg)
- [英文手机浅色](review/en-mobile-light.jpg)
- [中文桌面深色](review/zh-desktop-dark.jpg)
- [中文手机深色](review/zh-mobile-dark.jpg)

## 隐私与未完成项

新工具只用 React 页面状态，代码未调用网络、统计、存储或 URL 写入；表单没有可提交到服务器的 action，元数据只包含编辑好的公共示例和说明。浏览器确认 URL 不带输入且刷新不保留输入。本轮工具接口不支持网络抓包，因此未声称完成请求正文、生产分析脚本或日志的抓包验证。没有新增统计事件，也没有验证生产聚合入库。

发布前仍须完成：逐页人工内容/语言审核、CN 参考映射与适用范围复核、Node 24 CI、Vercel 预览与大陆网络可达性、GSC 启动基线与索引观察。没有用短期 App 下载或安装数据替代这些结果。后续日期/轮班/比较工具与其他语言市场未完成。

## 本地复现

在产品仓依次运行（构建前先停止现有 dev 服务）：

```sh
WEB_TOOLS_PREVIEW=1 npm run build
WEB_TOOLS_PREVIEW=1 npm run start -- -H 127.0.0.1 -p 3100
```

查看 `http://127.0.0.1:3100/zh-CN/tools` 或 `http://127.0.0.1:3100/en/tools`。只有显式预览开关才显示草稿。不要把预览开关当作上线审核；生产构建不设此变量。审核通过后按注册表逐页登记审核日期与发布状态，再走独立 Web PR/Vercel 流程。

辅助 Agent 实际使用：计算引擎和页面实现各为 GPT-6.1 Sol / High；P0 台账为 GPT-6 Luna / XHigh。主 Agent 审查代码、修复样式扫描、补集成测试并完成构建和浏览器验收。没有调用 Claude，也没有以子 Agent 完成声明替代检查。
