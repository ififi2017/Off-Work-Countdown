# Android 班次起床闹钟的平台边界

核对日期：2026-10-03。行为参考固定为 iOS `18129168acd23edc3a872cca3633a2831f60c6f2`（Plan 020）。任务状态仅记在 [progress.md](progress.md)。

## 已核实的 Android 能力

- [`AlarmManager.setAlarmClock`](https://developer.android.com/develop/background-work/services/alarms) 可以预排单次绝对时刻，在进程不运行或设备睡眠时投递 Intent。它不是替第三方应用播放、停止或贪睡铃声的托管服务；应用仍须实现响铃生命周期。
- 保留用户授予的 `SCHEDULE_EXACT_ALARM`。每次预约前检查 `canScheduleExactAlarms()`，处理预约时的权限变化；撤销该权限会停止应用并取消其精确预约。起床闹钟不能降级为非精确普通通知却仍显示预约成功。普通提醒现有降级行为不变。
- [全屏通知](https://developer.android.com/develop/ui/views/notifications/time-sensitive) 可承载锁屏响铃界面，但 Android 14+ 需另查 `canUseFullScreenIntent()`。用户可撤销权限，Play 对默认授权有[用途限制](https://developer.android.com/about/versions/14/behavior-changes-14#secure-fsi)，不能承诺安装后一定全屏显示。
- 在接收器返回后继续播放铃声需要应用提供可持续的响铃执行路径；原生前台服务是可评估方案。[由精确闹钟启动的时间敏感操作](https://developer.android.com/develop/background-work/services/alarms) 不受通常的后台前台服务启动限制，但仍须声明合法服务类型及相应权限、遵守发布政策。只在真正响铃时运行，不用服务或 WorkManager 轮询排班。
- 系统重启需重建持久登记中的未来预约；应用被用户强行停止、权限撤销、设备断电、厂商后台限制和普通进程退出是不同用例。普通进程退出可由 PendingIntent 唤醒，不能把它写成已证明强行停止后仍响铃。
- `AlarmManager` 没有读取本 App 全部已排闹钟的通用查询接口。只能把成功返回的登记保存为“最近一次系统接受的预约”，同时在重启、授权变化、重新进入和调班时核对恢复；`getNextAlarmClock()` 是设备下一次闹钟，不是本 App 完整清单。不得宣称拥有 AlarmKit 式实时系统队列。

## 客户端订阅没有精确到期凭据

[Play Billing `Purchase`](https://developer.android.com/reference/com/android/billingclient/api/Purchase) 暴露购买状态、签名、购买时间和自动续订标记，没有订阅到期字段。购买时间是首次订阅时间，续订不更新；价格阶段的月/年周期也不是当前已付费周期的精确结束时刻。现有 `EntitlementEngine.OFFLINE_SUBSCRIPTION_MS` 是离线缓存有效窗口，不能充当订阅到期时间。

Google 的精确 `lineItems.expiryTime` 在 [Developer API `purchases.subscriptionsv2.get`](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2) 返回，需可信服务端访问。客户端不能内嵌服务账户密钥。本轮明确排除购买验证服务器，因此没有可用于自动预排订阅闹钟的已验证精确截止时刻。取消自动续订也不等于失去已付费周期，不能据此取消所有闹钟。

## 与既定架构的冲突及可行选择

当前 `docs/agent-guides/android.md` 禁止前台服务；清单显式移除了 `FOREGROUND_SERVICE`。普通报告通知、倒计时与健康提醒沿用此架构。

1. **保留当前架构**：先落地纯 JVM 班次闹钟规则与回归，暂不开放起床闹钟开关或注册系统闹钟。报告、休假与记录页可以独立交付。这是本次代码采用的边界。
2. **另行批准响铃专用服务**：只在响铃期间运行原生服务，配套全屏权限/界面、默认系统闹铃、停止、九分钟贪睡、开关与权益撤销清理、持久登记和刷新提醒；仍不用轮询，仍用 `SCHEDULE_EXACT_ALARM`。须先更新架构约束并完成设备矩阵。终身权益可以按一个日历年预排；订阅仍受下一项限制，不能静默改成“仅终身可用”。
3. **为订阅补充可信精确期限**：在另一个已授权范围中引入 Developer API 验证服务，或将产品行为明确调整为不承诺订阅期内自动预排。后者改变原需求，不能在本轮自行采用。系统时钟 `ACTION_SET_ALARM` 需用户交接且无法可靠管理本 App 队列，不满足本次自动调班、清理和覆盖清单要求。

## 纯规则契约

`core/domain/alarms/ShiftAlarmPlanner.kt` 复用最终 `ScheduleRules.expandScheduleRange`：休假、休息、节假日、补班、手排与跨夜均由既有规则决定。提前量取第一个有效工作段，允许跨前一天；稳定 ID 使用与 iOS 一致的 SHA-256 UUID。

- 订阅只接受显式注入的 `VerifiedUntil`；没有到期凭据即 `Unavailable`。终身从记录时区的当前时刻加一个日历年，闰日与 DST 由 `java.time` 处理。
- 原预约及九分钟贪睡均严格早于截止时刻；取消自动续订不是撤销授权的输入。
- 差量取消不再需要的 ID、只添加缺项；覆盖日期不跨越失败缺口。刷新候选来自最后一条实际接受的未来预约加十分钟，订阅不得到期后承诺“刷新可继续”。无成功预约不虚构覆盖或耗尽事件。
- 关闭与确认失效以空目标集合清理所属 ID，刷新候选同时为空。规则结果不是系统已接受的证明；持久化、系统注册、响铃、锁屏、停止与贪睡的设备实现仍需上述平台方案。

没有照搬 iOS 通知数量预算，没有实现或声称 iOS `stopIntent` 自动补排。
