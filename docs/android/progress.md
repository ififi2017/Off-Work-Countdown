# Android 移植进度

**这是任务状态的唯一记录。** 交接包 `tasks.json` 只定义依赖、范围和验收，不记录状态。

更新：2026-09-23。交接包 1.2。源 SHA `9252fdfdc66aab88b4acb7493684f11991fd773d`。

## 任务状态

状态：NOT_STARTED → IN_PROGRESS → IMPLEMENTED → VERIFIED；另有 WAITING_OWNER、BLOCKED、DEFERRED。

| ID | 状态 | 证据 / 备注 |
|---|---|---|
| T00 | IMPLEMENTED | `baseline.md`。未 reset 工作区。QA-001 分支创建 NOT_RUN。 |
| T01 | IMPLEMENTED | `source-inventory.md`、`feature-parity.md`、`conflicts.md`。源读自固定 SHA。未跑 iOS XCTest。 |
| T02 | IMPLEMENTED | `wire-contract.md`、`synthetic-archives/`。检查：`node scripts/android-synthetic-archives.mjs --check`。Kotlin 导入 NOT_RUN。 |
| T03–T20 | NOT_STARTED | — |
| T21 | DEFERRED | 服务端验证，首发后（D-08 修订） |
| T22 | DEFERRED | Drive 同步，首发后（D-02 修订） |
| T23–T26 | NOT_STARTED | — |
| T27 | DEFERRED | Wear，首发后（D-05） |

## 执行状态

| 项 | 状态 |
|---|---|
| Android 工程 | 未创建 |
| 自动化应用测试 | NOT_RUN（140 条；首发 126 条） |
| 真机 / 模拟器 | NOT_RUN |
| Play Console | 未操作 |

## 下一任务

**T03 · 创建最小可构建原生工程**（依赖 T00，无未批决策阻塞本地 Debug）。

先读：`02_TECHNICAL_GUIDE.md` 第 2、3、14 章；`docs/agent-guides/android.md`。

环境（详见 `baseline.md`）：SDK 已就绪（compileSdk 37 可用）；`JAVA_HOME` 指向 Android Studio JBR（arm64）；无 cmdline-tools，需要时从 Android Studio SDK Manager 安装。T03 需确认所选 Gradle 版本能在 JBR 25 上运行，否则另装 arm64 JDK 17/21。

候选默认（发布前冻结）：`applicationId=com.rainif.doneat`，minSdk 26，versionName 3.2.0，versionCode 1。

之后可并行：T04 依赖 T03；T05 依赖 T02+T03；T06 依赖 T01+T02，不依赖 SDK。

## 基线漂移记录

每个里程碑结束运行：

```text
git log --oneline 9252fdfdc66aab88b4acb7493684f11991fd773d..origin/main -- lib src-mobile/ios/App/App/Native/Models src-mobile/ios/Shared
```

| 日期 | 基线之后影响规则的提交 | 处理 |
|---|---|---|
| 2026-09-23 | 0 | 无需跟进 |

## 变更记录

- 2026-09-21：T00–T02 完成。
- 2026-09-23：交接包 1.2（D-02/D-08 修订、新增 D-12），T21/T22 延后；进度只在本文件维护；本机 SDK 就绪。
