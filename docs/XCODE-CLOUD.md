# Xcode Cloud：iOS TestFlight 工作流

仓库已经提供 `src-mobile/ios/App/ci_scripts/ci_post_clone.sh`。Xcode Cloud
克隆仓库后会安装项目要求的 Node.js 24、执行 `npm ci`、生成未提交的
`CountdownRules.js`，并运行 `npm run check:ios`。不要把生成文件提交进 Git，
也不要在 Xcode Cloud 中跳过这个脚本。

## App Store Connect 中的一次性配置

1. 选择 `src-mobile/ios/App/App.xcodeproj`、共享的 `App` scheme 和 iOS 平台。
2. Start Condition 选择 Branch Changes，分支设为 `main`。
3. 文件过滤至少包括 `src-mobile/ios/**`、`lib/countdown.ts`、
   `lib/reminders.ts`、`lib/summary.ts`、`public/locales/**`、
   `scripts/build-ios-native-rules.mjs`、`scripts/check-ios-project.mjs`、
   `package.json` 和 `package-lock.json`。这些路径都会改变 iOS 包体或它使用的规则。
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
- 规则资源必须由当前 `lib/` 生成，禁止手工编辑或提交生成的 JavaScript 文件。
- Xcode Cloud 归档前仍建议先在本机执行一次 Release 编译；动效和横竖屏体验最终以真机为准。
