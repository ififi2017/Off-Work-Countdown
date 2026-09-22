# AGENTS.md 压缩记录

本次以工作区完整的 `AGENTS.md`（698 行）为基线；会话附带的文本在 iOS
上传说明处截断，因此没有用它覆盖工作区后半段的要求。保留英文指令，避免
翻译引入术语和约束歧义。此记录是交付说明，不属于常驻指令，也无需每次读取。

## 官方文章如何用于这次修改

2026-09-19 阅读了用户提供的 OpenAI 博客
[Rethinking skills and prompts for GPT-6 Astra](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)。
文章的适用建议是：技能描述简短且触发准确；复杂资料按需加载；删除过时的
步骤指挥和重复测试提醒；明确授权边界与完成标准；考虑其他模型也会读取这些
指令。文章没有要求删除项目特有的约束或一律放宽权限。

具体应用：根文件保存跨端约束与检查入口，专项流程进入有明确触发条件的版本
控制文档；技能仍然可选，不让新克隆或 CI 依赖本机技能。这里的分文件方案是
结合本仓库作出的设计选择，不是声称博客规定了这些文件名或划分方式。

## 完整交付

- [AGENTS.md](../../AGENTS.md)：根指令、架构/隐私/UI/本地化约束、变更检查表。
- [iOS 指南](../agent-guides/ios.md)：项目注册、测试陷阱、按请求执行的视觉 QA、CI。
- [发布指南](../agent-guides/releases.md)：版本、渠道、签名、上传、商店媒体和下载计数。
- [技能指南](../agent-guides/skills.md)：可选技能索引、安装规则、项目特有覆盖。

四份文件共同组成完整指令集，必须一起保留；根文件已声明其效力和读取条件。
配套文档位于正常版本控制目录，不在被忽略的 `.agents/skills` 中。

## 主要改动

1. 合并重复出现的 TypeScript/Swift 同步规则、fixture 要求、版本一致性、
   Desktop 发布步骤、iOS build number 和本地构建门槛。
2. 将“发生过什么、当时错了多少次”的叙述改为“触发条件、约束、验证方式”。
   删除重复事故故事和历史测量值，保留机制、API 名、路径、参数和失败表现。
3. 检查要求改成变更范围表，不再让一般编辑误读为每次必须完成三端全套构建。
   原有共享渲染/路由/语言/配置、Rust、共享规则和 iOS 的强制检查未降低。
4. iOS、发布签名和技能细节按需读取；保留具体命令，只去掉能由命令或规则本身
   表达的重复讲解。没有把正文简单转移后宣称全部 token 都节省了。
5. 合并文案原则与 UI 判断，保留尺寸、平台差异、既定设计系统和所有特殊例外。
6. 修复一处已确认的过时冲突，详情如下。未修改应用代码、技能文件或发布设置。

## 过时冲突的处理

原文件 Skills 段落仍说“the ban on porting schedule, summary or salary rules into
Swift”，但其架构段及交付检查已经要求 plan 019 的 Swift 实现与 TypeScript 同步。
以下现有源文件也明确记录并实现了这一架构：

- [ScheduleRules.swift](../../src-mobile/ios/App/App/Native/Models/ScheduleRules.swift)
- [SummaryRules.swift](../../src-mobile/ios/App/App/Native/Models/SummaryRules.swift)
- [ScheduleRuleFixtureTests.swift](../../src-mobile/ios/App/AppTests/ScheduleRuleFixtureTests.swift)

因此将旧禁令统一为现行要求：TypeScript 是共享行为规范，Swift 同步实现并通过
fixtures 验证，禁止另写同一数字的公式。此处是纠正明确冲突，不是默默放宽约束。

## 保守保留项

- iOS 视觉测试必须有明确请求；无请求时仍可完成无界面构建和自动测试，且不因
  缺少视觉 QA 阻塞交付。没有按博客的一般自主性建议删除这条用户边界。
- `qaOrientation` 修复仍标为“需完整 sweep 验证后才能相信横屏列”。本任务没有
  执行视觉测试，不能把未知状态改成已验证。
- 签名 Team ID、App Group 差异、profile 路径、手动 Organizer 导出、Developer ID
  策略都保留。它们可能随环境变化，但未获得证明其已过时的依据。
- CloudKit/备份许可、薪资隐私边界、19 个 UI 语言与 17 个商店语言的区别、媒体
  数量/分辨率/API display type、镜像下载统计修正均保留。
- `-only-testing` 零测试、进程崩溃后的假成功、时区隔离、串行性能测量、
  `ImageRenderer` 环境缺失等不能由普通模型默认行为推导出的规则均保留。
- 最小化并不替代发布门槛、跨端构建或有效测试计数；这些项目要求没有删除。

## 要求覆盖对照

原版行号指修改前的 698 行文件。表中合并/迁移均保留实质要求。

| 原版范围 | 覆盖内容 | 新位置 |
|---|---|---|
| 3–24 | 三端技术栈、原生 iOS、旧 Capacitor、共享范围、本地优先与 CloudKit 例外 | 根文件 Scope、Privacy |
| 25–34 | countdown/reminder 规范、Rust 边界、提醒验收 | 根文件 Shared rules |
| 35–65 | Swift 职责、oracle/fixtures、禁止重复公式、扩展排班与 live roster、禁止 JSCore | 根文件 Shared rules + iOS Project |
| 66–86 | segments、构建目标、route.ts、两种 macOS timer 与 Windows 实现 | 根文件 Shared rules |
| 88–120 | 六项 UI 判断与既定设计系统 | 根文件 UI |
| 122–149 | Desktop 布局、Mini Timer 状态、加班/下一班规则、木鱼与 debug 开关 | 根文件 UI、Shared rules |
| 150–159 | Windows 标题栏、禁止缩放/选择、双主题和长文本验证 | 根文件 UI |
| 161–175 | 服务用户的文案、技术说明、各状态文案审核 | 根文件 UI and copy |
| 176–202 | 双文案来源、19 语言、Watch/widget、字符串检查器可识别形式 | 根文件 Localization |
| 203–213 | 长内容语言范围、in-app 与 system 语言差异 | 根文件 Localization |
| 215–224 | 分享、匿名计数、Desktop 网络与 About 声明 | 根文件 Privacy |
| 226–233 | 子代理职责及禁止使用最高档模型 | 根文件 Work |
| 235–279 | 可选技能、忽略路径、安装、优先级、技能索引、ponytail 三项覆盖 | 根文件入口 + Skills 指南；旧 Swift 禁令按上述证据纠正 |
| 281–313 | 安装、公共检查、dev/build 互斥、Web 构建发布 | 根文件 Work + Releases |
| 314–341 | Desktop 构建、三个渠道、条件编译、四平台 Draft Release | 根文件命令 + Releases Versions and channels |
| 343–395 | Mac App Store 类型、App Group、profiles、证书、构建和 entitlement 检查 | Releases Mac App Store signing |
| 397–440 | iOS 项目/targets、Universal Purchase、synchronized folders、跨 target 文件 | iOS Project |
| 442–448 | ImageRenderer 独立环境与假成功 | iOS Rendering and automated checks |
| 450–509 | 视觉授权、三种壳层/sweep、orientation、check:ios、headless 命令 | 根文件视觉边界 + iOS Project / Visual QA / 构建命令 |
| 511–568 | 测试标识符、实际执行数、时区、串行性能断言 | iOS Rendering and automated checks |
| 570–580 | archive、build number、Organizer、自动导出前签名约定 | Releases iOS upload / Versions |
| 582–617 | Xcode Cloud、Rust 双平台 CI、变更范围检查、共享规则 parity | 根文件检查表 + iOS CI |
| 618–632 | 全部版本文件、独立 build number、iOS 发布渠道 | Releases Versions and channels |
| 633–658 | 商店语言、截图/视频、旧 display sets、共享 App Info、Apple frames | Releases Store media and metadata |
| 659–684 | PR/标签、部署与 tag、镜像回退、密钥和签名策略 | 根文件 Work + Releases |
| 686–698 | 保留用户变更、生成物、计划更新、下载计数、提交/PR 说明 | 根文件 Work + Releases |

## 体量与验证

字符按 Unicode 字符数计算，包含空格/换行；token 用“字符数 ÷ 4”统一粗估，
不是 GPT-6 Astra 的 tokenizer 实测。技术标识符可能让实际 token 数产生偏差。
原文件为 40,762 字符、40,890 UTF-8 字节。

| 范围 | 字符 | 行 | 粗估 token | 相对原版减少 |
|---|---:|---:|---:|---:|
| 原 AGENTS.md | 40,762 | 698 | ≈10,190 | 0.0% |
| 新根 AGENTS.md（常驻） | 13,195 | 198 | ≈3,299 | 67.6% |
| 新根文件 + 三份指南（合计） | 27,941 | 468 | ≈6,985 | 31.5% |

根文件的减少代表默认仓库指令加载量；专项任务仍会读取对应文档。整体缩减只
计算根文件和三份指令指南，不计本审阅记录；不代表整个会话、插件/技能描述或
系统提示的总 token 都按同比例减少。没有删除或改写本机技能描述。

验证包括原文逐段覆盖核对、关键路径/API/参数对照、所有 Markdown 文档链接
目标存在性、代码围栏配对及 `git diff --check`。这是纯文档改动，未运行应用
构建、测试、模拟器或发布命令。
