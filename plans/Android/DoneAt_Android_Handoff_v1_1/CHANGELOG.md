# 1.2 变更记录 · 首发范围收敛版

日期：2026-09-23。前版：1.1。不改变固定 iOS 源提交。目录名仍为 `DoneAt_Android_Handoff_v1_1`，避免已有链接失效。

## 确认来源

负责人阅读评审意见后回复：“本机已经有Android SDK 了，其他的可以按照你的建议更新好”。

## 实际修改

- D-02 修订：首发以 Android Auto Backup/设备转移换机恢复，业务库纳入备份（与 iOS 主数据随 iCloud 设备备份一致），购买缓存/密钥/令牌排除；Drive 同步 T22 与 QA-110～QA-122 移到首发后阶段。
- D-08 修订：首发纯客户端 Play Billing（与 iOS 纯客户端 StoreKit 对齐）；服务端验证 T21 移到首发后阶段，届时优先放入现有 Vercel Route Handlers。CFG-OAUTH、CFG-BACKEND 标 DEFERRED。
- 新增 D-12：Release 只用稳定 Compose/Material3，Expressive 风格由 designsystem token 实现；T04、QA-003 相应改写。
- PRD 主导航从三个改为源码的四个（计时/专注/记录/设置），与 docs/android/conflicts.md C-09 一致。
- 新增 QA-138～QA-140（系统备份与换机恢复），改写 QA-067/098/099/101/105/106/109/135 为客户端验证与首发范围；测试共 140 条，首发 126 条。
- `tasks.json` 删除 `status`/`evidence`：进度只在 `docs/android/progress.md` 维护；T23 不再依赖 T21/T22。
- T08：Swift 特有规则 fixtures 作为 Swift 与 Kotlin 共用检查；02 §14 增加基线漂移检查；T03 记录本机 JDK/SDK 事实与可选 Swift SDK for Android 评估。
- 同步更新 00～07、decisions.json、tasks.json、test-catalog.json、MANIFEST.json。

## 没有执行的事项

未创建 Android 工程，未运行应用测试，未操作 Play Console/Google Cloud，未部署服务。

# 1.1 变更记录 · 产品方向确认版

日期：2026-09-21。前版：1.0。本版不改变固定 iOS 源提交。

## 确认来源

本对话负责人回复：“1-6 我觉得都 OK”。本版将上一轮六项建议固化，并明确它们对应 D-01/D-02/D-03/D-05/D-08/D-11，不将其他 D 项误批。

## 实际修改

- D-01：收费模式确认，地区价格和试用/优惠未填假值。
- D-02：Google Drive 同步确认且属于手机/平板首发；保持默认关闭和最终用户主动授权。
- D-03：首发 JSON 跨平台数据迁移、商店权益独立；不做跨 iOS/Android 自动同步。
- D-05：Wear OS 独立后续阶段，T27 标 DEFERRED，QA-137 仍 NOT_RUN 并标后续范围。
- D-08：购买验证服务方向确认；基础设施与部署仍待落实，不能上传工资和工作记录。
- D-11：账户核验流程确认；实际账户信息保持 UNKNOWN，未推断 Google 开发者身份。
- 同步更新 00～07 文档、任务卡、tasks.json、test-catalog.json、AI 启动/接续提示词、发布签收表；新增 decisions.json 配置台账。
- 保留 28 张任务卡、137 条验收规范、12 项独立样例与 52 个原始参考入口；不删除未执行事项。

## 没有完成或没有重新执行的事项

未修改 GitHub 仓库或生成 Android 工程；未构建应用或运行真实应用测试；未创建 Google 账户、商品或 OAuth 项目；未部署服务、操作 Play Console 或提交审核。1.1 未重新检出/全量审计源仓库，也未重新核验全部平台政策和库版本；原引用保留，执行与发布时仍须按官方资料复核。

方案确认与代码/测试/部署/发布状态分开记录。文档静态校验的实际结果见 PACKAGE_VALIDATION.md。
