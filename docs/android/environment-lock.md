# Android 环境锁（T03）

记录：2026-09-23。均为本机真实构建所用版本。

## 工具链

| 项 | 版本 / 路径 |
|---|---|
| 机器 | macOS 27.0 arm64 |
| JDK | Android Studio 2026.1 自带 JBR，OpenJDK 25.0.3 arm64：`/Applications/Android Studio.app/Contents/jbr/Contents/Home`（系统 Temurin 21 为 x86_64，不可用） |
| Gradle | 9.7.1（wrapper） |
| AGP | 9.4.1 |
| Kotlin（KGP、Compose 编译器插件） | 2.4.10，与 AGP 9.4.1 内置 Kotlin 对齐；lint 提示 2.4.20 可用，升级需与 AGP 一起验证 |
| compileSdk / targetSdk / minSdk | 37 / 36 / 26（targetSdk 满足 Play ≥36；minSdk 仍待 D-04） |
| Android SDK | `~/Library/Android/sdk`：platforms android-37.0，build-tools 36.0.0，platform-tools 37.0.1；无 cmdline-tools |
| Java 字节码目标 | 17 |

## 依赖

| 库 | 版本 |
|---|---|
| Compose BOM | 2026.09.00 → material3 1.4.0、ui/foundation 1.12.1（稳定，D-12） |
| activity-compose | 1.13.0 |
| core-ktx | 1.19.0 |
| junit | 4.13.2 |

Release 运行时依赖树（`:app:dependencies --configuration releaseRuntimeClasspath`）不含任何 alpha/beta/rc；CI 用同一命令拒绝 Compose/Material3 预发布版本。无动态 `+` 版本。

## 模块

`:app`（Android 应用）、`:core:domain`（纯 JVM）、`:core:designsystem`（Compose 主题；T04 补全 token）。其余模块（data/platform/billing）在对应任务创建，不先建空模块。

## 已运行命令（`src-mobile/android`，`JAVA_HOME` 指向 JBR）

```text
./gradlew --version
./gradlew :core:domain:test :app:assembleDebug
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleRelease :app:bundleRelease
zipalign -c -P 16 -v 4 app-release-unsigned.apk
adb install / am start -W（Pixel_10_Pro AVD，API 36）
```

| 结果 | 证据 |
|---|---|
| `:core:domain:test` | 2 个测试，0 失败（`BackupSchemaTest`） |
| `:app:testDebugUnitTest` | 通过；app 目前无单元测试（0 条） |
| `:app:lintDebug` | 0 error，3 warning：OldTargetApi（target 36，37 可用）、Kotlin 2.4.20 可用 ×2、MissingApplicationIcon（图标在 T04/T15 加入） |
| Debug / R8 Release | 均成功；release APK 约 747 KB（未签名），AAB 约 1.7 MB |
| 16 KB 对齐 | 唯一 native 库 `libandroidx.graphics.path.so`（来自 Compose）四个 ABI 均 OK |
| 模拟器冷启动 | 成功，无崩溃，TotalTime 3181 ms（Debug，未优化，不作性能数据） |

构建提示 `Unable to strip libandroidx.graphics.path.so`：本机未装 NDK，库按原样打包；不影响功能，T24 做包体审计时复查。
