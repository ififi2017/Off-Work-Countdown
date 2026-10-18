# 022 · 3.2.1 商店新素材：周期报告、请假规划与 iPhone Duo

日期：2026-10-06。状态：IN PROGRESS（入口与规格已核验，中英文 18 张首轮样张及标题 V3／搜索 V4 共 4 支 creative 视频样片已生成；母版审阅、API 扩展和上传待完成）。

用户要求：用已登录的浏览器确认 ASC 新增的标题图、搜索结果图与 Duo 独立截屏入口，核查公开 API 接入能力，并更新两个新功能的商业营销素材计划。随后用户授权开始制图，并提供新版 Apple 机框。此前 ASC 为只读查看；后续用户授权单图 API 试传已完成，见文末实测记录，未修改位置绑定、送审或发布。

## 1. 已核验的入口与规格

在 App `6802803318` 的 iOS 3.2.1「准备提交」页面，英语（美国）本地化下已看到：

- 「产品页面信息 → 标题和搜索结果」中的两个独立栏位，各为 0/1 个素材。
- 「App 预览和截屏 → iPhone Duo」，为 0/10 个截屏、0/3 个 App Preview。
- 侧栏新增「素材库」。本轮没有逐一检查其余 16 个本地化的素材库存，不能据此断言所有语言为空。

网页接受的图片尺寸与 Apple 帮助文档交叉核对如下（宽 × 高，像素）：

| 用途 | 尺寸 | 制作安排 |
| --- | --- | --- |
| 标题图，21:9 | 3840 × 1646 | 独立横幅构图 |
| 标题／搜索通用图，16:9 | 5244 × 2950 | 可复用的通用备选；不强制所有栏位共用同一构图 |
| 搜索结果图，3:2 | 最小 1920 × 1280，最大 3840 × 2560 | 以 3840 × 2560 制作 |
| Duo 外屏 | 1398 × 2034；横向 2034 × 1398 | 原生紧凑布局取景 |
| Duo 内屏 | 2007 × 2853；横向 2853 × 2007 | 展示真实宽屏／横向布局 |

标题与通用图使用 PNG；3:2 搜索图及设备截屏接受 JPEG/JPG/PNG。本项目统一输出无透明通道的 PNG。Duo 当前页面是同一个最多 10 张的栏位，不按内外屏各自 10 张安排。实际混排、预览裁切与展示映射在上传时继续验收。

Apple 文档说明新 creative assets 面向 iOS 27／iPadOS 27 及以上的 App Store；没有搜索结果素材时可回退到常规截屏／预览，所以仍需保留完整的常规商店图。用户随后授权试做新的 creative 视频：标题 21:9（3840 × 1646）、搜索 3:2（本轮采用 1920 × 1280），均为 5–30 秒、30 或 60 fps、MOV/M4V/MP4。两处持续循环；搜索始终静音，标题可由用户开启声音。16:9 通用素材当前仅列图片规格。此项不改变常规 App Preview／审核视频暂不制作的决定。

来源：[素材规格](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/)、[截屏规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)、[设计建议与官方模板](https://developer.apple.com/app-store/asset-best-practices/)、[素材库说明](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets/)。

## 2. API 接入判断

现有工具是本项目自写的 Node.js 客户端：`scripts/app-store-connect/api.mjs` 通过 ES256 JWT 调用 `https://api.appstoreconnect.apple.com`，同步器管理 App／版本本地化、`appScreenshotSets`、`appScreenshots`、App Preview 等资源。认证、重试和上传校验基础可以继续复用。

**2026-10-06 初次官方文档核查（下方 CLI 源码复核已补充可用实现）：**

- Apple 素材库帮助页明确提到通过 API 上传和提交，当前链接指向 `appstoreconnectapi/app-asset-library`；2026-10-06 再核查时，网页与 DocC JSON／Markdown 均返回 404。设计页的 API 链接仍指向 API 总览。
- 2026-10-06 再次从官方入口下载的 OpenAPI `info.version` 仍为 `4.5`，JSON 条目 ZIP 时间为 2026-09-22 13:13:36（未声明时区）。973 条路径、1407 个 schema 及完整字段／字符串均未出现 creative、assetLibrary、appAssetLibrary、searchResult、productPageHeader；未找到标题／搜索素材的上传与绑定定义。官方 API 目录也未列出新资源。证据与下载哈希见 [复核记录](../../app-store-connect/ios/3.2.1/asc-api-availability.json)。
- 该契约的 `ScreenshotDisplayType`／`PreviewType` 没有 Duo 类型。单独的 `ScreenshotDisplayType` 文档只说明它是字符串，没有补充 Duo 枚举。
- 项目的配置校验、JSON Schema 和同步器也没有标题／搜索图字段或 Duo 支持。

这证明当前工具与已获取的公开契约尚未覆盖新能力，**不等于证明 Apple 后端不支持**。未猜测资源路径或 Duo 枚举，也未进行新资源写入试探。

2026-10-06 根据用户提供的 [ASC CLI 5.12.0](https://github.com/rorkai/App-Store-Connect-CLI/releases/tag/5.12.0)，固定 commit `8f001fbda872eb5198948d9bd15ce921ee8348bd` 复核源码：它通过公开 API 域名和团队 Key／JWT 实现图片上传与标题／搜索位置绑定，不依赖浏览器 Cookie。作者设计记录报告测试 App 实测成功；本项目尚未实测这些请求。初次「等待公开契约」不再作为图片接入的前置阻塞。

- `GET /v1/apps/{id}/assetLibrary` 获取素材库，`GET /v1/appAssetLibraryRefData` 获取规格。
- `POST /v1/appAssetLibraryImages`：`fileName`、`fileSize`、`category: CREATIVE_ASSETS`，关联 `assetLibrary`；按返回的 `uploadOperations` 上传，随后 PATCH 同一图片 `uploaded: true`，轮询到 `PREPARE_FOR_SUBMISSION` 且 `imageAsset` 尺寸有效。此实现没有沿用旧截图的 checksum 提交／`COMPLETE` 完成态。
- `POST /v1/appAssetLibraryPlacements`：类型 `PRODUCT_PAGE_HEADER_ASSET` 或 `APP_STORE_SEARCH_RESULTS_ASSET`，组 `DEFAULT_PROFILE`，关联 `image` 与 `appStoreVersionLocalization`。分配不等于送审／发布。
- Duo 复用旧截屏／App Preview 上传链，分别补充 `APP_IPHONE_DUO`／`IPHONE_DUO`。作者实测证据为创建空 set 成功，不能等同完整媒体处理验收。
- **5.12.0 尚未实现 creative 视频上传／绑定或素材送审**；素材库视频仅有 list。Duo App Preview 支持不能替代本项目标题／搜索视频。

源码依据：[图片上传](https://github.com/rorkai/App-Store-Connect-CLI/blob/5.12.0/internal/asc/asset_library_upload.go)、[位置绑定](https://github.com/rorkai/App-Store-Connect-CLI/blob/5.12.0/internal/cli/localizations/placement_writes.go)、[命令范围](https://github.com/rorkai/App-Store-Connect-CLI/blob/5.12.0/internal/cli/assetlibrary/command.go)。本轮仅下载阅读源码，未执行第三方程序、读取凭据或上传资源。

接入步骤：以已复核实现为起点，用只读请求核对本 App 的素材规格、库存及分配关系；creative 视频和送审契约独立核验。确认后扩展配置和差异计划，复用现有凭据与上传机制，按新资源实际要求实现上传、处理状态轮询、关联和回读。素材库资源的删除与从某一展示位置移除必须分开，不能把旧的截屏替换策略直接套到共享素材上。默认仍只读，写入需要显式 `--apply`，上传不得顺带选构建、送审或发布。

图片与视频制作可以先推进；若制作完成时契约仍未补齐，可通过已经开放的 ASC 素材库一次选择多个文件上传，再分配到对应语言与展示位置，并通过浏览器操作减轻重复工作。API 自动化单独验收，不能把网页上传成功记成 API 支持完成。

来源：[API 总览及 OpenAPI 下载入口](https://developer.apple.com/app-store-connect/api/)、[4.5 发布说明](https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-5-release-notes)、[截图类型](https://developer.apple.com/documentation/appstoreconnectapi/screenshotdisplaytype)、[现有资产上传流程](https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect)。

## 3. 商业图片安排

### 3.1 常规 iPhone／iPad：从现有 8 张扩展到 10 张

基线是已经上传的 [3.2.0 素材](../../app-store-connect/ios/3.2.0/README.md)：17 个 ASC 本地化 × 两种设备 × 8 张，共 272 张。沿用品牌、官方机框、真实 UI 和现有构图工具，新增两个功能页。建议顺序：

1. 倒计时跨页开场 1。
2. 倒计时跨页开场 2。
3. 请假规划：月历中看清一段完整假期。
4. 周期报告：从这周、这月、这一年的工作与休息中得到可读结论。
5. 免费 Apple Watch。
6. 月历与节假日。
7. 记录年视图。
8. 专注。
9. 小组件。
10. 休息。

这是本轮制作建议，尚非已经验收的版式。保留前两张的连续构图，新功能进入前四张。常规 iPhone 沿用 1320 × 2868，iPad 沿用 2064 × 2752；旧图片只有在 UI 与新版本一致时才复用。

请假页使用 Plan 020 P3e 的最新月历与分组界面：公共节假日方案和普通休息日方案分开，展示真实选中的连休范围、请假天数和必要的估算提示。文案方向为「把假期，排得更完整」，不承诺所有排班都能“请 X 休 Y”。具体数字来自固定地区、日期、余额和排班的实际计算结果。三次免费体验与 Plus 权益说明按产品实际机制表达。

报告页从周／月／年动画报告中选择信息完整的关键帧，以工时、加班与休息的关系为主，文案方向为「这一周，时间去了哪里」。主图优先隐藏收入；需要收入场景时只用明确的演示数据，不采集用户真实薪资。不得宣传并未计算的“准点率”或将推算写成实际记录。报告是 Plus 功能，不能让画面暗示全部免费。

### 3.2 标题与搜索结果：分别承担品牌和功能表达

- 标题图：DoneAt 品牌、现有品牌 mark 和简洁的时间／日落视觉。中文沿用「几点下班，心里有数」，英文沿用 `Know when your time is yours`；避免把横幅塞成两个新功能的说明书。
- 搜索视频（2026-10-06 用户修订）：24 秒依次展示倒计时、小组件、专注、记录、周期报告、请假规划；以真实 UI、欢迎页式错峰入场和柔和转场建立完整 App 印象。标题 V2 已获用户确认，保持不变。
- 静态搜索图备选：让用户立即看懂「下班倒计时 + 请假规划 + 周期报告」。以一张主要的真实产品画面和少量辅助画面建立主次，保留手机搜索结果缩小后仍可辨认的数字和月历范围。
- 通用 16:9 图：作为两种展示位置的备选，必须分别验证裁切效果后才复用。不能仅把横幅拉高或截屏拉宽。
- 按 Apple 官方模板保留安全区域，在 ASC 预览里检查与系统 App 名称、图标和按钮的关系。文字短、当地化；不在图中放价格、折扣、网址或其他平台标志。

### 3.3 Duo：真实取景后再排版

先核实当前 SDK、模拟器及 shipping build 的 Duo 运行状态。此前 Duo 专属适配从 3.2.0 延后，ASC 开放上传入口不代表产品端适配已经通过。

外屏重点拍倒计时和紧凑版请假方案；内屏重点拍完整月历、方案选择、周期报告与记录布局。使用实际 App 的取景，不将普通 iPhone 图拉伸为 Duo，也不在宣传图中拼造尚不存在的双栏 UI。若没有合适的 Apple 官方机框，先用无机框构图，不自行绘制设备边框。

每个本地化最多安排 10 张 Duo 图片，先用简中／英文母版确定内外屏配比与顺序，再扩到其余语言；在 ASC 实际预览确认展示映射之前，不预先承诺每种屏幕各一整套。

### 3.4 本地化与产物记录

先做简中和英文完整样张，校验缩小阅读、裁切与 UI 来源后，再扩展至现有 17 个 ASC 本地化；不要把 App 的 19 语误当成 ASC 19 个独立栏位。商业文案按语言改写，实际 UI 必须使用对应语言，禁止用英／中截图充当其他语言正式素材。

每张图片记录 locale、用途、设备／屏幕、顺序、尺寸、原始截图、构建版本／源码提交、演示数据与哈希。延续 `creative-compose.mjs`、`creative-finalize.mjs`、`creative-validate.mjs` 的可复现流程，扩展其原来写死的 8 页和两种设备假设；保留 3.2.0 归档不覆盖。

## 4. 执行与验收

- [x] 浏览器核实标题图、搜索图与 Duo 独立栏位及当前英文空状态。
- [x] 对照 Apple 规格，读取公开 OpenAPI 4.5 和项目同步实现，记录接入缺口。
- [x] 把两个新功能、标题／搜索图和 Duo 纳入同一素材计划。
- [x] 核实本地 Debug 来源、Duo 运行环境及两个功能取景；记录演示数据（不等于发布构建或完整 Duo 验收）。
- [x] 制作简中／英文的两个新功能页、标题图、搜索图及 Duo 样张，共 18 张；详见 [制作记录](../../app-store-connect/ios/3.2.1/artwork-proofs.md)。
- [x] 用户 2026-10-06 接受 Duo 外屏请假方案未完整出现在首屏，中英文外屏请假截图按真实状态纳入素材；不再作为本轮制图阻塞。
- [x] 从 Apple 官方三个 PSD 的 Art Safe Area 图层读取参考边界；模板来源已归档。首轮搜索主体过小，已依据用户实际预览重排图片／视频 V2，并制作实际卡片尺寸对比；其他裁切仍待 ASC 验证。
- [x] 用户授权后试做中英文标题 8 秒／搜索 12 秒 creative 视频，使用品牌 SVG 动效与真实 UI 录屏；仅本地预览。
- [x] 依据用户实际标题预览重排中英文标题图片／视频 V2：放大品牌句与 mark，按截图比例裁切并检查导航按钮避让；最终 ASC 裁切仍待验证。
- [x] 用户确认标题 V2；搜索视频按新要求改为中英文 24 秒六段 App 导览 V3，补录真实界面并检查关键帧／转场，标题素材保留原值。
- [x] 根据用户反馈修正搜索 V4 转场：持续展示区、固定机框、屏幕遮罩切换和连续进度，去除淡空与重复缩放；沿用已有录屏。
- [x] 根据用户追加的三种设备 ASC 预览修正标题 V3：收紧垂直排版，解决本地 iPad 横屏裁切，同时检查手机导航与 Duo 播放键避让；实际上传验证仍待完成。
- [x] 制作 Duo 简中完整 10 张首版（6 张外屏 1398×2034、4 张内屏 2007×2853），保留连续开场并覆盖全部功能；完成尺寸／无透明校验及本地预览，待用户审阅。来源与哈希见 `app-store-connect/ios/3.2.1/duo-zh-full-manifest.json`，本套尚未上传。
- [x] 检查缩小显示、长文案、安全区、品牌、权益和实际 UI；母版已确认并扩展至 17 语。
- [x] 完成 17 个 ASC 本地化，检查图片格式、无透明、尺寸、顺序与来源清单。
- [x] 复核 ASC CLI 5.12.0 源码，记录图片上传／绑定与 Duo 枚举实现，区分未支持的 creative 视频和送审。
- [x] 完成本 App 素材库／规格／位置只读验证及单张英文标题图 API 上传处理回读。
- [x] 视频 API 预留／分片上传／提交与处理回读成功；34 支标题／搜索视频已被 ASC 接收，规格均匹配。
- [x] 完成 17 语标题／搜索视频位置写入和 ACTIVE 回读验证。
- [ ] 等待 Apple 完成全部视频封面和播放资源转码；最新处理状态见上传回读记录。
- [ ] 将新增资源的批量上传流程纳入正式 JSON 同步器。
- [ ] 在 ASC 预览验证标题／搜索裁切与 Duo 内外屏展示；上传后回读处理状态、顺序和哈希，保存不含凭据的记录。

完成素材上传不等于审核通过或版本发布。素材、产品端 Duo 适配、API 接入分别记录验收结果。

2026-10-06 用户授权试传后，使用本项目 Node JWT 客户端实测素材库、规格、媒体列表和中英位置读取成功；英文 V3 标题图 `en-header-21x9-v3.png` 已完成预留、分片上传、提交和处理回读，Apple 返回 `PREPARE_FOR_SUBMISSION`、3840×1646。图片 ID `3f400019-57a8-8a76-802b-a4bb90d97b72`。现有英文标题／搜索位置已占用，未修改绑定、送审或发布；creative 视频写入与位置写入仍未实测。记录见 `app-store-connect/ios/3.2.1/asc-creative-live-probe.json`。

2026-10-06 视频 API 实测：用户授权后，使用本项目 Node JWT 客户端试传 `zh-CN-search-video-v4.mp4`（1920×1280、30 fps、24 秒，文件 SHA-256 与成品清单一致）。`POST /v1/appAssetLibraryVideos` 使用 `fileName`、`fileSize`、`category: CREATIVE_ASSETS` 和 `assetLibrary` 关系成功预留；按 `uploadOperations` 上传后，PATCH 同一资源 `uploaded: true` 成功。回读资源 `09c00019-57a8-8a76-8102-66be9d91d8a2` 已为 `PREPARE_FOR_SUBMISSION`，匹配搜索视频 spec `a28b6440-2fe2-58f0-9da3-354cb54cab57`。最后检查时预览帧为 `PROCESSING`、`videoAsset` 尚无值，因此只确认上传／提交成功，尚未确认可播放。没有修改位置绑定、送审或发布。脱敏回执见 `app-store-connect/ios/3.2.1/asc-creative-video-live-probe.json`。

2026-10-06 Duo 简中完整套图修订：修正内屏遮罩圆角过大导致第 3、4 张机框内露底的问题，同步应用于第 6、7 张。截图原始内容与尺寸保持不变；重生成预览、哈希和下载包，已目检请假／报告四角衔接。

2026-10-06 按用户要求，将 Duo 前两张连续开场合成一张 2853×2007 横版，保留真实外屏机身与完整倒计时画面；整套改为 9 张（横版开场 + 8 张功能图），已同步预览、顺序、来源哈希与下载包。旧 10 张版本移入本地历史目录；仍未上传 ASC。

### 全语言制作（用户 2026-10-06 追加）

- [x] 按已确认最新版扩展全部 17 个 ASC 本地化：Duo 9 张、iPhone 10 张、标题 V3 与搜索 V4 每语各一支，共 323 张截图、34 支视频。
- [x] 每语核对语义换行、单词完整、字形、机身间距、原生取景状态与节假日排班；通过尺寸／透明度／帧率／时长／哈希校验，并生成顺序清单与分语言下载包。

制作来源、复现脚本与实际完成数见 [全语言制作记录](../../app-store-connect/ios/3.2.1/all-locales-production.md)。用户随后明确授权整套上传 ASC；上传范围为 iOS 3.2.1 草稿的 17 个语言、323 张 iPhone／Duo 截图及 34 支标题／搜索视频。上传不包含构建选择、审核提交或版本发布。

### 全语言上传验收（用户授权上传 ASC）

17 语的 323 张截图与 34 支视频已上传并绑定到 iOS 3.2.1 草稿。34 个截图集逐项回读数量、顺序、MD5、尺寸和 COMPLETE；34 支视频核对本地 SHA256 上传回执、资源名称／字节数和 spec；34 个标题／搜索位置均 ACTIVE。独立回读校验零错误。回读时 18/34 支视频封面和播放资源已完成，其余 16 支仍在 Apple 转码队列；上传和位置绑定全部成功。既有 17 语 iPad 与 Watch 截图集保持原顺序。未选择构建、送审或发布。记录见 `app-store-connect/ios/3.2.1/asc-all-locales-upload-receipt.json` 与 `asc-all-locales-upload-verification.json`。实际 ASC 多设备裁切的浏览器目检仍单独保留待办。

## 2026-10-08 · PR #307 元数据与视频齐全性复核

- [x] 核实 #307 已合并，按用户指定文件更新 iOS 20 语 description／whatsNew（40 字段）；本地源字段校验及 ASC 独立回读 80/80 通过。
- [x] 实时回读原 17 语标题／搜索视频，共 34 支，全部播放资源与封面完成；34 个绑定正确。全部本地文件的哈希、尺寸、帧率、时长通过。
- [x] 核对新增 en-GB／es-MX／mr-IN 的媒体覆盖，记录尚无单独标题／搜索视频绑定；未声明 20 语媒体齐全。
- [x] 2026-10-09 用户撤回审核并授权后补同步 zh-Hans／en-US 共用副标题；20 语 App Info 独立回读仅两项预期差异。见 `asc-subtitle-unlock-update.json`。

证据与范围见 [核验记录](../../app-store-connect/ios/3.2.1/asc-pr307-metadata-video-check.md)。本轮不改媒体、构建选择、审核与发布状态。

## 2026-10-08 · 追加三种语言的视频覆盖

- [x] 按用户授权给 en-GB 复用 en-US、给 es-MX 复用 es-ES 标题 V3／搜索 V4，各新增两条绑定，无重复上传。
- [x] 从录制时最新 main `e02f93b`（#309，含 #307）独立干净源码重新编译 3.2.1（build 2），重录马拉地语六段原生界面；旧包素材全部替换。保存提交号与构建／媒体哈希，恢复演示数据、关闭唯一模拟器。
- [x] 新制作马拉地语标题 8 秒／搜索 24 秒，天城文排版、关键帧和转场目检、文字边界、240／720 帧、无音轨、完整解码与 SHA-256 校验通过。
- [x] 上传两支新视频并绑定 mr-IN，六个新增位置 ACTIVE；独立回读全部 20 语共 40 个标题／搜索位置、36 支不同视频，80 个版本文本字段匹配，错误 0。
- [ ] 等待 Apple 生成马拉地语两支视频的播放资源；当前封面 COMPLETE、状态 PREPARE_FOR_SUBMISSION，原 34 支全部可播放。

证据与源包说明见 [追加语言制作与回读](../../app-store-connect/ios/3.2.1/additional-locales-media.md)。本轮只新增视频和语言位置，不改已有截图、构建选择、审核与发布状态。

## 2026-10-11 · 标题视频官方安全区修正

- [x] 根据用户真机裁切问题重新下载 Apple 官方标题 PSD，独立读取 Art Safe Area：3840×1646 画布中的 `(1097,493,1646,661)`，确认原 V3 超出该区域。
- [x] 改为官方安全区内统一排版，新增只处理标题的生成模式；制作 18 支标题 V4，覆盖 20 个 ASC 语言（en-GB／es-MX 继续复用），保留原文案、品牌 SVG 和指针动效。
- [x] 18 语目检、54 帧 DOM／独立像素安全区检查、每支完整解码／240 帧／30fps／8 秒／无音轨／SHA-256／动态 spec 验证通过。
- [x] 上传全部 18 支新标题，保存成品、模板、技术核验和替换映射；独立回读 516 个线上位置与原 18 支搜索视频哈希，保持一致。
- [x] 用户明确批准单独送审后，提交仅包含 18 支新标题视频的 iOS 素材审核；回读 WAITING_FOR_REVIEW，未提交 App 版本。
- [x] 用户反馈审核通过后，回读 18 支 APPROVED／可播放，通过 ASC 正式流程发布至已上架 3.2.1 的 20 语；20/20 标题 ACTIVE 且绑定正确，496 个其他素材位置及 18 个搜索视频哈希保持不变。
- [x] 在 Chrome ASC 设备预览中检查中英 iPhone、简中 iPad 横屏与英文 iPhone Duo，保存截图；核心文字及 mark 完整可见。
- [ ] 新版在用户真机 App Store 中的裁切效果确认（ASC 设备预览不能替代真机）。

根因、官方模板来源、产物和审核回读见 [安全区修正记录](../../app-store-connect/ios/3.2.1/header-safe-v4-update.md)。旧版局部截图裁切近似检查已被本次官方安全区验收取代；新版已发布到全部 20 个商店语言，独立回读见 `asc-header-safe-v4-publication.json`。

## 2026-10-11 · 搜索视频安全区复核

- [x] 用户追问后，重新下载 Apple 官方 Search results PSD；独立读取 16-bit Lr16 中 Art Safe Area，3840×2560 的 `(836,765,2168,1030)`，SHA 与原模板一致。
- [x] 核对现有 18 支搜索 V4 与已上传源文件哈希一致；共享排版的品牌锚点 `(140,115)` 超出折算到 1920×1280 的安全区 `(418,382.5,1084,515)`。检查源码及简中专注关键帧，标题左边、手机右侧及上下均超出安全区。此前只检查画布／截断／重叠，不能作为官方安全区验收。
- [ ] 搜索素材按其独立官方安全区重新排版、逐场景验证并制作新版。

证据：`search-safe-v4-template-check.json`、`search-safe-v4-audit.json`。此次为诊断，没有改动线上搜索视频。
