# 首启反馈修复证据

2026-10-07，主 agent 实际查看 iOS 源码、模拟器和 USB Pixel 10 Pro。状态以 [progress](../../../docs/android/progress.md) 为准。

- `ios-schedule.png`、`ios-widget.png`：固定 3.2.1 UI 源 `0354203` 在专用 Duo / SDK 27.1 的新截图；七天同排、真实小组件展示层级。`ios-offer-reference.jpg` 是开发前重新查看的同版本购买页内优惠卡参考，**不是**本轮取消后 sheet 的截图。
- `pixel-schedule-before.png`、`pixel-privacy-before.png`：用户报告时的实际画面，记录六天加孤立周日以及透明隐私页叠画。
- `pixel-127-schedule.png`：实际首启，七个星期控件的 XML top/bottom 相同，完整星期名称供读屏使用。`pixel-128-weekdays-ar200.png`：同一生产组件的独立只读预览，阿拉伯语 RTL、200% 字号、4+3 平衡行；未修改系统字体或语言。
- `pixel-127-ready.png`、`pixel-127-privacy.png`：真实打开和返回 Stays on this device；隐私页没有底页像素或底页控件。`pixel-127-reminders-ready.mp4` 是提醒页到完成页的实际录屏，已抽帧查看；计时与整页使用共同 transition，未定量测帧率。
- `pixel-127-{widget,notification}.png`：不同 Android 表面结构，widget 有状态与进度，通知有结束时间与 chronometer；预览不会发布通知。`pixel-128-widget-{light,dark}.png` 核对最终零进度无假终点标识。浅色画面是明确标注的只读首启预览。
- `pixel-127-intro.png`、`pixel-128-intro.png`：完成首启后实际进入 Plus 介绍页，最终版使用 Close 图标。`pixel-127-intro-dismissed.png` 记录真实商品不可用时取消后的主页；127 与最终 128 均经取消和冷启动确认不会循环出现介绍页。

最终 128：662 项 Android tests 全通过，Lint 0 errors / 54 warnings / 4 hints，Debug/R8 Release 和本地 headless iOS build 通过。曾发现并修复 intro 标记读取的 minSdk API 兼容、只读预览的 ActivityResultRegistryOwner 缺失；最终只读首启已实际重新打开确认。

为保留用户已完成的 QA 设置，停止隔离 `com.rainif.doneat.parity321` 后备份，再在副本上回放。回归结束恢复原备份，设备设置与 records 文件均逐字节核对一致；最终 128 留在主页。正式包和正式数据未操作。设备中途自行/人工锁屏、USB 断开，agent 仅观察；用户恢复后才继续，agent 未执行锁屏或解锁，未测试闹钟、购买或修改网络/时间设置。

隔离包的真实 Play 商品不可用，因此 **合资格折扣 sheet 的实价展示及购买 NOT_RUN**；9 项新增 intro policy/store 测试和既有优惠资格测试不能代替正式注册包、许可测试账号的商品查询。没有伪造价格、权益或优惠期限。本目录媒体未裁切或重绘；录屏仅保留视频轨道。`sha256.json` 保存媒体校验和。
