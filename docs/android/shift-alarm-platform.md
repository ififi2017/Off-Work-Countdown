# Android 班次闹钟的平台契约

行为源固定 iOS 3.2.1 `035420377e4c762ba5556a3cc41fc9a94be4bc6e`。2026-10-07 用户明确批准完整同步，包括响铃专用 Android 平台实现；本轮禁止设备闹钟／锁屏测试。这里记录实现契约，任务状态和实际验收证据仅记入 [progress.md](progress.md)。

## 授权后的架构

`ShiftAlarmPlanner` 仍是纯 JVM：读取最终已提交排班，包括节假日、手排、跨夜和已采纳请假。`ShiftAlarmCoordinator` 采用 `RulesSource.BASE` 和记录时区，监听已投影的 session 并以 fresh committed snapshot 构造计划；首次档案与节假日读取完成后才登记／投递。不把今天提前开工、继续加班、工资或记录金额带入闹钟。`AlarmSettingsStore` 与登记 ledger 都在 `noBackupFilesDir/shift-alarms`，默认关闭，不进入 archive/schema 7、云同步、Auto Backup 或 device transfer。

`AndroidShiftAlarmPlatform` 使用 [AlarmManager.setAlarmClock](https://developer.android.com/reference/android/app/AlarmManager#setAlarmClock(android.app.AlarmManager.AlarmClockInfo,%20android.app.PendingIntent)) 注册绝对单次预约，预约前和投递时均核对 `canScheduleExactAlarms()`。使用用户授予的 `SCHEDULE_EXACT_ALARM`；不声明 `USE_EXACT_ALARM`。权限不足不以非精确提醒冒充已接受的班次闹钟。[Android 14 的精确闹钟授权说明](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)要求在回到应用和授权变化时重新检查。

本轮仅为真正响铃批准 `mediaPlayback` 前台服务及 `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK`。它使用系统默认闹铃音、`USAGE_ALARM` 和原生振动，停止时释放播放器／振动／通知。MediaPlayer 的 `WAKE_LOCK` 只持有 CPU partial wake lock，不唤醒显示屏。普通提醒、健康提醒、报告通知、ongoing 与 widget 继续原有非 FGS 路径，不以服务或 WorkManager 轮询排班。[用户请求的精确闹钟属于后台启动 FGS 的例外](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)；[mediaPlayback 类型与权限](https://developer.android.com/develop/background-work/services/fgs/service-types#media)适用于后台音频，Android 15 起不能从 BOOT_COMPLETED 启动该类型。

响铃通知提供停止与九分钟稍后提醒；点击通知才打开 `ShiftAlarmRingActivity`。无 full-screen intent、`USE_FULL_SCREEN_INTENT`、锁屏覆盖、keyguard 解锁、`turnScreenOn` 或自动 Activity 启动。Android 的响铃音量、勿扰与厂商后台策略仍属于设备行为，不能由代码测试声称已验证。

## 权益边界

2026-10-04 已授权的 `services/billing-api` 会查询 Google 的当前精确 `expiryTime` 并签发受包名、商品、token hash、nonce 和时间约束的签名回执；此前文档“本轮排除服务器、订阅没有可信期限”的阻塞已经失效。`PlusStoreState.shiftAlarmAuthorization(now)` 是唯一输入。

- 有可信精确期限的签名离线缓存可以返回 `VerifiedUntil`；离线本身不等于没有授权。
- 普通 Play `Purchase` 的活跃状态／购买时间／价格周期不含当前付费期到期，不能推算或替代该期限。没有可信精确 expiry 即 `Unavailable`；缓存有效期也不是付费到期时间。
- 终身按记录时区从当前时刻加一个日历年。取消自动续订不取消尚未到期的付费期。
- 原预约和九分钟稍后提醒都严格早于精确截止；投递、打开响铃页、实际响铃期间及 snooze 再次核验。服务的下一次检查等待不超过精确剩余时间；过期、关闭、权限撤回或真实排班不再包含该班次会停止／清理所属 ID。

## 真实登记、恢复和覆盖

Android 没有 AlarmKit 式本应用完整系统队列查询。ledger 只表达最近一次平台成功接受的预约，不声称是系统实时清单；`getNextAlarmClock` 也不是本应用队列。登记先持久化 unconfirmed 身份，再调用 `setAlarmClock`，成功且 confirmed 状态保存成功才计入覆盖。写入使用固定 UTF-8、文件描述符同步刷盘，并完整读回比对 token、accepted 和全部身份字段；不能把 `AtomicFile.finishWrite` 没有抛错当作保存成功。异常／写入失败取消该预约；未确认项不能响铃或贡献覆盖。持久化故障停止新增安排。

预约使用独立 `doneat-shift-alarm` URI 和随机 registration token；receiver、service、ring activity 均不导出。传入的 ID、时间或标题不能绕过当前 ledger。投递只接受已确认项的正确 token、当前仍有效的班次和已到预约时刻的五分钟投递窗口；重复或提前投递被拒绝。冷启动只保留待投递身份，不自行补响过去的预约。已响过而进程结束的 ledger 不自动重新启动音频。

协调器保留最近 36 小时的已提交班次作为在响／snooze 的关联校验，独立于五分钟投递窗口；因此九分钟 snooze 不会因原 fire 时间退出投递窗口而丢失，也不会让已休假、调班、改提前量或删除的旧班次继续等待。替换、停止与 snooze 串行处理，新 snooze 更换 token；通知操作 receiver 保持 `goAsync` 到事务完成。取消播放在主线程重新匹配 ID、token 与当前 service generation，旧预约的取消不能停止新预约。

未来目标按时刻排序，若实际平台容量耗尽，近的预约优先替换后面的预约。覆盖仅包含 confirmed 项，连续覆盖日期不跨失败缺口；无接受项不显示“已设置到”。刷新提醒采用独立 ID／通知频道和普通 inexact 预约，不改既有 reminders；候选来自实际接受的未来预约，订阅不会在到期后承诺“刷新可继续”。

开机与精确闹钟重新授权都将旧 confirmed 登记作废并重建未来预约，绝不启动铃声。[系统撤销精确闹钟权限会清除预约，重新授权需重新登记](https://developer.android.com/develop/background-work/services/alarms#exact-permission-declare)；磁盘曾经 accepted 不能证明系统队列仍存在。时间／时区／语言、权限、权益、排班与设置变化都会重算。用户强行停止、厂商限制、重启恢复、勿扰、静音、通知权限与前台服务启动失败须分别做设备验收，不能用 PendingIntent 单测代替。

## 验证边界

`ShiftAlarmEngineTest` 使用 fake platform，覆盖默认关闭、失效／精确到期、权限撤回、成功覆盖与失败缺口、容量优先、重复／伪造／提前投递、冷启动、九分钟 snooze、新 token、排班撤销、开机重建、重新授权后系统队列重建和持久化故障撤销旧覆盖。`VerifiedAlarmLedgerCommitTest` 注入 silent-save、损坏读回、读写异常和平台失败，验证未真正保存不能确认接受且已登记的系统预约被撤销。`AlarmSettingsStoreTest` 使用临时文件，覆盖本地往返、损坏读取、非法提前量和持久化失败。签名离线到期已有 115 阶段证据，不能外推为原生闹钟已通过设备测试。

本轮没有触发设备闹钟、锁屏、播放铃声、创建真机预约或执行系统权限 QA。实际 native ringing／停止／snooze／后台／重启／权限矩阵仍须独立授权后完成。
