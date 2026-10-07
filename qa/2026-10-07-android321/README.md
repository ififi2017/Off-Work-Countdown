# Android / iOS 3.2.1 对照证据

2026-10-07，主 agent 实际采集与查看。状态及完整检查以 [Android progress](../../docs/android/progress.md#2026-10-07--android-同步-ios-321) 为准；本目录不是新的任务 ledger。

## 环境与边界

- iOS：固定 UI 源 `035420377e4c762ba5556a3cc41fc9a94be4bc6e` 的实际 simulator build，Duo / SDK 27.1。开发前还查看了 iPhone 上的请假、日期、首启、Plus 和优惠截图。未生成或重绘 UI。
- Android：USB Pixel 10 Pro / Android 17，隔离 Debug 包 `com.rainif.doneat.parity321`，候选 123–126。正式 Play 3.2.1 (115) 未覆盖、未清数据。早期验收截图保留对应候选，最终折叠、横屏与优惠画面来自 126。
- `pixel-wide-*`、`pixel-half-*`、`pixel-vertical-*` 使用本地窗口/姿态注入；Pixel 没有真实铰链。这些证明实际 Compose 画面及几何避让，不证明折叠硬件 posture 回调。
- 请假为固定合成档案；Focus/Records 保留免费锁和样例。`pixel-offer-fixture.png` 是屏幕明确标注的 Sample price fixture，购买回调为空、未写优惠期限，不能作真实 Play 价格或购买证据。
- 没有锁屏、启用或触发闹钟、购买、改系统时间/网络、采用请假方案。iOS 闹钟设置截图仅查看关闭状态，07:00 出现在演示插图中。

## 画面索引

| Android 文件 | 观察依据 |
| --- | --- |
| `pixel-leave-regular.png` | 普通连休 24 组、9 天休息/5 天请假、48 个日期入口。 |
| `pixel-leave-dates.png` / `pixel-leave-detail.png` | 原生日期抽屉，选择保留；仅进入详情预留免费次数，返回仍为 2。 |
| `pixel-leave-ar-200-dark.png` | 阿拉伯语 RTL，200% 字号、深色、减少动态效果；等高多行标签与滚动可达操作。 |
| `pixel-onboarding-{welcome,ready,glance,plus}.png` | 实际首启与连续计时、Android 专属说明、Plus 三阶段。 |
| `pixel-whatsnew-zh.png` | 3.2.1 更新介绍、REST 演示与明确下一步。 |
| `pixel-wide-{timer,focus,records,settings}.png` | 展开布局；两 pane/画布、58/42 Records 与两列 Settings。 |
| `pixel-half-dark.png` | 最终 126：上方 hero、下方时间线和操作，中间避开水平铰链。 |
| `pixel-vertical-ar-200.png` | 最终 126：200% RTL 单安全 pane，避免跨垂直铰链。 |
| `pixel-landscape-clock.png` | 最终 126：实际物理横屏，黑底白色时钟/统计/班次时间。Back 返回与竖屏恢复另经交互确认。 |
| `pixel-offer-fixture.png` | 最终 126：无购买、无期限写入的数据画面，只核对层级和排版。 |

`ios-duo-{open,half,focus,records,settings}.png`、`ios-whatsnew.png`、`ios-landscape-clock.png` 是同源实际 iOS 对照。`ios-alarm-settings-disabled.png` 只记录关闭状态。

## 动效证据

- `ios-ready-glance.mp4`：实际 iOS Ready→Glance 的连续计时衔接。
- `pixel-leave-motion.mp4`：实际 Pixel 下一方案切换，包含切换前、逐格弹簧入场与完成态。已抽帧确认方案从 2/35 切到 3/35；不扣免费次数。
- 实现按 iOS 源的分层延迟、弹簧和持续计时逻辑复现，Android 原生表面使用 Compose。减少动态效果、辅助功能与后台停止通过代码回归/实际静态预览检查；未测高速摄影、定量帧率或声称逐像素一致。

`sha256.json` 记录原始文件校验和。屏幕尺寸、系统状态栏与采集时间均保留，图片没有裁切或重绘。视频仅移除 Android screenrecord 的非视频元数据轨道以便播放，画面未重新编码。
