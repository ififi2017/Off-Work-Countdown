# iOS 3.2.3 · Store media plan

Status 2026-10-19: storyboard and pages approved; zh-CN and en produced and
audited, awaiting final review. What was made, and where it differs from this
plan, is in `search-video.md` and `screenshots.md`. Nothing uploaded.

3.2.3 adds the widget suite. This release gets a new search-results video, with
the widgets as its highlight, and new widget screenshot pages. Nothing is
uploaded to App Store Connect without the owner's explicit yes.

## Apple limits (checked 2026-10-19)

| Asset | Limits | Plan |
|---|---|---|
| Search-results video (`APP_STORE_SEARCH_RESULTS_ASSET`) | 3:2, 1920×1280 to 3840×2560, 30 or 60 fps, 5–30 s, .mov/.m4v/.mp4. Plays muted in search (no unmute) and loops. | 1920×1280, 30 fps, 27 s, H.264, no audio track (as 3.2.2) |
| Art Safe Area (official search PSD) | 3840-scale `836,765,2168×1030`, 1920-scale `418,382.5,1084×515` | Headlines and heroes stay inside it. Native surfaces may bleed past it. Every frame is audited, as in 3.2.2. |
| iPhone 6.9″ screenshots (`APP_IPHONE_67`) | 1320×2868 portrait, up to 10 per set, PNG/JPEG, no alpha | Opaque PNG, 1320×2868 |
| Regular App Preview (not planned) | 886×1920, 15–30 s, ≤30 fps, stereo AAC track | Not made this round |

Sources: [creative asset specs](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/),
[app preview specs](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/),
[screenshot specs](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

## Search-results video: storyboard

The 3.2.2 grammar stays: one headline plus one native hero per beat, 0.3 s
cuts (the headline slides out through its mask and the hero cross-fades), and
a slow 98.5 → 100.5 % push. The countdown is ticking from the first frame, so
the loop closes on itself. The widget beats are new: real Home Screen and Lock
Screen recordings with live numbers, where each widget arrives on its own
(scale 0.94 → 1 and fade, 90 ms apart) in the manner of iOS.

| # | Time | Scene (native source) | zh-CN | en |
|---|---|---|---|---|
| 1 | 0–3 s | Live countdown, app timer | 几点下班，一眼有数。 | Know when you’re done. |
| 2 | 3–6 s | **New** Home Screen: Countdown (Ring) + Week progress, staggered in | 不用打开，桌面就有数。 ✎ | Your day, on your Home Screen. ✎ |
| 3 | 6–9 s | **New** Home Screen: Shifts (7 days) + Next holiday + Year progress, swapped in per widget | 班表和假期，都在桌面上。 ✎ | Your shifts and holidays, right there. ✎ |
| 4 | 9–12 s | **New** Lock Screen: rectangular countdown, week ring, Start shift control | 锁屏一亮，还剩多久。 ✎ | Wake your screen. See what’s left. ✎ |
| 5 | 12–15 s | Apple Watch: upgraded countdown (plus complications if the face can be set up on the simulator) | 抬腕，离下班更近。 | On your wrist. Closer to done. |
| 6 | 15–18 s | Focus timer · DoneAt Plus | 把这一段，留给专注。 | One thing. Your full focus. |
| 7 | 18–21 s | Records month, days filling in order | 时间去哪，都有迹可循。 | Your days. In perspective. |
| 8 | 21–24 s | Cycle report counting up · DoneAt Plus | 忙过的日子，慢慢看清。 | Your month, in review. |
| 9 | 24–27 s | Time off: 9-day run lighting up | 一点请假，多一点假期。 | A little leave. A longer break. |

✎ marks a new line that needs review. The rest is reviewed 3.2.2 copy. The
Life beat is dropped to make room. Shifts and schedules appear through the
Shifts widget. Widgets never show salary. "界面为演示数据" / "Illustrative
data" sits in the corner, with "DoneAt Plus · " added on the Plus beats.

## Widget screenshots: two new iPhone pages

Both pages use the approved poster layout (label, two-line serif headline,
subline, official iPhone 18 Pro Max frame, real capture). Demo data only.

**Page 3 · Home Screen.** A real Home Screen of widgets:
Countdown Timeline (medium), Ring + Week progress (small), Shifts 7 days
(medium), Next holiday + Year progress (small).

| | zh-CN | en |
|---|---|---|
| Label | 全新小组件 | NEW WIDGETS |
| Headline | 不用打开，<br>桌面就有数。 | Your day,<br>on your Home Screen. |
| Subline | 倒计时、本周进度、班表与节假日，<br>多种尺寸，随心摆放。 | Countdown, week progress, shifts and holidays.<br>Arrange them your way. |

**Page 4 · Lock Screen and Apple Watch.** A real Lock Screen with a
rectangular countdown, week ring and inline clock-off time, plus the Start
shift control in a bottom slot. A Watch frame overlaps the lower corner and
shows the upgraded countdown or a face with the new complications.

| | zh-CN | en |
|---|---|---|
| Label | 锁屏 · 控制中心 · Apple Watch | LOCK SCREEN · CONTROLS · WATCH |
| Headline | 锁屏一亮，<br>就知道还剩多久。 | Wake your screen.<br>See how long is left. |
| Subline | 锁屏小组件、一键开始上班，<br>Apple Watch 也能看。 | Lock Screen widgets, a Start shift control<br>and Apple Watch complications. |

**Order (10 per set).** 1–2 countdown opener, **3 Home Screen widgets**, **4
Lock Screen & Watch**, 5 time off, 6 cycle report, 7 calendar, 8 records, 9
focus, 10 rest. The old Watch page (5) and old widgets page (9) are retired,
and Watch moves into page 4. iPad and Duo sets are unchanged this round.

Locales: zh-CN and en (en serves en-US and en-GB) first. The other 15 store
locales follow after review.
