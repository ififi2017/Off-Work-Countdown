# 三个 Swift Skill 的适用性审查

日期：2026-09-06。范围：iOS 并发服务、AppTests、记录持久化与同步边界。

初次审查仅基于源码，以下问题按当时行号记录，不代表已观察到线上故障。用户确认后已实施整改，结果见文末「实施与验证」。保留工作区已有的 project.pbxproj 修改及其他审查文档。

## 结论

| Skill | 当前适用程度 | 建议 |
| --- | --- | --- |
| Swift Concurrency Pro | 高 | 优先检查 await 前后所有权、系统副作用的顺序、任务生命周期 |
| Swift Testing Pro | 高 | 用可控异步依赖覆盖真实服务时序，消除 yield 等待和断言后越界 |
| SwiftData Pro | 当前低，未来有条件适用 | 项目没有 SwiftData 模型；先量真实持久化成本，再决定是否需要查询层 |

本机工具链为 Apple Swift 6.3.3；工程使用 Swift 6 语言模式及 approachable concurrency，App 有 MainActor 默认隔离，Widget 和测试目标未声明相同默认隔离。不能把 App 的推断隔离直接套到另外两个目标，也不需要把 SWIFT_VERSION 写成工具链版本 6.3.3。

## 1. P1：NotificationService 的 generation 没有约束已提交的系统写入

位置：`src-mobile/ios/App/App/Native/Services/NotificationService.swift:178`、`:236`、`:255`、`:281`。

对应规则：actor 重入；取消是协作式的；系统副作用不能只靠完成后的本地状态检查保护。

`reschedule` 在 add 前检查 generation，却没有把 add 与 clear 串行化。允许的交错是：

1. 旧排班 A 提交 `center.add`，随后挂起。
2. 用户停止计时，clear B 增加 generation，读取并清理当前请求后返回。
3. A 的系统写入才完成。后续 generation 检查能阻止继续循环，却不能撤销这次写入。

普通提醒和 Live Activity 结束兜底均有这个窗口。快速改排班也可能让旧写入覆盖使用相同 identifier 的新请求。当前 `clearShiftNotifications` 的 generation 检查保护了清理本身，但没有覆盖另一方向的在途写入。

最小整改方向：借鉴同项目 LiveActivityService 的操作尾任务，让 shift 通道的 add/remove 共享顺序；保留 generation 淘汰旧意图，并在入队时确定所有权。开始实际操作时重新获取适当的当前时间。不要在旧 add 返回后盲目按稳定 identifier 删除，因为该 identifier 可能已归新排班所有。

```swift
// Before：两个入口可交错调用系统 API
try await center.add(request)

// After：结构示意，两个入口共用同一操作队列
let previous = pendingOperation
let task = Task { @MainActor in
    await previous?.value
    guard generation == scheduleGeneration else { return }
    await performShiftOperation()
}
pendingOperation = task
await task.value
```

这不是可直接粘贴的完整补丁：还需把现有 reschedule/clear 的操作体纳入同一队列，并检查失败和取消路径。前置读取后的 generation 检查也应放在任何删除操作之前。

验收：注入可暂停 add 的通知依赖，覆盖「旧 add 挂起 → stop → 放行旧 add → 最终无提醒」及「A → B 快速重排 → 最终仅 B」。测试必须控制实际副作用完成顺序，不能只测试 generation 比较函数。

## 2. P1：PlusEntitlement 的旧刷新结果可以覆盖新权益

位置：`src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift:353`、`:479`。

对应规则：await 后重新验证状态所有权。

Transaction.updates、订阅状态 updates、购买成功和 restore 都可触发 `refreshFromStore`。它们等待 `fetchStoreKitEvidence` 后直接更新授权、活动订阅标志和缓存，没有刷新序号。旧请求若先读到空权益、后返回，就可能覆盖购买后已经落地的新权益；同理可能用旧授权覆盖新的撤销结果。MainActor 保证同步片段互斥，不保证整个 async 方法完成顺序。

```swift
// Before
let fetched = await fetchStoreKitEvidence()
// 直接更新 authorization / cachedSnapshot

// After：最小所有权保护示意
refreshGeneration &+= 1
let generation = refreshGeneration
let fetched = await fetchStoreKitEvidence()
guard generation == refreshGeneration, !Task.isCancelled else { return }
// 再更新 authorization / cachedSnapshot
```

还应在 stop 时失效化旧刷新；所有状态写入都必须位于校验之后。该策略防止旧调用迟到覆盖，不承诺 StoreKit 返回的数据本身具有服务器版本顺序。

验收：注入证据获取闭包，强制 A 开始、B 开始、B 返回授权、A 返回空结果，确认授权与持久化缓存都保留 B；反向覆盖撤销，并覆盖 stop 时请求尚未完成。目前 PlusEntitlementTests 主要测试纯决策函数，不能证明服务完成顺序正确。

## 3. P2：FocusPlannerTests 用 yield 猜测异步工作已完成

位置：`src-mobile/ios/App/AppTests/FocusPlannerTests.swift:268`、`:297`。

对应规则：等待实际完成条件，而不是给调度器固定次数的机会。

两个 Live Activity 测试在 schedule/advance 后调用一到两次 `Task.yield()`，随即读取 sleepers 和 fired。yield 不保证被测任务已进入 sleep，也不保证唤醒后的 action 已完成；调度不同会造成误报。Apple 明确说明执行器可能直接恢复同一个任务：[Task.yield](https://developer.apple.com/documentation/swift/task/yield%28%29)。

```swift
// Before
clock.advance(to: boundary)
await Task.yield()
await Task.yield()
#expect(fired == [boundary])

// After：测试夹具新增明确的就绪/完成握手
await clock.waitUntilSleeping()
clock.advance(to: boundary)
await actionCompleted.wait()
#expect(fired == [boundary])
```

示意中的等待器需要用测试本地 continuation/stream 实现，处理先发生后等待、取消和清理；替换场景还需确认旧任务已退出。为异步测试设置合理 timeLimit。单独套 confirmation 不会自动等待，增加 yield 次数或固定 sleep 都不是修复。

## 4. P2：RecordsDayCanvasModelTests 的前置断言失败后仍可能越界

位置：`src-mobile/ios/App/AppTests/RecordsDayCanvasModelTests.swift:240`、`:265`。

对应规则：后续操作依赖的前置条件使用 #require。

```swift
// Before
#expect(sleep.count == 1)
#expect(sleep[0].source == .sleepEstimate)

// After：测试函数相应标为 throws
try #require(sleep.count == 1)
let interval = try #require(sleep.first)
#expect(interval.source == .sleepEstimate)
```

workIntervals 的 count 检查后直接读取 [0]/[1] 也是同类问题。应保留长度断言的语义，同时让前置条件失败终止当前测试，避免普通模型回归升级为测试进程崩溃。

## 5. 测量缺口：当前性能基准没有覆盖真实存盘成本

位置：`src-mobile/ios/App/AppTests/RecordsPerformanceTests.swift:14`、`src-mobile/ios/App/App/Native/Models/RecordCoordinator.swift:1599`。

测试创建 `RecordCoordinator.inMemory()`，而 writeArchive 在 fileURL 为 nil 时立即返回。生产路径在 MainActor 上执行全量 JSON 导出、反向解码验证、外层编码及原子写盘。因此现有图表性能测试无法回答「随着档案增大，编辑或同步落盘是否造成卡顿」。这是测量缺口，尚无证据认定用户已遇到卡顿。

建议新增独立的临时文件测量场景，固定日期和数据规模，使用单调时钟，测单条编辑、同步批次、导入及重新打开；同时验证重开后数据正确，结束清理文件和 defaults。保留现有内存基准用于计算与渲染成本。先获得设备上的测量结果，再选择批量写入、移出主 actor 或 SwiftData 查询层；异步落盘必须保留持久化成功后再确认导入/同步的契约。

## SwiftData Pro 的边界

源码扫描没有发现实际的 import SwiftData、ModelContainer、ModelContext、@Query 或 @Model 声明；只有延后映射的说明。当前是值类型 + JSON 档案 + CKSyncEngine 旁路同步。plan 002 的 P0A 实施记录也明确延后 SwiftData 查询层。

因此不应为使用新 Skill 而把 JSON 换成 SwiftData，更不应切回 SwiftData 自动 CloudKit 镜像。若测量证明需要引入，Skill 可用于审查 schema/migration、显式保存、关系删除规则、查询及 actor 边界；仍需保留版本化 JSON、逻辑身份、删除墓碑、同步 outbox 的持久化一致性及 TypeScript 规则单一来源。

## Skill 本身需要校验

本地 swift-concurrency-pro 的 `references/testing.md` 错称给 suite 添加 serialized 只影响其中的参数化测试。Swift Testing Pro 的说明与 Apple 文档一致：suite 内普通测试与子 suite 也会串行执行，但不阻止无关 suite 并发。不要把前者照搬为项目规则：[Apple：Running tests serially or in parallel](https://developer.apple.com/documentation/Testing/Parallelization)。

RecordsCloudSync 已有 MainActor 隔离，delegate 在访问可变状态前切回 MainActor；仅凭 `@unchecked Sendable` 不能判为现存数据竞争。可作为后续编译验证的简化候选，不列为本轮已确认缺陷。现有 LiveActivityService 的串行系统操作、ScheduleRangeEngine 的独立 JSContext、导入先存盘后发布状态等设计应保留。

## 建议实施顺序

1. 通知操作顺序保护和 Plus 刷新所有权，各自附可控交错的服务级回归测试。
2. 去掉测试中的 yield 等待假设，修复依赖前置条件的数组访问。
3. 补真实磁盘性能测量，再决定是否有 SwiftData 迁移的必要。

实施代码后的验收：重新生成 iOS 规则 bundle、运行 check:ios、模拟器编译并执行相关及完整 AppTests；通知与购买服务再做受影响系统场景验证。

## 实施与验证

2026-09-06 在用户确认后完成：

- NotificationService 的 shift add/remove 共享操作顺序，并在入队时更新 generation。页面任务被取消也不会中断已入队的清理。默认当前时间在操作获得执行机会后读取。只为系统调用增加可注入适配器，提醒规则仍由现有 TypeScript bundle 提供。
- PlusEntitlement 在刷新前分配 generation，结果提交前检查所有权与取消状态；stop 失效化在途请求。注入的证据获取闭包默认仍调用现有 StoreKit 实现。
- Live Activity 优先级调度返回可等待任务；两个测试使用时钟注册信号和 task.value 等待，移除固定次数 yield。
- RecordsDayCanvasModelTests 使用 #require 保护依赖前置条件的数组访问。
- 新增 ServiceConcurrencyTests，覆盖普通/兜底通知在途停止、调用者取消、同 ID 重排、权益授予/撤销乱序返回、stop 后迟到结果。检查授权缓存与活动订阅状态，均不调用真实通知或 StoreKit 服务。
- RecordsPerformanceTests 增加真实临时档案导入、单条写入、20 行远程批次、重开验证；使用单调时钟，并把测量结果附在 xcresult 内。临时数据和 defaults 在测试后清理。

验证结果：

- `npm run build:ios-native-rules`、`npm run check:ios`、`git diff --check` 通过。
- iPhone 17 Pro / iOS 26.5 模拟器 Debug 编译及完整 AppTests 通过：383 tests / 7 suites，测试执行 11.603 秒。
- 首次运行停在测试克隆设备的启动阶段，中止后改为预启动设备与 `-parallel-testing-enabled NO`。第一轮完整测试发现新测试未过滤无文案的禁用提醒，修正测试预期后完整复跑通过。
- 最终结果包：`/tmp/owc-swift-skills-verified.xcresult`；日志：`/tmp/owc-swift-skills-verified.log`。
- 未执行真机通知送达、后台系统清理或真实 StoreKit 购买/恢复验证；本次竞态验证使用可控的系统调用替身。

最终一轮模拟器 Debug 测量，单位 ms；这是单轮基线，不是真机发布版性能承诺：

| 档案规模 | 导入 | 单条写入 | 20 行远程批次 | 重开 |
| --- | ---: | ---: | ---: | ---: |
| 520 天 / 1,040 条初始观察 | 29.5 | 18.0 | 25.5 | 16.5 |
| 2,600 天 / 5,200 条初始观察 | 150.5 | 90.2 | 113.5 | 83.7 |

测量支持继续关注全量 JSON 保存与校验在主 actor 上的成本，尤其是多年档案，但尚不能据此选择 SwiftData。下一步应在真机 Release 测量并定位编码、校验和磁盘各自成本；若需要优化，先比较批量保存或有序后台落盘与数据库迁移的代价。本轮没有修改持久化实现，也没有引入 SwiftData。


## PR integration on current main

The PR is based on `56bf539`. It preserves the returning-user entitlement-check API added on main: repeated setup polls share a pending request, while purchases and StoreKit updates can fetch newer evidence. A deterministic regression test covers this interaction. Life income projection and the current iPad detail navigation are retained. Changes from the separate in-progress welcome/records redesign task and the pre-existing Xcode project reformat are excluded.
