# Android Play store listing draft

These are editable drafts for the first Android release. The app name, final package ID, distribution regions, prices and offers must be checked against the actual Play Console entry before use. Android screenshots must show the running Android app with synthetic work and salary data.

Google Play currently limits app names to 30 characters, short descriptions to 80, and full descriptions to 4,000 ([Play Console setup](https://support.google.com/googleplay/android-developer/answer/9859152)). Counts below are Unicode characters, including spaces and punctuation.

## English

Adapted from the English ASC 3.2.0 metadata in `app-store-connect/ios/3.2.0.json`. Android-specific surfaces, backup and billing replace the Apple-only features.

**Title (28):** DoneAt: Work Shift Countdown

**Short description (74):** Your shift countdown, schedule, widgets and estimated earnings at a glance

**Full description (2,358)**

How long until you clock out? How much have you earned today?
DoneAt puts your shift countdown, schedule and estimated earnings in one place. Spend less time doing the math and see where you are in your workday. The core countdown is free.

YOUR SCHEDULE, ON ANDROID
• Count down to work before your shift, see effective work time remaining during it, and keep the next shift in sight on days off.
• Set fixed weekdays, alternating weeks or work/rest rotations, including night shifts that cross midnight.
• Exclude your custom lunch break from working time.
• Start early, leave early, add overtime or time an unscheduled day without rebuilding your schedule.
• Optionally see estimated earnings for today, with weekly and yearly earnings summaries.
• Get shift, lunch and movement reminders.

YOUR DAY AT A GLANCE
Check your countdown with an Android home-screen widget or ongoing notification. Use layouts designed for phones and tablets. Share your countdown as an image or link. DoneAt supports 19 languages and follows your system language.

FREE FEATURES AND DONEAT PLUS
The core countdown is free. View records from the latest seven days in Week and Month views; older days remain locked in those views. Import, export and delete are also free.

DoneAt Plus unlocks:
• Older records, the Year view and editing past days.
• Life view: add life milestones and career salary periods to explore past estimates, your current work stage and projected gross lifetime income.
• Focus: plan tasks in focus and break blocks that respect lunch and shift-end boundaries.
• Optional cycle-end summaries to look back on your work.

Monthly and yearly subscriptions renew automatically until canceled. Eligible new subscribers can start the yearly plan with a 7-day free trial. Unless canceled before the trial ends, the yearly subscription begins at the price shown by Google Play. Lifetime access is a one-time purchase. Manage subscriptions in Google Play.

YOUR DATA, YOUR CHOICE
No DoneAt account is required. Data stays on your device by default. If Android backup or device transfer is enabled, your records and settings, including salary data, may be backed up or transferred by Android. You can also export and import your own backup files. Salary stays out of widgets, notifications, shared images and links.

Privacy Policy: https://doneat.app/en/privacy

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

- English feature graphic: `build/android-play-internal/store-listing/feature-graphic-en-1024x500.png`, generated by `scripts/marketing-shots/android/feature-graphic.mjs`. It uses the ASC cream background, Charter/Manrope typography, the “After work, time for you.” headline and a crop of the verified Android timer screenshot. The old purple SVG in `store-assets/feature-graphic-en.svg` is superseded. The PNG at the earlier `build/android-preconsole/store-assets/feature-graphic-en-1024x500.png` path is also replaced with this version.
- Preferred icon candidate: `build/android-preconsole/store-assets/icon-play-full-square-512.png`, rendered from the existing full-square brand SVG. It is 512 × 512, sRGB, 32-bit RGBA, opaque across the canvas, and about 26 KB. Google Play applies its own rounded mask and shadow, so this source leaves the edges square ([official icon specifications](https://developer.android.com/distribute/google-play/resources/icon-design-specifications)).
- Comparison only: `build/android-preconsole/store-assets/icon-existing-rounded-candidate.png` is an exact copy of `public/icon-512x512.png`. It has transparent rounded corners. Play recommends a full-square icon and warns against baking in rounded corners, so prefer the full-square candidate after visual review.

The icon uses the existing `sharp` package; the feature graphic uses the existing Chrome renderer and locally licensed ASC fonts. No asset or font was downloaded. The owner still needs to review the artwork beside the Android screenshots and confirm the final Console preview.

### Captured Android screenshot drafts

The following PNGs are under `build/android-preconsole/store-assets/`. They show the running API 36 Android app with synthetic data; no Pixel personal data was used. They are local screenshot candidates, not Play-installed purchase evidence. Paid feature demonstrations use the Debug-only access switch; the Plus offer page is omitted until real products are returned by Play.

| Files | Capture |
|---|---|
| `phone-en-welcome.png`, `phone-en-timer.png`, `phone-en-records.png`, `phone-en-life.png`, `phone-en-focus.png` | English phone, 1080 × 1920 |
| `phone-zh-records.png` | Simplified Chinese phone, 1080 × 1920 |
| `tablet-en-records.png`, `tablet-zh-records.png` | English / Simplified Chinese, 1920 × 1080 at 240 dpi; actual two-column tablet UI |

Choose the final screenshot order and captions after the signed Play candidate is available. The current Focus capture is an empty Today view, and the Timer capture shows the next shift on a rest day; a working-shift and populated-Focus capture would illustrate those features better for the final listing.

### English screenshots adapted from ASC 3.2.0

The current English set is `build/android-play-internal/store-listing/asc-style/screenshots/`, generated by `scripts/marketing-shots/android/compose.mjs`. It reuses ASC's cream background, Charter/Manrope typography, orange emphasis and opening two-image composition, with a neutral phone outline and new Android captures. Upload these six files in order:

1. `en-US-01-countdown.png`
2. `en-US-02-countdown-detail.png`
3. `en-US-03-calendar.png`
4. `en-US-04-records.png`
5. `en-US-05-focus.png`
6. `en-US-06-breaks.png`

All are 1080 × 1920, opaque RGB PNGs. The contact sheet (`overview.png`) is for review only. The originals are 1080 × 2400 captures of the current Android Debug build on an API 36.1 emulator, with synthetic schedules, records and tasks. Year and Focus scenes use the existing Debug-only Plus switch and are labeled as Plus features. No purchase screen or Apple-only feature is shown. The emulator was launched with `-read-only -no-snapshot-save`; its capture data is not saved to the original AVD.

The English copy files are `build/android-play-internal/store-listing/en-US-{title,short-description,full-description}.txt`. ASC source here means the repository's 3.2.0 metadata and uploaded screenshot templates, not a fresh remote metadata export. No ASC or Play Console writes are part of this preparation.
