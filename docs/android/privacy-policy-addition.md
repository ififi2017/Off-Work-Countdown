# Android privacy policy source wording

This file preserves source wording for the official website. Android privacy and
liquid-glass acknowledgements are published in all 19 website languages through
[website PR #30](https://github.com/ififi2017/doneat.app/pull/30). Current wording
lives in the website repository; do not republish this source as a new policy.
Publication and device-test evidence are recorded only in [progress.md](progress.md).

- [English privacy](https://doneat.app/en/privacy)
- [Simplified Chinese privacy](https://doneat.app/zh-CN/privacy)
- [Android liquid-glass acknowledgements](https://doneat.app/zh-CN/about#android-液态玻璃)

The root `/privacy` route is already opened by Android Settings. Play Data safety
answers still need to match the actual artifact and Google SDK disclosures;
publishing the website does not update the Console form.

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

2026-10-04 用户授权启用购买验证服务。上述文案须与实际上线构建及服务一致；不得继续声称购买状态从不发送给 DoneAt 服务端。Play Data safety 需按购买历史/购买标识的实际处理、服务提供方与保留方式核对，不能仅因只存哈希就声明无数据收集。官网 About 若有 Android 完全无联网的表述，应同步修正。本文件保留文案来源；后续修改以官网当前正文为准，发布与验收状态只记录在 progress.md。

## 2026-10-16 review-access supplement — implementation draft

The owner approved the R1 design and this disclosure scope on 2026-10-16. The
following copy describes the intended implementation, not evidence of deployment
or an already active service. Do not publish it or enable real review credentials
until retention, exit, revocation, backup exclusion and the final artifact have
been verified. Keep the website's English/Simplified Chinese About/Privacy copy
in sync. The other 17 existing privacy pages receive only a short localized notice
linking to this full supplement; this does not create new long-form translations.
No homepage, DNS or domain binding changes are authorized here.

### Website English copy

## Optional Android review access

In Android versions with review access enabled, an authorized reviewer can choose to enter a reusable review code to temporarily access Plus features. Activation and renewal use HTTPS to the existing `api.doneat.app` service on Cloudflare. This is separate from Google Play purchases: it requires no DoneAt account, Google sign-in, purchase or trial, and does not create or change an order or subscription. Ordinary use does not require review access.

For this optional authentication and abuse prevention, the service processes the review code, a random installation public key and its hash, proof of possession, a renewal secret and short-lived challenges. Its database stores the credential hash and status, installation public key and hash, renewal-secret hash, authorization revision, last issue/renewal time and revocation status (expiry follows the 24-hour lease), and challenge hashes and expiry times. A random or hashed identifier is still information collected by this service. These identifiers are not used for analytics or advertising and are not linked to Play orders. Review access does not collect Gmail, hardware identifiers, salary, schedules, work records, Focus content or backups. Raw codes, installation private keys, renewal secrets and signed authorization bodies are not stored in the service database or application logs. The private key stays in Android Keystore; local authorization material is excluded from backups and device transfer.

Each verified authorization lasts at most 24 hours. Activation and automatic renewal require a network connection. Revocation is applied when the app next checks online; a disconnected installation may retain the remaining authorized time, up to 24 hours. Expired challenges are rejected immediately, and a daily cleanup removes them and installation sessions whose last renewal was at least seven days ago. Reusable credential hashes remain until the owner rotates or revokes the credential; the seven-day installation cleanup does not itself invalidate the reusable code.

Choosing Exit review access clears local authorization immediately and attempts to delete that installation’s server session. If offline, the server session remains until cleanup. Reinstalling or returning after session cleanup requires activation again with a valid code. Exiting, expiry or revocation does not delete your local records or cancel a real Play purchase. For questions or server-record deletion requests, contact [hello@doneat.app](mailto:hello@doneat.app). Cloudflare processes network traffic under its own policies.

### 官网简体中文文案

## 可选的 Android 审核访问

在启用审核访问的 Android 版本中，获授权的审核人员可以自行输入可重复使用的审核码，临时访问 Plus 功能。激活和续期通过 HTTPS 访问 Cloudflare 上既有的 `api.doneat.app` 服务。这与 Google Play 购买分开：不需要 DoneAt 账号、Google 登录、购买或参加试用，也不会创建或更改订单、订阅。日常使用不需要开启审核访问。

为完成这项可选认证和防滥用，服务会处理审核码、随机生成的安装公钥及其哈希、私钥持有证明、续期密钥和短期挑战。数据库保存凭证哈希及状态、安装公钥及哈希、续期密钥哈希、授权修订号、最近签发／续期时间与撤销状态（到期时间按 24 小时租约确定），以及挑战哈希和期限。随机或经过哈希的标识仍是本服务收集的信息。这些标识不用于统计或广告，不关联 Play 订单。审核访问不收集 Gmail、硬件标识、薪资、排班、工作记录、专注内容或备份。原始审核码、安装私钥、续期密钥原文和签名授权正文不写入服务数据库或应用日志。私钥留在 Android Keystore；本机授权材料不进入备份或设备转移。

每次已验证授权最长有效 24 小时，激活和自动续期需要联网。撤销会在应用下次联网核对时生效；未联网的安装可能保留剩余授权时间，最长 24 小时。过期挑战会立即被拒绝，每日清理会删除过期挑战，以及距最后续期已满七天的安装会话。可重复使用的凭证哈希保留至所有者轮换或撤销凭证；七天安装清理本身不会让该审核码失效。

选择退出审核访问，会立即清除本机授权，并尝试删除该安装的服务端会话。离线退出时，服务端会话保留至清理。重装或会话清理后再次使用，需要用有效审核码重新激活。退出、到期或撤销不会删除本地记录，也不会取消真实 Play 购买。如需咨询或申请删除服务端记录，请联系 [hello@doneat.app](mailto:hello@doneat.app)。Cloudflare 依其政策处理网络流量。

### Play Data safety draft — not submitted

核对来源：[Google Play Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
（2026-10-16 查阅）。以下是本增量的填写建议，必须与最终 APK/AAB、服务和已有购买/SDK
申报一起核对，不覆盖既有表单，也不表示已经提交或已获 Google 认可。

| 新增处理 | 建议分类与填写 | 核对依据 |
| --- | --- | --- |
| 随机安装公钥/摘要、续期及挑战关联的安装标识 | Device or other IDs；Collected=Yes；Optional；非 ephemeral | 随机生成仍识别一个应用安装，服务端保留安装会话 |
| 审核凭证/挑战/授权元数据 | 与认证安装标识一起盘点，不另发明“无收集”豁免 | 输入凭证和证明会离开设备；仅哈希保存不免除披露 |
| 用途 | App functionality；Fraud prevention, security, and compliance | 仅可选审核认证、防重放与防滥用 |
| 共享 | 按 Cloudflare 实际服务提供方关系核对 service-provider exception | 不把服务托管自动等同广告共享，也不能跳过关系核实 |
| 加密与删除 | HTTPS 传输；退出尝试删安装；7 天清理；邮箱删除请求 | 需服务端清理、离线退出与最终客户端实测证据 |

一般计时无需开启审核访问；可选指用户能不提供这类信息而使用普通应用。
长效审核码摘要不是 Gmail/产品账号，也不关联 Play 订单；不要声明收集 Gmail、硬件 ID
或上传薪资/排班/记录。授权最长 24 小时不等于服务器只保留 24 小时：安装会话最后续期
7 天清理，凭证摘要保留至所有者轮换/撤销。只在内存使用的字段仍需逐项核对官方临时处理
定义，不能因随机、哈希、短效或不落日志而把整项填写为“不收集”。

发布前必须对照真实启用构建逐项确认字段、保留/清理时点、日志脱敏、TLS、删除入口和
Cloudflare 处理范围；公开政策、应用入口和 Console 答案一致后才允许正式审核访问启用。
这份草稿不批准生产部署、正式凭证签发、Console 提交、合并或发布。实际状态仅记 progress.md。
