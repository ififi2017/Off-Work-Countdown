# 017 · Apple Watch：Plus 抬腕倒计时与表盘组件

- **状态**：TODO — 2026-09-08 用户确认产品边界；尚未开始实现。
- **目标**：Plus 用户抬腕即可看到准确的班次状态、剩余工作时间和进度，短暂离开 iPhone 后仍可使用有效快照。
- **依赖**：[006 权益模型](006-free-trial-subscription.md)、[移动端架构与 W0–W3](../docs/PLAN-MOBILE.md)、当前 TypeScript 规则和原生 iOS App。
- **范围**：同一产品中的 iPhone companion watchOS App、Watch Widget Extension、WatchConnectivity、Plus 权益投影与发布验收。
- **交付方式**：feature branch → PR → main；本计划不代表授权上传或发布版本。各阶段全部保持未验收，完成时附实际证据。

## 1. 已确认的产品决定

1. Apple Watch 整套体验属于 Plus：真实倒计时、班次进度、表盘组件和获准交付的快捷操作均需有效权益。
2. 免费用户可以安装、打开 Watch App，看到简短功能说明和回到 iPhone 查看 Plus 方案的指引；不提供免费基础倒计时。
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
| 免费／到期页 | Plus 说明或到期说明、iPhone 操作指引 | 不显示真实班次值；不自动弹出购买流程 |
| 同步状态 | 首次等待、已同步、数据过期、暂不可达、版本不兼容 | 不把等待权益确认写成“你尚未购买” |
| 轻量控制 | W2 实测通过后交付开始／停止计时 | 不作为只读首版发布的必需项；必须有确认回执 |

非工作日“今天也上班”和加班延长列为后续增强；首版不做完整排班编辑、薪资、记录／人生、专注计时、独立云同步、Watch 购买页、独立通知调度或自定义常驻后台计时。
现有 iPhone 通知的系统镜像不加 Plus 门槛，不在 Watch 重复预约提醒。
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

建议文案：“在手腕上查看下班倒计时，包含在 Plus 中。请在 iPhone 上查看方案。”
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

开始／停止控制仅在 W1 同步可靠后启用：

- 首版只允许可达时请求；不可达时明确提示稍后重试，不长期排队可能过时的开始／停止操作。
- 命令包含 `commandId`、来源世代、预期班次标识／revision、发出时间与有效截止；iPhone 校验当前 Plus、班次和命令时效，经过现有入口执行。
- ACK 区分成功、已处理、过期、状态冲突、无权益和失败，并返回权威快照／revision；回执前不把乐观显示落成事实。
- 去重必须跨重启保留合理时间；超时不表示未执行，先对账或复用同一 commandId 重试，不能生成新命令重复执行。
- 本计划不默认启用 `transferUserInfo` 排队控制；未来确有需求再增加有效期、去重与取消语义。首版不需要文件传输通道。

## 6. 实施阶段与退出条件

### W0 · 工程、权益与契约

- [ ] 核实本机 Xcode／SDK、可用 Watch 型号，固定 watchOS 最低版本和支持矩阵；本计划不凭空填写未核实的版本。
- [ ] 在现有工程建立 Watch App 和 Widget Extension，记录实际 scheme、bundle id、companion 标识、签名、Watch App Group、嵌入关系与源文件归属。
- [ ] 明确 synchronized folder 与显式引用边界；不得将 iPhone 专用依赖或完整设置模型误编入 Watch。
- [ ] Watch 专属源码放在 iPhone `App/Native` 同步目录之外。核查现有 `check-ios-project.mjs` 的配置数量假设以及共享 WidgetSnapshot 的 iOS／macOS 条件分支，不能让新增 Watch targets 误走 macOS 代码或被旧检查误拒绝。
- [ ] 固定 WatchSnapshotV1、权益投影、来源世代重建、revision、到期、缓存与解码限制，提供 TS → Swift 共用 fixture。
- [ ] 建立可演示的免费／有效／过期／未知状态，验证恢复购买到 Watch 的最小闭环；未通过前不继续堆 UI。
- [ ] 扩展 `check:ios`、版本检查和 Xcode Cloud 检查范围；记录签名待办，更新 `docs/XCODE-CLOUD.md`。

退出证据：配对模拟器构建成功、契约与权益测试通过，所有新 targets 的配置检查覆盖。尚未取得签名或真机不等于完成发布验证。

### W1 · Plus 只读倒计时

- [ ] 完成 iPhone 生产者、Watch 接收缓存与主界面，覆盖所有班次状态及同步／锁定状态。
- [ ] 购买、恢复、续期和撤销独立触发权益同步；断连、重连、重启、旧包、坏包、未知版本和新世代有可复现行为。
- [ ] 跨午夜、午休、加班、轮休、时区／夏令时与睡眠跨班 fixture 通过。
- [ ] 在实际 Watch 检查时间准确性、短暂离线、字体、VoiceOver 和低亮度；记录系统计时渲染的选型与限制。

退出证据：有效 Plus 的抬腕只读闭环稳定，免费用户无真实班次泄露，差分结果与 iPhone 一致。

### W2 · 表盘组件与可选控制

- [ ] 圆形／长方形组件具备完整 timeline、锁定占位、权益与快照到期处理，深链接回正确状态。
- [ ] 小尺寸、AOD、实际支持的系统着色模式、长英文、简中、繁中、RTL 和辅助字号完成视觉检查。
- [ ] 用真机决定开始／停止是否交付；若交付，补齐 ACK 丢失、重复、乱序、超时、过期、冲突和手机重启测试。
- [ ] 若控制体验不可靠，在计划中明确记为首版延期，移除相关入口和商店承诺，只读 App 与两种组件仍可进入 W3。

退出证据：组件准确呈现且不会自建高频后台刷新；控制项有“验收通过”或“明确延期”的结论。

### W3 · 真机、签名与发布

- [ ] 至少覆盖一块支持 AOD 的 Watch 和一块较小屏幕 Watch，并由用户确认实际体验。
- [ ] 完成下方权益／连接矩阵，分别记录设备、OS、构建号、步骤、期望和结果；模拟器不能替代 StoreKit／WatchConnectivity 真机结论。
- [ ] 记录冷启动、前台／AOD 更新和代表性工作日耗电，与未运行 Watch 功能的同设备基线比较；不能仅凭模拟器宣称低功耗。
- [ ] Release archive 验证 iPhone、Watch App、所有 extensions 的嵌入、签名、App Group 与版本；原 iPad／iOS Widget／Live Activity 回归通过。
- [ ] 核查 Watch App／extension 的隐私清单与实际所用 API 声明，检查归档后的签名 entitlements 和 Watch 共享容器；不只检查工程配置文本。
- [ ] Plus 页、欢迎介绍、官网和 App Store 文案明确 Watch 需 Plus；审核备注说明 companion 依赖、购买／恢复入口和测试路径，不设置隐藏审核绕过。
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
