# 3.1.9 真机反馈实施与验收

范围与已确认口径见 [计划 015](../../plans/015-device-feedback-life-income-settings-sync.md)。本轮在隔离工作树实施，未改动用户原工作区的 Xcode 工程调整，未上传 App Store / TestFlight。

## 实施结果

- iPad 根页面左右 16 pt，侧边栏打开时二级页面内容左右 32 pt。导航容器保留稳定、对称的 frame；Records 双列重新包含标题和全部记录入口。周/月只让图表切换，不带动总结做整页过渡。辅助字体改用单列以避免窄列截字。
- 周/月/年总结分实际、计划/估算和合计。共享 TypeScript 对实际开始/停止与有效工作片段求交（排除午休），修正班次使用原排班时长作薪资分母；当前班次剩余时间单列预计，工时不重复。重复/缩短的加班声明、历史未停止事件、跨午夜均有回归。
- 人生档案支持粗略工作年份或多段精确任职日期/月薪/年薪。出生年份提供可编辑的入学/工作建议，退休默认 60；日薪设置经共享规则换算后预填。职业空档不计工作时间或历史收入。人生总结显示历史、退休前预计与终身税前总收入，未来开始工作前不提前计薪。
- 用户选择开启私有 CloudKit 后同步排班、薪资、提醒偏好、主题、语言、人生档案及原有记录/Focus。沿用既有 RecordRow 的 opaque payload，无新增 CloudKit record type/field。备份版本为 5，接受 1–5；设备授权、隐藏薪资/生物识别及实时活动开关不随设置复制。
- 首次 Plus Records 入口提供可跳过的人生档案说明，复用既有本机 dismissal 状态。欢迎流程新增 Records/Life 和 Focus 两页演示，兼容减少动态效果，未启动真实计时。
- 健康提醒的 Focus 接管入口改用标准设置行与原生导航。小组件复用 App 的 Focus 事件投影，休息日和无运行班次也包含已安排任务；薪资不进入 WidgetSnapshot。共享 WidgetKit 展示名称统一 DoneAt，未新增 Tauri 业务代码。
- 更新全部 19 种语言及移动端同步计划、隐私说明。

## 自动化证据

- `npm test`：27 个文件、341 项通过。
- iOS：392 项 Swift Testing、6 suites 通过；`/tmp/owc-feedback-tests-migrated.xcresult`。
- 共享 WidgetKit package：12 项通过，含真实 SwiftUI widget 编译。
- lint、版本一致性、check:ios、Web build + validation、Desktop export + validation 通过。
- iOS rules 已由当前 TypeScript 重建，模拟器构建通过。后续仅界面布局/说明微调已补增量构建；未把语法解析当作完整构建。

## 视觉与升级证据

本机截图与录屏目录：`/tmp/owc-feedback-shots`（不提交生成媒体）。

- iPad Pro 13-inch：横竖屏 Records 标题、侧边栏根页及排班二级页两侧留白已实际检查。`ipad-records-landscape.png`、`ipad-records-portrait.png`、`ipad-schedule-landscape.png`、`ipad-schedule-portrait.png`。
- 最终构建的 iPad 横屏深色 Records 已实际检查，双列、标题、估算说明和卡片边距正常。
- 最大辅助字体下已实际检查 Records 自动退为单列，侧边栏倒计时保持单行：`ipad-records-accessibility.png`。
- 排班 push 录屏已抽帧检查标题落点，未见先贴边再反向回弹：`ipad-settings-push.mp4`、`push-title-frames.png`。这不是 60 fps 性能测量。
- iPhone 英文欢迎页：实际走完流程并切换 Focus/短休息演示；发现人生说明被压成单行后补 `fixedSize`，倒计时示例与进度值也已对齐。
- 同一 iPad 模拟器从本轮早期构建升级出现的档案读取失败已定位：旧 `editedAt` Date 与新 `editedAtMs` 字段不兼容。现在双读、统一新写，并增加完整文档回归。保留原容器覆盖安装后，原记录已恢复显示；没有清空、隔离或重建档案来绕过失败。

## 仍需补充验收

- Plus 首次提示的完整购买/恢复购买路径、欢迎页最后文案修正后的完整浅深色截图矩阵仍需补验；当前已有提示条件实现及模型测试，不能视作完整端到端购买验证。
- 双设备离线修改/重连、相同字段竞争、账号切换、Production 真实收发；模型测试不证明 iCloud 服务端行为。
- 已有 CloudKit 开发/生产环境的缓存分区尚未实现，不能仅凭 Debug/Release 猜测签名环境。切换 TestFlight 与 Xcode 构建仍需按原云同步验收矩阵检查。
- 更老二进制不认识 schema 5 与新增实体，不保证降级读取新档案；升级迁移已覆盖。
- CUA 的拖动/滚轮未能稳定驱动模拟器 ScrollView，独立滚动的触摸手感仍需真机确认；两侧代码保持独立 ScrollView。所有设置子页、Focus 过渡和极端辅助字体的完整真机矩阵仍需签收。
- macOS 名称已检查共享代码/编译，未重装真实 macOS WidgetKit gallery 验证系统缓存刷新。macOS 没有 Focus 任务生产端，未声称任务可跨到 Tauri 主程序；目前可复用的是共享展示能力。
- 官网隐私页与 App Store 隐私问卷需在提交时核对本轮增加的可选薪资同步范围；未自动发布外部站点或商店元数据。
