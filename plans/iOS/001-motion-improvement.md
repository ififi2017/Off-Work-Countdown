# 001 — 统一并收敛全产品动效

- **Status**: IN PROGRESS — iOS 动效地基随 007 合入；Web/Desktop 尚未开始
- **Commit**: 基线 `f10c7f9`；进度复核 `755052f`（PR #82）
- **Severity**: HIGH
- **Category**: Purpose & frequency / Easing & duration / Performance / Accessibility / Cohesion
- **Estimated scope**: iOS 7–9 files；Web/Desktop 10–13 files；不涉及业务规则

## 当前进度（2026-08-28）

- iOS 已落地 `OWCMotion`、`TimerVisualPhase`、三种尺寸壳的阶段/导航过渡、Reduce Motion
  分支、主按钮按压反馈和按班次去重的完成庆祝；这些改动随 007 的 PR #82 合入 `main`。
- 原计划 A1/P1 要求彻底移除逐秒数字滚动，但当前实现改为共享
  `OWCCountdownTextTransition`，让竖屏、横屏、iPad、午休和休息态使用同一套、且会尊重
  Reduce Motion 的数字过渡。这里已经是一次明确的产品取舍变化，继续执行 001 前应先决定
  保留统一滚动还是改回“每秒直接更新”，不能把旧步骤机械地标成完成。
- Web/Desktop 工作流尚未执行；`transition-all`、高频进度属性和完整 Reduced Motion 矩阵仍需
  按 B 工作流处理。
- PR #82 已通过 iOS 模拟器构建、Web/Desktop 构建、lint 和单测；001 专属的 Reduce Motion
  真机矩阵、浏览器 10 分钟性能检查与 Windows Mini Timer feel check 尚未完成。

## 目标

在不改变界面结构、信息密度、导航方式和业务计算的前提下，让原生 iOS 与
Web/Desktop 各自形成一致、可中断、低成本并尊重“减少动态效果”的动效体系。

计划分成两个可以独立交付的工作流：

| 阶段 | iOS | Web + Desktop |
| --- | --- | --- |
| P0 基线 | 建立 `OWCMotion` 原生 token | 建立 TypeScript/CSS motion token，并设置全局 Reduced Motion 策略 |
| P1 高频界面 | 停止逐秒滚动倒计时数字 | 把逐秒进度从 `width`/`left` 改为 `transform` |
| P2 页面过渡 | 统一开始、停止、主导航和计时阶段的时长 | 修正 `easeIn`、双重位移和一秒主题过渡 |
| P3 无障碍 | 勾号、纸屑和阶段切换适配 Reduce Motion | Framer Motion、纸屑、滚动和 hover 全面适配 Reduce Motion |
| P4 收尾 | 每个班次只自动庆祝一次；统一按钮反馈 | 移除 `transition-all`；统一按钮反馈；可选优化 macOS 菜单栏面板 |

两个工作流之间没有代码依赖，可以分开提交和真机验收。共同完成标准是：

- 任何每秒发生的更新都不能持续触发布局动画。
- 进入、退出和普通状态切换不超过 300ms；恒定进度可以使用 900–1000ms `linear`。
- 开启系统“减少动态效果”后，保留颜色和透明度反馈，移除位移、缩放、纸屑和
  平滑滚动。
- 快速反复触发状态时，动画必须从当前状态重新定向，不能从第一帧重新播放。
- 不改变 iPhone、iPad、Web 或 Desktop 的现有布局尺寸和内容顺序。

---

# 工作流 A — iOS

## A1. 问题

### A1.1 逐秒数字滚动是最高频运动，并且不响应 Reduce Motion

`src-mobile/ios/App/App/Native/Views/TimerDesignView.swift:456` 当前代码：

```swift
Text(store.formatDuration(displayRemaining))
    .font(.system(size: 56, weight: .bold).monospacedDigit())
    .contentTransition(.numericText(countsDown: true))

// ...

.animation(.linear(duration: 0.16), value: Int(displayRemaining / 1_000))
```

这使 iPhone 竖屏倒计时每秒滚动，而横屏、iPad、午休和加班页面虽然声明了
`contentTransition(.numericText)`，却没有每秒动画事务。同一个倒计时因此出现两套行为。

### A1.2 相同开始/停止行为使用不同节奏

当前代表性代码：

```swift
// TimerDesignView.swift:332
withAnimation(.snappy(duration: 0.32)) {
    store.startCountdown(force: isNonWorkday)
}

// PhoneLandscapeView.swift:199
withAnimation(.smooth(duration: 0.42)) {
    store.startCountdown(force: nonWorkday)
}

// TabletDesignView.swift:588
withAnimation(.smooth(duration: 0.42)) {
    store.startCountdown(force: nonWorkday)
}
```

竖屏约 300ms，横屏和 iPad 为 420ms；部分按钮动作和外层容器又同时声明动画，
导致动画所有权不清晰。

### A1.3 计时阶段自然变化会瞬间替换

`TimerDesignView.swift:67`、`TabletDesignView.swift:243` 和
`PhoneLandscapeView.swift:219` 都根据运行、午休、加班、完成等条件直接切换分支。
外围动画主要观察 `store.countdownStarted`，因此午休开始/结束、进入加班和自然下班
不会触发页面过渡。

### A1.4 完成页每次出现都会自动庆祝

`src-mobile/ios/App/App/Native/Views/TimerStatusViews.swift:388` 当前代码：

```swift
.overlay { OWCConfettiOverlay(burst: celebrationBurst) }
.onAppear { celebrate() }
.onDisappear { celebrationHaptics?.cancel() }
```

尺寸级别变化、视图重建或重新进入完成页都可能重放五秒纸屑和整套触觉反馈。

### A1.5 通知模式勾号从零缩放

`src-mobile/ios/App/App/Native/Views/SettingsDetailDesignViews.swift:558` 当前代码：

```swift
withAnimation(.snappy(duration: 0.22)) {
    store.notificationMode = mode
}

// ...

.transition(.scale.combined(with: .opacity))
```

SwiftUI 默认 `.scale` transition 从 0 开始，不符合本项目克制的系统工具风格，且没有
Reduce Motion 分支。

## A2. 目标状态

新增 `src-mobile/ios/App/App/Native/DesignSystem/OWCMotion.swift`，只放原生表现 token：

```swift
import SwiftUI

enum OWCMotion {
    static let reduced = Animation.easeOut(duration: 0.16)
    static let press = Animation.easeOut(duration: 0.14)
    static let selection = Animation.snappy(duration: 0.18)
    static let navigation = Animation.snappy(duration: 0.28)
    static let phase = Animation.smooth(duration: 0.28)
}
```

目标规则：

- 倒计时秒数直接更新，不使用 `.numericText` 的逐秒滚动。
- 只有 `setup / running / lunch / overtime / completed / rest / error` 视觉阶段变化才动画。
- 阶段正常模式使用 `.opacity.combined(with: .scale(scale: 0.98))` 和
  `OWCMotion.phase`；Reduce Motion 使用 `.opacity` 和 `OWCMotion.reduced`。
- 主导航和开始/停止统一为 280ms，由页面容器控制；按钮 action 不再重复包
  `withAnimation`。
- 通知勾号正常模式从 `scale: 0.95` 开始，Reduce Motion 只使用 `.opacity`。
- 自动纸屑每个 `plannedEndAtMs` 只播放一次；标题按钮仍允许手动重播。

## A3. 项目约定

- 使用 SwiftUI 原生 `Animation` 和 `AnyTransition`，不引入第三方动画库。
- 所有排班、午休、加班、薪资和提醒判断仍来自 `CountdownRules.js` 返回的 snapshot。
- 视觉阶段可以根据 snapshot 已有字段分类，但不能重新实现排班规则。
- 继续使用现有 `@Environment(\.accessibilityReduceMotion)` 模式：
  `RootView.swift:18`、`PhoneLandscapeView.swift:6` 和 `TabletDesignView.swift:9`
  是现有范例。
- 继续由 UIKit 的 `OWCSystemBackSwipeBridge` 管理交互式返回；不能添加 SwiftUI
  `DragGesture` 模拟返回。

## A4. 实施步骤

1. 新增 `Native/DesignSystem/OWCMotion.swift`，写入 A2 中的五个 token。
2. 新增 `Native/Views/TimerVisualPhase.swift`：
   - 定义 `enum TimerVisualPhase: Hashable`，成员固定为
     `setup, running, lunch, overtime, completed, rest, rulesError`。
   - 提供只读取 `countdownStarted` 和 `NativeShiftSnapshot` 已有字段的分类函数。
   - 不调用或复制任何 TypeScript 排班算法。
3. 从以下高频倒计时数字移除 `.contentTransition(.numericText(...))`：
   - `Native/Views/TimerDesignView.swift`
   - `Native/Views/TimerStatusViews.swift`
   - `Native/Views/PhoneLandscapeView.swift`
   - `Native/Views/TabletDesignView.swift`
4. 删除 `TimerDesignView.swift:470` 绑定秒数的 `.animation(.linear(duration: 0.16), ...)`。
5. 在 `TimerDesignView` 的阶段内容边界使用 `TimerVisualPhase`：
   - 阶段内容加 `.id(phase)`。
   - 正常模式使用 `.opacity.combined(with: .scale(scale: 0.98))`。
   - Reduce Motion 使用 `.opacity`。
   - 容器只用 `.animation(..., value: phase)` 控制阶段变化。
6. 对 `LandscapeTimerView` 和 `TabletTimerView` 应用相同阶段边界；不要改变它们的
   `frame`、padding、侧栏宽度、ZStack 层级或 sheet 配置。
7. 把 iPad 和横屏的计时/设置切换统一为 `OWCMotion.navigation`：
   - 容器保留一个 `.animation(value: store.selectedTab)`。
   - tab/rail 按钮只赋值 `store.selectedTab`，不再重复 `withAnimation`。
   - Reduce Motion 时容器使用 `OWCMotion.reduced` 和纯透明度。
8. 从开始/停止 action 中删除仅用于页面切换的 `withAnimation(.snappy/.smooth)`；由
   步骤 5–7 的容器接管。非工作日二次确认的局部状态继续使用
   `OWCMotion.selection`。
9. 在通知模式页面读取 `accessibilityReduceMotion`：
   - 普通模式：`.opacity.combined(with: .scale(scale: 0.95))`。
   - Reduce Motion：`.opacity`。
   - 动画分别使用 `OWCMotion.selection` 和 `OWCMotion.reduced`。
10. 在 `CompletedShiftDesignView` 增加：

```swift
@AppStorage("ios.native.lastCelebratedShiftEndAtMs")
private var lastCelebratedShiftEndAtMs = 0.0
```

   自动播放入口改为比较 `snapshot.plannedEndAtMs`：相同则不自动重播；不同则先写入
   新值再调用 `celebrate()`。标题按钮直接调用 `celebrate()`，不修改这个判断。
11. 给 `OWCPrimaryButtonStyle` 补齐与次按钮一致的按压过渡：正常模式使用
   `OWCMotion.press`；Reduce Motion 保留 opacity，取消 scale。不要改变按钮尺寸、
   圆角或颜色。

## A5. 明确边界

- **不要修改** `CountdownRules.js`、`lib/countdown.ts`、`lib/reminders.ts` 或
  `lib/summary.ts`。
- **不要修改** `OWCProgressMeter` 的 `.transaction { $0.animation = nil }`。它用于阻止
  首帧零尺寸布局继承外层动画，是之前进度条从 0 爬入和卡住问题的保护。
- 不给每秒进度、每秒倒计时、薪资或 Live Activity 数字添加动画。
- 不改变 `OWCSystemBackSwipeBridge`、导航栏隐藏策略或安全区布局。
- 不改变 iPad 侧栏宽度、iPhone 横屏 rail、分享页 detent 或任何页面 frame。
- 不修改 WidgetKit timeline；Widget 和 Live Activity 不属于本轮 App 内动效范围。

## A6. 验证

### 机械检查

```bash
npm run build:ios-native-rules
npm run check:ios
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

预期：三条命令全部成功；没有新增 Swift 并发警告或 Xcode 导航警告。

### 真机感受检查

由用户在 Xcode 编译到真机后检查：

1. iPhone 竖屏、横屏和 iPad 分别开始/停止倒计时，三者收束时间一致。
2. 快速来回切换计时与设置，页面能从当前状态反向，不出现闪动或第二次归位。
3. 等待进入午休、加班和自然下班，阶段之间有一次 280ms 内的轻微过渡。
4. 倒计时秒数直接稳定更新，不持续滚动；进度条仍每秒正确更新且不从 0 爬入。
5. 设置 → 辅助功能 → 动态效果 → 减弱动态效果开启后：
   - 页面只淡入淡出；没有位移和缩放。
   - 通知模式勾号不弹出。
   - 下班完成不显示纸屑。
6. 在完成页旋转设备、收起/展开 iPad 侧栏、进入其他页面后返回，自动庆祝不重播；
   点击“今日已下班”标题仍能手动重播。
7. 设置二级页面的系统侧滑返回仍保持原有触发范围和交互进度。

### 完成条件

- 所有设备上的同一动作使用相同节奏。
- 逐秒刷新没有运动噪声。
- Reduce Motion 矩阵全部通过。
- 真机确认没有布局位移、顶部闪动、手势冲突或进度回退。

---

# 工作流 B — Web + Desktop

## B1. 问题

### B1.1 Framer Motion 和纸屑没有统一 Reduced Motion 策略

`components/off-work-countdown.tsx:1405` 当前页面 variants 包含位移；
`components/CountdownDisplay.tsx:33` 又执行第二层位移：

```tsx
<motion.div
  initial={{ opacity: 0, y: 20 }}
  animate={{ opacity: 1, y: 0 }}
  exit={{ opacity: 0, y: -20 }}
  transition={{ duration: 0.3 }}
>
```

`components/Confetti.tsx:22` 当前创建方式：

```ts
confetti.create(undefined, { resize: true, useWorker: false });
```

两者都没有覆盖系统 `prefers-reduced-motion`。

### B1.2 自定义主题背景永久重绘

`app/globals.css:83` 当前代码：

```css
@keyframes gradientAnimation {
  0% { background-position: 0% 50%; }
  50% { background-position: 100% 50%; }
  100% { background-position: 0% 50%; }
}

.bg-gradient-animate {
  background-size: 400% 400%;
  animation: gradientAnimation 15s ease infinite;
}
```

该元素覆盖整个窗口，全天进行装饰性 `background-position` 绘制。

### B1.3 逐秒进度修改布局属性

`components/ProgressBar.tsx:76` 当前 fill 和 bubble 使用 `width`、`left`，而
`transition` 没有对应的 `animate` 属性：

```tsx
<motion.div
  style={{ width: `${boundedProgress}%` }}
  transition={{ type: "spring", stiffness: 300, damping: 30 }}
/>

<motion.div
  style={{ left: `${boundedProgress}%`, x: "-50%" }}
  transition={{ type: "spring", stiffness: 300, damping: 30 }}
/>
```

`components/MiniCountdown.tsx:661` 当前代码：

```tsx
className="h-full rounded-full bg-orange-500 transition-[width] duration-500 ease-out"
style={{ width: `${showsCountdown ? progress : 0}%` }}
```

### B1.4 主流程使用 `easeIn` 并叠加两层位移

`components/off-work-countdown.tsx:1419` 当前代码：

```ts
exit: {
  opacity: 0,
  y: -10,
  transition: { duration: FLOW_EXIT_SECONDS, ease: "easeIn" as const },
}
```

外层页面与 `CountdownDisplay` 同时位移，进场总收束超过 300ms。

### B1.5 主题、薪资展开和快捷滚动过慢或不适配 Reduced Motion

当前代码：

```tsx
// off-work-countdown.tsx:2405
className="transition-colors duration-1000 ease-in-out"

// off-work-countdown.tsx:298
initial={{ height: 0, opacity: 0 }}
animate={{ height: "auto", opacity: 1 }}
exit={{ height: 0, opacity: 0 }}

// off-work-countdown.tsx:1870
container.scrollTo({ top: targetTop, behavior: "smooth" });
```

### B1.6 `transition-all` 和按压反馈不统一

`off-work-countdown.tsx:3010`、`:3904`、`:3918` 与
`MiniCountdown.tsx:430` 使用 `transition-all`。通用 `Button` 只有 hover 颜色，木鱼却
使用 `active:scale-[0.92]`，反馈强度不一致。

## B2. 目标状态

新增 `lib/motion.ts`：

```ts
export const motionEase = {
  out: [0.23, 1, 0.32, 1] as const,
  inOut: [0.77, 0, 0.175, 1] as const,
  drawer: [0.32, 0.72, 0, 1] as const,
};

export const motionDuration = {
  press: 0.14,
  small: 0.18,
  page: 0.22,
} as const;
```

在 `app/globals.css` 的 `:root` 增加 CSS 对应 token：

```css
--motion-ease-out: cubic-bezier(0.23, 1, 0.32, 1);
--motion-ease-in-out: cubic-bezier(0.77, 0, 0.175, 1);
--motion-ease-drawer: cubic-bezier(0.32, 0.72, 0, 1);
--motion-duration-press: 140ms;
--motion-duration-small: 180ms;
--motion-duration-page: 220ms;
```

目标规则：

- 所有 Framer Motion 子树由 `MotionConfig reducedMotion="user"` 统一适配系统设置。
- 纸屑设置 `disableForReducedMotion: true`。
- 自定义主题渐变保持静态；主题切换只做 220ms 透明度/颜色过渡。
- 进度 fill 使用完整 `transform: scaleX(...)`；连续进度使用 900ms `linear`。
- 主流程退场 120ms、进场 180ms，进场延迟 120ms，总时长 300ms。
- 所有触发频繁的按钮只过渡明确属性；按压反馈为 `scale(0.97)`、140ms ease-out。
- Reduced Motion 下 smooth scroll 改为 `auto`，hover/press 不产生 scale。

## B3. 项目约定

- 继续使用现有 Framer Motion、Tailwind 和 CSS，不增加依赖。
- `components/off-work-countdown.tsx:2645` 的 Desktop 设置轨道已经使用
  `motion-safe:`，是 Reduced Motion 的现有范例。
- 木鱼主线程纸屑/动画是 CSP 下的明确取舍；只改 Reduced Motion，不启用 Worker。
- Windows WebView Mini Timer 与 macOS AppKit Mini Timer 是独立实现，不合并生命周期。
- 不改变 Desktop 420–450px 窗口范围、固定 footer 或设置页结构。

## B4. 实施步骤

1. 新增 `lib/motion.ts` 和 B2 中的 TypeScript token；在 `app/globals.css` 增加对应
   CSS token。把当前重复的 drawer 曲线引用替换为这些 token 能覆盖的形式。
2. 在 `components/I18nProvider.tsx` 中引入 Framer Motion 的 `MotionConfig`，使用：

```tsx
<MotionConfig reducedMotion="user">
  <I18nextProvider i18n={instance}>{children}</I18nextProvider>
</MotionConfig>
```

   这样 Web、Desktop 主窗口和 Mini 页面都使用同一个系统偏好。
3. 在 `components/Confetti.tsx` 创建 cannon 时加入：

```ts
confetti.create(undefined, {
  resize: true,
  useWorker: false,
  disableForReducedMotion: true,
});
```

4. 删除 `gradientAnimation` keyframes 和 `.bg-gradient-animate` 上的永久 animation；
   保留现有渐变颜色，背景变为静态。
5. 在 `Background.tsx` 把主题交叉淡化改为 220ms、`motionEase.out`；开启 Reduced
   Motion 时由 `MotionConfig` 保留 opacity 并移除 transform 类动效。
6. 把根容器 `duration-1000 ease-in-out` 改为
   `duration-[220ms] ease-[var(--motion-ease-out)] motion-reduce:duration-0`。
7. 重写 `components/ProgressBar.tsx` 的 fill：

```tsx
<motion.div
  initial={false}
  animate={{ transform: `scaleX(${boundedProgress / 100})` }}
  style={{ transformOrigin: "left center" }}
  transition={{ duration: 0.9, ease: "linear" }}
/>
```

   使用 `useReducedMotion()` 时把 duration 设为 0。
8. `ProgressBar` 用 `ResizeObserver` 保存轨道实际宽度；bubble 的位置用一个完整
   transform 字符串移动：

```tsx
transform: `translateX(calc(${targetX}px - 50%))`
```

   `targetX = trackWidth * boundedProgress / 100`。保留现有 `bubbleShiftPx` 边缘夹取，
   但不要再动画 `left` 或 Framer 的 `x` shorthand。
9. 把 `MiniCountdown.tsx` 和 `components/mobile/ios-kit.tsx` 的进度 fill 改为满宽元素：

```tsx
className="h-full origin-left rounded-full bg-orange-500 motion-safe:transition-transform motion-safe:duration-1000 motion-safe:ease-linear"
style={{ transform: `scaleX(${progress / 100})` }}
```

   RTL 不反转进度方向，保持当前从左到右的时间进度语义。
10. 主流程 variants 使用：
    - 退场：120ms，`motionEase.out`，`y: -8`。
    - 进场：180ms，`motionEase.out`，`y: 8 → 0`，delay 120ms。
    - 删除所有 `easeIn`。
11. 把 `CountdownDisplay.tsx` 根元素从 `motion.div` 改为普通 `div`，删除其
    `initial/animate/exit/transition`，让外层 flow page 成为唯一动画所有者。
12. 薪资设置展开不再动画 `height`：布局立即展开/收起，只对内容做 180ms 的
    `opacity` 与 `translateY(-4px → 0)`；由 `MotionConfig` 在 Reduced Motion 下移除
    translate。快速开关时确认 AnimatePresence 能从当前 opacity 反向。
13. 快捷设置滚动前读取：

```ts
const reduceMotion = window.matchMedia(
  "(prefers-reduced-motion: reduce)"
).matches;
```

    `scrollTo` 的 behavior 使用 `reduceMotion ? "auto" : "smooth"`。
14. 替换所有已确认的 `transition-all`：
    - Desktop 快捷设置：仅 `color, background-color, border-color, box-shadow`。
    - 移动 Web tab：仅 `color, background-color, box-shadow`。
    - Mini 声音按钮：仅 `transform, color, background-color, opacity`。
15. 通用 `Button` 增加 `active:scale-[0.97]`、140ms ease-out，并加
    `motion-reduce:transform-none`。木鱼从 `scale(0.92)` 收敛到 `scale(0.97)`；
    Reduced Motion 下保留辉光/颜色反馈而不缩放。
16. 分享心情 hover 缩放只在 `(hover: hover) and (pointer: fine)` 下启用；Reduced
    Motion 时取消 transform，保留 ring 和背景反馈。
17. 可选的第二轮 Desktop polish：在真实 macOS 上评估菜单栏面板关闭时增加不超过
    120ms 的 ease-out opacity。由于该入口可能每天使用数十次，默认不增加位移或弹性；
    若真机感受没有明显收益，则保持现状并将此项标记为 WON'T DO。

## B5. 明确边界

- 不改变 React markup 的信息顺序、Desktop footer、窗口尺寸或滚动容器边界。
- 不修改排班、提醒、薪资或分享 URL 规则。
- 不把 Windows Mini Timer 和 macOS Native Mini Timer 合并。
- 不修改 macOS AppKit 原生进度条的即时更新策略。
- 不重新启用 canvas-confetti Worker，不扩大 CSP。
- 不为移动 Web 预览重新引入 Capacitor；`src-mobile/ios` 仍是唯一 iOS App。
- 不添加新的 npm、Rust 或 Swift 依赖。

## B6. 验证

### 机械检查

```bash
npm run lint
npm test
npm run build
npm run check:build:web
npm run build:desktop
npm run check:build:desktop
```

如果执行了步骤 17，还必须运行：

```bash
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri:build
```

预期：所有命令成功；Web build 继续保留 middleware/Route Handlers；Desktop export
继续生成有效 `out/`。

### 浏览器与 Desktop 感受检查

1. Chrome DevTools → Animations 设置为 10%：
   - 开始/返回只有一层页面位移。
   - 退场第一帧立即响应，没有 `ease-in` 的迟缓。
   - 页面总过渡不超过 300ms。
2. DevTools 模拟 `prefers-reduced-motion: reduce`：
   - Framer 页面只淡入淡出。
   - 下班完成没有纸屑。
   - 快捷设置立即滚到目标。
   - 心情 emoji、木鱼和标准按钮不缩放，但颜色/ring 反馈仍在。
3. 连续运行倒计时至少 10 分钟，Performance 面板确认进度更新不触发持续 Layout；
   fill 和 bubble 始终同步，0%、100% 不越界。
4. 快速反复切换开始/返回和薪资开关，动画从当前状态反向，没有重新从 0 开始。
5. 连续切换浅色、深色、自定义主题，前景和背景在 220ms 内同步完成，没有一秒拖尾。
6. Windows Mini Timer 运行状态下观察进度至少两分钟：进度连续线性移动，窗口拖动、
   置顶、皮肤切换和声音按钮不受影响。
7. macOS Native Mini Timer 保持现有布局、菜单栏定位和即时数字刷新。

### 完成条件

- Reduced Motion 覆盖 Framer、CSS、canvas-confetti、滚动和按压反馈。
- 高频进度不再动画 `width` 或 `left`。
- 主流程不存在 `easeIn`、双重 transform 或超过 300ms 的普通页面切换。
- Web 与 Desktop 共享同一套 motion token，平台专属窗口实现仍保持独立。

---

# 推荐执行顺序

1. iOS A1–A4：token、逐秒数字和视觉阶段基础。
2. Web/Desktop B1–B3：token、MotionConfig、Reduced Motion。
3. Web/Desktop B4–B9：永久背景与高频进度性能。
4. iOS A5–A9：阶段、导航和勾号过渡。
5. Web/Desktop B10–B16：页面切换、主题、展开和按钮反馈。
6. iOS A10–A11：庆祝去重与按钮收尾。
7. 两端分别完成真机/真实 Desktop feel check。
8. 只有在真实 macOS 体验明确变好时执行 B17。

两条工作流建议分别提交，避免一次 PR 同时混入 SwiftUI、React、CSS 和 AppKit，降低
回归定位难度。
