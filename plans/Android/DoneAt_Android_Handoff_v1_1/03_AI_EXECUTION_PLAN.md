# 03 · 给执行 AI 的分阶段实施计划

## 1. 工作方式

每次只选择一个依赖已完成的任务。先读源文件与当前任务涉及的条目，再输出改动范围，完成一条可运行的纵向链路，补测试、运行、审查差异，然后更新进度。不要一次生成整个工程再把测试留到最后。

同一功能的模型、序列化、UI、权限、测试可以分步完成，但“任务完成”必须达到该卡的验收条件。不允许用截图、空实现、打印日志、模拟支付/同步成功冒充真实能力。

若外部账户、设备或商业决策阻塞：把该任务标记 BLOCKED，记录精确原因；继续做不依赖它的工作。不要把阻塞项删掉，也不要让没有必要的外部依赖阻塞纯 Kotlin 规则和本地 UI。

`tasks.json` 的 `blocking_decisions` 只列真正未获批准的决策；`approved_decisions`/`approved_processes` 指向已确认项；`pending_configuration` 指向 decisions.json 中尚待落实的外部配置；`decision_gate_scope` 说明具体阻塞位置。D-01/D-02/D-03/D-05/D-08/D-12 的方向已确认（D-02、D-08 于 2026-09-23 修订），D-11 的核验流程已确认。T03可采用候选包名/minSdk完成本地Debug探针，正式签名/创建Play应用前冻结；价格未定不阻止领域和Debug接口；Drive 同步与服务端验证已移出首发，不阻塞首发任何任务。生产部署、真实用户数据传输和发布仍需配置、最终用户同意及适当操作授权。

推荐任务状态：NOT_STARTED → IN_PROGRESS → IMPLEMENTED → VERIFIED；需要负责人签收的进入 WAITING_OWNER，阻塞为 BLOCKED，批准延后的范围为 DEFERRED。只有 VERIFIED 加相应外部签收才可算发布完成。任务实际状态只在仓库根 `docs/android/progress.md` 维护；`tasks.json` 只定义依赖与范围（`scope`），不再记录状态。1.2 起 T21、T22、T27 属首发后阶段；方向获批不是实现进度。

## 2. 阶段与门禁

| 阶段 | 结果 | 允许进入下阶段的门禁 |
|---|---|---|
| M0 | 完整功能/字段/规则审计 | 基线固定、冲突可解释、未定产品决策有编号 |
| M1 | 可构建工程与设计系统 | Debug/Release技术探针和翻译检查通过 |
| M2 | Kotlin 规则核心 | 原规范输入差分通过，不能用肉眼看数值代替 |
| M3 | 持久化与备份 | 事务/迁移/导入/解析/旧数据通过 |
| M4 | 专注和调度模型 | 重启、重复动作、边界与权限测试通过 |
| M5 | 所有业务 UI | 每屏接真实状态，主要路径不靠假数据 |
| M6 | 系统集成与真实付费 | Widget/分享/权限、系统备份恢复与客户端 Play Billing 签收（服务端验证 T21 为后续） |
| M7 | 同步（首发后） | D-02 修订后不阻塞首发；启动后按双设备并发、删除、首次恢复与账号切换签收 |
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

**验收**：核实所有源码链接指向同一 SHA；登记已批准方向与真正未知的配置，不再把 Drive/收费模式/验证服务的首发取舍列为待选；账户事实未知就保留UNKNOWN；仓库没有被reset/覆盖。


### T01 · M0 · 完成逐入口功能与规则盘点

**依赖**：T00。**覆盖需求**：FR-01, FR-02, FR-03, FR-04, FR-05, FR-06, FR-07, FR-08, FR-09, FR-10, FR-11, FR-12, FR-13, FR-14, FR-15, FR-16, FR-17, FR-18, FR-19, FR-20, FR-21。

**先读**：AppRouteDestination、所有 Views/设置入口、PreferencesStore、Shift/Records/Focus/Life 模型、AppTests、Shared、当前翻译 key；旧 plans 只作佐证。

**执行**：列出每个可见入口、动作、开关、免费 gate、状态和测试；把未在本包细列的小功能添加为 FR 子项。枚举 source filenames 不是完成盘点，必须追到事件处理函数及持久化字段。将源 Bug/未签收行为单独列风险，不能未经批准复制或修正。

**必须交付**：feature-parity.md；source-inventory.md；conflicts.md；完整功能差异表。

**验收**：四个主入口、横屏/平板和深链接目标均覆盖；所有设置 key 有去向或负责人批准的差异，无“暂未找到就视为不存在”。


### T02 · M0 · 冻结字段级备份与领域模型契约

**依赖**：T01。**覆盖需求**：FR-02, FR-03, FR-05, FR-06, FR-07, FR-08, FR-09, FR-14, FR-15。

**先读**：完整 RecordJSON/RecordArchive、12 类实体 DTO、SyncedPreferences、ErasedID、源导入测试；02 第6章。

**执行**：提取每个版本新增字段、默认值、枚举、键、日历/毫秒语义、引用关系；准备匿名合成 v1–v6 档案与非法档案。明确 wire v6、本地 RecordLocalFile、fixture v1、sync envelope v1 是不同版本。

**必须交付**：wire-contract.md；synthetic-archives/；字段映射清单。

**验收**：抽样每一类实体；v6 中无自创字段和购买凭据；缺少真实旧样本时从源编码/测试构造并注明，不拿空对象代替。


### T03 · M1 · 创建最小可构建原生工程

**依赖**：T00。**覆盖需求**：FR-19, FR-20。

**先读**：02 第2、3、14章；Android 官方 AGP/Kotlin/Compose 当前文档。

**执行**：使用 Android Studio 当前可用稳定模板/官方配置；创建 app、domain、data、designsystem 等实际需要模块；确定包名候选；先成功运行空页面和纯 JVM 单元测试。不要一开始生成几十个空屏幕。 JDK 使用 Android Studio 自带 arm64 JBR（本机 temurin-21 为 x86_64 不可用）；SDK 位于 ~/Library/Android/sdk（platforms android-37.0、build-tools 36.0.0），需补装 cmdline-tools。可选：用不超过半天评估 Swift SDK for Android 能否编译 src-mobile/ios/Shared 核心，结论写入 environment-lock.md，不阻塞本任务。

**必须交付**：可运行 Debug 工程；environment-lock.md；Gradle wrapper/version catalog；基础 CI。

**验收**：./gradlew --version、domain:test、app:assembleDebug 成功；不存在未声明版本动态依赖；实际 SDK/编译器兼容记录齐全。

**决策与配置**：未决 D-04, D-10。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


### T04 · M1 · 完成稳定版 Material3 与 DoneAt 设计 token 探针

**依赖**：T03。**覆盖需求**：FR-18, FR-19。

**先读**：01 第7章；A01/A20；D-12；稳定版 Material3 API reference。

**执行**：锁定稳定 Compose BOM 与 Material3 1.4.x（D-12）；在 :core:designsystem 以自有 shape/motion/color token 实现 Expressive 风格；Release 依赖树中不得出现 alpha/beta 的 Compose/Material3。

**必须交付**：designsystem 实现和 gallery 测试页面（Debug only）；design-tokens-adr.md（记录哪些 Expressive 行为由自有 token 实现、将来切换条件）；依赖树。

**验收**：Release 依赖树无 alpha/beta Compose/Material3；主要状态/操作的 Expressive 风格经 token 实现；减少动态效果及大字体探针通过。

**决策与配置**：已确认 D-12。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


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

**执行**：支持周期锚点、manual roster、carry-over、holiday、clearedFrom、frozen shift、base fallback；保持统一 segment 引擎；建立源 Swift 测试→Kotlin 对照。Swift 特有规则的 fixtures 作为 Swift 与 Kotlin 共用的检查：由 Swift 测试导出 JSON，Swift 测试与 Kotlin 测试读取同一份文件，并加 stale 检查，避免形成第三份无 oracle 的实现。

**必须交付**：ExtendedScheduleResolver；Swift parity fixtures；优先级决策表。

**验收**：锚点前 floorMod、短月、休息与未排、历史冻结、清空后重启均通过；不能用 TS 测试冒充覆盖 iOS 独有逻辑。


### T09 · M2 · 实现记录汇总与人生计算

**依赖**：T07, T08。**覆盖需求**：FR-05, FR-06, FR-08。

**先读**：SummaryRules、lib/summary、LifeViewCalculator/LifeSummary、计划015/016最新修订和调用点。

**执行**：分开 live earnings 与 records fixed monthly allocation；实现自然日分摊、实际/预测、年终奖、职业收入和未来比例；缓存不参与业务结果。

**必须交付**：SummaryEngine/LifetimeEngine；浮点/货币策略；分支测试。

**验收**：跨月周、请假固定月薪不扣、空档、重叠拒绝、一次性比例调整通过；所有相同语义 UI 投影引用统一服务。


### T10 · M3 · 实现记录档案存储、事务写入与编解码

**依赖**：T02, T03。**覆盖需求**：FR-06, FR-07, FR-09, FR-14, FR-15。

**先读**：实体字段契约、RecordCoordinator/Command 的行为与源写入错误处理。

**执行**：D-13：与 iOS 相同，内存 RecordState + 原子替换的 RecordLocalFile（schema-6 文档 + 墓碑）；串行写协调器：计算→编码→回读校验→原子写→发布，任一步失败不改变已发布状态与文件；损坏档案阻断写入直到隔离；以 Swift RecordJSON 为 oracle 的编解码 fixtures。

**必须交付**：records 模型与 RecordJson（:core:domain）；RecordArchive/RecordStore（:core:data）；record-json-fixtures；文件系统测试。

**验收**：进程重启读回一致；写入失败/校验失败不部分提交；损坏档案不被当作空档案且不被覆盖；data 模块测试真实文件系统；编解码 fixture 全通过。

**决策与配置**：已确认 D-13。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


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

**执行**：四个主入口独立导航栈；恢复/新建草稿流程；设置分组；错误/空/恢复态；窗口和后台重建保持状态；首发不展示 Drive 同步入口（T22 已延后）。

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

**依赖**：T11, T14, T16。**覆盖需求**：FR-01, FR-11, FR-12, FR-13, FR-15, FR-17。

**先读**：源Widget投影、分享协议、当前品牌资产；A11/A12/A25；02第8/11章。

**执行**：安全Widget DTO、多尺寸Glance、过期态；普通通知适配；独立分享图渲染；SAF/FileProvider；分享链接沿用源网页版，不注册外部 App Links；备份规则。dataExtractionRules/fullBackupContent：业务 records/ 原子档案与 device/settings.json 纳入 cloud backup 与 device transfer（D-13，不存在 WAL）；排除购买缓存、待确认购买标记、Keystore 相关数据、令牌与 debug 设置（D-02 修订）。

**必须交付**：Widgets/Share/LinkHandler；manifest与dataExtractionRules；链接配置说明；备份/恢复验证记录（QA-138～QA-140）。

**验收**：薪资不会出现在组件/通知/分享元数据；组件多实例/重启/尺寸变化；链接预览不自动覆盖；不新增危险权限。业务数据可随系统备份/设备转移恢复，购买缓存与密钥不在备份内。

**决策与配置**：已确认 D-02。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


### T20 · M6 · 实现权益领域与 Billing 客户端

**依赖**：T03, T15。**覆盖需求**：FR-16。

**先读**：PlusEntitlement、01矩阵、02第9章、A06/A08；D-01/D-07。

**执行**：状态机、ProductDetails本地价格、single-flight购买/恢复、pending/取消/失效/离线；权益只来自 queryPurchasesAsync 与 Play 公钥签名校验；客户端 acknowledge 并持久化待确认重试（3天窗口）；fake隔离debug；保存原操作上下文（D-08 修订：首发无自建服务）。

**必须交付**：EntitlementEngine/BillingRepository/Paywall；状态转移测试。

**验收**：取消续费未到期仍可用；Pending无权；断网不抹已验证缓存；同意D-07前保持源失效采集行为。

**决策与配置**：已确认 D-01, D-03, D-08；待配置 CFG-PRICE；未决 D-07。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


### T21 · M6 · （后续）服务端购买验证与 RTDN

**范围：首发后阶段，不阻塞首发。**

**依赖**：T20。**覆盖需求**：FR-16, FR-20。

**先读**：02第9章；A07/A08；D-08已确认记录、CFG-BACKEND与服务凭据边界。

**执行**：首发后按需启动。优先在现有 Next.js/Vercel Route Handlers 实现 Publisher 验证、幂等权益、RTDN 重查、撤销/linkedToken；不收工资或记录。

**必须交付**：权益验证服务代码（优先现有 Vercel Route Handlers）；部署runbook；监控/重试；接口contract tests。

**验收**：真实许可测试账户购买、恢复、pending、退款、取消及重复RTDN；无密钥进Git/APK；只有mock通过不算生产完成。

**决策与配置**：已确认 D-08；待配置 CFG-BACKEND。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


### T22 · M7 · （后续）Android 私有云 Drive 同步

**范围：首发后阶段，不阻塞首发。**

**依赖**：T10, T11, T13, T20。**覆盖需求**：FR-01, FR-15。

**先读**：源Recovery/RecordsCloudSync/SyncPayload/SyncLocalState与相关测试；02第10章；已确认D-02/D-03与CFG-OAUTH。

**执行**：Google授权与私有scope；pull-before-push；不可变批次+墓碑；首次恢复/冲突；账号切换；reset fence；持久outbox与重试；明确无iCloud自动互通。

**必须交付**：SyncTransport/Coordinator；设置恢复页；sync-protocol.md；模拟传输contract tests。

**验收**：新设备旧机关闭恢复；双设备改不同日不丢；删除后离线旧设备不复活；授权取消/配额/分页失败不当空云；使用已批准Drive完成真实联调与双设备验收，不能只靠mock。

**决策与配置**：已确认 D-02, D-03；待配置 CFG-OAUTH。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


### T23 · M8 · 全功能集成与权限/付费回归

**依赖**：T17, T18, T19, T20。**覆盖需求**：FR-01, FR-02, FR-03, FR-04, FR-05, FR-06, FR-07, FR-08, FR-09, FR-10, FR-11, FR-12, FR-13, FR-14, FR-15, FR-16, FR-17, FR-18, FR-19, FR-20。

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

**决策与配置**：已确认 D-01, D-02, D-03, D-08；流程已确认 D-11；待配置 CFG-PRICE, CFG-PLAY-ACCOUNT, CFG-APP-IDENTITY；未决 D-10。参见 decisions.json；配置缺失只阻塞相应外部阶段，不重新询问已确认方向。


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
| Play购买回调成功就设置isPlus=true | 以queryPurchasesAsync与Play公钥签名为准，持久化、确认（acknowledge）、恢复与撤销完整走通 |
| 失去网络等于用户失去终身权益 | 区分不可用与确认无权益；保留最后已验证缓存 |
| 云同步覆盖一个JSON，以时间较新胜出 | 保留每实体编辑戳与墓碑，多设备合并 |
| 关闭同步就删云数据 | 区分暂停、云删除、本机移除 |
| 把业务库排除出Auto Backup，换机后记录全丢 | D-02修订：业务库纳入系统备份/设备转移，只排除购买缓存、密钥与令牌；隐私文案如实描述 |
| 减少动画只把时长设小 | 移除连续循环/触感，保留静态可理解状态 |
| 单元测试通过=通知、购买、云同步都通过 | 这些需要对应真机/真实服务证据 |
| 为了Expressive引入alpha/beta Material3 | D-12：Release只用稳定版，Expressive风格由designsystem token实现 |
| 使用默认主题就称已完成设计 | 依据设计系统gallery及逐屏验收检查形状/层级/动作/动效token |
| 生成了AAB就说已上架 | 实际Console配置、测试资格与审查是独立发布门禁 |

## 7. 禁止自动改变的范围

未征得确认，禁止新增 DoneAt 登录系统、跨平台权益服务、广告/分析 SDK、全局云端工资数据库；禁止改订阅价格、试用期限、免费窗口、历史采集政策、源收入口径；禁止为了Android修改线上iOS规则使其迎合错误结果；禁止把负责人私钥、Play令牌、真实导出文件放进测试仓库。

可以自主处理：纯工程文件布局、变量命名、局部无语义重构、补足测试和文案错误、在已批准设计token内改善排布。对产品/数据语义有影响的差异必须进入 decisions/ADR，不可埋在实现备注里。
