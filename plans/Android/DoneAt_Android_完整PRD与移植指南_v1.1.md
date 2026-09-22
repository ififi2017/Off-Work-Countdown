# DoneAt Android · 完整 PRD、移植与技术指引

**版本：1.1 · 2026-09-21 · 产品方向确认版**

固定 iOS 源码：`9252fdfdc66aab88b4acb7493684f11991fd773d`。目标：Kotlin / Jetpack Compose / Material 3 Expressive / Google Play。

本版落实负责人“1-6 我觉得都 OK”的确认；聊天六项映射见开始须知与第05章，不能误解为D-01至D-06全部获批。

本文件包含8份Markdown正文及变更记录。配套ZIP保留28张任务卡（27张首发NOT_STARTED、Wear任务T27为DEFERRED）、137条尚未运行的测试（其中QA-137属后续Wear）、12项独立样例、52项原参考入口，并新增decisions.json记录批准范围与外部配置。

这不是已经完成的Android工程、部署或发布报告。使用本版替代1.0；无需同时喂给开发AI两个版本。

阅读顺序：开始须知 → PRD → 技术方案 → 实施任务 → QA与Play发布 → 来源与决策 → AI提示词 → 验收案例 → 变更记录。


---

<!-- section: 00_START_HERE.md -->

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


---

<!-- section: 01_PRD.md -->

# 01 · DoneAt Android 产品需求文档

## 1. 产品定义

DoneAt 是让用户看清当前班次剩余有效工作时间、阶段进度、预计收入，并回顾与规划工作时间的本地优先工具。Android 版保留产品能力，使用 Android 原生交互重新表达，不逐像素复制 iOS Liquid Glass，也不把原本的记录和专注删成一个简单时钟。[R01], [R11]

**用户目标**：打开就知道“现在在哪个阶段、还要工作多久、接下来做什么”；修改班次后全应用一致；退出应用不丢失计时；换机不丢历史；不因通知权限或购买网络异常失去基本使用能力。

**非目标**：企业考勤与工资结算、法定退休/劳动法计算、实时汇率、健康诊断、位置打卡、工资上传分析、社交账号、广告、后台保活工具、桌面端悬浮窗照搬。收入和人生数字必须用“预计/估算”语义，不能宣称等于真实发薪或法定退休待遇。

## 2. 首发范围与用户类型

建议最低 Android 8.0 / API 26（D-04）；手机、平板、可折叠窗口均支持；首发从 Google Play 分发。无 Google Play 服务的设备至少能运行本地核心，支付和 Drive 同步应展示能力不可用，而不是崩溃。是否专门维护中国大陆商店、厂商支付和无 GMS 云同步为另一个发行项目，不在本次默认范围。

用户状态：新用户、从 iOS 导入用户、免费用户、有效月/年订阅用户、终身用户、待支付用户、宽限期用户、失效用户、已开启同步用户、仅本地用户。权限状态与购买状态相互独立，不创建“授权一次就默认全部权限”的捷径。

## 3. 功能需求总表

下表为完整移植的追踪主键。优先级“必须”指正式完整版，不意味着第一个开发迭代必须同时完成。

| ID | 能力 | 要求与边界 | 优先级 |
|---|---|---|---|
| FR-01 | 首次启动与恢复 | 新建、恢复 JSON、选择性云端恢复；不得上传欢迎默认值覆盖旧数据 | 必须 |
| FR-02 | 固定排班 | 上下班、工作星期、手动模式、跨夜、班中休息、排班时区 | 必须 |
| FR-03 | 扩展排班 | 多班型、工作/休息班型、周期、大小周、轮换、自定义、手排、继承与清空 | 必须 |
| FR-04 | 计时与当天调整 | 未开始/工作/休息/加班/已结束/休息日/未排班；提前结束、撤销及继续加班按源码 | 必须 |
| FR-05 | 薪资与隐私 | 月/日薪、平均工作日、年终奖参数、当前累计、隐藏与身份确认 | 必须 |
| FR-06 | 记录与可视化 | 日详情、周/月/年、实际与预计、来源标记、免费窗口、编辑入口 | 必须 |
| FR-07 | 历史编辑 | 确认按计划、未工作、自定义时间、请假/补班/清除修正；历史快照不漂移 | 必须 |
| FR-08 | 人生 | 阶段、职业经历、空档、退休年龄、历史/未来收入、未来固定比例调整 | 必须 |
| FR-09 | 专注 | 时间画布、任务、番茄钟、休息、模板、收藏、放置/排序、重启恢复 | 必须 |
| FR-10 | 提醒 | 进度/班次/休息/微休息/周期总结/专注；权限与调度降级 | 必须 |
| FR-11 | 系统持续展示 | 普通通知的当前阶段及适当系统计时；不承诺等同灵动岛 | 必须，允许平台差异 |
| FR-12 | 桌面小组件 | 多尺寸、状态与下一阶段、点击直达、薪资隔离、过期态 | 必须，刷新受系统约束 |
| FR-13 | 分享与链接 | 无工资卡片、班次链接、Android Sharesheet、链接导入确认 | 必须 |
| FR-14 | JSON 备份与迁移 | v1–v6 导入、v6 导出、预检、冲突预览、原子提交、失败可恢复 | 必须 |
| FR-15 | 云端恢复与同步 | Android 私有同步替代 CloudKit；恢复、开关、冲突、删除语义不丢 | 必须；D-02 已确认 Drive |
| FR-16 | Plus 与 Play Billing | 月/年/终身、适用优惠、恢复、取消/宽限/过期/撤销、可靠验证 | 必须；D-01 模式已确认，价格/优惠待配置 |
| FR-17 | 设置与应用服务 | 主题、语言、记录时区、通知、数据、Plus、关于、反馈、评价 | 必须 |
| FR-18 | 19 语言与无障碍 | 完整文案/复数/RTL/大字体/TalkBack/键盘/触控替代操作 | 必须 |
| FR-19 | 自适应布局 | 三个主导航、手机横竖屏、平板分栏、折叠/分屏状态恢复 | 必须 |
| FR-20 | 发布与隐私 | Release/AAB、签名、数据申报、政策、测试轨道、回滚预案 | 必须 |
| FR-21 | Wear OS 扩展 | 同源纯 Kotlin 规则、离线排班、无薪资传输、表盘复杂功能 | D-05 已确认延后，不在首发范围 |

FR-02～FR-09 的细小开关、菜单与参数必须在 M0 从现有路由、设置模型、翻译 key、测试枚举成子条目。文件名不能证明某个功能已移植；只有可执行用例与结果能证明。

## 4. 免费与 Plus 矩阵

按当前代码而不是旧营销描述定义。[R05], [R09], [R12]

| 行为 | 从未购买的免费用户 | 有效 Plus / 终身 | 权益失效后 |
|---|---|---|---|
| 基础排班、主倒计时、基础收入显示 | 可用 | 可用 | 保留基础使用 |
| 新工作观测 | 继续采集，服务免费窗口 | 继续采集 | 当前基线停止新增；D-07 可另行修订 |
| 最近七个自然日记录 | 可查看允许的明细 | 可查看 | 不删除数据；显示范围由统一访问策略处理 |
| 图表、人生、记录页编辑、专注 | Plus 门禁 | 可用 | 门禁恢复；不销毁数据 |
| 初次开启同步、周期结束总结开关 | Plus 门禁 | 可开启 | 不自行推断“关闭所有已经开启的同步”；按源调用点和 D-02 冻结规则 |
| 恢复已有备份/云端数据 | 不能要求先重新购买才恢复 | 可用 | 保留恢复路径；恢复不等于获得付费编辑权限 |
| 导出自己的数据、删除自己的数据 | 可用，必要时身份确认 | 可用 | 仍可用 |
| 小组件 | 基础投影可用 | 可用 | 不塞入付费数据泄漏 |
| Watch 的现行产品定位 | 当前源码说明 Watch App 和两种复杂功能免费 | 同左 | 不自行改为 Plus |

针对“失效后已开启同步”的具体门禁，M0 必须检查当前同步引擎及测试；只看到 UI 上的“开启需 Plus”不等于后续每次同步都要 Plus。Android 推荐保留已开启同步的安全运行与用户数据控制；本轮 D-02 只确认提供商、默认关闭及首发范围，不自动批准修改权益到期后的规则。M0 仍需冻结源行为，确需产品变更时记录补充决策，不能靠缓存布尔值偶然决定。[R01], [R12]

免费门禁不是透明度为 0 的覆盖层。受保护页面的 UiState 不得带被遮挡的工资、历史值和任务内容；Semantics、复制、截图分享、通知投影同样不能泄露。

## 5. 信息架构

维持三个主入口：**计时、记录、设置**。专注从计时页和记录相关上下文进入，是完整功能页但不擅自增加第四个主 Tab。记录中的“人生”是记录尺度/入口，不与主页竞争。[R11]

```text
欢迎 / 恢复
└─ 主壳（计时 | 记录 | 设置，各自保留导航栈）
   ├─ 计时 → 当天调整 / 排班 / 专注画布 / 分享
   ├─ 记录 → 日详情 / 周 / 月 / 年 / 人生 → 编辑 / 职业经历
   └─ 设置 → 排班、薪资、提醒、健康提醒、主题、语言、记录时区
             Plus、同步、数据管理、冲突中心、关于
```

Android 新增的“通知渠道/精确提醒状态/Google Play 管理订阅”属于平台适配入口。不得保留“打开 iCloud 设置”“App Store 恢复购买”等失效操作。

## 6. 逐页交互与状态

### 6.1 欢迎与首次恢复（FR-01）

首屏可选择开始设置、从文件恢复、从已选云服务恢复。基础使用不强制登录、付费或授权通知；Google 授权只能在用户选择云功能后请求，不能照搬 iOS 的账号可用性假设。已有本地有效设置优先打开主界面，不重复欢迎。

恢复流程：选择来源 → 只读查询 → 完整下载候选副本 → 校验/差异预览 → 用户确认 → 原子提交 → 进入主界面。查询失败、授权取消、超时均不是“云端为空”。新设备恢复不依赖旧设备同时启动。未完成恢复前禁止把默认班次上传为新版本。[R14]

新建流程：班次与工作日 → 休息/收入可跳过 → 提醒可跳过 → 完成。设置存为草稿，最终确认才提交；后台中断后恢复草稿，不生成业务观测或同步编辑版本。Plus 展示可关闭，不阻断免费开始。

### 6.2 主计时（FR-04/05）

顶部：日期、当前班次及次级专注入口。中心：状态标签、主时间、有效进度。下方：预计收入（按隐私设置）、今天摘要、接下来、主要操作。分享、设置等不能比倒计时更抢眼。

| 状态 | 主时间含义 | 附加说明 | 行为 |
|---|---|---|---|
| 未开始 | 距本次开始的时长 | 展示班次起止、下一休息 | 编辑班次/按既有规则开始 |
| 工作中 | 剩余有效工作时间 | 不把未计薪休息当工作时间 | 当天调整、进入专注 |
| 休息中 | 距本次休息结束 | 有效工作累计冻结 | 查看下一工作段；相关设置 |
| 加班中 | 剩余有效延长时间 | 标记加班，收入按原计划时薪延伸 | 调整加班/结束 |
| 已结束 | 完成态，不显示负数 | 下一班次或下一休息日 | 撤销/继续加班按源行为 |
| 休息日 | 明确“今天休息”及下一班次 | 不伪装成 00:00 未开始 | 编辑安排 |
| 未排班 | 明确“尚未安排班次” | 与休息日区分 | 添加排班 |
| 规则/数据异常 | 保留已知有效数据，给出恢复操作 | 不显示虚构薪资/下一班次 | 重试/检查/导出 |

源码 `heroRemainingMs` 在未开始和休息阶段使用对应边界，工作阶段使用有效剩余。因此页面不能一律显示 `endAt - now`。主倒计时、预计结束钟点、专注倒计时必须分别标注，避免把三个时间混为一个。[R02]

今天修改班次时，应展示“应用到今天 / 从下一次开始”的源规则允许选项；当前快照固定与未来规则更新分离。不能因为用户改了常规下班时间就追溯覆盖历史或丢掉正在运行的专注。

### 6.3 排班（FR-02/03）

基础编辑区：时间、工作星期、休息区间、排班模式、时区说明。复杂设置渐进展开，不能强迫简单朝九晚六用户理解轮班模型。

高级编辑区：班型库 + 周期编辑器 + 月历手排。支持 weekly、alternatingWeeks、rotation、custom；周期有锚点日期；一天可以是工作班型、休息班型或未安排。手动赋值、撤销赋值、恢复规则、清空从某日起的自动延续必须是不同动作。[R03], [R04]

已核实约束：班型名去首尾空白后 1–40 字符；时刻 0–1439 分钟；周期 1–366 天；终点早于或等于起点表示次日终点；休息启用时必须有正时长。保留已归档班型供历史解析。输入校验提示就地显示，不保存半合法状态。[R03]

手排优先于周期和继承，但节假日、清空边界、冻结历史、固定快照回退的完整组合应以解析器和 Swift 测试逐分支移植，不能简单拼一个“总优先级列表”覆盖所有层。没有明确分配不是休息日解析成功；无规则月份的按日期继承必须考虑短月、闰月、人工空档及源测试。[R04]

节假日数据本地打包、保留版本和授权；不要自动按系统地区启用法律性质的工作安排，不额外请求位置。数据覆盖之外不猜测下一年假期，显示覆盖范围并允许手工安排。

### 6.4 薪资（FR-05）

支持源码已有月薪/日薪输入及平均工作日、年终奖折算参数；货币显示沿用源配置语义，若源无货币切换不得擅自加入自动换汇。金额为空与 0 不混同；拒绝负数、无限大、溢出和不合格式；读取用户地区小数分隔符，存规范数值，不存格式化文案。

明确两类口径：计时页的今日收入按有效工作段进度；记录页固定月薪按后续确认的自然日口径分摊，不因请假或少记工时扣薪。完整月月基数包含既有年终奖月均份额；日薪仍依工作日规则。两者标签说明一致，不强行用同一个“日工资×天数”函数代替全部业务。[R02], [R10], [R14]

隐藏收入是统一状态，眼睛图标表达点击后动作。隐私确认使用 Android 生物识别/设备凭据能力；失败/取消不揭示、不导出。无设备锁的降级体验需要明确提示而不是假装身份验证成功。[R09]

### 6.5 记录与历史（FR-06/07）

记录页提供日/周/月/年尺度及人生入口；当前选择的日期、尺度、滚动位置在导航和窗口变化后稳定。用源记录时区确定“今天”与免费窗口，不随旅行把记录移动到另一日期。[R05], [R08]

日详情：计划区间、最终解析区间、实际观测/人工确认的来源、休息与加班、收入及计算口径、修改入口。周/月/年：实际与预计分别编码，不重复统计已发生部分。图表下面同时提供文本汇总/可访问列表。

历史最终计划解析链：有效日修正 > 日历例外 > 获胜排班快照；清除修正表示继续向下解析。工作观测不进入这条计划优先级链，它是另一类事实证据。UI 必须区分“按计划推算”“手动确认”“观测所得”“无法解析”。[R08]

编辑日记录支持按源命令确认计划、未工作、自定义上下界、请假/补班/清除；保存失败保持原值与草稿。多层修改同一个数据库事务提交。时间边界调整必须保留计划内休息间隙，不能压成一条连续工作段。[R09]

### 6.6 人生（FR-08）

支持粗略工作起始年，或多段精确职业起止、月/年薪经历；可编辑出生/入学/工作建议与退休年龄，退休默认 60 是产品默认而不是法定判断。源计划后续修订须与当前源模型核验。[R13], [R14]

经历有稳定 ID，选中“已走过/未来推算”不会因重新分段跳到另一个对象。期间重叠应明确拒绝，空档收入为零。不推断涨薪、通胀和投资收益。未来收入调整是从某年龄起一次性降到固定比例并保持到退休，不是每年复利下降；起始年龄已过去则只调整今天之后的预测，历史收入保持原值。[R10], [R14]

未填写资料提供可跳过引导，不制造假数据。图表必须标记用户填写、默认建议、估算三类来源。

### 6.7 专注画布（FR-09）

保留单一画布、多尺度观察、任务卡、可用工作块、恢复块、番茄轮次、收藏和模板。基础用户经付费门禁后应回到原草稿和落位，不丢失“新建后放入下一块”上下文。[R06], [R11], [R05]

默认 25 分钟专注、5 分钟短休息、15 分钟长休息，每 4 轮长休；允许范围分别 10–60、1–15、5–30、2–6。改设置影响下一会话，不重写当前会话计划终点。精确行为以模型/Planner/Store 的分支及测试对齐。[R06]

任务最少包含标题、图标、预计轮数、计划日期/落位、完成与删除状态。收藏不是复制一套无关联内容；模板应用只放得下的完整任务前缀，不能擅自截断一个任务的轮数，也不能因今日短班修改模板本身。

拖动用于排程，但所有拖动都必须提供“移动到/上移/下移/选择时段”的可访问替代；长按不得覆盖点击查看。已有任务冲突、不够时间、未到可开始时间，分别提示，不统一报“错误”。

进入后台后不依赖 UI 协程维持状态；重开依据持久化终点和事件重建。不因恢复、双击按钮、通知动作与前台同时触发而创建重复会话；自动会话保持源确定性 ID。午休、工作结束、主动停止、其他设备胜出分别保留结束原因，不无声删除历史。[R06]

### 6.8 提醒与系统展示（FR-10/11/12）

提醒分类：班次/进度、休息边界、健康微休息、专注结束、周期总结。具体开关/阈值/文案由 `lib/reminders` 和源通知设置枚举，不凭“常见番茄钟”臆造新策略。[R01], [R18]

周期总结仅在已可靠解析到后续休息日时成立；普通进度提醒关闭不必关闭独立总结；同一结束点避免普通完成和总结双响。摘要不得包含薪资。源 iOS 功能的实际通知投递也有独立真机门禁，Android 不能以模拟器成功代替真机。[R15]

Android 13+ 通知被拒绝时，页面可继续使用，设置展示未授权及跳转；不要循环请求。精确提醒需用户授予相应特殊权限时再请求；无权限显示“提醒可能延迟”，不得谎称准点。不能通过申请不相干的前台服务、无障碍或悬浮窗绕过限制。[A10], [A24]

普通持续通知显示当前阶段、结束钟点/可适用的系统倒计时、点击返回。Live Update 的资格和系统呈现受限制，本项目没有已验证的可用性，不把它列为灵动岛的一比一承诺。[A11]

小组件至少提供紧凑计时、中等概览、大尺寸当天/下一阶段三个响应式布局。不能承诺 App 不运行时每秒执行 Kotlin 更新；界面显示结束钟点、正确阶段和必要的更新时间/过期提示。收入不进入小组件数据对象；不用“默认隐藏、点一下显示”变相突破。[R01], [A12]

### 6.9 分享与文件（FR-13/14）

普通分享卡片只含阶段、时长、进度、班次等允许字段；渲染输入是显式安全 DTO，不能截整个收入界面。使用系统 Sharesheet；临时图片经 FileProvider 授予读取，随后清理。分享链接只允许源协议中的起止时间，不加薪资、职业经历、用户 ID 或明文内部文件路径。[R01]

链接进入先解析/验证，再预览是否应用，不自动覆盖用户配置。旧 URL 继续兼容；新 App Links 的域名校验由负责人部署，不要求更改原站点 SEO 路由结构。[A25]

备份导出明确提示包含薪资/职业/专注等个人内容，提供源已有的“排除人生档案”选项。使用系统文档选择器，不索取所有文件访问权。导入先预检，再展示新增/不变/冲突/被拒绝/已删除跳过数量；不会在读取文件途中覆写活跃数据库。[R07], [R09]

### 6.10 同步（FR-15）

D-02 已确认：采用用户主动授权的 Google Drive 应用专用存储，默认关闭；Android↔Android 自动同步属于手机/平板正式首发要求。保留没有 DoneAt 账号的产品结构。这是待实现的 Android 替代方案，不是已经部署的服务，也不会自动与 iCloud 互通。[A13]

必备状态：关闭、待授权、首次检查、待选择本地/云端、同步中、已同步、离线待同步、需要重新授权、配额/服务错误、冲突、云端重置待处理。开关显示已提交状态，不以用户刚点的值冒充成功。[R12]

暂停同步、删除云副本、移除此设备数据是三个不同操作。删除云端时防止离线老设备重新上传旧档案；有未同步本地数据先提供导出/审阅。切换 Google 账号不能把前一账号本地记录自动传给后一账号。具体同步协议见 02。

### 6.11 Plus（FR-16）

D-01 已确认提供月订阅、年订阅、终身一次性买断；具体价格、销售地区、优惠/试用期限仍需负责人配置，不属于本次方向确认的已知参数。**终身是非消耗型一次性商品，不是“永久订阅”。**不得硬编码展示价格、试用资格或汇率。[R05], [A06]

购买页应有功能说明、合法获取的本地化价格/周期、到期后收费说明、关闭、恢复购买、隐私和条款。资格不满足或商品读取失败时，不出现可点击但必失败的“免费试用”。待付款不得提前授予权益；取消购买保留原操作草稿。

跨平台权益已确认独立（D-03）；首发不做 iOS/Android 自动同步，业务数据通过 JSON 双向迁移。Apple Universal Purchase 不等于 Google Play 权益；不能凭导入 JSON 的 `isPlus` 授权。需要互通时另行引入可验证跨商店凭据与用户关联方案，由负责人批准账号/隐私/后台成本后实施。

价格/试用未配置时，可继续调试商品接口和权益逻辑，但生产页面不得虚构价格、试用天数或优惠资格。没有已配置且用户符合条件的有效优惠时，不显示免费试用承诺；这不等于负责人已经决定永久不提供试用。

### 6.12 设置、关于与评价（FR-17）

设置分组：工作与收入、提醒、个性化、数据与隐私、Plus、关于。关键危险项有解释、确认和可取消操作；同步/删除页面统一互斥操作锁。

关于包含版本、开源许可证、帮助/隐私、反馈和 Google Play 评价入口。反馈默认不带工资/日志，仅用户主动附加已脱敏诊断。不要硬编码历史邮件地址，从当前项目配置核实负责人指定地址。

Android 评价保留“充分使用之后、不打断完成当下”的原则，但**不照搬 iOS 的评价预询问**：Play In-App Review 指南不允许在卡片前询问意见。自动请求按合适时机与节流执行；手动“评价”按钮直达商店，不绑定可能不弹出的 In-App Review API。[R15], [A15]

## 7. Material 3 Expressive 视觉规范（Android 新设计）

### 7.1 设计方向与可审查标准

识别点保留 DoneAt 橙色与时钟意象；Expressive 用在当前状态、主要操作和必要的状态过渡，不把页面变成彩色海报。不是“给所有卡片加超大圆角”或“换一套主题色”就算完成。遵循官方 Material3 组件、颜色角色、字体层级、形状与 motion scheme；具体实验组件集中封装。[A01], [A02], [A03]

品牌色方案默认；提供系统动态配色开关（支持平台上才显示），不默认替换用户已经选定的主题。浅色/深色/跟随系统独立于品牌/动态配色模式。保存用户选择，重启和恢复后不闪回另一主题。

### 7.2 组件规格

| 区域 | 组件/实现原则 | 约束 |
|---|---|---|
| 主导航 | Material 自适应 NavigationSuite 方案 | 窄窗底栏，宽窗 rail/适当 drawer，不按机型硬编码 |
| 顶栏 | 原生 Material app bar + 标准图标 | 标题长文本可截/换行，主要操作始终可触达 |
| 主倒计时 | 明确数字层级、等宽数字特性 | 不每秒重新布局整页；TalkBack 不每秒播报 |
| 主操作 | Filled / expressive shape 按钮 | 一屏仅一处最高强调；危险结束与普通开始区别明确 |
| 周期选择 | 标准分段/Toggle group 包装 | 手势只是补充，仍可点击与键盘选择 |
| 排班日历 | 可访问格子 + 明确选中/今天/休息/未排标记 | 不只靠颜色；长按有替代菜单 |
| 记录图表 | Compose 绘制 + 文本等价内容 | 真实/估算用线型或填充差异，不依赖动画传达数据 |
| 专注任务 | 状态明确的可交互块 | 拖动有落点反馈与取消；大字体不把任务标题挤成不可读 |
| 表单 | Material text field、日期/时间选择器 | 原生键盘、IME inset、错误信息、保存防重复 |
| 次要动作 | Text/Outlined/Icon 按钮 | 不新增无语义的图标；Material Symbols 代替 SF Symbols |
| 反馈 | Snackbar、inline error、系统 haptics | 不用全屏弹窗报告每次小保存成功 |

默认版式建议：4dp 间距网格；页面边距紧凑窗 16–24dp；交互触达区至少 48dp；正文约 16sp，辅助约 12–14sp，主数字在窄窗约 56–72sp 起测。以上是待视觉验收的设计 token，不是不可调整的业务常量。200% 字体下允许改变排布和滚动，不能把文字缩回原大小。

主计时线框：

```text
[日期 / 班次]                         [专注]

            [工作中]
             03:25:18
          剩余有效工作时间
       ────── 进度 / 休息标记 ──────
       今天预计收入        [隐藏]

[接下来：休息 / 下班 / 下次班次]
[今天摘要：已工作 / 已休息 / 预计结束]
               [主要操作]

             计时 | 记录 | 设置
```

宽窗不是放大手机：计时与当天详情两栏；记录日历/图表与选中日详情分栏，独立滚动；设置采用列表-详情。使用同一页面状态与路由目标，不为平板再写一套业务计算。[A18]

### 7.3 动效与无障碍

数字变化只影响数字区域；工作→休息→结束可做短过渡，禁止每秒弹跳卡片/震动。购买成功保留明确成功反馈，但不要求 Android 机械复刻 iOS 2.8 秒连续 rigid 触感。系统动画关闭/减少动态效果时去除连续旋转，仍有静态成功状态。

使用 TalkBack 可识别名称、角色、状态与操作；图形有文本替代；隐藏收入在语义树中也隐藏；当前时间无需每秒 live region。阿拉伯语 RTL、硬件键盘、200% 字体、对比度、色觉差异是验收条件，不是发布后的优化。

## 8. 非功能指标（本包建议的验收目标，不是已经测得的结果）

| 编号 | 目标 | 测量方法 |
|---|---|---|
| NFR-01 | 核心业务无网络也可用，进程回收不丢已提交数据 | 飞行模式、进程终止、重启场景 |
| NFR-02 | 前台计时误差显示不因累计 tick 漂移；恢复后立即按绝对时间重算 | 注入时间、长时间运行和休眠后恢复 |
| NFR-03 | 中档参考真机 Release 冷启动 P95 目标 ≤2s；热启动 ≤1s | 明确机型/OS/样本数，Macrobenchmark，不能用 Debug 比 |
| NFR-04 | 60Hz 常见交互大部分帧在 16.7ms 预算，卡顿帧比例目标 <1% | 宏基准与真实图表/长列表，超标给 trace |
| NFR-05 | 15,000 日人生估算、十年记录不阻塞主线程 | 大数据固定档案，取消/缓存验证 |
| NFR-06 | 非使用时无周期性每秒唤醒、无无期限 wakelock/FGS | 日志、系统调度与耗电对比；目标阈值绑定参考设备 |
| NFR-07 | 所有 P0 测试通过，规则 fixture 覆盖输入集合无删减 | CI 实际执行数、报告、差分 |
| NFR-08 | 发布包无调试解锁、测试支付、敏感日志或密钥 | Release APK/AAB 与 manifest 扫描 |
| NFR-09 | 19 语言键、占位符与复数通过自动检查 | 生成报告；中文/英文/阿语/长文本视觉抽检 |
| NFR-10 | 数据写入、导入、迁移失败后保留原数据和可恢复副本 | 故障注入、低空间、途中进程终止 |

## 9. 首发产品验收场景

新用户在不登录、不购买、不授权通知的情况下完成班次设置并正确倒计时；带午休与夜班用户看到正确阶段；从 iOS v6 备份导入后记录、排班、人生与专注保持语义；已购买用户离线/重装/取消自动续费不被错误锁定；数据为空与读取失败界面不同；同一操作经手机/平板/通知入口结果一致；所有平台差异向用户如实解释。


---

## 本文参考网址

- **A01** · [Compose Material 3 发布说明](https://developer.android.com/jetpack/androidx/releases/compose-material3)
- **A02** · [Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)
- **A03** · [Material 3 Expressive 设计入口（网页依赖 JavaScript）](https://m3.material.io/blog/building-with-m3-expressive)
- **A06** · [Play Billing 接入](https://developer.android.com/google/play/billing/integrate)
- **A10** · [AlarmManager 与精确闹钟权限](https://developer.android.com/develop/background-work/services/alarms)
- **A11** · [Live Update 通知及适用范围](https://developer.android.com/develop/ui/views/notifications/live-update)
- **A12** · [Glance 小组件更新与状态](https://developer.android.com/develop/ui/compose/glance/glance-app-widget)
- **A13** · [Google Drive 应用专用数据](https://developers.google.com/workspace/drive/api/guides/appdata)
- **A15** · [Google Play 应用内评价](https://developer.android.com/guide/playcore/in-app-review)
- **A18** · [Compose 自适应导航](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation)
- **A24** · [前台服务类型与适用范围](https://developer.android.com/develop/background-work/services/fgs/service-types)
- **A25** · [Android App Links 校验](https://developer.android.com/training/app-links/verify-applinks)
- **R01** · [仓库根 AGENTS：架构、隐私、规则与本地化契约](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md)
- **R02** · [iOS 快照与主倒计时显示规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift)
- **R03** · [扩展排班数据模型](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift)
- **R04** · [扩展排班解析器](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift)
- **R05** · [Plus 权益与免费窗口](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift)
- **R06** · [专注模型、模板与确定性会话 ID](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift)
- **R07** · [RecordJSON：跨平台备份协议与合并](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift)
- **R08** · [记录日解析优先级](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift)
- **R09** · [记录编辑、导入导出及隐私确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordsActions.swift)
- **R10** · [当前汇总与人生收入规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift)
- **R11** · [统一页面路由](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/AppRouteDestination.swift)
- **R12** · [同步设置、恢复与删除交互](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift)
- **R13** · [计划 015：收入、设置同步与用户确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md)
- **R14** · [计划 016：后续修订、首次恢复、固定月薪](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md)
- **R15** · [计划 012：周期总结与评价资格](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/012-ios-retention-and-cycle-notifications.md)
- **R18** · [共享提醒规范与测试入口（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/reminders.ts)

[A01]: https://developer.android.com/jetpack/androidx/releases/compose-material3
[A02]: https://developer.android.com/develop/ui/compose/designsystems/material3
[A03]: https://m3.material.io/blog/building-with-m3-expressive
[A06]: https://developer.android.com/google/play/billing/integrate
[A10]: https://developer.android.com/develop/background-work/services/alarms
[A11]: https://developer.android.com/develop/ui/views/notifications/live-update
[A12]: https://developer.android.com/develop/ui/compose/glance/glance-app-widget
[A13]: https://developers.google.com/workspace/drive/api/guides/appdata
[A15]: https://developer.android.com/guide/playcore/in-app-review
[A18]: https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation
[A24]: https://developer.android.com/develop/background-work/services/fgs/service-types
[A25]: https://developer.android.com/training/app-links/verify-applinks
[R01]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md
[R02]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift
[R03]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift
[R04]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift
[R05]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift
[R06]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift
[R07]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift
[R08]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift
[R09]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordsActions.swift
[R10]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift
[R11]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/AppRouteDestination.swift
[R12]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift
[R13]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md
[R14]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md
[R15]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/012-ios-retention-and-cycle-notifications.md
[R18]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/reminders.ts


---

<!-- section: 02_TECHNICAL_GUIDE.md -->

# 02 · Kotlin 原生移植与技术指引

本章除明确引用的当前源码行为外，均为 Android 建议实现。代码块是接口/算法约束示例，不是声称已在当前工具链编译通过的工程。最终具体 API 签名以锁定依赖、源码和编译为准。

## 1. 先建立两条边界

**业务等价边界**：相同输入、相同时区、相同当前时间，Android 与基线 iOS/共享 TS 对同一语义输出一致。不能因为 Compose 好写就删掉记录解析层、午休段、历史快照或权益状态。

**平台替代边界**：SwiftUI → Compose，StoreKit → Play Billing，WidgetKit → App Widget/Glance，ActivityKit → 合适的 Android 通知，CloudKit → 经批准的 Android 同步提供商。替代的是操作系统接入，不是业务规则。[R01], [R02], [R07]

禁止 Swift 到 Kotlin 的逐文件机械翻译。大的 Store/Coordinator 应按职责拆分，但先建立行为测试，再重构，不在无测试情况下同时改算法、存储和 UI。

## 2. 技术选型与版本冻结

### 2.1 选型

Kotlin、Jetpack Compose、Material 3 Expressive；Kotlin Coroutines/Flow；ViewModel 单向数据流；Room 保存业务及事务数据；DataStore 只保存非事务性的本机小偏好；java.time 处理时间；kotlinx.serialization 或一个统一的严格 JSON 适配器；Glance/RemoteViews 做小组件；WorkManager 做可延迟任务；AlarmManager 做经授权且确实需要的时间边界；官方 Play Billing。

应用不需要跨平台 UI 或 KMP 才能共享规则。`:core:domain` 先做纯 Kotlin/JVM，后续 Wear OS 可复用。依赖注入先用明确构造函数与 AppContainer；除非规模或团队规范证明有需要，不为了“架构完整”引入自定义 DI 框架、通用 EventBus、反射路由或几十个空模块。

### 2.2 已核实的版本事实（2026-09-21）

| 项目 | 已核实信息 | 执行选择 |
|---|---|---|
| Play 手机/平板 target | 当次查到新应用/更新最低 API 36 | `targetSdk >= 36`，发布前复核，不使用旧的 target 35 方案 [A04] |
| minSdk | 不是 Play target 要求 | 建议 26，D-04 确认；不能因 min 26 推断所有新 API 可无条件调用 |
| Material3 | 当前页 stable 1.4.0，expressive 路线 1.5.0-alpha28；1.4 稳定线曾移除实验 Expressive API | 候选锁 `1.5.0-alpha28`，仅在技术探针编译与 UI 验证后采用；风险需负责人签收 [A01] |
| Compose BOM | 官方示例 `2026.09.00` | 稳定 BOM 为起点，显式覆盖 Material3；审查其传递依赖，不声称其他库一定仍稳定 [A20] |
| Billing | 官方接入示例 `billing-ktx:9.1.0` | 候选锁 9.1.0；不用已越正常截止线的 v7 新建工程 [A05], [A06] |
| AGP | 当前发布页给 9.4 的 Gradle 9.6.0 / JDK 17 / 最大 API 37 兼容信息 | M1 依据可用稳定渠道选择并记录，不把该表误当整个项目已兼容 [A19] |
| Kotlin / Compose compiler | 官方示例 Kotlin 2.4.10；编译器插件与 Kotlin 版本关联 | 与所选 AGP/内置 Kotlin、KSP 联合验证，不孤立升级 [A21], [A22] |

**技术探针必须先于业务开发**：空 Compose 页面 → 需要的 Expressive 组件/主题 → Room 生成 → 序列化 → BillingClient 初始化 → Glance 最小组件 → Debug 和 R8 Release 构建。记录实际 Gradle/JDK/AGP/Kotlin/Compiler/KSP/Compose/Material3/Room/Billing/Glance 版本和依赖树到 `docs/android/environment-lock.md`。

使用 AGP 9 内置 Kotlin 时，不再套用旧教程给 Android 模块重复应用 `org.jetbrains.kotlin.android`；`:core:domain` 纯 JVM 模块的插件另行配置。优先 KSP，不因旧 KAPT 示例复制出不兼容构建。[A22]

不要使用 `+`、`latest.release`、未经验证的 alpha BOM 或全局强制降级。Material3 的预发布依赖可能传递带入其他预发布库，`:designsystem` 隔离的是 API 使用边界，不是能神奇隔离最终 APK 的运行时依赖。若负责人不接受预发布风险，须批准一个用稳定 API 实现 Expressive 设计语言的替代规范，而不是开发 AI 私自把 UI 改回普通 Material3。[A01], [A20]

## 3. 推荐工程布局

```text
src-mobile/android/
  settings.gradle.kts
  build.gradle.kts
  gradle/libs.versions.toml
  gradle/wrapper/...
  app/                         # Android Application、导航、装配与 manifest
    src/main/kotlin/.../
      AppContainer.kt
      MainActivity.kt
      navigation/
      feature/onboarding/
      feature/timer/
      feature/schedule/
      feature/records/
      feature/life/
      feature/focus/
      feature/settings/
  core/domain/                 # 纯 JVM，不依赖 android.* / Room / Compose / Billing
    time/ schedule/ summary/ records/ focus/ entitlement/
    model/ repository/         # 接口、命令、不可变业务对象
  core/data/                   # Room、DAO、实体映射、JSON codec、事务实现
  core/designsystem/           # Theme、tokens、组件、Expressive 包装与 previews
  core/platform/               # Alarm、通知、小组件投影、Biometric、Share、链接
  core/billing/                # BillingClient、购买服务适配、缓存凭据
  core/sync/                   # 批准后的 Drive transport、同步协调器
  baselineprofile/             # 到性能阶段才创建，不先生成空工程
```

审计、ADR、进度和发布资料统一放在**仓库根 `docs/android/`**，不再在 `src-mobile/android/` 内创建第二份同名目录。下文省略路径的 `progress.md`、`feature-parity.md`、`wire-contract.md` 等均相对这个根文档目录；Gradle路径相对 `src-mobile/android/`；Node脚本放根 `scripts/`。

以上是拟创建路径，不是声称仓库已有 Android 模块。模块数量可在 M1 调整，但必须保持纯领域层和设计系统边界。功能页面先用 package 划分，不为每个按钮建立模块。

依赖方向：app → 具体 data/platform/billing/sync/designsystem；这些模块 → domain。domain 不反向依赖任何平台模块；Room 实体不暴露给 Composable；页面不能直接拿 BillingClient 或 Drive API；同步不得直接修改 ViewModel。通过领域 repository 接口、不可变输入和命令提交串联。

### 3.1 状态与动作

每页 `UiState` 明确 Loading / Ready / Empty / RecoverableError；错误状态保留最近有效内容时须明确其时效。`ViewModel` 暴露 `StateFlow`，生命周期感知收集；一次性导航/分享命令独立处理，避免配置变更后重放购买/删除动作。

`SavedStateHandle` 保存选中日、页面尺度、非敏感草稿引用；持久业务状态在 Room。不要把全部 RecordState 放入 Bundle，工资和 Token 不写入导航 route/Intent URI。

写操作流程：UI 草稿 → 领域校验 → repository 单事务 → 新状态 → 重建受影响通知/小组件/同步 outbox。成功返回必须发生在提交后；写失败不显示已保存。并发修改有序、可取消读取，不靠 Composable 中随机起 coroutine。

### 3.2 建议领域接口

```kotlin
// 表示职责，不要求照抄具体命名；签名最终由源 oracle 的输入/输出决定。
interface ShiftEngine {
    fun evaluate(input: ShiftInput, now: Instant): ShiftEvaluation
    fun expand(input: ScheduleInput, range: CivilDateRange): List<PlannedDay>
}
interface SummaryEngine {
    fun summarize(input: SummaryInput, now: Instant): SummaryResult
    fun lifetime(input: LifetimeInput): LifetimeSummary
}
interface ReminderPlanner {
    fun plan(input: ReminderInput, now: Instant): List<PlannedReminder>
}
interface RecordRepository {
    fun observeState(): Flow<RecordState>
    suspend fun execute(command: RecordCommand): CommandResult
}
interface EntitlementRepository {
    val state: StateFlow<EntitlementState>
    suspend fun refresh(): RefreshResult
    suspend fun restore(): RestoreResult
}
```

不要把 Android Context 传入这些计算接口。时间从输入或注入的 Clock 提供；业务函数不能在内部偷偷调用 `Instant.now()`、读取单例偏好或启动网络请求。

## 4. 时间、排班与收入移植

### 4.1 两类时间必须分开

- **瞬间**：Unix epoch 毫秒、Kotlin Long/Instant；已发生事件与当前会话起止用它。
- **民用日期/时刻**：LocalDate、LocalTime、ZoneId；“2026-10-03 的夜班”是某记录/排班语境的日期，不是 UTC 午夜。

每条跨平台记录保留原时区/日历语义。当前设备时区、排班时区、记录时区三者不能默默互换。JSON 日期严格 `YYYY-MM-DD`；瞬间按毫秒，不把 Swift Date 的 epoch 或秒单位误当 Unix 毫秒。[R07], [R08]

日期格式描述中的 `YYYY-MM-DD` 是协议可读表示，不是 Java 格式模式：实际使用 `DateTimeFormatter.ISO_LOCAL_DATE` 或严格的 `uuuu-MM-dd`，禁止 Java 的周序年 `YYYY` 与年内日 `DD` 导致跨年串日。

按日迭代使用 `LocalDate.plusDays`，不使用 `+86_400_000` 遍历日历。夏令时缺失时刻/重复时刻的选择必须从 CivilZone + TS/Swift 测试生成 fixtures 锁定；不能仅调用 Java `atZone()` 并假设默认选择与 Swift 一样。应用语言的第一周起始日可改变展示范围，但不改变历史记录身份。[R10]

### 4.2 有效段模型

每段 `[startAtMs, endAtMs)`，排序、非重叠、正长度，使用同一规则做归一化。暂停/班中休息是不计入有效工作的空隙，不是把所有时间混成一个总 start/end。

```text
durationMs        = Σ(end - start)              # 当前有效段总长，可能含加班
plannedDurationMs = 原计划有效段总长            # 加班时不得覆盖
elapsedMs         = Σ clamp(now - start, 0, end - start)
remainingMs       = max(0, durationMs - elapsedMs)
progressRatio     = clamp(elapsedMs / durationMs, 0, 1)
payRatio          = elapsedMs / plannedDurationMs
```

零分母按源规则输出合法空/零状态，不产生 NaN。上述 `progressRatio` 是建议内部 0…1 单位；若源 `progress` 使用 0…100，oracle 适配器显式换算，禁止拿 0.5 当 0.5%。

`heroRemaining`：未开始 → 开始时刻减 now；休息中 → 当前休息结束减 now；其余有效工作中 → `remainingMs`。休息期间工作 elapsed 与收入不前进，但休息倒计时前进。[R02]

**算例（人工设计，不是伪造的原仓库测试输出）**：09:00–12:00、13:00–18:00，原计划 8h，日薪 80；12:30 时已工作 3h、剩余有效 5h、主显示休息剩余 30min、收入 30。加班延至 20:00，19:00 已工作 9h、当前总长 10h、进度 90%、payRatio 1.125、收入 90；不能用 90%×80 得到 72。

基础与扩展排班先生成统一的有效段输入，再调用同一引擎。不得为轮班、Widget 和 Focus 再写三套倒计时算法。[R01], [R04]

### 4.3 扩展排班的特殊陷阱

源班型的 `endMinutes <= startMinutes` 表示跨到次日，包含相等的情况；不要用通用表单校验误拒绝 24 小时班。长达 24 小时但扣完休息无有效段时，依源校验进一步拒绝/处理，不能出现无限进度。[R03]

周期锚点之前也要正确取索引：用带数学意义的 floorMod，而不是 Kotlin 负数 `%` 直接索引。手排和类型单独保存；旧班型归档不是删除历史。未知班型引用可处于同步中间态，解析为未分配，不擅自替换默认白班。

`extendedContent` 固定规则内容；实时手排覆盖仍然参与历史解析；过去日期可能有冻结班型；部分旧固定快照有历史覆盖回退。Android 必须提供与 `RecordCoordinator.expandableHours(for:)` 同职责的**唯一入口**，任何读取快照的地方都调用它。[R01], [R03], [R04]

“清空排班”不是删除全部记录；`clearedFromDayKey` 会停止指定日起的自动继承/节假日分配。不要把字段丢掉导致用户刚清空，下一次重启又自动填回。

### 4.4 记录解析与收入

先实现计划解析，再实现观测汇总，最后接图表。`DayRecordResolver` 中 active override → calendar exception → snapshot 为计划链；`.cleared` 要向下回退；手工日历例外与 bundled 数据的选择需保留来源、版本和时间戳逻辑。[R08]

获胜快照不仅按日期：相同 effectiveFrom 还比较 editCount/editTieBreaker/ID。阶段选择也有稳定比较规则。UUID 比较应按源规范统一大小写后的字符串/明确字节序进行，不能直接用具有不同有符号排序语义的 JVM `UUID.compareTo` 替代。不能简单“数据库最后一行 wins”。预建索引，避免 15,000 天×全部记录线性扫描。

月薪汇总需区分计时页 live estimate 与记录页固定月收入。计划 015 中较早的按工作日分配，被计划 016 的后续确认进一步修改为自然日分摊与不因请假扣薪；最终计算接入以现有调用链及 fixtures 为准，不能只读其中一个旧函数就替代整页。[R10], [R13], [R14]

金额：建议保存规范十进制文本/BigDecimal，计算/显示舍入策略独立。为了与 JS/Swift Double 兼容，不可未经对照就改变每一步舍入；中间保留足够精度，只在源规定点舍入。fixture 的时间/枚举/ID 必须精确一致；浮点值用有业务依据的公差，例如规范化时间 ≤1ms、显示金额按币种最小单位一致，不能把公差放宽到足以吞掉算法错误。币种小数位不能一律硬编码 2。

人生按已填写区间累加，空档为零；职业阶段不能重叠；未来固定比例调整只改预测段，保持历史不动。用稳定原阶段 ID 派生展示分段，选中对象不依赖当前数组 index。[R10], [R14]

## 5. 规则等价测试：先建 oracle，再写 Kotlin

### 5.1 两组规范，不互相冒充

**共享规则**：TS `lib/countdown.ts`、`lib/summary.ts`、`lib/reminders.ts` 和现有 `scripts/ios-schedule-rule-oracle.mjs`。在开发环境生成独立 JSON fixtures 给 Kotlin；现有 Swift fixtures 可继续保留。只能在构建/测试阶段运行 Node，不带 JS 引擎进 APK。[R01], [R16], [R17], [R18], [R19]

**iOS 独有规则**：扩展排班、记录编辑/冲突、专注细节、首次恢复等，源 Swift 与对应 Swift 测试是规范。新增 Swift→JSON 测试导出或等价手工测试映射；不能假称 TS oracle 覆盖了它们。[R04], [R06]

### 5.2 Fixture 文件格式建议（新测试协议，不是用户备份协议）

```json
{
  "fixtureSchemaVersion": 1,
  "sourceCommit": "9252fdfdc66aab88b4acb7493684f11991fd773d",
  "generator": "scripts/generate-android-rule-fixtures.mjs",
  "sourceHashes": {},
  "cases": [
    {
      "id": "unique-case-id",
      "origin": "typescript-oracle-or-swift-test-name",
      "operation": "evaluateShift",
      "input": {},
      "expected": {}
    }
  ]
}
```

上面的 input/expected 空对象只是 schema 示意，不能提交为有效用例。最终生成器必须调用真实源函数，记录源哈希；执行数不得为零；CI 重新生成后有 diff 即失败。不要把错误 Kotlin 的结果写回 expected。

覆盖：全天、午休、多个有效段、跨夜、周/月/年边界、闰年、DST 正反向、手动/关闭自动模式、空工作日、下一班次、下一休息日、加班、提前结束及撤销、短月排班继承、冻结历史、金额无效值、实际/预测分割、人生调整、提醒去重。

无法运行 Swift 的 Linux 环境不能宣称完成 Swift 差分。先映射现有测试并实现可本地执行部分，CI 加 macOS job 跑导出/验证。公开样例可供理解，但无法代替缺少的源测试。

## 6. 数据模型与兼容协议

### 6.1 需要保留的业务实体

| 实体 | Android 持久化重点 | 丢失后的后果 |
|---|---|---|
| CareerPeriod | ID、起止、创建/编辑信息、时区/日历 | 历史归属与人生收入错位 |
| ScheduleSnapshot | periodID、effectiveFrom、配置、extendedContent、编辑戳 | 修改当前排班会回写历史 |
| CalendarException | 自然键含来源语义、effect、cleared、datasetVersion | 请假/补班或节假日覆盖错误 |
| DayOverride | dayKey、kind、segments、zone、编辑戳 | 人工确认被计划覆盖 |
| WorkObservation | eventID、事件类型/时间、关联身份、zone | 重复或伪造“实际”记录 |
| LifeProfile | 各阶段、收入经历、未来调整及可空字段 | 职业历史和预测被重置 |
| FocusTask | UUID、计划/落位、轮数、图标、收藏、删除/完成、模板关联 | 重启后任务丢落位或重复 |
| FocusSession | UUID、关联任务、起止、结束原因、kind | 多设备重复会话/无法恢复 |
| FocusPlanningConfiguration | 计划、模板与计时设置 | 模板和恢复块失真 |
| SyncedPreferences | 明确可同步的业务偏好 | 默认配置覆盖旧用户 |
| ExtendedSchedule | 班型、周期、节假日标记、清空边界、编辑戳 | 轮班和历史无法复现 |
| RosterDay | dayKey、typeID、冻结类型、generatedFromPattern、zone | 过去日期随班型编辑漂移 |

表格不是完整字段替代品。M0 必须把 12 类 DTO 的**所有字段、可空性、默认值、版本迁移、枚举 rawValue、键名、时间单位**抽成 `wire-contract.md`，逐字段打勾，不凭本表省略剩余字段。[R03], [R06], [R07]

内部还需：ErasedID/tombstone、同步元信息与 outbox、冲突候选、已处理动作去重、导入作业/恢复信息。它们不是都应出现在用户 v6 导出里。

### 6.2 Room 与 DataStore 分工

Room：业务行、同步业务设置、会话状态、命令结果与 outbox，在同一事务中修改。核心保存失败时不能只把 DataStore 设置改掉，留下“新设置+旧历史”混合状态。

DataStore：本机配色显示偏好、已看引导等不需与业务行原子一致的设置。源规定参与跨设备同步的语言/主题值要通过业务偏好模型与映射同步，而不是直接把整个 DataStore 上传。

权限是否授予、设备锁能力、Android 渠道设置、系统是否能发精确闹钟都来自当前设备查询，不从 iOS 备份恢复成 true。购买凭据、密钥、Google access token、系统 URI 权限和 Debug flags 不参与同步/备份。

Room schema 导出并提交；升级用 Migration + MigrationTestHelper，禁止 `fallbackToDestructiveMigration()` 用在生产业务库。磁盘满/损坏时进入只读/恢复状态，不自动删库“解决闪退”。需要文件级副本时必须使用一致性的数据库快照策略并正确处理WAL，不能在数据库运行时仅复制主 `.db` 文件当完整备份。原子替换前保留安全副本，迁移失败能回退到尚未改写的数据副本，而不是安装旧 APK 读取新库。

### 6.3 JSON v6 双向契约

当前 `RecordJSON.schemaVersion=6`，接受 1–6。[R07]

```text
exportedAtMs                Unix milliseconds
 timeZoneIdentifier         文件级默认时区
 calendarIdentifier         文件级日历信息
 careerPeriods[]
 scheduleSnapshots[]
 calendarExceptions[]
 dayOverrides[]
 workObservations[]
 lifeProfile?
 focusTasks[]
 focusSessions[]
 focusPlanningConfiguration?
 syncedPreferences?
 recordsStartedOn?
 extendedSchedule?
 rosterDays[]
```

这是已读 export 调用的字段结构提示；顺序不重要，名称/语义重要。源 DTO 有版本演进，执行 AI 仍须读取完整编码/解码实现，补齐兼容默认值。

**用户导出不是内存 RecordState 的完整序列化**：源 state 里有 erased/sync，但已读 export 构造并未把整个 state 直接输出。不要擅自把云 Token、本地冲突、墓碑或 Android 私有列塞进 schema 6。Android 同步 envelope 另立协议版本，不伪装成源备份格式。

导入流程：SAF 读取受限文件 → 流式/限额读取 → 格式与版本检查 → DTO 校验 → 在候选副本合并 → 报告 → 用户确认 → 单事务提交 → 重建投影。建议默认导入上限 25 MiB，超过则停止并提示导入限制；这是产品保护阈值，M0 根据真实大型档案调整，不截断数据后继续成功。

必须区分整文件无效、未知版本、个别行被拒绝、同 ID 冲突和已删除跳过。v7 不能直接作为 v6 忽略字段导入。已知 v1–v6 的未知非关键字段可以按明确兼容策略保留或提示，不以全局忽略未知字段掩盖必填数据丢失。

默认同 ID 冲突保持本地并展示 incoming；自动合并仅按源 `(editCount, editTieBreaker)`。墙上时间仅为展示，不能作为最终输赢依据。新值恢复已删自然键必须高于墓碑版本；恢复 UUID 身份需映射关联引用，不能只换主键却保留旧 periodID/taskID。[R07]

至少测试：iOS 导出→Android 导入→Android 导出→iOS 导入。比较规范化业务含义，不逐字比较 JSON 空格/排序；明确只能变化 exportedAt 和规范化排序等非业务元数据。备份不能迁移 App Store 或 Google Play 的付费权益。

## 7. 专注状态机与确定性身份

模型先移植，页面后接入。分开 Task、PlanAssignment、Session、TimerSettings，不把可重复使用模板等同正在运行的会话。

建议事件：StartRequested、BoundaryReached、StopRequested、PlanChanged、SettingsChanged、AppResumed、ExternalStateMerged。每个事件有去重键。数据库用事务保证同一逻辑会话只启动一次；通知动作与前台操作走同一命令处理器。

必须维护源现有的 kind 和 endReason：focus/shortBreak/longBreak；completed/stoppedByUser/stoppedAtBoundary/abandoned/supersededBySync。[R06]

### 7.1 不能用错 UUID 算法

源自动会话 ID 并非标准 Java `UUID.nameUUIDFromBytes`，也不是标准 SHA-1 UUIDv5。它是指定 UTF-8 文本的 **SHA-256 前 16 字节，再设置 UUID version/variant bits**。[R06]

```text
block seed:
 owc.focus.block.v1|<lowercase-task-uuid>|<startAtMs>|<endAtMs>
recovery seed:
 owc.focus.recovery.v1|<lowercase-previous-session-uuid>|<kind-rawValue>

bytes = SHA256(UTF8(seed))[0:16]
bytes[6] = (bytes[6] & 0x0F) | 0x50
bytes[8] = (bytes[8] & 0x3F) | 0x80
```

使用固定 test vectors 验证字符串大小写、毫秒格式和字节序。不要给自动会话每次生成随机 UUID；用户手工任务仍按源规则生成独立 UUID。

### 7.2 重启与背景恢复

持久化 session 起止与计划；界面每秒刷新只负责展示。恢复时推进到当前有效状态，可补全可证明的确定性结束事件，但不能凭进程休眠“推测用户完成了所有专注任务”。自动串联下一轮/休息的规则从 FocusPlanner/FocusLiveChain/FocusStore 测试对齐，不能擅自选择传统番茄钟行为。

本机进行时长显示可结合 elapsedRealtime 防止普通时钟微调引起视觉跳动；业务绝对边界仍按源设定处理。设备重启后 monotonic clock 归零，必须回到持久化 Instant 与规则重建，不能复用旧 elapsedRealtime base。

## 8. Android 调度、通知与小组件

### 8.1 不创建全天每秒运行的服务

前台：生命周期可见时 ticker 驱动小范围投影；后台：保留绝对状态、安排有意义的边界/提醒；重开：立即重新计算。WorkManager 是最终一致/可延迟任务，不是秒级计时器。[A10], [A12], [A24]

首次用户授权、修改排班、当天调整、专注开始/结束、时区/时钟变化、重启、应用更新后需要重建必要的未来提醒。重建做差量：稳定 ID 的未变化提醒保留，过期/取消的移除，不每秒重排整个未来月。

`PlannedReminder` 建议字段：eventKey、kind、triggerAt、shift/session identity、generation、文案 key+安全参数、notification channel。持久化成功后再调用系统；系统注册失败留待重试并显示降级状态。

### 8.2 精确提醒

默认不声明 `USE_EXACT_ALARM`，不能自行把工作倒计时认定为受豁免的闹钟产品。确有用户精确提醒需求时，使用合规且需要用户授权的 `SCHEDULE_EXACT_ALARM` 路径，先查 `canScheduleExactAlarms()`，处理撤销、冷安装与恢复。[A10]

无精确权限时使用合适的非精确调度，并清晰告知可能延迟；用例不能要求系统未授权情况下依然必达秒级。OnAlarmListener 的进程相关替代不能当作杀进程后可靠提醒方案。频繁微休息不通过密集 exact-while-idle 抢系统配额。

Android 强行停止与系统省电/厂商限制可能阻止后续执行；帮助页解释事实，不指导用户授予无关危险权限。重新打开后恢复状态并安排未来事件，不补发已经错过的整批里程碑。过期事件的丢弃窗口按事件类型及源策略记录为测试常量，不能临时由各 receiver 自行决定。

### 8.3 持续通知

常规 NotificationCompat + 点击 PendingIntent，可显示状态/结束钟点/阶段进度。需要系统计时时，仅对准确的一段连续时间使用 chronometer；跨休息段的“有效剩余”不等于简单目标钟点。每次边界机会校正；无法保证边界更新时优先显示真实绝对终点或上一更新状态，不假装持续精准的有效工时。

通知 ID、requestCode/Intent data、immutable flags、动作去重、显式组件都要验证。敏感操作从通知进入前台确认，不能未解锁就导出备份。通知的 publicVersion 与锁屏内容均无收入。用户主动关闭持续展示后不要立即重新弹回来，除非新会话的明确产品规则允许。

Live Update 只在实际符合当时官方适用条件、设备支持、权限及审核确认后增强；基本功能不能依赖它。没有资格时普通通知是正式降级，不是故障。[A11]

### 8.4 小组件

Glance 是 App Widget 层，不是普通 Compose 页面，禁止直接复用依赖 Activity 的 Composable。UI 的数据来自独立 `WidgetProjection`，该类型不含工资、职业收入、购买 Token 或完整记录归档。

系统周期更新通常至少 30 分钟，WorkManager 周期最短常用 15 分钟且仍非准点机制；官方不建议休眠时每分钟更新。业务变化、启动与边界调度触发额外更新，但不建立每秒 worker。[A12]

设计三态：有可靠当前阶段、仅有未来班次/结束钟点、数据过期/未配置。首次添加、多个实例、调整尺寸、进程死亡、重启、切换主题/语言均测试。RemoteViews 计时能力若用于增强，先做单独真机探针，并测试在所有支持 launcher 中的表现；不以一个模拟器证明所有厂商一致。

### 8.5 权限最小集

| 权限/能力 | 使用时机 | 默认 |
|---|---|---|
| POST_NOTIFICATIONS（适用系统） | 用户打开提醒/持续展示时 | 可拒绝，基础功能继续 |
| RECEIVE_BOOT_COMPLETED | 重启后重建未来调度 | 只安排任务，不启动常驻服务 |
| INTERNET / 网络状态 | Billing 服务、经授权同步 | 不用于隐性统计上传 |
| SCHEDULE_EXACT_ALARM | 确认精准提醒方案后 | 不强制，不与基础使用捆绑 |
| USE_BIOMETRIC | 用户执行隐私保护操作 | 检查实际设备能力与凭据回退 |
| 文档/图片访问 | SAF / FileProvider 临时授权 | 不请求全盘存储 |

不需要位置、联系人、电话、麦克风、相机、无障碍服务、所有文件、悬浮窗、通知读取权限。合并 manifest 可能包含依赖引入权限，发布审计以最终包为准，不以手写 manifest 为准。

## 9. Play Billing 与权益服务

### 9.1 商品结构（D-01 收费模式已确认；商品标识与价格待配置）

建议一个订阅产品 `doneat_plus`，配置 `monthly` 与 `yearly` base plan；年计划可有用户符合条件时的 offer。终身单独一次性非消耗商品 `doneat_plus_lifetime`。这是一份拟议 Play 命名，不是将 StoreKit 商品 ID 原封不动复制，也不是已经在 Console 创建。[A06]

读取 ProductDetails、实际可购 offer、价格阶段与币种；保存选中的 product/basePlan/offerToken，仅在合适生命周期缓存。购买前重新检查可用性。不能自行根据国家货币符号算售价，不能把月价×12 当作平台年价。

### 9.2 权益状态

| 平台证据 | 应用权限 |
|---|---|
| 待支付 PENDING | 不授予，保留 pending UI 与原操作 |
| 已验证有效订阅 | 授予到服务端确认的截止时间 |
| 用户取消自动续费但未到期 | 仍有效到实际截止时间 |
| 已验证宽限期 | 按平台确认的 grace 状态/时间继续 |
| Account hold / paused / expired | 按当前有效时间与服务端状态停止订阅权益，不删数据 |
| 已验证非消耗型终身且未撤销 | 终身授权 |
| 退款/撤销 | 收到可靠证据后回收相应授权 |
| 网络/验证服务暂不可用 | 保留最后已验证缓存，时间性权益仍检查期限 |
| 成功完整查询确认无权益 | 可替换旧缓存；必须区别于查询失败 |

Play 的 pending 生命周期不是 Apple Ask to Buy 的 24 小时规则。不能照搬 iOS 常量。客户端 Purchase 并不给出足够可靠的完整订阅到期语义，不可用 purchaseTime 加 30/365 天猜到期。[R05], [A06], [A08]

### 9.3 已确认采用：小型无 DoneAt 账号的权益验证服务

D-08 已确认生产支付采用**只处理必要购买元数据**的小型验证服务；排班、工资、职业数据不得上传到该服务，不新增 DoneAt 用户登录账号。可以按本章开始实现、接口测试和部署脚本编写。部署平台、域名、预算、最小权限凭据与生产上线操作仍待落实，不能把方案获批当成服务已部署。服务可用 Kotlin + Ktor + 持久数据库实现，独立于 Android APK；该技术组合仍是实施建议，不代表负责人已经选择了云厂商。[A07]

建议 API 契约（新设计，需实现真实服务）：

```text
POST /v1/play/verify
 request: packageName, productId, purchaseToken, requestId,
          optional integrity evidence and installation proof
 response: signed entitlement, canonical state, verifiedAt,
           expiresAt/graceEnd if applicable, product/basePlan,
           receipt revision, retryable error if not verified

POST /v1/play/rtdn
 authenticated Pub/Sub push -> enqueue token verification -> canonical refresh

GET /healthz
 no purchase or user data
```

APK 里只能包含公开服务地址/公钥/非秘密配置；Google service account 密钥、签名私钥和 Publisher API 凭据只在服务端受控环境，通过最小权限身份获取。不得要求负责人把私钥贴进聊天或提交 Git。

服务端：allowlist 包名与商品 → 去重 purchaseToken/requestId → 调 Google Play Developer API 获取真实状态 → 校验产品及合法关联 → 数据库事务保存权益 → 确认持久化后 acknowledge → 返回可校验签名的缓存证据。不能仅信任客户端 `purchaseState`、价格或 `isPlus`。[A07]

使用 token 唯一性作幂等核心，不把可能缺失/变化的 orderId 当唯一主键。处理 linkedPurchaseToken，升级/替换后不让旧证据继续发双份权益；RTDN 只做“需要重查”信号，不能只信消息里的状态；考虑乱序、重发、退款和 voided purchases。[A07], [A08]

匿名验证接口仍需鉴权/防滥用设计：purchaseToken 是敏感购买证明，不能有可枚举的按token查询公开接口，也不能把一个用户的token响应缓存给另一请求。缓存签名载荷应包含固定包名、商品/授权类型、签发时间、实际期限、证据版本及绑定上下文；校验算法、公钥keyId与版本必须allowlist。安装绑定不能直接变成“换机不能恢复”，新安装必须能通过当前Play购买查询重新验证；不得仅用本地随机安装ID证明购买归属。RTDN端点校验Pub/Sub推送身份，verify端点限流并保护日志；所有网络请求仅HTTPS。

只对 PURCHASED 且已验证的初次购买执行确认；终身商品不 consume；在规定窗口完成 acknowledge，否则可能被自动退款。建议服务端重试队列与告警，不以一个客户端回调承担可靠性；当前官方窗口为三天，pending 不是已成功购买。[A06], [A07]

不在日志记录明文 purchaseToken/邮件/工资。安装标识仅在必要的防滥用/绑定场景使用并申报，不能拿“无账号”宣传成“服务器完全不处理任何数据”。Play Integrity 是可选风控信号，不得因临时服务失败误取消已验证有效用户。[A14]

### 9.4 客户端实现细节

只维护一个应用级 BillingClient；注册更新监听早于首次查询；恢复前台时查当前购买；重连有退避。购买/恢复操作互斥，不在 recomposition 中启动支付；旋转重建页面不重复调用 launchBillingFlow。[A06]

缓存已验证授权与来源、版本和时限，敏感 Token 使用 Keystore 支持的保护并排除备份；公钥验证不能被 Debug 分支覆盖。服务端超时不等于未购买。离线退款无法立即获知，应诚实接受“下一次成功验证后撤销”的边界，不能宣称永久离线与即时撤销同时保证。

调试 FakeBilling 只在 debug/test source set，release 不能通过 deep link、偏好、环境变量或导入文件解锁。管理订阅按钮仅对订阅用户存在；购买终身不会自动取消其已有订阅，需明确提醒并提供平台管理入口，不能诱导重复付费。

## 10. Android 私有同步方案（D-02 已确认，纳入手机/平板首发）

### 10.1 选定主方案与不做的事

已确认采用 Google Drive `appDataFolder`，仅请求需要的 `drive.appdata` scope；同步默认关闭，用户主动授权后启用，基础使用无需 Google 登录。这个空间用于应用数据，不是公开 Drive 文件夹；客户端不能携带服务账号替用户访问 Drive。[A13]

D-03 已确认第一版仅 Android↔Android 自动同步；iOS↔Android 用 v6 文件互迁，两个商店购买权益独立。要自动跨 iOS/Android 同步，需同时改 iOS 的存储 transport/授权，或经批准统一后端；这是 D-03 的独立产品变化，不是 Android 加个 API key 就会发生。

**不能用“上传一个 JSON 到固定文件并以 modifiedTime 最后写入获胜”冒充多设备同步**，那会丢另一设备的手排、任务和删除。业务冲突仍按源 editCount/tieBreaker 与墓碑处理，Drive 只是传输层。[R07]

Google Cloud 项目、Android OAuth 客户端配置、应用标识与签名关联、授权配置及测试账户仍需在真实环境落实。未取得这些配置可实现同步协议与合成数据测试；真实 OAuth/Drive 恢复与多设备验收必须单独记录，不能以 mock 通过替代。

### 10.2 可实施的保守 v1 协议

采用不可变批次文件，避免依赖未经验证的跨设备 compare-and-swap 能力。每批包含：transportSchemaVersion、generation、batchId、writerId、writerSequence、createdAt、contentHash、变更实体、删除墓碑。业务 DTO 使用明确版本映射，不把本机权限和权益带入。writerId 为此同步空间内的随机设备身份，不能复用于分析。

本地一笔业务事务同时记录 dirty/outbox。后台合并相邻小改动后上传不可变 batch；batchId 确定重试身份，上传成功但本地未记账时先查/去重，不能制造逻辑重复。Drive 文件名并非唯一性约束，必须依据 batchId/内容哈希去重。[A13]

拉取：列出 appDataFolder 全部分页 → 下载未处理批次 → 校验版本/大小/哈希 → 按业务身份合并到候选副本 → 统一处理 tombstone/冲突 → 单事务提交状态与 processed batch → 再允许 push。哈希只能检查内容一致性，不是用户认证；访问控制来自 OAuth 与私有空间。

首次启用：用户同意数据范围 → 授权 → 完整 pull → 本地/云端差异预览 → 选择/合并 → 提交 → 才初始化配对及 push。禁止在首个空页面出现时立即上传默认设置。

v1 先保证不可变批次合并正确；不要实现没有证明的自动历史压缩。需要压缩时另做 ADR：checkpoint 覆盖范围、仍需保留的 tombstone/reset fence、离线设备重新加入规则与重放测试。开发阶段以十年记录/大量手排数据验证批次数、恢复耗时和 Drive 配额，超限不能静默跳文件。完整备份和日志批次必须能够从新设备恢复，不依赖源设备内存。

### 10.3 删除与 generation fence

删除云端不能只是“删当前文件”；老设备仍可能重新上传旧数据。设计一个可被所有设备识别的 reset/fence 记录，generation 由有序版本与随机 tie-breaker 决定。并发 reset 的比较规则固定；旧 generation 的业务批次一律不合并。

设备 push 前先完成 pull/fence 检查；即使发生检查后旧批次上传的竞争，读取端也因旧 generation 丢弃它。后续清理旧批次；保留必要的无业务内容 fence，阻止复活。界面和隐私文案说明删除范围，不谎称仍保留业务数据也叫已彻底删除。

如果用户在 Drive 外部删除了整个应用空间，已配对设备发现原 fence/空间身份缺失时必须暂停并让用户选择，不自动重建并上传旧档案。云端重置而本机仍有未同步数据时，先提供导出/审阅，不能无声抹掉。[R12], [R14]

### 10.4 断网、账号切换与失败

断网只排队本地已提交改动；UI 显示待同步而不是“保存失败”。授权取消、401、配额限制、服务异常分别分类处理；指数退避，不每秒重试。Google 账号变更使配对状态失效，旧数据保留但禁止自动发送到新账号。退出/撤销授权不等于删除云副本或本地副本。

同步中的权限变化不重写正在进行的会话计划；设置变更作用点与源一致。多设备专注仍需唯一活动会话冲突处理和确定性 ID，不把两台设备各自的 timer state 简单同时标 running。

## 11. 隐私、安全与系统备份

Android Auto Backup 默认可能包含应用文件，所以“数据只在本地”不能靠未设置网络代码来保证。显式制定 fullBackupContent/dataExtractionRules，排除业务库、敏感偏好、购买缓存、密钥与同步凭据；分别验证 cloud backup 与 device transfer 行为。不要以 `allowBackup=false` 一行就声称所有 OEM 都绝不会转移数据。[A16]

主方案的跨设备数据传输走明确的文件导出或用户同意的 Drive，同意前不传工资/经历。Keystore 保护密钥不保证导出的明文 JSON 自动加密；导出前直说这是含个人信息的文件，不能用“安全备份”暗示端到端加密。

UI 隐藏、存储加密、传输 TLS、端到端加密是四件不同事情。默认不引入 SQLCipher 来宣称更安全；若需要数据库额外加密，先解决密钥丢失、迁移、备份恢复和 native 16KB 兼容，再做独立 ADR。应用解锁隐藏工资不等于能防 root/系统管理员取证。

可在敏感页采取最近任务缩略图遮挡/按需 FLAG_SECURE；分享卡片通过安全 DTO 生成，不能为了分享解除整个敏感页面保护。是否全面禁截图由 D-09 决定，避免阻碍用户正常分享非敏感内容。

日志只保留错误类别、非敏感版本/耗时/操作 ID，不记录 JSON 正文、Token、工资、任务标题、职业时间表；异常上报 SDK 默认不加。负责人决定增加时必须重做 Data safety 与同意策略。[A14]

## 12. 本地化与原生资源

从 xcstrings 生成 Android 资源，在生成器中处理 plural、格式占位符、转义和允许相同译文列表。不能直接把 2.7MB 文件复制到 assets 再手写运行时翻译引擎；Android 使用资源系统，转换工具只在开发时运行。[R01], [R21]

19 locale 映射建议：

```text
en       -> values + values-en（默认英文可只用 values）
ar       -> values-ar
de/es/fr/id/it/ja/ko/pt/ru/th/tr/vi -> 对应 values-<语言>
hi-IN    -> values-b+hi+IN
mr-IN    -> values-b+mr+IN
zh-CN    -> values-b+zh+Hans+CN
zh-HK    -> values-b+zh+Hant+HK
zh-TW    -> values-b+zh+Hant+TW
```

具体目录与 Android locales_config 要自动校验；pt 不擅自替换成 pt-BR；印尼语兼容 Android 语言标签；繁体香港与台湾保持原文差异，不合并成一个 zh-Hant 译本。[R21]

源 Swift `String.count` 与 Kotlin `String.length` 的Unicode计数单位不同；班型名等长度限制应以源测试锁定用户可见字符/组合字符语义，不能把一个emoji或组合音标计成多倍长度后悄悄缩短可输入名称。

key 映射使用可逆清单，处理 Android 资源名限制与碰撞。iOS `%@`、`%lld`、位置化参数和复数变体不能用简单全局字符串替换；每个语言的占位符名称、类型、顺序与英文基准一致。`%`、引号、`&`、`<` 等按资源 XML 规则转义。

系统应用语言/应用内选择采用明确策略：默认跟随系统，显式选择持久化并刷新 UI 与应用通知/小组件的应用文案；系统 Launcher 名称等交给系统资源选择。源 iOS/桌面的系统表面规则不能未经判断机械移植。[R01]

## 13. 自适应、性能与测试实现

以窗口大小而非“是不是平板”选择布局；参考 WindowSizeClass/Adaptive Navigation，窄窗约 <600dp、600–839dp 可用 rail、≥840dp 可采用分栏，最终按官方 API 和实际窗格空间落地。横屏、分屏、折叠变化保持同一 ViewModel 的业务状态，不把路由/草稿重置。[A18]

长历史查询放后台 dispatcher；领域计算接受取消或分块策略；缓存键包含记录 revision、时区、所选区间、配置版本。每秒 ticker 不触发整年/人生重算；索引随业务修改重建一次。确认缓存失效正确后再优化，不能为了性能用过期历史回答。

可持久数据用真实 Room 的 instrumentation 测试；领域纯 JVM 测试；Compose UI 测试验证语义与动作；截图测试验证代表性布局；Macrobenchmark 使用 release-like 构建。截图和 unit test 不能证明后台提醒或真实支付可靠。

Release 使用 R8，保留必需序列化映射并测试被混淆后的导入/支付/启动。扫描所有 `.so`（包括间接 SDK）；即使业务代码全 Kotlin 也不能断言没有 native 依赖。按当前 16KB 官方要求验证打包及真机/模拟器，勿只看源码语言。[A17]

## 14. CI 与现有仓库保护

新增独立 Android workflow；仍保持现有 Web/Desktop/iOS 检查通过，不改现有部署触发来方便 Android。新增 fixture 生成器应只输出新 Android fixtures 或明确共享产物，不更改线上规则作为“适配”。

建议阶段命令（相应脚本/模块创建后才可运行）：

```bash
# repository root
npm ci
npm test
npm run check:version
# 如新增以下命令，先在 package.json 实现后再报告它已运行：
# npm run generate:android-rule-fixtures
# npm run check:android-fixtures
# npm run check:android-strings

cd src-mobile/android
./gradlew --version
./gradlew :core:domain:test
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
./gradlew :app:connectedDebugAndroidTest    # 需要真实可用设备/模拟器
./gradlew :app:lintRelease :app:bundleRelease
```

模块任务名称以真实 `./gradlew tasks` 为准；聚合 test 命令还须覆盖 data/platform/billing/sync 各模块，不能只跑 app tests 就自称全测。最终包路径由构建输出确认，不能在失败构建后贴旧 AAB 当新版本。

CI 产物：JUnit/XML、coverage 与用例数、lint、截图差异、Room schemas、fixture/source hash、依赖树、APK/AAB 与 SHA256、R8 mapping、权限清单、版本和 commit。签名与上架 job 受保护，不允许普通 PR 读取生产密钥；Fork PR 不注入 secret。产品营销版本可对齐现仓库，Android versionCode 单调递增且独立管理，由 D-10 冻结。


---

## 本文参考网址

- **A01** · [Compose Material 3 发布说明](https://developer.android.com/jetpack/androidx/releases/compose-material3)
- **A04** · [Google Play 目标 API 政策](https://support.google.com/googleplay/android-developer/answer/11926878)
- **A05** · [Play Billing 废弃周期](https://developer.android.com/google/play/billing/deprecation-faq)
- **A06** · [Play Billing 接入](https://developer.android.com/google/play/billing/integrate)
- **A07** · [Play Billing 安全及服务端验证](https://developer.android.com/google/play/billing/security)
- **A08** · [订阅生命周期](https://developer.android.com/google/play/billing/lifecycle/subscriptions)
- **A10** · [AlarmManager 与精确闹钟权限](https://developer.android.com/develop/background-work/services/alarms)
- **A11** · [Live Update 通知及适用范围](https://developer.android.com/develop/ui/views/notifications/live-update)
- **A12** · [Glance 小组件更新与状态](https://developer.android.com/develop/ui/compose/glance/glance-app-widget)
- **A13** · [Google Drive 应用专用数据](https://developers.google.com/workspace/drive/api/guides/appdata)
- **A14** · [Google Play Data safety 申报](https://support.google.com/googleplay/android-developer/answer/10787469)
- **A16** · [Android 数据备份默认行为](https://developer.android.com/identity/data/backup)
- **A17** · [16 KB 内存页兼容](https://developer.android.com/guide/practices/page-sizes)
- **A18** · [Compose 自适应导航](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation)
- **A19** · [AGP 当前发布与兼容矩阵](https://developer.android.com/build/releases/gradle-plugin)
- **A20** · [Compose BOM 与显式版本覆盖](https://developer.android.com/develop/ui/compose/bom)
- **A21** · [Compose 编译器插件](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler)
- **A22** · [AGP 9 内置 Kotlin](https://developer.android.com/build/migrate-to-built-in-kotlin)
- **A24** · [前台服务类型与适用范围](https://developer.android.com/develop/background-work/services/fgs/service-types)
- **R01** · [仓库根 AGENTS：架构、隐私、规则与本地化契约](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md)
- **R02** · [iOS 快照与主倒计时显示规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift)
- **R03** · [扩展排班数据模型](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift)
- **R04** · [扩展排班解析器](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift)
- **R05** · [Plus 权益与免费窗口](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift)
- **R06** · [专注模型、模板与确定性会话 ID](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift)
- **R07** · [RecordJSON：跨平台备份协议与合并](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift)
- **R08** · [记录日解析优先级](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift)
- **R10** · [当前汇总与人生收入规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift)
- **R12** · [同步设置、恢复与删除交互](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift)
- **R13** · [计划 015：收入、设置同步与用户确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md)
- **R14** · [计划 016：后续修订、首次恢复、固定月薪](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md)
- **R16** · [共享 TypeScript 倒计时规范（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/countdown.ts)
- **R17** · [共享 TypeScript 汇总规范（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/summary.ts)
- **R18** · [共享提醒规范与测试入口（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/reminders.ts)
- **R19** · [现有 TypeScript 规则 oracle（实施阶段读取接口）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/scripts/ios-schedule-rule-oracle.mjs)
- **R21** · [iOS 翻译目录（已核实路径，实施阶段转换完整文件）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Localizable.xcstrings)

[A01]: https://developer.android.com/jetpack/androidx/releases/compose-material3
[A04]: https://support.google.com/googleplay/android-developer/answer/11926878
[A05]: https://developer.android.com/google/play/billing/deprecation-faq
[A06]: https://developer.android.com/google/play/billing/integrate
[A07]: https://developer.android.com/google/play/billing/security
[A08]: https://developer.android.com/google/play/billing/lifecycle/subscriptions
[A10]: https://developer.android.com/develop/background-work/services/alarms
[A11]: https://developer.android.com/develop/ui/views/notifications/live-update
[A12]: https://developer.android.com/develop/ui/compose/glance/glance-app-widget
[A13]: https://developers.google.com/workspace/drive/api/guides/appdata
[A14]: https://support.google.com/googleplay/android-developer/answer/10787469
[A16]: https://developer.android.com/identity/data/backup
[A17]: https://developer.android.com/guide/practices/page-sizes
[A18]: https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation
[A19]: https://developer.android.com/build/releases/gradle-plugin
[A20]: https://developer.android.com/develop/ui/compose/bom
[A21]: https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler
[A22]: https://developer.android.com/build/migrate-to-built-in-kotlin
[A24]: https://developer.android.com/develop/background-work/services/fgs/service-types
[R01]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md
[R02]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift
[R03]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift
[R04]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift
[R05]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift
[R06]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift
[R07]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift
[R08]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift
[R10]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift
[R12]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift
[R13]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md
[R14]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md
[R16]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/countdown.ts
[R17]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/summary.ts
[R18]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/reminders.ts
[R19]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/scripts/ios-schedule-rule-oracle.mjs
[R21]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Localizable.xcstrings


---

<!-- section: 03_AI_EXECUTION_PLAN.md -->

# 03 · 给执行 AI 的分阶段实施计划

## 1. 工作方式

每次只选择一个依赖已完成的任务。先读源文件与当前任务涉及的条目，再输出改动范围，完成一条可运行的纵向链路，补测试、运行、审查差异，然后更新进度。不要一次生成整个工程再把测试留到最后。

同一功能的模型、序列化、UI、权限、测试可以分步完成，但“任务完成”必须达到该卡的验收条件。不允许用截图、空实现、打印日志、模拟支付/同步成功冒充真实能力。

若外部账户、设备或商业决策阻塞：把该任务标记 BLOCKED，记录精确原因；继续做不依赖它的工作。不要把阻塞项删掉，也不要让没有必要的外部依赖阻塞纯 Kotlin 规则和本地 UI。

`tasks.json` 的 `blocking_decisions` 只列真正未获批准的决策；`approved_decisions`/`approved_processes` 指向已确认项；`pending_configuration` 指向 decisions.json 中尚待落实的外部配置；`decision_gate_scope` 说明具体阻塞位置。D-01/D-02/D-03/D-05/D-08 的方向已确认，D-11 的核验流程已确认。T03可采用候选包名/minSdk完成本地Debug探针，正式签名/创建Play应用前冻结；价格未定不阻止领域和Debug接口；云服务尚未配置不阻止合成数据协议测试。生产部署、真实用户数据传输和发布仍需配置、最终用户同意及适当操作授权。

推荐任务状态：NOT_STARTED → IN_PROGRESS → IMPLEMENTED → VERIFIED；需要负责人签收的进入 WAITING_OWNER，阻塞为 BLOCKED，批准延后的范围为 DEFERRED。只有 VERIFIED 加相应外部签收才可算发布完成。1.1 中 T00～T26 均为 NOT_STARTED，T27 为 DEFERRED；方向获批不是实现进度。

## 2. 阶段与门禁

| 阶段 | 结果 | 允许进入下阶段的门禁 |
|---|---|---|
| M0 | 完整功能/字段/规则审计 | 基线固定、冲突可解释、未定产品决策有编号 |
| M1 | 可构建工程与设计系统 | Debug/Release技术探针和翻译检查通过 |
| M2 | Kotlin 规则核心 | 原规范输入差分通过，不能用肉眼看数值代替 |
| M3 | 持久化与备份 | 事务/迁移/导入/解析/旧数据通过 |
| M4 | 专注和调度模型 | 重启、重复动作、边界与权限测试通过 |
| M5 | 所有业务 UI | 每屏接真实状态，主要路径不靠假数据 |
| M6 | 系统集成与真实付费 | Widget/分享/权限和支付服务签收 |
| M7 | 同步 | 双设备并发、删除、首次恢复与账号切换签收 |
| M8 | 完整回归 | 全功能 traceability、真机、性能/无障碍通过 |
| M9 | 上架 | 负责人完成 Console 与商业/隐私/签名签收 |
| M10 | Wear（已确认延后） | 不阻塞首发；另行启动后执行独立手表矩阵与手机配对验收 |

开发顺序允许部分并行：M0审计后，设计系统、本地化与fixtures可独立推进。**不能并行重写同一个核心模型，不能让多个 AI 各自发明数据协议。**主执行者负责接口冻结和集成审查。

## 3. 任务卡

源码reads相对固定提交；任务交付的文档默认位于仓库根 `docs/android/`（除非明确写其他路径），不在多个位置复制进度。所有 task 的 reads 路径相对固定提交。同名文件未在当前窗口读到时，应先从仓库定位，不杜撰内容。


### T00 · M0 · 锁定基线与建立工作区

**依赖**：无。**覆盖需求**：全局基线。

**先读**：00_START_HERE、decisions.json、根 AGENTS、git 状态、基线提交与实际 tag。

**执行**：记录当前分支和未提交改动，不清理用户工作区；以固定 SHA 读取 iOS，开发分支只新增 Android 及必要测试工具。若当前源不是固定 SHA，列出差异后选择明确基线，不自行切走未提交修改。

**必须交付**：docs/android/baseline.md；源 SHA、版本、工作树状态、首发/后续范围声明；决策及外部配置台账。

**验收**：核实所有源码链接指向同一 SHA；登记已批准方向与真正未知的配置，不再把Drive/收费模式/验证服务列为待选；账户事实未知就保留UNKNOWN；仓库没有被reset/覆盖。


### T01 · M0 · 完成逐入口功能与规则盘点

**依赖**：T00。**覆盖需求**：FR-01, FR-02, FR-03, FR-04, FR-05, FR-06, FR-07, FR-08, FR-09, FR-10, FR-11, FR-12, FR-13, FR-14, FR-15, FR-16, FR-17, FR-18, FR-19, FR-20, FR-21。

**先读**：AppRouteDestination、所有 Views/设置入口、PreferencesStore、Shift/Records/Focus/Life 模型、AppTests、Shared、当前翻译 key；旧 plans 只作佐证。

**执行**：列出每个可见入口、动作、开关、免费 gate、状态和测试；把未在本包细列的小功能添加为 FR 子项。枚举 source filenames 不是完成盘点，必须追到事件处理函数及持久化字段。将源 Bug/未签收行为单独列风险，不能未经批准复制或修正。

**必须交付**：feature-parity.md；source-inventory.md；conflicts.md；完整功能差异表。

**验收**：三主入口、横屏/平板和深链接目标均覆盖；所有设置 key 有去向或负责人批准的差异，无“暂未找到就视为不存在”。


### T02 · M0 · 冻结字段级备份与领域模型契约

**依赖**：T01。**覆盖需求**：FR-02, FR-03, FR-05, FR-06, FR-07, FR-08, FR-09, FR-14, FR-15。

**先读**：完整 RecordJSON/RecordArchive、12 类实体 DTO、SyncedPreferences、ErasedID、源导入测试；02 第6章。

**执行**：提取每个版本新增字段、默认值、枚举、键、日历/毫秒语义、引用关系；准备匿名合成 v1–v6 档案与非法档案。明确 wire v6、Room v1、fixture v1、sync envelope v1 是不同版本。

**必须交付**：wire-contract.md；synthetic-archives/；字段映射清单。

**验收**：抽样每一类实体；v6 中无自创字段和购买凭据；缺少真实旧样本时从源编码/测试构造并注明，不拿空对象代替。


### T03 · M1 · 创建最小可构建原生工程

**依赖**：T00。**覆盖需求**：FR-19, FR-20。

**先读**：02 第2、3、14章；Android 官方 AGP/Kotlin/Compose 当前文档。

**执行**：使用 Android Studio 当前可用稳定模板/官方配置；创建 app、domain、data、designsystem 等实际需要模块；确定包名候选；先成功运行空页面和纯 JVM 单元测试。不要一开始生成几十个空屏幕。

**必须交付**：可运行 Debug 工程；environment-lock.md；Gradle wrapper/version catalog；基础 CI。

**验收**：./gradlew --version、domain:test、app:assembleDebug 成功；不存在未声明版本动态依赖；实际 SDK/编译器兼容记录齐全。


### T04 · M1 · 完成 Material3 Expressive 依赖与组件探针

**依赖**：T03。**覆盖需求**：FR-18, FR-19。

**先读**：01 第7章；A01/A20/A21/A22；所选版本 API reference。

**执行**：实现主题、主要按钮、分段选择、时间选择、进度与导航小样；记录 Experimental 注解及传递依赖；构建 Debug 与 R8 Release。探针中存在的试验组件不能散落到业务层。

**必须交付**：designsystem 实现和 gallery 测试页面（Debug only）；expressive-adr.md；依赖树。

**验收**：实际包含本项目需要的 Expressive 行为；没有把 stable1.4 API 与 alpha API 混用；减少动态效果及大字体探针通过。


### T05 · M1 · 建立翻译转换与质量检查

**依赖**：T02, T03。**覆盖需求**：FR-18。

**先读**：Localizable.xcstrings、19 locale 目录、01/02 本地化约束。

**执行**：实现离线生成器、key 映射、复数与格式转换；提交 Android 原生 strings/plurals；新增仅 Android 平台文案并补齐19语言；建立重复/缺失/参数类型检查。

**必须交付**：scripts/generate-android-strings.*；check 脚本；key-map；完整 resources。

**验收**：生成后无不应有 diff；XML 可编译；中文三变体、印度语言、阿语、长德文占位符各有专项测试。


### T06 · M2 · 导出共享规则差分 fixtures

**依赖**：T01, T02。**覆盖需求**：FR-02, FR-04, FR-05, FR-06, FR-08, FR-10。

**先读**：lib/countdown、summary、reminders；现有 ios-schedule-rule-oracle 和 Swift FixtureTests。

**执行**：复用现有 oracle 调用，不抄 Kotlin 结果；新增 JSON 输出并记录输入、expected、源 hashes、用例来源；规则生成和 stale-check 是两个独立命令。

**必须交付**：generate-android-rule-fixtures；共享 fixtures；CI stale guard。

**验收**：npm test 仍通过；生成用例数非零且不少于映射范围；手工改变一个源 fixture 后 stale guard 必定失败。


### T07 · M2 · 实现固定班次与时间核心

**依赖**：T03, T06。**覆盖需求**：FR-02, FR-04, FR-05。

**先读**：CountdownRules、Shared/ShiftRuleCore、ScheduleRules、TS 对应函数；02 第4章。

**执行**：按有效段实现工作/休息/夜班、nextShift/nextRest、overtime、manual；注入 Clock/Zone；单独做 civil/DST adapter。先跑 domain fixture，不连接 UI。

**必须交付**：ShiftEngine 与纯 Kotlin 模型；TimeResolver；差分报告。

**验收**：固定规则 fixture 全通过；12:30午休与19:00加班算例正确；0时长、空workdays不崩溃或死循环。


### T08 · M2 · 实现扩展排班和 Swift 特有测试

**依赖**：T02, T07。**覆盖需求**：FR-03, FR-04。

**先读**：ExtendedSchedule/Rules/Editing 与所有对应 Swift 测试。

**执行**：支持周期锚点、manual roster、carry-over、holiday、clearedFrom、frozen shift、base fallback；保持统一 segment 引擎；建立源 Swift 测试→Kotlin 对照。

**必须交付**：ExtendedScheduleResolver；Swift parity fixtures；优先级决策表。

**验收**：锚点前 floorMod、短月、休息与未排、历史冻结、清空后重启均通过；不能用 TS 测试冒充覆盖 iOS 独有逻辑。


### T09 · M2 · 实现记录汇总与人生计算

**依赖**：T07, T08。**覆盖需求**：FR-05, FR-06, FR-08。

**先读**：SummaryRules、lib/summary、LifeViewCalculator/LifeSummary、计划015/016最新修订和调用点。

**执行**：分开 live earnings 与 records fixed monthly allocation；实现自然日分摊、实际/预测、年终奖、职业收入和未来比例；缓存不参与业务结果。

**必须交付**：SummaryEngine/LifetimeEngine；浮点/货币策略；分支测试。

**验收**：跨月周、请假固定月薪不扣、空档、重叠拒绝、一次性比例调整通过；所有相同语义 UI 投影引用统一服务。


### T10 · M3 · 实现 Room、事务与迁移基础

**依赖**：T02, T03。**覆盖需求**：FR-06, FR-07, FR-09, FR-14, FR-15。

**先读**：实体字段契约、RecordCoordinator/Command 的行为与源写入错误处理。

**执行**：建立业务实体、索引、外键/逻辑引用校验、outbox、tombstone；实现事务写 API；schema 导出；写入错误保留原数据与草稿。

**必须交付**：Room DB/DAO/mappers；Repository；MigrationTests；seed 测试。

**验收**：进程重启读回一致；低空间/事务失败不部分提交；没有生产 destructive migration；data 模块测试真实数据库。


### T11 · M3 · 实现 JSON 导入导出与冲突管理

**依赖**：T10, T02。**覆盖需求**：FR-14, FR-17。

**先读**：完整 RecordJSON/RecordsActions/RecordArchive；02 第6章。

**执行**：SAF选择、大小限制、版本校验、候选合并预览、原子写；同ID与墓碑处理；恢复UUID映射；排除人生导出；冲突中心。

**必须交付**：ArchiveCodec/ImportCoordinator；导入预览UI；双向往返测试。

**验收**：v1–v6 每版本成功与失败样例；v7明确拒绝；重复导入不重复；收入隐藏时身份确认；导入不能改购买状态。


### T12 · M3 · 实现日记录解析和编辑命令

**依赖**：T08, T09, T10。**覆盖需求**：FR-06, FR-07。

**先读**：DayRecordResolver/RecordActions/DayOverrideProjection/RecordDayEditDraft。

**执行**：唯一 expandableHours 入口；实现覆盖/例外/快照链与观测分离；多个层同事务保存；历史编辑和薪资视图不互相污染。

**必须交付**：DayResolver/RecordCommandHandler；编辑状态机；来源标记DTO。

**验收**：cleared回退、手工例外优先、快照同日排序、保留休息、历史冻结均通过；不能用现在设置重算全部历史。


### T13 · M4 · 实现专注模型、计划、模板与恢复

**依赖**：T07, T10。**覆盖需求**：FR-09。

**先读**：FocusModels/Planner/Store各分文件/LiveChain；对应源测试。

**执行**：按源实现计划块、任务、收藏、模板、可开始条件与边界；实现确定性SHA256身份；持久化会话；以领域事件推进恢复，UI暂不复杂美化。

**必须交付**：FocusEngine/Repository；身份vectors；recovery tests。

**验收**：完整前缀任务放置、不重写当前终点、双击/重启/通知竞争不重复；结束原因完整；非工作块不能越界开始。


### T14 · M4 · 实现提醒规划与 Android 调度适配

**依赖**：T06, T07, T12, T13。**覆盖需求**：FR-10, FR-11。

**先读**：lib/reminders/ReminderRules、源健康/通知设置与计划012；A10/A24。

**执行**：领域输出绝对提醒；Android实现权限状态、差量调度、稳定ID、重启/时间变化恢复；去重进度/周期/专注边界；非精确降级。

**必须交付**：ReminderPlanner；AlarmScheduler；Receiver/permission UI；notification tests。

**验收**：拒绝通知/精确权限不阻断主应用；无全天FGS；普通结束与周期总结不双响；系统强停限制写清楚。


### T15 · M5 · 实现主壳、首次启动和设置

**依赖**：T04, T05, T10。**覆盖需求**：FR-01, FR-17, FR-18, FR-19。

**先读**：01逐页规范、AppRouteDestination、FirstRunRecovery、源完整偏好清单。

**执行**：三主入口独立导航栈；恢复/新建草稿流程；设置分组；错误/空/恢复态；窗口和后台重建保持状态；云入口先使用接口但不假装实现完成。

**必须交付**：导航、Onboarding、Settings；UI与状态恢复测试。

**验收**：免费离线用户能完成设置；默认值不变成dirty上传；back关闭弹窗不退出错误层；平板/横屏无重复状态。


### T16 · M5 · 实现计时、收入与排班页面

**依赖**：T07, T08, T15。**覆盖需求**：FR-02, FR-03, FR-04, FR-05。

**先读**：01计时/排班/薪资规范与具体源视图动作。

**执行**：所有状态接真实领域投影；排班日历、班型、循环、当日调整；收入隐藏和身份确认；按数字区域局部刷新，不用假倒计时。

**必须交付**：Timer/Schedule/Salary页面；interaction与截图基准。

**验收**：各状态图/语义树可验证；首尾相等夜班、休息、未排班都有UI；输入失败不提交；权限拒绝仍可用。


### T17 · M5 · 实现记录、图表、日编辑与人生页面

**依赖**：T09, T11, T12, T15。**覆盖需求**：FR-06, FR-07, FR-08。

**先读**：01记录/人生、现有日画布与LifeView；免费投影门禁。

**执行**：日周月年/人生尺度；选中稳定ID；actual/projected文本标记；大屏独立滚动；图形等价列表；接真实编辑与导出。

**必须交付**：Records/Life UI；免费/Plus fake仅debug；截图/可访问测试。

**验收**：不以假图表示成功；隐藏值不在Semantics；200%字体和阿语无截断关键值；大数据不每秒全算。


### T18 · M5 · 实现专注画布与无障碍操作

**依赖**：T13, T15。**覆盖需求**：FR-09, FR-18。

**先读**：FocusCanvas/BlockSheet/UsualScale/Template相关源UI与01规范。

**执行**：完成任务新增编辑收藏、落位、计时、模板应用；拖动和非拖动路径均接同一命令；保存草稿；锁屏和通知入口返回同一任务上下文。

**必须交付**：Focus UI；拖动/替代动作测试；边界状态截图。

**验收**：未到时间/不够时间/其他会话占用各有正确反馈；重开恢复不新开第二计时；付费后续动作只执行一次。


### T19 · M6 · 实现小组件、分享、链接与平台隐私

**依赖**：T11, T14, T16。**覆盖需求**：FR-11, FR-12, FR-13, FR-17。

**先读**：源Widget投影、分享协议、当前品牌资产；A11/A12/A25；02第8/11章。

**执行**：安全Widget DTO、多尺寸Glance、过期态；普通通知适配；独立分享图渲染；SAF/FileProvider/AppLinks；备份排除规则。

**必须交付**：Widgets/Share/LinkHandler；manifest与dataExtractionRules；链接配置说明。

**验收**：薪资不会出现在组件/通知/分享元数据；组件多实例/重启/尺寸变化；链接预览不自动覆盖；不新增危险权限。


### T20 · M6 · 实现权益领域与 Billing 客户端

**依赖**：T03, T15。**覆盖需求**：FR-16。

**先读**：PlusEntitlement、01矩阵、02第9章、A06/A08；D-01/D-07。

**执行**：状态机、ProductDetails本地价格、single-flight购买/恢复、pending/取消/失效/离线；连接真实验证接口；fake隔离debug；保存原操作上下文。

**必须交付**：EntitlementEngine/BillingRepository/Paywall；状态转移测试。

**验收**：取消续费未到期仍可用；Pending无权；断网不抹已验证缓存；同意D-07前保持源失效采集行为。

**决策与配置**：已确认 D-01, D-03；待配置 CFG-PRICE；未决 D-07。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


### T21 · M6 · 部署真实购买验证与通知处理

**依赖**：T20。**覆盖需求**：FR-16, FR-20。

**先读**：02第9章；A07/A08；D-08已确认记录、CFG-BACKEND与服务凭据边界。

**执行**：实现Publisher验证、幂等权益持久化、确认重试、RTDN重查、撤销/linkedToken、签名缓存；最小权限部署；不收工资或记录。

**必须交付**：独立权益服务代码；部署runbook；监控/重试；接口contract tests。

**验收**：真实许可测试账户购买、恢复、pending、退款、取消及重复RTDN；无密钥进Git/APK；只有mock通过不算生产完成。

**决策与配置**：已确认 D-08；待配置 CFG-BACKEND。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


### T22 · M7 · 实现 Android 私有云恢复与同步

**依赖**：T10, T11, T13, T20。**覆盖需求**：FR-01, FR-15。

**先读**：源Recovery/RecordsCloudSync/SyncPayload/SyncLocalState与相关测试；02第10章；已确认D-02/D-03与CFG-OAUTH。

**执行**：Google授权与私有scope；pull-before-push；不可变批次+墓碑；首次恢复/冲突；账号切换；reset fence；持久outbox与重试；明确无iCloud自动互通。

**必须交付**：SyncTransport/Coordinator；设置恢复页；sync-protocol.md；模拟传输contract tests。

**验收**：新设备旧机关闭恢复；双设备改不同日不丢；删除后离线旧设备不复活；授权取消/配额/分页失败不当空云；使用已批准Drive完成真实联调与双设备验收，不能只靠mock。

**决策与配置**：已确认 D-02, D-03；待配置 CFG-OAUTH。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


### T23 · M8 · 全功能集成与权限/付费回归

**依赖**：T17, T18, T19, T21, T22。**覆盖需求**：FR-01, FR-02, FR-03, FR-04, FR-05, FR-06, FR-07, FR-08, FR-09, FR-10, FR-11, FR-12, FR-13, FR-14, FR-15, FR-16, FR-17, FR-18, FR-19, FR-20。

**先读**：07完整用例；feature-parity.md；已批准D项。

**执行**：移除所有生产mock占位；串联路由、通知、恢复、购买后续动作；使用真实发布配置，关闭Debug特权；补齐M0枚举的细小功能。

**必须交付**：全量traceability报告；阻塞清单；Release candidate。

**验收**：FR全映射；每条通过附测试名/证据；无“编译过所以功能完成”；功能数量和用例数均非零且无被偷偷删项。


### T24 · M8 · 性能、无障碍与真机系统矩阵

**依赖**：T23。**覆盖需求**：FR-18, FR-19, FR-20。

**先读**：01 NFR；04/07系统矩阵。

**执行**：中档机宏基准、15k日历数据、长列表；手机平板折叠大字体RTL；Doze/重启/精确权限/强停；截图和TalkBack；必要native16KB验证。

**必须交付**：性能与真机报告；截图集合；修复与复测；baseline profile如有收益。

**验收**：按参考机型记录原始结果，不编百分比；每个外部能力单独签收；减少动效后无持续震动/循环动效。


### T25 · M9 · 完成 Google Play 配置与发布资料

**依赖**：T23, T24。**覆盖需求**：FR-20。

**先读**：04发布手册；D-10/D-11；当前Play Console实际提示。

**执行**：负责人创建/核对应用与商品、签名、隐私链接、Data safety、内容分级、目标人群、App access、测试轨道；生成真实Android商店截图与审查说明；API版本重新核对。

**必须交付**：发布AAB/hash/mapping；store-listing；privacy-data-map；console checklist。

**验收**：商店宣称与实际功能/价格一致；涉及新个人账号的12人14天条件按实际账号核实；无已读事实被代填为已审批。

**决策与配置**：已确认 D-01, D-02, D-03, D-08；流程已确认 D-11；待配置 CFG-PRICE, CFG-OAUTH, CFG-BACKEND, CFG-PLAY-ACCOUNT, CFG-APP-IDENTITY；未决 D-10。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


### T26 · M9 · 发布签收、分阶段上线与回滚

**依赖**：T25。**覆盖需求**：FR-20。

**先读**：04最终门禁与故障预案。

**执行**：负责人审批生产提交；使用内部/封闭测试后再开放；能分阶段时分阶段发布并监测Android vitals/评价；回滚采用更高versionCode修复，保留数据库向前兼容。

**必须交付**：release-signoff.md；版本/commit/tag关联；事故runbook。

**验收**：签名和包名与Console一致；发布不自动执行未经授权账号操作；发现数据丢失/付费错误立即停止扩量。


### T27 · M10 · 后续阶段：Wear OS 独立交付（首发不执行）

**依赖**：T07, T08, T19。**覆盖需求**：FR-21。

**当前状态**：DEFERRED。**范围**：后续阶段，不阻塞手机/平板首发。

**先读**：源Shared/WatchApp/WatchWidgets、AGENTS当前免费定位；D-05；当时官方Wear文档。

**执行**：本轮已确认延后，不参与手机/平板首发。后续阶段获准启动时：复用domain规则，Data Layer传工资无关排班与版本，独立离线解析、过期/未配对态，两类复杂功能；使用Wear Compose Material3而非手机布局缩小。

**必须交付**：Wear app/complications；手机配对说明；Wear发布矩阵。

**验收**：离开手机仍可解析未来排班、不靠短期过期snapshot；无工资/购买Token传输；Watch免费规则未经批准不改收费。

**决策与配置**：已确认 D-05。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。

## 4. 每个任务提交前的固定检查

检查本任务测试实际执行数量、失败日志和产物时间；review git diff 确认没有删除测试、降低断言、加入真实秘密、擅改商店文案、破坏 Web/iOS；确认所有新增文案进入 19 locale；确认 Release 与 Debug 不共享测试解锁。

一次提交解决一个可描述的职责。提交说明包含用户可见原因、源规则依据、改动文件、测试命令与结果、未验证项。禁止仅写“优化”“fix all”。不要自动 push main、打发布 tag、上传 Play 或创建商品，除非负责人明确授权相关外部操作。

## 5. 每次交接给下一 AI 的状态模板

```markdown
# Android 实施交接
Source baseline: <SHA>
Android work commit: <SHA>
Completed task IDs: <真实完成>
Current task: <ID>
Approved decisions: <D IDs + 负责人原文/日期>
Changed files: <列表>
Executed checks: <命令、执行数、结果、产物路径>
Not executed: <原因，不能写通过>
Known failing tests: <测试名、预期/实际、最小复现>
Next executable task: <ID + 输入>
Protected files / uncommitted owner changes: <明确记录>
```

任务状态必须提交到 `docs/android/progress.md` 和机器清单或等价项目记录。下一个会话只需读取00、进度、当前任务卡、涉及的02章节和源文件，不必每次吞下整个仓库。

## 6. 纠偏规则：较弱 AI 最常见的错误

| 错误实现 | 正确纠偏 |
|---|---|
| 只做了计时页就宣布完整移植 | 对照 FR 总表与 M0 矩阵，不具备的功能仍未完成 |
| 每秒 end-now，午休也涨收入 | 先修有效段引擎与差分测试，再接UI |
| 完整保留一次旧快照以为历史固定了 | 检查 live roster + frozen assignment 的统一解码入口 |
| DayOverride、观测、排班混成一张随意覆盖表 | 恢复源解析链与事实证据分层 |
| 时区变化给每条日期加减8小时 | 日期是标签，Instant才做时区换算 |
| 月薪一律除21.75或按出勤扣款 | 区分计时页/记录页语义，按当前源与后续修订 |
| Focus自动session用随机UUID或Java nameUUID | 精确实现源SHA256裁切与bit规则 |
| Play购买回调成功就设置isPlus=true | 校验平台证据，持久化、确认、恢复与撤销完整走通 |
| 失去网络等于用户失去终身权益 | 区分不可用与确认无权益；保留最后已验证缓存 |
| 云同步覆盖一个JSON，以时间较新胜出 | 保留每实体编辑戳与墓碑，多设备合并 |
| 关闭同步就删云数据 | 区分暂停、云删除、本机移除 |
| Auto Backup从未配置却宣传工资绝不上传 | 审计最终备份规则与数据流，必要时更正文案 |
| 减少动画只把时长设小 | 移除连续循环/触感，保留静态可理解状态 |
| 单元测试通过=通知、购买、云同步都通过 | 这些需要对应真机/真实服务证据 |
| 编译报错就删Expressive控件换普通UI | 先检查锁定版本/API；需降级须负责人批准 |
| 使用默认主题就称Material3 Expressive | 依据设计系统gallery及逐屏验收检查形状/层级/动作/动效 |
| 生成了AAB就说已上架 | 实际Console配置、测试资格与审查是独立发布门禁 |

## 7. 禁止自动改变的范围

未征得确认，禁止新增 DoneAt 登录系统、跨平台权益服务、广告/分析 SDK、全局云端工资数据库；禁止改订阅价格、试用期限、免费窗口、历史采集政策、源收入口径；禁止为了Android修改线上iOS规则使其迎合错误结果；禁止把负责人私钥、Play令牌、真实导出文件放进测试仓库。

可以自主处理：纯工程文件布局、变量命名、局部无语义重构、补足测试和文案错误、在已批准设计token内改善排布。对产品/数据语义有影响的差异必须进入 decisions/ADR，不可埋在实现备注里。


---

<!-- section: 04_QA_AND_PLAY_RELEASE.md -->

# 04 · 验收、Google Play 上架与运行维护手册

**1.1 决策状态**：已确认收费模式、Drive首发同步、首发跨平台边界、Wear延后和购买验证服务；Play账户核验流程已确认，但账户事实未知。方案确认不等于QA通过、生产服务部署或发布许可。首发范围FR-01～FR-20；QA-137/T27只属后续Wear。详见05及decisions.json。

这份清单区分能自动验证的代码与必须由负责人/真机/真实服务验证的事项。当前交接包没有执行其中的 Android 测试，也没有访问 Play Console。公开平台规则核对日期为 2026-09-21，正式提交前复核。[A04], [A09], [A14], [A23]

## 1. 验收证据结构

每项结果包含：需求 ID、测试 ID、源规范位置、Android 实现路径、前置条件、操作/输入、预期、实际、设备/构建/日期、证据路径、执行人。用例状态只能 PASS / FAIL / BLOCKED / NOT_RUN；没有日志或截图的真机结论不能填 PASS。

一个功能同时需要领域与平台验证时分别登记。例如：提醒时间计算 PASS，不等于 Pixel/三星熄屏下真实投递 PASS；购买状态机 PASS，不等于真实 Play 退款回收 PASS；模拟同步 transport PASS，不等于两台设备上真实 Drive 恢复 PASS。

建议 `docs/android/qa/traceability.md` 使用：

| FR | Source | Android | Automated | Device/service | Result |
|---|---|---|---|---|---|
| FR-04 | CountdownRules + rule fixtures | ShiftEngine/Timer | 测试名与报告 | 设备场景 | 待执行 |
| FR-14 | RecordJSON | ArchiveCodec | 版本/往返测试 | 文件选择器恢复 | 待执行 |

本表只是格式示例，不能复制两行就声称覆盖全功能。

## 2. 测试层级与环境矩阵

| 层级 | 验证内容 | 环境 | 禁止替代 |
|---|---|---|---|
| Domain unit | 时间、排班、收入、记录解析、专注、权限判定 | JVM + 固定 Clock/Zone | 不靠屏幕上的数字人工目测 |
| Differential | 同输入与原 TS/Swift 输出比较 | Node/JVM/macOS Swift CI | 不用自创 expected 代替全部源规范 |
| Persistence | Room、迁移、事务、导入冲突/失败回滚 | Android instrumentation | 不只测内存 fake repository |
| UI | 点击、导航、锁定状态、无障碍、窗口重建 | Compose tests + screenshot | 不把一张Preview当运行页面 |
| Platform | 权限、后台、通知、小组件、分享、链接、生物识别 | 模拟器+真机 | 不只在前台模拟时间 |
| Commerce | 购买、优惠资格、pending、确认、续费、恢复、退款 | Play许可测试+服务端 | 不靠本地isPlus开关 |
| Cloud | 首次拉取、双设备并发、删除fence、账号切换、配额 | 真实测试Google账号/设备 | 不以本机导出文件代替云恢复 |
| Release | R8、签名、API、AAB、16KB、最终权限 | Release构建+Console预发布报告 | 不用Debug成功替代 |

建议至少覆盖 API 26、31/32、33、34/35、36 及发布时最新稳定 Android。每个 API 不必组合所有机型，但通知/精确闹钟权限变化节点必须测试。目标 API 与运行系统 API 是不同维度。

设备建议：一台当前 Pixel/接近原生的实体机，一台主流厂商实体机，一台中档参考性能机；平板可实体机加模拟器；折叠/分屏使用可调整窗口环境。不要把具体型号未提供当成不能开始，先在模拟器完成自动化，再列出真机签收。

布局：窄屏约360dp、常见400dp以上、横屏、600dp附近、840dp以上；浅/深/跟随系统、品牌/动态色；100%/130%/200%字体；英语、简中、繁中港台、德文长文本、阿语RTL及其余语言资源检查。

## 3. 重点业务门禁

**时间**：同一毫秒边界的半开区间一致；跨夜属于原班次日期；休息期间收入冻结；加班分母不改原计划时薪；关闭App再开不累计漂移；DST和时区变化有fixture。

**记录**：计划与观测分离；实际与预测不重复；月薪口径按最新修订；历史编辑保留休息空隙；重新编辑班型不改变已冻结历史；免费窗口按自然日期。[R02], [R05], [R08], [R10], [R14]

**数据**：1–6版备份、v6双向往返、损坏/过大文件、重复导入、同ID冲突、墓碑、引用重映射、低空间和中途死亡；旧库升级不丢数据。[R07]

**专注**：确定性ID、单活跃会话、边界停止、模板完整前缀、设置只影响下轮、恢复不会伪造已完成任务。[R06]

**付费**：待付款无权益；取消续费未过期保留；到期准确；终身离线缓存；查不到服务不等于查到空权益；恢复不丢原动作；源“过期后停止观测”的政策按D-07执行。[R05], [A06], [A08]

## 4. 安全与隐私发布门禁

### 4.1 逐条数据流登记

| 数据 | 默认位置/动作 | 发布前需要确认 |
|---|---|---|
| 工资、班次、职业、任务与记录 | 本地Room | 未同意同步前无离设备传输；日志和组件无内容 |
| 用户主动JSON导出 | 用户选定SAF目标 | 明确告知包含个人信息；排除购买/授权秘密 |
| Drive同步业务数据 | 用户主动授权后上传私有空间 | 解释字段、目的、关闭与删除；不能等同“未收集”自动填表 |
| 购买Token/产品/权益时间 | Play及批准的权益服务 | 购买记录/标识的收集、用途、保留和删除说明 |
| 服务端基础请求日志 | 取决于托管配置 | IP/UA是否保存、保留多久、是否可关闭；不要口头承诺零日志 |
| 崩溃/性能诊断 | 默认不加外部SDK | 增加后重新审计数据安全和隐私政策 |
| 通知授权/系统能力 | 本机系统状态 | 不与其他设备互相覆盖 |
| 用户联系开发者 | 系统邮件/浏览器显式动作 | 默认不附工资、记录和未脱敏日志 |

Google Play 对仅在设备上处理的数据、离设备传输、可关联标识与用户发起分享分别有定义。**不因为“无DoneAt账号”“使用私人Google Drive”“不做广告”就直接选择No data collected。**按最终实现和每个SDK/后端行为填写，留存说明依据。[A14]

如未来引入应用账号创建，需要重新核对 Play 的应用内及外部账号删除要求；当前无账号方案不因此豁免本地/云业务数据删除功能。Google OAuth 授权与本应用账号是否构成政策意义上的账号体系，应按实际实现判断，不能只改按钮名字规避。[A29]

### 4.2 最终包与网站

最终 merged manifest 无无关敏感权限；明文网络关闭；exported组件与Intent过滤器最小化；未导出内部receiver；所有允许外部输入的链接和文件经过验证。

备份策略验证 cloud backup 与 device-to-device transfer；密钥/Token不进入备份；业务默认本地承诺与Auto Backup行为一致。[A16], [A28]

隐私政策使用稳定公开HTTPS页面，应用内和商店均可打开，明确DoneAt Android、运营主体/联系渠道、数据类型、目的、存储/同步、购买验证、第三方服务、保留/删除、用户选择。它必须描述最终版本，不复制iOS“仅iCloud”文本；政策不是AI写好就已经合法审核。

普通分享图、通知、Widget、调试信息无工资；可视隐藏时TalkBack/最近任务截图也不泄露。若使用截图限制，实际测试正常无敏感分享仍可用。

## 5. Google Play 账户与身份准备（负责人操作）

确认现有开发者账户、个人/组织类型、创建日期、实际可用地区与收款资料状态；不要为了绕验证虚构国家或主体。本人完成当前Console要求的身份/设备等验证，开发AI只给步骤，不代填无法验证的信息。[A23]

对**2023-11-13以后创建的个人开发者账户**，当前官方要求在申请生产访问前完成至少12位测试者连续加入封闭测试14天。满足天数后还需申请并回答测试反馈与准备情况，不是14天一到自动上架。旧个人/组织账户按其实际Console状态核实，不一概套用。[A09]

测试者需要真正体验关键功能并反馈；不要买虚假测试或只凑名单。提前安排跨夜、备份、权限和付费测试脚本，避免等开发结束后才发现生产访问未开放。

## 6. 创建应用与签名

负责人确定应用名DoneAt、默认语言、应用类别、是否含广告、分发国家、应用本体免费+内购模式、应用ID（D-10），再创建对应Play条目。不能把Play的应用价格和Plus内购混为一件事。[A23]

包名一经正式使用须长期维护；建议 `com.rainif.doneat` 仅为候选，首次上传前检查Console冲突和负责人决定。debug使用`.debug`后缀并使用独立数据空间，防止开发覆盖正式档案。

使用Android App Bundle与Play App Signing流程。负责人保管upload key、备份和恢复方案；CI只在受保护发布环境访问upload签名资料；应用签名证书与upload证书不同，Google OAuth/App Links/Firebase等关联必须使用正确证书，尤其正式分发使用Play app signing证书。[A23], [A25]

发布前核对：applicationId、versionName、单调增长versionCode、minimum/target/compile API、支持ABI、依赖许可、R8 mapping、AAB SHA256。扫描AAB是否包含native库并验证16KB；当前官方时间点/Console警告复核，不复制旧博客的截止日期。[A04], [A17]

### 账户事实核验记录（D-11 / CFG-PLAY-ACCOUNT）

| 事实 | 当前值 | 可接受的后续依据 |
|---|---|---|
| 是否已有 Play 开发者账户 | UNKNOWN | 负责人明确提供或实际 Console 核对 |
| 个人 / 组织 | UNKNOWN | 实际账户资料；不从 Apple 开发者身份推断 |
| 创建时间 | UNKNOWN | 账户记录或负责人明确说明 |
| 身份验证与生产访问 | UNKNOWN | 当前 Console 任务/状态与核验日期 |

在 M0 建台账并尽早核验；涉及资格的最终判断以提交时实际账户和官方要求为准。缺失以上资料不得代填“已通过”，也不得用它阻塞独立的本地开发。私密身份材料和密钥不要求粘贴在聊天或提交进公开仓库。

## 7. Play Billing 配置与真实验证

创建D-01批准的订阅产品、月/年base plan和终身非消耗商品；设置销售国家/价格、有效状态、可用优惠、宽限/保留策略及适用条款。每个商品在应用读取到的ProductDetails与Console一致。[A06], [A08]

配置Publisher API访问与最小权限，部署权益验证服务，配置RTDN入口和鉴权，确认服务端ack重试。将许可测试者与封闭测试者分别核对：在测试轨道能安装，不必然等于具备正确的Billing许可测试设置。

至少实际完成一次：月/年购买、终身购买、用户取消、付款Pending、Pending成功/取消、App退出后恢复、重装恢复、取消自动续费后到期前使用、测试续费、退款/撤销、服务暂不可用、重复回调/RTDN。优惠资格用真实符合/不符合两组账户验证。

不要在普通真实账户上无确认地进行不可逆扣费。开发环境与生产环境的包名/服务端allowlist分开；假购买只用于测试，不能遗留在发布包。

## 8. 商店资料与截图

资料必须展示**真正运行的Android Material3 Expressive界面**，不能拿iPhone截图、概念渲染图或未实现的Wear/云同步页面冒充。使用合成测试数据，不使用用户真实工资/经历。[A26]

最少准备：应用标题、简短说明、完整说明、支持联系方式、隐私政策、图标、feature graphic、手机截图；平板既然纳入范围，也准备真实大屏截图。19种UI语言不等于自动生成合格商店文案，商店本地化要单独检查长度与“免费/Plus”表达。

当前核实的基础素材规格：图标512×512 PNG、最大1024KB；feature graphic 1024×500 JPEG或无alpha PNG；简短说明最多80字符。手机素材建议准备4–8张真实9:16截图，按当前Console设备分类与分辨率要求导出；不要套用过高细长机型截图直接违反最大长宽比要求。[A26]

建议截图叙事（实际功能完成后执行）：①一眼看清下班剩余有效时间；②多班型与轮班；③工时与收入估算，清晰标注Plus能力；④专注画布；⑤记录与人生；⑥Android小组件；⑦平板分栏/隐私与备份。一个画面讲一个点，前几张优先展示真实UI，不能整套只有装饰文字。

完整说明需明确：基础功能免费范围、Plus用途、终身非自动续费、月/年自动续费由平台管理、同步提供商/适用平台、估算非工资结算、离线功能与系统提醒限制。避免“永久免费”“永不延迟”“自动与iCloud互通”等与最终产品不符的承诺。

## 9. App content / 审查资料

逐项填写当前Console要求：Data safety、隐私政策、广告、内容分级、目标人群、App access、特殊权限声明及适用的其他表单。[A14], [A23]

没有账号的核心路径应明确告诉审核人员。存在Plus付费门禁或Google授权的测试路径时，提供平台支持的审查访问说明/测试配置，不能在正式APK放隐藏万能解锁码。审查说明写清如何设置短测试班次、进入记录/专注、恢复文件、查看小组件和管理数据。

精确闹钟/前台服务若最终存在，声明必须反映真正用例；本包默认不使用全天FGS，不声称享有USE_EXACT_ALARM豁免。未使用的权限从merged manifest移除。[A10], [A24]

## 10. 轨道与发布顺序

内部测试：构建安装、Crash、关键恢复/支付流程。封闭测试：符合实际账户要求的测试者与周期、收集真实反馈；服务和商品使用可控测试配置。生产访问申请获准、QA和数据/商业决策签收后，才提交生产审核。能够分阶段发布的更新按负责人选择的比例逐步扩量；首次发布的可用选项以Console为准。[A09], [A23]

上架状态是提交/审核中/获准/实际上线的真实状态，不能把“上传AAB成功”写成“已上架”。审核处理时间不可保证；发现阻塞按实际原因修复，不重复盲目提交。

## 11. 运行监测与回滚

不加行为分析SDK也可以由负责人查看Play Console已有的Android vitals、安装/崩溃和用户评价等聚合信息；不要因此擅自给App添加用户追踪。服务端仅监测购买验证/ack重试/RTDN失败与同步相关技术错误，保持日志脱敏。

停止扩量条件：数据丢失、旧备份无法恢复、明显收入/时间计算错误、购买后无法使用/误扣费、隐私泄露、大规模Crash/ANR。优先停止受影响版本扩量、保全日志与用户数据、发布更高versionCode修复包。不能指望用户安装更旧APK即可回到旧数据库schema。

服务器出错时保留已验证权益缓存；客户端出错时不要建议用户先清除数据/重装。先导出或保存受保护副本，在修复版本中验证迁移恢复；无法备份时明确风险并选择不破坏数据的诊断。

## 12. 发布签收表

| 门禁 | 签收人 | 当前状态 |
|---|---|---|
| 产品方向与首发边界 | 项目负责人 | 六项建议已确认；D-11仅流程确认，不代表账户事实已核实 |
| 其余D项、商品参数与生产环境 | 项目负责人 | 待配置/签收；按05及decisions.json，不重复询问已确认方向 |
| 源码差分/领域/数据库/导入测试 | 开发与审查AI/人员 | 待执行 |
| 真机后台、权限、小组件、无障碍 | 测试人员 | 待执行 |
| 真实购买与服务端/RTDN | 负责人+开发 | 待执行 |
| 真实多设备同步与删除 | 负责人+测试 | 待执行 |
| 19语言、Material3 Expressive与大屏 | 产品负责人 | 待执行 |
| 隐私、安全、许可证与最终权限 | 负责人+审查 | 待执行 |
| AAB、签名、版本、Play表单/测试资格 | 负责人 | 待执行 |
| 生产发布授权与回滚联系人 | 负责人 | 待执行 |

产品方向一行记录本轮真实确认，其余工程、设备、服务与发布门禁仍未执行。方向批准不得改写为测试“通过”；实际通过必须来自后续开发证据。


---

## 本文参考网址

- **A04** · [Google Play 目标 API 政策](https://support.google.com/googleplay/android-developer/answer/11926878)
- **A06** · [Play Billing 接入](https://developer.android.com/google/play/billing/integrate)
- **A08** · [订阅生命周期](https://developer.android.com/google/play/billing/lifecycle/subscriptions)
- **A09** · [新个人开发者账户的测试要求](https://support.google.com/googleplay/android-developer/answer/14151465)
- **A10** · [AlarmManager 与精确闹钟权限](https://developer.android.com/develop/background-work/services/alarms)
- **A14** · [Google Play Data safety 申报](https://support.google.com/googleplay/android-developer/answer/10787469)
- **A16** · [Android 数据备份默认行为](https://developer.android.com/identity/data/backup)
- **A17** · [16 KB 内存页兼容](https://developer.android.com/guide/practices/page-sizes)
- **A23** · [Play 创建与设置应用](https://support.google.com/googleplay/android-developer/answer/9859152)
- **A24** · [前台服务类型与适用范围](https://developer.android.com/develop/background-work/services/fgs/service-types)
- **A25** · [Android App Links 校验](https://developer.android.com/training/app-links/verify-applinks)
- **A26** · [Play 商店预览素材规范](https://support.google.com/googleplay/android-developer/answer/9866151)
- **A28** · [Android Auto Backup 排除规则](https://developer.android.com/identity/data/autobackup)
- **A29** · [Google Play 账号删除要求](https://support.google.com/googleplay/android-developer/answer/13327111)
- **R02** · [iOS 快照与主倒计时显示规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift)
- **R05** · [Plus 权益与免费窗口](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift)
- **R06** · [专注模型、模板与确定性会话 ID](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift)
- **R07** · [RecordJSON：跨平台备份协议与合并](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift)
- **R08** · [记录日解析优先级](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift)
- **R10** · [当前汇总与人生收入规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift)
- **R14** · [计划 016：后续修订、首次恢复、固定月薪](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md)

[A04]: https://support.google.com/googleplay/android-developer/answer/11926878
[A06]: https://developer.android.com/google/play/billing/integrate
[A08]: https://developer.android.com/google/play/billing/lifecycle/subscriptions
[A09]: https://support.google.com/googleplay/android-developer/answer/14151465
[A10]: https://developer.android.com/develop/background-work/services/alarms
[A14]: https://support.google.com/googleplay/android-developer/answer/10787469
[A16]: https://developer.android.com/identity/data/backup
[A17]: https://developer.android.com/guide/practices/page-sizes
[A23]: https://support.google.com/googleplay/android-developer/answer/9859152
[A24]: https://developer.android.com/develop/background-work/services/fgs/service-types
[A25]: https://developer.android.com/training/app-links/verify-applinks
[A26]: https://support.google.com/googleplay/android-developer/answer/9866151
[A28]: https://developer.android.com/identity/data/autobackup
[A29]: https://support.google.com/googleplay/android-developer/answer/13327111
[R02]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift
[R05]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift
[R06]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift
[R07]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift
[R08]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift
[R10]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift
[R14]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md


---

<!-- section: 05_SOURCES_AND_DECISIONS.md -->

# 05 · 源码证据、已确认决策与参考资料

## 1. 本轮核对的范围

固定仓库：`ififi2017/Off-Work-Countdown`，主分支在核对时指向 `9252fdfdc66aab88b4acb7493684f11991fd773d`，该提交时间 `2026-09-20T14:07:09Z`。固定版本：[查看提交](https://github.com/ififi2017/Off-Work-Countdown/commit/9252fdfdc66aab88b4acb7493684f11991fd773d)。主分支含3.2.0相关修改，但没有用商店二进制做一致性验证。

本轮通过仓库接口读取目录和关键文件。未运行代码，未获取完整本地clone，未检查全部Swift行、全部测试执行结果、真实iOS界面或生产服务。以下区分“实际读到的内容”和“下个AI必须继续读的内容”，避免把计划当成审计完成证明。

| 资料 | 本轮读取情况 | 直接支持的结论 |
|---|---|---|
| 根AGENTS | 1–480行分段核对 | 原生SwiftUI、本地优先、无产品账号、共享规则、薪资隔离、19语言、Watch免费等 [R01] |
| README_CN | 读取项目介绍及可见内容 | 品牌和基础功能；同步表述不可作为当前唯一依据 [R23] |
| 目录树 | root/src-mobile/ios/App/Shared/Native/Models/Views/plans等；部分大树响应截断 | 核实源码路径、原生结构和19 locale；不等于所有文件全部审完 |
| CountdownRules.swift | 完整读取 | NativeShiftSnapshot字段、heroRemaining分支、平台无薪资投影 [R02] |
| ExtendedSchedule.swift | 完整读取 | 班型、周期、手排、冻结类型、清空边界、字段约束 [R03] |
| ExtendedScheduleRules.swift | 1–225行 | 统一tuple接入、计划索引、手排/冻结/回退接口；后部组合分支仍需源测试 [R04] |
| PlusEntitlement.swift | 1–340行（分段有交叠） | 权益状态、免费7日、失效后观测停止、门禁及pending action [R05] |
| FocusModels.swift | 1–260行 | 确定性ID、计时默认/范围、Task/Plan/Template模型与完整前缀 [R06] |
| RecordJSON.swift | 1–410行中的核心导出/导入片段 | schema6接受1–6、实体、墓碑/冲突模式、导出字段；完整DTO与merge尾部待读 [R07] |
| DayRecordResolver.swift | 1–210行 | 计划链、选择规则、索引和观测分离 [R08] |
| RecordsActions.swift | 1–220行 | 导出、导入预览、隐私确认、编辑门禁与时间边界保留段 [R09] |
| SummaryRules.swift | 1–220行 | 共享TS规范、时间区间、薪资/人生部分；记录页最终调用链待完整测试 [R10] |
| AppRouteDestination.swift | 完整读取 | 三主入口相关二级页面与统一Focus画布路由 [R11] |
| RecordsSyncSettingsView.swift | 1–210行 | 首次恢复、开关反映提交态、暂停/云删/本机移除与互斥 [R12] |
| plans/012 | 完整读取 | 评价资格、周期总结与去重；旧JS运行时实现已被后续方案取代 [R15] |
| plans/015、016 | 完整读取 | 用户后续修订：薪资、未来固定比例、首次恢复和原生大屏 [R13], [R14] |
| lib/countdown/summary/reminders、oracle、全部测试、xcstrings | 路径由AGENTS/源码引用确认；本轮未完整读取这些大文件 | 执行阶段必须使用的规范入口，不能声称已跑过全部差分 [R16], [R17], [R18], [R19], [R20], [R21] |

根LICENSE、第三方资源/节假日授权、Assets和PrivacyInfo亦须M0/M9继续核查，本轮未对其所有内容作法律/授权审计。

## 2. 已识别的历史冲突与裁决

### C-01：本地优先不等于完全无同步

README/旧计划中的“无同步”不能覆盖后续明确同意的私有CloudKit设置/收入同步。Android保留本地默认与用户主动授权边界；不能据旧README删同步，也不能据新同步需求无提示把全部数据放到公共后端。[R01], [R13]

### C-02：旧JS运行时设计已过时

旧计划012仍有CountdownRules.js相关语句；当前根AGENTS与native rules计划指定纯Swift原生规则及TS fixture约束。Android采用纯Kotlin，TS只作为开发/测试oracle，不把JSCore/WebView带回生产应用。[R01], [R15], [R22]

### C-03：固定月薪不是按出勤简单扣款

计划015先改自然月工作日分摊，计划016后续又确认自然日分摊、固定月薪不因少记工时/请假扣减。最终代码调用路径和测试优先，不能只引用较早计划的一句公式。[R13], [R14], [R10]

### C-04：人生收入调整不是逐年下降

后续确认是从起始年龄起一次性到设定比例并保持，仅作用于未来。历史不重算，空档不补收入。给实现者的反例：45岁/60%不是每年乘0.6，也不是到退休线性下降到60%。[R14]

### C-05：Watch计划名称含Plus不等于现行收费

根AGENTS当前明确Watch App和两种复杂功能免费。不要根据历史文件名 `017-apple-watch-plus.md` 或文案删除了“免费”推断重新收费。[R01]

### C-06：免费用户与过期用户并非完全同一数据采集策略

当前PlusEntitlement区分从未购买用户与曾持有后失效的用户；不能用“免费=无权限”一个分支误吞此区别。D-07决定Android是否继续保留，未批准前以基线为准。[R05]

### C-07：iOS评价预询问不直接照搬

原产品有评价预询问；Google Play In-App Review规范要求不在卡片前询问用户意见。Android保留恰当时机但使用平台允许的流程；手动评价入口直达商店。[R15], [A15]

### C-08：Expressive库的发布日期不等于稳定依赖组合

官方当前发布页区分Material3稳定与预发布。新工程需要明确锁定与技术探针，不把“1.4最新版稳定”和“Expressive APIs”硬拼；也不能声称封装进designsystem就不会带入传递依赖。[A01], [A20]

## 3. 已确认决策与剩余配置（1.1）

### 3.1 确认来源与解释边界

负责人在本对话中于 2026-09-21 回复 **“1-6 我觉得都 OK”**，同意上一轮表格中的六项建议。聊天序号 1/2/3/4/5/6 对应 **D-01/D-02/D-03/D-05/D-08/D-11**，不是 D-01～D-06。该确认不等于修改所有未讨论的产品细则，也不等于已经配置账户、商品、服务或通过验收。

| ID | 状态 | 当前决定 | 仍待配置/验证的事项 |
|---|---|---|---|
| D-01 | APPROVED（收费模式） | 月订阅、年订阅、终身一次性非消耗商品均保留 | 地区价格、销售范围、试用/优惠、生产商品标识；不得自行填金额或试用天数 |
| D-02 | APPROVED（提供商与首发范围） | Google Drive appDataFolder；默认关闭、主动授权；手机/平板首发包含 Android 多设备同步，不以纯本地版替代 | OAuth/Cloud 配置、真实双设备恢复及删除测试；权益失效后的同步门禁仍审计源行为，未额外批准改变 |
| D-03 | APPROVED | 首发不做 iOS/Android 自动同步，业务数据经 JSON 双向迁移，购买权益独立 | 迁移往返和权益隔离验证；任何日后自动互通或账号方案需要新决策 |
| D-04 | PROPOSED（本轮未覆盖） | 原建议 minSdk API26 / Android8；目标 API 在实现和发布阶段复核 | 支持矩阵与正式包签收；本轮不得代签 |
| D-05 | APPROVED（延后） | 手机/平板先发布；Wear OS 独立后续阶段，不阻塞首发 | T27 标 DEFERRED；FR-21/QA-137 保留为后续范围；启动时间与投入另行安排 |
| D-06 | PROPOSED（本轮未覆盖） | 原建议可选精准提醒授权，拒绝后降级，不默认使用高限制权限或全天常驻服务 | 平台探针与最终权限声明；本轮不得代签 |
| D-07 | PROPOSED（本轮未覆盖） | 原建议暂按源代码保留失效 Plus 停止新增工作观测的行为 | M0 核对调用链及产品签收；不能用 D-01 的收费模式确认冒充批准细则变化 |
| D-08 | APPROVED（验证服务方案） | 采用小型服务端购买验证，仅处理必要购买信息；不上传工资/记录，不新增 DoneAt 账号 | 云厂商、域名、预算、凭据、安全配置、部署及真实支付验收 |
| D-09 | PROPOSED（本轮未覆盖） | 原建议敏感页面保护，不全面阻止无薪资内容分享 | 隐私交互与最终截图策略签收 |
| D-10 | PROPOSED（本轮未覆盖） | 候选 applicationId 为 com.rainif.doneat；Android versionCode 独立增长 | 包名、营销版本、签名与首次上传前冻结；尚未创建 Play 应用 |
| D-11 | APPROVED_PROCESS_PENDING_FACTS | 按真实 Play Console 账户核对验证、测试与生产访问要求 | 是否已有、个人/组织、创建时间、生产访问均 UNKNOWN；不能从 Apple 身份推断 |

### 3.2 未知参数不等于方向未批准

| 配置 ID | 对应决定 | 需要落实 | 对开发的影响 |
|---|---|---|---|
| CFG-PRICE | D-01 | 价格/地区/试用/优惠/正式商品配置 | 不阻止领域层、支付接口和 Debug 测试；阻止正式销售与相应商店文案签收 |
| CFG-OAUTH | D-02 | Cloud/OAuth 项目、标识和签名关联、授权配置与测试账户 | 不阻止同步协议及单元测试；真实 Drive 联调与用户数据传输前需要落实 |
| CFG-BACKEND | D-08 | 部署环境/域名/预算、Publisher API 身份、签名密钥、RTDN 配置 | 不阻止服务实现及本地测试；真实验证、部署和运营签收前需要落实 |
| CFG-PLAY-ACCOUNT | D-11 | 实际开发者账户、类型、创建时间、验证与生产访问状态 | 不阻止本地开发；在 M0 登记并尽早核验，实际 Console/生产申请前必须有证据 |
| CFG-APP-IDENTITY | D-10 | 最终包名、营销版本、签名与 versionCode 方案 | 本地可用原候选；生产 OAuth/商品/签名/首次上传前冻结 |

没有有效的生产试用配置与资格依据时，不展示“免费试用 N 天”；这不是永久取消试用的产品决定。方案已批准后，不再反复询问是否采用 Drive、是否分开商店权益或是否需要验证服务；只处理真正缺失的配置和未覆盖决策。

### 3.3 实施边界与执行状态

正式首发覆盖 FR-01～FR-20；T00～T26 尚未开始，T27 为 DEFERRED。137 条应用测试仍全部 NOT_RUN，其中 QA-137 属后续 Wear 范围，不参与首发阻塞，也不是 PASS。报价/购买、创建真实账号、改价、部署生产或提交 Play 等外部操作仍需适当授权；本次回复只确认方向，不代表已经执行。

同步产品范围批准不替代最终用户的 Google OAuth 同意；验证服务批准不授权把业务记录上传服务端。保留根 AGENTS 的本地优先、无 DoneAt 账号及敏感数据隔离边界。

机器可读记录位于 `decisions.json`，每项包含决定、状态、受影响需求/任务和仍未知的配置。更新时须同时修改本节、PRD、技术说明、任务卡/JSON、AI 提示词和发布清单，不只在一个文件追加不同版本结论。

后续决策记录格式：

```text
ID / status: PROPOSED | APPROVED | APPROVED_PROCESS_PENDING_FACTS | REJECTED | REVISED
owner decision: <负责人明确回答，不由 AI 代签>
date:
approval scope: <只批准的内容>
remaining unknowns: <未知参数、配置、账户事实与待验收项>
affected FR / tasks:
privacy / store / source-parity implications:
required test changes:
```

## 4. 源码阅读地图

先读取根AGENTS与最新修订，再按所做任务缩小范围：

- 时间规则：`Shared/ScheduleRuleInput.swift`、`ShiftRuleCore.swift`、`ExtendedSchedule*.swift`，Native `ScheduleRules.swift`、`CountdownRules.swift`、`SummaryRules.swift`、`ReminderRules.swift`；共享TS与oracle。
- 数据：`RecordJSON.swift`、`RecordCoordinator.swift`、`RecordCommand.swift`、实体DTO、`DayRecordResolver.swift`、`DayOverrideProjection.swift`、`RecordsActions.swift`与导入/恢复测试。
- 专注：`FocusModels.swift`、`FocusPlanner.swift`、`FocusStore.swift`及拆分文件、`FocusLiveChain.swift`与画布/模板/会话测试。
- 权益：`PlusEntitlement.swift`、`PaywallView.swift`、`PlusSettingsView.swift`、具体Gate调用点与StoreKit测试；Android平台证据另对照Play官方文档。
- 恢复/同步：`FirstRunRecovery`/`RecoveryStore`相关、`RecordsCloudSync.swift`、`RecordsSyncPayload`与同步本地状态；核对实际定义路径，不凭名称猜字段。
- 原生页面：`Native/Views`与组件、`Native/DesignSystem`；翻译以 `Localizable.xcstrings` 为iOS权威来源，源widget扩展文案有独立打包边界。

不是所有符号都保证一个同名文件；执行AI应搜索定义和调用关系。上面的已验证路径与待查符号通过读取状态表区分。

## 5. 官方资料使用说明

参考源优先为Android Developers、Google Play Console Help、Google Developers、Material官方。技术决策需要查实际API和版本说明，不以博客或AI记忆补齐当前方法名。

页面里“推荐”“强制”“适用个人账户”“适用Wear”和“手机新应用”不是同一层约束。必须结合新应用/更新、设备类别、目标API、账号类型和发布日期解读。尤其目标API、Billing废弃时间、精确闹钟、16KB、Data safety和素材规则须在正式发布前再核对。

Material官方设计入口部分内容依赖JavaScript，本轮并未逐项读取其交互稿。文档中的具体页面布局/token是本包提出的Android设计方案，而不是宣称逐字照抄Material官方规范。

## 6. 完整参考目录

| 编号 | 资料与网址 | 用途/证据边界 |
|---|---|---|
| R01 | [仓库根 AGENTS：架构、隐私、规则与本地化契约](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md) | 固定提交源码，具体已读范围见本章第1节 |
| R02 | [iOS 快照与主倒计时显示规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R03 | [扩展排班数据模型](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R04 | [扩展排班解析器](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R05 | [Plus 权益与免费窗口](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R06 | [专注模型、模板与确定性会话 ID](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R07 | [RecordJSON：跨平台备份协议与合并](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R08 | [记录日解析优先级](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R09 | [记录编辑、导入导出及隐私确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordsActions.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R10 | [当前汇总与人生收入规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R11 | [统一页面路由](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/AppRouteDestination.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R12 | [同步设置、恢复与删除交互](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift) | 固定提交源码，具体已读范围见本章第1节 |
| R13 | [计划 015：收入、设置同步与用户确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md) | 固定提交源码，具体已读范围见本章第1节 |
| R14 | [计划 016：后续修订、首次恢复、固定月薪](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md) | 固定提交源码，具体已读范围见本章第1节 |
| R15 | [计划 012：周期总结与评价资格](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/012-ios-retention-and-cycle-notifications.md) | 固定提交源码，具体已读范围见本章第1节 |
| R16 | [共享 TypeScript 倒计时规范（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/countdown.ts) | 源码规范入口；完整内容由执行阶段继续读取 |
| R17 | [共享 TypeScript 汇总规范（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/summary.ts) | 源码规范入口；完整内容由执行阶段继续读取 |
| R18 | [共享提醒规范与测试入口（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/reminders.ts) | 源码规范入口；完整内容由执行阶段继续读取 |
| R19 | [现有 TypeScript 规则 oracle（实施阶段读取接口）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/scripts/ios-schedule-rule-oracle.mjs) | 源码规范入口；完整内容由执行阶段继续读取 |
| R20 | [现有 Swift 跨语言规则测试（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/AppTests/ScheduleRuleFixtureTests.swift) | 源码规范入口；完整内容由执行阶段继续读取 |
| R21 | [iOS 翻译目录（已核实路径，实施阶段转换完整文件）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Localizable.xcstrings) | 源码规范入口；完整内容由执行阶段继续读取 |
| R22 | [计划 019：原生规则与翻译迁移（实施阶段复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/019-ios-native-rules-and-localization.md) | 源码规范入口；完整内容由执行阶段继续读取 |
| R23 | [README：仅用作项目介绍，部分数据边界描述已落后](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/README_CN.md) | 固定提交源码，具体已读范围见本章第1节 |
| A01 | [Compose Material 3 发布说明](https://developer.android.com/jetpack/androidx/releases/compose-material3) | 官方平台资料；发布前重新核对适用范围与版本 |
| A02 | [Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3) | 官方平台资料；发布前重新核对适用范围与版本 |
| A03 | [Material 3 Expressive 设计入口（网页依赖 JavaScript）](https://m3.material.io/blog/building-with-m3-expressive) | Material设计入口；部分内容依赖JavaScript，具体API以Android发布文档为准 |
| A04 | [Google Play 目标 API 政策](https://support.google.com/googleplay/android-developer/answer/11926878) | 官方平台资料；发布前重新核对适用范围与版本 |
| A05 | [Play Billing 废弃周期](https://developer.android.com/google/play/billing/deprecation-faq) | 官方平台资料；发布前重新核对适用范围与版本 |
| A06 | [Play Billing 接入](https://developer.android.com/google/play/billing/integrate) | 官方平台资料；发布前重新核对适用范围与版本 |
| A07 | [Play Billing 安全及服务端验证](https://developer.android.com/google/play/billing/security) | 官方平台资料；发布前重新核对适用范围与版本 |
| A08 | [订阅生命周期](https://developer.android.com/google/play/billing/lifecycle/subscriptions) | 官方平台资料；发布前重新核对适用范围与版本 |
| A09 | [新个人开发者账户的测试要求](https://support.google.com/googleplay/android-developer/answer/14151465) | 官方平台资料；发布前重新核对适用范围与版本 |
| A10 | [AlarmManager 与精确闹钟权限](https://developer.android.com/develop/background-work/services/alarms) | 官方平台资料；发布前重新核对适用范围与版本 |
| A11 | [Live Update 通知及适用范围](https://developer.android.com/develop/ui/views/notifications/live-update) | 官方平台资料；发布前重新核对适用范围与版本 |
| A12 | [Glance 小组件更新与状态](https://developer.android.com/develop/ui/compose/glance/glance-app-widget) | 官方平台资料；发布前重新核对适用范围与版本 |
| A13 | [Google Drive 应用专用数据](https://developers.google.com/workspace/drive/api/guides/appdata) | 官方平台资料；发布前重新核对适用范围与版本 |
| A14 | [Google Play Data safety 申报](https://support.google.com/googleplay/android-developer/answer/10787469) | 官方平台资料；发布前重新核对适用范围与版本 |
| A15 | [Google Play 应用内评价](https://developer.android.com/guide/playcore/in-app-review) | 官方平台资料；发布前重新核对适用范围与版本 |
| A16 | [Android 数据备份默认行为](https://developer.android.com/identity/data/backup) | 官方平台资料；发布前重新核对适用范围与版本 |
| A17 | [16 KB 内存页兼容](https://developer.android.com/guide/practices/page-sizes) | 官方平台资料；发布前重新核对适用范围与版本 |
| A18 | [Compose 自适应导航](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation) | 官方平台资料；发布前重新核对适用范围与版本 |
| A19 | [AGP 当前发布与兼容矩阵](https://developer.android.com/build/releases/gradle-plugin) | 官方平台资料；发布前重新核对适用范围与版本 |
| A20 | [Compose BOM 与显式版本覆盖](https://developer.android.com/develop/ui/compose/bom) | 官方平台资料；发布前重新核对适用范围与版本 |
| A21 | [Compose 编译器插件](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler) | 官方平台资料；发布前重新核对适用范围与版本 |
| A22 | [AGP 9 内置 Kotlin](https://developer.android.com/build/migrate-to-built-in-kotlin) | 官方平台资料；发布前重新核对适用范围与版本 |
| A23 | [Play 创建与设置应用](https://support.google.com/googleplay/android-developer/answer/9859152) | 官方平台资料；发布前重新核对适用范围与版本 |
| A24 | [前台服务类型与适用范围](https://developer.android.com/develop/background-work/services/fgs/service-types) | 官方平台资料；发布前重新核对适用范围与版本 |
| A25 | [Android App Links 校验](https://developer.android.com/training/app-links/verify-applinks) | 官方平台资料；发布前重新核对适用范围与版本 |
| A26 | [Play 商店预览素材规范](https://support.google.com/googleplay/android-developer/answer/9866151) | 官方平台资料；发布前重新核对适用范围与版本 |
| A27 | [Android 通知运行时权限](https://developer.android.com/develop/ui/compose/notifications/notification-permission) | 官方平台资料；发布前重新核对适用范围与版本 |
| A28 | [Android Auto Backup 排除规则](https://developer.android.com/identity/data/autobackup) | 官方平台资料；发布前重新核对适用范围与版本 |
| A29 | [Google Play 账号删除要求](https://support.google.com/googleplay/android-developer/answer/13327111) | 官方平台资料；发布前重新核对适用范围与版本 |


---

## 本文参考网址

- **A01** · [Compose Material 3 发布说明](https://developer.android.com/jetpack/androidx/releases/compose-material3)
- **A15** · [Google Play 应用内评价](https://developer.android.com/guide/playcore/in-app-review)
- **A20** · [Compose BOM 与显式版本覆盖](https://developer.android.com/develop/ui/compose/bom)
- **R01** · [仓库根 AGENTS：架构、隐私、规则与本地化契约](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md)
- **R02** · [iOS 快照与主倒计时显示规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift)
- **R03** · [扩展排班数据模型](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift)
- **R04** · [扩展排班解析器](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift)
- **R05** · [Plus 权益与免费窗口](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift)
- **R06** · [专注模型、模板与确定性会话 ID](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift)
- **R07** · [RecordJSON：跨平台备份协议与合并](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift)
- **R08** · [记录日解析优先级](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift)
- **R09** · [记录编辑、导入导出及隐私确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordsActions.swift)
- **R10** · [当前汇总与人生收入规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift)
- **R11** · [统一页面路由](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/AppRouteDestination.swift)
- **R12** · [同步设置、恢复与删除交互](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift)
- **R13** · [计划 015：收入、设置同步与用户确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md)
- **R14** · [计划 016：后续修订、首次恢复、固定月薪](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md)
- **R15** · [计划 012：周期总结与评价资格](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/012-ios-retention-and-cycle-notifications.md)
- **R16** · [共享 TypeScript 倒计时规范（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/countdown.ts)
- **R17** · [共享 TypeScript 汇总规范（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/summary.ts)
- **R18** · [共享提醒规范与测试入口（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/reminders.ts)
- **R19** · [现有 TypeScript 规则 oracle（实施阶段读取接口）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/scripts/ios-schedule-rule-oracle.mjs)
- **R20** · [现有 Swift 跨语言规则测试（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/AppTests/ScheduleRuleFixtureTests.swift)
- **R21** · [iOS 翻译目录（已核实路径，实施阶段转换完整文件）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Localizable.xcstrings)
- **R22** · [计划 019：原生规则与翻译迁移（实施阶段复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/019-ios-native-rules-and-localization.md)
- **R23** · [README：仅用作项目介绍，部分数据边界描述已落后](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/README_CN.md)

[A01]: https://developer.android.com/jetpack/androidx/releases/compose-material3
[A15]: https://developer.android.com/guide/playcore/in-app-review
[A20]: https://developer.android.com/develop/ui/compose/bom
[R01]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md
[R02]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift
[R03]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift
[R04]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift
[R05]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift
[R06]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift
[R07]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift
[R08]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift
[R09]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordsActions.swift
[R10]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift
[R11]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/AppRouteDestination.swift
[R12]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift
[R13]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md
[R14]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md
[R15]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/012-ios-retention-and-cycle-notifications.md
[R16]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/countdown.ts
[R17]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/summary.ts
[R18]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/reminders.ts
[R19]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/scripts/ios-schedule-rule-oracle.mjs
[R20]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/AppTests/ScheduleRuleFixtureTests.swift
[R21]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Localizable.xcstrings
[R22]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/019-ios-native-rules-and-localization.md
[R23]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/README_CN.md


---

<!-- section: 06_PROMPT_FOR_IMPLEMENTING_AI.md -->

# 06 · 可直接交给执行 AI 的提示词

## A. 首次会话：先审计，不盲写

把下面这段与交接包一起交给有仓库读写及Android构建能力的AI。它应先建立真实基线，然后按任务卡推进，而不是凭聊天摘要重写整个应用。

```text
你要把 ififi2017/Off-Work-Countdown 的 iOS 原生版本完整移植为 Kotlin + Jetpack Compose + Material 3 Expressive Android 应用，并完成 Google Play 发布准备。

先读取本交接包：
00_START_HERE.md
01_PRD.md
02_TECHNICAL_GUIDE.md
03_AI_EXECUTION_PLAN.md
05_SOURCES_AND_DECISIONS.md
decisions.json
然后读取仓库根 AGENTS.md、当前进度（若已有）和固定源提交。

源基线：9252fdfdc66aab88b4acb7493684f11991fd773d。
拟新增目录：src-mobile/android/。
本轮优先执行 T00、T01、T02；依据真实源文件建立功能与字段级清单。
随后可执行没有阻塞决策的下一任务，每次仅处理一个明确可验收任务。

负责人已于2026-09-21回复“1-6 我觉得都 OK”，采用上一轮六项建议：
- D-01：保留月/年订阅与终身买断；金额、试用、正式商品配置仍未知。
- D-02：Google Drive appDataFolder同步纳入手机/平板首发；默认关闭，用户主动授权。
- D-03：首发只以JSON跨平台迁移业务数据；不做iOS/Android自动同步，购买权益独立。
- D-05：Wear OS后续独立阶段，T27=DEFERRED，不阻塞首发，不标已完成。
- D-08：采用只验证必要购买信息的小型服务，不上传工资/记录，不建DoneAt账号；基础设施与部署凭据待落实。
- D-11：按实际Play账户核验发布条件的流程已确认；是否已有、类型、创建时间、生产访问仍UNKNOWN。
这些是聊天六项映射，不是D-01至D-06全部获批。D-04/D-06/D-07/D-09/D-10维持原状态。不要重复询问已确认方向；只登记真正缺失的配置或未覆盖决策。不因价格/账号/云配置未知停止独立的本地开发，也不能据方案同意擅自执行生产部署、改价、扣费或发布。

必须遵守：
1. 不改、不删除用户已有未提交工作；不自动发布、上传、改价、创建账号/商品。
2. 当前代码+测试是业务依据，旧README/旧plans不能覆盖后续修订。
3. 不使用WebView/Capacitor/Flutter/React Native/运行时JS来替代Kotlin原生移植。
4. 不简化掉午休有效段、跨夜、加班原计划时薪、历史快照、记录层级、专注状态机或19语言。
5. 先建立TS/Swift→Kotlin差分fixtures；禁止用你的实现反向改expected来“通过”。
6. 备份是schema6，兼容1–6；数据库版本和fixture版本独立。读取完整DTO，不只按文档摘要挑字段。
7. 工资不进入Widget、通知、普通分享、链接、日志或分析；导出文件是单独用户确认的数据路径。
8. 不擅自增加DoneAt账号。执行已确认的Drive/跨平台/收费/服务端方向；Wear延后。严格区分已批准方向、未定价格与生产配置，不重新将全部D项标为待定。
9. Pending不是已购买；失败不是确认无权益；生产Billing与云同步不得用mock/stub冒充完成。
10. 所有实验性Expressive API集中封装，依赖版本由真实编译探针锁定；不要通过换回普通UI掩盖错误。
11. 每个任务都要交付实现、测试、实际运行命令与结果。不能只说“应该通过”。
12. 没有设备/服务/凭据时列NOT_RUN或BLOCKED；继续不受影响的任务，不能编造证据或清掉阻塞项。
13. 不以“iOS不方便”直接删功能；平台差异需要明确替代、用户影响与批准状态。
14. 更新docs/android/progress.md、feature-parity.md和任务状态，保留下一AI可接手的上下文。

本次输出：
- 实际完成的任务ID和改动文件；
- 已确认的源行为及新发现的缺项/冲突；
- 运行过的命令、真实测试执行数量、失败与产物路径；
- 仍需负责人决定的D项（只问真正阻塞当前任务的）；
- 下一可执行任务及必须读取的源文件。

不要先花大量时间制作漂亮的假页面，不要一次性生成没有行为测试的全工程。
完成定义以00和04为准，不以“能打开首页”为准。
```

## B. 后续会话：一张任务卡一次完成

```text
继续 DoneAt Android 移植。
先读00_START_HERE.md、仓库AGENTS、docs/android/progress.md、decisions.json及05已确认D项。
本轮任务：<Txx，填写真实下一任务；首发不选择已延后的T27>。
读取03中这张任务卡、相关02章节、07相关测试和其原始源码；不要重新发明接口。
只修改本任务需要的文件，并补充真实测试。
遇到现有失败先区分历史失败与本次回归，不删测试、不放宽精度。
结束时交付diff摘要、测试命令/结果/执行数、未运行项、剩余风险和下一任务。
不能宣布其他未执行任务完成，也不能自动开展未经批准的云/支付生产操作。
```

## C. 独立审查 AI：专门找错

```text
审查当前 DoneAt Android 变更，不要默认实现者说的“通过”可信。
按固定iOS基线、01需求、02技术约束、07测试和实际diff核对：
有效段/时区/加班、固定月薪口径、历史快照/手排冻结、JSON版本兼容、
专注确定性ID/恢复、权限降级、工资泄露、真实购买验证与离线缓存、
同步墓碑/删除fence/账号切换、19语言与RTL、Material3 Expressive实际使用。
检查Debug特权是否可能进Release，检查测试是否被删除、改expected或实际执行零条。
按decisions.json区分方向批准/配置未知/未覆盖决策；首发FR-01～FR-20，不能漏掉Drive或验证服务，也不能把Wear延后当首发失败或当Wear已实现。
按阻塞发布/重要/一般排列发现，给出具体文件位置、复现输入、预期与实际以及修复建议。
没有实际验证的环境明确列出；不要把静态审查当真机验收。
```

## D. 给负责人的最短使用方式

先把整个ZIP交给开发AI，让它从00和A段开始；之后每轮用B段指定下一张任务卡。不要让它只看合并文档的开头，也不要只给PRD而不提供技术约束和测试目录。关键规则/数据/支付/同步阶段完成后，使用C段独立审查再进入后续阶段。


---

<!-- section: 07_TEST_CATALOG.md -->

# 07 · 可执行验收案例目录

**状态：本文件是测试规范，所有案例均为 NOT_RUN。它不是已经通过的测试报告。**

1.1 只更新范围：QA-001～QA-136 属手机/平板首发，QA-137 属 D-05 已确认延后的 Wear 阶段。后者不阻塞首发、不删除、不标为已通过。方向批准不能改变任何测试的 NOT_RUN 状态。

用例中的确定性数字为本包独立设计；`ORACLE` 行必须先取得固定提交的真实 TS/Swift 输出，不能把本表描述当作已运行输出。完整移植还需补齐 M0 从所有源设置、调用点和源测试发现的子用例。

层级：JVM=纯规则单元测试；DB=数据库/事务/迁移；UI=Compose及无障碍；DEVICE=真机平台；SYNC=至少两端+真实云；PLAY=真实Play测试轨道/许可证测试；SEC=安全与隐私；PERF=Release性能；CI=构建流水线；WEAR=可选手表范围。未有权限/设备/服务时明确记为 NOT_RUN 或 BLOCKED。

每个执行结果记录 caseId、源SHA、Android提交、设备/OS/语言、输入文件哈希、实际输出、命令、测试数量及报告路径。对D项的批准修改必须注明决策ID和预期变更，不直接删掉不方便的案例。

## 基线与工程门禁

对应需求：FR-20。依据/相关资料：[R01], [A01], [A04], [A22]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-001 / CI | 全新检出固定SHA，工作区另有用户未提交文件 | 执行T00并创建Android分支 | 记录SHA和未提交文件；不reset、不覆盖、不以main最新内容混入固定基线。 |
| QA-002 / CI | 空Android工程，锁定所有依赖版本 | 构建Debug与启用R8的Release | 两种构建实际成功；报告实际版本、JDK和依赖树，无动态+版本。 |
| QA-003 / UI | 需要采用的Expressive主题、按钮及运动方案探针 | 编译并在目标设备交互 | 使用真实已存在API；不因实验API编译失败私自换回普通Material样式。 |
| QA-004 / CI | AGP9内置Kotlin的候选工程 | 检查Android和纯JVM模块插件 | Android不重复应用冲突的旧kotlin-android插件；domain独立无android.*依赖。 |
| QA-005 / CI | 原仓库TS/Swift fixtures与新增Android fixtures | 改规则但不更新生成文件，执行检查 | 检测源哈希/生成差异并失败；实际测试数量大于零，不接受空报告。 |
| QA-006 / SEC | Release APK/AAB与合并manifest | 扫描Debug gate、token、私钥、权限和测试地址 | 无调试解锁入口、测试支付适配器或密钥；无不相干敏感权限。 |
| QA-007 / CI | Android相关改动以及未修改的Web/Desktop/iOS | 执行原仓库适用检查与Android检查 | 报告真实回归结果；不能以Android成功替代其他目标保护。 |

## 有效时间段、跨日与时区

对应需求：FR-02, FR-04, FR-05。依据/相关资料：[R01], [R02], [R10]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-008 / JVM | 09–12、13–18；原计划8h；日薪80；现在08:00 | evaluateShift | elapsed=0、remaining=8h，主时间为距开始1h；收入0，非已工作。 |
| QA-009 / JVM | 同上；现在09:00 | evaluateShift | 工作开始边界正确；remaining=8h；无负数/NaN。 |
| QA-010 / JVM | 同上；现在11:00 | evaluateShift | 已工作2h，剩余6h，进度25%，收入20。 |
| QA-011 / JVM | 同上；现在12:00与12:30 | 分别evaluateShift | 进入休息；12:30 elapsed=3h、remaining=5h、hero=30min、收入30。 |
| QA-012 / JVM | 同上；现在13:00 | evaluateShift | 休息结束；hero切为有效剩余5h，不残留0秒休息态。 |
| QA-013 / JVM | 同上；现在18:00及18:05 | evaluateShift | 完成态；remaining=0；不自动把晚到的5分钟算加班。 |
| QA-014 / JVM | 同上延长末段到20:00；现在19:00 | evaluateShift | 当前总长10h、planned8h、elapsed9h、remaining1h、进度90%、payRatio1.125、收入90。 |
| QA-015 / JVM | 工作段09–10、11–12、14–16，now10:30 | 计算有效累计与当前间隙 | elapsed1h、remaining3h；休息hero直到11:00；不累计多个空隙。 |
| QA-016 / JVM | 22:00–次日06:00；now次日01:00；无休息 | 计算并查询日记录归属 | 已工作3h、剩余5h；班次归起始日，不在午夜生成第二份班次。 |
| QA-017 / JVM | 09:00–09:00合法班型，无休息 | 展开一日班次 | 依源定义终点在次日而非0h；仍执行源有效段校验。 |
| QA-018 / JVM | 空段、0长度段、倒序段、重叠段或非法时间 | 执行校验及恢复读取 | 按冻结源规范归一化或拒绝；绝不出现负长、重复累计、NaN或静默默认白班。 |
| QA-019 / JVM | now精确等于每个segment起止毫秒 | 逐边界计算 | 使用半开区间语义；每个瞬间只计入一次；显示舍入与源oracle一致。 |
| QA-020 / JVM | 周期锚点、跨年周、闰年2028-02-29 | 按民用日展开 | 日期连续且身份唯一；不是每次加86400000毫秒。 |
| QA-021 / ORACLE | America/Los_Angeles夏令时跳过/重复时刻，含夜班 | TS/Swift与Kotlin同输入比较 | 与源缺失/重叠时刻选择一致；未生成源输出前不得猜测Java默认行为。 |
| QA-022 / JVM | 历史记录时区Asia/Shanghai，设备改America/Los_Angeles | 重开记录及免费窗口 | 历史dayKey和原时区语义不变；设备时区不静默覆盖记录时区。 |
| QA-023 / JVM | 同一前台时钟暂停tick90秒，然后恢复 | 重新evaluate而非循环补tick | 立即显示当前正确状态；不将缓存remaining减1作为长期事实。 |
| QA-024 / DEVICE | 运行班次中修改系统时间/时区再重启 | 重新计算和重建调度 | 执行已冻结的时钟变更语义；不重复完成/提醒；UI与历史分类一致。 |
| QA-025 / ORACLE | 关闭自动模式、空工作日、无法解析下一班次 | 比较源规则输出 | 准确区分手动可开始、休息与未排班；无下一班次不构造虚假的明天。 |

## 排班、历史冻结与输入约束

对应需求：FR-02, FR-03, FR-04, FR-07。依据/相关资料：[R03], [R04], [R08], [R09]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-026 / JVM | 班型名为空、仅空白、40与41个字符 | 保存班型 | 与源trim/长度单位一致；临界Unicode组合字符另做对照，不直接等同UTF-16长度。 |
| QA-027 / JVM | 周期长度0、1、366、367；未知新preset | 读取/保存规则 | 合法长度1–366；已定义的未知preset回退custom；不可保存空周期。 |
| QA-028 / JVM | 三天周期锚点2026-09-21，查看锚点前一天 | 解析周期位置 | 使用floorMod得到最后一项，不以负数数组索引崩溃。 |
| QA-029 / JVM | 周期为工作，某日手动设休息 | 解析该日再撤销手排 | 手排覆盖；撤销恢复下层规则，不把撤销保存为永久休息。 |
| QA-030 / JVM | 手排引用尚未下载到的班型ID | 先到RosterDay后到类型 | 前者安全显示未分配；后者恢复正确班型，不改写原ID。 |
| QA-031 / JVM | 过去一天存assignedShiftType冻结值；未来一天只指类型ID | 修改该班型名称/起止 | 过去保持冻结值；未来按源实时类型规则更新。 |
| QA-032 / JVM | 历史使用扩展排班；当前关闭扩展排班 | 读取历史图表与日详情 | 仍以历史extendedContent/冻结覆盖解析，不回退当前固定班而改变过去。 |
| QA-033 / ORACLE | 无规则月继承前月，含31→30→28/29日和手工月份 | 与Swift测试逐组合比较 | 严格匹配源继承/人工空档规则，不凭简单日数复制补齐不存在日期。 |
| QA-034 / ORACLE | holidayRegion=nil、空串、合法地区及clearedFromDayKey | 组合解析跨清空边界日期 | 保留nil与空串语义；清空后不会重启又自动填回；手排/节假日组合依源测试。 |
| QA-035 / JVM | 已归档班型被历史引用 | 从新建选择器与历史分别读取 | 不能新选的归档类型仍能解释旧记录；不级联删除历史。 |
| QA-036 / JVM | 今天正在工作；修改常规班次 | 分别选应用今天/从下一次开始 | 按源允许项固定当前快照/未来规则；不回写过去或无理由改当前专注终点。 |
| QA-037 / JVM | 同一天有效override、user exception、bundled exception和snapshot并存 | 解析，再逐层cleared | override优先；清除后正确回退；观测不参与计划优先链。 |
| QA-038 / JVM | 多个同effectiveFrom快照，乱序查询返回 | 解析并反转数据库返回顺序 | 按editCount/tieBreaker/ID确定同一胜者，而非最后一行。 |
| QA-039 / JVM | 历史09–12、13–18，将上下界改10–17 | 保存自定义工时 | 得到10–12、13–17；保留休息洞，不生成10–17连续7h。 |
| QA-040 / DB | 一天编辑需同时写override与exception，中途故障 | 故障注入并重开 | 全部提交或全部回滚；草稿保留，不显示半成功。 |

## 记录、收入与人生

对应需求：FR-05, FR-06, FR-07, FR-08。依据/相关资料：[R05], [R08], [R10], [R13], [R14]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-041 / JVM | 金额空、0、负数、极大值、NaN/Infinity及逗号小数地区 | 校验输入和反序列化 | 空与0按源区分；非法值明确拒绝，不截断为另一个合法工资。 |
| QA-042 / ORACLE | 固定月薪完整月，分别少记录工时、请假、正常出勤 | 生成记录月汇总 | 依当前后续规则月基数不因请假扣减；年终奖份额与源一致。 |
| QA-043 / ORACLE | 一周横跨两个不同天数月份；月薪不变 | 生成周已过/剩余汇总 | 分别按所在月自然日分摊；不使用统一21.75或单月工作日作分母。 |
| QA-044 / ORACLE | 日薪模式与固定月薪相同日历输入 | 比较收入调用路径 | 日薪仍按源工作日/进度规则；不能套用固定月薪自然日口径。 |
| QA-045 / JVM | 同一天已有实际，未来仍有计划 | 计算实际+预计 | 对同一语义时间区间无重复计算；明细来源与汇总可对账。 |
| QA-046 / JVM | 记录时区今天2026-09-21 | 免费用户分别查看09-15/09-14/09-22 | 09-15至09-21是七个自然日窗口；09-14和未来不因数组条数而进入。 |
| QA-047 / JVM | 从未购买与已订阅后到期两类用户 | 产生新工作观测 | 默认基线前者继续后者停止；D-07变更必须连同预期显式修订。 |
| QA-048 / SEC | 免费/过期用户打开受限图表/人生/专注 | 检查UiState、Semantics和分享 | 受限真实值不传给隐藏布局；不能从可访问树、剪贴板或日志获取。 |
| QA-049 / UI | 周/月相同结构图表、已选日、滚动位置 | 切换尺度/返回/旋转 | 保持合理选择与位置；数字不重复跳动；宽窗两栏滚动互不抢占。 |
| QA-050 / JVM | 两段职业之间有一年空档 | 人生收入汇总 | 空档零收入；不延伸上一个工资自动填满。 |
| QA-051 / JVM | 职业区间重叠或终点早于起点 | 保存资料 | 清晰拒绝/展示校验；不能双算工资或静默抹除原经历。 |
| QA-052 / ORACLE | 未来收入从45岁起60%，退休60岁 | 计算跨45岁前后预测 | 45岁后一次性变60%并保持；不是逐年乘0.6，也不是线性递减。 |
| QA-053 / ORACLE | 收入调整起始年龄已过去，存在历史收入 | 重新估算 | 历史不变；只从当前预测起点应用比例。 |
| QA-054 / JVM | 职业跨闰年及不同长度的部分月 | 按月/年薪计算 | 部分月按本月实际日数；不统一按30天；终点排他性依源fixture。 |
| QA-055 / UI | 选择原职业阶段，时间推进或刷新导致展示切段 | 重新渲染人生画布 | 选中身份基于稳定阶段ID，不跳到另一段/数组位置。 |
| QA-056 / PERF | 15000日人生和十年真实/预计记录 | 快速切换日期再离开页面 | 后台计算可取消；主线程不遍历全档案；旧结果不覆盖较新的选择。 |

## 专注任务与会话恢复

对应需求：FR-09。依据/相关资料：[R06], [R11]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-057 / JVM | 全新专注设置 | 读取默认并输入超范围数值 | 默认25/5/15/4；规范化到10–60/1–15/5–30/2–6。 |
| QA-058 / JVM | 专注已启动并保存plannedEnd | 修改专注时长 | 当前plannedEnd不变，下一会话使用新设置。 |
| QA-059 / JVM | 固定任务UUID及start/end毫秒 | 生成自动会话ID | 匹配acceptance_examples的SHA256/位设置结果；禁止MD5或SHA1替代。 |
| QA-060 / DB | 前台和通知动作同时启动同一块，随后重复回调 | 并发执行两次命令 | 一个逻辑会话和一次状态转移；重复触发返回已处理结果。 |
| QA-061 / DEVICE | 专注进行中进程被回收；20分钟后重开 | 恢复本地会话 | 用持久时间重建，不从满时长重新开始；历史写入幂等。 |
| QA-062 / JVM | 专注到期后到午休/下班边界 | 重建计划和通知 | 遵循源停止/恢复策略；不越过不可工作边界虚构专注成果。 |
| QA-063 / JVM | 模板任务轮数2、3、1，仅剩4个工作块 | 应用模板 | 只放完整首任务2轮；不放第二任务部分，不跳过第二任务去塞第三任务。 |
| QA-064 / JVM | 同模板分别应用长班与短班 | 检查模板本体 | 模板轮数/任务不被短班裁剪永久覆盖。 |
| QA-065 / UI | 放入下一块操作触发Plus购买 | 成功后回到原操作 | 保留草稿及原落位，至多执行一次；取消购买仍可继续编辑草稿。 |
| QA-066 / UI | 拖动任务到非法/冲突位置后取消 | 查看原任务与计划 | 原任务位置保留；明确冲突原因；TalkBack可通过非拖动动作完成同类操作。 |
| QA-067 / SYNC | 两台设备自动启动相同时间块，离线后重连 | 合并会话 | 相同确定性ID合一；真正竞争会话按源规则保留supersededBySync历史。 |
| QA-068 / JVM | 停止、自然完成、边界停止与废弃四种操作 | 查询会话记录 | 各自保留对应结束原因；不删除或统统改为completed。 |

## 数据持久化、导出与跨端兼容

对应需求：FR-01, FR-14, FR-17。依据/相关资料：[R07], [R09], [R14]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-069 / DB | iOS导出的schema1、2、3、4、5、6合法备份各一份 | 逐个导入 | 全部支持既定旧版本默认/迁移；不得仅改版本号假装兼容。 |
| QA-070 / DB | iOS v6包含12类实体、nil/空串、冻结手排、专注模板 | Android导入→导出→iOS重新导入 | 业务字段和身份语义无丢失；差分只含明确允许的导出时间/排序。 |
| QA-071 / DB | schema7、错误根类型、截断JSON、非法时区/日期 | 预览导入 | 整文档不支持/格式错误与行级拒绝按源策略区分；活跃库未被覆盖。 |
| QA-072 / SEC | 超大数组、极深嵌套、重复身份、巨大金额/时间 | 解析不可信导入文件 | 有限制与明确错误，不无限内存、不溢出、不绕过类型校验。 |
| QA-073 / DB | 本地和导入文件同ID不同内容 | 默认导入预览并取消 | 展示冲突；默认不无提示覆盖本地；取消后状态不变。 |
| QA-074 / DB | 本地有ErasedID墓碑，导入旧备份含同ID | 默认skipErased | 记录不复活，报告跳过数量；不能把墓碑仅当普通垃圾清理。 |
| QA-075 / DB | 明确restoreErased，涉及阶段/快照/任务依赖 | 执行恢复 | UUID身份依源规则重新分配并重映射引用；自然键保留合法语义。 |
| QA-076 / DB | 相同实体两份editCount相同、tieBreaker不同；系统时钟反向 | 双向合并 | 结果与源固定比较一致；不根据editedAt或Drive modifiedTime选择。 |
| QA-077 / DB | 导入合法大档案，在提交前后分别模拟崩溃/低空间 | 重开应用 | 保留旧完整状态或新完整状态；没有半份导入与伪保存成功。 |
| QA-078 / SEC | 用户导出含收入档案与排除人生档案两种模式 | 检查输出JSON和权限 | 仅实际v6导出字段；不带Play权益、OAuth token、本机权限或内部sync state。 |
| QA-079 / DEVICE | 通过SAF选云文档/只读URI/取消保存 | 导入和导出 | 不用全盘文件权限；URI错误清晰，可取消；不把文件名当已成功写入。 |
| QA-080 / DB | 每个曾发布的Room schema升级到当前版本 | 运行迁移及重开读取 | 实体/编辑戳/关系/墓碑保留；禁止fallbackToDestructiveMigration用于正式用户。 |
| QA-081 / DEVICE | 新用户无有效配置，欢迎草稿中途重启 | 继续欢迎后完成 | 草稿可恢复；确认前不生成dirty业务设置或工作观测。 |
| QA-082 / DEVICE | 用户导入自己的数据但无Plus或已过期 | 执行恢复/导出/删除 | 数据控制不要求重新付费；恢复不会伪造Plus或获得付费编辑权限。 |

## Android 调度、通知与小组件

对应需求：FR-10, FR-11, FR-12。依据/相关资料：[R01], [R15], [A10], [A11], [A12]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-083 / DEVICE | Android13+拒绝通知；基础班次正常 | 完成欢迎并倒计时 | 本地功能可用；状态如实提示未授权，不重复强迫请求。 |
| QA-084 / DEVICE | 精确提醒权限未授予/被拒绝 | 启用普通提醒 | 有明确延迟降级；不调用无权限API致崩溃，不改用违规USE_EXACT_ALARM。 |
| QA-085 / DEVICE | 已授权并排好未来提醒；运行中撤销精确权限 | 返回应用并检查系统任务 | 重新检查能力并重建合法任务；不把旧已取消闹钟当仍有效。 |
| QA-086 / DEVICE | 班次编辑/时区改变/重启/应用更新 | 重建未来提醒 | 旧计划失效；新提醒去重；不在重启后补发已错过的一串通知。 |
| QA-087 / ORACLE | 普通进度关闭，Plus周期总结开启；后一天可靠休息 | 生成提醒列表 | 仍有周期总结；同结束点普通兜底不重复响。 |
| QA-088 / ORACLE | 后一天排班解析失败或节假日覆盖不足 | 计算周期末 | 不把未知当休息，不发送虚构周期总结。 |
| QA-089 / DEVICE | 同一通知按钮连续点击；主界面也点相同操作 | 执行命令 | 持久去重且及时更新通知；不重复结束/新增会话。 |
| QA-090 / DEVICE | 工作日跨午休，显示持续通知计时 | 进入休息并回到工作 | 不把全天end-now称为有效剩余；阶段/计时含义一致，受限时显示正确结束钟点。 |
| QA-091 / DEVICE | 普通工作计时不符合Live Update展示资格 | 检查前台/锁屏 | 普通通知回退可用；不宣称每台机都有灵动岛等效UI。 |
| QA-092 / DEVICE | 桌面小组件缩放为紧凑/中/大，切主题与语言 | 查看工作/休息/未排/过期 | 各布局内容准确可触达；无工资字段，过期不伪装实时。 |
| QA-093 / DEVICE | 进程已死或设备Doze，桌面停留30分钟 | 观察小组件和耗电/系统任务 | 不每秒调Worker；系统允许时刷新，不能承诺精确边界刷新；计时增强先过设备探针。 |
| QA-094 / SEC | 恶意外部Intent调用内部receiver/service或错误PendingIntent | 尝试执行修改命令 | 非公开组件不可外部调用；公开动作校验数据，无工资URI、可变Intent注入。 |

## 购买、恢复与服务端证据

对应需求：FR-16, FR-20。依据/相关资料：[R05], [A05], [A06], [A07], [A08]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-095 / PLAY | 实际可购月/年/终身商品，不同币种与offer资格 | 加载付费页 | 价格/周期/试用来自ProductDetails；不硬编码或以月价乘12伪年价。 |
| QA-096 / PLAY | 商品加载失败/无GMS/用户无可购offer | 打开付费页 | 基础应用不阻断；失败与无资格区分，无必失败的试用按钮。 |
| QA-097 / PLAY | PENDING购买，超过24小时仍待付款 | 刷新与重装恢复 | 不授予Plus，也不套Apple AskToBuy24小时自动清除规则。 |
| QA-098 / PLAY | 月订阅成功且验证正常，重复回调 | 确认权益并处理pending action | 服务端只验证/确认一次逻辑购买；原操作至多一次；真实价格与商品可追溯。 |
| QA-099 / SEC | 伪造isPlus、本地purchaseState、包名/商品/签名或导入权益 | 提交verify和本地恢复 | 平台证据、allowlist和签名校验生效；不能靠本地布尔解锁。 |
| QA-100 / PLAY | 用户取消自动续费但订阅未来才到期 | 恢复购买和重启 | 权益保持到真实截止；不因cancel标记立即撤销。 |
| QA-101 / PLAY | 平台宽限、account hold、暂停、恢复、到期 | 测试时钟与Publisher API状态 | 按规范状态生效；不按purchaseTime+30天推断。 |
| QA-102 / PLAY | 网络失败或一个未验证条目，已有合法未到期缓存 | 刷新 | 保留合法缓存及期限；失败不等于完整确认无权益。 |
| QA-103 / PLAY | 可靠完整查询确认为无权益/已退款撤销 | 应用刷新 | 回收对应权利但保留用户数据与导出；不被旧cache永久覆盖。 |
| QA-104 / PLAY | 已持有终身，当前网络断开 | 进入原付费功能 | 遵守已验证终身缓存策略；不会因网络问题当免费；在线撤销证据可更新。 |
| QA-105 / PLAY | 服务器验证成功但ack失败，后续重试 | 重发任务与回调 | 持久重试并告警；初次购买在规定窗口确认，终身绝不consume。 |
| QA-106 / PLAY | 升级/替换订阅，RTDN乱序/重复，linked token仍缓存 | 刷新 canonical状态 | 不出现旧新双份权益；RTDN不是唯一真实性依据。 |
| QA-107 / PLAY | 已订阅用户购买终身 | 完成后查看管理入口 | 不谎称原订阅自动取消；明确管理路径，避免重复付费。 |
| QA-108 / DEVICE | 付款页面旋转/退后台/进程恢复并再点购买 | 检查BillingClient及请求次数 | 无多个客户端重复流程；购买/恢复互斥，UI重组不重复launch。 |

## 同步、删除及新设备恢复

对应需求：FR-01, FR-09, FR-15。依据/相关资料：[R07], [R12], [R14], [A13]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-109 / SYNC | 用户未点云功能；全新安装 | 完成本地使用并检查网络 | 不请求Google授权，不上传工资/默认设置；只允许明确记录的其他网络功能。 |
| QA-110 / SYNC | 云端已有完整档案，旧设备关闭；新安装 | 授权并首次恢复 | 完整分页下载→预览→原子应用；不依赖旧设备上线发送当前快照。 |
| QA-111 / SYNC | 首次查询超时/401/配额错误 | 进入恢复选择 | 显示未知/失败，不作为空云创建并上传欢迎默认值。 |
| QA-112 / SYNC | 设备A改日期甲，设备B离线改日期乙 | 恢复联网并双向同步 | 两天修改都保留；不是最后整文件上传者抹除另一台。 |
| QA-113 / SYNC | 同ID并发编辑、时钟错误且网络乱序 | 重复合并批次 | 按编辑戳稳定收敛；不看墙钟/文件modifiedTime。 |
| QA-114 / SYNC | 一台删除，另一台持旧行，之后重连 | 同步墓碑 | 旧行不复活；合法显式重新创建使用更高版本规则。 |
| QA-115 / SYNC | 上传成功但本地未确认即崩溃，云上同名文件多份 | 恢复重试并拉取 | 按batchId/hash去重，不以文件名唯一性假设创建重复业务。 |
| QA-116 / SYNC | 用户删除云端，老设备离线持旧generation | 老设备晚到上传旧批次 | fence阻止旧数据复活；有未同步本地内容先审阅/导出。 |
| QA-117 / SYNC | 两台设备并发reset | 重新读取所有fence/batch | 固定有序规则选唯一新generation；输的一方不复活旧批次。 |
| QA-118 / SYNC | 用户在Drive外部删整个应用数据空间，旧机还配对 | 自动同步触发 | 暂停并请求选择；不能自动新建云空间把已删工资重新上传。 |
| QA-119 / SYNC | Google账号A已同步，切到B | 打开同步设置 | 旧本地数据不自动流入B；明确解除配对/导出/选择状态。 |
| QA-120 / SYNC | 依次暂停同步、删除云副本、移除此设备数据 | 检查三个作用范围 | 行为不同且明确；暂停不删数据，本机移除不误删云；危险操作互斥。 |
| QA-121 / SYNC | 页数多、批次大、未知格式或哈希错误、恢复中断 | 拉取全部后合并 | 无静默漏页；错误候选不污染本地；重新执行可恢复且幂等。 |
| QA-122 / SYNC | 数据同步收到主题/语言/薪资，也收到伪权限/权益字段 | 映射业务和本机状态 | 只接受协议内业务字段；通知权限、生物识别授权、Play权益不跨设备复制。 |

## 隐私、UI、语言与 Play 发布

对应需求：FR-05, FR-13, FR-17, FR-18, FR-19, FR-20, FR-21。依据/相关资料：[R01], [R09], [R21], [A09], [A14], [A15], [A16], [A17], [A18]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-123 / SEC | 隐藏工资，生物识别取消/失败或无设备锁 | 请求显示/导出敏感内容 | 失败/取消不泄露；无设备锁有明确降级说明，不假装验证成功。 |
| QA-124 / SEC | 页面含工资、任务和职业信息，切后台/最近任务 | 检查截图/任务缩略图/TalkBack | 执行D-09批准策略；普通安全卡片分享不通过解除整个窗口保护实现。 |
| QA-125 / SEC | 生成普通分享卡和班次链接 | 检查图片、元数据、URL、日志 | 无工资/职业/身份/token；不截图整个屏幕。 |
| QA-126 / DEVICE | 合法旧分享链接、恶意超长/错误参数、外部App启动 | 预览并应用 | 严格校验后需用户确认；不无提示覆盖；App Links只匹配批准域名/路径。 |
| QA-127 / SEC | 系统cloud backup和device transfer分别启用 | 备份/恢复应用数据 | 业务库/秘密/购买缓存按显式规则排除；不能仅凭无上传代码声称数据未出设备。 |
| QA-128 / UI | 19locale，包含阿拉伯语、长德语、简繁中及占位符 | 自动资源检查及重点页视觉操作 | 无遗漏key/坏复数/格式崩溃；RTL可用，香港台湾资源不误丢。 |
| QA-129 / UI | 系统字体200%、小窗320dp、键盘弹出 | 编辑班次/工资/任务/付费页 | 信息可读且所有操作可滚动到；不缩文字或挡保存按钮。 |
| QA-130 / UI | 窄窗→平板分屏→折叠展开；各主入口不同导航栈 | 连续resize、返回、旋转 | 选择/草稿/栈不丢；无按设备名创建另一套规则；宽窗内容合理分栏。 |
| QA-131 / UI | TalkBack开启、仅键盘/方向导航、减少动画 | 使用日历、图表和专注拖放替代 | 语义角色/状态完整；不每秒播倒计时；所有功能无需拖动也能完成。 |
| QA-132 / DEVICE | 已完成计时后的合适启动与手动评价按钮 | 触发评价流程 | 无评分/满意度预询问；系统不弹不循环；手动按钮直达Play页。 |
| QA-133 / PLAY | 真实Play账号类型与创建日期已确认 | 创建测试/申请生产访问 | 仅适用账号执行12人连续14日要求；完成后还需生产访问审核，不承诺自动通过。 |
| QA-134 / PLAY | Release AAB含全部依赖与可能的native .so | 检查target、签名、Billing和16KB兼容 | 以实际包为准；API/库符合发布当日要求；native依赖不能因主语言Kotlin被忽略。 |
| QA-135 / PLAY | 当前实现含Drive授权和购买验证服务 | 逐项填写Data safety/隐私/删除入口 | 按真实离设备流向判断；不照搬iOS Data Not Collected，不谎称自建后端无数据。 |
| QA-136 / PLAY | Android真实手机/平板截图和各语言商店文案 | 检查商店素材及审核操作说明 | 不放iOS截图/假功能；审核员能访问合法测试流程，不提供工资真数据或暗门。 |
| QA-137 / WEAR | D-05已确认延后；仅后续Wear阶段获准启动并具备手机/手表环境后执行，手机离线/关机 | Watch端解析缓存排班并刷新复杂功能 | 复用同一无薪资规则；离线可延续排班；具体版本/发布独立验证。当前保留NOT_RUN并从首发阻塞集合排除，不删除该用例或标PASS。 |

## 结果与阻塞登记

所有必选案例通过，仍不自动代表完整产品通过：还需要源功能盘点没有遗漏、规则fixtures没有删减、生产权限/云/支付验收证据齐备。Wear只有负责人明确排除后才可不纳入首发分母。

```text
case: QA-xxx
status: PASS | FAIL | NOT_RUN | BLOCKED
sourceCommit:
androidCommit:
build / device / OS / locale:
input / fixture hash:
command and actual test count:
expected vs actual:
evidence path:
related decision / approved deviation:
owner / reviewedAt:
```

本目录共 **137** 条独立案例；机器可读版本见 `test-catalog.json`。数字为计划数量，不是已执行数量。


---

## 本文参考网址

- **A01** · [Compose Material 3 发布说明](https://developer.android.com/jetpack/androidx/releases/compose-material3)
- **A04** · [Google Play 目标 API 政策](https://support.google.com/googleplay/android-developer/answer/11926878)
- **A05** · [Play Billing 废弃周期](https://developer.android.com/google/play/billing/deprecation-faq)
- **A06** · [Play Billing 接入](https://developer.android.com/google/play/billing/integrate)
- **A07** · [Play Billing 安全及服务端验证](https://developer.android.com/google/play/billing/security)
- **A08** · [订阅生命周期](https://developer.android.com/google/play/billing/lifecycle/subscriptions)
- **A09** · [新个人开发者账户的测试要求](https://support.google.com/googleplay/android-developer/answer/14151465)
- **A10** · [AlarmManager 与精确闹钟权限](https://developer.android.com/develop/background-work/services/alarms)
- **A11** · [Live Update 通知及适用范围](https://developer.android.com/develop/ui/views/notifications/live-update)
- **A12** · [Glance 小组件更新与状态](https://developer.android.com/develop/ui/compose/glance/glance-app-widget)
- **A13** · [Google Drive 应用专用数据](https://developers.google.com/workspace/drive/api/guides/appdata)
- **A14** · [Google Play Data safety 申报](https://support.google.com/googleplay/android-developer/answer/10787469)
- **A15** · [Google Play 应用内评价](https://developer.android.com/guide/playcore/in-app-review)
- **A16** · [Android 数据备份默认行为](https://developer.android.com/identity/data/backup)
- **A17** · [16 KB 内存页兼容](https://developer.android.com/guide/practices/page-sizes)
- **A18** · [Compose 自适应导航](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation)
- **A22** · [AGP 9 内置 Kotlin](https://developer.android.com/build/migrate-to-built-in-kotlin)
- **R01** · [仓库根 AGENTS：架构、隐私、规则与本地化契约](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md)
- **R02** · [iOS 快照与主倒计时显示规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift)
- **R03** · [扩展排班数据模型](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift)
- **R04** · [扩展排班解析器](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift)
- **R05** · [Plus 权益与免费窗口](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift)
- **R06** · [专注模型、模板与确定性会话 ID](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift)
- **R07** · [RecordJSON：跨平台备份协议与合并](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift)
- **R08** · [记录日解析优先级](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift)
- **R09** · [记录编辑、导入导出及隐私确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordsActions.swift)
- **R10** · [当前汇总与人生收入规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift)
- **R11** · [统一页面路由](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/AppRouteDestination.swift)
- **R12** · [同步设置、恢复与删除交互](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift)
- **R13** · [计划 015：收入、设置同步与用户确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md)
- **R14** · [计划 016：后续修订、首次恢复、固定月薪](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md)
- **R15** · [计划 012：周期总结与评价资格](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/012-ios-retention-and-cycle-notifications.md)
- **R21** · [iOS 翻译目录（已核实路径，实施阶段转换完整文件）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Localizable.xcstrings)

[A01]: https://developer.android.com/jetpack/androidx/releases/compose-material3
[A04]: https://support.google.com/googleplay/android-developer/answer/11926878
[A05]: https://developer.android.com/google/play/billing/deprecation-faq
[A06]: https://developer.android.com/google/play/billing/integrate
[A07]: https://developer.android.com/google/play/billing/security
[A08]: https://developer.android.com/google/play/billing/lifecycle/subscriptions
[A09]: https://support.google.com/googleplay/android-developer/answer/14151465
[A10]: https://developer.android.com/develop/background-work/services/alarms
[A11]: https://developer.android.com/develop/ui/views/notifications/live-update
[A12]: https://developer.android.com/develop/ui/compose/glance/glance-app-widget
[A13]: https://developers.google.com/workspace/drive/api/guides/appdata
[A14]: https://support.google.com/googleplay/android-developer/answer/10787469
[A15]: https://developer.android.com/guide/playcore/in-app-review
[A16]: https://developer.android.com/identity/data/backup
[A17]: https://developer.android.com/guide/practices/page-sizes
[A18]: https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation
[A22]: https://developer.android.com/build/migrate-to-built-in-kotlin
[R01]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md
[R02]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift
[R03]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift
[R04]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift
[R05]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift
[R06]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift
[R07]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift
[R08]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift
[R09]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordsActions.swift
[R10]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift
[R11]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/AppRouteDestination.swift
[R12]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift
[R13]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md
[R14]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md
[R15]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/012-ios-retention-and-cycle-notifications.md
[R21]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Localizable.xcstrings


---

<!-- appendix: CHANGELOG.md -->

# 1.1 变更记录 · 产品方向确认版

日期：2026-09-21。前版：1.0。本版不改变固定 iOS 源提交。

## 确认来源

本对话负责人回复：“1-6 我觉得都 OK”。本版将上一轮六项建议固化，并明确它们对应 D-01/D-02/D-03/D-05/D-08/D-11，不将其他 D 项误批。

## 实际修改

- D-01：收费模式确认，地区价格和试用/优惠未填假值。
- D-02：Google Drive 同步确认且属于手机/平板首发；保持默认关闭和最终用户主动授权。
- D-03：首发 JSON 跨平台数据迁移、商店权益独立；不做跨 iOS/Android 自动同步。
- D-05：Wear OS 独立后续阶段，T27 标 DEFERRED，QA-137 仍 NOT_RUN 并标后续范围。
- D-08：购买验证服务方向确认；基础设施与部署仍待落实，不能上传工资和工作记录。
- D-11：账户核验流程确认；实际账户信息保持 UNKNOWN，未推断 Google 开发者身份。
- 同步更新 00～07 文档、任务卡、tasks.json、test-catalog.json、AI 启动/接续提示词、发布签收表；新增 decisions.json 配置台账。
- 保留 28 张任务卡、137 条验收规范、12 项独立样例与 52 个原始参考入口；不删除未执行事项。

## 没有完成或没有重新执行的事项

未修改 GitHub 仓库或生成 Android 工程；未构建应用或运行真实应用测试；未创建 Google 账户、商品或 OAuth 项目；未部署服务、操作 Play Console 或提交审核。1.1 未重新检出/全量审计源仓库，也未重新核验全部平台政策和库版本；原引用保留，执行与发布时仍须按官方资料复核。

方案确认与代码/测试/部署/发布状态分开记录。文档静态校验的实际结果见 PACKAGE_VALIDATION.md。
