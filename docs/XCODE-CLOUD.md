# Xcode Cloud：iOS TestFlight 工作流

仓库已经提供 `src-mobile/ios/App/ci_scripts/ci_post_clone.sh`。Xcode Cloud
克隆仓库后会安装项目要求的 Node.js 24、执行 `npm ci`，并运行 `npm run check:watch-fixtures`、
`npm run check:ios-rule-fixtures` 和 `npm run check:ios`。不要在 Xcode Cloud 中跳过这个脚本。
自 019 R4 起 iOS 不再生成或打包 JavaScriptCore 规则包。
Watch 与排班、提醒、汇总与收入规则（019 R1–R3）的 Swift 差分 fixture 是需提交的测试输入；规则变化后运行
`node scripts/generate-watch-shift-fixtures.mjs` 和 `npm run generate:ios-rule-fixtures` 更新，检查模式发现过期或缺失会失败，不会自动改写验收值。

## App Store Connect 中的一次性配置

1. 选择 `src-mobile/ios/App/App.xcodeproj`、共享的 `App` scheme 和 iOS 平台。
2. Start Condition 选择 Branch Changes，分支设为 `main`。
3. 文件过滤至少包括 `src-mobile/ios/**`、`lib/countdown.ts`、
   `lib/reminders.ts`、`lib/summary.ts`、`lib/watch-projection.ts`、`public/locales/**`、
   `src-tauri/macos-widget/**`（Widget 界面与 Mac 版共用，编进 iOS 小组件）、
   `scripts/ios-schedule-rule-oracle.mjs`、`scripts/check-ios-strings.mjs`、
   `scripts/generate-ios-schedule-rule-fixtures.mjs`、`scripts/generate-watch-shift-fixtures.mjs`、
   `scripts/generate-watch-localizations.mjs`、`scripts/check-ios-project.mjs`、`scripts/check-version.mjs`、
   `scripts/xcode-product-versions.mjs`、`package.json` 和 `package-lock.json`。这些路径都会改变 iOS
   包体、它使用的规则或本地检查结果。`src-mobile/ios/**` 已覆盖 `WatchApp`、`WatchWidgets`、
   `WatchAppTests` 与 `Shared`。
4. 添加 Archive action，scheme 选择 `App`，Deployment Preparation 选择
   **TestFlight and App Store**。共享 scheme 的 Archive configuration 已固定为 Release。
5. 添加 TestFlight Internal Testing post-action，并选择内部测试组。Xcode Cloud 会为每次
   构建自动分配递增的整数 build number；项目中的 `MARKETING_VERSION` 仍由版本发布流程维护。

首次运行建议暂时不加文件过滤，确认签名、App Group、Widget Extension 和 TestFlight
分发全部成功后，再启用上述过滤。工作流本身保存在 App Store Connect，不会写回仓库。

## Release 约束

- App 与 Widget 的 Release configuration 都不能定义 `DEBUG`；
  `npm run check:ios` 会阻止误配置。
- 欢迎页强制重放、QA 路由、强制旋转和分享页自动弹出只允许放在 `#if DEBUG` 中。
- 规则的 Swift 差分 fixture 必须由当前 `lib/` 生成，禁止手工编辑。
- iOS 文案以 `Localizable.xcstrings` 为准，直接编辑（019 L2b 起不再生成）。`ci_post_clone.sh` 会跑
  `npm run check:ios-strings`：某条缺语言、仍是英文、占位符与英文不一致；代码要的键不在 catalog，或 catalog
  里有没人要的键；两端共用的键措辞不一致；或 Widget 要读的键已从 `public/locales` 删除时，都会失败。
  Watch 文案表由 catalog 生成。
- Xcode Cloud 归档前仍建议先在本机执行一次 Release 编译；动效和横竖屏体验最终以真机为准。

## 3.2.0 整改的 PR 门禁

2026-09-19 远端核对：PR #207 的 `App | PR Check`、`App | PR Check | Test - iOS` 和 `App | PR Check | Test - watchOS` 均为 SUCCESS，说明下面的 PR 验证流程已实际运行。main 的旧分支保护 API 返回 `Branch not protected`，生效 rulesets API 返回空列表，尚未设为强制合并门禁。新版本的归档和 TestFlight 验收仍独立进行。

018 要求保留上面的 main 归档分发工作流，另建 PR 验证工作流。以下是工作流要求；修改此文档不代表 GitHub 合并规则已经生效。

- PR 工作流使用同一工程、共享 App scheme 和 `ci_post_clone.sh`，执行构建与自动化测试，不配置 TestFlight 分发。
- 路径过滤覆盖 `src-mobile/ios/**`、`lib/**`、`public/locales/**`、iOS 规则／工程／版本检查脚本及 npm 依赖文件。
- 保存实际执行的测试数量和结果包。测试选择器匹配零项不能作为通过；性能比较使用串行运行，不以并行任务的墙钟耗时设阈值。
- 首次成功运行后，在仓库合并规则中选择该工作流实际产生的检查名称作为必需检查，不能预填猜测的名称。
- Watch targets 已加入工程：`App` scheme 构建时依赖并嵌入 `DoneAt Watch App`（其 `PlugIns` 含 `DoneAt Watch Widgets`），所以 main 归档工作流无需另选 Watch scheme。PR 工作流除 `App` scheme 的 iOS 模拟器测试外，另加共享 `DoneAt Watch App` scheme 在 watchOS 模拟器上的 Test action（运行 `WatchAppTests`）。发布归档的签名、Watch App Group 与真机验收继续遵循 017。
- 本机等价命令（2026-09-13 实测可用）：

  ```bash
  npm run check:ios
  xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
  xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme "DoneAt Watch App" \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)' -parallel-testing-enabled NO test
  ```

- `WatchAppTests`、`WatchApp`、`WatchWidgets` 与 `Shared` 是**显式引用**，不是同步文件夹：磁盘上新增的测试文件若没登记进目标 Sources，Watch scheme 会照常显示成功却一项未跑。`npm run check:ios` 对已有 Watch 测试文件做 Sources 计数检查；新增文件时同时登记目标并扩展该检查，并核对实际执行的测试数量。

| 工具链路径 | 本地状态 | 验收用途 |
| --- | --- | --- |
| Xcode 26.6／iOS 26.5 SDK | 已用于 018 当前实现的自动化测试 | 现有 iOS 26 路径与数据兼容 |
| Xcode 26.6／watchOS 26.5 SDK＋Simulator runtime 23T570 | 已用于 shipping Watch 构建、WatchAppTests 与配对模拟器通信检查 | Watch 目标、嵌入与 WatchConnectivity 模拟验证（不代替真机） |
| 含 iOS 27 SDK 的 Xcode | 2026-09-19 已用于完整 802 项 iOS 测试及手机 UI 走查 | 证明当前实现可构建，不代表 P4 Duo 专属适配完成 |
| 含 iOS 27.1 SDK 的 Xcode | 本机尚未提供 | ArrangementView／Duo 分区的编译与回归 |

新 SDK 路径必须使用对应工具链验证；`#available` 不能使旧 SDK 识别它没有声明的 API。Duo 的模拟验证和真机体验分别记录，不互相代替。
