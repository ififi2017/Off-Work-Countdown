# 商店宣传图流水线

生成上架用的商店截图：

- `macos/` 产出 Mac App Store 需要的 2880×1800，中英各五张。左文右图，右边舞台居中，主窗 / 迷你窗 / 小组件尺寸不同也能对齐。
- `ios/` 产出 iPhone 6.9 英寸 1320×2868 与 iPad 13 英寸 2064×2752，中英各三张，共十二张。官方 Apple 机框叠在屏洞上。

色板跟 DoneAt 走：奶油底 `#FFF1D8`、梅子墨 `#2B1935`、橙 `#F45A1E`。macOS 用晚间梅子渐变，iOS 用奶油底。套框跟官网 DeviceHero 一样：官方机框撑开盒子，截图铺在屏洞里，框叠在上面。不要挖空边框、裁金属圈或重画灵动岛。整机要完整露出；设备尽量铺满舞台，但不能裁掉底框。

这套东西的价值不在脚本本身，而在于它把「图是怎么来的」固定下来了：审核被拒、
换文案、发新版本要重出一轮时，不用再从头调一遍尺寸、字体和交通灯的位置。

## 跑一轮

```bash
npm run dev:desktop
```

另开一个终端：

```bash
npm run shots:macos
```

产物在 `macos/out/`，`zh-CN-01-countdown.png` 这样的命名，序号就是上传到
App Store Connect 时的顺序。

跑的过程中别在同一个仓库里执行 `npm run build`：它和 `next dev` 共用 `.next`，
会把开发服务器正在用的 chunk 覆盖掉，截出来的就是一屏 Runtime Error 而不是应用
界面——而脚本不会报错，它只管截。

`shots:macos` 是 `capture` 加 `compose` 两步。只改文案不用重截界面，单跑
`npm run shots:macos:compose` 即可。

## 两步分别做什么

**`macos/capture.mjs`** —— 截裸界面，存进 `macos/raw/`。

用 headless Chrome 打开 `localhost:3001`（`npm run dev:desktop` 的固定端口），
注入一份 `__TAURI_INTERNALS__` 的假实现，让 Web 版本以为自己跑在 Tauri 里：
把 `get_mini_window_settings` 报成 macos、开机自启报成已开启、语言报成对应
locale。同时把时钟钉死在 14:22:08，班次设成 09:00–18:00、月薪 12000 —— 否则
每次跑出来的数字都不一样，同一套图里对不上。

窗口按 430×430 以 3 倍渲染；Mini Timer 按 248×100 且背景透明，好让 compose
那步把它叠在渐变上。

**`macos/compose.mjs`** —— 把裸图排成成品，存进 `macos/out/`。

1440×900 CSS 以 2 倍渲染成 2880×1800。左边是 DoneAt 字标和文案，右边是一块
固定舞台：主窗、迷你窗、小组件桌面图都在舞台正中，不按各自高度顶齐。文案在
`COPY` 表里，中英各一份。

每张图的画面有三种形态，由 `COPY` 表里的字段决定：默认是应用主窗（圆角、投影、
补画交通灯），`mini: true` 是透明底的悬浮窗，`crop: true` 是桌面截图——目前只有
小组件那张用它。

## `macos/assets/` 与 `ios/frames/`

小组件是真机上的 SwiftUI 组件，`capture.mjs` 造不出来（它只会开无头浏览器截 Web
界面）。所以那两张桌面截图作为固定素材放在 `macos/assets/`。

iOS 官方机框来自 Apple Design Resources，放在 `ios/frames/`：

- `iphone-17-pro-max-deep-blue.png`（1470×3000，屏洞 insets 75 / 66 / 75 / 66）
- `iPad Pro (M5) 13" - Space Black - Portrait.png`（2300×3000，屏洞 insets 118 / 124 / 118 / 124）

许可见同目录的 `Apple Design Resources License.rtf`。框自带灵动岛，不要再另造。

要换 macOS 小组件底图，按 `widget-en.jpg` / `widget-zh-CN.jpg` 覆盖即可，重跑
`npm run shots:macos:compose` 就会用上。截图时连壁纸和 Dock 一起截——单独一块
组件浮着看不出它是「桌面上的东西」，而这正是它跟免费版的差别所在。

## 几个不能改错的地方

- **不能带 alpha 通道。** App Store Connect 直接拒收带透明通道的 PNG。compose
  会用 `sips` 走一遍 BMP 再写回 PNG，把官方机框的透明边压实。
- **一套里所有图必须同尺寸。** macOS 2880×1800；iPhone 1320×2868；iPad 2064×2752。
- **交通灯是 compose 画上去的。** 应用在 macOS 上用覆盖式标题栏，标题栏那块
  空白本来就是留给系统按钮的，浏览器截图里画不出来。补的是应用真实的样子，
  不是编出来的功能——挪动窗口圆角或阴影时，记得同步 `.lights` 的位置。
- **要 macOS 本机跑。** 图里的字体是系统的 SF Pro 和 PingFang SC，别的机器上
  渲染出来不是一回事。Chrome 装在非默认路径时用 `CHROME_BIN` 指过去。
- **iOS compose 用 Chrome `--screenshot`，不要改回 CDP `Page.captureScreenshot`。**
  主屏幕小组件那张大图走 CDP 会挂死。macOS 的 `capture.mjs` 仍用 CDP，那是另一条路。

## 不进仓库的东西

`raw/` 和 `out/` 是生成物，已在 `.gitignore` 里。排版中间页写在系统临时目录，
不落进这个文件夹。要留成品就自己归档，别提交。（`macos/assets/` 和 `ios/frames/`
是例外。）

Chrome 的用户目录刻意建在系统临时目录而不是这里：它里面带着 Chrome 自带扩展的
JS，留在仓库里 `eslint .` 会去 lint 它们并报错——`.gitignore` 挡得住 git，挡不住
eslint。

## iPhone 与 iPad

一条命令完成 Debug 构建、模拟器布景、截图、排版与规格检查：

```bash
npm run shots:ios
```

需要本机安装 Xcode、iOS 模拟器运行时、Google Chrome，以及以下两个模拟器：

- `iPhone 17 Pro Max`
- `iPad Pro 13-inch (M5)`

名字不同时可以覆盖：

```bash
IOS_SHOTS_IPHONE='你的 iPhone 模拟器名' \
IOS_SHOTS_IPAD='你的 iPad 模拟器名' \
npm run shots:ios
```

`ios/capture.mjs` 会先生成原生规则包，再把 Debug App 构建到系统临时目录。它只把
已有的 DEBUG QA 值作为当前 App 进程的启动参数；不会写入用户持久设置，也不会把
截图入口编进 Release。三张竖图是：

1. 计时中（`qaDebugScenario=working`）
2. 主屏幕小组件（欢迎页第 5 屏的系统表面）
3. 午休（`qaDebugScenario=lunch`）

原片按 `en-1.png` / `zh-1.png`、`en-ipad-1.png` / `zh-ipad-1.png` 落在 `ios/raw/`。
截图固定使用浅色外观、14:22 状态栏、满格网络和 100% 电量。

只改宣传文案或画面排版时，无需重跑 Xcode：

```bash
npm run shots:ios:compose
npm run shots:ios:validate
```

原片在别的目录时：

```bash
IOS_SHOTS_RAW_DIR='/path/to/raw' \
IOS_SHOTS_OUT_DIR='/path/to/output' npm run shots:ios:compose
IOS_SHOTS_OUT_DIR='/path/to/output' npm run shots:ios:validate
```

成品在 `ios/out/`。`zh-CN-iphone-01-timer.png` 这样的序号就是各语言、各设备上传到
App Store Connect 的顺序。`ios/validate.mjs` 会确认十二张图尺寸正确且没有 alpha
通道。

当前尺寸来自 Apple 的 Screenshot specifications：竖版 iPhone 使用 6.9 英寸
1320×2868（API 槽位仍是 `APP_IPHONE_67`），iPad 使用 13 英寸 2064×2752。

生成完成后，用仓库内的 App Store Connect 同步脚手架上传。只给 `en-US`、`zh-Hans`、
`zh-Hant` 配截图和 Preview，其余商店语言继承英文。先读
`docs/APP-STORE-CONNECT-SYNC.md`；默认命令只显示差异，替换已有截图集还需要
`--replace-screenshots`。App Preview 竖版是 `886×1920`，必须带音轨。
