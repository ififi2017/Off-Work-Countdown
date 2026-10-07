# 2026-10-07 计时页空优惠工具栏项修复

用户真机最新 TestFlight 截图：未订阅、未触发终身优惠时，计时页左上角显示没有内容的圆形 Liquid Glass 按钮。

## 原因与变更

`TabletTimerRoot` 无条件创建 `.topBarLeading` 的 `ToolbarItem`。子视图 `LifetimeOfferToolbarButton` 在没有已领取的有效优惠时返回空内容，但工具栏项仍存在，系统保留了玻璃背景。

现在由父工具栏判断 `canOfferLifetime`、优惠存在且 `isActive(at: .now)`，满足时才创建整个工具栏项。无优惠、仅邀请未领取、已授权或已过期时不创建该项。优惠按钮沿用现有生命周期观察，并增加与优惠卡片相同的截止时间任务，到期后刷新 `PlusEntitlement`，让父工具栏移除整个项。取消任务不修改优惠，也不延长领取期限。

## 验证

- `npm run check:ios`：通过。
- `git diff --check`：通过。
- Xcode 27.1 headless iOS Simulator 构建及现有 `AppTests/LifetimeOfferTests`：实际运行 9 项，全部通过，非零测试数已核对。
- 使用检查前已经启动的唯一 iPhone 17（iOS 27.0）模拟器；关闭并行测试并限制同时仅一个模拟器测试目标，没有启动第二台，检查后仍为同一台。
- 测试覆盖邀请不启动时钟、领取后精确 24 小时过期、不重启期限、时钟回退不复活、有效价格、商店不可用与重启、已购买资格及本地化百分比。
- 本轮不改购买资格、价格、优惠触发方式、期限或订阅状态。

测试结果：`build/ios-offer-toolbar-fix/LifetimeOfferTests.xcresult`；日志：同目录 `test.log`。
尚未重打上传包、上传 TestFlight 或替换用户真机 App，修复后真机视觉复验待新构建。

## PR 基线复验

在最新 `main`（`ea593050`）的独立 checkout 上再次通过 `check:ios`、`check:ios-strings`、headless iOS Simulator 构建和上述 9 项优惠测试。结果保存于 `build/ios-offer-toolbar-pr/LifetimeOfferTests.xcresult`；关闭并行测试并复用同一台 iPhone 17。
