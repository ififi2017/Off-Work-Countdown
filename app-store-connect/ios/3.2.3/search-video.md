# iOS 3.2.3 · Search-results video (local, not uploaded)

ASC slot: Product page → Header and search results → search results asset
(`APP_STORE_SEARCH_RESULTS_ASSET`). Replaces the 3.2.2 video for 3.2.3, whose
headline feature is the widget suite. The storyboard was approved on
2026-10-19 (see `media-plan.md`).

## What changed from 3.2.2

- Nine beats of three seconds, cut in 0.3 s, 27 s in all: countdown → Home
  Screen widgets → shifts and week on the Home Screen → Lock Screen → Apple
  Watch → focus → records → cycle report → time off. The Life beat makes room.
- The widget beats use real widgets from a Home Screen recording. Two widgets
  sit side by side, cropped at their own continuous corners, and each arrives
  90 ms after the one before (`layout: 'row'`, `stagger` in
  `creative-search-3.2.3.mjs`). Two widgets per beat keep them legible at
  search-result size. A three-widget row was tried and read too small.
- The Lock Screen beat is the Lock Screen's own widget row (countdown, ring,
  week progress) and its two DoneAt controls (Start shift, time until
  clock-off) on the wallpaper. The recording ticks.
- Every other beat keeps its 3.2.2 layout and line, recaptured from the 3.2.3
  Debug build.

## Headlines

zh-CN and en were reviewed on 2026-10-19 (table below). For the other
locales, the Home Screen beat reuses each locale's reviewed 3.2.2 widget
line, and the shifts and Lock Screen lines are new for 3.2.3 and need
review. Every other beat keeps its reviewed 3.2.2 line.

| Beat | zh-CN | en |
|---|---|---|
| Countdown | 几点下班，一眼有数。 | Know when you’re done. |
| Home Screen | 不用打开，桌面就有数。 | Your day, on your Home Screen. |
| Shifts and week | 班表和本周，一眼看清。 | Your shifts. Your week. |
| Lock Screen | 锁屏一亮，还剩多久。 | Wake your screen. See what’s left. |
| Apple Watch | 抬腕，离下班更近。 | On your wrist. Closer to done. |
| Focus · Plus | 把这一段，留给专注。 | One thing. Your full focus. |
| Records | 时间去哪，都有迹可循。 | Your days. In perspective. |
| Cycle report · Plus | 忙过的日子，慢慢看清。 | Your month, in review. |
| Time off | 一点请假，多一点假期。 | A little leave. A longer break. |

The three widget beats in every locale:

| Locale | Home Screen | Shifts and week | Lock Screen |
|---|---|---|---|
| mr-IN | ॲप न उघडताही, किती वेळ उरला. | तुमच्या शिफ्ट्स. तुमचा आठवडा. | स्क्रीन सुरू करा, उरलेला वेळ पाहा. |
| zh-CN | 不用打开， 桌面就有数。 | 班表和本周， 一眼看清。 | 锁屏一亮， 还剩多久。 |
| zh-TW | 不打開， 也看得到。 | 班表和本週， 一眼看清。 | 螢幕一亮， 還剩多久。 |
| en | Your day, on your Home Screen. | Your shifts. Your week. | Wake your screen. See what’s left. |
| de | Auch ohne Öffnen der App. | Deine Schichten. Deine Woche. | Bildschirm an. Restzeit im Blick. |
| fr | Même sans ouvrir l’app. | Vos horaires. Votre semaine. | Un regard. Le temps restant. |
| es | Sin abrir la app. | Tus turnos. Tu semana. | Un vistazo. Lo que te falta. |
| it | Anche senza aprire l’app. | I tuoi turni. La tua settimana. | Un’occhiata. Ecco quanto manca. |
| pt | Sem abrir o app. | Seus turnos. Sua semana. | Acenda a tela. Veja quanto falta. |
| ja | 開かなくても、 あと何分。 | シフトも今週も、 ひと目で。 | 画面をつければ、 あと何分。 |
| ko | 앱을 열지 않아도, 한눈에. | 근무표와 이번 주, 한눈에. | 화면을 켜면, 남은 시간이 보여요. |
| ru | Без запуска приложения. | Ваши смены. Ваша неделя. | Один взгляд — сколько осталось. |
| tr | Uygulamayı açmadan da gör. | Vardiyaların. Haftan. | Ekranı aç, kalan süreyi gör. |
| id | Tanpa membuka aplikasi. | Shift-mu. Minggumu. | Nyalakan layar, lihat sisa waktu. |
| vi | Không cần mở ứng dụng. | Ca làm của bạn. Tuần của bạn. | Bật màn hình, biết còn bao lâu. |
| th | ไม่ต้องเปิดแอป ก็ดูได้ | กะงานของคุณ สัปดาห์นี้ในแวบเดียว | เปิดหน้าจอ ก็รู้ว่าเหลืออีกนาน |
| hi-IN | ऐप खोले बिना भी देखें। | आपकी शिफ़्टें। आपका हफ़्ता। | स्क्रीन जगाइए, बचा समय देखिए। |
| ar | دون فتح التطبيق. | مناوباتك. أسبوعك. | أضئ الشاشة، واعرف كم تبقّى. |

The es, it and ru Lock Screen lines were shortened once, so every locale
sets its headlines at or above the 64 px floor (68 px for CJK).

## Capture

- One Debug build of this branch (`/private/tmp/owc-323-creative-build`) on
  the iPhone 18 Pro Max simulator (3C9FDCBC…) and the Apple Watch Series 12
  46 mm simulator (BCE439EB…), one at a time.
- In-app beats: `creative-capture-search-3.2.3.mjs`, the 3.2.2 capture
  limited to timer, focus, records, report and leave, plus the Watch fixture.
  A Watch-only run (`IOS_SHOTS_SCENES=watch`) leaves the iPhone shut down.
- Widget beats were arranged by hand and captured with
  `creative-capture-widgets-3.2.3.mjs`:
  - The simulator was booted with `SIMCTL_CHILD_TZ` set to a zone where it
    was mid-afternoon (about 15:00) during a 09:00–17:00 demo shift. The
    status bar shows that real time; nothing is overridden.
  - Demo data: `regularSeed` + `calendarSeed` from `creative-seed-3.2.1.mjs`
    (localized day/rest shift names, the locale's working week) with no
    holiday region, so no localized holiday names differ between locales.
    DoneAt Plus is on (debug).
  - Home Screen page 1 (free): classic countdown (medium), ring, week
    progress, shifts (medium). Only page 1 is used. The
    layout was written to SpringBoard's `IconState.plist` while the simulator
    was shut down; the system language was switched for each locale.
  - Lock Screen: rectangular countdown, ring and week progress circulars,
    the weekend inline line, and the Start shift and time-until-clock-off
    controls.
  - `simctl recordVideo` writes no frames on the Home Screen, and the
    simulator draws Home Screen widgets once and then holds them, so both
    Home Screen beats are stills whose widgets arrive one by one. The Lock
    Screen clip is a screenshot sequence, each frame held until the next.
    The countdown ticks in the app, Lock Screen and Watch beats.
  - Per locale (`prep.sh` steps): seed the demo data without a holiday
    region, launch the app until it publishes widget payloads in that
    language, switch the system language, drop chronod's cached timelines
    and re-key the Home Screen widgets, reboot, launch the app, page to
    Today view and back so every widget redraws at the same moment, then
    capture. On the Lock Screen, opening Customize and tapping Done
    refreshes widgets that still show the previous language. The
    simulator is shut down between locales until the Mac's load is under
    30.
  - Arabic mirrors the Home Screen; the compositor mirrors the widget
    crops and their order.

## Reproduce

```sh
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath /private/tmp/owc-323-creative-build build
IOS_SHOTS_LANGUAGE=zh-CN,en IOS_SHOTS_SCENES=timer,focus,records,report,leave \
  node scripts/marketing-shots/ios/creative-capture-search-3.2.3.mjs
# iPhone shut down:
IOS_SHOTS_LANGUAGE=zh-CN,en IOS_SHOTS_SCENES=watch \
  node scripts/marketing-shots/ios/creative-capture-search-3.2.3.mjs
# Home/Lock Screen arranged as above, per locale:
node scripts/marketing-shots/ios/creative-capture-widgets-3.2.3.mjs zh-CN-home1 6
node scripts/marketing-shots/ios/creative-capture-widgets-3.2.3.mjs zh-CN-home2 4
node scripts/marketing-shots/ios/creative-capture-widgets-3.2.3.mjs zh-CN-lock 8
IOS_SHOTS_LANGUAGE=zh-CN,en node scripts/marketing-shots/ios/creative-search-3.2.3.mjs
node scripts/marketing-shots/ios/creative-audit-3.2.3.mjs
```

Raw captures and renders are ignored (`raw/3.2.3`, `out/creative-3.2.3`);
the manifests, audit and review sheets are copied into this folder.

## Poster fonts

The first render set new Chinese characters (就, 知, 道, 剩, 久 and others) in a
system fallback (PingFang SC) next to Noto Serif SC, because the poster fonts
are Google Fonts subsets of earlier copy. The Simplified Chinese serif and
sans subsets were refreshed with the 3.2.3 copy
(`creative-fonts-refresh.mjs`), and both renderers now fail on any text that
Chrome sets in a non-poster font (`assertPosterFonts`; families recorded as
`fontsUsed` in the manifests).

## Status (2026-10-19)

All 18 locales rendered locally; nothing uploaded, bound or submitted.
Every video is 1920×1280, 30 fps, 810 frames (27 s), H.264 yuv420p, no
audio. Every frame passed the safe-area, clipping and overlap audit.
Chrome reports only the licensed poster fonts, and
`creative-audit-3.2.3.mjs` has no findings (`audit.json`). Review sheets
with the Art Safe Area outlined: `search-review/<locale>-safe-area-sheet.jpg`.

| Locale | ASC | Headline px | Frames audited | SHA-256 |
|---|---|---|---|---|
| ar | ar-SA | 88 | 825 | `c1d94912c223` |
| de | de-DE | 64 | 825 | `92adbbf0eed1` |
| en | en-US | 69 | 825 | `278a8de03d8f` |
| es | es-ES | 66 | 825 | `ad66a9244af3` |
| fr | fr-FR | 68 | 825 | `72a5c90cc1b0` |
| hi-IN | hi | 72 | 825 | `9c884b992690` |
| id | id | 71 | 825 | `15c0cf53d004` |
| it | it | 69 | 825 | `63f81a305465` |
| ja | ja | 68 | 825 | `4e465e47f3df` |
| ko | ko | 73 | 825 | `65be56afabaa` |
| mr-IN | mr-IN | 79 | 825 | `63916bdae98e` |
| pt | pt-BR | 70 | 825 | `11002f906a54` |
| ru | ru | 64 | 825 | `b75caf06e1bb` |
| th | th | 68 | 825 | `bfbd0d13a828` |
| tr | tr | 65 | 825 | `74ccbefe8563` |
| vi | vi | 72 | 825 | `70c0884a8dbc` |
| zh-CN | zh-Hans | 93 | 825 | `db8d7bbdeb5d` |
| zh-TW | zh-Hant | 85 | 825 | `91ebeff96bf0` |

en serves en-US and en-GB, and es serves es-ES and es-MX, as in 3.2.2.
