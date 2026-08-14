# M6 · 微软商店上架计划（MSIX）

在现有 NSIS 与 MSI 之外新增一条并行的 MSIX 产线，把 Windows 客户端送进
Microsoft Store，并让 `desktop-v*` tag 在发 GitHub Release 的同时自动向商店提交更新。
商店版的更新功能接入微软商店。

## 当前进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0** | Partner Center 账号、占名、拿到应用标识三元组 | 🟢 身份、隐私政策页、支持邮箱已就绪；listing 素材待补 |
| **P1** | `msstore` 构建渠道：更新入口改接商店、自启动改 startupTask | 🟢 更新入口与自启动都已完成并在真机验证 |
| **P2** | `Package.appxmanifest` + 本地自签打包，真机验收 | 🟢 自签包已装机逐项验收，WACK PASS |
| **P3** | 首次人工提交并上架 | ⬜ 未开始 |
| **P4** | Entra 凭据 + `release-msstore.yml` 自动提交 | ⬜ 未开始 |
| **P5** | 文档：下载页、README、About 页区分两个渠道 | ⬜ 未开始 |

P3 是硬性串行点：**商店提交 API 只能更新已上架的产品，创建不了产品**，所以
P4 无论如何排不到 P3 前面。

### 已完成（2026-08-13）

在 macOS 上能验证的部分都做完了，全部在分支 `codex/msstore-msix` 上：

| 交付物 | 位置 |
|---|---|
| `DESKTOP_CHANNEL` 渠道维度 | `next.config.mjs`、`scripts/build-desktop.mjs`、`npm run build:desktop:msstore` |
| 商店构建配置 | `src-tauri/tauri.msstore.conf.json`（`bundle.active: false` + `mainBinaryName`） |
| 自更新按渠道编译进出 | `self-update` Cargo feature（默认开）、`lib/updater-stub.ts` 模块替换 |
| updater capability 内联 | `src-tauri/tauri.conf.json` 的 `security.capabilities` |
| 商店深链 | `open_microsoft_store_listing` 命令 + Store ID `9PM0HJ2PP2LJ` |
| 「在 Microsoft Store 中检查更新」文案 | 19 份 `translation.json` |
| 包清单 | `src-tauri/msstore/Package.appxmanifest`（含 `windows.startupTask` 声明） |
| 打包脚本 | `scripts/pack-msix.mjs`、`npm run pack:msix` |
| 版本校验扩展 | `npm run check:version` 一并校验 MSIX 四段版本号 |
| 隐私政策页与支持邮箱 | `/en/privacy`、`/zh-CN/privacy`、`config/site.ts` 的 `supportEmail` |

已验证：`--no-default-features` 的产物中不含更新器代码与权限（前端产物搜不到
`plugin:updater`，`cargo tree` 里也没有 `tauri-plugin-updater` 与
`tauri-plugin-process`）；两种 feature 配置下 `cargo fmt --check` 与
`clippy -D warnings` 均通过；完整 `tauri build` 在 macOS 上产出
`Off Work Countdown` 可执行文件。

### P2 验收：在 Windows 上怎么跑

以下命令已在 Windows 11 + winapp CLI 0.5.0 上实际跑通（2026-08-13），
**与初稿相比有四处必须的订正**，每处都在注释里说明了原因。

环境：Windows 11、Node 24、Rust MSVC 工具链，外加

```powershell
winget install microsoft.winappcli --source winget
```

⚠️ **Rust 工具链是真前提，不是「大概装过」。** 初稿把它当既有条件，实际这台机器上
没有。`winget install Rustlang.Rustup` 装完之后**必须开一个新终端**，否则
`cargo` 不在 PATH 上，表现是 tauri 报
`failed to run 'cargo metadata' … program not found`，看起来像 tauri 的问题。

```powershell
npm ci
npm run check:version

# 1. 构建商店渠道的 exe。
#
#    ⚠️ 直接用 node 调 tauri.js，别走 npx，也别走 node_modules\.bin\tauri。
#    Windows 上那两条都是 shell 包装器（.cmd / .ps1），会先把第一个 `--` 自己
#    吃掉，tauri CLI 收到的就成了裸的 --no-default-features 并拒掉。
#    走 node 就没有包装器插在中间，一个 `--` 即可，各 shell 表现一致。
node node_modules/@tauri-apps/cli/tauri.js build --config src-tauri/tauri.msstore.conf.json -- --no-default-features

# 2. 先只暂存，确认目录结构与图标齐全再往下走
npm run pack:msix -- "x64=src-tauri/target/release/Off Work Countdown.exe" --stage-only

# 3. 本地自签打包。
#
#    ⚠️ cert generate 必须显式指 --manifest。不指的后果不是报错，而是**静默**用
#    `CN=<当前用户名>` 生成证书并 exit 0，直到签名后装不上才暴露。
winapp cert generate --manifest src-tauri\msstore\Package.appxmanifest --if-exists skip
#
#    ⚠️ 这一步不能走 `npm run pack:msix --`：npm 自己有一个 `--cert` 配置项，会把
#    它连同值一起吃掉，脚本收不到，于是**打出一个未签名的包**——而未签名的包
#    Add-AppxPackage 会直接拒绝，所以至少不会漏到更后面。直接调 node 绕开 npm。
node scripts/pack-msix.mjs "x64=src-tauri/target/release/Off Work Countdown.exe" --cert devcert.pfx

# 4. 信任证书（需要管理员终端），每台机器只需一次
winapp cert install .\devcert.pfx

# 5. 安装（普通终端即可，证书受信之后不需要管理员）
Add-AppxPackage .\finiaRStudio.OffWorkCountdown_3.1.3.0_x64.msix
```

`winapp pack` 与 `winapp package` 是同一个命令的两个名字，别名有效，
`scripts/pack-msix.mjs` 里用哪个都行——CLI 帮助里的规范名是 `package`。

**怎么确认 `--no-default-features` 真的生效了**（这是本轮最该自动化的一条检查，
比读代码和搜前端产物都直接）：

```powershell
Get-ChildItem src-tauri\target\release\.fingerprint\ -Filter "*updater*"
Get-ChildItem src-tauri\target\release\.fingerprint\ -Filter "*tauri-plugin-process*"
```

两条都应该**没有任何输出**，同时 `.fingerprint\` 下有 20 多个其它
`tauri-plugin-*` 目录作为对照——空结果才有意义。少写一个 `--` 的那种包
在这里会立刻显形。

⚠️ `.fingerprint\` 有个坑：**它不会因为依赖被移除而清理**。把某个插件改成
可选之后，旧构建留下的目录还在，照着它看会得出"没编译掉"的错误结论。要判断
当前配置到底带没带，用依赖图，别看残留：

```powershell
cargo tree --manifest-path src-tauri\Cargo.toml --no-default-features | Select-String "tauri-plugin-(autostart|updater|process)"
```

商店渠道下这条应该**一条都匹配不到**，默认渠道下三条齐全。

#### ⚠️ 两种 feature 配置的 clippy/test 不能裸跑

`cargo clippy --no-default-features` 直接跑会在 build script 阶段失败：

```
failed to resolve ACL: UnknownManifest { key: "updater", ... }
```

原因是裸 cargo 用的是 `tauri.conf.json`，而那里的 capability 白名单内联了
`updater-capability`（决策 2），插件却被 `--no-default-features` 编译掉了。
`tauri build --config` 会替换掉整个数组，裸 cargo 不会。

**这不是本轮改出来的**——在这个分支上一直如此，只是之前的验证跑在 macOS 上，
而 macOS 上另有一处 Windows-only 代码不参与编译，掩盖了它。正确的跑法是把商店
渠道的 capability 从环境变量喂进去：

```powershell
$env:TAURI_CONFIG = '{"app":{"security":{"capabilities":["default","desktop-capability"]}}}'
cargo clippy --manifest-path src-tauri\Cargo.toml --all-targets --no-default-features -- -D warnings
cargo test  --manifest-path src-tauri\Cargo.toml --no-default-features
Remove-Item Env:\TAURI_CONFIG
```

默认渠道那一轮不需要这个变量。另外 **clippy 必须在 Windows 上也跑一遍**：
`open_microsoft_store_listing` 里的 `needless_return` 只在 Windows 编译时才存在，
macOS 上那段被 `#[cfg]` 掉了，本轮就是在 Windows 上才发现的。

### P2 验收结果（2026-08-13，Windows 11 26100 / winapp CLI 0.5.0）

自签包已装机（`finiaRStudio.OffWorkCountdown_3.1.3.0_x64.msix`，4.9 MB），
`PackageFullName` 的后缀 `vzcbgpq3qw6zw` 与 §3 记录的 Package Family Name 对得上
——这是三元组没写错的第一个可验证信号。

**WACK：PASS**（`appcert.exe test`，无 FAIL 项）。

三项重点的结论：

1. **启动时零网络请求，已实测。** launch 后连续 45 秒轮询该进程的 TCP/UDP 套接字，
   `Distinct sockets observed: 0`；先 `Clear-DnsClientCache` 再看
   `Get-DnsClientCache`，`github`/`gh-proxy` 一条解析都没有。
   不只是"没有更新请求"，是**整个进程一个连接都没建**。
2. **「检查更新」跳商店、页面打不开，符合预期。** 商店进程被拉起并跳转，页面显示
   「你搜索的内容不在此处」。深链机制本身是通的，空页面只是因为产品还没上架。
   **不是 bug，P3 之后自然生效。**
3. **自启动：旧行为已确认是个假开关，决策 3 已落地并验证。** 见下。

#### 自启动：MSIX 里注册表那条路坏在哪

改造前的实测（值得留档，因为它比"不受支持"具体得多）：应用内开关按下去 **UI 变成
"开"，重启之后还是"开"**，但

- 真实的 `HKCU\...\Run` 里**从头到尾没有出现过**这个应用的条目；
- MSIX 的 StartupTask 状态一直是 `State=0`（禁用）。

也就是说 `tauri-plugin-autostart` 的写入被 MSIX 的**注册表虚拟化**吃进了包容器，
而它读回来的又是同一份虚拟视图——**自洽，但 Windows 完全看不见**。这比"不生效"
更难查：应用内的每一个可观察信号都告诉你它开着。

改造后（决策 3，走 `windows.startupTask`）逐步验证：

| 动作 | 观察 |
|---|---|
| 装好后首次读 | 开关 = 关，与 `State=0` 一致（旧实现这里会错报"开"） |
| 应用内打开 | `State` 0 → 2，`UserEnabledStartupOnce` 0 → 1 |
| 看「设置 → 应用 → 启动」 | **条目出现了**，开关为"开" |
| 在系统设置里关掉 | `State` → 1（DisabledByUser） |
| 重启应用再读 | 开关 = 关且**置灰**，并显示「由 Windows 接管。可在「设置 → 应用 → 启动」中更改。」 |
| 全程 | 真实 `Run` 键始终没被写过 |

⚠️ **别用直接改注册表 `State` 的办法模拟"用户关掉了"**——试过，改成 1 之后
`StartupTask.State()` 仍然报 Enabled。那个 DWORD 不是 WinRT 的真实来源（或至少
不是唯一来源）。要模拟只能真的去系统设置里点那个开关。

#### §5 那张表的实测结果

| 功能 | 结果 |
|---|---|
| Windows Mini Timer | ✅ **容器内完全正常**——透明圆角、木鱼计数、与主窗读数同步；位置也记住了（重启后回到同一坐标）。这是原先最不确定的一项 |
| single-instance | ✅ 连开两次，始终只有一个进程、同一个 PID |
| 托盘图标 | ✅ 已注册，且 `NotifyIconSettings` 里记的是**包标识路径**，`InitialTooltip` 正确 |
| 主窗渲染 | ✅ WebView2 在容器里正常，无白屏 |
| 配置读写 | ✅ 能读能写——但**位置与决策 6 的假设不符**，见下 |
| 通知实际弹出 | ⬜ 未验证（要等到真的触发里程碑，本轮没测） |
| 全局快捷键实际触发 | ⬜ 未验证（设置项在，没做按键实测） |
| 托盘菜单的本地化文案 | ⬜ 未验证 |
| 日志写入 | ➖ 不适用：`tauri_plugin_log` 只在 `debug_assertions` 下注册，release 包根本不写日志文件。§5 原来那一行描述的事情在正式包里不存在 |

#### ⚠️ 决策 6 的前提是错的：配置**是互通的**

决策 6 假设"MSIX 会把 `tauri-plugin-store` 的写入重定向到包容器"。**实测不是这样**：

- 商店版写的是**真实的** `%APPDATA%\com.rainif.offworkcountdown\desktop-state.json`
  （在应用内改一个设置，这个文件的 mtime 立刻跟着变，而当时只有 MSIX 那个进程在跑）；
- 包容器 `%LOCALAPPDATA%\Packages\<PFN>\` 下的 `LocalState`、`LocalCache`、
  `RoamingState` **全是空的**。

被虚拟化的只有**注册表**（`SystemAppData\Helium\User.dat`），文件写入没有。
这台机器上 NSIS 版也装着，两边读写的是同一份 `desktop-state.json`。

后果要顺着改：

- 决策 6「不做迁移」的**结论仍然成立**，但理由变了——不是"代价用文档承担"，
  而是**根本不需要迁移**；
- §7 验收标准第 7 条、以及 P5 要在下载页写的「配置与 GitHub 版不互通」
  **是错的，不能这么写**；
- 决策 7 那张表里「配置位置：包容器，与左侧不互通」同样要改；
- 真正需要提醒的反而是另一面：**两个渠道同时装着会共用一份配置**，同时开两个
  实例互相覆盖设置是可能的（single-instance 只在同一个包标识内生效）。

**共用配置还有一个不那么直观的后果：通知会互相吃掉。**
`notificationMarker.sentMilestones` 和倒计时设置存在同一个文件里，所以先跑的那个
渠道把当天的里程碑标记成已发之后，另一个渠道启动时看到的就是"这些都发过了"，
于是整天一条都不弹。本轮就撞上了：验收时 `sentMilestones` 已经是
`[50,75,90,95,100]`、`endAtMs` 也过了，商店版因此全程安静——**这不是通知坏了**。
用包 AUMID 直接发 toast 是能弹的（见 §5 表格），说明平台这一层没问题。

排查这类"商店版不弹通知"时，先看这个 marker 再怀疑 MSIX。

这条只在 Windows 真机上暴露，macOS 上的开发验证碰不到，正是 §5 开头那句告诫的例子。

## 0. 核心判断：走 MSIX，不走 EXE/MSI

微软商店对 Win32 应用开了两条路，对本项目而言差别是决定性的：

| | EXE/MSI（直接传现有 NSIS 包） | MSIX |
|---|---|---|
| 代码签名 | **必须自己 Authenticode 签名**，证书须链到微软信任根 | **不必签名**，过认证后由微软证书重签 |
| 费用 | OV/EV 证书 $200–400/年，EV 还要 HSM | 0 |
| 改造量 | 几乎为零 | 中等（manifest、自启动、更新器） |
| 更新 | 自己管 | 商店管 |

[PLAN-M5-TAURI.md §6](PLAN-M5-TAURI.md) 已经决定不购买代码签名证书。这一条把
EXE/MSI 那条路直接排除了——它的前置条件正是 M5 明确不做的事。

**因此 MSIX 是唯一成立的路线。** 它顺带解决了 M5 §6 遗留的 Windows SmartScreen
摩擦：商店安装不经过 SmartScreen 拦截。这是上架真正的收益，比"多一个分发渠道"实在。

代价是本文剩下的全部内容：MSIX 是容器化的应用模型，本项目有两处行为在容器里不成立
——**自动更新**和**开机自启**，它们各自对应决策 2 和决策 3。

## 1. 目标与非目标

**目标**

- **MSIX 是并行新增的第三条 Windows 产线，NSIS 与 MSI 完全不变。** 同一个
  `desktop-v*` tag 之后产出三种 Windows 安装形态，各自走各自的分发与更新通道。
- Windows x64 + ARM64 以单个 `.msixbundle` 上架，覆盖面与现有 NSIS 包一致
- `desktop-v*` tag 触发后自动向商店提交更新，无需人工上传包
- **商店版的更新功能接入微软商店**——应用内的更新入口保留，只是改由商店承担
- 商店版与 GitHub 版长期并存，互不影响

**非目标**

- **M6 不做 macOS App Store。** macOS 商店版需要独立的沙盒适配、签名与审核产线，
  不是 MSIX 上架的附带工作；它已转入 §9 的远期里程碑，不与 M6 串行推进。
- **不迁移 GitHub 版用户。** 商店版是新增入口，不是替代品。
- **不做商店内购、不做付费版。** 保持免费——顺带说，GitHub Actions 那条自动
  更新链路目前只支持免费应用（见 §4）。
- **不追求 19 语言的商店 listing。** 应用 UI 的 19 语言不变；商店页面的描述文案
  初期只做英文 + 简体中文，与 `lib/content-locales.ts` 对长文内容的既有取舍一致。

## 2. 架构决策

### 决策 1：商店版是新增的分发渠道，不是新的构建目标，更不是新分支

`BUILD_TARGET` 已经把 Web 与 Desktop 拆成两个构建目标（M5 决策 1）。商店版**不新增
构建目标**——它的前端产物与 Desktop 同源，差别只在更新入口与自启动实现。因此引入一个
正交的**渠道**维度：

```
BUILD_TARGET     = web | desktop        产物形态（静态导出与否）
DESKTOP_CHANNEL  = github | msstore     分发渠道（更新通道与自启动实现）
```

沿用 `next.config.mjs` 里 `NEXT_PUBLIC_BUILD_TARGET` 的既有做法，构建期确定，
避免运行时探测造成首帧闪烁：

```js
NEXT_PUBLIC_DESKTOP_CHANNEL: process.env.DESKTOP_CHANNEL === 'msstore' ? 'msstore' : 'github',
```

对应新增：

- `npm run build:desktop:msstore` —— `scripts/build-desktop.mjs` 接受渠道参数
- `src-tauri/tauri.msstore.conf.json` —— 覆盖 `beforeBuildCommand` 指向上面这条命令

**为什么不用第三条分支：** 理由与 M5 决策 1 完全相同，且这次更极端——两个渠道
共享的不只是 `components/`，连 `src-tauri/` 都共享，独有的只有一份 manifest 和
若干开关。开分支的搬运成本会随时间复利增长。

### 决策 2：更新入口保留，实现改接微软商店

**`tauri-plugin-updater` 在商店版里必须关掉，这是硬性的**：MSIX 的安装目录
（`C:\Program Files\WindowsApps\...`）是只读的，更新器下载的 NSIS 增量包根本装不上；
应用自行安装代码也不符合商店对更新渠道的要求。

**但"关掉更新器"不等于"没有更新功能"。** 商店版的更新由商店承担，应用内的
「检查更新」入口应当保留并指向商店，而不是整块消失——一个看不到任何更新入口的应用，
用户无从判断自己是不是最新版，只会退回到手动去商店翻页面。

分两步做：

| | 实现 | 阶段 |
|---|---|---|
| **保底** | `ms-windows-store://pdp/?productid=<StoreId>` 深链，点击跳转商店详情页 | P1 |
| **增强** | `Windows.Services.Store` 的 `StoreContext`，应用内检查并触发商店更新 | 可选，P3 之后 |

先做深链的理由不是省事，是**可测性**：`StoreContext` 的更新查询在 sideload 安装的
包上拿不到结果，只有真正从商店装下来的版本才能验证。把它排在 P3 之前等于写完一段
无法验收的代码。深链在任何安装形态下都能验证，且永远不会失效。

深链需要给 [src-tauri/capabilities/desktop.json](../src-tauri/capabilities/desktop.json)
的 `opener:allow-open-url` 白名单加上 `ms-windows-store:` scheme——该插件的白名单
能否表达非 http scheme 需要在 P1 实测，若不行则退回 Rust 侧直接调 `ShellExecute`。

改造涉及四处，缺一不可：

| 位置 | 现状 | 商店版 |
|---|---|---|
| [src-tauri/src/lib.rs:1696](../src-tauri/src/lib.rs) | `.plugin(tauri_plugin_updater::Builder::new().build())` | Cargo feature 关掉 |
| [src-tauri/src/lib.rs:1619](../src-tauri/src/lib.rs) | `install_update_via_mirror` command | 同上，一并编译掉 |
| [src-tauri/capabilities/desktop.json](../src-tauri/capabilities/desktop.json) | `updater:default` | 拆出去，商店版不加载 |
| [components/off-work-countdown.tsx:696](../components/off-work-countdown.tsx) 与 [:1674](../components/off-work-countdown.tsx) | 动态 import `@tauri-apps/plugin-updater` | 按渠道换成商店深链 |

⚠️ 镜像回退（`install_update_via_mirror` 与 `latest-cn.json`）在商店版里没有对应
概念——商店自己解决了中国大陆的下载问题。这条链路整体编译掉，不要试图保留。

**⚠️ capability 必须内联进 `tauri.conf.json`，不能放在 `capabilities/` 目录里。**

直觉做法是把 `updater:default` 拆到 `capabilities/updater.json`，再用
`app.security.capabilities` 白名单在商店构建里排除它。**这个做法不成立**，实测
（2026-08-13）：`tauri-build` 会解析并校验 `capabilities/` 目录下的**每一个**文件，
白名单只决定哪些生效，不影响校验。于是 `--no-default-features` 构建在 build script
阶段就炸：

```
Permission updater:default not found, expected one of autostart:default, …
```

正确做法是把它作为**内联 Capability 对象**写进 `tauri.conf.json` 的白名单，
`capabilities/` 目录里不留任何引用更新器的文件：

```jsonc
// tauri.conf.json —— 白名单一旦显式列举，就必须把目录里的都列上
"capabilities": [
  "default",
  "desktop-capability",
  { "identifier": "updater-capability", "windows": ["main"],
    "permissions": ["updater:default", "process:default"] }
]

// tauri.msstore.conf.json —— 数组整体替换，内联那项自然消失
{ "app": { "security": { "capabilities": ["default", "desktop-capability"] } } }
```

`process:default` 跟着一起走：`relaunch()` 只在装完更新后用到，没有第二个调用点。

代价是白名单从此要手工维护——新增 capability 文件必须同时加进这两个列表，否则它
不会生效。这是内联换来的，不是可选项。

**⚠️ Cargo feature 与 `default` 的方向**：`tauri-plugin-updater` 应当放进
**默认开启**的 feature（例如 `default = ["self-update"]`），商店构建用
`--no-default-features` 关掉。反过来做——默认关闭、GitHub 构建显式打开——的后果是
本地 `npm run tauri:dev` 会静默丢失更新器，而这个功能在开发期几乎不会被主动测试，
问题会一路漏到发版。

**About 页文案要同步改。** [AGENTS.md](../AGENTS.md) 里"版本检查在启动时自动运行"
那段描述写在 `public/locales/{en,zh-CN}/content.json`，商店版这条链路根本不存在，
照抄就是错误陈述。

**设置页需要一条新文案**，不要复用 `updateNotConfigured`——它的语义是"更新器配置
有问题"，而商店版是"更新由商店负责"，这是两回事，照搬会让用户以为应用坏了。新增
一个 key（如 `manageUpdatesInStore`），并按 [AGENTS.md](../AGENTS.md) 的要求补齐
全部 19 份语言文件。按同一份文案原则，措辞是陈述事实加一个去处，不是道歉。

### 决策 3：自启动改用 `windows.startupTask`

`tauri-plugin-autostart` 在 Windows 上写 `HKCU\...\Run` 键。MSIX 里这不是受支持的
自启动方式，而且真正的问题不是"不生效"——是它可能**生效得很糟**：Run 键指向
`WindowsApps` 下的 exe，绕过包标识直接拉起进程，于是托盘和通知的 AUMID 全部失效，
表现为"开机自启后通知不弹"，排查成本极高。

正确做法是在 manifest 里声明扩展：

```xml
<uap5:Extension Category="windows.startupTask" Executable="Off Work Countdown.exe" EntryPoint="Windows.FullTrustApplication">
  <uap5:StartupTask TaskId="OffWorkCountdownStartup" Enabled="false" DisplayName="Off Work Countdown" />
</uap5:Extension>
```

**这带来一处商店版与 GitHub 版的实质行为差异**：`Enabled="false"` 是初始状态，之后
的开关由系统接管——用户可以在"设置 → 应用 → 启动"里关掉，而应用无权强行改回来。
应用内那个自启动开关在商店版里需要改为读取真实状态并在被系统禁用时给出说明，不能
只当成一个自己说了算的布尔值。

实现上，Rust 侧用 `windows` crate 的 `StartupTask` API 读写，与 `tauri-plugin-autostart`
一样按 feature 二选一。

**已实现（2026-08-13）**，形状如下：

| | GitHub 渠道 | 商店渠道 |
|---|---|---|
| Cargo feature | `run-key-autostart`（在 `default` 里） | `--no-default-features` 关掉 |
| 实现 | `tauri-plugin-autostart` 的 **Rust** API | `windows::ApplicationModel::StartupTask` |
| `locked` | 恒为 `false` | 由 `StartupTaskState` 决定 |

三个当时不明显、但只能这么做的点：

1. **`run-key-autostart` 必须跟 `self-update` 一起放进 `default`，而不是单独一个
   `--features`。** 商店构建因此仍然只需要一个 `--no-default-features` 就切换全部
   渠道差异；多一个参数就多一次漏掉的机会，而漏掉的后果是一个"能装能跑、只有
   自启动悄悄失效"的包——正是这一轮实测到的那种。
2. **`autostart:default` 从 `capabilities/default.json` 里删掉了。** 插件被编译掉
   之后这条权限解析不了，会在 build script 阶段炸，与决策 2 的 updater capability
   是同一个坑。删得掉是因为前端不再直接调 JS 插件：两条渠道都走同一个 Rust 命令
   （`get_autostart_state` / `set_autostart_enabled`），差异全在 Rust 侧的 `#[cfg]`。
   顺带 `@tauri-apps/plugin-autostart` 这个 npm 依赖也不再需要。
3. **写命令返回的是写完之后的真实状态，不是入参的回声。** 被用户在系统设置里锁掉时
   `RequestEnableAsync` 不报错、只是不生效，把它当成"开成功了"就会又造出一个假开关。
   前端照返回值回填，并在 `locked` 时置灰开关加一句说明（`launchAtLoginManagedBySystem`，
   19 份语言文件已补齐）。

### 决策 4：打包用 winapp CLI，makeappx 作为退路

Tauri 不产 MSIX，`bundle.targets` 里没有这个选项，短期也不会有。选微软官方的
`winapp` CLI，理由是它有一份[官方 Tauri 指南](https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/guides/tauri)，
且原生支持多架构 bundle：

```bash
winapp pack ./dist/x64 ./dist/arm64 \
  --manifest src-tauri/msstore/Package.appxmanifest \
  --executable "Off Work Countdown.exe"
```

传多个目录直接产出 `.msixbundle`，每个切片的 `ProcessorArchitecture` 自动按 PE 头
识别并回填——正好对上仓库已有的 x64 + ARM64 矩阵。

`--executable` 必须显式传：产物名带空格，且自动探测只在目录里恰好有一个 exe 时才成立。

**⚠️ 产物名要靠 `mainBinaryName` 才对得上。** `bundle.active: false` 时 Tauri 不做
打包，也就不会把二进制改名成 `productName`——默认吐出来的是 Cargo 包名
`off-work-countdown`。因此 `tauri.msstore.conf.json` 显式设了
`"mainBinaryName": "Off Work Countdown"`，让商店版的可执行文件名与 NSIS 版一致，
manifest 里的 `Executable=` 也就不用为渠道分叉。

**提交商店的包不要签名。** `--cert` / `--generate-cert` 只用于本地 sideload 验收。

**⚠️ 已知风险**：winapp CLI 的文档前提写的是 Windows 11 + winget 安装，而
GitHub 的 `windows-latest` 是 Server 镜像。P2 本地跑通之后、P4 上 CI 之前必须单独
验证这一点。退路是直接调 Windows SDK 的 `makeappx.exe` 手写 `AppxManifest.xml`
——更啰嗦，但没有任何环境前提，SDK 在 runner 上一定存在。

不选社区的 `tauri-windows-bundle`：它能用，但商店提交这条链路上出问题时，官方工具
的错误信息和文档能对上，第三方封装会多一层猜测。

### 决策 5：版本号第四段恒为 0

MSIX 的 `Package/Identity/Version` 必须是四段，且**第四段保留给商店，必须写 0**。
产品版本 `3.1.3` 对应 `3.1.3.0`。

`scripts/check-version.mjs` 现在校验 `package.json` / lockfile / Cargo / tauri.conf
四处一致，需要扩一条：manifest 版本必须等于 `${产品版本}.0`。

还有一条商店特有的约束：**每次提交的版本必须严格递增**。这与现有的发版流程天然兼容
（版本号本来就单调递增），但意味着**一次提交被拒后不能改完用同一版本号重提**——必须
升版本。这一点要写进 [AGENTS.md](../AGENTS.md) 的发版规则，否则第一次被拒时必然踩到。

### 决策 6：不做迁移（前提已被实测推翻，结论不变）

> ⚠️ **本节的原始前提是错的。** 原文假设"MSIX 会把 `tauri-plugin-store` 的写入
> 重定向到包容器（`%LOCALAPPDATA%\Packages\<PFN>\...`），换渠道的用户会看到一份
> 空配置"。2026-08-13 的真机实测表明**文件写入根本没有被重定向**：商店版写的是
> 真实的 `%APPDATA%\com.rainif.offworkcountdown\desktop-state.json`，包容器下的
> `LocalState` / `LocalCache` / `RoamingState` 全空。被虚拟化的只有注册表。
> 详见「P2 验收结果」。

因此：

- **不做迁移**的结论**仍然成立**，但理由从"代价用文档承担"变成**根本不需要迁移**
  ——两个渠道读写同一份配置，换过去本来就是原样。
- 下载页**不能**写"配置不互通"，那是错的。真正值得提醒的是反面：两个渠道同时装着
  会**共用一份配置**，而 single-instance 只在同一个包标识内生效，所以两个实例可以
  同时开着、互相覆盖设置。这一条要不要写进下载页，属于 P5 的文案取舍。

原始前提之所以看起来可信，是因为 MSIX 的注册表虚拟化确实存在——决策 3 那个假开关
正是它造成的。文件和注册表在这里的行为不一样，不能从一个推另一个。

### 决策 7：三条 Windows 产线长期并存，各自独立

NSIS、MSI、MSIX 从同一个 tag、同一份源码产出，**互不替代**。商店版和 GitHub 版是
两个独立的应用标识，可以同时安装，**不做互斥检测**。

| | NSIS `-setup.exe` | MSI | MSIX |
|---|---|---|---|
| 分发 | GitHub Release | GitHub Release | Microsoft Store |
| 更新 | 应用内更新器 + 镜像回退 | 同左 | 商店（应用内入口深链过去） |
| 首装摩擦 | SmartScreen 警告 | SmartScreen 警告 | 无 |
| 自启动 | 注册表 Run 键 | 同左 | `windows.startupTask`，系统可接管 |
| 配置位置 | `%APPDATA%` | 同左 | **同左**——文件写入未被容器重定向，三者共用一份 |
| 上线时机 | 推 tag 即发布 | 同左 | 推 tag 后经认证，滞后数小时到数天 |

**MSIX 不放进 GitHub Release。** 商店外分发的 MSIX 需要自购证书签名，否则用户装不上
——那正是 §0 排除掉的前提。MSIX 只有商店这一个出口。

最后一行是必须接受的后果：**商店版永远滞后于 GitHub 版**。不要在下载页承诺两边同步。

## 3. 账号与商店侧准备（P0）

### 已拿到的身份（2026-08-13）

| 字段 | 值 |
|---|---|
| `Package/Identity/Name` | `finiaRStudio.OffWorkCountdown` |
| `Package/Identity/Publisher` | `CN=57D14FB1-9452-4F62-8C84-A50889A0FE89` |
| `PublisherDisplayName` | `fi_niaR Studio` |
| Package Family Name | `finiaRStudio.OffWorkCountdown_vzcbgpq3qw6zw` |
| Store ID | `9PM0HJ2PP2LJ` |

这些都不是机密——每个上架的 MSIX 包里都带着它们，任何人解包都能看到，所以直接进
仓库。真正需要保密的是 §4 那四个 secret。

Store ID 写在 `src-tauri/src/lib.rs` 的 `MICROSOFT_STORE_PRODUCT_ID`，前三个写在
`src-tauri/msstore/Package.appxmanifest`。两处同属一份不可分割的商店身份。

**深链在 P3 之前打不开**：商店对未发布的产品不提供 `pdp` 页面。这不是 bug。

### 还缺的

账号本身没有成本：个人和公司开发者账号现在都免费（公司注册费 2026 年 5 月取消，
个人账号 2025 年底起免费）。M5 §6 那张成本表里"Windows 代码签名 $200–400"这一项，
在商店这条路上是 0。

1. 商店 listing 素材：截图（至少 1 张）、描述、年龄分级问卷

**支持联系邮箱**：`offwork@rainif.com`。它写在 `config/site.ts` 的 `supportEmail`，
隐私政策页从那里读，**Partner Center 的 listing 必须填同一个地址**——两处对不上是
个查起来很烦的问题。

**隐私政策 URL 已就绪**：`https://off.rainif.com/en/privacy`（简体中文
`/zh-CN/privacy`）。写它的时候顺带查出两件 About 页没覆盖到的事实，现在都写明了：
站点确实会写一个 cookie（`i18nextLng`，只在你选过语言之后），以及商店版完全不发起
更新请求——这与 GitHub 版启动时检查新版本是不同的行为，一份不区分两者的隐私政策
在商店版上就是不准确的。

## 4. CI 自动发版（P4）

### 凭据链

这是整条链路最容易卡住的一步，四个环节缺一不可：

1. Partner Center 账号关联一个 Microsoft Entra ID 租户
2. 在 Entra 里注册应用，拿 Client ID + Client Secret
3. 回 Partner Center → 账户设置 → 用户管理 → Microsoft Entra 应用，把它加进来，
   **并授予 Manager 角色**（漏掉这步的表现是认证通过但接口 403）
4. 记下 Seller ID 和 Store product ID

### Secrets

| Secret | 来源 |
|---|---|
| `AZURE_AD_TENANT_ID` | Entra → 标识 → 概述 |
| `AZURE_AD_APPLICATION_CLIENT_ID` | Entra → 应用注册 |
| `AZURE_AD_APPLICATION_SECRET` | Entra → 证书和密码 |
| `SELLER_ID` | Partner Center → 账户设置 |

**⚠️ client secret 最长 24 个月。** 这是本仓库第一个会过期的 secret——
`TAURI_SIGNING_PRIVATE_KEY` 是永久的，所以现有流程里没有轮换意识。过期的表现是
某次发版商店提交突然失败而 GitHub Release 一切正常，如果不知道有这回事会查很久。
到期时间要记进 [AGENTS.md](../AGENTS.md) 的发版规则。

### 工作流形状

**[release-desktop.yml](../.github/workflows/release-desktop.yml) 一行不改。** 它继续
产出 macOS DMG、Windows NSIS 与 MSI、updater 签名、`latest.json` 与 `latest-cn.json`。
MSIX 是**新增的第三条产线**，跑在一份新的工作流里。

新建 `.github/workflows/release-msstore.yml`，与 `release-desktop.yml` 同样挂在
`desktop-v*` 上，但**保持独立**：

- 商店提交失败不应该让 GitHub Release 一起红，反之亦然
- 商店链路涉及会过期的凭据和外部审核，独立的工作流更好定位
- 它不传 `tagName`，因此不碰任何 Release——与 `build-desktop.yml` 刻意不碰 Release
  是同一个理由

代价是 Windows 的 Rust 会编译两遍（NSIS/MSI 一遍，MSIX 一遍）。这两遍的配置确实
不同（渠道开关、feature），合并反而要在一个 job 里切两次构建配置。公开仓库
Actions 不限量，多编译一遍换来两条产线完全解耦，值。

```
job build       matrix: windows-latest(x64) / windows-11-arm(arm64)
                tauri build --config src-tauri/tauri.msstore.conf.json \
                            -- --no-default-features
                upload-artifact: 仅 exe

job publish     needs: build, runs-on: windows-latest
                download-artifact → dist/x64, dist/arm64
                winapp pack → .msixbundle
                microsoft/microsoft-store-apppublisher@v1.1
                msstore reconfigure --tenantId … --sellerId … --clientId … --clientSecret …
                msstore publish ./*.msixbundle -id <StoreProductId>
```

`winapp pack` 需要两个架构的产物在同一台机器上，所以必须拆成两个 job 用 artifact
汇总——不能像 `release-desktop.yml` 那样让矩阵各自独立完成。

**⚠️ `--no-default-features` 前面那个 `--` 不能省。** Tauri v2 的 CLI 没有这个选项，
只有 `--features`；裸写会得到
`error: unexpected argument '--no-default-features' found`。`--` 之后的参数才会被
透传给 cargo。少一个横杠，构建出来的是一个**带完整自更新链路的商店包**——它能跑、
能过打包，装到用户机器上才会暴露。

### 两条限制

- **只支持免费应用。** 付费产品的 GitHub Actions 更新链路尚未开放。本应用免费，
  当前无影响，但这条限制值得记住——它会把"将来做个付费版"的选项和这条自动化流程
  绑在一起。
- **提交 ≠ 上线。** 推 tag 之后仍要过微软认证，几小时到几天。工作流跑绿只代表
  提交成功。

## 5. 平台差异与风险

### ⚠️ WebView2 无法随包分发

MSIX 塞不进 WebView2 bootstrapper，只能依赖系统自带的 Evergreen Runtime。
Windows 11 自带；Windows 10 上它随 Edge 分发，绝大多数机器有，但不是绝对。

处理方式：把 manifest 的 `TargetDeviceFamily/@MinVersion` 定在 `10.0.19041.0`
（Windows 10 2004）。定得低会让老机器装完打不开——**一个装上去白屏的应用比一个
装不上的应用差得多**，商店评分会直接反映这一点。

Tauri 官方文档在 EXE/MSI 那条路上建议改用 `webviewInstallMode: offlineInstaller`，
那是给 NSIS 包用的，MSIX 这条路上没有对应手段。

### 需要在真机上重新验收的功能

MSIX 的容器模型会影响一批平台相关行为，这些都**不能靠 macOS 上的开发验证代替**
（[AGENTS.md](../AGENTS.md) 已有类似告诫）：

| 功能 | 预期 | 实测（2026-08-13） |
|---|---|---|
| 通知 | ✅ 更好 | 🟡 平台层已验证：用包 AUMID（`<PFN>!App`）直接发一条 toast 能弹出、能进操作中心，Windows 随即登记了该 AUMID。⬜ 应用自身那条链路仍未端到端验证，原因见下 |
| 托盘图标 | ✅ 正常 | ✅ 已注册，`NotifyIconSettings` 里是包标识路径 |
| 托盘菜单的本地化文案 | ✅ 正常 | ⬜ 未验证 |
| 全局快捷键 | ✅ 正常 | ⬜ 未验证——设置项在，没做按键实测 |
| single-instance | ✅ 正常 | ✅ 连开两次只有一个进程 |
| Windows Mini Timer | ⚠️ 待验证 | ✅ **正常**，含记忆位置 |
| 自启动 | ⚠️ 行为变化 | ✅ 已改 `windows.startupTask` 并验证，见决策 3 |
| 配置读写 | — | ✅ 能读写，但**没有**被重定向到容器，见决策 6 |
| 日志写入 | ✅ 正常 | ➖ 不适用：release 包不注册 log 插件，压根不写日志 |

细节见上面的「P2 验收结果」。剩下三项未验证的都属于"要真的触发一次才算数"，
不阻塞 P3，但补测之前别在验收标准里勾掉。

WACK（Windows App Certification Kit）在本地先跑一遍，能提前发现大部分会导致认证
失败的 manifest 问题——本轮已跑，**PASS**。

### 应用显示名的多语言

NSIS 安装向导的 14 种语言（[PLAN-3.1.0.md §1.1](PLAN-3.1.0.md)）在 MSIX 里不适用
——MSIX 的显示名走 `resources.pri` 和 `ms-resource:` 引用。初期只做英文
`Off Work Countdown`，与决策 1 "商店版不新增前端差异"保持一致。若要补，属于独立的
一小块工作，不阻塞上架。

## 6. 里程碑

| 阶段 | 交付物 | 完成判据 |
|---|---|---|
| **P0** | Partner Center 账号、占名、标识三元组、隐私政策页 | ✅ 三元组已记录（§3）；`/en/privacy` 与 `/zh-CN/privacy` 已就绪 |
| **P1** | `msstore` 渠道 | ✅ 构建产物中不含更新器代码与权限；文案已按渠道分支<br>✅ 自启动已改 `windows.startupTask` 并在真机走通全流程<br>⬜「检查更新」能真正打开商店页（等 P3 上架） |
| **P2** | manifest + 本地打包 | ✅ manifest 与打包脚本就位<br>✅ 自签包已装机，WACK PASS；§5 表格除通知/快捷键/托盘菜单文案三项外均已验收 |
| **P3** | 首次上架 | 商店页面可搜到，可安装 |
| **P4** | 自动提交 | 推一个 `desktop-v*` tag，商店后台出现新的待认证提交 |
| **P5** | 文档 | 下载页给出两个渠道及其差异；README 中英双语同步 |

P1 有两条判据卡在后面的阶段上，这是刻意的：自启动要先在真机上看清 MSIX 里的实际
行为，深链要等产品真正上架才能点通。两者都属于「先写就是写一段无法验收的代码」，
与决策 2 里 `StoreContext` 排在 P3 之后同理。

## 7. 验收标准

1. ✅ 商店安装的版本**不含任何自行下载安装的代码路径**，「检查更新」跳转到商店详情页，
   且 About 页不再声称启动时检查版本
   —— 已验证：`cargo tree --no-default-features` 里没有 updater/process；启动 45 秒
   零套接字零 DNS。唯一残留是前端产物里还有一处 `invoke("install_update_via_mirror")`
   的调用点（`lib/desktop-state.ts` 的 `installDesktopUpdateViaMirror`，商店渠道下
   不可达），Rust 侧那个命令在商店构建里只剩一个返回 Err 的空壳。真正下载安装的
   代码两侧都没有了
2. ✅ 商店版开机自启可用，且用户在系统"启动"设置里关掉后应用内开关能反映真实状态
   —— 已验证，见决策 3 那张分步表
3. ✅ 商店版与 GitHub 版可同时安装，互不干扰
   —— 两个渠道的托盘条目同时存在；但**配置是共用的**（决策 6），"互不干扰"仅指
   安装与进程，不含设置
4. ⬜ x64 与 ARM64 各自从商店安装后功能一致（本轮只打了 x64）
5. ✅ `npm run check:version` 覆盖 manifest 版本
6. ⬜ 推一个 `desktop-v*` tag，**三种 Windows 产物全部产出**：GitHub Release 里仍有
   NSIS 与 MSI，商店后台出现新的待认证提交；两条工作流任一失败不影响另一条
7. ⬜ 下载页明确写出：商店版更新滞后；**两个渠道共用同一份配置**（原文写的
   "配置不互通"是错的，见决策 6）

## 8. 未决问题

### 待决

- **winapp CLI 能否在 GitHub 的 Windows Server runner 上跑通**（决策 4）。这是
  P4 唯一的技术不确定性，退路已备好，但要在动 CI 之前先验证，别在 workflow 里
  反复调试环境。
- **商店 listing 的截图从哪来。** 现有 `readme_image/` 是 README 用图，尺寸和
  内容未必符合商店要求，可能要重新截。
- **是否把商店徽章放到下载页。** 涉及决策 7 那张表要不要在页面上展开——写太细
  会变成让用户替产品做选择，写太粗又会让人踩到"更新怎么不同步"的坑。属于文案
  问题，P5 时按 [AGENTS.md](../AGENTS.md) 的文案原则定。
- **是否把商店版的更新入口从深链升级为 `StoreContext`**（决策 2）。它能让
  「检查更新 → 下载中 → 重启以更新」这套现有 UI 语义在商店版里完整保留，不用跳出
  应用。但只有 P3 上架后才能真正验证，届时再按实际体验决定值不值得。

### 已决（留档，避免重复讨论）

- **不走 EXE/MSI 提交**：需要自购代码签名证书，与 M5 §6 的决定冲突。见 §0。
- **M6 不做 macOS App Store**：它是独立的远期里程碑，不占用微软商店上架路径。见
  §1、§9。
- **不做配置迁移**：复杂度不匹配收益，用文档承担。见决策 6。
- **不做渠道互斥检测**：两个版本可以共存。见决策 7。
- **更新器用默认开启的 Cargo feature**：反过来会让本地开发静默丢失更新器。见决策 2。

## 9. 远期里程碑：macOS App Store

> 状态：远期候选，尚未排期。以下是 2026-08-14 对当前源码与 Apple 审核要求的差距审计，
> 不是对现有 GitHub macOS 版本的发布承诺。

### 9.1 渠道定位

macOS App Store 版与现有 GitHub 直发版**长期并存**。现有版本继续使用 GitHub Release、
应用内更新器和 ad-hoc 签名；商店版新增独立的 `macappstore` 渠道，使用相同源码，但在
构建期裁掉商店不允许的能力，并由 App Store 承担安装与更新。

不为商店版开长期分支，也不把它定义成第三个 `BUILD_TARGET`。沿用 M6 的正交渠道模型：

```text
BUILD_TARGET     = web | desktop
DESKTOP_CHANNEL  = github | msstore | macappstore
```

`macappstore` 必须是编译期渠道，不能只靠运行时隐藏按钮。更新器、私有 API 和
LaunchAgent 自启动等不合规代码及 capability 都不能进入最终商店二进制。

### 9.2 当前结论：不能直接提交

截至 2026-08-14，当前 macOS `.app` **不符合直接提交 Mac App Store 的条件**：

| 阻塞项 | 当前实现 | 商店版要求 |
|---|---|---|
| 私有 API / 透明 WebView | `macOSPrivateApi: true`、Cargo `macos-private-api`，浮动 WebView 使用透明窗口 | 移除私有 API；保留状态栏与悬浮窗能力，standard / woodfish 面板改用公开 AppKit API 原生实现 |
| App Sandbox | 没有商店沙盒 entitlements 与 provisioning profile | 开启 `com.apple.security.app-sandbox`，只申请实际需要的最小权限 |
| 应用内更新 | updater 从 GitHub 检查、下载并安装更新，另有镜像回退 | 商店包完全移除 updater/process 插件、权限、端点、镜像命令与对应 UI，由 App Store 更新 |
| 开机自启 | `tauri-plugin-autostart` 使用 `~/Library/LaunchAgents` | 改为公开的 `SMAppService`，由用户明确授权，并验证沙盒内状态同步 |
| 签名与上传 | Release workflow 在 macOS 使用 ad-hoc identity `-`，产出 `.dmg` / `.app` | 使用 Apple Distribution 签名应用、Mac Installer Distribution 签名 `.pkg`，通过 App Store Connect 上传 |
| 商店元数据 | 没有 `macappstore` 配置、category、商店 Info.plist 与隐私申报 | 补齐 bundle category、Team / App ID、加密声明、隐私、支持 URL、截图、年龄分级等资料 |
| 最低系统版本 | 原生 Objective-C 按 macOS 13 编译，Tauri bundle 未显式对齐 | 商店配置显式声明 macOS 13.0，避免包元数据承诺一个实际不能运行的更低版本 |

托盘、通知、原生 AppKit Mini Timer 和默认全局快捷键目前没有被判定为必然阻塞，但必须
放进沙盒真机验收。特别是快捷键注册、辅助功能权限和睡眠唤醒后的后台行为，不能只凭
非沙盒 GitHub 版的结果推断。

这里也修正 M6 初稿中的一个概念：Mac App Store 上架需要 Apple Developer Program
会员、商店分发证书、provisioning profile 和签名 `.pkg`；**不以 Developer ID + 单独
notarization 作为提交前置条件**。Developer ID 公证是商店外直接分发的链路，不能和
App Store Connect 提交流程混为一谈。

### 9.3 实施阶段

| 阶段 | 内容 | 完成标准 |
|---|---|---|
| **MAS-P0** | 技术可行性验证 | 本地 `macappstore` 渠道可构建；二进制不含私有 API、updater 与 LaunchAgent；启用最小沙盒后可正常启动 |
| **MAS-P1** | 沙盒功能适配 | 主窗口、状态栏、倒计时、通知、系统语言、外部链接、原生 standard / woodfish Mini Timer、全局快捷键与用户授权的登录项在真机通过 |
| **MAS-P2** | 分发产线 | 配置 Team ID、App ID、entitlements、profile 与商店专用 Info.plist；产出 Universal `.app` 和正确签名的 `.pkg` |
| **MAS-P3** | TestFlight 与审核材料 | App Store Connect 上传成功；隐私标签、支持/隐私 URL、截图、描述、年龄分级和审核备注完整 |
| **MAS-P4** | 首次人工审核 | TestFlight 冒烟通过，处理审核问题并完成首次上架；记录以后可重复执行的发布清单 |
| **MAS-P5** | 自动发布与渠道文档 | tag 可独立触发商店构建/上传；下载页与 About 页准确区分 GitHub 版和商店版的更新与能力差异 |

阶段顺序不能颠倒：先做 MAS-P0 / P1，确认核心常驻能力在 App Sandbox 中成立，再购买或
续费开发者会员并投入 listing 与自动化。技术验证失败时，GitHub 直发版不受影响。

### 9.4 关键实现决策

1. **保留状态栏与悬浮窗能力，standard / woodfish 面板改为原生 AppKit。**
   Mac App Store 不禁止状态栏图标、菜单、置顶悬浮面板或原生透明窗口；需要替换的是当前
   依赖 `macos-private-api` 的透明 WebView 实现，而不是这些产品能力。
   `src-tauri/native-mini/NativeMiniTimer.m` 的公开 AppKit 路径继续保留，并扩展或复用为
   standard / woodfish 的商店实现。改造后的商店版仍须支持：
   - 状态栏图标与菜单；
   - 从状态栏或应用入口显示 / 隐藏悬浮面板；
   - 悬浮窗置顶、倒计时与 standard / woodfish 两种皮肤；
   - 木鱼点击动画、本地计数，以及首次点击静音且不引入音频资源的既有规则；
   - 与主窗口共享倒计时快照和唯一的 `hideEarnings` 状态，不在原生面板里复制排班算法
     或维护独立的收入显隐状态。

   GitHub 版可继续使用现有 WebView 悬浮窗，商店版使用公开 AppKit API 的原生面板；两者
   可以有不同渲染实现，但对用户承诺的核心能力应一致。若原生重写未达到上述验收标准，
   MAS-P1 不算完成，不能用直接删除木鱼悬浮窗来绕过。
2. **更新能力按 Cargo feature 和前端模块替换双重裁剪。**
   复用 `msstore` 已验证的 `--no-default-features` 思路，但为 `macappstore` 建独立配置与
   自动化断言；不能让不可达的下载安装命令留在 Rust 二进制里。
3. **登录项使用 `SMAppService`，不直接写共享目录。**
   开关必须反映系统真实状态，用户在系统设置里关闭后，应用内不能继续显示为已开启。
4. **只申请最小 entitlements。**
   默认不申请用户文件、通讯录、定位、摄像头、麦克风等权限。网络权限仅按最终商店版
   实际保留的外部链接 / 用户主动分享方案评估；工资、班次和偏好继续只存本机。
5. **最低系统版本统一为 macOS 13。**
   `build.rs`、Tauri bundle 与 App Store Connect 元数据必须一致；若要下调，先证明所有
   原生符号与回退路径可在更低版本运行，而不是只改版本字符串。
6. **商店发布与 GitHub Release 解耦。**
   两条工作流可由同一个版本 tag 触发，但任何一条失败都不应阻断另一条产物；商店版
   不生成 GitHub updater artifact，也不读取 updater 私钥。

### 9.5 上架验收清单

- `npm run lint`、单元测试、Web build/check、Desktop export/check 全部通过
- `cargo fmt --check`、两组 feature 的 clippy/test 与 macOS release build 全部通过
- 对商店产物做依赖、字符串与 capability 审计，确认无 updater、镜像端点、私有 API、
  LaunchAgent 写入和调试开关
- `codesign --verify --deep --strict`、entitlements、provisioning profile、架构与最低系统
  版本检查通过，安装包由正确的商店分发身份签名
- 在受支持的最低 macOS 版本与当前 macOS 上各做一次沙盒真机冒烟；覆盖 light/dark、
  中英文长文案、休眠唤醒、跨日班次、通知、托盘、Mini Timer、快捷键和登录项
- App Store Connect / TestFlight 安装的包启动时不访问 GitHub 更新端点，更新入口不承诺
  应用内下载安装
- 隐私政策可从应用内和商店元数据访问；App Privacy 申报与实际网络、存储行为一致
- 审核备注解释菜单栏常驻、通知、全局快捷键和登录项的用户价值与触发方式，并提供可复现
  的测试步骤

### 9.6 进入排期的门槛

同时满足以下条件后，才把本节从“远期候选”升级为正式里程碑：

1. M6 首次上架完成，不再占用商店渠道基础设施的主要维护精力；
2. 确认愿意承担 Apple Developer Program 的持续费用和年度证书 / profile 维护；
3. MAS-P0 证明沙盒版的托盘、原生 Mini Timer、通知和倒计时后台语义可接受；
4. 接受商店版与 GitHub 版可能存在明确、可解释的功能差异。

参考：[Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)、
[App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)、
[Mac 软件分发打包](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)、
[Tauri App Store 指南](https://v2.tauri.app/distribute/app-store/)。
