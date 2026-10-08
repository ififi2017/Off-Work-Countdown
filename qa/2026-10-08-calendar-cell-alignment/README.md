# 月历对齐与预测提醒 · 2026-10-08

实际截图来自同一台 DoneAt QA iPhone 17 / iOS 27.0，竖屏。未生成或重绘 UI。

| 文件 | 检查 |
|---|---|
| [请假月历](leave-cn-september.jpg) | 2026-09：25–27 节名、28–29 空说明、30 请假图标以及调休格日期共用基线；仅剩实际绘出的请假图例。 |
| [预测说明](leave-cn-prediction.jpg) | 2027-02 春节，三角对齐整段说明的垂直中心；月历节名与无节名日期对齐，无旗帜图例。 |
| [记录月历](records-cn-october.jpg) | 2026-10：10 号日期、调休、工作横条使用同一布局与间隔；普通字体 large 下接近方格。 |
| [记录大字号](records-cn-large.jpg) | 系统 accessibility-large；沿用记录密集图表已有字体上限，格高可增长，长节名仍单行省略，不纵向重叠。 |
| [英文深色](leave-en-dark.jpg) | GB 2026-12 的 Christmas、Boxing Day 等长节名尾部省略，数字同一基线。 |
| [完整英文节名](leave-en-full-name.jpg) | 实际点击 12 月 28 日，展示 Boxing Day (observed)。 |
| [进入录屏](warning-entry.mp4) | 实际启动录像的第 7–10 秒；摘要、预测说明和月历渐入，说明没有先于摘要独自可见。 |
| [进入抽帧](warning-entry-frames.png) | 原录像第 7–11 秒，每 0.2 秒抽帧，按行阅读；仅等比缩小和拼接，未重绘。 |

请假布局使用已有 DEBUG 真实规划器样例：`qaRoute leave`、`qaLeavePlanner YES`、`qaLeaveRestDays 8`；中国大陆选正常春节方案或列表中 2026-09-30 起的方案，英文地区用 `qaLeaveRegion GB`。固定真实查询窗口为 2026-09-21 至 2027-09-20；这组样例绕过计次，不能当作扣次验证。

记录页使用模拟器既有样例归档与中国大陆排班，`qaRoute records`、`qaRecordsScale month`、DEBUG Plus 授权仅用于显示 10 号；没有修改用户真机。检查大字号后已将模拟器字体恢复为 large。原用户 HEIC 截图只读取到临时目录，不提交仓库。

Astra 审核结论、自动验证与未测范围见[回归记录](../../docs/reviews/2026-10-08-calendar-cell-alignment.md)。
