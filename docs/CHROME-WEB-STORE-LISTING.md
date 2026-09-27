# Chrome Web Store listing

The Chrome Web Store API cannot edit the listing, so this text is pasted into the
Developer Dashboard by hand. The dashboard shows descriptions as plain text: copy
the contents of each `text` block as-is, including the blank lines and `•` bullets.
Images come from `npm run shots:chrome-web-store`; see
[`scripts/marketing-shots/README.md`](../scripts/marketing-shots/README.md).

Every claim below must stay true of the popup: no permissions, no network requests,
no background work, data only in this browser's `localStorage`. Update this file
in the same change that alters any of them.

## Store listing

**Category:** Productivity → Workflow & Planning. **Language:** English is the
default listing; add Chinese (Simplified) as a localized listing.

The store title and the summary under it come from the package, not from the
dashboard: the manifest's `name` and `description` read `extensionName` and
`extensionSummary` from `src-extension/copy.json` in every locale. Titles follow
the iOS App Store names (`DoneAt - 下班倒计时`); `short_name` and the toolbar
tooltip stay `DoneAt`. The build rejects titles over 75 characters and summaries
over 132. The English and Chinese summaries are repeated below for review; edit
them in `copy.json`.

### English

**Summary**

```text
See how long until you clock off and what you've earned today, one click from your toolbar. Private, offline, no account.
```

**Description**

```text
Know exactly when your workday ends, without keeping a tab open.

DoneAt puts a calm countdown to clock-off in your Chrome toolbar. Click the icon and you can see at a glance how much of the day is left, how far through it you are and, if you like, what you have earned so far. It is made for anyone who has ever asked "how long until I can go home?" and wanted a straight answer.

WHY INSTALL IT

• One click from any tab
There is no website to open and no app to switch to. Whatever you are working on, the answer is one click away, and closing the popup takes you straight back.

• It fits the way you actually work
Set your start and end times and your workdays once. Lunch breaks pause the countdown, night shifts that run past midnight are counted correctly, and before your shift or on a day off, DoneAt counts down to the next one.

• Watch the day add up
Add a monthly or daily salary and see today's earnings grow second by second, along with estimates for this week and this year. One tap hides the amount when someone is looking over your shoulder.

• Private by design
Your hours, salary and preferences are saved only in this browser. There is no account to create, no analytics and nothing is sent anywhere. DoneAt asks for no permissions, so it cannot read the pages you visit.

• Light and quiet
Nothing runs in the background. DoneAt works everything out from the clock each time you open it, so it uses no memory or battery between glances, and it works offline.

• Make it yours
Choose Light, Dark, Sunset or Cyberpunk, or follow your system. Available in 19 languages.

GETTING STARTED

1. Open the Extensions menu (the puzzle icon) and pin DoneAt to your toolbar.
2. Set your start and end times and your workdays, then press Start Countdown.
3. Click the icon whenever you want to check. Lunch breaks and salary live in Settings.

WANT IT OUTSIDE THE BROWSER TOO?

DoneAt is also available for Mac and Windows, where the time left stays in your menu bar or system tray, and for iPhone and iPad, with Home Screen widgets and support for rotating shifts. The Get the app button in Settings takes you to doneat.app.

DoneAt is open source, so you can read exactly what it does on GitHub.
```

### 简体中文

**简介**

```text
点一下工具栏，就知道还有多久下班、今天挣了多少。数据只存在你的浏览器里，离线可用，无需注册。
```

**详细说明**

```text
几点下班，心里有数，不用一直开着网页。

DoneAt 把下班倒计时放进 Chrome 工具栏。点一下图标，就能看到今天还剩多少时间、已经完成了多少，想看的话，还能看到今天已经挣了多少钱。每一个在工位上想过「还有多久能走」的人，都可以用它得到一个清清楚楚的答案。

为什么值得装

• 在任何标签页，点一下就能看
不用打开网站，也不用切换应用。无论手上在忙什么，答案都只差一次点击；关掉弹窗就回到原来的页面。

• 贴合你真实的上班方式
上下班时间和工作日只需设置一次。午休时倒计时自动暂停，跨过午夜的夜班也算得对；还没上班或者休息日，会自动倒数到下一个班次。

• 看着今天一点点攒起来
填上月薪或日薪，就能看到今日已赚按秒增长，还有本周和今年的估算。有人从身后路过时，点一下就能把金额藏起来。

• 隐私放在第一位
作息、薪资和偏好只存在这台浏览器里。不用注册账号，没有统计上报，也不会把任何数据发送出去。DoneAt 不申请任何权限，所以读不到你浏览的网页。

• 轻巧安静
不在后台运行。每次打开时根据当前时间算好一切，没打开的时候不占内存、不耗电，断网也能用。

• 换成你喜欢的样子
浅色、深色、日落、赛博朋克四种主题，也可以跟随系统；支持 19 种语言。

三步开始

1. 打开扩展程序菜单（拼图图标），把 DoneAt 固定到工具栏。
2. 设置上下班时间和工作日，点「开始倒计时」。
3. 想看的时候点一下图标就好。午休和薪资在设置里调整。

想在浏览器之外也能看到？

DoneAt 也有 Mac 和 Windows 版，剩余时间常驻菜单栏或系统托盘；还有 iPhone 和 iPad 版，桌面小组件抬眼就能看，轮班、倒班也能排好。设置里的「获取 App」会带你去 doneat.app。

DoneAt 是开源软件，它做了什么、没做什么，都可以在 GitHub 上看得清清楚楚。
```

## Privacy practices

The dashboard's privacy tab is answered in English.

**Single purpose**

```text
DoneAt shows a countdown to the end of the user's workday in the toolbar popup, with optional estimates of the day's earnings. Everything is calculated locally from the schedule the user enters.
```

**Permission justification:** none. The manifest requests no permissions, host
permissions, content scripts or background worker.

**Remote code:** No, I am not using remote code. All scripts, styles, fonts and
translations are packaged; the CSP limits scripts to the extension itself.

**Data usage:** tick none of the data categories. Schedule, salary and
preferences are kept in the extension's own `localStorage` and never leave the
device; uninstalling removes them. Then certify the three statements (no sale to
third parties, no use unrelated to the single purpose, no use for credit or
lending).

**Privacy policy URL:** `https://doneat.app/en/privacy`. Before the first
submission, confirm that page covers the Chrome extension: it should say the
extension stores data only in the browser and makes no network requests.
