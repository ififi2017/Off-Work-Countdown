# 商店宣传图流水线

生成上架用的商店截图。目前只有 `macos/` 一套，产出 Mac App Store 需要的
2880×1800 中英各五张。

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

1440×900 CSS 以 2 倍渲染成 2880×1800。文案在文件顶部的 `COPY` 表里，中英各
一份，改文案改那里。

## 几个不能改错的地方

- **不能带 alpha 通道。** App Store Connect 直接拒收带透明通道的 PNG，所以
  背景必须完全不透明。改背景样式时留意别引入透明底。
- **一套里所有图必须同尺寸。** 2880×1800 是 Apple 接受的最大档（16:10）。
- **交通灯是 compose 画上去的。** 应用在 macOS 上用覆盖式标题栏，标题栏那块
  空白本来就是留给系统按钮的，浏览器截图里画不出来。补的是应用真实的样子，
  不是编出来的功能——挪动窗口圆角或阴影时，记得同步 `.lights` 的位置。
- **要 macOS 本机跑。** 图里的字体是系统的 SF Pro 和 PingFang SC，别的机器上
  渲染出来不是一回事。Chrome 装在非默认路径时用 `CHROME_BIN` 指过去。

## 不进仓库的东西

`raw/`、`out/` 和 `p-*.html`（排版中间页）都是生成物，一轮下来十几 MB，已在
`.gitignore` 里。要留成品就自己归档，别提交。

Chrome 的用户目录刻意建在系统临时目录而不是这里：它里面带着 Chrome 自带扩展的
JS，留在仓库里 `eslint .` 会去 lint 它们并报错——`.gitignore` 挡得住 git，挡不住
eslint。
