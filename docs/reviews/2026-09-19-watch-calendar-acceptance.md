# 2026-09-19 · Watch V2、019 与 P8 本轮验收

本轮实现范围：Watch 独立排班及免费化、统一月历排班编辑、历史计划补填、019 回归。未上传、未发布，未接入节假日数据。整个 018 与发布门禁保持未完成。

## 实现

- 共享无薪资 Swift 排班源码，V2 传递持久化规则而非只够一班的快照。当前班次覆盖限于对应班次；后台 receiver 从进程启动并在写入／组件刷新后完成后台任务。
- Watch App、圆形及长方形组件免费；V2 不写入权益和薪资字段，保留 V1 缓存读取。小包 application context，大包后台文件，配对世代和版本顺序共用原子缓存入口。
- 所有模式共用顶部月历，日期点击只选择，下方选择班次；模式、周期和班次类型修改在草稿中即时预览，统一保存、放弃和当前班次生效范围确认。详细班次配置移入系统弹层。
- 过去日期的手工计划保存完整班次工时快照，备份和 CloudKit DTO 可读旧数据。旧固定快照和无快照职业区间可接受补填，实际记录／请假优先，清除恢复原计划。
- “接下来”区分本月已生效／下月预定；扩展排班及专注时间轴使用“中途休息”。手机说明页、Plus 权益列表、版本介绍和 19 语言一并调整。

## 已有自动化证据

- `npm run lint`：通过。
- `npm test -- --maxWorkers=1`：34 文件、411 测试通过。最后串行执行用时 24.93 秒。
- Web 构建、`check:build:web`：通过。
- Desktop 导出、`check:build:desktop`：通过。
- `check:ios`、`check:ios-strings`：通过；所有新增键覆盖 19 语言。
- iOS App 与嵌入 Watch 构建、完整 AppTests 编译：通过。最终完整串行 iOS 执行 787 测试、50 个测试组通过。
- Watch 独立目标构建与完整串行测试：22 测试、3 个测试组通过；包括离线循环、跨月沿用、当前班次覆盖、缓存恢复、接收完成计数、V1→V2 升级及拒绝迟到 V1 降级。
- 共享规则 fixture 重新生成后无内容变化，工程结构、19 语言与 `git diff --check` 最后复查通过。
- 019 打包补查：实际构建的 Widget 扩展包含 19 份 locale JSON，与源码逐份一致，均含中途休息文案；复数与 Live Activity 规则测试随完整 iOS 套件通过。该检查不代替系统界面实际输出验收。

日志保存在本机 `/private/tmp/owc-*.log`，不是可移植的长期附件；关键结果记录在本文。

## 视觉证据

- iPhone 18 Pro 默认字号首屏：已实际查看，新月历、单行模式、所选日期与班次选择均可见，无遮挡。无障碍层级中可见日期各一个点击目标。
- 初始截图：`/private/tmp/p8-calendar-iphone18pro-baseline.jpg`。这是新界面构建，后续模式措辞已更新为“自由排班／手动计时”。
- iPhone 18 Pro 六周月份（2026 年 8 月）、点日期只选择、点击 Night 即时更新月历并启用保存、切换规律显示确认：通过。未保存用户数据。
- iPad 13 阿拉伯语 RTL 竖屏：视觉通过；该次横屏请求未得到横屏图像，无障碍远程会话超时，不能计为横屏或 VoiceOver 通过。
- iPhone 17e 深色 Accessibility Large：首轮发现模式文字与周期控件拥挤。已改用自然增高的独立模式按钮、标准滚动容器和系统极短星期；新构建复查通过：滚动后模式、周期、日期详情和班次选择均可读可点击，改班即时更新月历。截图 `/private/tmp/p8-final-iphone17e-large-dark-scrolled.jpg` 与 `/private/tmp/p8-final-iphone17e-large-dark-palette-tapped.jpg`；长字体下末尾选项保留水平滚动。
- 其他截图分别为 `/private/tmp/p8-calendar-iphone18pro-aug2026-sixweek.jpg`、`/private/tmp/p8-calendar-iphone18pro-date-night-preview.jpg`、`/private/tmp/p8-calendar-iphone18pro-mode-switch-confirmation.jpg`、`/private/tmp/p8-calendar-ipad13-arabic-rtl-light.jpg`。
- 最终中文 iPhone 18 Pro 竖屏：`/private/tmp/p8-final-iphone18pro-zh-portrait.jpg`（368×800）通过。真实横屏 framebuffer 为 800×368：`/private/tmp/p8-final-iphone18pro-zh-landscape-calendar.jpg`、`/private/tmp/p8-final-iphone18pro-zh-landscape-editor.jpg`；月历及滚动后的模式、日期详情、班次选择均正常。点击 Night 后即时更新详情并启用保存，未保存草稿；截图 `p8-final-iphone18pro-zh-landscape-night-preview.jpg`。无障碍层级正常，仍不等同于实际 VoiceOver 朗读验收。
- 最终横屏首轮遇到模拟器 SpringBoard／display-port 故障，同一设备关闭重启后恢复；以上结论来自恢复后的实际界面。iPad 已覆盖 RTL 竖屏，iPad 横屏尚未另行取得证据。

## 串行回归过程

- 第一轮执行 784 测试：历史补填、差分、复数及性能通过；Watch 断言使用显式整数类型、旧 schema/大小测试需更新，并发现未开始计时／休息日没有当前覆盖时不应写入 `resumeAtMs`。均已修正。
- 第二轮执行 785 测试：仅非法日期 `2026-02-30` 校验失败。共享源码抽取时把完整日期校验退化为格式校验，已恢复民用日期往返验证，未通过修改 fixture 隐藏失败。
- 串行性能实测（第一次完整执行）：一年 recordsMetrics 4.9 ms、单日画布 0.6 ms、职业全程冷准备 506.1 ms、记录列表 5.2 ms；原 019 记录的一年 metrics 4.9 ms、冷准备 859 ms。既有性能断言通过，但这不是新旧二进制同机交替多轮基准。
- 最终完整 iOS：787 测试、50 个测试组全部通过（`owc-ios-final-tests.log`）。最终读数：一年 metrics 5.4 ms、单日画布 0.6 ms、全职业冷准备 535.2 ms、列表 3.6 ms；现有断言均通过。
- Watch 首次构建通过但未启动测试；自动配对的 iPhone Air 缺少宿主 App，安装后进入测试。回归随后暴露测试仍手动重复配对、以及等待 ready 却未等待重复包处理结束的旧假设，已修正。最终 `owc-watch-final-tests.log` 记录 22 测试／3 组通过及 `TEST SUCCEEDED`，包含新增的 V1→V2 升级用例。
- 多台模拟器与 JavaScript 测试并发时曾发生 oracle 超时及 worker 通信错误；关闭多余模拟器后串行重跑 411 项全部通过，未放宽超时断言。日志为 `owc-tests-serial.log`。

## 尚未取得的真机证据

- 首次同步后不再打开 Watch App，跨多个班次、休息日及月界继续运行；离线和重启恢复。
- 手机改班后真实 WatchConnectivity 后台抵达、旧包迟到、表盘两种组件及 AOD、耗电。
- Widget／实时活动系统实际输出、VoiceOver 朗读体验与真机大字号。

2026-09-13 Ultra 2 的早期反馈属于 V1，不作为本轮 V2 验收。模拟时间测试仅证明缓存规则结果，不证明系统投递时机。

## 下一目标

以上收口后，下一项是 018 已规划的节假日与调休模板：随 App 内置，按系统地区默认，可切换或关闭；人工改班优先，月历区分节假日与调休上班日，未知年份不猜测。本轮不包含数据接入和任何上传／发布。
