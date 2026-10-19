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

✎ written for 3.2.3 (needs review); the rest is reviewed 3.2.2 copy.

| Beat | zh-CN | en |
|---|---|---|
| Countdown | 几点下班，一眼有数。 | Know when you’re done. |
| Home Screen ✎ | 不用打开，桌面就有数。 | Your day, on your Home Screen. |
| Shifts and week ✎ | 班表和本周，一眼看清。 | Your shifts. Your week. |
| Lock Screen ✎ | 锁屏一亮，还剩多久。 | Wake your screen. See what’s left. |
| Apple Watch | 抬腕，离下班更近。 | On your wrist. Closer to done. |
| Focus · Plus | 把这一段，留给专注。 | One thing. Your full focus. |
| Records | 时间去哪，都有迹可循。 | Your days. In perspective. |
| Cycle report · Plus | 忙过的日子，慢慢看清。 | Your month, in review. |
| Time off | 一点请假，多一点假期。 | A little leave. A longer break. |

The shifts beat replaced the approved “班表和假期，都在桌面上。/ Your shifts
and holidays, right there.” Once the beats became two widgets each, shifts
and holidays no longer fitted one beat legibly. The holiday widget with its
leave plan stays on screenshot page 3's Home Screen (second page) and in the
closing time-off beat.

Headline sizes: zh-CN 93 px, en 69 px (floor 64 px for Latin script). The
longest en line is the Lock Screen one; a shorter line would raise every en
headline toward the 3.2.2 size (78 px).

## Capture

- One Debug build of this branch (`/private/tmp/owc-323-creative-build`) on
  the iPhone 18 Pro Max simulator (3C9FDCBC…) and the Apple Watch Series 12
  46 mm simulator (BCE439EB…), one at a time.
- In-app beats: `creative-capture-search-3.2.3.mjs`, the 3.2.2 capture
  limited to timer, focus, records, report and leave, plus the Watch fixture.
  A Watch-only run (`IOS_SHOTS_SCENES=watch`) leaves the iPhone shut down.
- Widget beats were arranged by hand and captured with
  `creative-capture-widgets-3.2.3.mjs`:
  - The simulator was booted with `SIMCTL_CHILD_TZ=Etc/GMT-13` so it was
    mid-afternoon there (about 15:00) during a 09:00–17:00 demo shift. The
    status bar shows that real time; nothing is overridden.
  - Demo data: `regularSeed` + `calendarSeed` from `creative-seed-3.2.1.mjs`
    (localized day/rest shift names, CN or US holiday region), DoneAt Plus on
    (debug), and leave in the widget window: zh-CN 2–6 Nov (5 days of leave,
    9 days off), en 23–25 and 27 Nov (4 days of leave, 9 days off around
    Thanksgiving).
  - Home Screen page 1 (free): classic countdown (medium), ring, week
    progress, shifts (medium). Page 2: next holiday with leave (medium; time
    off is Plus), year progress, weekend, work summary (medium, Plus). The
    layout was written to SpringBoard's `IconState.plist` while the simulator
    was shut down; the system language was switched for each locale.
  - Lock Screen: rectangular countdown, ring and week progress circulars,
    the weekend inline line, and the Start shift and time-until-clock-off
    controls.
  - `simctl recordVideo` writes no frames on the Home Screen (widget timers
    are not screen changes), so widget clips are screenshot sequences, each
    held until the next. On the Home Screen the simulator also stops drawing
    widget timers after a while, so the Home Screen beats show still widgets
    that arrive one by one. The countdown ticks in the app, Lock Screen and
    Watch beats.

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

## Status (2026-10-19)

zh-CN and en rendered locally; nothing uploaded, bound or submitted.

| Locale | ASC | Headline px | Report in-point | Frames audited | SHA-256 |
|---|---|---|---|---|---|
| zh-CN | zh-Hans | 93 | 6.8 s | 825 | `3e0219a95816` |
| en | en-US + en-GB | 69 | 6.0 s | 825 | `980bf0966131` |

Both are 1920×1280, 30 fps, 810 frames (27 s), H.264 yuv420p, no audio.
Every frame passed the safe-area, clipping and overlap audit, and
`creative-audit-3.2.3.mjs` reports no findings (`audit.json`). Review
sheets with the Art Safe Area outlined are in `search-review/`. The other
15 store locales keep the 3.2.2 video until their lines are written.
