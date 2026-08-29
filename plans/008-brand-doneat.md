# 008 — DoneAt 品牌换装与 iOS 外表面

- **Status**: IN PROGRESS — 品牌母版与主要 iOS/PWA/Tauri 外表面已合入；Web favicon、着色变体与 Live Activity 实拍待做
- **Reviewed against**: 2026-08-27 图标评审与 Grill；2026-08-28 真机收口；`755052f`（PR #82）
- **Severity**: MEDIUM（不挡 007 送审；着色变体后补）
- **Category**: 品牌 / iOS 外表面 / 全平台图标
- **Estimated scope**: `assets/brand`、三端图标位图、`src-mobile/ios` 的 `BrandMark` / LaunchScreen / Widget、`scripts/check-ios-project.mjs`
- **相关**: [007](007-ios-stable-before-subscription.md) 已同批合入；短名与送审节奏以 007 Grill 为准（正式名 **DoneAt**）；002 / 006 不受影响

## 一句话

把图标从通用橙环时钟换成「Open Day」断口钟，把带底板的迷你 App 图标从启动页和灵动岛清出去。iOS 外表面短名是 **DoneAt**，范围不再在本计划里拍板。

## 已完成，不要重做

### 品牌母版（`assets/brand/`，已跟踪）

| 文件 | 用途 |
| --- | --- |
| `off-work-countdown-icon.svg` | 满幅 1024 母版 → iOS AppIcon、Web maskable |
| `off-work-countdown-icon-rounded.svg` | 圆角容器 → Web、Tauri、`BrandIcon` |
| `off-work-countdown-mark.svg` | 透明 UI mark → `BrandMark`、macOS 菜单栏托盘；**只有指针**换明暗色，环和点两边通用 |
| `layers/01..04` | Icon Composer 用的四层平色画布（背景 / 环 / 指针 / 点） |

形态：圆心 512,512、半径 298 的橙环，从 109° 起顺时针扫 262°，缺口落在五点；米色指针指 12 与 5（**17:00 是产品默认下班时刻**，不是装饰）；缺口里一个脱落的橙点。旧图标的橙环 + 米色指针是老用户的识别锚点，刻意保留。

### 位图（全部由 `sharp` 从母版重出）

- iOS：`AppIcon-512@2x.png`（1024，无 alpha）、`BrandIcon.imageset`（圆角，透明角）、新增 `BrandMark.imageset`（无底板，明/暗各 1x/2x/3x）
- Web：`icon-192` / `icon-512`（透明角）、`icon-maskable-512`（满幅不透明）
- Tauri：17 个，用 `npx tauri icon` 从透明的 1024 源图生成；macOS 菜单栏另用 `macos-tray-mark.png` / `macos-tray-mark-dark.png`（不要写进 `bundle.icon`）

### 代码

- `OWCBrandMark.swift` 改成新几何。弧用 `addRelativeArc` 加**正 delta**，绕开 SwiftUI `clockwise:` 在 y 轴向下时方向反直觉的坑。
- `WidgetExtension/OffWorkWidgets.swift` 两处 `Image("BrandIcon")` → `Image("BrandMark")`，并去掉 `clipShape(RoundedRectangle)`。灵动岛和锁屏卡片本身就是容器，里面再套一层圆角底板会读成贴纸。
- `Base.lproj/LaunchScreen.storyboard`：底部居中，`[BrandMark] DoneAt` 一行。**没有**分隔线、**没有**英文副标题 `Off Work Countdown`。明暗自适应。
- 欢迎页首页、品牌收尾页和关于页复用可交互的 `CelebratingBrandMark`：只有缺口里的橙色圆点接收五连击，保留细微的系统玻璃按压反光；第五次让指针旋转一圈并回到五点。Logo 本体不会被拖走。
- `scripts/check-ios-project.mjs`：启动页必须画 `BrandMark` 且文案为 `DoneAt`；禁止 `BrandIcon`、`LaunchMark` / `LaunchMarkLight` / `LaunchMarkDark`，以及英文副标题。`BrandMark` 必须保留 dark appearance（WidgetKit / Live Activity 要用）。已做负向测试。
- 删除 `Splash.imageset`（6 张 2732×2732）。它是 Capacitor 遗留，**全仓无任何引用**，storyboard 用的一直是 `BrandIcon`。

## 已验证 / 未验证

**已验证（模拟器 iPhone 17 Pro）**

- `xcodebuild build-for-testing` 通过；`check:ios`、`check:version`、`npm test`（468）、`lint` 全过
- `npm run build` + `check:build:web`；`npm run build:desktop` + `check:build:desktop` 全过
- App 图标在 iOS 自己的蒙版下、与系统图标并排的实拍
- 未排班态里 `OWCBrandMark` 的实拍（用来确认弧的扫掠方向）
- 所有生成位图的透明度：该透明的角像素 `alpha=0`，该不透明的 `hasAlpha: no`

**已验证（2026-08-28 真机）**

- iPhone 17 Pro 竖屏/横屏与 iPad 上的欢迎页、关于页和侧边栏 Logo 尺寸、居中与明暗色切换
- 浅色启动页使用浅底适配的 mark，不再显示深色底 App Icon
- 五连击只命中橙色圆点；指针庆祝可触发，Logo 不再被长距离拖走，细微玻璃按压反馈保留

**仍未验证 / 未完成**

1. **灵动岛与锁屏 Live Activity 的实际观感**——代码改了，但没有真正触发一个 Live Activity 看过。这是仍未被眼睛确认的主要 iOS 运行时表面。
2. iPad 启动页的最终实拍（SplashBoard 会缓存旧快照）
3. iOS 26 着色（tinted）外观下的图标
4. Web 浏览器标签页仍使用旧的 `app/favicon.ico`；PWA manifest、通知和分享使用的新 192/512 图标已经合入

## 死路，别再走（都有实测）

1. **LaunchScreen 做不了 i18n。** 试过两种机制：19 份 `LaunchScreen.strings`（键 `sUb-t0-lbl.text`），以及每个 `.lproj` 一份完整 storyboard（日文那份的编译产物里按 UTF-8 字节核过，确实烤进了「退勤」）。在一台**全新建、系统语言设为日文**的模拟器上，启动页仍然显示 `Base.lproj` 的英文。对照组排除了「语言没切」：同一台机器桌面 App 名显示的是「退勤」，来自 `ja.lproj/InfoPlist.strings`。结论：启动页由 FrontBoard 在 App 进程建立本地化上下文**之前**加载，只认 Base。已回退，`Base.lproj/LaunchScreen.storyboard` 顶部留了注释记录这个结论。要说用户语言的东西放**第一帧 SwiftUI**。
2. **别用 `qlmanage` 渲透明 SVG。** 它会合成到白底。本次曾因此让所有本该透明的图标（Web / Tauri / `BrandIcon`）圆角外变成不透明白色，浅色背景上看不出来。用 `sharp`（仓库已有依赖，走 librsvg）。
3. **别用 ImageMagick 写 `.ico`。** 它把每一档存成未压缩 BMP，产物 370KB（原版 26KB）。用 `npx tauri icon`。
4. **改了启动页看不到变化，先怀疑快照缓存。** iOS 把启动画面缓存在 `<data>/Containers/Data/Application/*/Library/SplashBoard/Snapshots/`。清掉再重装才看得到新的。另外 `simctl launch --wait-for-debugger` 显示的是**缓存快照**——缓存为空时只有黑屏，得先正常启动一次把快照「热」出来。
5. **不要再给启动页做一套 `LaunchMark`。** 曾为 SplashBoard 画不出透明 `BrandMark` 试过不透明合成图、以及 `LaunchMarkLight` / `LaunchMarkDark` + trait `hidden`。`check:ios` 已禁止这三条名字。启动页继续用和 WidgetKit 同一套 `BrandMark`；真机若 44pt mark 仍不画，先清 SplashBoard 缓存，再查 `UIStackView` 里的 `UIImageView`，不要加第三套图。

## 待办

### P1 — 短名其余表面（启动页已按 Grill 落地）

短名是 **DoneAt**。范围、商店材料、3.1.6 / 3.1.7 节奏见 [007 Grill 锁定](007-ios-stable-before-subscription.md#grill-locked)，不要再拍板。

启动页、19 份 `InfoPlist.strings`、欢迎页首屏、关于页、Widget 画廊、灵动岛 / 锁屏标题已由 007 P4 收口为 DoneAt。共享 `translation.json` 未改，Web / Windows / macOS 名称不受影响；全平台改名见 [009](009-doneat-platform-brand-domain.md#grill-locked)。

### P2 — 深色与着色外观变体 + Icon Composer

`AppIcon.appiconset/Contents.json` 仍只有一张 universal 图，iOS 18+ 的 tinted 外观会按亮度自动推导，深底浅字推出来会很闷。`assets/brand/layers/` 已按 Icon Composer 备好四层，缺的是导入那一步和一个 `.icon` 文件（工程里目前没有）。不挡送审。

### P3 — 真机复测清单

主要 App 内表面已真机收口。剩余按「仍未验证 / 未完成」走一遍，重点是灵动岛；触发一次 Live Activity，确认 mark 是裸的、没有底板、在黑色胶囊上读得出来。着色图标和 iPad 启动页不挡 3.1.7。

### P4 — Web 标签页 favicon

PWA/manifest 的 192、512 与 maskable 图标已经换新；Next App Router 自动使用的
`app/favicon.ico` 仍是旧版。后续从圆角品牌母版生成新的多尺寸 `.ico`，并在浏览器清缓存后
核对浅色/深色标签栏。

### P5 — 提交（已完成）

品牌母版、图片资源、SwiftUI 表面、启动页与检查脚本已随 PR #82 合入 `main`。`xiaohongshu-tool/`
与本计划无关，未进入提交。

## 实现时的判断

1. **图标为什么不是纯抽象的 C 形**
   选：把时钟找回来。抽象 C 形一眼看不出品类，老用户认不出，且在 19 个语区会被读成 19 种字母含义。
   未选：保留纯 Open Day 边界（辨识度更高，但断了老用户的识别锚点）。

2. **指针为什么指 5 点而不是旧图标的 3 点**
   选：17:00 是产品默认下班时刻，指针指它是有实义的。代价是 40px 下竖指针加下方橙点会读成惊叹号——评审时确认可接受。
   未选：沿用旧图标 12/3（不会读成惊叹号，但指针不指任何东西）。

3. **启动页背景为什么跟随系统而不是钉死品牌深紫**
   选：`systemBackground`，与 App 第一帧的明暗一致，避免白闪进深色 App。
   未选：钉死深紫（品牌感更强，但浅色主题用户会看到深→浅的跳变）。

4. **`BrandMark` 为什么由指针承担明暗切换**
   选：环和点是橙色，两种背景上都读得出；只有米色指针在浅底会消失，所以只让它换成 plum。
   未选：整个 mark 做两套完全不同的配色（维护两倍，且橙色本来就不需要换）。

5. **删 `Splash.imageset` 时顺手改了 `check:ios`**
   选：把那条检查从守废弃资源改成守真正在用的 `BrandMark` + DoneAt 文案，并禁止再引入 `LaunchMark` 分叉。
   未选：直接删掉那条检查（启动页就再没有护栏了）。
