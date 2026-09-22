# 017 · Apple Watch：免费只读 App、独立排班与表盘组件

- **状态**：IN PROGRESS — 2026-09-19 按用户确认改为全部免费，并实现 V2 共享规则长期独立排班；本轮自动化、视觉与待真机证据见验收记录。早期 Ultra 2 反馈属于 V1，不能替代 V2 后台接续验收。
- **自由排班清除增量**：2026-09-20 协议 V4 传递清空起点；继续读取 V1–V3，新旧设备不得静默忽略该边界。见 [验收记录](../../docs/reviews/2026-09-20-free-roster-clear.md)。
- **节假日增量**：2026-09-19 协议 V3 在共享核心上增加手机选定地区的日期效果；Watch 不携带全球名称库。继续读取 V1/V2 缓存，同配对世代不接受协议降级。两端升级后启用，见 [验收记录](../../docs/reviews/2026-09-19-holiday-templates.md)。
- **目标**：所有用户均可免费抬腕查看班次状态、剩余工作时间和进度，首次同步后通过缓存规则独立接续排班。
- **依赖**：[006 权益模型](006-free-trial-subscription.md)、[018 架构整改](018-ios-3.2.0-architecture-remediation.md)、[移动端架构与 W0–W3](../../docs/PLAN-MOBILE.md)、当前 TypeScript 规则和原生 iOS App。W0 工程／契约准备可提前开展，Watch 生产者在 018 P1／P2 提交与生命周期边界建立后接入。
- **权威口径**：`docs/PLAN-MOBILE.md` 的 W0–W3 章节与本计划重复，冲突时以本文为准；W0 应把那一节收敛成指向本文的指针，避免两处漂移。
- **范围**：配对 iPhone 的免费只读 Watch App、两种表盘组件、共享排班核心、WatchConnectivity V2 与发布前验收。
- **交付方式**：feature branch → PR → main；本计划不代表授权上传或发布版本。各阶段全部保持未验收，完成时附实际证据。

## 2026-09-19 · 当前契约（取代下文 V1 权益与快照限制）

用户已确认 Watch App、圆形和长方形组件全部免费。本轮不增加腕上编辑、开始／停止、独立通知、收入显示或发布操作。下文关于 Plus 与单次绝对快照的段落仅保留为 V1 实施历史，不再约束 V2。

- iPhone、Watch App、Watch Widgets 编译同一份 `Shared/ShiftRuleCore.swift`、`ScheduleRuleInput.swift`、`ExtendedSchedule.swift`、`ExtendedScheduleRules.swift`。薪资、记录库和提醒协调仍由 iPhone 持有。
- V2 持久化模式、时区、班次类型、周期、自由日历及沿用来源；当前班次覆盖单独限定截止时刻。缓存规则不因下一班开始而失效。V1 仍可读，两端升级到 V2 才支持长期独立循环。
- 保存、恢复、当前班次变化在手机前台也触发 Watch 发布，并等待记录持久化。小包使用 application context；超过 48 KiB 的配置使用文件传输，接收上限 2 MiB。共同经过配对世代、递增版本、重复包和原子落盘校验；大包握手持久化所期待版本。
- receiver 由进程拥有；WatchConnectivity 后台任务等待缓存写入和组件刷新完成。投递由系统安排，已缓存规则的下一班不依赖后台准时唤醒。
- App 与组件保留本地班次应对正常断连。首次无数据、缓存损坏、版本不兼容分别显示等待同步、重新同步、升级提示。
- 真机必须另验：首次同步后不再打开 Watch App，跨多班／休息日／月界；离线和重启；手机改班后台抵达；旧文件迟到；表盘更新与耗电。模拟时间测试不代替这组证据。

本轮实测、待确认项见 [2026-09-19 验收记录](../../docs/reviews/2026-09-19-watch-calendar-acceptance.md)。

## 1. 已确认的产品决定

1. Plus 覆盖的是**独立 Watch App、表盘组件和获准交付的快捷操作**，不是「腕上能看到倒计时」这件事本身。自 iOS 18 / watchOS 11 起，iPhone 的实时活动会自动出现在手表的智能叠放里，不需要任何 watchOS 代码；本产品的实时活动对免费用户开放，因此免费用户在 3.1.9 之后**已经**可以抬腕看到下班倒计时。边界按这个现状划定（2026-09-12 用户确认）。
2. 免费用户保留智能叠放里的实时活动，也可以安装、打开 Watch App，看到简短功能说明和回到 iPhone 查看 Plus 方案的指引。Watch App 内的完整班次状态、表盘组件和控制属于 Plus。不得为了制造付费理由去削弱已经发布的免费实时活动。
3. 有效月订、年订、试用期、Apple 扣款宽限期和未撤销的终身买断均可用。沿用现有商品，不增加 Watch SKU、产品账号或自有校验服务器。
4. iPhone／iPad、Web／Desktop 的现有免费能力不回收。006 中“小组件免费”指已有表面，新增 Watch 表盘组件明确属于 Plus。
5. 首版依赖配对 iPhone；购买、恢复购买、管理订阅和复杂设置在 iPhone 完成。iPad 购买的 Plus 可经配对 iPhone 的 StoreKit 恢复后使用，iPad 不能直接成为 Watch companion。
6. Watch 不承载工资、时薪、今日收入或可反推薪资的数据；不把完整设置或记录库同步到 Watch。

## 2. 首版表面与范围

| 表面 | 必须交付 | 边界 |
| --- | --- | --- |
| Watch 主界面 | 工作、午休、休息、加班、已下班状态；剩余有效工作时间；进度；计划下班时间 | 若加班改变当前结束时刻，明确显示生效结束时间；午休期间剩余工作量不递减 |
| 圆形组件 | 进度环及紧凑时间或整数百分比 | 小尺寸、AOD、系统着色下仍可辨识 |
| 长方形组件 | 状态、结束时间、剩余时间与紧凑进度 | 长文案不能挤掉主要时间 |
| 免费／到期页 | Plus 说明或到期说明、iPhone 操作指引 | 不显示真实班次值；不自动弹出购买流程；可以说明智能叠放里的实时活动仍然可用 |
| 同步状态 | 首次等待、已同步、数据过期、暂不可达、版本不兼容 | 不把等待权益确认写成“你尚未购买” |
| 轻量控制 | 3.2.0 明确延期 | 不实现命令接收器、ACK 或操作入口，不进入本版商店承诺 |

非工作日“今天也上班”和加班延长列为后续增强；首版不做完整排班编辑、薪资、记录／人生、专注计时、独立云同步、Watch 购买页、独立通知调度或自定义常驻后台计时。
现有 iPhone 通知的系统镜像不加 Plus 门槛，不在 Watch 重复预约提醒。实时活动在智能叠放里的呈现同样不加门槛，并且本计划顺带改进它：用 `.supplementalActivityFamilies` 提供自定义的小尺寸呈现，替代系统默认套用的灵动岛视图。这属于 iOS 侧的免费改进，不依赖 Watch App，可以独立发布，验收放在 W1。
`accessoryInline`、`accessoryCorner` 不进入首版必需清单。

## 3. 权益与锁定体验

### 授权来源

iPhone 沿用 `PlusEntitlement` 的统一 StoreKit 2 验证与判定。Watch 消费版本化权益投影，不能另写一套商品和宽限期判定。
投影至少包含状态、权益修订号、验证时间和该状态的有效截止值；截止值来自 Apple 已验证交易／renewal info，不以本地固定天数延长。
首版信任系统配对通信传递的 iPhone 验证结果；不把这一投影宣称为 Watch 独立完成的 StoreKit 签名验证。

| 状态 | Watch 行为 |
| --- | --- |
| 正常订阅／试用 | 截至已验证 `expirationDate` 授权；关闭自动续费不提前锁定 |
| 扣款宽限期 | 截至已验证 `gracePeriodExpirationDate` 授权 |
| 未撤销终身 | 无订阅到期日；仍接收后续撤销更新 |
| 确认无权益／到期／无宽限期重试／撤销 | 锁定真实功能，组件显示中性占位，控制命令不可执行 |
| 首次未知／暂时校验失败 | 没有有效缓存则提示回 iPhone 确认；有缓存则仅在原有效范围内沿用 |
| Ask to Buy／购买 pending | 提示等待批准；不抹除已有有效授权，不预先解锁 |

权益到期和班次数据到期独立判断：Plus 有效但快照过期显示同步说明，不能变成促销页；班次快照有效但 Plus 到期不能继续显示真实计时。
契约中的 `expiresAtMs` 专指班次内容截止，权益使用 `access.validUntilMs`；终身的后者为空。真实内容显示上界是两者中较早的截止（终身只看内容截止），边界 entry 按实际原因分别显示同步说明或权益说明。
家庭共享沿用现有商品配置和 StoreKit 验证结果，不新增额外承诺。多份权益并存时，有效终身不因另一份月订到期被锁定。

### 同步与撤销

- 购买、恢复、续期、宽限期、到期和退款对账后，即使班次没有改变，也必须发布新权益状态。
- 无权益时仍传递锁定更新；不能靠“停止同步”锁定，否则手表会保留旧授权。
- 生产者在没有有效授权时发送不含班次内容的锁定包；pending 若仍有另一份有效权益则保持授权。接收端先检查权益再读取缓存，序列化测试同时验证锁定包没有真实班次字段。
- Watch 主界面、组件 timeline、深链接和 iPhone 命令接收端均执行相应权益检查；手机自身免费计时操作不受 Watch 门槛影响。
- 时间线提前加入权益截止和快照截止的占位 entry；收到撤销后替换缓存并请求刷新。WidgetKit 的系统刷新并非即时，不能承诺退款瞬间清除所有表盘旧画面。
- 断网不等于无权益；离线不能即时得知退款或续订。到期未取得新验证结果时提示“请在 iPhone 上确认 Plus 状态”，不声称用户一定没有续费。
- 锁定不删除 iPhone 的排班、历史或已开启的云同步；Watch 本地旧快照不可被组件或快捷操作绕过门槛使用。

建议文案：“表盘组件与完整班次状态，包含在 Plus 中。请在 iPhone 上查看方案。”
不要写成「在手腕上看下班倒计时属于 Plus」：免费用户在智能叠放里已经看得到实时活动倒计时，这句话与用户的实际体验矛盾，既会招来退款，也属于商店文案准确性（2.3）风险。
组件只保留简洁图标／占位，点击进入说明页，不放价格或促销文字。先提供可靠的手动打开 iPhone 指引；任何跨设备跳转必须证明实际可用，不能假设可强行唤起 iPhone App。
全部新增 UI 文案进入 19 个 locale，价格继续由 StoreKit 提供。

## 4. 数据契约与时间正确性

### WatchSnapshotV1

沿用移动端计划的 salary-free 快照，并在 W0 固定以下字段语义和解码 fixture：

| 分组 | 必需语义 |
| --- | --- |
| 协议 | `schemaVersion`、来源世代、持久化单调 `revision`、`generatedAtMs`、`expiresAtMs` |
| 班次 | 当前有效 `segments`、`plannedEndAtMs`、`overtimeEndAtMs`、计时启停状态 |
| 状态边界 | 规则端生成的状态切换时间、下一班简要投影及其有效范围 |
| 呈现 | locale、显示所需的时区语义、本地化短文案、组件所需值 |
| 权益 | 同一发布包中的版本化权益投影，与班次有效期分开 |

- TypeScript 是排班、提醒、汇总和薪资规则的唯一实现。iPhone 经当前生成的 `CountdownRules.js` 生产投影；缺字段就扩展共享规则出口，不把排班算法移植到 Swift。
- Watch 只对已给定的绝对 segments 做渲染所需的比较与求和；剩余时间不能退回“结束时刻减现在”。所有算术用 TS 生成的差分 fixture 验证，包括午休和加班。
- iPhone 负责选择明确的快照有效范围，W0 固定并记录策略。Watch 不在有效范围以外推导新班次、轮休或节假日；睡眠跨过整班后不补发状态／通知。
- 同一世代拒绝旧 revision；来源重装、重新配对、换表和恢复备份时通过明确的新基线握手替换世代，不能永久拒收归零后的 revision，也不能让迟到旧包恢复旧授权。
  新世代只从当前配对会话的显式基线接受，握手标明替换的旧世代；持久化当前与退役世代，普通迟到数据包不能触发世代切换。W0 用重装／恢复／换表 fixture 验证这一流程。
- 校验有限数值、时间顺序、segments 有序且不重叠、载荷大小、版本与来源。损坏或不支持的包不覆盖有效缓存；没有有效缓存则安全空态。
- 权益和班次作为一致的发布包原子落盘，避免新到期状态与旧组件读取发生混搭。Watch App 和其 extension 只共享 Watch 侧容器；不读取 iPhone App Group。

## 5. 通信、组件与控制

`updateApplicationContext` 是最新完整快照的主通道；会话激活、重新可达、配对变化、iPhone 设置／班次／语言／权益变化和前后台对账均触发适当重发。正常后台不每秒发送。
Watch 保留最后有效快照，重启可读；iPhone 不可达仍可离线渲染，但不保证未来设置变更即时到达。

组件使用系统日期文本与预生成 timeline，覆盖午休、工作恢复、下班、加班结束、下一班和两种到期边界。
系统 timer 只用于语义相符的连续片段；不能为了秒数跳动而在午休继续扣减剩余工作时间。若系统表面无法准确连续呈现，则采用正确的分钟／状态粒度，在 W1 原型和实机中验收。
禁止自建每秒后台 Timer 或借用运动会话保活。

以下开始／停止控制协议保留为后续版本设计；3.2.0 明确不实现。未来启用前需独立确认范围并完成验证：

- 首版只允许可达时请求；不可达时明确提示稍后重试，不长期排队可能过时的开始／停止操作。
- 命令包含 `commandId`、来源世代、预期班次标识／revision、发出时间与有效截止；iPhone 校验当前 Plus、班次和命令时效，经过现有入口执行。
- ACK 区分成功、已处理、过期、状态冲突、无权益和失败，并返回权威快照／revision；回执前不把乐观显示落成事实。
- 去重必须跨重启保留合理时间；超时不表示未执行，先对账或复用同一 commandId 重试，不能生成新命令重复执行。
- 本计划不默认启用 `transferUserInfo` 排队控制；未来确有需求再增加有效期、去重与取消语义。首版不需要文件传输通道。

## 6. 实施阶段与退出条件

### W0 · 工程、权益与契约

- [x] 核实本机 Xcode／SDK、可用 Watch 型号，固定 watchOS 最低版本和支持矩阵；本计划不凭空填写未核实的版本。—— 2026-09-13：Xcode 26.6（17F113）、iOS／watchOS 26.5 SDK；工程最低 iOS 26.0、watchOS 26.0，即支持所有能运行 watchOS 26 的 Apple Watch。模拟器覆盖 Series 11 42mm 与 SE 3 40mm，真机为用户的 Apple Watch Ultra 2。
- [x] 在现有工程建立 Watch App 和 Widget Extension，记录实际 scheme、bundle id、companion 标识、签名、Watch App Group、嵌入关系与源文件归属。—— scheme `DoneAt Watch App`；`…macappstore.watchkitapp` 与 `…watchkitapp.widgets`，companion 为 `…macappstore`；两者签入 `group.com.rainif.offworkcountdown.macappstore.watch`；Watch App 嵌入 `App.app/Watch/`，组件在其 `PlugIns/`；源码在 `WatchApp`、`WatchWidgets`、`WatchAppTests`、`Shared`（显式引用）。
- [x] 明确 synchronized folder 与显式引用边界；不得将 iPhone 专用依赖或完整设置模型误编入 Watch。—— 见 `docs/XCODE-CLOUD.md`；`check:ios` 对 Watch 测试文件做 Sources 登记计数。
- [x] Watch 专属源码放在 iPhone `App/Native` 同步目录之外。核查现有 `check-ios-project.mjs` 的配置数量假设以及共享 WidgetSnapshot 的 iOS／macOS 条件分支，不能让新增 Watch targets 误走 macOS 代码或被旧检查误拒绝。
- [x] 固定 WatchSnapshotV1、权益投影、来源世代重建、revision、到期、缓存与解码限制，提供 TS → Swift 共用 fixture。—— 见第 10 节；fixture 20 组（2026-09-13 增至 20 组）。
- [ ] 建立可演示的免费／有效／过期／未知状态，验证恢复购买到 Watch 的最小闭环；未通过前不继续堆 UI。—— 状态演示已完成：配对模拟器上 DEBUG 注入的 7 步端到端通过，用户 Ultra 2 真机运行良好。仍缺真实 StoreKit（沙盒）恢复购买到 Watch 的实测记录，用户预期无问题但未实测。
- [x] 扩展 `check:ios`、版本检查和 Xcode Cloud 检查范围；记录签名待办，更新 `docs/XCODE-CLOUD.md`。具体两条先做，否则第一次构建前就会红：
  - `scripts/check-ios-project.mjs` 目前要求工程内**所有** `PRODUCT_BUNDLE_IDENTIFIER` 只能是 App、Widget、Tests 三者之一，多一个就 `fail`；新增 Watch App 与 Watch Widget 必然引入新 id，要先扩这份白名单。
  - `scripts/check-version.mjs` 已扫描工程内全部 `MARKETING_VERSION`，新增 targets 的显式版本值也会参与比对；需要补强的是每个预期 target／configuration 的覆盖完整性，避免漏配置或继承配置未被验证。

退出证据：配对模拟器构建成功、契约与权益测试通过，所有新 targets 的配置检查覆盖。尚未取得签名或真机不等于完成发布验证。

### W1 · Plus 只读倒计时

- [x] 完成 iPhone 生产者、Watch 接收缓存与主界面，覆盖所有班次状态及同步／锁定状态。—— 2026-09-13 用户确认在 Apple Watch Ultra 2 真机运行良好。
- [ ] 购买、恢复、续期和撤销独立触发权益同步；断连、重连、重启、旧包、坏包、未知版本和新世代有可复现行为。—— 后半句由契约、缓存、接收器与发布器测试覆盖；权益独立发布有测试。真实购买、恢复、续期、撤销触发未实测。
- [x] 跨午夜、午休、加班、轮休、时区／夏令时与睡眠跨班 fixture 通过。—— TS 生成的 20 组：午休冻结与边界、跨午夜、加班、春季与秋季夏令时、另一时区、整班睡过（转到下一班而不补记下班）、提前下班。休息日由 `WatchSnapshotComposerTests` 验证（不下发当天班次、保留下一班）；轮休是否为工作日由 TypeScript 规则及其测试决定，Watch 只消费绝对时段。
- [ ] 在实际 Watch 检查时间准确性、短暂离线、字体、VoiceOver 和低亮度；记录系统计时渲染的选型与限制。—— 用户在 Ultra 2 上确认整体运行良好；以上各项未逐条记录。
- [x] iOS 侧为实时活动加上 `.supplementalActivityFamilies` 的智能叠放呈现，并在真机确认免费用户抬腕所见；这一条不依赖 Watch App，可以独立发布。—— `.supplementalActivityFamilies([.small])` 已接入；2026-09-13 用户确认真机智能叠放显示正常。

退出证据：有效 Plus 的抬腕只读闭环稳定，免费用户无真实班次泄露，差分结果与 iPhone 一致。

### W2 · 表盘组件

- [x] 圆形／长方形组件具备完整 timeline、锁定占位、权益与快照到期处理，深链接回正确状态。—— 时间线含分钟条目、各规则边界及权益与快照两个截止点（`WatchDisplayProjectionTests`）；锁定、需确认、等待与过期有占位；`widgetURL` 打开 Watch App，由 App 按当前包重新判定锁定。2026-09-13 增加智能叠放相关性提示，见第 11 节。
- [ ] 小尺寸、AOD、实际支持的系统着色模式、长英文、简中、繁中、RTL 和辅助字号完成视觉检查。—— 2026-09-13 模拟器部分已做（见第 11 节）：SE 3 40mm 上英文、德文长文案、繁中、午休、休息日、锁定页与最大辅助字号均完整显示或按设计转为可滚动；RTL 发现方向问题并已修复、截图确认；简中与常亮在 42mm 上已查。真机小屏、表盘着色（accented）与真机常亮未查，保持未勾选。
- [x] 确认 3.2.0 没有开始／停止命令接收器、ACK、操作入口或对应商店承诺；控制按 018 决定延期。—— `check:ios` 拒绝组件中的 `ControlWidget`、`AppIntent` 与 `Button`。

退出证据：组件准确呈现且不会自建高频后台刷新；控制明确延期，只读 App 与两种组件进入 W3。

### W3 · 真机、签名与发布

- [ ] 至少覆盖一块支持 AOD 的 Watch 和一块较小屏幕 Watch，并由用户确认实际体验。
- [ ] 完成下方权益／连接矩阵，分别记录设备、OS、构建号、步骤、期望和结果；模拟器不能替代 StoreKit／WatchConnectivity 真机结论。
- [ ] 记录冷启动、前台／AOD 更新和代表性工作日耗电，与未运行 Watch 功能的同设备基线比较；不能仅凭模拟器宣称低功耗。
- [ ] Release archive 验证 iPhone、Watch App、所有 extensions 的嵌入、签名、App Group 与版本；原 iPad／iOS Widget／Live Activity 回归通过。—— 2026-09-13 本机 `App` scheme Release 归档并导出 App Store 包（未上传）：Watch App 与组件均嵌入，三者均为 Apple Distribution 签名、`get-task-allow` 为 false、App Group 正确。回归项与 Xcode Cloud 归档未完成。
- [ ] 核查 Watch App／extension 的隐私清单与实际所用 API 声明，检查归档后的签名 entitlements 和 Watch 共享容器；不只检查工程配置文本。—— 隐私清单：两者声明 FileTimestamp C617.1，Watch 源码只读取缓存文件的大小与类型，未直接调用时间戳 API，声明偏保守但无害，保留。归档后 entitlements 已核（见上一条）。真机共享容器未核。
- [ ] Plus 页、欢迎介绍、官网和 App Store 文案明确 Watch App 与表盘组件需 Plus，同时不暗示免费用户在手表上看不到任何东西；审核备注说明 companion 依赖、购买／恢复入口和测试路径，不设置隐藏审核绕过。—— App 内订阅页、欢迎页、What's New 与 Apple Watch 说明页已完成；官网、App Store 文案与审核备注未完成。
- [ ] 产出并上传 Apple Watch 商店截图（App Store Connect 的 `APP_WATCH_*` 槽位）。`scripts/marketing-shots/` 目前没有 watch 这一套，需要新建；按 2026-09-08 那条「截图覆盖 17 个商店语言」的决定先估工作量，若决定缩小语言范围，在本计划里记下这个决定和理由。
- [ ] Xcode Cloud archive 和 TestFlight 配对分发验证通过后再提交审核；沿用现有人工分发与签名约定，不新增未经确定的自动导出路径。

## 7. 必须覆盖的验收矩阵

| 维度 | 必测案例／结果 |
| --- | --- |
| 权益 | 免费、试用、月／年订、取消续费但未到期、宽限期、无宽限重试、到期、退款、终身、终身与订阅并存、家庭共享撤销、pending、不可信交易 |
| 恢复 | 新装／换表、恢复购买、iPad 已购买后配对 iPhone 恢复、查询失败、续订已发生但尚未同步；不能误导为确定无权益 |
| 离线 | 有效缓存继续、跨权益到期锁定、只跨快照到期显示同步说明、终身但班次过期、未知权益不自动放行 |
| 通信 | iPhone 前台／后台／系统终止／重启、蓝牙断开、Watch 仅 Wi-Fi、断网重连、重新配对、换表、未安装 companion |
| 一致性 | 乱序／重复／坏包／不支持版本、来源重建、旧授权晚到、权益变而班次不变、缓存原子写入中断 |
| 班次 | 午休冻结、加班、跨午夜、夏令时与时区变化、轮休／休息日、整班睡过、未设置排班与停止计时 |
| 组件 | 两种 family、冷启动／重启、AOD、权益截止 entry、快照截止 entry、撤销刷新延迟、深链接锁定检查 |
| 隐私 | 使用包含明显薪资哨兵值的输入，检查序列化载荷、缓存、日志、组件、预览和最终 Watch 包；不得包含薪资数据或完整个人记录 |

## 8. 开发检查与交付记录

- 文档计划阶段只做文档差异与链接检查，不把尚未实现的功能标为已测试。
- 实现阶段执行 `npm run check:version`、`npm run build:ios-native-rules`、`npm run check:ios`，并编译 iPhone 与配对 Watch 模拟器；W0 落定 scheme 后把实际可运行命令补入本节。
- 契约／状态／命令验收放入对应 Swift Testing target 与共享规则旁的 vitest；Watch 专属 target 的测试需实际运行，不用 iPhone 模型测试代替。
- 涉及 `lib/`、locales 或共享构建配置时，按 AGENTS.md 完成 lint、单元测试、Web build／验证、Desktop export／验证及 iOS 模拟器构建；先停止共用 `.next` 的开发服务。
- iPhone 新入口或购买回流有变化时，运行相关 iPhone／iPad 横竖屏、浅深色 QA 并人工查看；Watch 单独留下截图和实机验证记录。
- 不修改已批准的薪资隐私边界，不提交生成规则包、构建产物、签名材料或本地环境文件。
- 实施过程中更新本计划、`docs/PLAN-MOBILE.md` 和相关 Xcode Cloud 说明；未完成的 StoreKit 真机矩阵继续阻止发布，不阻止 W0 开工。

## 9. Apple 参考与开工核实项

Apple 文档支持 companion App 的通用内购；本项目采用 iPhone 购买、配对投影授权是工程选择。WatchConnectivity 和 WidgetKit 的投递／刷新由系统调度，因此本计划不承诺实时到账或即时移除旧画面。

- [Creating independent watchOS apps](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps/)
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [Keeping your watchOS app’s content up to date](https://developer.apple.com/documentation/watchos-apps/keeping-your-watchos-app-s-content-up-to-date)
- [App Review Guidelines，3.1.1／3.1.2](https://developer.apple.com/app-store/review/guidelines/)

参考检索日期：2026-09-08。W0 根据实际 SDK 再核实 target 配置、平台可用 API 和最低系统版本；W3 根据当时审核要求核实展示与恢复路径。文档依据不构成已通过审核的承诺。

## 10. W0 实施记录（2026-09-12，未整体验收）

已新增 [纯数据契约](../../src-mobile/ios/Shared/WatchSnapshot.swift) 及 iPhone AppTests 中的契约测试。契约文件位于 iPhone 同步源码目录之外，目前只显式编入 App；测试通过 `@testable import App` 使用同一实现，不重复编译一份模型。

已覆盖锁定包省略班次、未配置／停止空态、解码大小及结构限制、两个截止值、来源替换、包／权益版本倒退、同权益版本篡改授权、损坏排序元数据、重复投递及候选持久化失败后重试。排序器仅返回待保存状态。

新增 [原子缓存](../../src-mobile/ios/Shared/WatchSnapshotCache.swift)：独立 actor 在后台恢复缓存，将有效包与排序元数据放进同一个文件原子保存，成功后才替换内存。失败保留旧内存和文件、允许同包重试；重复和拒绝包不写文件。来源基线必须由显式配对边界提供，不能从包内自认。测试验证真实写入次数、旧来源迟到、损坏恢复及未知薪资字段不会持久化；通信生产者的完整薪资哨兵验收仍未完成。

[绝对 segments 计算](../../src-mobile/ios/Shared/WatchShiftEvaluation.swift) 只比较和求和；14 组 TypeScript bundle 生成的 fixture 覆盖午休冻结／恢复、跨午夜、夏令时、加班原下班边界及最终到点。`npm run check:watch-fixtures` 检查 fixture 新鲜度，已加入仓库的 Xcode Cloud 克隆脚本；这不代表远端 PR 工作流已经配置。

本机 Xcode 26.6 / 17F113 下，三个共享文件通过 watchOS Simulator 26.5 SDK 的 Swift 6 严格并发类型检查；完整 iPhone 测试为 **610 个、32 个 suite 通过**，详见 [018 本批验证记录](018-ios-3.2.0-architecture-remediation.md)。Watch 专属 target、Watch 实际运行、通信、权益生产者、UI、两种组件、19 locale 文案和真机仍未完成。未实现控制、ACK 或命令接收器；W0–W3 复选框保持未完成。

2026-09-13：018 已移除旧 Store，现有 Widget Composer 使用班次功能对象生成无薪资载荷，发布器只接收值；进程服务消费独立功能边界。完整 iPhone 回归增至 **618 个、33 个 suite 通过**。这为 Watch 生产者提供了接入位置，仍不代表 Watch 通信或目标交付完成；候选替换提交与启动收口继续依赖 018。


2026-09-13 后续：018 已建立功能命令的候选准入、后台归档和实际提交回执，修正启动重置及外部班次对账；完整 iPhone 回归 **637 个测试、38 个 suite 通过**。Watch 接入仍须从这些稳定功能边界生成独立载荷；W0 工程、配对通信、只读 App、两种组件与真机验收未因此完成。详见 [018 本批记录](018-ios-3.2.0-architecture-remediation.md)。

2026-09-13 接手：iPhone Watch 生产者的 WCSession 回复 block 编译错误已修复（至多回复一次的包装与可测试的代理入口），Watch 接收端的配对回复闭包改为 `@Sendable` 以避免 Swift 6 执行器检查崩溃，生产者发送字节改为确定性编码。iPhone 源码完整回归 **679 个测试、42 个 suite 通过**，其中发布器 10 个测试覆盖持久化、失败重试、权益独立发布、同输入零写入零发送、epoch 与迟到完成、代理 hello 生命周期及真实班次薪资哨兵。随后 watchOS 26.5 Simulator runtime 已就绪：shipping `App` scheme Release 模拟器构建通过，产物嵌入 Watch App 及其 Widgets，Watch AppIcon 编译进资源；WatchAppTests 发现并修复一个从未登记到目标的测试文件后，在 watchOS 26.5 模拟器实际执行 **4 个测试通过**。iPhone 与 Watch 模拟器配对后的实际通信、Watch App／组件运行与 timeline、`WatchSnapshotReceiver` 回调测试、签名归档、真机、AOD、耗电及商店素材仍未验收；W0–W3 复选框保持未完成。

2026-09-13 本机续做：在配对的 iPhone／Watch 模拟器上完成 WatchConnectivity 端到端验证，免费→锁定、终身→内容、过期→锁定、未知→无内容、订阅→内容、宽限→`active` 共 7 步全部通过（含 Watch App 关闭时下发与 Watch 重启保持配对），两端 generation／revision 一致、无薪资文本。首轮暴露并修复“手机重启后系统长期报告 Watch App 未安装导致 hello 回空、Watch 不重试”的问题：手机按最后记录的 Watch epoch 作答，Watch 有界前台重试。权益状态由仅 DEBUG 的注入项驱动，真实 StoreKit 恢复购买与 Ask to Buy 未在模拟器端到端验证。Watch 接收端现有注入测试，WatchAppTests 7 个通过。模拟器结论不代替 W1 的真机时间准确性、短暂离线、VoiceOver 与耗电验收；W0–W3 复选框保持未完成。详见 [018 本批记录](018-ios-3.2.0-architecture-remediation.md)。

2026-09-13 界面打磨：按 Apple HIG 与官方文档重做 Watch App 主界面、Plus 锁定页及圆形／长方形组件——数值带说明与单位，时间按排班时区与 App 语言显示，常亮只到分钟并调暗次要内容，锁定页按第 3 节文案说明 Plus 并保留“智能叠放实时活动免费”；9 个新文案覆盖 19 个 locale。已在 watchOS 26.5 模拟器上截图检查 17 个夹具状态及实时表盘。W1／W2 的真机、小屏、着色模式、辅助字号、RTL、VoiceOver 与耗电验收仍未完成。详见 [018 界面打磨记录](018-ios-3.2.0-architecture-remediation.md)。

2026-09-13 iPhone 端说明：设置新增 Apple Watch 说明页，明确区分免费的智能叠放实时活动（需打开锁定屏幕实时活动）与 Plus 包含的 Watch App 和表盘复杂功能，提供两步添加说明与隐私说明；订阅页权益、欢迎页正文和 3.2.0 What's New 同步体现 Watch，文案不暗示免费用户手表上看不到任何内容。W3 的官网与 App Store 文案、审核备注和 Watch 商店截图仍未完成。

## 11. 本机收尾记录（2026-09-13，未整体验收）

**用户真机确认**：Watch App 在用户的 Apple Watch Ultra 2 上运行良好；智能叠放里的实时活动显示正常。沙盒 StoreKit 购买用户预期无问题，尚未实测，因此 W0／W1 相关复选框保持未勾选。

**智能叠放相关性**：Watch 组件的 `TimelineProvider.relevance()` 返回当前班次时段（第一段开始至实际结束，并截断到快照与权益到期），`RelevantContext.date(interval:kind: .scheduled)`；锁定、需确认、过期、已下班或已停止时不提供时段。Watch 收到新包时除 `reloadTimelines` 外调用 `invalidateRelevance(ofKind:)`。这只是提示，排序与展示次数由 watchOS 决定；未使用位置等需要权限的线索。纯函数 `WatchDisplayProjection.relevantIntervals` 由 `WatchDisplayProjectionTests` 覆盖（首轮测试曾用超出快照到期的班次构造数据，该包本身无效，已改为验证过期包不提供时段）。

**班次 fixture**：由 17 组增至 20 组，新增夏令时秋季回拨（当天实际 9 小时）、另一时区（纽约）、整班睡过（转到下一班而不补记下班）。休息日与轮休的覆盖位置见 W1 第三条。

**隐私**：Watch App 与组件构建产物（含组件扩展与调试动态库）中未搜到 salary、earned、hourly、wage 等薪资字段；同一扫描能找到已知字符串作为正对照。隐私清单结论见 W3。

**小屏与视觉（Xcode 26.6／watchOS 26.5 模拟器）**：SE 3 40mm 上英文、德文长文案、繁中工作中、午休、休息日与锁定页截图检查，均无截断；锁定页在小屏超出高度时位于 `ViewThatFits` 的 `ScrollView` 分支内（该设备未授权交互，滚动由代码确认，42mm 上锁定页完整显示）。无内容时锁定页等提示按 Watch 系统语言显示，属设计行为。最大辅助字号通过模拟器系统设置验证：工作中与午休完整显示，锁定页转为滚动；`simctl ui content_size` 与启动参数在 watchOS 上不生效，截图后已恢复原设置。

**RTL 问题与修复**：Watch 两个 target 不声明 bundle 本地化（文案由脚本生成），系统语言为阿拉伯语时界面仍从左到右（进度条自左填充）。现改为让方向跟随文字所用语言：班次内容跟随包内 iPhone App 语言，提示与占位跟随 `WatchLocalizations` 解析出的 Watch 系统语言；新增 `WatchDisplayFormat.isRightToLeft` 及测试。修复后在 SE 3 40mm、系统语言阿拉伯语下截图验证：阿拉伯语班次内容的状态图标位于文字右侧、进度条自右填充，锁定页与休息日按阿拉伯语排版；同一系统下英文班次内容保持从左到右。截图后已恢复模拟器原语言设置（zh-Hans、en／zh_CN）。组件在表盘上的 RTL 呈现未在模拟器表盘中截图，依赖同一方向逻辑。

**仍未完成**：真实 StoreKit 恢复／购买／续期／撤销触发；真机时间准确性、短暂离线、VoiceOver、低亮度、小屏真机与表盘着色；耗电；Xcode Cloud 归档与 TestFlight；官网、App Store 文案与审核备注；Watch 商店截图。
