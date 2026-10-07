# 2027 中国大陆预测假期

用户于 2026-10-07 批准在正式数据更新前使用以下安排，并持续提示数据为推测。此决定替代计划 020 中原先不使用中国大陆未来预测的要求。

| 节日 | 预测休息日 | 预测补班日 |
| --- | --- | --- |
| 元旦 | 1 月 1–3 日 | 无 |
| 春节 | 2 月 5–13 日 | 1 月 31 日、2 月 14 日 |
| 清明 | 4 月 3–5 日 | 无 |
| 劳动节 | 5 月 1–5 日 | 5 月 8 日 |
| 端午 | 6 月 9 日 | 无 |
| 中秋 | 9 月 15 日 | 无 |
| 国庆 | 10 月 1–7 日 | 9 月 26 日、10 月 9 日 |

采用主方案，共 29 个休息日、5 个补班日；未纳入国庆九天备选，也未添加 2028 年及以后的中国大陆预测。

## 数据与提示

- 独立、可审阅的本地来源为 `scripts/data/china-2027-prediction.v1.json`，版本和 SHA256 锁在 `scripts/holiday-template-sources.json`。不把它冒充 holiday-cn 的正式公告。
- iOS、Watch、Android 共用 `HolidayTemplates.json`；Web/Desktop 由同一来源导出。中国大陆覆盖扩大到 2007–2027，`estimatedYears: [2027]` 明确区分预测与正式数据。原有中国大陆 2007–2026 数据、名称表及其他 248 个地区的数据保持一致。
- iOS / Android 排班月历、接下来和请假规划显示预测提示；预测假期或补班的日期详情附“推测”，请假结果与日历附“使用 2027 年推测假期”。Web/Desktop 排班月历和日期读法使用相同标识。2026 年 12 月提前提示即将使用的预测年份。
- 19 语均有完整提示及短标；iOS 现有 en-GB / es-MX 和 Android 生成资源同步。提醒为持续可读文案，不阻止操作或反复弹窗。

简体中文完整文案：

> 2027 年中国大陆节假日与调休安排为推测，仅供参考，请勿作为真实假期信息。请以国务院年底发布的正式通知为准；DoneAt 将在下一年度安排公布后尽快更新，请及时更新软件。

预测通过现有地区节假日解析器参与计算，手动排班继续优先。不新增网络请求、后台监控或日期预测算法；进入 2027 年也不会自动将预测改标为正式。

## 正式公告发布后的更新

1. 核对国务院正式通知及上游 holiday-cn 对应年份的公告链接和日期。
2. 按现有来源锁更新流程审阅上游提交、输入哈希和数据版本，重新生成模板。当该年份的 `papers` 和 `days` 均非空时，生成器优先正式数据，并自动撤掉该年份的 `estimatedYears`；只有两者均为空才使用本地预测，一边为空会报错。
3. 更新输出 SHA256，重新导出 Web/Desktop JSON、跨端 fixtures，运行模板校验、跨端回归和各端构建，然后随软件新版发布。
4. 提示由数据元信息决定；用户安装包含正式数据的版本后，预测说明撤下。已保存的手动排班、休假方案和历史记录不由数据更新静默覆盖。

## 验证记录

本轮自动检查跨午夜执行至 2026-10-08；预测来源的批准日期仍为 2026-10-07。

数据验证已通过：固定输入两次完整生成字节一致；新增 34 个日期精确匹配批准方案；6 项生成器/导出测试、模板校验及 Desktop 导出一致性通过。模板 SHA256 为 `7b57ef1542ac6ec8613d4cf0a2677922ec74199296560928e3e686d6a716f0a8`。

新增回归覆盖预测假期、五个补班日、春节九天零请假成本、手动排班优先、未选中国大陆/未启用时不影响、2028 年仍未覆盖，以及正式替换后移除预测标识。

- `npm test -- --maxWorkers=2`：50 个文件、552 项全部通过。首轮仅发现两个未再生成的 Android fixture，生成后完整重跑通过，无未处理错误。
- lint、`check:ios`、`check:ios-strings`、Android 生成翻译检查、版本检查、模板校验、Desktop 日历一致性及 `git diff --check` 通过。
- Web build / `check:build:web`、Desktop build / `check:build:desktop` 通过。Desktop 初次图标编译被沙盒阻止访问系统编译服务和缓存，同命令在批准后的本地构建中通过。
- Android 最新完整 Gradle gate 通过：四模块单测、`lintDebug`、`assembleDebug`、`assembleRelease`，`BUILD SUCCESSFUL in 24m 29s`（188 tasks，25 executed / 163 up-to-date），证据为 `/private/tmp/doneat-android-cn2027-final-output.log`。domain 411 / data 89 / design-system 12 / app 50，共 562 项通过，主代理已逐一核对 62 份 XML 的 tests / failures / errors / skipped（后面三项均为 0）。Lint 为 0 error、49 warning、3 hint，不声称零警告。
- Android 按规定核对 `9252fdfd..origin/main` 在共享规则路径的漂移：52 条提交，最新 `d2532ab7`，最早 `a6a6c382`，完整记录 `/tmp/doneat-android-cn2027-drift.log`。冻结来源 `9252fdfd` 和已授权 Plan 020 增量 `18129168` 不变；本轮仅纳入用户批准的预测数据、元信息和提示，没有自动移植其余主干规则。
- iOS 最终无界面 arm64 simulator build 通过（`/private/tmp/doneat-holiday-ios-arm64-build.log`，`BUILD SUCCEEDED`），包含 App、Widget 和 Watch 目标。Xcode MCP 调用超出 300 秒工具时限，但其后台编译继续完成；同一 DerivedData 的 CLI 测试也完成了 AppTests 编译。四个指定 suite（HolidayTemplateTests / LeavePlannerTests / ScheduleRuleFixtureTests / WatchIndependentScheduleTests）因现有 iPhone 17 / iOS 27.0 的 `com.apple.instruments.deviceservice.lockdown` 连接超时而未启动，已结束本轮测试，没有将编译成功或零项测试当作测试通过。
- 预览尝试使用本机回环地址；本轮 Desktop 静态导出在普通浏览器中未能进入月历，Web 构建不提供该原生客户端排班入口，因此不能用普通网页画面代替客户端视觉验收。未验证 Android 真机或 Desktop 原生壳界面。临时预览服务已结束。

本轮未发布、未上传商店，保留工作区中已有的其他任务改动。iOS 未进行手动界面或截图验收；依据仓库规则仅执行无界面构建及自动测试。

协作分为数据生成、Android 实现和翻译，主代理审查并集成 Swift / TypeScript 与文档。数据子代理使用工具支持的 GPT-6.1 Sol / High 配置；其他子代理继承完整会话上下文，工具未提供可独立核对的实际底层模型标识，不能声称已核实与模型偏好表完全一致。
