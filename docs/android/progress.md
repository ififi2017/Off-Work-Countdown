# Android 移植进度

更新：2026-09-21。交接包 1.1。源 SHA `9252fdfdc66aab88b4acb7493684f11991fd773d`。

## 本轮任务

| ID | 状态 | 证据 |
|---|---|---|
| T00 | IMPLEMENTED | `docs/android/baseline.md`。未 reset 工作区。QA-001 分支创建 NOT_RUN。 |
| T01 | IMPLEMENTED | `source-inventory.md`、`feature-parity.md`、`conflicts.md`。源读自固定 SHA。未跑 iOS XCTest。 |
| T02 | IMPLEMENTED | `wire-contract.md`、`synthetic-archives/`。检查：`node scripts/android-synthetic-archives.mjs --check`。Kotlin 导入 **NOT_RUN**。 |
| T03–T26 | NOT_STARTED | — |
| T27 | DEFERRED | Wear，不阻塞首发 |

handoff `tasks.json` 保持 1.1 快照，不在此回写。

## 执行状态

| 项 | 状态 |
|---|---|
| Android 工程 | 未创建（本轮按交接提示先做 T00–T02，未生成假页面） |
| 自动化应用测试 | NOT_RUN |
| 真机 / 模拟器 | NOT_RUN |
| Play / OAuth / 验证服务 | 未操作 |

## 下一任务

**T03 · 创建最小可构建原生工程**（依赖 T00，无未批决策阻塞本地 Debug）。

先读：`02_TECHNICAL_GUIDE.md` 第 2、3、14 章；AGP 9.4 / Compose BOM `2026.09.00` / Kotlin 2.4.10 官方页。

本机阻塞：可用 **arm64 JDK 17+**、Android SDK（compileSdk 37、targetSdk ≥ 36）。未就绪时仍可先写 Gradle 文件，但不得声称 `assembleDebug` 通过。

候选默认（发布前冻结）：`applicationId=com.rainif.doneat`，minSdk 26，versionName 3.2.0，versionCode 1。

T04 依赖 T03。T05 依赖 T02+T03。T06 依赖 T01+T02，不依赖 SDK。

## 本轮命令

```text
git show -s --format='%H' 9252fdfdc66aab88b4acb7493684f11991fd773d
git rev-parse HEAD
git status --porcelain
git log --oneline HEAD..9252fdfdc66aab88b4acb7493684f11991fd773d
java -version   # 失败：Bad CPU type in executable
node scripts/android-synthetic-archives.mjs
node scripts/android-synthetic-archives.mjs --check
```

未运行：`npm test`、`./gradlew`、模拟器、Play、任何 XCTest。
