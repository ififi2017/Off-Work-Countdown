# 商店素材本地化核对与配套修正

## 范围

用户授权一个子代理制作全部截图，先审文案，再逐图检查溢出和遮挡；主代理复核。保持八页顺序与已确认构图，首张针对语言单独编辑；用户同时进行真机走查。

## 主代理发现并修正

- 巴西葡萄牙语节日名原为英文：源包只有 pt_BR，而生成器只匹配 pt。现在精确语言不可用时优先采用该国相同语言的原生地区变体（如 pt_BR、pt_PT），再沿用已有兜底。
- 用锁定 wheel 与 China 数据重生成，比较全部 249 个地区后确认日期、休息/上班标记不变。变更只影响 17 个地区的原生语言名称；所有现有 19 个 App locale 均保留。
- 新增巴西独立日葡萄牙语资源回归检查；数据版本、输出 hash 与截图 Demo 名称同步更新。
- 月历增加纯 DEBUG 的 ios.native.qaScheduleDate 启动参数，仅导航到目标月份并选中日期，不改变时钟或保存排班。
- Watch ReviewFixture 增加纯 DEBUG 的本地化标签与时区参数，由截图脚本从生产目录提取对应语言标签，避免非中英界面出现 Working。生产通信与解析未变。
- 识图发现跨场景捕获时，番茄钟记录时区与原生时间格式化时区不同；App 入口增加纯 DEBUG 的 ios.native.qaTimeZone，启动时设置进程默认时区。截图同时配置归档、偏好和进程时区，不修改系统时间或设备设置，Release 不包含该入口。增量构建通过。

## 验证

- Holiday resource check：通过（249 regions、2632 names）。
- Holiday 专项测试：2/2 通过。
- lint：通过（截图脚本后续更新仍需最终再查）。
- check:ios：通过。
- npm test：最初因 String Catalog 自动提取条目失败。9 月 20 日已保留其他并行改动，仅修复非语义条目的提取方式并删除对应 10 个条目；19 语言检查通过，串行 npm test 35 文件 / 413 项通过。
- 后续真机反馈修复：iOS 61 项相关回归、首次引导 23 项复验、Watch 24 项通过，最终 iPhone/Watch 组合构建通过；详见 [真机反馈修复记录](2026-09-20-ios-device-regressions.md)。
- 独立 Debug iOS simulator build：通过，含 Watch 嵌入目标；Watch 参数增量构建也通过。
- 构建目录：/private/tmp/owc-store-locales-build；日志：/private/tmp/owc-store-locales-build.log。

## 并行工作保护

保留用户实时修改的 AGENTS.md、docs/agent-guides、project.pbxproj、Info.plist 与 Watch scheme；Localizable.xcstrings 仅按条目插入说明、修复法语文案与删除误提取项，不重排或回退其他改动。不因新生成截图宣称真机或 ASC 发布门禁完成；本轮没有上传或发布。
