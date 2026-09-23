# Android 基线台账（T00）

记录时间：2026-09-21。读取固定 iOS 源，不清理工作区，不 reset / checkout。

## 固定源

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/ififi2017/Off-Work-Countdown |
| 源 SHA | `9252fdfdc66aab88b4acb7493684f11991fd773d` |
| 源提交时间 | 2026-09-20T14:07:09Z（本地 2026-09-20 22:07:09 +0800） |
| 源说明 | Merge pull request #214（ASC reviewed copy validator） |
| `origin/main` | 与源 SHA 相同 |
| 产品版本（该 SHA 的 `package.json`） | 3.2.0 |
| 指向该 SHA 的 git tag | 无 |
| 拟 Android 根 | `src-mobile/android/` |
| iOS 包名（该 SHA） | `com.rainif.offworkcountdown.macappstore`（Universal Purchase） |
| Android 候选 applicationId（D-10，未冻结） | `com.rainif.doneat` |

源码链接一律使用该 SHA，例如  
`https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md`。

## 当前工作树（未改动）

| 项 | 值 |
|---|---|
| 检出分支 | `codex/free-schedule-clear`（跟踪 `origin/codex/free-schedule-clear`） |
| HEAD | `3a3eb9ffdbf2e04eca3f1aa4b49fc2a02e5c1686` |
| HEAD 说明 | `feat(ios): clear future free-schedule plans safely` |
| 相对源 SHA | HEAD 是源的祖先；源比 HEAD **多 8 个提交**；HEAD 没有源没有的提交 |
| 源多出的提交 | `473948fd`、`f1ec0112`、`5ed68a7e`、`b09675c1`、`89d21246`、`2f8c0d38`、`a8cf8551`、`9252fdfd` |

**基线选择**：业务与字段审计只读 `9252fdf`（`git show 9252fdf:PATH`），不以工作区或 HEAD 当 iOS 规范。未把工作区切到该 SHA，也未创建 Android 分支：当前 HEAD ≠ 源，且工作区有未提交改动。QA-001「创建 Android 分支」记为 **NOT_RUN**。

未提交内容（仅登记，未恢复、未删除、未纳入本任务）：

- 已改：`AGENTS.md`、`src-mobile/ios/App/App.xcodeproj/project.pbxproj`、Watch scheme、`Info.plist`、`Localizable.xcstrings`
- 已删（工作区）：`plans/001`–`019` 与 `plans/README.md`（交接包要求以当前代码+测试为准，旧 plans 只作佐证）
- 未跟踪：`app-store-connect/ios/3.2.0*`、`docs/agent-guides/`、`docs/reviews/2026-09-19-agents-optimization.md`、`plans/Android/`、`plans/iOS/`

## 首发 / 后续范围

首发必须：FR-01～FR-20（FR-15 首发=系统备份换机恢复；FR-16 首发=客户端 Play 验证）。  
延后：T21 服务端验证、T22 Drive 同步（QA-110～QA-122）、FR-21 / T27 / QA-137（Wear OS）。延后不是已完成，也不阻塞首发。

## 决策与外部配置

| ID | 状态 | 批准范围 | 仍未知 |
|---|---|---|---|
| D-01 | APPROVED | 月/年订阅 + 终身买断 | CFG-PRICE |
| D-02 | APPROVED（2026-09-23 修订） | 首发 Auto Backup/设备转移换机恢复（业务库纳入）；Drive 同步延后（T22） | 后续：CFG-OAUTH |
| D-03 | APPROVED | 首发仅 JSON 互迁；商店权益独立 | — |
| D-04 | PROPOSED | minSdk 26 建议 | 支持矩阵未代签 |
| D-05 | APPROVED | Wear 延后 | 后续启动时间 |
| D-06 | PROPOSED | 精确提醒可选、降级 | 未代签 |
| D-07 | PROPOSED | 失效后停新增观测，先按源 | 未代签 |
| D-08 | APPROVED（2026-09-23 修订） | 首发纯客户端 Play Billing；服务端验证延后（T21），优先现有 Vercel | 后续：CFG-BACKEND |
| D-09 | PROPOSED | 敏感页保护，不全面禁截图 | 未代签 |
| D-10 | PROPOSED | 候选 `com.rainif.doneat` | CFG-APP-IDENTITY |
| D-11 | APPROVED_PROCESS_PENDING_FACTS | 按真实 Play 账户核验 | CFG-PLAY-ACCOUNT；账户事实 UNKNOWN |
| D-12 | APPROVED（2026-09-23） | Release 只用稳定 Compose/Material3，Expressive 风格用 designsystem token | — |

价格、Play 账户、正式包名均 **不阻塞** 源码审计与本地 Kotlin；OAuth 与后端已随 D-02/D-08 修订移出首发。  
本轮未询问已确认方向，未部署、未改价、未操作 Play Console。

## 本机环境（T00 登记，2026-09-23 更新，未冒充已构建）

| 项 | 事实 |
|---|---|
| 机器 | darwin arm64 |
| JDK | 系统 `temurin-21.jdk` 为 **x86_64**，不可用；可用 Android Studio 自带 JBR：`/Applications/Android Studio.app/Contents/jbr/Contents/Home`（arm64，OpenJDK 25.0.3） |
| Android SDK | `~/Library/Android/sdk`：platforms `android-37.0`、build-tools `36.0.0`、platform-tools（adb 37.0.1）、emulator、system image `android-36.1/google_apis_playstore`；**无 cmdline-tools**；`ANDROID_HOME` 未设置（工程用 `local.properties` 的 `sdk.dir`） |
| Android Studio | 2026.1；AVD `Pixel_10_Pro` |
| `./gradlew` / `assembleDebug` | **NOT_RUN** |
| 应用测试 | **NOT_RUN**（137 条 QA 仍全部 NOT_RUN） |

## 版本号四套（禁止混用）

| 协议 | 当前 |
|---|---|
| 用户备份 wire | schemaVersion **6**，接受 1…6 |
| Room | 尚未创建（将来 v1，独立） |
| 规则 fixture | 尚未创建（将来 v1，独立） |
| 同步 envelope | 尚未创建（将来 v1，独立） |
