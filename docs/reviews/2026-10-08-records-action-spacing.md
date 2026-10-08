# 入口留白、预测说明与记录月历基线（2026-10-08）

记录页规划休假和播放月报因各自最小点击高度之外又加外层间距而显得疏离；请假摘要的全部方案行同样叠加卡片 padding 与 stack gap。用户进一步指出 2、6 号记录日相对相邻日期偏上。

## 修正

- 两端月视图入口作为一组，保留 iOS 44pt／Android 48dp 点击区域，去掉两者之间额外间距；周／年入口不变。
- 请假摘要对信息与入口分别设置留白，全部方案及可选日期行共用零间距入口组，底部仅留 4pt／dp；保留现有按钮、路由和长文字换行。
- `holidayEstimatedYearWarning` 缩短为两段，每项使用一个真实 newline，无分号。保留中国大陆、预测非正式、国务院年底正式通知和公布后尽快更新。iOS 21 目录项、公共 19 语同键和 Android 生成资源同步；en-GB 与 en 相同，Android 生成器正常回落默认表。
- 工作横条为空时原 `RecordsMiniWorkBar` 的 EmptyView 没有占用 VStack 槽，整组居中造成无横条日期偏下。有横条的 2、6 号因此相对偏上。仅 iOS 月历用始终存在的固定高度 ZStack 保留空横条槽；Android 已有固定 Box 槽。填色、斜纹、选择、详情、排序和计次均不变。

## 验证

- iOS 最终 XcodeBuildMCP 构建成功：`build_run_sim_2026-10-08T13-01-59-890Z_pid2841_bdd0f3cc.log`，37 秒；目录、字符串、Android 生成和 diff 检查通过。
- JavaScript 50 文件／552 项通过。首次与多端编译并行时 552 项均通过，但 Vitest worker `onTaskUpdate` 出现 unhandled timeout，退出非零；单独重跑 29.22 秒无错误，日志 `/private/tmp/doneat-action-spacing-vitest-retry.log`。lint 无错误，Web build 与 `check:build:web`、Desktop export 与 `check:build:desktop` 通过，各自日志 `/private/tmp/doneat-action-spacing-{web,desktop}-build.log`。
- Android 最终七项 gates 通过：690 项，主代理独立核对四模块 XML，0 failure/error/skip；lint 0 errors / 54 existing warnings / 4 hints，Debug／R8 Release 成功。日志 `/private/tmp/doneat-records-action-spacing-android-final-gradle.log`。
- 单台 iPhone 17／iOS 27.0 实际核对中文浅色普通 large 和 accessibility-large：修后 1/2/3、5/6/7、8/9/10 基线，单／双摘要入口，大字号提醒、滚动和可选日期实际点击；字号恢复 large。实图与复现见[QA](../../qa/2026-10-08-records-action-spacing/README.md)。
- Astra（GPT-6 Astra / XHigh）实施前讨论、阶段源码与截图审核完成；用户指出基线缺陷后重新讨论根因。最终以新构建截图确认普通／辅助功能字号日期和节名基线一致，双入口无重叠、点击区保留、提醒可滚动且固定操作可见，后审通过，无阻塞项。旧图仅作为修前对照。Android 协作 GPT-6.1 Sol / High，预测文案协作 GPT-6 Luna / XHigh。
- 无 Android 设备、真机、iPad、横屏、全语言视觉、Web/Desktop 新视觉矩阵或真实购买验收。本轮没有改规则或假期数据。基于 main c599ad45 的独立分支，原脏工作区未动；PR 未合并或发布。
