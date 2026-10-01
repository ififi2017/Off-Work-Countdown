# Android 小组件与 HyperOS 兼容性

## 标准 Android 小组件

DoneAt 有三个独立的 `AppWidgetProvider`，默认尺寸分别为 2×2、4×2、4×4。
它们共用 Glance 响应式布局和预计算的无薪资 `WidgetSnapshot`，不在小组件里推导排班。

- Android 12+ 使用 `targetCellWidth` / `targetCellHeight`；同时保留 `minWidth` / `minHeight`，兼容不读取格数声明的桌面。
- 三种入口都声明 `resizeMode="horizontal|vertical"`，并提供最小/最大缩放尺寸。实际网格、尺寸选择器和拖动手柄由桌面实现。
- `receiver` 的类名保持稳定，避免让已添加的小组件失效。入口名称包含默认尺寸；实际拖动后的占格数可以不同。
- `minResizeWidth` / `minResizeHeight` 不等于默认尺寸。不能为了让选择器显示 4×2，就把所有入口的最小缩放范围改成 4×2。

参考：[Android 尺寸与响应式布局](https://developer.android.com/develop/ui/views/appwidgets/layouts)、[Glance 小组件配置](https://developer.android.com/develop/ui/compose/glance/create-app-widget)。

## 只有 2×2 时如何定位

先核对安装版本的最终清单，而不是只看工作区代码。确认三个 provider 后，再在同一台手机上检查：

1. 系统 `AppWidgetManager` 是否登记三个 provider 及对应 metadata；若少于三个，检查安装包、用户/profile 和组件启用状态。
2. 登记齐全但选择器只显示一个：检查桌面是否聚合入口，是否还有展开/尺寸切换界面，以及桌面缓存。不要清除桌面数据，这会丢失用户布局。
3. 大尺寸可以添加但不能拖动：检查宿主是否提供缩放手柄、桌面网格/锁定布局，以及它传给 widget 的 options。
4. 添加或改变尺寸后核对实际布局、后台刷新、重启和深浅色，不能仅凭 XML 宣布兼容。

可由开发者在明确选定的测试设备上收集以下只读信息；不要在分享前附上其他应用或个人内容的完整系统转储：

```bash
adb -s <测试设备序列号> shell dumpsys package com.rainif.doneat
adb -s <测试设备序列号> shell dumpsys appwidget
```

小米官方文档说明，同名 receiver label 会被当成同功能的不同尺寸并聚合。该条描述的是“小米 Widget”；尚不能直接证明标准 Android Widget 在所有 HyperOS 版本中的行为。分别命名可以帮助辨认入口及复测，但不是经真机验证的通用修复。

## 接入小米小部件中心

标准 Android 桌面兼容与小米小部件中心接入是两项工作。接入后者须遵循[小米技术规范](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1584)及[提审流程](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1588)：

- 增加小米标识、widget 版本；如需要曝光刷新，接收其刷新广播。
- 内容准备和刷新放在独立的 `:widgetProvider` 进程；按规范控制内存，避免启动 App 主进程。
- 核对 2×2、4×2、4×4、系统深浅色与不同桌面布局，并提交小米应用商店和小部件审核。

DoneAt 的接入设计还需要验证 Glance/WorkManager 的进程行为，阻止 `Application` 在 widget 进程中初始化业务档案和购买服务，并让跨进程刷新只读取现有 `WidgetSnapshot`。进程内的 `WidgetSignals` 不能自动跨进程通知。直接给现有 receiver 加 `miuiWidget=true` 或 `android:process` 不足以完成接入。

版本与本轮设备反馈、测试结果统一记录在 [progress.md](progress.md)。
