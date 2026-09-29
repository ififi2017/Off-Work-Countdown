# DoneAt for Chrome

采用 400 px 宽的工具栏弹窗，启动骨架与主界面共用 500 px 高度，避免加载后窗口跳变。
设置页为 560 px 高，较长内容在窗口内滚动，底部按钮始终可见。
沿用 PC 版的 Geist 字体、滚动数字和收入汇总，复用 Web 的时间滚轮下拉。支持上下班时间、跨夜班、工作日、午休、月薪/日薪、
收入隐藏、五种主题和全部 19 种界面语言。

## 构建与安装

```bash
npm install
npm run build:extension
```

1. 在 Chrome 地址栏打开 `chrome://extensions`。
2. 开启「开发者模式」，点击「加载已解压的扩展程序」。
3. 选择仓库中的 `build/chrome-extension` 文件夹。
4. 在工具栏扩展菜单中固定 DoneAt，点击图标打开。

最低 Chrome 版本为 120。修改源码后重新构建，再在扩展管理页点击 DoneAt 的
刷新按钮。构建目录已被 Git 忽略；使用同一目录重载可保留扩展内的设置。
ZIP 需先解压再加载。已上架
[Chrome Web Store](https://chromewebstore.google.com/detail/bepmkflijihfjodllcjogafffdcjabcf)；
Web 首页下载区和官网下载页各有一条低调的文字链接，不做商店徽章。

## 使用行为

- 主界面设置上下班时间和工作日，点击「开始倒计时」。再次打开按实际时间恢复。
- 午休、薪资与语言在设置页修改，点击「保存」生效；返回或关闭弹窗放弃未保存的修改。
- 上下班时间和工作日只在主界面编辑；倒计时底部的「修改班次」返回编辑。首版不保存历史班次。
- 设置页底部用一个「获取 App」按钮统一指向 doneat.app 对应语言首页，由官网分发各平台下载；
  链接只带 `utm_source=chrome-extension&utm_medium=referral&utm_campaign=get-app`，不含作息或收入。
  这些链接由用户点击后在新标签页打开，不携带作息、薪资或用户标识。
- 午休仅在完整落于班次内部时扣除。无效范围会显示说明，沿用 PC 版的忽略规则。
- 工时与收入使用有效工作时间，午休期间暂停累加。周/年汇总标注为按设置推算。
- 点击弹窗外部会关闭弹窗，这是 [Chrome popup 的标准行为](https://developer.chrome.com/docs/extensions/develop/ui/add-popup)。
  关闭后没有后台循环；下次打开重新按当前时间计算，包括跨天和休息日。
- 首版包含弹窗，无后台通知、侧边栏、工具栏倒计时角标或桌面悬浮窗。

## 数据与架构

- 使用扩展自身 origin 的 `localStorage`。设置不与网页版、PC 应用或 Chrome Sync 同步；
  卸载扩展会删除这些设置。没有账号、远程资源、网络请求、网页读取或统计上报。
- `src-extension/popup.tsx` 组合共享 `RollingText`、`TimeSelector`、`PeriodSummary`、`WorkdaySelector`、
  `ThemeToggle` 等组件，复用 `lib/countdown.ts`、`lib/summary.ts` 和 `lib/second-tick.ts`。
- `state.ts` 只负责输入校验和选择现有规则返回的班次，不另写工时、收入或午休公式。
- 翻译直接引用 `public/locales`，构建时按 `src-extension/translation-keys.json` 只打包弹窗用到的键；
  新增共享文案时同步更新该列表。19 种语言都在本地，不依赖语言下载请求。
  每种语言是 `chunks/` 下的独立本地模块，打开弹窗只加载当前语言，切换语言时再按需加载。
  扩展专用文案在 `src-extension/copy.json`，
  必须覆盖全部 19 种语言。Chrome 安装描述采用 Chrome 支持的语言目录名。
  商店标题与简介也在这里（`extensionName` / `extensionSummary`），标题跟 iOS 商店名一致，
  如「DoneAt - 下班倒计时」；工具栏提示和 `short_name` 仍只写 DoneAt。
- Chrome 要等主文档的 `load` 完成才显示工具栏弹窗（见
  [Chromium 的显示逻辑](https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/browser/ui/views/extensions/extension_popup.cc)）。
  `popup.html` 只加载 `bootstrap.js` 与 `bootstrap.css`；引导在 `load` 回调结束后的
  下一次任务中加载完整样式和应用脚本。不要把 React、语言包或字体 preload 放回 HTML，
  也不要使用可能被隐藏窗口节流的 `requestAnimationFrame` 等待显示。
- 首屏加载失败时提供重载按钮；错误文案随 Chrome 语言，覆盖安装元数据的全部语言。
  Tailwind 只扫描实际引入的组件；包检查限制引导 JS 小于 3 kB、基础 CSS 小于 2 kB，
  完整 JS 小于 700 kB、完整 CSS 小于 55 kB。
- 独立 esbuild 入口避免 Next 的内联引导脚本和路由运行时。
- 共享动画组件用 framer-motion 的 `LazyMotion` + `m`，只打包淡入淡出和位移，不带拖拽与布局投影。
- 图标提供 16 / 32 / 48 / 128：32 取自 `src-tauri/icons`，
  16（工具栏 1x）、48（扩展管理页）与 128 在 `src-extension/icons`。128 按 Chrome 要求
  图案 96×96、四周 16px 透明边，由 `npm run shots:chrome-web-store:compose` 生成后复制过来。
- 商店截图、宣传图和商店图标见 `scripts/marketing-shots/README.md` 的 Chrome 应用商店一节；
  商店页中英文案与隐私问卷答案见 [Chrome Web Store listing](CHROME-WEB-STORE-LISTING.md)。

## 上架与发版

`npm run package:extension` 构建并生成 `build/doneat-chrome-extension-<version>.zip`，
可直接在开发者后台上传。首次上架、商店页、截图和隐私问卷只能在后台手动完成。

上架后用 Chrome Web Store API（V2）发新版本，凭据放在 `~/.config/doneat/chrome-web-store.env`
（字段见 `scripts/chrome-web-store-publish.mjs` 顶部），不进仓库：

```bash
npm run cws:status    # 只读：商店里已发布 / 审核中的版本
npm run cws:upload    # 构建、打包、上传；版本号必须高于商店里的
npm run cws:publish   # 提交审核，通过后自动发布（加 -- --staged 则等手动发布）
```
  [Manifest V3 CSP](https://developer.chrome.com/docs/extensions/reference/manifest/content-security-policy)
  限制脚本为本地文件；`connect-src 'none'` 禁止发出网络请求。
- 版本读取 `package.json`，构建前自动运行 `check:version`。不改变现有 Web/Desktop 构建目标。

## 验证

```bash
npm run lint
npm test
npm run build:extension
npm run check:build:extension
```

`bootstrap.test.ts` 检查窗口 load 回调返回后才加载应用，以及资源失败时的重载入口。
`state.test.ts` 覆盖关闭后重开、午休收入暂停、跨夜班、休息日、损坏数据、19 语言及打包文案完整性。
包检查覆盖 MV3、版本、CSP、本地资源、无扩展权限、无远程脚本及无桌面运行时。
CI 会构建并检查扩展。共享组件或规则的改动仍需完成根目录 `AGENTS.md` 中对应的检查。

界面可通过本地 HTTP 静态服务预览构建目录；这只验证渲染和交互。
真正的扩展验收仍须加载到 Chrome，检查工具栏弹窗、关闭重开、浏览器重启、离线和数据保留。

### 启动诊断

`performance.getEntriesByType("mark")` 可查看本地的 `doneat:bootstrap`、
`doneat:window-load`、`doneat:app-request`、`doneat:ready` 时间点。
这些标记仅留在当前页面内存中，不记录作息、收入或身份，也不上传。
HTTP 预览可以验证加载顺序；工具栏点击到窗口出现的总时间还包括 Chrome 创建进程和窗口的耗时。
