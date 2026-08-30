# App Store Connect 元数据同步

`scripts/app-store-connect-sync.mjs` 把一个 iOS 新版本的商店文案和截图从本地 JSON
同步到 App Store Connect。默认行为是只读的差异预览；只有 `--apply` 会写远端，而且脚本
不会选择构建、不会提交审核，也不会发布版本。

它管理两类 Apple 资源：

- App 级本地化：名称、副标题、隐私政策 URL、隐私选择 URL。
- 版本级本地化：推广文本、描述、关键词、支持 URL、营销 URL、版本更新说明、截图和
  App Preview。

这个项目的 iOS 与 Mac App Store 使用同一个 Universal Purchase App 记录。名称、副标题和
隐私 URL 是共享的 App 级信息；改它们时要同时检查 macOS 商品页。任一端版本在审核时
App Info 会锁定，`asc:sync` 会跳过这些字段，不要为了换截图去碰名称。描述、关键词、
版本更新说明、截图和 Preview 跟随配置指定的 `IOS` 版本；可编辑的草稿仍可同步媒体。

## 一次性准备 API Key

在 App Store Connect 的「用户和访问 → 集成 → App Store Connect API」创建团队 API Key。
使用至少能编辑商店元数据的角色（通常为 App Manager），下载只提供一次的 `.p8` 私钥，
然后在当前终端设置：

```bash
export ASC_KEY_ID='你的 Key ID'
export ASC_ISSUER_ID='你的 Issuer ID'
export ASC_PRIVATE_KEY_PATH='/安全位置/AuthKey_XXXXXXXXXX.p8'
```

如果私钥沿用 Apple 工具常见的路径
`~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`，可以不设置
`ASC_PRIVATE_KEY_PATH`；脚本会根据 `ASC_KEY_ID` 自动找到它。

私钥不要放进仓库。仓库已忽略 `*.p8`、`*.pem` 和 `.env*.local`，但更推荐把 `.p8` 保存在
仓库之外。脚本用 ES256 在内存中签发最长 19 分钟的 JWT，不会打印私钥、JWT 或 Apple
返回的临时上传 URL。

## 为新版本准备配置

从示例复制一份版本文件：

```bash
mkdir -p app-store-connect/ios
cp app-store-connect/ios.example.json app-store-connect/ios/3.1.8.json
```

然后填写所有占位文本、法定版权名称和目标版本号。脚本会拒绝包含 `YOUR …`、
`WHAT'S NEW …` 或以「填写」开头的示例值，避免把脚手架文案传到线上。

配置可以提交进 Git：它不含凭据，并且能让商店文案跟代码一起评审。主要结构如下：

```json
{
  "schemaVersion": 1,
  "screenshotBaseDir": "scripts/marketing-shots/ios/out",
  "app": {
    "bundleId": "com.rainif.offworkcountdown.macappstore",
    "platform": "IOS",
    "versionString": "3.1.8",
    "createVersionIfMissing": true,
    "releaseType": "MANUAL",
    "copyright": "© 2026 法定版权名称",
    "usesIdfa": false
  },
  "localizations": {
    "zh-Hans": {
      "name": "DoneAt",
      "subtitle": "……",
      "description": "……",
      "keywords": "关键词一,关键词二",
      "supportUrl": "https://doneat.app/zh-CN/about",
      "whatsNew": "……",
      "screenshots": {
        "APP_IPHONE_67": ["zh-CN-iphone-01-timer.png"],
        "APP_IPAD_PRO_3GEN_129": ["zh-CN-ipad-01-timer.png"]
      },
      "previews": {
        "IPHONE_67": ["zh-review-886x1920.mov"]
      }
    }
  }
}
```

截图相对路径从仓库根目录下的 `screenshotBaseDir` 解析，也可以写绝对路径。JSON Schema 在
`app-store-connect/metadata.schema.json`，支持 Schema 的编辑器会直接显示字段提示。

新增 locale 时，至少填写：

- App Info：`name`。
- 版本信息：`description`、`keywords`、`supportUrl`。

脚本会同时创建 `appInfoLocalizations` 和 `appStoreVersionLocalizations`。它还会检查两边的
locale 集合是否一致；不一致时 Apple 会拒绝提交版本，所以脚本会提前停止。没有写进配置
的现有 locale 和字段会保留，不会被删除或清空。要清空可选字段，显式写 `null`。

## 推荐工作流

先生成并校验商店截图：

```bash
npm run shots:ios
```

只改过排版文案时，可以用较快的流程：

```bash
npm run shots:ios:compose
npm run shots:ios:validate
```

接着做三步同步：

```bash
# 1. 纯本地检查：不需要 API 凭据
npm run asc:check -- --config app-store-connect/ios/3.1.8.json

# 2. 读取远端并显示字段级差异；仍然不会写入
npm run asc:plan -- --config app-store-connect/ios/3.1.8.json --include-screenshots --include-previews

# 3. 确认预览后同步。交互式输入 "IOS 3.1.8" 才会继续
npm run asc:sync -- --config app-store-connect/ios/3.1.8.json --include-screenshots --include-previews
```

自动化或已经人工确认过输出时可以加 `--yes` 跳过交互确认。`--apply` 会在配置允许时创建
不存在的新版本，之后创建/更新各语言元数据，并在最后重新读取远端验证。它不会把版本送审。

## 截图同步的安全边界

Apple 的截图 API 是四步流程：预留资源、按服务端给出的 byte range 上传、提交整个文件的
MD5、轮询异步处理结果。脚本实现了完整流程，并在最后显式同步配置中的截图顺序。

- 不传 `--include-screenshots` 时完全不读取或修改远端截图。
- 远端文件名、MD5、顺序和处理状态都一致时跳过上传。
- 远端截图集为空时直接上传。
- 远端已有不同截图时，普通同步会在写入任何内容前停止。
- 确认确实要整组替换后，使用
  `--include-screenshots --replace-screenshots`。这会先删除对应 locale/display type 的旧截图集，
  再上传新集；脚本会在确认提示里标出这是破坏性步骤。

如果上传中途断网，新版本的截图集可能只完成了一部分。重新运行 `asc:plan` 检查状态，再用
`--replace-screenshots` 重建该组即可。脚本一次只上传一张，确保创建顺序稳定；每张最多等待
Apple 三分钟完成处理。

## 从已有版本导出

可以把线上版本的所有受管字段导出成同一套 JSON，再作为下一版本的起点：

```bash
npm run asc:export -- \
  --source-version 3.1.6 \
  --target-version 3.1.7 \
  --output app-store-connect/ios/3.1.7.json \
  --download-screenshots
```

导出只读取 App Store Connect。它会：

- 从 3.1.6 读取所有版本 locale，并合并对应的 App 名称、副标题与隐私 URL。
- 在 JSON 的 `exportedFrom` 中记录来源版本和时间，同时让 `app.versionString` 指向 3.1.7。
- 原样保留推广文本、描述、关键词、URL 和 `whatsNew`。
- 使用 `--download-screenshots` 时，将每个 locale/display type 的远端截图下载到
  `app-store-connect/screenshots/3.1.6/`，并把路径与顺序写回配置。这个下载目录已被 Git 忽略。
- 输出文件已存在时拒绝覆盖；确认后使用 `--force`。

因为 `whatsNew` 和版权年份也会按来源版本原样复制，面向下一版本导出后必须人工检查这两项。
不需要截图时去掉 `--download-screenshots`，导出的 JSON 就只包含文本元数据。

## App 语言与商店 locale

iOS App 内支持 19 个语言 locale。App Store Connect 对繁体中文只提供一个商品页 locale，
同时不接受马拉地语 `mr`（API 会返回 `locale` 无效），所以当前可发布 17 个商店本地化：

| App locale | App Store Connect locale |
| --- | --- |
| `en` | `en-US` |
| `zh-CN` | `zh-Hans` |
| `zh-HK`、`zh-TW` | `zh-Hant` |
| `de` | `de-DE` |
| `es` | `es-ES` |
| `fr` | `fr-FR` |
| `pt` | `pt-BR` |
| `ar` | `ar-SA` |
| `hi-IN` | `hi` |
| `mr-IN` | 不支持独立商店本地化；App 内仍保留马拉地语 |
| `id`、`it`、`ja`、`ko`、`ru`、`th`、`tr`、`vi` | 与 App locale 相同 |

`zh-Hant` 文案要同时照顾香港与台湾读者，避免只在其中一个地区成立的口语。Apple 还提供
英语、法语、西班牙语和葡萄牙语的其他地区变体；当前配置先与 App 的每种翻译一一对应，
以后只有在准备独立校对地区用语和关键词时，再增加 `en-GB`、`es-MX`、`fr-CA`、`pt-PT`
等变体。

## 送审必须人工完成

这个工具只管理版本草稿内容。源码中没有调用 `reviewSubmissions`、
`reviewSubmissionItems` 或旧的 `appStoreVersionSubmissions` 端点，因此 `asc:sync` 完成后
版本仍然留在 App Store Connect，必须人工完成当前的两步流程：

1. 选择正确的 build，点击 **Add for Review**，把当前 iOS 草稿（现为 3.1.8）加入审核提交。
2. 在 Draft Submission 中重新检查所有项目，再点击 **Submit for Review**。

Apple 明确说明第一步不会把内容送进审核队列，只有第二步才会真正送审。导出、plan 和 check
都是远端只读；sync 会写元数据和截图，但不会执行上述任一步。

当前成品尺寸 `1320×2868` 属于 6.9 英寸显示，但 App Store Connect API 仍把这个槽叫
`APP_IPHONE_67`（没有 `APP_IPHONE_69`）。`2064×2752` 的 iPad 成品使用
`APP_IPAD_PRO_3GEN_129`。App Preview 的对应枚举是 `IPHONE_67`，竖版必须是
`886×1920`，并且必须带音轨——无声片用静音立体声 AAC 即可，缺音轨会被拒。不要仅凭
设备营销名称改 API 枚举，尺寸与槽位要一起核对。

截图和 Preview 只写进 `en-US`、`zh-Hans`、`zh-Hant`。其余商店语言不要上传媒体，
让它们继承英文。17 个 locale 各传一套既慢又容易留下过期槽。

替换截图后，删掉该 locale 上不再使用的 display type（例如旧的 `APP_IPHONE_65`）。
Connect 控制台会优先展示闲置的旧槽，于是简体看起来还是旧图、繁体已经是新图。
脚本只同步配置里出现的槽，不会自动清掉配置外的远端集；发现错槽时用
`--replace-screenshots` 重建目标槽，并在 Connect 里删掉多余的那一组。

## 范围与失败处理

脚本有意不做这些事：

- 不上传 IPA、选择 build 或修改 build number。
- 不填写 App Review 联系人、审核备注、隐私标签、年龄分级或出口合规。
- 不提交审核、不自动发布，也不操作 TestFlight。
- 不删除配置中没有出现的语言或字段。

写入是否允许仍由 App Store Connect 状态决定。推广文本可以单独更新已发布版本；描述、
关键词、名称、副标题和截图通常要求目标版本处于可编辑状态。遇到 401/403 先检查 Key 的角色、
Issuer ID 和 App 访问权限；遇到 409/422 时，脚本会打印 Apple 返回的错误代码和字段路径。

Apple 官方参考：

- [App Info Localizations](https://developer.apple.com/documentation/appstoreconnectapi/app-info-localizations)
- [App Store Version Localizations](https://developer.apple.com/documentation/appstoreconnectapi/app-store-version-localizations)
- [Uploading Assets to App Store Connect](https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
