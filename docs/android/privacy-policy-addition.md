# Draft Android additions to the official privacy policy

This is local source copy for the existing site policy. The 2026-10-04 verification additions have also been applied to the local `codex/android-privacy-policy` site draft, but **have not been published**. Before a Play listing uses `https://doneat.app/privacy`, edit these two site files, review the whole page for consistency, update its date, and publish the site through its normal review path:

- English: `/Users/zhengyuxuan/doneat-site/src/content/pages/en/privacy.md`
- Simplified Chinese: `/Users/zhengyuxuan/doneat-site/src/content/pages/zh-CN/privacy.md`

The root `/privacy` route chooses a supported language; it is the same URL already opened by Android Settings. The current pages name iPhone/iPad/Mac/Windows in the introduction and local-storage paragraph, and name only Apple/Microsoft in purchase/distribution sections. Update those sentences and the third-party list alongside the inserts below; do not leave two conflicting platform lists. The existing iCloud paragraphs stay specific to iPhone and iPad. Any final Data safety answers must be checked against the actual Play-installed artifact and the current Google SDK disclosures.

## English source copy

**Introduction and local data.** Add Android to the list of apps covered by the page. In “Data stored by DoneAt,” include Android application data in the sentence about local storage. The work schedule, salary, records, Focus tasks and preferences still stay on device by default; there is no DoneAt account or DoneAt server copy of this work data. Purchase verification is described separately below.

**Insert after “Optional iCloud sync”:**

### Android backup and device transfer

On Android, the app includes the records archive and device settings in Android's system backup and device-transfer rules. The archive can contain schedules, records, salary settings and history, life information and Focus plans. Device settings can contain an unfinished setup draft, including salary entered during setup. Whether a backup is created, where it is stored and how it is restored depend on your device, Google account and Android backup settings. DoneAt does not receive a copy on its own servers. The running timer, reminder registry, purchase proof and pending purchase acknowledgement are excluded from the app's backup rules and are rebuilt or checked again after a restore.

This release does not offer automatic Google Drive sync. Android and iPhone do not sync with each other automatically. You can move a RecordJSON file yourself; its contents may include salary and other personal information.

**Insert in “Backup exports”:**

On Android, export and import are actions you choose in Records & Data. An exported RecordJSON file is readable JSON and can contain your records, schedules, salary and Focus information. The system picker or share destination you choose handles the separate copy. Deleting information inside DoneAt does not delete files you previously exported elsewhere.

**Insert in “Plus purchases”:**

On Android, Google Play handles Plus subscriptions and lifetime purchases. DoneAt asks Play for currently owned purchases, checks Play's signature, and stores a signed purchase proof and acknowledgement retry information in app-private storage excluded from Android backup and device transfer. The proof includes a purchase token and product identifier; it does not contain your salary or work records. The app uses Play Billing again when it starts, resumes, restores purchases or retries acknowledgement. Google Play processes the payment and purchase information under its own policies. DoneAt does not receive payment card details. A restored data archive does not restore Plus access; the app checks Play again.

When server verification is enabled, the app also sends the Play purchase token, product identifier and a random request nonce over HTTPS to `api.doneat.app`, hosted on Cloudflare. The service uses Google Play's purchase API to verify entitlement and its exact expiration time, and returns a digitally signed receipt. Google sends purchase-state change notifications through Cloud Pub/Sub so the service can check the latest state again. This does not upload schedules, salary, work records, Focus plans or device backups.

The service stores a hash of the purchase token, product identifier, entitlement status and expiry, verification time, test-purchase flag, replacement-token hash and revision. Purchase rows are kept to support entitlement checks, restoration and replacement protection. Notification message IDs use a 30-day deduplication window; older entries are removed when later notifications are processed. Raw purchase tokens and Google response bodies are processed transiently and are not saved in DoneAt's database or application logs. A transient IP-based rate limit helps prevent abuse; DoneAt does not store IP addresses or those IP hashes in its database. Cloudflare and Google process network traffic under their own policies. The signed receipt stays in app-private storage excluded from Android backup.

These purchase identifiers are used for purchase verification and fraud prevention, not advertising or usage profiling. For questions about a server purchase record or a deletion request, use the contact address on this page. Uninstalling the app or deleting local work records does not automatically remove the server's purchase record or cancel the Play subscription.

**Update “Apps on your phone and computer” with an Android-specific paragraph:**

The Android app does not add a DoneAt usage analytics service. It accesses Google Play and, when enabled, the purchase-verification service described above when checking or buying Plus and when it asks Play to show an in-app review prompt after an eligible completed shift. The app does not receive a result telling it whether you submitted a review. If you submit one, Google Play handles the rating and text; a public review may be visible to the developer, and a closed-test review may be shared privately with the developer. Reminder alarms and notifications are scheduled on the device. Opening an external link or sharing through another app reaches that destination under its own policy.

**Update “Third-party services”:** add “Google — Google Play distribution, Plus payments and purchase status, in-app review, and Android system backup/device transfer when enabled in device settings.” Add “Cloudflare — hosting the Android purchase-verification service and its purchase-state database.” Google also provides purchase verification and Cloud Pub/Sub delivery. Do not describe Android backup as DoneAt's own Google Drive sync.

**Insert in “Deleting your data”:**

On Android, use Records & Data to export or delete records, and uninstall the app to remove its local app data. Files you exported elsewhere are separate copies. Android system backups may remain under your device or Google account backup settings after the app is uninstalled; manage those copies in the relevant system settings. DoneAt cannot access or delete those system backups for you. Removing local data does not cancel a Google Play subscription; manage or cancel it in Google Play.

## 简体中文源文案

**导语和本地数据。** 在页面所涵盖的平台以及“DoneAt 保存的数据”的本地存储句子中加入 Android。排班、薪资、记录、专注任务和偏好默认仍保存在设备上；没有 DoneAt 账号，DoneAt 自有服务器不保存这些工作数据的副本。购买验证单独说明如下。

**在“可选的 iCloud 同步”之后加入：**

### Android 系统备份与设备转移

在 Android 上，应用的系统备份和设备转移规则包含记录档案与本机设置。档案可能包含排班、记录、薪资设置及历史、人生信息和专注计划。本机设置还可能包含未完成的初始设置草稿，以及在设置时输入的薪资。是否创建备份、备份保存在何处，以及如何恢复，取决于你的设备、Google 账号和 Android 备份设置。DoneAt 自有服务器不会收到副本。正在运行的计时器、提醒登记、购买凭证和待确认购买标记不在应用的备份规则中；恢复后会重新建立或查询。

本版本没有自动 Google Drive 同步。Android 和 iPhone 之间也不会自动同步。你可以自行转移 RecordJSON 文件；其中可能包含薪资和其他个人信息。

**在“备份导出”中加入：**

在 Android 上，只有你在“记录与数据”中选择导入或导出时，才会处理 RecordJSON 文件。导出的 JSON 可以直接读取，可能包含记录、排班、薪资和专注信息。你选择的系统文件位置或分享目的地会保存另一份副本。在 DoneAt 中删除信息，不会删除此前导出到其他位置的文件。

**在“Plus 购买”中加入：**

在 Android 上，Plus 订阅和终身购买由 Google Play 处理。DoneAt 向 Play 查询当前持有的购买，校验 Play 签名，并在不参与 Android 备份或设备转移的应用私有存储中保存签名购买凭证和待确认购买的重试信息。凭证包含购买令牌和商品标识，不包含薪资或工作记录。应用启动、返回前台、恢复购买或重试确认时，会再次调用 Play Billing。付款和购买信息由 Google Play 依其政策处理。DoneAt 不会取得银行卡资料。恢复记录档案不会恢复 Plus 权益；应用会重新向 Play 查询。

启用服务端验证时，应用还会通过 HTTPS 向 Cloudflare 托管的 `api.doneat.app` 发送 Play 购买令牌、商品标识和随机请求标识。服务调用 Google Play 购买 API 核验权益与精确到期时刻，并返回数字签名凭据。Google 通过 Cloud Pub/Sub 发送购买状态变更通知，服务收到后重新查询最新状态。这一过程不上传排班、薪资、工作记录、专注计划或设备备份。

服务保存购买令牌的哈希、商品标识、权益状态与到期时刻、核验时间、测试购买标记、替换令牌哈希与修订号，用于权益检查、恢复和防止旧购买在套餐替换后重新生效。通知消息 ID 按 30 天窗口去重，在处理后续通知时清理过期记录。原始购买令牌与 Google 响应只在处理请求时使用，不写入 DoneAt 数据库或应用日志。服务临时使用 IP 限流以防滥用，不在 DoneAt 数据库保存 IP 或这些 IP 哈希；Cloudflare 和 Google 依其政策处理网络流量。签名凭据保存在不参与 Android 备份的应用私有存储中。

这些购买标识用于核验与防欺诈，不用于广告或使用行为画像。如需咨询或申请删除服务端购买记录，可通过本页联系地址联系开发者。卸载应用或删除本地工作记录，不会自动删除服务端购买记录，也不会取消 Play 订阅。

**在“手机和电脑上的应用”中加入 Android 段落：**

Android 应用没有加入 DoneAt 使用统计服务。应用会在检查或购买 Plus 时访问 Google Play，并在启用服务端验证时访问上文所述的验证服务；完成符合条件的班次后，也可能请求 Play 显示应用内评价提示。应用不会收到是否提交评价的结果。如果你提交评价，评分和文字由 Google Play 处理；公开评价可能由开发者看到，封闭测试中的评价也可能由 Play 私下提供给开发者。提醒闹钟和通知在设备上调度。打开外部链接或通过其他应用分享时，目的地依其自身政策处理信息。

**在“第三方服务”中加入：**“Google —— 通过 Google Play 分发应用、处理 Plus 付款与购买状态、应用内评价，以及在设备设置允许时提供 Android 系统备份与设备转移。”另加入“Cloudflare —— 托管 Android 购买验证服务及购买状态数据库”。Google 服务还包括购买核验与 Cloud Pub/Sub 通知传递。不要把 Android 系统备份写成 DoneAt 自有的 Google Drive 同步。

**在“删除你的数据”中加入：**

在 Android 上，你可以在“记录与数据”中导出或删除记录；卸载应用会移除设备上的本地应用数据。此前导出到其他位置的文件仍是独立副本。卸载后，Android 系统备份可能仍留在设备或 Google 账号的备份设置下；请在相应系统设置中管理。DoneAt 无法代你访问或删除这些系统备份。删除本地数据也不会取消 Google Play 订阅；订阅可在 Google Play 中管理或取消。

## 发布前一致性检查

2026-10-04 用户授权启用购买验证服务。上述文案须与实际上线构建及服务一致；不得继续声称购买状态从不发送给 DoneAt 服务端。Play Data safety 需按购买历史/购买标识的实际处理、服务提供方与保留方式核对，不能仅因只存哈希就声明无数据收集。官网 About 若有 Android 完全无联网的表述，应同步修正。该文件是待发布文案源，不代表官网已更新。
