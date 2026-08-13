# M6 · 微软商店上架计划（MSIX）

在现有 NSIS 与 MSI 之外新增一条并行的 MSIX 产线，把 Windows 客户端送进
Microsoft Store，并让 `desktop-v*` tag 在发 GitHub Release 的同时自动向商店提交更新。
商店版的更新功能接入微软商店。

## 当前进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0** | Partner Center 账号、占名、拿到应用标识三元组 | ⬜ 未开始 |
| **P1** | `msstore` 构建渠道：更新入口改接商店、自启动改 startupTask | 🟡 更新入口已完成，自启动待做 |
| **P2** | `Package.appxmanifest` + 本地自签打包，真机验收 | ⬜ 未开始 |
| **P3** | 首次人工提交并上架 | ⬜ 未开始 |
| **P4** | Entra 凭据 + `release-msstore.yml` 自动提交 | ⬜ 未开始 |
| **P5** | 文档：下载页、README、About 页区分两个渠道 | ⬜ 未开始 |

P3 是硬性串行点：**商店提交 API 只能更新已上架的产品，创建不了产品**，所以
P4 无论如何排不到 P3 前面。

**P1 已完成的部分（2026-08-13）**：`DESKTOP_CHANNEL` 渠道维度、`self-update`
Cargo feature、内联 updater capability、商店深链命令与 19 份语言文案。
`npx tauri build --config src-tauri/tauri.msstore.conf.json -- --no-default-features`
在 macOS 上跑通，产物为不含更新器的 `Off Work Countdown` 可执行文件。

自启动（决策 3）留到 P2 与 manifest 一起做：`windows.startupTask` 要有真实的
`Package.appxmanifest` 才能验证，先写等于写一段无法验收的代码——与决策 2 里
`StoreContext` 排在 P3 之后是同一个理由。

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

- **不做 macOS App Store。** 它需要 $99/年的 Apple Developer 账号和真正的公证，
  与 M5 §6 的决定冲突，且沙盒对托盘 / 全局快捷键 / 原生 Mini Timer 的限制远比
  MSIX 严苛，不是同一量级的工作。
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

### 决策 6：设置数据不互通，且不做迁移

MSIX 会把 `tauri-plugin-store` 的写入重定向到包容器
（`%LOCALAPPDATA%\Packages\<PFN>\...`）。**从 GitHub 版换到商店版的用户会看到一份
空配置。**

技术上可以在首次启动时读旧路径做一次性导入（MSIX 的重定向是写时复制，旧文件仍可读），
但这条路要处理"两个版本同时装着、各自在改配置"的情况，复杂度不匹配收益——商店版是
新增入口，主要面向新用户，而不是让老用户搬家。

**决定：不做迁移。** 代价用文档承担：下载页需要明确写出两个渠道的配置不互通。这与
M5 §6 "文档是交付物的一部分"的处理方式一致。

若将来商店渠道的量级证明值得，再补迁移不会推翻任何现有结构。

### 决策 7：三条 Windows 产线长期并存，各自独立

NSIS、MSI、MSIX 从同一个 tag、同一份源码产出，**互不替代**。商店版和 GitHub 版是
两个独立的应用标识，可以同时安装，**不做互斥检测**。

| | NSIS `-setup.exe` | MSI | MSIX |
|---|---|---|---|
| 分发 | GitHub Release | GitHub Release | Microsoft Store |
| 更新 | 应用内更新器 + 镜像回退 | 同左 | 商店（应用内入口深链过去） |
| 首装摩擦 | SmartScreen 警告 | SmartScreen 警告 | 无 |
| 自启动 | 注册表 Run 键 | 同左 | `windows.startupTask`，系统可接管 |
| 配置位置 | `%APPDATA%` | 同左 | 包容器，与左侧不互通 |
| 上线时机 | 推 tag 即发布 | 同左 | 推 tag 后经认证，滞后数小时到数天 |

**MSIX 不放进 GitHub Release。** 商店外分发的 MSIX 需要自购证书签名，否则用户装不上
——那正是 §0 排除掉的前提。MSIX 只有商店这一个出口。

最后一行是必须接受的后果：**商店版永远滞后于 GitHub 版**。不要在下载页承诺两边同步。

## 3. 账号与商店侧准备（P0）

现在个人和公司开发者账号都免费——公司注册费在 2026 年 5 月取消，个人账号 2025 年
底起免费。M5 §6 那张成本表里"Windows 代码签名 $200–400"这一项，在商店这条路上是 0。

1. 注册 Partner Center 开发者账号
2. 保留应用名 `Off Work Countdown`
3. 记下应用标识三元组（产品 → 应用标识）：
   - `Package/Identity/Name`
   - `Publisher`（形如 `CN=<GUID>`）
   - `PackageFamilyName`

   **⚠️ 这三个值大小写敏感，空格和标点都要一致**，写错会在上传阶段才报错。
4. 商店 listing 素材：截图（至少 1 张）、描述、支持邮箱、年龄分级问卷
5. **隐私政策 URL** —— 仓库目前没有 `/privacy` 页面，About 页不构成正式隐私政策。
   需要先在 `off.rainif.com` 上补一页。内容本身不难写（本地优先、不上传薪资、匿名
   聚合埋点），[AGENTS.md](../AGENTS.md) 的隐私章节已经把事实说清楚了，照实写即可。

第 5 条不要留到最后——它是 listing 的必填项，卡在这里会让 P3 白等一轮。

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

| 功能 | 预期 | 备注 |
|---|---|---|
| 通知 | ✅ 更好 | 有真正的包标识，不再依赖 AUMID 变通 |
| 托盘图标与本地化菜单 | ✅ 正常 | |
| 全局快捷键 | ✅ 正常 | |
| single-instance | ✅ 正常 | |
| Windows Mini Timer | ⚠️ 待验证 | 程序化建窗 + 记忆位置，容器内需实测 |
| 自启动 | ⚠️ 行为变化 | 见决策 3 |
| 日志写入 | ✅ 正常 | 路径被重定向，不影响功能 |

WACK（Windows App Certification Kit）在本地先跑一遍，能提前发现大部分会导致认证
失败的 manifest 问题。

### 应用显示名的多语言

NSIS 安装向导的 14 种语言（[PLAN-3.1.0.md §1.1](PLAN-3.1.0.md)）在 MSIX 里不适用
——MSIX 的显示名走 `resources.pri` 和 `ms-resource:` 引用。初期只做英文
`Off Work Countdown`，与决策 1 "商店版不新增前端差异"保持一致。若要补，属于独立的
一小块工作，不阻塞上架。

## 6. 里程碑

| 阶段 | 交付物 | 完成判据 |
|---|---|---|
| **P0** | Partner Center 账号、占名、标识三元组、隐私政策页 | 三元组已记录；`off.rainif.com/privacy` 可访问 |
| **P1** | `msstore` 渠道 | `--no-default-features` 构建产物中不含更新器代码与权限；「检查更新」改为跳转商店且能实际打开；About / 设置页文案已按渠道分支 |
| **P2** | manifest + 本地打包 | 自签 `.msixbundle` 在 Windows 真机装上，§5 表格逐项验收通过；WACK 全绿 |
| **P3** | 首次上架 | 商店页面可搜到，可安装 |
| **P4** | 自动提交 | 推一个 `desktop-v*` tag，商店后台出现新的待认证提交 |
| **P5** | 文档 | 下载页给出两个渠道及其差异；README 中英双语同步 |

P1 和 P2 可以在 P0 之前动手——标识三元组只在打包时才需要，写代码不用等账号。唯一
的例外是深链里的 Store product ID，先留占位常量，P0 拿到后再填。

## 7. 验收标准

1. 商店安装的版本**不含任何自行下载安装的代码路径**，「检查更新」跳转到商店详情页，
   且 About 页不再声称启动时检查版本
2. 商店版开机自启可用，且用户在系统"启动"设置里关掉后应用内开关能反映真实状态
3. 商店版与 GitHub 版可同时安装，互不干扰
4. x64 与 ARM64 各自从商店安装后功能一致
5. `npm run check:version` 覆盖 manifest 版本
6. 推一个 `desktop-v*` tag，**三种 Windows 产物全部产出**：GitHub Release 里仍有
   NSIS 与 MSI，商店后台出现新的待认证提交；两条工作流任一失败不影响另一条
7. 下载页明确写出：商店版更新滞后、配置与 GitHub 版不互通

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
- **不做 macOS App Store**：需要 $99/年账号，且沙盒限制远超 MSIX。见 §1。
- **不做配置迁移**：复杂度不匹配收益，用文档承担。见决策 6。
- **不做渠道互斥检测**：两个版本可以共存。见决策 7。
- **更新器用默认开启的 Cargo feature**：反过来会让本地开发静默丢失更新器。见决策 2。
