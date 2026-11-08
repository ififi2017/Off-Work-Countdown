# 021 工作地点自动化 · P0 能力验证（iOS）

计划：[plans/iOS/021-workplace-automation.md](../../plans/iOS/021-workplace-automation.md) §7 P0、§8.2。
状态：**探针已就绪，真机验证未开始。** 下表每项在有证据前保持“未验证”；未经验证的能力不进入对外承诺（官网、商店、App 内文案）。3.3.0 的 P0 只验证 iOS；Siri 与 Android GMS 已移出 3.3.0，不在本表。

## 平台基线（2026-11-08 记录）

| 项目 | 值 |
| --- | --- |
| iOS／watchOS 最低系统 | 26.0（`IPHONEOS_DEPLOYMENT_TARGET`） |
| 构建 SDK | iPhoneSimulator 27.1（Xcode 当前版本） |
| 监控 API | `CLMonitor` + `CLMonitor.CircularGeographicCondition`，`CLServiceSession(authorization: .always)` |
| 系统条件额度 | Apple 文档：单个 App 同时最多 20 个条件；5 个地点 × 内外圈 = 10 |
| `UIBackgroundModes` | 仍只有 `fetch`、`remote-notification`；区域监控不需要 `location` 模式，除非实测证明需要 |
| 新增 `Info.plist` 键 | `NSLocationWhenInUseUsageDescription`、`NSLocationAlwaysAndWhenInUseUsageDescription`（19 语言 + es-MX） |

## 探针

DEBUG 构建：设置 → 关于，长按两次“DoneAt”字样打开调试菜单 → 计划 021 · P0 → 工作地点探针。Release 构建没有入口，也不编译探针代码。

- 开启后建立 `CLServiceSession(authorization: .always)` 并请求授权；`didFinishLaunching` 内恢复会话与 `CLMonitor`，系统因跨越边界在后台拉起 App 时也能接到事件。
- “把当前位置加为地点”：取一次精度 ≤100 米的位置，注册内圈（默认 200 米，可 100–500）与外圈（内圈 +100 米）。
- “补足到 5 个地点”：在第一个地点以北 1–4 公里加补足地点，共 10 个条件，用于额度测试。
- 每条记录：收到时间、系统观察时间（`event.date`）与延迟、条件与状态、App 前后台状态、是否锁屏（受保护数据是否可读）、授权与精度、系统诊断标志。
- 文件存于 Application Support，`completeFileProtectionUntilFirstUserAuthentication`，排除系统备份；导出为 TSV，只含地点名称与半径，不含坐标。
- 探针不写工时、不发通知、不改排班。

### 内部 TestFlight 探针版

也可用 `WORKPLACE_PROBE` 旗标打一个只给内部测试员的 TestFlight 建置（做法见 [releases.md](../agent-guides/releases.md) “Internal geofence probe build”）。它没有调试器、连正式 iCloud，更接近真实使用；入口是“关于”页长按“DoneAt”两次，直接打开探针页，不开放其他调试工具。该建置不得提交审核或发布。

| 建置号 | 上传日期 | 分发范围 | 备注 |
| --- | --- | --- | --- |
| 3.3.0 (1) | 2026-11-08 | 仅内部测试（上传时设 `testFlightInternalTestingOnly`，App Store Connect 不允许外部测试或送审） | 基于 `af4df8f6`；版本号与建置号只在归档命令中指定，未提交到工程 |

### 测试前

1. 用 Xcode 安装 Debug 构建到 iPhone，然后**断开调试器**：在 Scheme 关闭 Debug executable，或安装后停止运行，再从主屏幕打开。调试器会让 App 一直留在后台，结果不可信。
2. 打开探针，授权选“始终允许”，开启“精确位置”。
3. 在公司把当前位置加为地点。需要测额度时再补足到 5 个地点。
4. 正常通勤；每天结束或测完一个情境后，生成导出文件并分享回来分析。

## 验证矩阵（§8.2）

| # | 情境 | 期望／关注 | 结果 | 证据 |
| --- | --- | --- | --- | --- |
| 1 | 前台进出 | 收到内圈 satisfied 与外圈 unsatisfied；记录延迟 | 未验证 | |
| 2 | 后台、长时间锁屏进出 | 收到事件；`locked` 时能否写入（P1 文件保护假设） | 未验证 | |
| 3 | 系统回收后（过夜、开大量其他 App） | 系统在后台拉起 App 并送达事件（`launch` 后紧接 `event`，无 `became active`） | 未验证 | |
| 4 | 用户在多任务中划掉 App | 预期收不到；如实记录，属平台限制 | 未验证 | |
| 5 | 重启后首次解锁前／后 | 首次解锁前预期收不到；解锁后能否恢复 | 未验证 | |
| 6 | 午间外出、路过公司、长时间静止室内 | 误触发、重复触发次数 | 未验证 | |
| 7 | 改为“使用期间”、关闭精确位置、关闭系统定位 | 诊断标志正确，不出现伪造的离开 | 未验证 | |
| 8 | 5 个地点、10 个条件 | 无 `conditionLimitExceeded`；与其他 App 共存 | 未验证 | |
| 9 | 弱网络、关闭 Wi-Fi | 只记录实测结果 | 未验证 | |
| 10 | 耗电对照（开启／关闭各一段） | 记录设备、系统、时长、移动情况 | 未验证 | |

试点至少 10 个完整到离岗周期，汇总：成功触发、漏触发、误开始／误结束、观察到收到的延迟（中位数与最大值）、需要人工更正的次数。小样本只作试点结论，不据此宣传可靠性百分比或固定耗电。

## 结论对 I2 的影响

- 冷启动与锁屏都能收到、延迟在分钟级 → I2 按 §3 默认参数实现。
- 漏触发多或延迟长 → 调整内外圈半径与 15 分钟事件时效等实现默认，并在文案中说明需要用户核对。
- 第 4、5 项收不到属于平台限制，写入说明，不算 P0 失败。
- 出现无法解释的午间误结束或重复记录，阻断 I2 发布。
