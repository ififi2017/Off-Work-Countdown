# Android Play store listing draft

These are editable drafts for the first Android release. The app name, final package ID, distribution regions, prices and offers must be checked against the actual Play Console entry before use. Android screenshots must show the running Android app with synthetic work and salary data.

Google Play currently limits app names to 30 characters, short descriptions to 80, and full descriptions to 4,000 ([Play Console setup](https://support.google.com/googleplay/android-developer/answer/9859152)). Counts below are Unicode characters, including spaces and punctuation.

## English

**Title (6):** DoneAt

**Short description (66):** See time left in your shift, track work, and plan what comes next.

**Full description**

Know how much working time is left in this shift. DoneAt counts the time you actually plan to work, including breaks, and shows your progress and estimated earnings in one place.

Set up your usual hours or a changing schedule, then check the current shift, upcoming work and reminders. Keep a record of your days and use the home-screen widget for a quick, salary-free view. You can start without an account, a purchase or notification permission.

The free app includes the timer, schedules, earnings estimates, the most recent seven calendar days of records, and basic widget information. You can import, export or delete your own records without Plus.

DoneAt Plus unlocks longer-range records and charts, the Life view, record editing, Focus planning and optional cycle-end summaries. Choose a monthly or yearly subscription, or a one-time lifetime purchase. Google Play shows your local price and renewal terms before you pay, and handles subscription cancellation. A lifetime purchase does not cancel an active subscription.

Your schedule, salary and records stay on your device by default. If Android system backup or device transfer is enabled, the records archive and device settings, including an unfinished setup draft, can be copied and restored by that system. These files may contain salary. You can move a RecordJSON file yourself; automatic Google Drive sync and automatic iPhone-to-Android sync are not part of this release. Purchases are restored separately through Google Play.

Earnings and long-range figures are estimates for planning, not payroll calculations. Reminder timing depends on Android permissions and device settings.

## 简体中文

**标题（14）：** DoneAt · 下班倒计时

**简短说明（26）：** 看清本班剩余工作时间，记录每一天，安排接下来的工作。

**完整说明**

看清这一班还剩多少有效工作时间。DoneAt 会按你安排的工作时段和休息时间倒计时，同时显示进度和预计收入。

设置平时的工时或轮班安排，就能查看当前班次、接下来的工作与提醒。每天的记录留在应用中；桌面小组件可快速查看时间信息，不显示薪资。不用创建账号、购买 Plus 或授权通知，也能开始使用。

免费功能包括计时、排班、收入估算、最近七个自然日的记录，以及基础小组件信息。导入、导出和删除自己的记录也不需要 Plus。

DoneAt Plus 可查看更长时间范围的记录和图表，使用“人生”视图、编辑记录、安排专注任务，并选择开启周期结束总结。可选择月订阅、年订阅或一次性购买终身版。付款前，Google Play 会显示本地价格与续费条款；订阅取消也在 Google Play 中管理。购买终身版不会自动取消已有订阅。

班次、薪资和记录默认保存在设备上。启用 Android 系统备份或设备转移时，记录档案和本机设置（包括未完成的初始设置草稿）可由系统复制、恢复；这些文件可能包含薪资。你也可以自行导入或导出 RecordJSON 文件。本版本没有自动 Google Drive 同步，也不会自动在 iPhone 和 Android 之间同步。购买权益需另外通过 Google Play 恢复。

收入和长期数字用于规划参考，不是工资结算结果。提醒的实际送达时间受 Android 权限和设备设置影响。

## Verified contact fields

- Support email: `hello@doneat.app`, published on the [English About page](https://doneat.app/en/about) and [Chinese About page](https://doneat.app/zh-CN/about).
- Privacy policy: [https://doneat.app/privacy](https://doneat.app/privacy), the URL already used by the Android About screen and routed by the site according to language. The fixed pages are [English](https://doneat.app/en/privacy) and [Simplified Chinese](https://doneat.app/zh-CN/privacy).
- Website: [https://doneat.app](https://doneat.app), already used by the Android About screen.

No phone number, company address or unpublished support channel is supplied here. Play Console fields that require identity or tax facts need the account owner's real details.

## Store media brief

Capture the actual release-candidate Android UI with synthetic schedules and salary. A short phone set can show (1) the current-shift countdown, (2) schedule and break setup, (3) a recent free record, (4) the salary-free widget, and (5) the Plus screen **after** Play returns real localized products. Use only screens and prices observed on the Play-installed test build; omit the paid screenshot until that is possible. Keep the first images useful to free users. Check each caption against the capture before upload.

| Screen | English caption draft | 简体中文标题草稿 |
|---|---|---|
| Timer | See the work time left in this shift | 看清本班剩余工作时间 |
| Schedule | Plan hours and breaks your way | 安排工时与休息 |
| Records | Look back on recent days | 回看最近的工作日 |
| Widget | Check time from your home screen | 在桌面快速查看时间 |
| Plus | Go further with records and Focus | 用 Plus 查看更多记录与专注计划 |

Play's current artwork requirements call for a 512 × 512 PNG app icon (32-bit, at most 1,024 KB) and a 1,024 × 500 JPEG or 24-bit PNG feature graphic without alpha; screenshots must depict the actual app. Local candidates are listed below; the final rendered listing still needs inspection in Play Console before upload. [Official image requirements](https://support.google.com/googleplay/android-developer/answer/9866151), [store-listing guidance](https://support.google.com/googleplay/android-developer/answer/13393723).

### Local asset candidates for owner review

- Editable English feature graphic: [feature-graphic-en.svg](store-assets/feature-graphic-en.svg), 1024 × 500. It reuses the open-clock paths in `assets/brand/off-work-countdown-icon.svg` and the existing `landingTagline` (“Know when your time is yours”). The locally rendered 24-bit, opaque PNG is `build/android-preconsole/store-assets/feature-graphic-en-1024x500.png`. Review the artwork at small Play display sizes and approve any localized variant before upload.
- Preferred icon candidate: `build/android-preconsole/store-assets/icon-play-full-square-512.png`, rendered from the existing full-square brand SVG. It is 512 × 512, sRGB, 32-bit RGBA, opaque across the canvas, and about 26 KB. Google Play applies its own rounded mask and shadow, so this source leaves the edges square ([official icon specifications](https://developer.android.com/distribute/google-play/resources/icon-design-specifications)).
- Comparison only: `build/android-preconsole/store-assets/icon-existing-rounded-candidate.png` is an exact copy of `public/icon-512x512.png`. It has transparent rounded corners. Play recommends a full-square icon and warns against baking in rounded corners, so prefer the full-square candidate after visual review.

Both rendered PNGs use the repository's already-installed `sharp` package; no asset, font or image-generation service was downloaded. The owner still needs to review the artwork beside the Android screenshots and confirm the final Console preview.

### Captured Android screenshot drafts

The following PNGs are under `build/android-preconsole/store-assets/`. They show the running API 36 Android app with synthetic data; no Pixel personal data was used. They are local screenshot candidates, not Play-installed purchase evidence. Paid feature demonstrations use the Debug-only access switch; the Plus offer page is omitted until real products are returned by Play.

| Files | Capture |
|---|---|
| `phone-en-welcome.png`, `phone-en-timer.png`, `phone-en-records.png`, `phone-en-life.png`, `phone-en-focus.png` | English phone, 1080 × 1920 |
| `phone-zh-records.png` | Simplified Chinese phone, 1080 × 1920 |
| `tablet-en-records.png`, `tablet-zh-records.png` | English / Simplified Chinese, 1920 × 1080 at 240 dpi; actual two-column tablet UI |

Choose the final screenshot order and captions after the signed Play candidate is available. The current Focus capture is an empty Today view, and the Timer capture shows the next shift on a rest day; a working-shift and populated-Focus capture would illustrate those features better for the final listing.
