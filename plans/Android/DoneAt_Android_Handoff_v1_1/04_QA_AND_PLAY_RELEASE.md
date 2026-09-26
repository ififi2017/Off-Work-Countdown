# 04 · 验收、Google Play 上架与运行维护手册

**1.2 决策状态**（2026-09-23 修订）：收费模式、首发跨平台边界、Wear延后已确认；D-02 修订为首发以系统备份/设备转移换机恢复、Drive 同步延后；D-08 修订为首发纯客户端 Play Billing、服务端验证延后；D-12 Release 只用稳定 Material3。Play账户核验流程已确认，但账户事实未知。方案确认不等于QA通过或发布许可。首发 126 条用例；QA-110～QA-122（Drive）与 QA-137（Wear）属后续阶段。详见05及decisions.json。

这份清单区分能自动验证的代码与必须由负责人/真机/真实服务验证的事项。截至 2026-09-26，本地四模块 388 项单测、lint、Debug/R8 Release/AAB、Web/Desktop 构建与输出、iOS headless build、12 项 Swift fixture 和真实 iOS→Kotlin→iOS 往返已通过；API 36 的 Auto Backup 与文档化设备转移/重装路径已恢复业务档案及设备设置。126 项首发 QA 的逐项状态见 `docs/android/preconsole-qa-2026-09-26.md`，不能把上述门禁等同于 126 项全通过。Play Console 尚未操作，公开平台规则于 2026-09-21 核对过，正式提交前复核。[A04], [A09], [A14], [A23]

## 1. 验收证据结构

每项结果包含：需求 ID、测试 ID、源规范位置、Android 实现路径、前置条件、操作/输入、预期、实际、设备/构建/日期、证据路径、执行人。用例状态只能 PASS / FAIL / BLOCKED / NOT_RUN；没有日志或截图的真机结论不能填 PASS。

一个功能同时需要领域与平台验证时分别登记。例如：提醒时间计算 PASS，不等于 Pixel/三星熄屏下真实投递 PASS；购买状态机 PASS，不等于真实 Play 退款回收 PASS；系统备份规则 PASS，不等于真机换机恢复 PASS。

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
| Persistence | D-13 原子档案、兼容读取、导入冲突/失败回滚 | JVM 文件系统测试 + Android 设备恢复 | 不只测内存 fake repository |
| UI | 点击、导航、锁定状态、无障碍、窗口重建 | Compose tests + screenshot | 不把一张Preview当运行页面 |
| Platform | 权限、后台、通知、小组件、分享、链接、生物识别 | 模拟器+真机 | 不只在前台模拟时间 |
| Commerce | 购买、优惠资格、pending、确认、续费、恢复、退款 | Play 许可测试与 Console；首发客户端签名验证 | 不靠本地 isPlus 开关或 JVM 状态机单测 |
| 后续 Drive | 首次拉取、双设备并发、删除 fence、账号切换、配额 | 后续阶段真实测试 Google 账号/设备 | 首发不实施 Drive；不以本机导出文件代替云恢复 |
| Release | R8、签名、API、AAB、16KB、最终权限 | Release构建+Console预发布报告 | 不用Debug成功替代 |

建议至少覆盖 API 26、31/32、33、34/35、36 及发布时最新稳定 Android。每个 API 不必组合所有机型，但通知/精确闹钟权限变化节点必须测试。目标 API 与运行系统 API 是不同维度。

设备建议：一台当前 Pixel/接近原生的实体机，一台主流厂商实体机，一台中档参考性能机；平板可实体机加模拟器；折叠/分屏使用可调整窗口环境。不要把具体型号未提供当成不能开始，先在模拟器完成自动化，再列出真机签收。

布局：窄屏约360dp、常见400dp以上、横屏、600dp附近、840dp以上；浅/深/跟随系统、品牌/动态色；100%/130%/200%字体；英语、简中、繁中港台、德文长文本、阿语RTL及其余语言资源检查。

## 3. 重点业务门禁

**时间**：同一毫秒边界的半开区间一致；跨夜属于原班次日期；休息期间收入冻结；加班分母不改原计划时薪；关闭App再开不累计漂移；DST和时区变化有fixture。

**记录**：计划与观测分离；实际与预测不重复；月薪口径按最新修订；历史编辑保留休息空隙；重新编辑班型不改变已冻结历史；免费窗口按自然日期。[R02], [R05], [R08], [R10], [R14]

**数据**：1–6版备份、v6双向往返、损坏/过大文件、重复导入、同ID冲突、墓碑、引用重映射、低空间和中途死亡；旧版 JSON 档案升级不丢数据。[R07]

**专注**：确定性ID、单活跃会话、边界停止、模板完整前缀、设置只影响下轮、恢复不会伪造已完成任务。[R06]

**付费**：待付款无权益；取消续费未过期保留；到期准确；终身离线缓存；查不到服务不等于查到空权益；恢复不丢原动作；源“过期后停止观测”的政策按D-07执行。[R05], [A06], [A08]

## 4. 安全与隐私发布门禁

### 4.1 逐条数据流登记

| 数据 | 默认位置/动作 | 发布前需要确认 |
|---|---|---|
| 工资、班次、职业、任务与记录 | 本地原子 JSON 档案（D-13）；随 Android 系统备份/设备转移 | 系统备份由 Google 处理（Android 9+ 设锁屏时端到端加密）；如实填写 Data safety；日志和组件无内容 |
| 用户主动JSON导出 | 用户选定SAF目标 | 明确告知包含个人信息；排除购买/授权秘密 |
| Drive同步业务数据（后续阶段） | 首发无；启用后用户主动授权上传私有空间 | 该阶段上线前重做申报：字段、目的、关闭与删除 |
| 购买Token/产品/权益时间 | Play 与本机缓存（首发无自建服务） | 本机缓存不进备份；后续加验证服务时补充申报 |
| 服务端基础请求日志（后续阶段） | 首发无自建服务 | 加入验证服务时确认 IP/UA 是否保存、保留多久；不要口头承诺零日志 |
| 崩溃/性能诊断 | 默认不加外部SDK | 增加后重新审计数据安全和隐私政策 |
| 通知授权/系统能力 | 本机系统状态 | 不与其他设备互相覆盖 |
| 用户联系开发者 | 系统邮件/浏览器显式动作 | 默认不附工资、记录和未脱敏日志 |

Google Play 对仅在设备上处理的数据、离设备传输、可关联标识与用户发起分享分别有定义。**不因为“无DoneAt账号”“使用私人Google Drive”“不做广告”就直接选择No data collected。**按最终实现和每个SDK/后端行为填写，留存说明依据。[A14]

如未来引入应用账号创建，需要重新核对 Play 的应用内及外部账号删除要求；当前无账号方案不因此豁免本地/云业务数据删除功能。Google OAuth 授权与本应用账号是否构成政策意义上的账号体系，应按实际实现判断，不能只改按钮名字规避。[A29]

### 4.2 最终包与网站

最终 merged manifest 无无关敏感权限；明文网络关闭；exported组件与Intent过滤器最小化；未导出内部receiver；所有允许外部输入的链接和文件经过验证。

备份策略验证 cloud backup 与 device-to-device transfer：原子 JSON 业务档案可恢复（QA-138～QA-140），密钥/Token/购买缓存不进入备份；隐私文案与 Auto Backup 实际行为一致。[A16], [A28]

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

首发为纯客户端验证（D-08 修订）：在 Console 取得许可公钥写入构建配置，确认客户端 acknowledge 与重试；Publisher API/RTDN/验证服务属后续阶段。将许可测试者与封闭测试者分别核对：在测试轨道能安装，不必然等于具备正确的Billing许可测试设置。

至少实际完成一次：月/年购买、终身购买、用户取消、付款Pending、Pending成功/取消、App退出后恢复、重装恢复、取消自动续费后到期前使用、测试续费、退款/撤销、Play 服务暂不可用、重复回调。优惠资格用真实符合/不符合两组账户验证。

不要在普通真实账户上无确认地进行不可逆扣费。Debug 使用独立包名/数据空间；假购买只用于测试，不能遗留在发布包。

## 8. 商店资料与截图

资料必须展示**真正运行的Android界面**，不能拿iPhone截图、概念渲染图或未实现的Wear/云同步页面冒充；商店文案不得宣称多设备同步。使用合成测试数据，不使用用户真实工资/经历。[A26]

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

不加行为分析SDK也可以由负责人查看Play Console已有的Android vitals、安装/崩溃和用户评价等聚合信息；不要因此擅自给App添加用户追踪。首发无自建服务端；后续阶段的服务端仅监测购买验证/ack重试/RTDN失败与同步相关技术错误，保持日志脱敏。

停止扩量条件：数据丢失、旧备份无法恢复、明显收入/时间计算错误、购买后无法使用/误扣费、隐私泄露、大规模Crash/ANR。优先停止受影响版本扩量、保全日志与用户数据、发布更高versionCode修复包。不能指望用户安装更旧 APK 即可读取新版档案格式。

首发 Play 查询暂时失败时保留已验证权益缓存；客户端出错时不要建议用户先清除数据/重装。先导出或保存受保护副本，在修复版本中验证迁移恢复；无法备份时明确风险并选择不破坏数据的诊断。

## 12. 发布签收表

| 门禁 | 签收人 | 当前状态 |
|---|---|---|
| 产品方向与首发边界 | 项目负责人 | 2026-09-21 六项确认，2026-09-23 修订 D-02/D-08 并新增 D-12；D-11仅流程确认，不代表账户事实已核实 |
| 其余D项、商品参数与生产环境 | 项目负责人 | 待配置/签收；按05及decisions.json，不重复询问已确认方向 |
| 源码差分/领域/档案/导入测试 | 开发与审查 AI/人员 | 本地四模块 388 项与 iOS→Kotlin→iOS 往返通过；QA 矩阵仍有部分/未跑项 |
| 真机后台、权限、小组件、无障碍 | 测试人员 | 待执行 |
| 真实购买（客户端验证）与换机备份恢复 | 负责人+开发 | 真实 Play 购买未跑；API 36 Auto Backup 与文档化设备转移/重装恢复业务字节一致，其他设备/缓存重建待核 |
| 真实多设备同步与删除 | 负责人+测试 | 后续阶段（D-02 修订），不阻塞首发 |
| 19语言、稳定 Material3 + DoneAt token 与大屏 | 产品负责人 | 待执行 |
| 隐私、安全、许可证与最终权限 | 负责人+审查 | 待执行 |
| AAB、签名、版本、Play表单/测试资格 | 负责人 | 本地 R8 Release/AAB 构建通过；生产签名、最终哈希与 Console/测试资格未核 |
| 生产发布授权与回滚联系人 | 负责人 | 待执行 |

表中工程与部分设备行只记录已有的本地证据。Play 商品、签名、Console 表单、许可测试购买和生产发布仍待负责人核验；各 QA 用例按证据矩阵逐项判定，不由任务状态推断 PASS。


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
