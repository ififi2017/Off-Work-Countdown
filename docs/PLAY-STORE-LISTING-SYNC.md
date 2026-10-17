# Google Play 商品详情同步

`scripts/play-store-listing-sync.mjs` 把 `com.rainif.doneat` 的 Google Play 商品详情
（标题、简短说明、完整说明）和图片从本地文件同步到 Play Console。默认行为是只读的差异
预览；只有 `--apply` 会写远端。脚本不会选择构建、不会改动测试轨道或正式版发布，也不会
更改默认语言、联系方式、分类或定价。

它使用 Google Play Developer API v3 的 edits 接口：

1. `edits.insert` 新建一个临时 edit。
2. 读取 `edits.listings.list` 和每个受管图片类型的 `edits.images.list`，与本地比较。
3. `--apply` 时：`edits.listings.patch`（新语言用 `update` 创建）→ 图片不一致的类型
   `edits.images.deleteall` 后按文件名顺序 `edits.images.upload` → `edits.validate` →
   `edits.commit`。
4. 提交后再开一个只读 edit 复核，然后丢弃它。

预览模式同样需要临时 edit 才能读取；结束时脚本会删除它，不会提交。

## 一次性准备服务账号

Android 发布工作流已经用服务账号上传 AAB（GitHub secret `PLAY_SERVICE_ACCOUNT_JSON`）。
同步商品详情还需要它在 Play Console 的「用户和权限」里对本应用拥有
**管理商品详情（Manage store presence）** 权限；只有发布权限时，写入会返回 HTTP 403。

本地运行时把同一份 JSON 密钥保存在仓库之外，并在当前终端设置路径：

```bash
export PLAY_SERVICE_ACCOUNT_KEY_PATH='/安全位置/play-service-account.json'
```

未设置时脚本会回退到 `GOOGLE_APPLICATION_CREDENTIALS`。密钥不要放进仓库。脚本用 Node
自带的 `crypto` 签发 RS256 JWT 换取一小时有效的访问令牌（scope
`androidpublisher`），不引入 Google SDK，也不会打印私钥或令牌；OAuth 失败时只报告 HTTP
状态码。

## 配置与图片

每个版本一个 JSON，例如 `play-store/3.2.2.json`，可以提交进 Git：

```json
{
  "schemaVersion": 1,
  "packageName": "com.rainif.doneat",
  "imageBaseDir": "play-store/images",
  "listings": {
    "en-US": {
      "title": "DoneAt: Work Shift Countdown",
      "shortDescription": "……",
      "fullDescription": "……"
    },
    "zh-CN": { "title": "DoneAt · 下班倒计时", "shortDescription": "……", "fullDescription": "……" }
  }
}
```

- `listings` 的键是 Play 语言代码（见下表）。字段可以只写一部分，只比较和写入已写的字段；
  Play 上尚不存在的语言必须三项都写。宣传视频等其他字段不受管理，`patch` 不会清掉它们。
- 字符上限按 Unicode 字符计（含空格和标点）：标题 30、简短说明 80、完整说明 4,000。
- 配置里没有的远端语言保持不变，并在预览中列为「Not in config」。脚本不会删除语言。
- 3.2.2 的 English 与简体中文取自 `docs/android/store-listing.md` 的「Play 3.2.2 final
  candidate copy」。其余 19 个 Play 语言由 `scripts/play-listing-adapt-3.2.2.mjs` 从已审阅的
  ASC 3.2.2 元数据改写：去掉 Apple Watch、iPhone Duo、iCloud 与 Apple EULA，换成 Android
  小组件与倒计时通知、Android 备份和 Google Play 订阅条款。ASC zh-Hant 分成 zh-TW 与 zh-HK
  （后者用应用的香港用词），es-MX 对应 es-419。改动后运行
  `node scripts/play-listing-adapt-3.2.2.mjs --write` 重写配置。

图片按语言放在 `<imageBaseDir>/<Play 语言>/` 下。`play-store/images/` 已被 Git 忽略，每次
发布时从生成的商店素材复制进来：

```text
play-store/images/en-US/
  phoneScreenshots/01-countdown.png …   # 2–8 张，按文件名（自然数字序）排序
  sevenInchScreenshots/…                # 可选，0–8 张
  tenInchScreenshots/…                  # 可选，0–8 张
  featureGraphic.png                    # 可选，1024×500，JPEG 或无 alpha 的 PNG
  icon.png                              # 可选，512×512 PNG，≤1 MB
```

只有本地存在的图片类型才受管理；缺少的文件夹或文件表示远端对应图片保持不变。本地检查会
核对格式、文件大小、尺寸（截图每边 320–3,840 px，长边不超过短边两倍）、数量和 alpha 通道。
远端比较使用 Play 返回的 SHA-256 与顺序；任一张不同就整组替换。

截图必须是运行中的真实 Android 应用，并使用合成的班次与薪资数据。3.2.2 的截图在 Pixel 上
用隔离的 Debug 安装拍摄，按 ASC iPhone 版式排版，流程见 `scripts/marketing-shots/android/README.md`；
来源说明见 `docs/android/store-listing.md`。

## App 语言与 Play 语言

| App 语言（`public/locales`） | Play 语言 |
|---|---|
| `ar` | `ar` |
| `de` | `de-DE` |
| `en` | `en-US` |
| `es` | `es-ES` |
| `fr` | `fr-FR` |
| `hi-IN` | `hi-IN` |
| `id` | `id` |
| `it` | `it-IT` |
| `ja` | `ja-JP` |
| `ko` | `ko-KR` |
| `mr-IN` | `mr-IN` |
| `pt` | `pt-BR` |
| `ru` | `ru-RU` |
| `th` | `th` |
| `tr` | `tr-TR` |
| `vi` | `vi` |
| `zh-CN` | `zh-CN` |
| `zh-HK` | `zh-HK` |
| `zh-TW` | `zh-TW` |

Android 应用另有 `en-GB` 与 `es-419` 两个地区变体（`locales_config.xml`），配置里也可以使用
这两个 Play 语言。其他 Play 语言会被拒绝。映射在脚本的 `APP_LOCALE_TO_PLAY` 中维护，测试会
检查它覆盖 `public/locales` 的全部 19 个语言。

## 推荐工作流

```bash
# 1. 纯本地检查：不需要凭据
npm run play:listing:check -- --config play-store/3.2.2.json

# 2. 读取 Play 并显示差异；临时 edit 会被丢弃，不写入
npm run play:listing:plan -- --config play-store/3.2.2.json

# 3. 确认预览后提交。交互式输入 "com.rainif.doneat" 才会继续
npm run play:listing:sync -- --config play-store/3.2.2.json
```

可选参数：

- `--text-only`：只比较和写入文字，忽略所有图片。
- `--changes-not-sent-for-review`：以 `changesNotSentForReview=true` 提交，之后在 Play Console
  的「发布概览」里手动送审。应用开启了托管发布，或 Play 提示变更需要单独送审时使用。
  未开启托管发布时 Play 会自动送审，`commit` 返回 HTTP 400「Changes are sent for review
  automatically」并拒绝该参数；edit 不会提交，远端保持原样（2026-10-17 实测）。
- `--yes`：跳过输入确认，仅用于已审阅过预览的非交互环境。

不带 `--changes-not-sent-for-review` 时，`edits.commit` 的效果与在 Console 保存并发送变更
一致：Play 会审核商品详情，通过后才出现在商店。脚本本身不会再额外送审或发布。

## 范围与失败处理

- 任何写入步骤失败时，未提交的 edit 会被删除，远端保持原样；修正后重新运行即可。
- `edits.validate` 或 `edits.commit` 返回的错误会原样显示 Google 的说明。
- 提交后复核仍有差异时脚本以失败退出，用 `play:listing:plan` 查看。Play 可能需要片刻处理
  新图片。
- 同一时间只运行一个同步：Play 提交一个 edit 时会使其他未提交的 edit 失效。
- 不管理：发布轨道、版本说明（由 `.github/workflows/release-android.yml` 上传）、默认语言、
  联系方式、隐私政策 URL、分类、内容分级、数据安全表单和价格。
