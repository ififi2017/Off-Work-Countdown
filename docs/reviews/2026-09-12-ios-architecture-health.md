# iOS 代码结构、健康度与扩展性审查

审查日期：2026-09-12。基线：`611e7a5`。范围为 `src-mobile/ios`，并检查共享规则入口、Widget 合约引用、构建配置和测试配置。只做审查，没有修改产品代码。原有三个计划文件的工作区修改未动。

**结论：已经有明显的“屎山化”倾向，主要集中在应用协调和状态管理层；整体仍有可用的边界和修复基础。现在适合做有针对性的职责拆分，继续把新需求塞进同一个 Store 会明显增加回归成本。没有理由整体重写。**

这里的判断依据是职责交叉、变更传播、持久化成本和测试边界，文件行数只作辅助证据。文中的“高／中”是维护优先级，不代表已经复现了对应严重程度的线上故障。

## 规模与增长

统计使用物理行数，包含空行、注释和 DEBUG 代码；不计目录外共享 Swift 文件、TypeScript 和生成的 JavaScript。

| 范围 | Swift 文件 | 物理行数 |
| --- | ---: | ---: |
| iOS 目录全部 | 158 | 59,048 |
| 产品代码，含 Widget、排除 AppTests | 120 | 44,590 |
| Native/Models | 42 | 20,200 |
| Native/Views | 62 | 18,807 |
| Native/Services | 9 | 2,599 |
| Native/DesignSystem | 5 | 1,836 |
| AppTests | 38 | 14,458 |

`OffWorkStore.swift` 有 7,512 行，连同 6 个扩展文件共 8,562 行，约占 iOS 目录产品代码的 19.2%。主文件有 339 个按声明缩进统计的方法，约 522 行处在 DEBUG 条件块中。因此，大文件并非主要由截图工具代码撑大。

62 个 View 文件中有 52 个直接引用 `OffWorkStore`，10 个直接读取 `records.state`。这**不表示所有 Store 属性变化都会让全部 View 重绘**；Observation 能追踪具体属性。问题在于依赖接口过宽，以及部分消费者实际观察了整份 `state` 或通用 `revision`。

按 Git 历史各日期末的提交取样，Store 主文件从 2026-08-28 的 1,902 行，增长为 09-01 的 5,669 行、09-05 的 6,446 行、09-08 的 7,345 行和当前的 7,512 行。最近 30 个触及 iOS 的非 merge 提交中，13 个触及 Store 或其扩展。新增功能能解释代码总量增长，但持续向同一协调点集中是风险信号。

## 优先处理的问题

### 1. 高：OffWorkStore 已经成为全应用的业务和界面中枢

证据：[Store 定义与依赖](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/OffWorkStore.swift:196)、[导航路径](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/OffWorkStore.swift:338)、[设置变更入口](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/OffWorkStore.swift:3328)、[付费后动作分派](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/OffWorkStore.swift:5246)、[专注计时生命周期](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/OffWorkStore.swift:7171)。

同一个类型拥有导航、付费弹窗、引导流程、UserDefaults、班次会话、设置提交、记录查询、Life 计算与缓存、Focus 计划与运行状态、同步后的恢复和通知调度。`applyScheduleChange` 同时涉及当前班次覆盖、持久化排班、当天记录投影和 Focus 重排，已经很难只理解其中一个功能就安全修改。

已有的 `OffWorkStore+Focus…` 文件改善了阅读定位，但它们仍是同一个类型，共享状态和依赖，尚未形成职责隔离。`LifeSummaryCache` 甚至依赖 Store 内部定义的 `LifeViewModelCacheKey`，显示计算契约还留在应用中枢中。

影响：增加跨功能需求时需要理解过多上下文，测试经常要构造完整 Store，独立开发和后续增加新的入口会更困难。

建议：先抽出实际拥有状态和行为的 Focus 运行／计划对象，以及应用导航状态；再将 Records 查询与 Life 派生模型逐步移出。保留一个很薄的应用组合入口，按调用方向传入班次快照、记录接口和动作。不要仅把 7,512 行平均分装进更多 extension，也不用立即建立多套 Swift Package 或通用架构框架。

### 2. 高：普通设置操作的成本随着整份历史档案增长

证据：[设置属性的持久化副作用](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/OffWorkStore.swift:531)、[同步偏好入口](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/OffWorkStore.swift:6241)、[偏好入库](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/RecordCoordinator.swift:447)、[完整档案写入](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/RecordCoordinator.swift:1770)。

真实调用链是：设置赋值 → `didSet` → UserDefaults → `upsertSyncedPreferences` → 整份 `RecordState` 导出 JSON → 再解码校验 → 包装后再次编码 → 原子写盘。`RecordCoordinator` 隔离在 MainActor，这些同步步骤直接占用主线程。即使没有启用云同步，本地同步偏好仍会写入记录档案。

`applyScheduleChange` 连续给多个字段赋值，当前没有包在现有的 `withBatchedWrites` 中；修改多个设置可能执行多轮整档案保存。`upsertSyncedPreferences` 也没有业务内容相同则跳过的检查。部分 Focus 模板操作已经正确使用批量写入，说明仓库内已有可复用的改进路径。

影响：倒计时本来是轻量工具，但随着多年记录和专注历史积累，切换主题或修改排班也会承担历史数据的编码和校验成本。本次现有 `RecordsPerformanceTests.diskCost` 串行运行中，520 天档案的一次观察记录写入为 18.3 ms，2,600 天档案为 90.0 ms；两者分别含 1,040 和 5,200 条初始观察记录。该测试直接验证了同一完整档案保存路径的增长成本，但并非设置操作的单独基准，也不是目标真机帧耗时。

建议顺序：先合并一次用户操作中的偏好变更，跳过无变化写入；批量提交后只发一次变更通知。保留损坏档案保护、导入校验和原子写入。随后根据实际磁盘测量决定是否引入独立串行持久化执行器或增量存储；异步化时必须保留写入顺序与失败语义，不能只给现有方法外包一层 `Task`。

### 3. 中：通用 revision 混合了业务数据变化和同步元数据变化

证据：[同步元数据更新也增加 revision](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/RecordCoordinator.swift:464)、[记录页加载签名](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RecordsDesignView.swift:888)、[系统服务更新签名](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RootView.swift:255)、[Life 刷新触发器](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/LifeSummaryRefreshModifier.swift:8)。

保存同步状态、修改偏好、修改 Focus、修改记录都会推动一个通用版本号。记录页加载、日解析缓存、系统服务调度和 Life 刷新都依赖它，导致无关变化也进入这些路径。

Life 已用内容键避免每次重新计算几十年数据，这是有效补救；但触发刷新后仍需建立并比较包含多组历史数组的键，其他以通用 revision 为键的缓存则直接失效。因此不能把问题简单描述为“每次都重算全部 Life”，实际问题是失效边界过宽。

建议：在记录提交点区分少量明确的变更域，例如排班／历史、Focus、偏好、同步元数据。让系统服务观察它实际发布的数据，让记录计算只观察它实际需要的输入。先解决已有的误触发，不建设通用事件总线。

### 4. 中：应用服务生命周期写在 RootView 中，难以完整验证

证据：[启动编排](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RootView.swift:110)、[更新标志](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RootView.swift:17)、[服务调度](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/RootView.swift:442)。

RootView 除了装配导航和界面，还安排 StoreKit、CloudKit、班次恢复、Focus 模板恢复、Widget 发布、通知和 Live Activity。触发条件分散在启动 task、多组 `onChange`、scenePhase 和日期通知中，通过 `isLaunching`、`pendingReschedule`、`serviceTask` 和版本标记协作。

这里已经有认真处理顺序和取消的代码；风险是下一项功能仍要手动接入这套时序。`ServiceConcurrencyTests` 能验证通知和 StoreKit 的服务内部竞态，却没有覆盖 RootView 如何串起这些服务。缺少的是应用协调层测试，不能用增加普通模型测试替代。

建议：将现有生命周期编排移入可直接驱动的应用服务协调对象，View 只转交启动、前台／后台和已提交变更。对“启动一次”“连续设置编辑后进入后台”“同步替换当前 Focus”“旧发布被新状态取代”建立少量集成测试。保持现有服务内部的序列化保护。

### 5. 中：记录类型扩展依赖多处手工映射，部分遗漏不会编译报错

证据：[记录类型集合](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/RecordJSON.swift:4)、[运行时类型判断提取身份和版本](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/RecordJSON.swift:806)、[同步身份映射](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Models/RecordsSyncAdapter.swift:175)。

新增一种记录需要同步维护本地状态、JSON DTO、导入、删除、冲突、同步身份／载荷和显示文案。有限类型的穷举 switch 本身合理，但 `identityKey`、`editCount`、`tieBreaker` 接受 `some Equatable` 后做运行时类型判断，遗漏类型会退回 nil、0 或默认 tie-breaker，编译器无法检查完整性。

影响：新类型可能能够编译、能够保存，却在导入或冲突处理中使用错误的身份／版本元数据。这是当前扩展机制的风险，并非声称已有十种类型存在对应错误。

建议：复用已有 `RecordIncomingValue` 做穷举提取，或让现有多种记录实现一个很小的身份／编辑戳契约。集中这三项元数据，并用覆盖全部实体类型的导入、导出、删除和冲突往返测试约束新增类型。没有必要重写整个 CloudKit 同步层。

### 6. 中：平台适配存在高维护成本的特殊路径，测试门禁也需要明确

证据：[运行时替换宿主方向方法](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/AppDelegate.swift:180)、[横屏额外窗口](/Users/zhengyuxuan/Off-Work-Countdown/src-mobile/ios/App/App/Native/Views/PhoneLandscapePresentation.swift:47)、[GitHub CI](/Users/zhengyuxuan/Off-Work-Countdown/.github/workflows/ci.yml:1)、[Xcode Cloud 配置说明](/Users/zhengyuxuan/Off-Work-Countdown/docs/XCODE-CLOUD.md:9)。

手机横屏通过额外 UIWindow 覆盖原界面以保存编辑状态，方向策略还会对运行时宿主类做 method swizzling。这些实现有具体缘由，也包含无障碍和窗口所有权保护；不过它们是系统升级、弹窗与方向交互时需要重点回归的适配债务。不能把三个平台导航壳的存在本身判定为重复设计。

仓库共有 509 个 `@Test` 声明，但这不是覆盖率。GitHub 工作流中没有 iOS 构建／测试 job；仓库文档描述的 Xcode Cloud 工作流主要是 main 分支 Archive 与 TestFlight 分发。本次没有读取线上 App Store Connect 工作流，不能据此断言线上没有另配测试；可以确定的是仓库可见配置不足以证明每个 PR 都经过 iOS 测试。

建议：明确并执行 PR 级 iOS 编译与核心自动化测试门禁，性能测试按仓库要求串行执行并检查真实运行数量。导航与方向适配需要在发布检查中保持覆盖；本次未做模拟器视觉检查。

## 值得保留的基础

- **规则共享边界有效。** Swift 通过 CountdownRules 消费生成规则，日解析器接收已经展开的 segments；不应因 JavaScriptCore 桥接存在就建议再写一套 Swift 排班／薪资规则。
- **已经有真实的纯模型。** `DayRecordResolver`、`FocusPlanner`、`LifeViewCalculator`、画布模型和部分 Live Activity 决策可独立理解和测试。可以沿这些边界继续拆解。
- **数据保护不是空白。** RecordCoordinator 有损坏档案阻写、隔离备份、候选状态导入和原子写入；同步有编辑戳、删除标记、代际隔离和冲突保留。不能为了“删代码”抹掉这些行为。
- **并发已有防护。** 工程使用 Swift 6、MainActor 默认隔离和 Approachable Concurrency；重计算有后台执行路径，通知／权益有取消和新旧请求顺序测试。不是一堆无保护的全局异步任务。
- **测试基础相当可观。** 38 个测试文件覆盖夜班、时区、记录层优先级、导入冲突、专注生命周期和性能测量；后续拆分可以用现有测试保住行为。
- **原生依赖克制。** Xcode 工程的 packageReferences 为空，未见为了状态管理或页面路由堆叠第三方 Swift 框架。

## 扩展性判断

| 下一类变化 | 当前扩展性 | 主要原因 |
| --- | --- | --- |
| 新增一个展示组件或复用既有快照的页面 | 中上 | 已有设计系统、模型和共享渲染组件 |
| 调整排班、记录、Focus 之间的联动 | 偏低 | 共同依赖大 Store，提交副作用分散 |
| 新增一种持久化／同步记录 | 中下 | 多处映射与冲突行为必须同步维护 |
| 多年历史数据增长 | 偏低 | 完整档案编码、校验、写盘和粗粒度失效 |
| 增加独立系统入口或新设备界面 | 中下 | 纯规则可复用，应用协调仍携带导航和 UI 状态 |
| 维护既有核心计算 | 中上 | 单一规则来源、值模型和回归测试可继续利用 |

最划算的顺序是：**先减少重复写入和无关失效，再拆 Focus／导航／应用服务协调，随后集中记录元数据契约并补齐协调层门禁。** 拆分成功的标准是一个功能的修改不再必须触碰多个无关领域，而不是文件变短或目录变多。

## 本次验证

- `npm run check:ios`：通过。
- `npm run check:version`：通过，产品版本一致为 3.1.9。
- `npm run build:ios-native-rules`：已从当前 TypeScript 重新生成规则资源。
- Xcode 26.6、iOS 26.5 的 iPhone 17 Pro 模拟器：编译成功，使用 `-parallel-testing-enabled NO` 运行完整测试目标；测试汇总明确报告 **509 个测试、14 个 suite 全部通过**，测试运行用时 23.933 秒。没有仅凭 xcodebuild 退出码判断通过。构建／测试日志未检出 `warning:` 或 `error:`。
- 未执行 Release 归档、线上 CloudKit／StoreKit 联调或模拟器视觉检查。本报告不把源码规模当作性能实测，也不将测试数量等同于覆盖率。

现有性能测试的本次单次读数如下，仅用于说明这台开发机上的增长趋势，不是多轮中位数或真机指标：

| 档案操作 | 520 天档案 | 2,600 天档案 |
| --- | ---: | ---: |
| 导入 | 30.0 ms | 151.6 ms |
| 写入一条观察记录 | 18.3 ms | 90.0 ms |
| 接收并保存 20 条远端记录 | 23.8 ms | 112.8 ms |
| 重新打开档案 | 16.4 ms | 84.7 ms |

记录页侧的缓存路径表现较好：一年日解析缓存命中 0.2 ms，一个月相邻班次日格构建 7.3 ms，单日画布 3.7 ms；Life 冷准备约 2,201.2 ms，缓存命中 0.6 ms。Life 冷准备包含异步工作，这个数字不能当作主线程阻塞时长。它同时说明现有缓存优化有价值，应保留并改善失效边界。

原始证据：[构建和测试日志](/private/tmp/owc-ios-architecture-audit-tests.log)、[Xcode 测试结果](/private/tmp/owc-ios-architecture-audit-tests.xcresult)。
