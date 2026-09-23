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
| Material3 | 当前页 stable 1.4.0，expressive 路线 1.5.0-alpha28；1.4 稳定线曾移除实验 Expressive API | D-12（2026-09-23）：Release 锁稳定 1.4.x，不用 alpha；Expressive 风格由 designsystem token 实现，官方 Expressive 稳定后再评估 [A01] |
| Compose BOM | 官方示例 `2026.09.00` | 稳定 BOM 为起点，显式覆盖 Material3；审查其传递依赖，不声称其他库一定仍稳定 [A20] |
| Billing | 官方接入示例 `billing-ktx:9.1.0` | 候选锁 9.1.0；不用已越正常截止线的 v7 新建工程 [A05], [A06] |
| AGP | 当前发布页给 9.4 的 Gradle 9.6.0 / JDK 17 / 最大 API 37 兼容信息 | M1 依据可用稳定渠道选择并记录，不把该表误当整个项目已兼容 [A19] |
| Kotlin / Compose compiler | 官方示例 Kotlin 2.4.10；编译器插件与 Kotlin 版本关联 | 与所选 AGP/内置 Kotlin、KSP 联合验证，不孤立升级 [A21], [A22] |

**技术探针必须先于业务开发**：空 Compose 页面 → 需要的 Expressive 组件/主题 → Room 生成 → 序列化 → BillingClient 初始化 → Glance 最小组件 → Debug 和 R8 Release 构建。记录实际 Gradle/JDK/AGP/Kotlin/Compiler/KSP/Compose/Material3/Room/Billing/Glance 版本和依赖树到 `docs/android/environment-lock.md`。

使用 AGP 9 内置 Kotlin 时，不再套用旧教程给 Android 模块重复应用 `org.jetbrains.kotlin.android`；`:core:domain` 纯 JVM 模块的插件另行配置。优先 KSP，不因旧 KAPT 示例复制出不兼容构建。[A22]

不要使用 `+`、`latest.release`、未经验证的 alpha BOM 或全局强制降级。Material3 的预发布依赖可能传递带入其他预发布库，`:designsystem` 隔离的是 API 使用边界，不是能神奇隔离最终 APK 的运行时依赖。负责人已按 D-12 选择稳定依赖：Expressive 设计语言用稳定 API + DoneAt 自有 shape/motion/color token 实现，记录在 `design-tokens-adr.md`；不是把 UI 改回未经设计的默认 Material3。[A01], [A20]

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
  core/billing/                # BillingClient、客户端签名校验、权益缓存（首发无服务端适配）
  core/sync/                   # 后续阶段（D-02 修订）：Drive transport、同步协调器；首发不创建
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

**iOS 独有规则**：扩展排班、记录编辑/冲突、专注细节、首次恢复等，源 Swift 与对应 Swift 测试是规范。新增 Swift→JSON 测试导出或等价手工测试映射；不能假称 TS oracle 覆盖了它们。导出的 JSON 是 Swift 与 Kotlin **共用**的检查：Swift 测试和 Kotlin 测试读同一份文件并有 stale 检查，这样 iOS 改规则时 Kotlin 会在 CI 中失败，而不是悄悄形成第三份无 oracle 的实现。[R04], [R06]

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

**D-13（2026-09-23）取代本节的 Room 部分**：记录与 iOS 一样保存在内存 `RecordState` + 一个原子替换的 JSON 文件（`RecordLocalFile`：schema-6 文档 + 墓碑），由 `:core:data` 的 `RecordStore` 串行写入。下文关于 Room 表、DAO、Migration 的要求不再适用；事务、失败不部分提交、损坏不自动删库等原则仍然适用。DataStore 仍用于本机显示偏好。

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
| 当次查询返回、签名校验通过的订阅 | 授予；首发不需到期时间，每次前台/启动重新查询 |
| 用户取消自动续费但未到期 | 仍有效到实际截止时间 |
| 宽限期（查询仍返回） | 继续授予 |
| Account hold / paused / expired（查询不再返回） | 停止订阅权益，不删数据 |
| 已验证非消耗型终身且未撤销 | 终身授权 |
| 退款/撤销 | 收到可靠证据后回收相应授权 |
| 网络或 Play 服务暂不可用 | 保留最后已验证缓存（订阅缓存设保守有效期，终身不过期） |
| 成功完整查询确认无权益 | 可替换旧缓存；必须区别于查询失败 |

Play 的 pending 生命周期不是 Apple Ask to Buy 的 24 小时规则。不能照搬 iOS 常量。客户端 Purchase 并不给出完整订阅到期语义，不可用 purchaseTime 加 30/365 天猜到期；首发也不需要：`queryPurchasesAsync` 只返回当前有效（含宽限期）的订阅与未撤销的非消耗商品，是首发的权益来源。[R05], [A06], [A08]

**首发（D-08 修订，2026-09-23）为纯客户端验证**，与 iOS `PlusEntitlement` 的纯客户端 StoreKit 对齐：用 Play Console 公钥校验 `originalJson`/`signature`，校验包名与商品 allowlist，客户端 acknowledge 并持久化待确认标记在 3 天窗口内重试。已知代价如实记录：退款/撤销在下一次成功查询时才生效；root 设备可篡改客户端判断。若后续出现明显盗版或需要实时撤销，再启动 9.3 的服务端阶段。

### 9.3 后续阶段：小型无 DoneAt 账号的权益验证服务（首发不做）

**D-08 修订**：本节保留为首发后的设计参考（T21）。届时优先放在现有 Next.js/Vercel Route Handlers（仓库已有 `app/api/` 路由），而不是新建 Ktor 服务。以下原文中的“已确认/可以开始”均指该后续阶段。

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

缓存已验证授权与来源、版本和时限，敏感 Token 使用 Keystore 支持的保护并排除备份；公钥验证不能被 Debug 分支覆盖。查询超时/服务断开不等于未购买。离线退款无法立即获知，应诚实接受“下一次成功验证后撤销”的边界，不能宣称永久离线与即时撤销同时保证。

调试 FakeBilling 只在 debug/test source set，release 不能通过 deep link、偏好、环境变量或导入文件解锁。管理订阅按钮仅对订阅用户存在；购买终身不会自动取消其已有订阅，需明确提醒并提供平台管理入口，不能诱导重复付费。

## 10. Android 私有同步方案（D-02 修订：首发后阶段）

**2026-09-23 修订**：首发不含 Drive 同步；换机恢复走第 11 章的系统备份/设备转移，跨平台走 v6 文件。本章保留为后续阶段（T22）的设计，章内“首发”字样均指该阶段。

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

Android Auto Backup 默认可能包含应用文件，所以“数据只在本地”不能靠未设置网络代码来保证。显式制定 fullBackupContent/dataExtractionRules，分别验证 cloud backup 与 device transfer 行为。[A16], [A28]

**D-02 修订（2026-09-23）：业务 Room 库纳入备份**，与 iOS 主数据随 iCloud 设备备份（仅 `LifeSummaryCache`、Watch 快照排除）的行为一致，使换机不丢记录。要求：

- 包含：业务库（`.db` 与同组 `-wal`/`-shm`，或在 BackupAgent 中先 checkpoint，二选一并以真机恢复验证）、需随用户迁移的 DataStore 偏好。
- 排除：购买/权益缓存、待确认购买标记、Keystore 相关数据、任何令牌、debug 设置、可重建的缓存与小组件投影。
- 恢复后首次启动：执行一致性检查与 Room 迁移，重建提醒/小组件，重新查询 Play 权益与系统权限，不从备份信任任何授权状态。
- 云端备份在 Android 9+ 且设备设有锁屏时由系统端到端加密；未设锁屏时不是。隐私说明如实写明这一条件，不笼统宣称“端到端加密”。每应用 25MB 上限；超限时系统跳过备份，需在帮助中说明并建议 v6 导出。

首发的跨设备数据传输是系统备份/设备转移与明确的文件导出；后续阶段加入用户同意的 Drive，同意前不向 Drive 传工资/经历。Keystore 保护密钥不保证导出的明文 JSON 自动加密；导出前直说这是含个人信息的文件，不能用“安全备份”暗示端到端加密。

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

新增独立 Android workflow；仍保持现有 Web/Desktop/iOS 检查通过，不改现有部署触发来方便 Android。

**基线漂移**：每个里程碑结束时运行 `git log --oneline <基线SHA>..origin/main -- lib src-mobile/ios/App/App/Native/Models src-mobile/ios/Shared`，把影响已移植规则的提交登记到 `docs/android/progress.md`，决定跟进或推迟后再推进基线 SHA；不静默跟随 main。新增 fixture 生成器应只输出新 Android fixtures 或明确共享产物，不更改线上规则作为“适配”。

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
- **A28** · [Android Auto Backup 排除规则](https://developer.android.com/identity/data/autobackup)
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
[A28]: https://developer.android.com/identity/data/autobackup
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
