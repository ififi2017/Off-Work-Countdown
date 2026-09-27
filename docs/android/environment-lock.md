# Android 环境锁

更新：2026-09-26。此页记录当前本机工具链与已跑命令；任务状态只在 [progress.md](progress.md)。

## 工具链

| 项 | 版本 / 路径 |
|---|---|
| 机器 | macOS 27.0 arm64 |
| JDK | Android Studio 2026.1 自带 JBR，OpenJDK 25.0.3 arm64：`/Applications/Android Studio.app/Contents/jbr/Contents/Home`（系统 Temurin 21 为 x86_64，不用于本机 Gradle） |
| Gradle | 9.7.1（wrapper） |
| AGP / Kotlin | 9.4.1 / 2.4.10（含 Compose 编译器插件） |
| compileSdk / targetSdk / minSdk | 37 / 36 / 26 |
| Android SDK | `~/Library/Android/sdk`：platforms android-37.0，build-tools 36.0.0，platform-tools 37.0.1；无 cmdline-tools |
| Java 字节码目标 | 17 |
| 应用版本候选 | `com.rainif.doneat`、3.2.0、versionCode 1；首次 Play 上传前核对并冻结 |

## 当前依赖与模块

版本以 `src-mobile/android/gradle/libs.versions.toml` 为准。Compose BOM 2026.09.00（Material3 1.4.0、UI/Foundation 1.12.1）；activity-compose 1.13.0，core-ktx 1.19.0，Navigation 3 1.1.7，Lifecycle 2.11.0，Biometric 1.1.0，Fragment 1.9.0，Glance 1.2.0，Play Billing 9.1.0，Play In-App Review 2.0.2，WorkManager 2.10.5，Kotlinx Serialization/Coroutines 1.11.0，JUnit 4.13.2。Release Compose/Material3 只用稳定版本（D-12），无动态 `+` 版本。

| 模块 | 职责 |
|---|---|
| `:app` | 原生 Android UI、系统集成、Play Billing 客户端 |
| `:core:domain` | 纯 JVM 规则、记录编解码、会话与权益状态机 |
| `:core:data` | D-13 原子 JSON 档案、设置、会话与队列存储 |
| `:core:designsystem` | Compose 主题、数字、进度与组件 token |

业务记录不使用 Room；本机显示偏好另存，运行会话与购买证据不进系统备份。

## 当前本地验证

从 `src-mobile/android` 运行 Gradle，`JAVA_HOME` 指向上表 JBR。完整四模块命令：

```text
./gradlew :core:domain:test :core:data:test :core:designsystem:testDebugUnitTest :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleRelease :app:bundleRelease
```

`/tmp/doneat-boundary-final-gradle.log`：433 项 JUnit 通过（domain 336、data 74、design 8、app 15），lint 0 error / 34 warning / 1 hint，Debug、R8 Release 与 AAB 成功。包含计时恢复、专注边界/合并、进程中断和档案恢复入口。此前 7 项 Swift 职业区间、17 项数字输入/共享规则测试仍是对应修复的证据；本轮 iOS headless build 通过。当前未签名 Release APK 为 5,341,494 字节，AAB 为 9,197,491 字节；哈希见 `build/android-preconsole/artifact-hashes.txt`。ZIP/ELF 16 KiB 对齐通过。生产签名与 Play 处理结果仍须在 T24/T26 记录。

仓库侧：`npm run lint` 与 `npm test`（445 项）、`check:version`、`check:ios`、Web/Desktop build 与输出检查通过。iOS 本地 headless simulator build 、`NumberInputTests` 5 项与 `ScheduleRuleFixtureTests` 12 项通过（`doneat-number-input-final-ios.log`）；iOS/Watch 四个产物版本均为 3.2.1；真实 iOS→Kotlin→iOS v6 往返保留 12 类实体全部身份与字段。完整 QA 用例状态以 [preconsole-qa-2026-09-26.md](preconsole-qa-2026-09-26.md) 为准，不能把单测总数等同于 126 项首发验收。

API 36 设备上的 Auto Backup 清除/恢复以及系统文档化的设备转移/重装路径，均使业务档案与设备设置字节相同；运行会话、SharedPreferences 与 `no_backup` 未进入备份。直接 `bmgr restore` 返回 -1000，不能据此宣称该传输方式成功；D2D 的 device-local/no_backup 探针与 Debug Plus 未被恢复；重装后系统可触发小组件重建新缓存。真实云账户、物理换机和最终设备矩阵仍在 T23/T24。

## 2026-09-23 初始 T03 记录（历史）

当时只有 `:app`、`:core:domain`、`:core:designsystem`；domain 2 项、app 0 项测试，lint 3 warning，Debug/R8 Release/AAB 与 API 36 冷启动通过。约 747 KB 的未签名 release APK、约 1.7 MB AAB 和单个 `libandroidx.graphics.path.so` 四 ABI 16 KB 对齐，是那一版工件的测量，**不是当前包体数据**。本机未装 NDK 时出现 `Unable to strip` 提示；当前包体审计见上方独立记录。
