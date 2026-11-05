# 2027 中国大陆正式放假安排（3.2.5）

## 已核对来源

- 国务院办公厅《[关于2027年部分节假日安排的通知](https://www.gov.cn/zhengce/content/202611/content_7085101.htm)》，国办发明电〔2026〕10号，2026-11-05 发布。已直接读取正文，逐项核对放假与补班日期；政策文件库的[同文页面](https://www.gov.cn/zhengce/zhengceku/202611/content_7085102.htm)与正文一致。
- `holiday-cn` 固定到 [`a91748e8d6dd21ede3728a2f5bbb16e3a30daf6e`](https://github.com/NateScarlet/holiday-cn/commit/a91748e8d6dd21ede3728a2f5bbb16e3a30daf6e)。对照原固定提交 `18c8f140`，2007–2026 JSON 与 MIT 许可没有变化，2027 JSON 新增正式公告及 34 个日期。上游其余变动仅为 ICS 和开发工具配置，不进入产品。
- 输入 SHA256、公告元信息与输出 SHA256 记录在 `scripts/holiday-template-sources.json`。不通过运行时网络或当前年份把预测自动转正。

| 节日 | 正式休息日 | 正式补班日 |
| --- | --- | --- |
| 元旦 | 1 月 1–3 日 | 无 |
| 春节 | 2 月 5–13 日 | 1 月 31 日、2 月 14 日 |
| 清明 | 4 月 3–5 日 | 无 |
| 劳动节 | 5 月 1–5 日 | 5 月 8 日 |
| 端午 | 6 月 9 日 | 无 |
| 中秋 | 9 月 15 日 | 无 |
| 国庆 | 10 月 1–7 日 | 9 月 26 日、10 月 9 日 |

共 29 个休息日、5 个补班日，与此前获准的预测逐日一致。正式来源优先于历史预测文件，生成器撤下 `estimatedYears`。历史预测输入保留为可追溯记录和生成器回归测试输入，不再参与本次正式数据生成。

iOS、Watch 和 Android 使用同一份 `HolidayTemplates.json`；Web/Desktop 更新 `CN.json` 与索引，所有端按元信息撤下“推测”及相关提示。2026 年 12 月不再预警 2027 年预测；2027 年 12 月仍提示尚未覆盖的 2028 年。手动排班继续优先，已有休假方案、历史记录与其他 248 个地区不变。产品各端版本在本轮开始时已统一为 3.2.5，无需再次改号。

## 验证

- [x] 七个节日及五个补班日逐项对照国务院原文；34 个日期与固定上游 JSON 精确匹配。
- [x] 使用固定 wheel 和上游文件两次完整生成，字节一致；所有名称、中国历史日期和其他 248 个地区与原始模板一致。Web/Desktop 仅两份文件更新。
- [x] 数据校验、Desktop 导出一致性、各端版本 3.2.5 一致性检查。
- [x] 完整 Vitest：59 个文件、721 项通过；lint、iOS 文案及 TypeScript/iOS/Android 规则 fixture 检查通过。Android extended fixture 按真实 Swift 重新生成，只有 `holidayDataset` 与来源哈希更新，所有规则答案不变。
- [x] iOS 无界面 simulator build（含 App、Widget、Watch）通过。另直接编译并执行真实 Swift 核心，验证 2027 年正式覆盖、34 个日期/5 个补班日、节日与补班标注均无推测、2028 年未覆盖。该直接检查不代替 AppTests 的模拟器执行。
- [ ] iOS AppTests 执行未通过：节假日／日期标注／请假规划／分组测试均编译成功，但两次运行各等待约五分钟仍未启动任何用例，已结束运行。未把编译成功、零项测试或中断当作通过；全程最多一个模拟器，没有手动视觉验收。
- [x] Android 四模块单测共 807 项通过（domain 469、data 97、design-system 13、app 228），逐份 JUnit XML 核对失败/错误/跳过均为 0。
- [x] Android 全部门禁成功（6m20s、188 tasks）：四模块测试、`lintDebug`、`assembleDebug`、`assembleRelease`。lint 为 0 error、75 warning、4 hint；保留已有告警。iOS 构建产物与 Android Debug/Release APK 中的日历 SHA256 均精确匹配锁定输出。

没有执行 iOS 模拟器视觉验收或真机升级验证。本轮通过 Xcode MCP 打开工程时，连接要求本机授权，因此使用仓库已规定的 CLI 无界面构建/自动测试；未把接口授权失败写成构建失败。

Android 漂移命令只读核对 `9252fdfd..origin/main` 的共享规则路径，共 71 条，最新 `08dbfd22`、最早 `a6a6c382`。本轮只更新获授权的正式假期数据与测试，不推进冻结源或移植其他主干规则。

测试子任务使用工具明确配置的 GPT-6.1 Sol / High，主代理审查并集成；主代理会话未提供可独立核对的底层模型名称。发布状态将在实际证据取得后记录，不以本地检查代替上传、审核或上架。

Web build 与 `check:build:web` 已通过。PR [#362](https://github.com/ififi2017/Off-Work-Countdown/pull/362) 的 [Vercel 预览](https://off-work-30-git-codex-cn-holidays-2027-ififi2017s-projects.vercel.app)已生成；不据预览部署状态声明生产发布。

本地日志：`/private/tmp/doneat-cn2027-tests-final.log`、`doneat-cn2027-web-build.log`、`doneat-cn2027-ios-build.log`、`doneat-cn2027-ios-tests-final.log`、`doneat-cn2027-android-final.log`（均在 `/private/tmp/`）。Swift 直接检查输出为 `/private/tmp/doneat-cn2027-swift-smoke/output.log`。PR 仍未合并；没有上传或发布商店包。
