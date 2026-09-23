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

### C-08：Expressive库的发布日期不等于稳定依赖组合（D-12 已裁决：Release 用稳定版）

官方当前发布页区分Material3稳定与预发布。新工程需要明确锁定与技术探针，不把“1.4最新版稳定”和“Expressive APIs”硬拼；也不能声称封装进designsystem就不会带入传递依赖。[A01], [A20]

## 3. 已确认决策与剩余配置（1.1）

### 3.1 确认来源与解释边界

负责人在本对话中于 2026-09-21 回复 **“1-6 我觉得都 OK”**，同意上一轮表格中的六项建议。聊天序号 1/2/3/4/5/6 对应 **D-01/D-02/D-03/D-05/D-08/D-11**，不是 D-01～D-06。该确认不等于修改所有未讨论的产品细则，也不等于已经配置账户、商品、服务或通过验收。

**2026-09-23 修订**：负责人在评审后回复“其他的可以按照你的建议更新好”，据此修订 D-02、D-08 并新增 D-12（见下表）。原 2026-09-21 的 D-02/D-08 结论被取代，保留于 decisions.json 的 `superseded` 字段。

| ID | 状态 | 当前决定 | 仍待配置/验证的事项 |
|---|---|---|---|
| D-01 | APPROVED（收费模式） | 月订阅、年订阅、终身一次性非消耗商品均保留 | 地区价格、销售范围、试用/优惠、生产商品标识；不得自行填金额或试用天数 |
| D-02 | APPROVED（2026-09-23 修订） | 首发以 Android 系统备份/设备转移换机恢复（业务库纳入备份，购买缓存/密钥/令牌排除），跨平台 v6 文件；Google Drive appDataFolder 多设备同步延至首发后，届时默认关闭、主动授权 | 真机换机恢复验证（QA-138～QA-140）；后续同步阶段的 OAuth 配置与双设备测试 |
| D-03 | APPROVED | 首发不做 iOS/Android 自动同步，业务数据经 JSON 双向迁移，购买权益独立 | 迁移往返和权益隔离验证；任何日后自动互通或账号方案需要新决策 |
| D-04 | PROPOSED（本轮未覆盖） | 原建议 minSdk API26 / Android8；目标 API 在实现和发布阶段复核 | 支持矩阵与正式包签收；本轮不得代签 |
| D-05 | APPROVED（延后） | 手机/平板先发布；Wear OS 独立后续阶段，不阻塞首发 | T27 标 DEFERRED；FR-21/QA-137 保留为后续范围；启动时间与投入另行安排 |
| D-06 | PROPOSED（本轮未覆盖） | 原建议可选精准提醒授权，拒绝后降级，不默认使用高限制权限或全天常驻服务 | 平台探针与最终权限声明；本轮不得代签 |
| D-07 | PROPOSED（本轮未覆盖） | 原建议暂按源代码保留失效 Plus 停止新增工作观测的行为 | M0 核对调用链及产品签收；不能用 D-01 的收费模式确认冒充批准细则变化 |
| D-08 | APPROVED（2026-09-23 修订） | 首发纯客户端 Play Billing：queryPurchasesAsync + Play 公钥签名校验 + 客户端 acknowledge，与 iOS 纯客户端 StoreKit 对齐；服务端验证/RTDN 延后，届时优先放入现有 Vercel Route Handlers | 首发只需许可公钥与真实购买验收；已知代价：撤销在下次查询生效、root 可篡改 |
| D-09 | PROPOSED（本轮未覆盖） | 原建议敏感页面保护，不全面阻止无薪资内容分享 | 隐私交互与最终截图策略签收 |
| D-10 | PROPOSED（本轮未覆盖） | 候选 applicationId 为 com.rainif.doneat；Android versionCode 独立增长 | 包名、营销版本、签名与首次上传前冻结；尚未创建 Play 应用 |
| D-11 | APPROVED_PROCESS_PENDING_FACTS | 按真实 Play Console 账户核对验证、测试与生产访问要求 | 是否已有、个人/组织、创建时间、生产访问均 UNKNOWN；不能从 Apple 身份推断 |
| D-12 | APPROVED（2026-09-23 新增） | Release 只用稳定 Compose/Material3（1.4.x）；Expressive 风格由 designsystem 的 DoneAt token 实现，官方 Expressive 稳定后再评估 | T04 探针与 design-tokens-adr.md |

### 3.2 未知参数不等于方向未批准

| 配置 ID | 对应决定 | 需要落实 | 对开发的影响 |
|---|---|---|---|
| CFG-PRICE | D-01 | 价格/地区/试用/优惠/正式商品配置 | 不阻止领域层、支付接口和 Debug 测试；阻止正式销售与相应商店文案签收 |
| CFG-OAUTH | D-02 | （后续阶段）Cloud/OAuth 项目、签名关联、测试账户 | DEFERRED：首发不需要 |
| CFG-BACKEND | D-08 | （后续阶段）部署位置（优先现有 Vercel）、Publisher API 身份、RTDN 配置 | DEFERRED：首发不需要 |
| CFG-PLAY-ACCOUNT | D-11 | 实际开发者账户、类型、创建时间、验证与生产访问状态 | 不阻止本地开发；在 M0 登记并尽早核验，实际 Console/生产申请前必须有证据 |
| CFG-APP-IDENTITY | D-10 | 最终包名、营销版本、签名与 versionCode 方案 | 本地可用原候选；生产 OAuth/商品/签名/首次上传前冻结 |

没有有效的生产试用配置与资格依据时，不展示“免费试用 N 天”；这不是永久取消试用的产品决定。方案已批准后，不再反复询问首发是否加入 Drive、是否分开商店权益或是否需要验证服务；只处理真正缺失的配置和未覆盖决策。

### 3.3 实施边界与执行状态

正式首发覆盖 FR-01～FR-20（FR-15 首发为换机恢复，FR-16 首发为客户端验证）；T21、T22、T27 属首发后阶段。实际进度只在 `docs/android/progress.md` 维护。140 条应用测试仍全部 NOT_RUN，其中 QA-110～QA-122 与 QA-137 属后续范围，不参与首发阻塞，也不是 PASS。报价/购买、创建真实账号、改价、部署生产或提交 Play 等外部操作仍需适当授权；本次回复只确认方向，不代表已经执行。

后续同步阶段的产品批准不替代最终用户的 Google OAuth 同意；后续验证服务不授权把业务记录上传服务端。系统备份遵循用户在系统中的备份开关。保留根 AGENTS 的本地优先、无 DoneAt 账号及敏感数据隔离边界。

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
