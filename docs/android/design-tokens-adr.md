# ADR：DoneAt 设计 token 与稳定版 Material3（T04）

状态：已采纳（2026-09-23）。关联决策：D-12。

## 背景

D-12 规定 Release 只用稳定版 Compose/Material3；Material 3 Expressive 的组件与 `MotionScheme` 仍在 alpha，不能进入生产包。计划 01 §7 同时要求 Expressive 风格用在"当前状态、主要操作和必要的状态过渡"，并且与仓库"克制、平台原生"的 UI 原则一致。

## 决定

`:core:designsystem` 用 DoneAt 自有 token 实现 Expressive 的效果，只调用稳定 API：

| token | 内容 | 与 iOS 的对应 |
|---|---|---|
| `DoneAtColors.light/dark` | 完整 M3 颜色角色；页面/卡片对齐 iOS 的中性分组背景，强调色标当前状态与主操作 | 默认主色精确对应 `OWCDesign.accent`：浅色 `#F2590A`，深色 `#FF872E` |
| `DoneAtColors.brand` | `#F97316`，仅用于装饰 | 浅色表面上低于 4.5:1，不能作文字或数据 |
| `DoneAtStateColors` | 工作 / 休息 / 下班 / 加班四种状态色 | 总与文字标签同时出现，不单靠颜色区分 |
| `DoneAtShapes` | 4 / 8 / 14 / 22 / 28 dp；主操作高 56 dp，按下时圆角降到 12 dp | 14、22 即 `OWCDesign.controlRadius`、`cardRadius` |
| `DoneAtMotion` | press 140、selection 180、stateExit 100、stateEnter 180、phase 280 ms；强调减速曲线 cubic-bezier(0.23, 1, 0.32, 1)；空间变化用带少许回弹的 spring | 数值与 `OWCMotion` 一致 |
| `DoneAtType.countdown` | 64 sp、等宽数字（`tnum`）、随系统字号缩放 | 计划 01 §7.2 的 56–72 sp 测试区间 |
| `DoneAtCountdown` | 数字翻页：每一位单独过渡，只有变化的那位移动；倒数时旧数字向下滑出、新数字从上方滑入，伴随淡变与轻微模糊（Android 12+） | 对应 `OWCCountdownTextTransition` 的 `.numericText(countsDown: true)`，时长用 `countdownTick`（160 ms 线性） |
| `DoneAtSpacing` | 4 dp 网格，页边距 16 dp，触达区 ≥ 48 dp | `OWCDesign.pageInset` 16 |
| `DoneAtProgressMeter` | 班次进度条与浮动百分比气泡：指针固定在进度位置，气泡绕指针滑动，最多探出轨道 14 dp；加班换深橙，午休暂停为灰色加微光 | 几何与 `OWCProgressMeter` 相同 |

由 token 实现的 Expressive 行为：

- **形状变化**：`DoneAtPrimaryButton` 静止时为胶囊（圆角取实测高度的一半，大字体下仍是胶囊），按下时收成 12 dp 圆角方形，用 spring 过渡。
- **动效分工**：形状与位置用带回弹的 spring；颜色与透明度只用 tween，不回弹。阶段标记切换颜色用 `phase`（280 ms）。
- **减少动态效果**：系统"移除动画"（动画缩放为 0）时，所有 spec 退化为 snap 或 160 ms 淡变；gallery 可单独切换以便检查。
- **强调层级**：每屏只有一个 filled 主操作；结束类操作用 error 色描边按钮，与开始操作明确区分。
- **主题**：品牌配色为默认；动态配色为可选开关，仅 Android 12+ 显示；浅色、深色、跟随系统与配色来源相互独立。`SystemBarsFollowTheme`（`:app`）让系统栏图标跟随应用主题而非系统主题。

没有采用的：`MaterialExpressiveTheme`、`MotionScheme`、`ButtonGroup`、`LoadingIndicator`、`FloatingToolbar`、形状库 `MaterialShapes` 等 Expressive API。

## 进度条（`DoneAtProgressMeter`）

- 几何放在纯函数 `ProgressMeterGeometry.place`，单测按 iOS 公式核对 0%、5%、50%、100% 与越界值：指针始终对准进度，气泡在两端最多外探 14 dp，且指针总落在气泡的平直边上。
- 气泡宽度按实际文字测量；字号固定 13 dp，不随系统字号放大（与 iOS 相同：进度条高度不变），读屏改用整数百分比，并暴露为进度范围。
- 数字格式跟随应用当前语言（应用内语言），不是系统语言：阿拉伯语显示阿拉伯-印度数字，德语为 `62,4 %`。
- 气泡文字用各配色的前景色（浅色白字、深色深字），不固定白色；iOS 深色下白字配亮橙对比度不足。
- 从右到左的语言从右侧填充，气泡与指针随之镜像。
- 每秒重算，几何不做动画；只有午休微光是动画，减少动态效果时去掉。

## 数字翻页（`DoneAtCountdown`）

- iOS 用系统的 `.numericText(countsDown:)`；Compose 没有等价 API，用稳定的 `AnimatedContent` 按位实现：每一位是一个独立过渡，冒号与未变的位保持不动，等宽数字保证每位宽度固定，不引起重新排版。
- 位移为行高的 60%，同时淡入淡出；模糊用 `Modifier.blur`，只在 Android 12 以上生效，更低版本只有位移与淡变。苹果未公开其曲线、位移与模糊参数，Android 通过录屏对照达到观感接近，不追求逐帧一致。
- `countsDown = false` 反向滚动，供记录等递增数字使用。
- 减少动态效果时直接替换数字；读屏只读完整描述，不读逐秒变化。

## 可访问性

- `DoneAtColorsTest` 检查普通文字、容器文字和四种状态色均 ≥ 4.5:1，描边 ≥ 3:1；用户自定义强调色仍检查全部文字配对 ≥ 4.5:1。默认强调色的例外见下节，不能再宣称所有配对都达到小字 AA。
- 倒计时对 TalkBack 用一句完整描述替代数字，不会每秒重读。
- 阶段标记、分段选择都有文字，不靠颜色传达状态。

### 默认强调色与 iOS 对齐（2026-10-04）

用户的两端对照截图指出默认橙色明显不同。原 Android 为所有强调色文字统一满足 4.5:1，将浅色 `primary` 压为 `#C2410C`、深色改为 `#FF9A5C`，导致主按钮、底栏和进度条偏离 iOS。本次按固定 iOS `18129168` 的 `OWCDesign.accent` 使用浅色 RGB `(0.95, 0.35, 0.04)`、深色 `(1, 0.53, 0.18)`，对应 Android 的 `accentLight` / `accentDark`；`primary`、`surfaceTint` 和另一主题的 `inversePrimary` 共用这两个 token。

计时页收入/主题按钮及记录页收入/全部记录按钮均采用主题 `primary`；自定义和壁纸配色仍能覆盖它。调色对话框的默认草稿从浅色强调色开始，品牌标志的装饰橙 `#F97316` 继续独立使用。

取舍明确保留：默认浅色橙字和橙底白字与 iOS 一致，达到 3:1，但未达到普通小字 4.5:1；测试按这一明确边界检查并锁定 iOS RGB。深色按钮继续使用原有深色前景以保持可读性。普通正文、状态文字和自定义颜色的对比度要求保持 4.5:1。此处只记录设计契约，设备验证结果在 `progress.md`。

## 验证（Pixel 10 Pro 模拟器，API 36）

Debug 专用 gallery：`adb shell am start -n com.rainif.doneat/.gallery.DesignGalleryActivity [--es theme light|dark]`。Release 包不含该页面。

| 探针 | 结果 |
|---|---|
| 浅色 / 深色 | 主计时线框、状态标记、按钮、分段选择、色板正常；深色强制时状态栏图标改为浅色（修复前看不见） |
| 按下主按钮 | 胶囊收成 12 dp 圆角，旁边按钮不受影响 |
| 200% 字体 | 文字换行、状态标记改为多行排列、按钮随内容增高且仍为胶囊（修复前变成固定 28 dp 圆角）；倒计时由系统非线性缩放保持一行 |
| 系统移除动画 | `DoneAtMotion.reduced` 读到开启 |
| 长德文按钮 | 正常换行 |
| 数字翻页 | 录屏逐帧：01:00:00 → 00:59:59 时只有变化的 5 位移动，首位 0 与冒号不动；旧数字向下淡出、新数字从上方带模糊淡入，约 160 ms |
| 进度条 | 浅色、深色、0%、100%、加班、午休均与 iOS 一致；应用语言设为阿拉伯语时从右填充并显示阿拉伯-印度数字（修复前数字跟随系统语言） |

检查中调整：浅色 `secondaryContainer` 原与 `primaryContainer` 几乎同色，改为暖灰 `#F5DED4`。

动态配色仅在代码中接入，本次未在壁纸取色的设备上检查；TalkBack 的实际朗读随 T15 的真实页面检查。

## 依赖树（releaseRuntimeClasspath）

Compose BOM 2026.09.00：`androidx.compose.material3:material3:1.4.0`，`compose-ui`/`foundation`/`animation`/`runtime` 1.12.1，均为稳定版。Android CI 在 Release 依赖出现 `-alpha`/`-beta`/`-rc` 的 Compose 或 Material3 时失败。

## 何时切换到官方 Expressive API

同时满足以下条件时重新评估：

1. `MaterialExpressiveTheme`、`MotionScheme` 与所需组件进入稳定版 Material3，并包含在我们采用的稳定 BOM 中；
2. 切换后 Release 依赖检查仍全部为稳定版；
3. 在 gallery 中对比，官方实现不降低上面的对比度、减少动态效果与大字体表现。

切换时保留 token 名称，把实现改为引用官方 scheme，页面代码不需要改动。

## 玻璃底栏与主题过渡

用户于 2026-09-29 明确要求采用 AndroidLiquidGlass，并参照 iOS 的底栏观感。手机竖屏使用 `DoneAtGlassNavigation`；宽屏/矮屏继续使用 Material 导航侧栏。四个 destination、独立返回栈及重复点按返回根页的行为不变。

- 固定依赖 Backdrop 2.0.1（`io.github.kyant0:backdrop`），间接依赖 Shapes 1.2.1；通过 Maven Central 获取。透镜的三层绘制参考上游 `LiquidBottomTabs` 示例，修改说明保留在源文件头部。两者 Apache-2.0 原文随包附带，在“关于 → 致谢”可查看。
- 用一份页面 backdrop 为底栏提供背景，隐藏的无交互 Tab 层提供透镜内的放大图标和文字。玻璃参数集中在设计系统：8 dp 模糊、14/24 dp 底栏折射、细边缘高光；胶囊形状，橙色文字/图标配中性选中底色。选中层本身保留背景模糊，底栏和透镜分层绘制，允许透镜完整浮出底栏。主题及动态配色均取应用 `MaterialTheme`，不独立读取系统配色。
- API 31 起使用模糊，库在支持 RuntimeShader 的系统上增加折射；更早系统使用实色胶囊，不创建背景采样层。横屏/平板保留导航侧栏。
- 底栏按实际文字高度测量。滚动页面在内容末尾留足空白，固定按钮在底栏上方；键盘弹出时收起底栏。Tab 使用 `selectableGroup` / `Role.Tab` 并暴露选中状态，支持 RTL、文字缩放及现有 19 语言。
- 主题颜色采用既有 `phase` 280 ms 过渡，快速反复切换从当前颜色继续；页面本身保持挂载。系统移除动画时颜色直接切换。按住 Tab 时透镜放大至 1.32 倍，内部图标/文字放大至 1.2 倍。按压使用 `press` 140 ms，跟手使用 `tracking` 无回弹弹簧，松手用 `spatial` 回到最近的 Tab；期间不切换页面。滑到远离底栏处取消、切后台或窗口失焦均收回。系统移除动画时取消放大和跟手移动，保留点击及松手选择。


## 自定义强调色

用户于 2026-09-30 要求 Android 调色板。在主题页保留浅色/深色/自动选项，增加八种常用色、DoneAt 橙色恢复入口，以及 HSV 滑块与六位 HEX 输入的自定义色对话框。对话框编辑草稿，取消不写入设置；保存或选常用色才应用，并沿用现有主题颜色过渡。

- `DeviceSettings.accentColor` 保存不透明 RGB 整数，可为空；与壁纸配色一样属于 Android 本机设置，不加入跨端 RecordJSON 或同步协议。旧文件缺省或非法色值恢复品牌色，不丢弃其他本机设置。
- 选择自定义颜色会关闭壁纸配色；开启壁纸配色时保留之前的自定义颜色，关闭后恢复。默认橙色清除自定义选择并关闭壁纸配色。
- `DoneAtAccent` 保留中性页面表面和语义状态色，调整 primary/secondary、对应 container/前景及 inversePrimary/surfaceTint；原生分段选择、tonal 按钮和滑块轨道与主操作使用同一强调色。选定 RGB 原值保留；强调色用于文字时，必要时向白/黑调整明度，使其对六种表面至少达到 4.6:1。按钮及容器前景选择可读的黑/白。品牌图标保持品牌色。
- 沿用现有稳定 Material3 Slider、AlertDialog 和输入框，无新依赖。常用色有本地化名称、RadioButton 选中状态和 48 dp 触摸范围；滑块暴露标签，HEX 校验错误及保存动作可供辅助功能使用。HEX 输入、预览和格式提示保持从左到右；其余布局按 RTL 镜像。真机微信输入法会把 Ascii 键盘的 A–F 组合成拼音，因此请求直接拉丁输入，但不启用密码遮罩，色值始终可见。


### 背景与 iOS 对齐

用户明确要求背景色与 iOS 一致。`OWCDesign.page/card` 使用 UIKit 的 systemGroupedBackground / secondarySystemGroupedBackground；已有 iOS 27 参考截图中浅色页面为 `#F2F2F7`、卡片为 `#FFFFFF`。Android 对应 `surface/background` 与 `surfaceContainerLow` 使用这两个值；深色采用页面 `#000000`、卡片 `#1C1C1E`，更高层级为 `#2C2C2E` / `#3A3A3C`。移除旧暖棕/淡粉底色，次级文字及描边随中性底色重新配对并通过对比度回归。

自定义强调色和壁纸配色都保留同一套页面/卡片背景。壁纸仍提供强调、次级和语义颜色角色，通过 `withNeutralSurfaces` 统一中性表面；不再让壁纸染色页面及卡片。
