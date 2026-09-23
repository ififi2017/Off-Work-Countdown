# DoneAt Android 移植交接包 · 从这里开始

**文档版本：1.1 / 2026-09-21**  
**交付对象：项目负责人、执行开发 AI、人工代码审查与发布人员**  
**目标：以 Kotlin + Jetpack Compose + Material 3 Expressive 原生实现 iOS 功能，并完成 Google Play 发布准备。**

## 0. 这份交接包是什么

这是基于真实仓库核对的产品与实施规范，不是已经完成的 Android 工程，不是构建成功证明，也不是 Google Play 审核通过保证。作者已读取关键代码与历史修订，但没有逐行审完所有 Swift 文件、运行 iOS/Android 工程、连接生产 CloudKit 或操作 Play Console。完整枚举与差分测试仍是执行阶段的第一道门禁，不能省略。

固定源版本：

```text
repository: https://github.com/ififi2017/Off-Work-Countdown
branch_at_audit: main
source_commit: 9252fdfdc66aab88b4acb7493684f11991fd773d
source_commit_time: 2026-09-20T14:07:09Z
proposed_android_root: src-mobile/android/
```

固定提交与关键契约的源码入口见 [R01]；基线提交页面可在05的版本信息中定位。主分支存在 3.2.0 相关开发；它与 App Store 当前公开二进制不能直接画等号。本包默认移植以上提交的 iOS 实现。若负责人要求对齐另一发布 tag，先生成基线差异清单，再更新本包，禁止默默跟随 main 改需求。

## 本轮已确认的产品决策（1.1）

负责人于 2026-09-21 回复上一轮六项建议：**“1-6 我觉得都 OK”**。编号指聊天中的六行，不是 D-01～D-06。下列方向已获确认，不要让下一位 AI 再次询问同一选择。

| 聊天项 | 对应决策 | 已确认执行方向 | 未因此自动确定的内容 |
|---|---|---|---|
| 1 · 收费 | D-01 | 保留月订阅、年订阅、终身一次性买断 | 各地区价格、试用/优惠条件、生产商品配置 |
| 2 · 同步 | D-02 | 手机/平板正式首发包含 Google Drive appDataFolder 的 Android 多设备同步；默认关闭，用户主动授权后启用 | OAuth/Cloud 项目配置与真实双设备验收；未额外修改权益到期后的同步规则 |
| 3 · 跨平台 | D-03 | 首发通过 JSON 双向迁移业务数据；不做 iOS/Android 自动同步，两个商店购买权益独立 | 不授权新增 DoneAt 账号或改造 iOS 云端 |
| 4 · 手表 | D-05 | 手机/平板先发布，Wear OS 留作独立后续阶段，不阻塞首发 | 手表阶段的启动时间、投入和发布签收 |
| 5 · 验证服务 | D-08 | 采用只处理必要购买信息的小型服务端验证服务，不上传工资/工作记录，不新增 DoneAt 账号 | 实际部署平台、域名、预算、凭据及上线操作 |
| 6 · Play 账户 | D-11 | 按实际 Play Console 账户确定验证、测试与生产访问要求 | 是否已有账户、个人/组织、创建时间、生产访问状态均未知 |

完整决策及剩余配置见 `05_SOURCES_AND_DECISIONS.md` 和 `decisions.json`。D-04、D-06、D-07、D-09、D-10 保持原建议/待确认状态，不因这次回复自动变成已批准。价格、试用或账户资料缺失不阻止源码审计、纯 Kotlin 规则和本地界面开发，但不能据此假填正式商品或发布表单。

本轮是**文档决策更新**：未启动 Android 实现、未修改 GitHub 仓库、未部署云服务、未操作 Play Console；同意方案不等于已经完成外部配置或获准立即发布。

## 1. 阅读顺序

| 文件 | 用途 | 什么时候读 |
|---|---|---|
| `00_START_HERE.md` | 范围、事实等级、完成定义 | 每次交接必读 |
| `01_PRD.md` | 功能清单、逐页行为、免费/Plus、视觉和产品验收 | 开发前通读，做某功能时重读对应条目 |
| `02_TECHNICAL_GUIDE.md` | Kotlin 架构、规则、数据、后台、支付、同步 | 建工程前通读；实现时按领域加载 |
| `03_AI_EXECUTION_PLAN.md` | 有依赖关系的任务卡、命令、证据和禁止事项 | 每次选择下一个任务时使用 |
| `04_QA_AND_PLAY_RELEASE.md` | 测试矩阵、发布门禁、人工 Console 操作 | 测试与上线阶段；不可到最后才读 |
| `05_SOURCES_AND_DECISIONS.md` | 已读证据、参考网址、已确认决策与剩余配置 | 遇到争议或政策变化时使用 |
| `06_PROMPT_FOR_IMPLEMENTING_AI.md` | 可复制给另一个 AI 的启动指令 | 新会话入口 |
| `07_TEST_CATALOG.md` | 具体验收案例、预期和自动化层级 | 写测试时逐条实现 |
| `acceptance_examples.json` | 人工设计的确定性计算/身份示例 | 只能作补充，不能代替原仓库 oracle |
| `tasks.json` | 28 张任务卡的依赖与状态 | 给上下文较小的 AI 维护进度 |
| `test-catalog.json` | 137 条测试规范，初始全部 NOT_RUN | 自动建立测试追踪表 |
| `references.json` | 52 项源码和官方参考网址 | 按引用 ID 定位资料 |
| `decisions.json` | 六项确认映射、其余 D 项与外部配置状态 | 开工、交接及发布前必读 |
| `CHANGELOG.md` | 1.1 相对 1.0 的变更和未执行范围 | 确认没有误用旧版待定项 |

文档里的 `[Rxx]` 指固定提交源码，`[Axx]` 指官方平台资料。每份 Markdown 末尾有其引用网址，完整目录在 05。公开政策与依赖版本查询日期均为 2026-09-21，上架前必须重新核对。

## 2. 事实等级与冲突处理

- **已验证事实**：关键源码或明确后续用户修订中可直接看到的现有行为。
- **Android 方案**：本包建议的新架构、界面、包名、质量指标和平台替代方案；不是 iOS 已有实现。
- **已确认决策**：D-01 收费模式、D-02 Drive 同步、D-03 首发互通边界、D-05 手表延后、D-08 购买验证服务；D-11 仅确认按实际账户核验的流程。具体状态见 05 与 decisions.json。
- **待确认/待配置**：价格、试用、生产环境、实际 Play 账户资料，以及本轮未覆盖的 D-04/D-06/D-07/D-09/D-10。不得把方向确认冒充参数、外部账户或验收已完成。
- **待全量审计**：路径已核实、功能入口已核实，但文件剩余内容或全部调用点尚待开发 AI 阅读。不是“功能不存在”。

优先级：安全与平台强制限制 > 负责人在这些边界内针对 Android 的最新明确决定 > 固定基线的当前实现及其测试 > 后续修订计划 > 旧计划/README。若测试与代码不一致，记录最小复现和产品影响，再判定；不能通过改 expected、删测试、降精度或重生成快照掩盖问题。[R01]

## 3. 不能改动的底线

原生 Kotlin/Compose；不使用 WebView、Capacitor、Flutter、React Native 或运行时 JavaScript 引擎替代本次移植。保留 DoneAt 品牌与本地优先原则。不擅自新增 DoneAt 账号、广告、行为分析 SDK。业务数据与购买权益分离。工资不得出现在桌面小组件、通知正文、普通分享卡片/链接、日志或分析载荷；用户主动导出的备份是单独授权的数据导出流程。[R01], [R07]

“完整移植”必须覆盖：排班与倒计时、收入、记录及人生、专注、提醒、小组件、数据迁移、隐私、付费体系、19 语言、手机/平板适配，以及已确认的 Android 同步方案。分阶段开发只是实施顺序，不代表可以把未完成部分叫作最终完整版。

已确认手机/平板首发覆盖 FR-01～FR-20，包括真实 Drive 同步和购买验证服务。Apple Watch 是独立 watchOS 目标；Wear OS 的 FR-21/T27/QA-137 保留为后续阶段，当前不计入首发发布阻塞，也不能标为已完成。iOS/Android 首发仅做 JSON 数据迁移，购买权益独立，不做自动跨平台同步，不新增 DoneAt 账号。购买验证服务获方案批准，不表示生产部署和发布已执行或可以跳过操作授权。

## 4. 两个容易误读的当前行为

当前免费记录窗口是**今天及之前六个记录时区的自然日**，不是 168 小时。当前源码对“从未购买的免费用户”和“曾有权益、现已过期/撤销的用户”区别处理：后者停止新增工作观测。Android 暂按基线实现并独立测试；产品负责人可以通过 D-07 明确改变它。权益到期不等于删除已有数据。[R05]

当前备份协议**导出 schemaVersion=6，接受 1…6**。Android Room 数据库版本是另一个独立版本号，禁止把数据库 version=1 写成备份版本、或把自创 JSON 标记为兼容 schema 6。[R07]

## 5. Definition of Done

所有范围内 FR 条目能追溯到实现和测试；源码审计无未解释缺项；TS→Kotlin、Swift 特有规则→Kotlin 差分通过；旧备份及双向往返通过；Release 构建通过；未用假的支付/同步服务充当生产实现；真机完成权限、后台、恢复购买和离线场景；19 语言与大屏验收；负责人完成真实 Play 配置并签收。

报告必须分别标明“代码完成”“自动化通过”“真机通过”“外部服务配置完成”“允许发布”，不能合并成一句“全部搞定”。没有设备、凭据或测试人员时，保留对应阻塞项并交付其余成果，不能编造验证记录。


---

## 本文参考网址

- **R01** · [仓库根 AGENTS：架构、隐私、规则与本地化契约](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md)
- **R05** · [Plus 权益与免费窗口](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift)
- **R07** · [RecordJSON：跨平台备份协议与合并](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift)

[R01]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md
[R05]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift
[R07]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift
