# 06 · 可直接交给执行 AI 的提示词

## A. 首次会话：先审计，不盲写

把下面这段与交接包一起交给有仓库读写及Android构建能力的AI。它应先建立真实基线，然后按任务卡推进，而不是凭聊天摘要重写整个应用。

```text
你要把 ififi2017/Off-Work-Countdown 的 iOS 原生版本完整移植为 Kotlin + Jetpack Compose + 稳定版 Material3（DoneAt 设计 token 实现 Expressive 风格）Android 应用，并完成 Google Play 发布准备。

先读取本交接包：
00_START_HERE.md
01_PRD.md
02_TECHNICAL_GUIDE.md
03_AI_EXECUTION_PLAN.md
05_SOURCES_AND_DECISIONS.md
decisions.json
然后读取仓库根 AGENTS.md（CLAUDE.md 为其符号链接）、docs/agent-guides/android.md、docs/android/progress.md 和固定源提交。

源基线：9252fdfdc66aab88b4acb7493684f11991fd773d。
拟新增目录：src-mobile/android/。
T00、T01、T02 已完成（见 docs/android/progress.md）；从 progress.md 列出的下一任务开始，每次仅处理一个明确可验收任务。

负责人已于2026-09-21回复“1-6 我觉得都 OK”，采用上一轮六项建议：
- D-01：保留月/年订阅与终身买断；金额、试用、正式商品配置仍未知。
- D-02（2026-09-23 修订）：首发以 Android 系统备份/设备转移换机恢复（业务库纳入备份，购买缓存/密钥/令牌排除）；Drive 同步延至首发后（T22）。
- D-03：首发只以JSON跨平台迁移业务数据；不做iOS/Android自动同步，购买权益独立。
- D-05：Wear OS后续独立阶段，T27=DEFERRED，不阻塞首发，不标已完成。
- D-08（2026-09-23 修订）：首发纯客户端 Play Billing（queryPurchasesAsync + Play 公钥签名校验 + 客户端 acknowledge）；服务端验证延至首发后（T21）。
- D-12（2026-09-23）：Release 只用稳定 Compose/Material3，不引入 alpha。
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
8. 不擅自增加DoneAt账号。执行已确认的换机恢复/跨平台/收费/客户端验证方向；Drive、服务端与Wear均为后续阶段。严格区分已批准方向、未定价格与生产配置，不重新将全部D项标为待定。
9. Pending不是已购买；失败不是确认无权益；生产Billing与系统备份恢复不得用mock/stub冒充完成。
10. Release 不引入 alpha/实验 Material3 API；Expressive 风格经 :core:designsystem token 实现，依赖版本由真实编译探针锁定。
11. 每个任务都要交付实现、测试、实际运行命令与结果。不能只说“应该通过”。
12. 没有设备/服务/凭据时列NOT_RUN或BLOCKED；继续不受影响的任务，不能编造证据或清掉阻塞项。
13. 不以“iOS不方便”直接删功能；平台差异需要明确替代、用户影响与批准状态。
14. 只在docs/android/progress.md更新任务状态（tasks.json 不记状态），同步feature-parity.md，保留下一AI可接手的上下文。

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
先读00_START_HERE.md、仓库AGENTS、docs/agent-guides/android.md、docs/android/progress.md、decisions.json及05已确认D项。
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
专注确定性ID/恢复、权限降级、工资泄露、客户端购买验证（签名/acknowledge）与离线缓存、
系统备份包含/排除规则与恢复后重建、19语言与RTL、Release依赖无alpha。
检查Debug特权是否可能进Release，检查测试是否被删除、改expected或实际执行零条。
按decisions.json区分方向批准/配置未知/未覆盖决策；首发FR-01～FR-20；Drive同步、服务端验证与Wear属后续阶段，不能当首发失败，也不能当已实现。
按阻塞发布/重要/一般排列发现，给出具体文件位置、复现输入、预期与实际以及修复建议。
没有实际验证的环境明确列出；不要把静态审查当真机验收。
```

## D. 给负责人的最短使用方式

先把整个ZIP交给开发AI，让它从00和A段开始；之后每轮用B段指定下一张任务卡。不要让它只看合并文档的开头，也不要只给PRD而不提供技术约束和测试目录。关键规则/数据/支付/同步阶段完成后，使用C段独立审查再进入后续阶段。
