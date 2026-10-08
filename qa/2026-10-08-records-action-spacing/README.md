# 入口留白、预测文案及记录基线 · 2026-10-08

同一台 DoneAt QA iPhone 17 / iOS 27.0 竖屏，真实应用截图，未重绘 UI。

| 文件 | 检查 |
|---|---|
| [修后记录月历](records-cn-aligned.jpg) | 普通 large 字号。1/2/3、5/6/7 与 8/9/10 共享日期和说明基线；休息日保留空工作条槽。两入口紧凑分组。 |
| [修前记录月历](records-cn-light.jpg) | 仅作前后对照：没有横条的日期偏下，2、6 号偏上。不计入修后通过证据。 |
| [记录大字号](records-cn-large-aligned.jpg) | accessibility-large；密集月历沿用现有字号上限，日期和单行省略说明仍对齐。 |
| [单入口摘要](leave-cn-single-row.jpg) | 全部方案上下留白收紧，预测提醒两段真实换行。 |
| [双入口摘要](leave-cn-two-rows.jpg) | 全部方案和可选日期一致分组，不重复额外间距。 |
| [单入口大字号](leave-cn-accessibility-large.jpg) | 日期范围自然换行；提醒完整显示，可滚动到月历。 |
| [大字号滚动](leave-cn-large-scrolled.jpg) | 实际上滑查看月历，底部操作保留。 |
| [双入口大字号](leave-cn-two-rows-large.jpg) | 两入口无重叠，实际点击可选日期进入 35 日期列表。 |

DEBUG 真实规划器：`qaRoute leave / qaLeavePlanner YES / qaLeaveRestDays 8 / qaLeaveRegion CN`，春节样例选 proposal 0；常规休息日组用 proposal 28 或从全部方案筛选不结合节假日。固定查询窗口为 2026-09-21 至 2027-09-20，QA 绕过计次，不能证明真实扣次。记录页用 `qaRoute records / qaRecordsScale month / DEBUG Plus`，仅在 QA 模拟器显示未来日，不修改真机数据。字号检查后恢复 large。

[model/shared 漂移](android-model-drift.txt) 基于 origin/main c599ad45，55 条；冻结源与授权增量未推进。本轮 Android 没有设备视觉验收；Web/Desktop 完成构建和共用目录检查，没有补充视觉矩阵。完整检查与审核见[回归记录](../../docs/reviews/2026-10-08-records-action-spacing.md)。
