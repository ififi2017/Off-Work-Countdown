# 合成备份档案

来源：`9252fdf` 的 `RecordSchemaCompatibilityTests.fullState` / `downgraded`，并补了一条 snapshot 与一条 calendar exception，使 12 类实体都有样本。

**不是**真实用户备份。金额与任务标题为匿名测试值。

| 文件 | 用途 |
|---|---|
| v1.json … v6.json | 合法降级/当前导出形状 |
| illegal-v0.json / illegal-v7.json | 版本拒绝 |
| illegal-not-json.txt | invalidDocument |
| illegal-invalid-date-v6.json | 非法民用日应拒行 |
| illegal-purchase-injected-v6.json | 含 purchaseToken/isPlus，不得授 Plus |
| manifest.json | 出处与四套版本声明 |

生成/校验：`node scripts/android-synthetic-archives.mjs` 与 `--check`。
