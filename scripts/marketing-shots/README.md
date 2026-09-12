# 商店宣传图流水线

生成上架用的商店截图，以及发小红书用的笔记图：

- `macos/` 产出 Mac App Store 需要的 2880×1800，中英各六张。左文右图，右边舞台居中，主窗 / 迷你窗 / 小组件尺寸不同也能对齐。
- `windows/` 产出微软商店用的 3840×2160（16:9，商店接受的最大档），19 种商店语言各五张，共九十五张。版式与 macOS 同源，没有小组件那张。
- `ios/` 产出 iPhone 6.9 英寸 1320×2868 与 iPad 13 英寸 2064×2752，17 种商店语言各六张，共两百零四张。官方 Apple 机框叠在屏洞上。
- `xiaohongshu/` 产出小红书笔记图 1080×1440（3:4 竖版），中文三张。
  这是信息流展示面积最大的比例；1:1 和 4:3 都会被压小或裁切。

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
`npm run shots:macos:compose` 即可。Windows 那套同理：`npm run shots:windows`，
产物在 `windows/out/`。两套共用 CDP 端口，别同时跑两个 capture。

## Windows

`windows/capture.mjs` 与 macOS 共用 `desktop-capture.mjs`，只把 platform 换成
windows：主窗带上应用自绘的最小化 / 关闭按钮（Windows 上系统标题栏是关掉的），
所以 compose 不补任何窗口装饰，圆角按 Windows 11 的 8px。五张依次是倒计时、迷你窗、
统计、班次、设置。

19 种界面语言与商品页的 19 个语言一一对应。阿拉伯语整页从右往左排；韩文要
`word-break: keep-all`，否则标题会从音节中间折开（「얼마 / 나」）；阿拉伯文、天城文
和泰文不能用负字距，会把连写拆开或让上下标挤在一起。

图是在 macOS 上截的，应用界面里的字是 SF Pro / PingFang，不是 Windows 上实际的
Segoe UI / 微软雅黑。要换成真机字体，只能在 Windows 上跑 dev server 重截 raw。

### 商品页导入包

微软商店没有能上传本地截图的 CLI：`msstore` 能用 `submission get` / `update`
改商品页文字，但截图只认「文件名是网址、由它下载」的那条路，读不了本地文件。
所以走 Partner Center 的导入导出：

```bash
# 先在 Partner Center 点「导出列表」，把 CSV 下载下来
npm run msstore:listing -- ~/Downloads/listingData-<id>.csv ~/Downloads/doneat-msstore-3.1.9
```

产物是一个根文件夹：一份 CSV 加一个 `images/`（九十五张）。在 Partner Center 选
「导入列表 → 导入文件夹」上传整个文件夹。文案在 `listing-copy.mjs`，一个语言一段。

**九十五张 3840×2160 合计约 314 MB，Partner Center 的文件夹上传会卡住。** 实测要先
重排成 1920×1080（约 95 MB，仍高于商店 1366×768 的下限）再生成导入包：

```bash
WINDOWS_SHOTS_SCALE=1 npm run shots:windows:compose
npm run msstore:listing -- ~/Downloads/listingData-<id>.csv ~/Downloads/doneat-msstore-3.1.9
```

几个会安静出错的地方：

- **生成的 CSV 不带 BOM。** Partner Center 导出的是 UTF-8 with BOM，而它自己的导入端
  处理不了：带 BOM 的文件——哪怕是刚导出、一个字没改的那份——只会报一句没有任何细节
  的错误。用别的编辑器改完再存时，注意别把 BOM 加回去。
- **图片字段填的是相对 CSV 的 `images/xxx.png`**，不是绝对路径，也不是只写文件名。
  上传的是整个文件夹、CSV 就在里面，所以不要带根文件夹名——文档给的例子
  （`my_folder/images/x.png`）会让路径深一层。真被拒了用
  `MSSTORE_LISTING_ROOT_PREFIX=1` 切回文档那种写法。
- **图片字段留空不会删图**，只会保留上一版；所以五个槽位每次都全写一遍。
- **文字字段留空会回退到 default 列**（这里是空的），等于该语言什么都不显示。
- **表头加一列语言代码就能新开一个语言的商品页**，代码见微软的 supported languages
  表。`Field` / `ID` / `Type` 三列不能动，改了整份文件都不会被处理。
- **新语言不用填 Title。** `Package.appxmanifest` 声明了全部 19 个语言，只有「包里
  没有的语言」才必须从已保留的名称里挑一个。
- 字段上限见 add-and-edit-store-listing-info：描述 10000、更新说明 1500、功能每条
  200、简介建议 270 以内（上限 1000，但超过 270 会被折叠）。

## 两步分别做什么

**`macos/capture.mjs`** —— 截裸界面，存进 `macos/raw/`。截法在
`desktop-capture.mjs`，Windows 那套共用。

用 headless Chrome 打开 `localhost:3001`（`npm run dev:desktop` 的固定端口），
注入一份 `__TAURI_INTERNALS__` 的假实现，让 Web 版本以为自己跑在 Tauri 里：
把 `get_mini_window_settings` 报成对应平台、开机自启报成已开启、语言报成对应
locale。同时把时钟钉死在 2026-09-24（周四）14:22:08，班次设成 09:00–18:00、
月薪 12000 —— 否则每次跑出来的数字都不一样，同一套图里对不上。钉日期是为了统计页：
Store 里预置了九月的出勤和木鱼数，月份、「今天」和迷你窗上的木鱼数（64）都靠这一天
对上。统计页入口按 `desktopStats` 的译文去点，找不到按钮会直接报错，而不是截下上一屏。

窗口按 430×430 以 3 倍渲染；Mini Timer 按 248×100、5 倍渲染且背景透明（成品里放得
比 1:1 大），好让 compose 那步把它叠在渐变上。

中文标题没有空格，`text-wrap: balance` 会从词中间折开。长标题在 `COPY` 里用 `\n`
标出断点。

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
- `ipad-pro-m5-13-inch-space-black-portrait.png`（2300×3000，屏洞 insets 118 / 124 / 118 / 124）

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
截图入口编进 Release。六张竖图是：

1. 计时中（`qaDebugScenario=working`）
2. 主屏幕小组件（欢迎页第 5 屏的系统表面）
3. 午休（`qaDebugScenario=lunch`）

4. 年度记录（`qaRecordsScale=year`）
5. 人生画布（`qaRecordsScale=life`）
6. 专注（`qaRoute=focus`、`qaFocusScenario=runningFocus`）

原片按 `<语言词干>-1.png` 与 `<语言词干>-ipad-1.png` 落在 `ios/raw/`，词干见
`capture.mjs` 的 `LANGUAGES`（`en` / `zh` / `zh-tw` / `ja` / `ko` / `de` / `es` /
`fr` / `it` / `pt` / `ru` / `ar` / `hi` / `id` / `th` / `tr` / `vi`）。截图固定使用
浅色外观、14:22 状态栏、满格网络和 100% 电量。

`IOS_SHOTS_LANGUAGE` 收逗号分隔的列表，只重拍其中几种语言；`IOS_SHOTS_SKIP_INSTALL=1`
沿用模拟器上已装的 QA 包，`IOS_SHOTS_REBOOT=1` 在需要 cfprefsd 重读偏好时重启模拟器
（代价是通知授权被重置，专注页会重新弹权限弹窗）。

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
App Store Connect 的顺序。`ios/validate.mjs` 会确认两百零四张图尺寸正确且没有 alpha
通道。`IOS_SHOTS_LAYOUT_PREVIEW=1` 允许缺原片的语言借用英文原片占位，用来在没拍全之前
先看长文案在文案带里的排版；这种产物不能上传。

`compose.mjs` 不再清空 `ios/out/`，好让你单独重排某几种语言。残留的旧文件由
`validate.mjs` 当作 unexpected 报出来。

当前尺寸来自 Apple 的 Screenshot specifications：竖版 iPhone 使用 6.9 英寸
1320×2868（API 槽位仍是 `APP_IPHONE_67`），iPad 使用 13 英寸 2064×2752。

生成完成后，用仓库内的 App Store Connect 同步脚手架上传。只给 `en-US`、`zh-Hans`、
`zh-Hant` 配截图和 Preview，其余商店语言继承英文。先读
`docs/APP-STORE-CONNECT-SYNC.md`；默认命令只显示差异，替换已有截图集还需要
`--replace-screenshots`。App Preview 竖版是 `886×1920`，必须带音轨。

### App Preview 素材（`IOS_SHOTS_MODE=previews`）

```bash
IOS_SHOTS_MODE=previews IOS_SHOTS_PLATFORM=iphone \
  IOS_SHOTS_LANGUAGE=en,zh-CN node scripts/marketing-shots/ios/capture.mjs
```

原片落在 `ios/previews/raw/`（不进版本库），成品 `886×1920` 仍然是手工剪出来的那两
个 `*-review-886x1920.mov`。`IOS_SHOTS_BEAT=1..6` 只录其中一拍，`IOS_SHOTS_SKIP_BUILD=1`
沿用上一次的构建。种子和截图共用 `launch()`，所以片子和商店图描述的是同一个虚构的
一天，薪资也永远是种子里那个 12000。

默认只录四拍——计时、午休、记录周视图、专注。另外两拍是 `optIn`，要 `IOS_SHOTS_BEAT`
点名才会跑，原因写在 `PREVIEW_BEATS` 里：

- **人生视图（5）** 屏幕不动。`simctl io recordVideo` 按画面变化编码，同样按住八秒，
  三次分别只录到 7.7s、2.75s、0.07s。它是一张图，用 `ios/raw/` 里的那张静帧在剪辑里
  推镜头。
- **锁屏（2）** 录不稳，而且模拟器把锁屏当作 luminance-reduced，实时活动画的是常亮
  变体（"21 分钟"）而不是亮屏时跳秒的样子。

录像时长是"画面动了多久"，不是"按住了多久"——脚本用它当校验，录不到东西会直接报错，
而不是留下一个能播零点几秒的文件。


## 小红书

小红书图文笔记的封面和轮播，统一用 **1080×1440（3:4）**。发现页双列卡片按这个比例
占满；个人主页九宫格会从正中裁成 1:1，所以标题放在画面中上部、手机截图主体落在
中间，上下各留出大约 180px 给裁切和点赞条。

素材直接读 `ios/raw/` 里的中文三张（`zh-1.png` 计时、`zh-2.png` 小组件、
`zh-3.png` 午休）。文案套 iOS 中文三张的标题，副标题按 3:4 缩了一点，好在信息流
缩略图里读完。只改文案时：

```bash
npm run shots:xiaohongshu
```

原片在别处时：

```bash
XHS_SHOTS_RAW_DIR='/path/to/ios/raw' npm run shots:xiaohongshu
```

成品在 `xiaohongshu/out/`：`zh-CN-01-timer.jpg` 起，按序号当封面和后两张轮播。
发笔记用 JPEG（质量 90，远小于 5MB）；PNG 是同尺寸的不透明底稿。三张必须同尺寸，
滑动时才不会跳。
