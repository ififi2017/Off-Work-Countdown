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
| T03 | IMPLEMENTED | `environment-lock.md`；`src-mobile/android`；`.github/workflows/android.yml`（CI 尚未在 GitHub 上运行）。domain 2 测试通过；Debug/R8 Release/AAB 成功；模拟器冷启动成功。 |
| T04–T20 | NOT_STARTED | — |
| T21 | DEFERRED | 服务端验证，首发后（D-08 修订） |
| T22 | DEFERRED | Drive 同步，首发后（D-02 修订） |
| T23–T26 | NOT_STARTED | — |
| T27 | DEFERRED | Wear，首发后（D-05） |

## 执行状态

| 项 | 状态 |
|---|---|
| Android 工程 | 最小工程（app、core:domain、core:designsystem） |
| 自动化应用测试 | NOT_RUN（140 条；首发 126 条） |
| 真机 / 模拟器 | 模拟器仅做 T03 启动探针；真机 NOT_RUN |
| Play Console | 未操作 |

## 下一任务

可并行，任选其一：

- **T04 · 稳定版 Material3 与 DoneAt 设计 token 探针**（依赖 T03）。
- **T05 · 翻译转换与质量检查**（依赖 T02+T03）。
- **T06 · 导出共享规则差分 fixtures**（依赖 T01+T02，不需要 SDK）。T07 依赖它。

环境与命令见 `environment-lock.md`。候选默认（发布前冻结）：`applicationId=com.rainif.doneat`，minSdk 26，versionName 3.2.0，versionCode 1。

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
- 2026-09-23：T03 完成（最小工程、CI、环境锁）。
- 2026-09-23：交接包 1.2（D-02/D-08 修订、新增 D-12），T21/T22 延后；进度只在本文件维护；本机 SDK 就绪。
