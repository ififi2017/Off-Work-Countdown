# ADR：Mobile P1 基线与商店决策期限

- 状态：通用购买与产品方向已定；最低系统和设备矩阵仍须在 P2 前定案
- 日期：2026-08-22
- 关联计划：[PLAN-MOBILE.md](PLAN-MOBILE.md)

## P1 临时基线

P1 先验证技术路线，不上传 build：

- 用 iOS 26 SDK / runtime 验证预约 Live Activity；
- 首个壳按 iPhone portrait 配置，模拟器之外至少验证一台 iOS 26 真机；
- P1 不承诺 iPad、横屏或 iOS 16.1–25；这些只记录差距，不在 spike 中扩张范围；
- iOS 作为现有 macOS 商店版的新增平台，使用同一 App Store Connect 记录与
  `com.rainif.offworkcountdown.macappstore` bundle id；
- Mobile 使用独立静态产物和根 `index.html`，不能复用已经选中 Desktop 分支的 `out/`；
- “独立产物”只表示复用同一套 TypeScript 业务规则和本地资源，绝不表示复用 Web 页面
  成品。iOS 必须有独立竖屏信息架构、触摸密度、导航和系统表面；
- Widget、Live Activity、通知和 App Group 投影全部不含薪资。

Capacitor 8.4.2 的 SwiftPM 生成器在 iOS 26 目标下会保留 `swift-tools-version: 5.9`，却写出
PackageDescription 6.2 才提供的 `.v26`。`npm run sync:mobile:ios` 因此在每次同步后把它
等价改写为 `.iOS("26.0")`；该字符串 API 从 PackageDescription 5.0 起可用。

这个基线只回答「iOS 26 主路径能不能成立」，不是最低系统或正式设备矩阵的最终结论。

## P1 当前证据

- Mobile 根入口、19 locale、离线资源和 Web/Desktop 私有代码裁剪检查已通过；
- 直接渲染 Web 页面虽然能完成主流程，但其留白、页头、卡片层级与导航不符合 iPhone
  产品标准，已被明确否决，不能作为 go 依据；
- 第一版 Mobile 专用 Timer/Settings 竖屏 UI 已完成 390×844 浅色、深色、英文与简中
  交互/截图检查；未来班次、下一班和加班入口沿用 macOS 商店版语义；
- iOS shell 使用原生 `UITabBar` 与 Web 状态同步；浏览器里的玻璃底栏只是视觉回归 fallback，
  打包后由 iOS 26 系统控件提供 Liquid Glass；
- Capacitor iOS 工程已生成，SwiftPM 依赖锁定到 8.4.2；
- 完整 Simulator scheme 已构建通过，并在 iOS 26.5 / iPhone 17 Pro Simulator 安装真实 `.app`；
  已验证 Dynamic Island、Home Indicator 安全区、原生 Liquid Glass 底栏、标签本地化以及
  浅色/深色主题同步；
- 当前开发机没有连接 iPhone，因此软键盘、前后台、系统终止、手动强退与预约 Live Activity
  仍没有真机证据，不能据此锁最低 iOS 或进入 P2。

## P2 前必须锁定

### 1. 通用购买与 bundle id（已锁定）

现有 Mac App Store 版 bundle id 是
`com.rainif.offworkcountdown.macappstore`，定价为 US$0.99 / ¥8。Apple 的通用购买要求
iOS 与 macOS 使用同一 App Store Connect 记录和同一 bundle id；分开的既有记录不能直接
合并。项目所有者已确认采用**通用购买**：iOS 沿用现有记录、bundle id、付费商品关系与
品牌，不是独立销售的 Web 包装版。iOS target 已改用
`com.rainif.offworkcountdown.macappstore`；创建平台与首次上传前仍需核对 capability、签名和
现有 App Store Connect 记录，不能另建同名 App 记录。

### 2. 最低 iOS

P1 在真机记录预约 Live Activity 的创建、后台到点、系统终止、手动强退、取消和重排结果。
若主路径成立，再比较旧系统覆盖价值与双路径维护成本，选择：

- iOS 26+：只维护预约 Live Activity 主路径及本地通知降级；或
- iOS 16.1+：额外维护旧系统「本地通知 → 用户打开后启动短 Live Activity」路径。

### 3. 正式设备矩阵

P1 暂按 iPhone portrait。P2 前必须明确是否把 iPad、横屏和 iPad 多任务列为正式支持；
只要列入支持，就必须进入布局、截图、无障碍和 TestFlight 验收矩阵，不能依赖兼容模式。

## 已锁定的隐私边界

完整班次、薪资与偏好只进入主应用私有存储。App Group 只接受 salary-free
WidgetSnapshot 投影；通知和 Live Activity payload 同样不含工资、时薪、累计收入或可反推
这些数值的字段。这个决定不随最低系统、设备矩阵或销售方式变化。

## P1 退出条件

- P1a Mobile 静态产物、19 locale 与根入口检查通过；
- P1b 模拟器和至少一台 iOS 26 真机记录完成；
- 项目所有者确认最终最低系统和正式设备矩阵（通用购买已锁定）；
- 结论回写 `PLAN-MOBILE.md` 后才能进入 P2。
