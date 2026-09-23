# ADR：DoneAt 设计 token 与稳定版 Material3（T04）

状态：已采纳（2026-09-23）。关联决策：D-12。

## 背景

D-12 规定 Release 只用稳定版 Compose/Material3；Material 3 Expressive 的组件与 `MotionScheme` 仍在 alpha，不能进入生产包。计划 01 §7 同时要求 Expressive 风格用在"当前状态、主要操作和必要的状态过渡"，并且与仓库"克制、平台原生"的 UI 原则一致。

## 决定

`:core:designsystem` 用 DoneAt 自有 token 实现 Expressive 的效果，只调用稳定 API：

| token | 内容 | 与 iOS 的对应 |
|---|---|---|
| `DoneAtColors.light/dark` | 完整 M3 颜色角色；暖中性表面，橙色只标当前状态与主操作 | 品牌橙 `OWCDesign.orange`；深色主色取 iOS 深色强调色 `#FF872E` 的色相 |
| `DoneAtColors.brand` | `#F97316`，仅用于装饰 | 浅色表面上对比度 2.67，不能作文字或数据 |
| `DoneAtStateColors` | 工作 / 休息 / 下班 / 加班四种状态色 | 总与文字标签同时出现，不单靠颜色区分 |
| `DoneAtShapes` | 4 / 8 / 14 / 22 / 28 dp；主操作高 56 dp，按下时圆角降到 12 dp | 14、22 即 `OWCDesign.controlRadius`、`cardRadius` |
| `DoneAtMotion` | press 140、selection 180、stateExit 100、stateEnter 180、phase 280 ms；强调减速曲线 cubic-bezier(0.23, 1, 0.32, 1)；空间变化用带少许回弹的 spring | 数值与 `OWCMotion` 一致 |
| `DoneAtType.countdown` | 64 sp、等宽数字（`tnum`）、随系统字号缩放 | 计划 01 §7.2 的 56–72 sp 测试区间 |
| `DoneAtSpacing` | 4 dp 网格，页边距 16 dp，触达区 ≥ 48 dp | `OWCDesign.pageInset` 16 |

由 token 实现的 Expressive 行为：

- **形状变化**：`DoneAtPrimaryButton` 静止时为胶囊（圆角取实测高度的一半，大字体下仍是胶囊），按下时收成 12 dp 圆角方形，用 spring 过渡。
- **动效分工**：形状与位置用带回弹的 spring；颜色与透明度只用 tween，不回弹。阶段标记切换颜色用 `phase`（280 ms）。
- **减少动态效果**：系统"移除动画"（动画缩放为 0）时，所有 spec 退化为 snap 或 160 ms 淡变；gallery 可单独切换以便检查。
- **强调层级**：每屏只有一个 filled 主操作；结束类操作用 error 色描边按钮，与开始操作明确区分。
- **主题**：品牌配色为默认；动态配色为可选开关，仅 Android 12+ 显示；浅色、深色、跟随系统与配色来源相互独立。`SystemBarsFollowTheme`（`:app`）让系统栏图标跟随应用主题而非系统主题。

没有采用的：`MaterialExpressiveTheme`、`MotionScheme`、`ButtonGroup`、`LoadingIndicator`、`FloatingToolbar`、形状库 `MaterialShapes` 等 Expressive API。

## 可访问性

- `DoneAtColorsTest` 检查两套配色中每一对"文字/底色"都 ≥ 4.5:1（含四种状态色），描边 ≥ 3:1。
- 倒计时对 TalkBack 用一句完整描述替代数字，不会每秒重读。
- 阶段标记、分段选择都有文字，不靠颜色传达状态。

## 验证（Pixel 10 Pro 模拟器，API 36）

Debug 专用 gallery：`adb shell am start -n com.rainif.doneat/.gallery.DesignGalleryActivity [--es theme light|dark]`。Release 包不含该页面。

| 探针 | 结果 |
|---|---|
| 浅色 / 深色 | 主计时线框、状态标记、按钮、分段选择、色板正常；深色强制时状态栏图标改为浅色（修复前看不见） |
| 按下主按钮 | 胶囊收成 12 dp 圆角，旁边按钮不受影响 |
| 200% 字体 | 文字换行、状态标记改为多行排列、按钮随内容增高且仍为胶囊（修复前变成固定 28 dp 圆角）；倒计时由系统非线性缩放保持一行 |
| 系统移除动画 | `DoneAtMotion.reduced` 读到开启 |
| 长德文按钮 | 正常换行 |

检查中调整：浅色 `secondaryContainer` 原与 `primaryContainer` 几乎同色，改为暖灰 `#F5DED4`。

动态配色仅在代码中接入，本次未在壁纸取色的设备上检查；阿拉伯语 RTL 与 TalkBack 的实际朗读随 T15 的真实页面检查。

## 依赖树（releaseRuntimeClasspath）

Compose BOM 2026.09.00：`androidx.compose.material3:material3:1.4.0`，`compose-ui`/`foundation`/`animation`/`runtime` 1.12.1，均为稳定版。Android CI 在 Release 依赖出现 `-alpha`/`-beta`/`-rc` 的 Compose 或 Material3 时失败。

## 何时切换到官方 Expressive API

同时满足以下条件时重新评估：

1. `MaterialExpressiveTheme`、`MotionScheme` 与所需组件进入稳定版 Material3，并包含在我们采用的稳定 BOM 中；
2. 切换后 Release 依赖检查仍全部为稳定版；
3. 在 gallery 中对比，官方实现不降低上面的对比度、减少动态效果与大字体表现。

切换时保留 token 名称，把实现改为引用官方 scheme，页面代码不需要改动。
