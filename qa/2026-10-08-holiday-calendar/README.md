# 休假结果页实际截图 · 2026-10-08

单台 DoneAt QA iPhone 17 / iOS 27.0，竖屏，普通字体 large；UDID E0315490-9169-4FD5-AC30-EA2F8368DDCF。来自实际 XcodeBuildMCP Simulator 截图，没有生成或重绘 UI。

| 截图 | 观察 |
|---|---|
| [中文结果](zh-CN-summary.jpg) | 最终构建，至少连休 13 天，请 3 天最省；周一开头、单摘要、全部方案入口、单行调休。 |
| [全部方案](zh-CN-plans.jpg) | 首轮结构实现，实际点击入口后的按成本排序列表及选中标记。 |
| [预测方案](zh-CN-prediction.jpg) | 首轮结构实现，列表选中 2027 春节返回；短标及完整告知。 |
| [英文长名称](en-long-holiday.jpg) | 最终构建，GB 圣诞与 Boxing Day (observed) 单行尾部省略。 |
| [英文全名](en-holiday-full-name.jpg) | 实际点击 12 月 28 日，弹出完整节名与日期，不消耗额外次数。 |
| [英文免费页底部](en-free-bottom.jpg) | 最终计次文案：本组切换和详情免费；实际滚到底，六行和图例完整越过固定按钮。 |
| [每周第一天选项](zh-CN-week-start-menu.jpg) | 实际打开设置菜单，提供星期日和星期一。 |
| [选择星期一](zh-CN-week-start-monday.jpg) | 实际选择后设置行立即更新，重启后的中文结果图证明月历生效。 |
| [实际查询计次](zh-CN-search-counted.jpg) | 关闭 DEBUG 方案样例，实际从表单查找，3 次减到 2 次；打开详情返回仍为 2 次。 |
| [中文辅助功能字号](zh-CN-accessibility-bottom.jpg) | 早期收尾版本 accessibility-medium，实际滚到底，无纵向重叠；最新尾部省略由英文图验证。 |
| [俄语三分类](ru-categories.jpg) | 早期收尾版本，普通字号菜单完整呈现三项分类。 |
| [俄语摘要](ru-summary.jpg) | 早期收尾版本，成本/天数纵排、年份日期完整。 |

中文结果复现参数：`-ios.native.onboardingComplete YES -ios.native.qaRoute leave -ios.native.qaLeavePlanner YES -ios.native.qaLeaveRestDays 13 -ios.native.languageOverride zh-CN -theme light -ios.native.debugPlusAuthorized YES`。周一偏好由设置 UI 选择，随后重启，不通过参数伪造。

英文长名称：`qaLeaveRegion GB`、`languageOverride en`、`theme dark`、`debugPlusAuthorized NO`、`leavePlannerTrialsUsed 1`，省略 restDays 使用默认预算 5 天；DEBUG 真实规划器样例不写排班/余额且绕过计次，仅供展示。计次证据单独使用 `qaLeavePlanner NO`、普通真实查询及初始 `leavePlannerTrialsUsed 0`；样例截图不作为扣次证据。

Astra（GPT-6 Astra / XHigh）已完成前两轮结构、英文底部、大字号与俄语菜单审核。最新计次文案、全名入口及起始星期设置补审结果见[回归记录](../../docs/reviews/2026-10-08-holiday-calendar-recommendations.md)。没有 Android 设备视觉、iPad、横屏或全语言矩阵验收。
