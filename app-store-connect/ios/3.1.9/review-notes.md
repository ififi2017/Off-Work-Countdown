# App Store Connect review copy — iOS 3.1.9

The App Store Connect version review note is one shared field. It is not localized by locale. Paste the English note below into the existing version-level review field. Keep the existing review contact fields unchanged. The Chinese text is a reference for the owner and is not a second App Store Connect field.

## English review note — copy from here

DoneAt 3.1.9 expands the native iPhone and iPad app beyond the shift countdown.

What to review:

- Records: records from today and the previous six days are free to view in Week and Month; older days stay locked inside those views. Export and delete also remain free. DoneAt Plus unlocks older records, the Year view and editing a past day.
- Life view: Plus uses optional life milestones and career salary periods to show past estimates, the current work stage and projected gross lifetime income.
- Focus: Plus lets the user plan tasks and run focus and break sessions. A session respects lunch and shift-end boundaries.
- iCloud: the user can choose private iCloud sync for schedules, records, salary, reminder preferences, appearance, language, Life profile and Focus data. Enabling sync is a Plus feature; sync that is already enabled continues after a subscription expires. Quick setup can restore iCloud records on a new device.
- The real-time countdown, today’s schedule and earnings estimate remain free.

How to reach the paid features:

1. Finish or skip onboarding. On the optional Plus introduction, tap See plans to open the paywall or Skip to continue with the free countdown.
2. Open Records. Week and Month show the free seven-day window. Tap an older locked day, Year, Life, Focus, editing a past day or Enable iCloud Sync to present the paywall. Continue viewing the list returns to the free window.
3. Open Settings → DoneAt Plus to restore or manage purchases. Restore purchases is available without Plus.

Products:

- Yearly subscription: 7-day introductory free trial for eligible new subscribers.
- Monthly subscription: no trial.
- Lifetime: one-time non-consumable with Family Sharing. Buying lifetime does not cancel an active subscription; the app warns first and keeps Manage subscription available until that subscription ends.

There is no DoneAt account or product sign-in. Please use a Sandbox Apple ID to test purchases.

Privacy: data stays on the device by default. When the user enables iCloud sync, the listed synced data is stored in that user’s private iCloud database. Notification authorization, biometric protection, Live Activity settings and the running timer stay on each device. Salary never appears in widgets, notifications, Live Activities, share links or analytics. A backup export is created only when the user selects Export; the user chooses where to save or share it in the system sheet. A full backup includes records, synced settings, salary and career history.

## 中文参考（不单独粘贴到 App Store Connect）

DoneAt 3.1.9 扩展了原生 iPhone 和 iPad 应用，不再只有下班倒计时。

审核内容：

- 记录：今天和之前 6 天的记录可在周、月视图中免费查看；更早日期在这些视图中仍会锁定。导出与删除也继续免费。DoneAt Plus 解锁更早记录、年视图和历史日期编辑。
- 人生视图：Plus 根据用户自愿填写的人生节点和职业薪资阶段，展示过去推算、当前工作阶段和预计税前终身收入。
- 专注：Plus 可安排任务并运行专注与休息计时；计时会遵守午休和下班边界。
- iCloud：用户可选择用私人 iCloud 同步排班、记录、薪资、提醒偏好、外观、语言、人生档案和专注数据。开启同步属于 Plus；已开启的同步在订阅到期后仍会继续。换新设备时可通过快速设置恢复 iCloud 记录。
- 实时倒计时、今日排班和收入估算继续免费。

进入付费功能：

1. 完成或跳过欢迎流程。在可选的 Plus 介绍页点按“查看方案”打开付费页，或点按“跳过”继续使用免费倒计时。
2. 打开“记录”。周、月视图会显示免费的 7 天窗口。点按更早的锁定日期、年视图、人生、专注、编辑历史日期或“开启 iCloud 同步”会打开付费页；“继续查看列表”会返回免费窗口。
3. 打开“设置”→“DoneAt Plus”恢复或管理购买；没有 Plus 也能使用“恢复购买”。

商品：年订为符合资格的新订阅者提供 7 天介绍期免费试用；月订无试用；终身版为支持家庭共享的一次性非消耗型购买。购买终身版不会自动取消正在生效的订阅，应用会先提醒，并在订阅结束前保留“管理订阅”入口。

DoneAt 没有产品账号或登录。请使用 Sandbox Apple ID 测试购买。

隐私：数据默认留在本机。用户打开 iCloud 同步后，上述同步数据会存入该用户的私人 iCloud 数据库。通知授权、生物识别保护、实时活动设置和正在运行的计时留在各台设备。薪资不会出现在小组件、通知、实时活动、分享链接或统计中。只有用户选择“导出”时才会创建备份导出；用户随后在系统分享面板中选择保存或分享位置。完整备份包含记录、同步设置、薪资和职业薪资历史。

## Media prepared by the repository

Listing screenshots and previews are declared in `app-store-connect/ios/3.1.9.json`:

- `en-US`: six `APP_IPHONE_67` screenshots, six `APP_IPAD_PRO_3GEN_129` screenshots and one existing `IPHONE_67` App Preview.
- `zh-Hans`: six Simplified Chinese iPhone screenshots, six Simplified Chinese iPad screenshots and one existing Chinese App Preview.
- `zh-Hant`: six independently composed Traditional Chinese iPhone screenshots and six Traditional Chinese iPad screenshots. Its configured App Preview reuses the existing Chinese video and was not remade for this screenshot set.
- Total new listing screenshots: 36 (six scenes × two devices × three locales).
- The other 14 App Store locales inherit the English media, following the repository release convention.

The IAP review screenshot is `app-store-connect/iap/review-paywall.png`. The same image is configured for the monthly, yearly and lifetime products through `app-store-connect/iap.json`. All three remote review screenshots are `COMPLETE` and match local MD5 `b459beea940f1c7ed3ccd5679a4b1e71`; the receipt is `iap-screenshot-sync.json`.

Each localized description ends with a localized Terms of Use label linked to Apple’s standard EULA and a localized Privacy Policy label linked to that locale’s existing metadata URL. This follows Apple’s subscription listing guidance: <https://developer.apple.com/app-store/subscriptions/>. The app paywall uses the same standard EULA URL.

The JSON metadata schema and sync script do not manage version-level App Review notes or contact fields. For this upload, the English note above was synchronized separately through the App Store Connect API and verified; all existing contact and demo-account fields were preserved. See `review-note-sync.json`.
