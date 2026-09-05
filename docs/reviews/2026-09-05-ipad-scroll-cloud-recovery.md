# iPad 独立滚动与 CloudKit 缺失记录恢复

## 变更

记录页宽度达到现有双列阈值时，图示和总结各用一个有界 ScrollView；尺度切换与归档提醒留在顶部。窄屏保留单列滚动，沉浸画布不变。

用户报告 `unknownItem` / `recordChangeTag specified, but record not found`：保存请求持有云端已删除记录的系统字段。旧实现只显示错误，重试继续复用失效 change tag；删除成功的回执也没有清理本地系统字段。

现在删除确认后清理对应数据或删除标记的系统字段。对已有坏状态，先读取全局删除代次和该记录的删除标记，再清理匹配失败版本的字段并重新排队。保留本地 payload、编辑版本和删除/恢复意图；更高代次沿用现有 fence 清理逻辑；旧异步结果不能改动已更换的 engine 或覆盖较新回执。恢复期间暂不重发该行；网络错误保留本地数据并进入现有错误恢复流程。

这类错误需要应用处理，CKSyncEngine 不会替应用决定如何恢复业务记录，参见 [Apple CKSyncEngine](https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5)。

## 验收

`check:ios` 通过；完整模拟器回归最终 381 项通过。首次运行原有 `Replacing a focus-to-work handoff rejects the stale scheduled action` 出现一次 Task.yield 时序失败，未修改该测试，全量复跑通过。新增 3 项恢复测试两次均通过。

iPad 月视图标准字体与大字体已做视觉检查。CUA 模拟器拖动没有可靠产生位移，左右独立滚动的手势验收保留待真机复核，不以截图替代。日志：`/tmp/owc-ipad-cloud-tests.log`、`/tmp/owc-ipad-cloud-retest.log`。

- 自动化覆盖缺失行保留本地编辑、旧失败不覆盖新回执/跨 fence、缺失删除标记仍保留删除意图。
- iPad：拖动右列总结到底，左侧图示保持不动；再拖动左侧，右侧保持原位置。切换周/月/年/人生后重复。收窄窗口应回到单列。
- 真机云端：用原有报错数据重新运行候选构建，联网等同步；该记录不再重复使用失效标记。另一设备能收到正确结果。
- 专用测试数据：删后恢复、另一设备离线修改后重连、整库删除 fence、恢复过程中切换账户/关闭同步。不能用“清空所有数据后不报错”替代验收。

本地回归不等于真实 iCloud 数据已验证；本次不直接修改用户云端记录。
