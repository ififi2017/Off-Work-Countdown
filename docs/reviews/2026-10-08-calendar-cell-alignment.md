# 月历基线、方格与预测说明（2026-10-08）

用户三张真机截图显示：节名与无说明日期错位、移除旗帜后仍有图例、预测三角未居中、预测说明在入场动画前提前出现，以及记录月历日期／调休／横条间距不均。

## 修正

- iOS 请假格统一日期和说明高度，空说明也占相同槽位，移除无上限的透明占位。网格整体测量宽度，普通字体取列宽与内容最小高度的较大值，大字号允许增高；月历背景带、点击和全名详情不变。
- 图例按当前月份实际画出的符号生成，节名替代图标的日期不再贡献旗帜图例；业务 holiday 分类仍保留，无注释的旗帜兜底仍有对应图例。
- 预测警告用居中 HStack／Row，图标对齐整段文字中心；与摘要和月历共用 arrival 状态，按摘要、提醒、月历顺序渐入。减少动态效果沿用既有行为。
- 记录月历把日期、节名、横条放进同一布局，各槽位和间隔统一；空说明、空横条保留位置，普通字体按列宽接近方格，大字号可纵向增长。选中描边、斜纹、状态角标和日详情动作保留。
- Android 对应修正同步到三个 UI 文件；规则、假日数据、查询排序、额度计次、购买和文案未改。

## 验证与审核

- iOS 最终 XcodeBuildMCP 构建成功，日志 `build_run_sim_2026-10-08T05-58-11-410Z_pid2841_6ac8597e.log`；`check:ios`、`check:ios-strings`、Android 生成检查及 diff 检查通过。仅布局修正，没有新增镜像实现的测试或重跑不相关的 JavaScript 套件。
- Android 最终七项门禁通过：690 项（domain 437 / data 95 / design-system 12 / app 146），0 failure/error/skip，主代理独立核对 XML；lint 0 errors / 54 existing warnings / 4 hints，Debug / R8 Release 成功。日志 `/private/tmp/doneat-calendar-square-leave-android-final-gradle.log`。Astra 要求补齐 Android 请假格按列宽扩展后，全部七项门禁再次通过；主代理再次独立核对 XML。
- 单台 iPhone 17 / iOS 27 实际点按核对中文浅色／英文深色，2026-09 请假月历、2027-02 预测提醒、2026-10 记录调休格、系统 accessibility-large，以及长英文节名省略与点击全名。实际录屏逐帧核对预测提醒入场。见[截图与复现](../../qa/2026-10-08-calendar-cell-alignment/README.md)。
- 按用户此前要求，GPT-6 Astra / XHigh 在实施前确认源码根因和修正范围；完成后复审实际 iOS 截图、入场帧及两端源码，通过英文深色省略与点击全名验证；按反馈补齐 Android 网格层尺寸后，再次确认最终通过，无剩余阻塞项。Android 修正协作使用 GPT-6.1 Sol / High。
- 规定 Android model/shared 漂移命令基于最新 `origin/main=d462fdaf` 输出 55 条，日志见 QA 的 `android-model-drift.txt`；冻结源 `9252fdfd` 与授权增量 `18129168` 未推进，本轮只修正 UI。
- 本轮无 Android 设备视觉、iPad／横屏或全语言矩阵验收，无真实购买测试；原产品工作区未提交内容未改动。PR #307 已合并，因此基于最新 main 的 `codex/calendar-cell-alignment` 单独提修复 PR，不直接推 main 或发布。
