# Widget suite (3.2.3, plan 023): overnight build and self-check

Branch `feat/widget-suite`, stacked on `fix/ios-notification-tap-crash` (#322,
which carries the 3.2.3 crash and timer fixes). Rebase onto `main` after #322
merges.

Built and checked without a person present, on one simulator at a time
(iPhone 18 Pro, iOS 27). Nothing here has run on a real device yet; the list
at the end is what still needs one.

## What is in the branch

| Area | Widgets | Access |
|---|---|---|
| Countdown | Classic (unchanged, kept as the first entry), Big digits, Ring, Timeline, Detail (medium/large/extra large) | Free |
| Week and shifts | Week progress (small, medium, Lock Screen), Shifts (today, 7-day strip, month) | Free |
| Holidays | Weekend countdown; Next holiday | Free; the time-off part of Next holiday is Plus (D2) |
| Summary and life | Year progress | Free |
| | Work summary (week/month/year by size), Life progress | Plus |
| Focus | Focus timer with +1 and stop | Plus |
| Control Center | Start shift, Clock-off time | Free (D3) |
| | Focus | Plus |
| Apple Watch | Upgraded countdown (segment ring, corner, inline); Week, Shift, Holiday, Up next | Free (D4); no time-off figures on Watch |
| macOS | The four countdown styles | Free; no Mac summary (D5) |
| Settings | Settings › Appearance › Widgets: every widget with a size picker, Free/Plus badges, sample data for locked Plus widgets, how-to-add steps | |

## Contact sheets

Rendered offscreen by `AppTests/WidgetSuiteRenderTests` (every view at every
declared size; Monday 15:19, 9:00–18:00 with a 12:00–13:00 lunch, mainland
China holidays, Plus sample data where locked).

| Sheet | Language and appearance |
|---|---|
| [widgets-zh-CN-light.jpg](2026-10-19-widget-suite/widgets-zh-CN-light.jpg) | Simplified Chinese, light |
| [widgets-zh-CN-dark.jpg](2026-10-19-widget-suite/widgets-zh-CN-dark.jpg) | Simplified Chinese, dark |
| [widgets-en-light.jpg](2026-10-19-widget-suite/widgets-en-light.jpg) | English, light |
| [widgets-en-dark.jpg](2026-10-19-widget-suite/widgets-en-dark.jpg) | English, dark |

To regenerate: run the test with
`TEST_RUNNER_OWC_WIDGET_RENDER_DIR=<folder>` in the environment.

`ImageRenderer` cannot animate live timers, so focus and Classic Lock Screen
progress bars show a yellow placeholder and the focus time stays at 25:00. On
the Home Screen they use the orange tint set in code.

## Fixed during self-check

- Minute-precision `SystemFormatStyle.Timer` printed words ("6小时53分钟");
  replaced with `Text(timerInterval:)`.
- Ring styles showed lunch gaps before clock-in; they now show one whole ring
  until a shift is running.
- Static `ProgressView`s took the system tint (yellow); replaced with segment
  bars.
- "Coming up" rows for tomorrow showed only a time; non-today rows now carry
  the weekday ("周二 09:00").
- The Timeline style was redrawn to scale (start, lunch range, now, end).
- The Settings gallery originally laid all sizes side by side with a lot of
  empty space; it now has a size picker on a grey stage. It also forced light
  mode and now follows the system appearance; Lock Screen previews stay dark.
- The year summary bars were too short on the large size; raised to fill the
  card.

## Decisions made overnight, for your review

1. **Next holiday shows the leave plan you adopted**, not a fresh search. A
   widget cannot run the planner, and showing your own plan avoids numbers
   that change between refreshes.
2. **Life progress always assumes 80 years**, because the life profile has no
   life-span field; the copy says "按 80 岁计" so the figure is never presented
   as a prediction. When no career start is set, the career row starts at 22.
3. **Summary period follows widget size**: small = week, medium = month,
   large = year. There is no per-widget configuration intent yet.
4. **Year progress is free.** It has no salary or record content; the Plus life
   widget shows the year row as well.
5. **Shifts keeps showing today until today's shift ends**, then moves on to
   tomorrow.
6. **The Start shift control only starts the countdown** (the same as the app's
   button). It does not create a record or change the schedule.
7. **Every countdown style keeps the live H:MM:SS timer**, matching Classic,
   including the Lock Screen ring. A minute-precision system timer prints words
   ("6小时53分钟"), so there is no minutes-only variant.
8. **Watch complications use a minute clock** (HH:MM remaining) to stay within
   the Watch refresh budget.
9. **Week progress projects existing rule outputs** (current/next shifts and
   holidays) and adds no new scheduling rule, so nothing was added to `lib/` or
   Kotlin.
10. **No macOS summary widget** (D5); macOS gets the four countdown styles.
11. **Russian copy uses "ты"**, matching the app's existing Russian register.
12. **Control and intent titles are listed in `UNSEEN_ON_PURPOSE`** in
    `check-ios-strings`, because the system reads them through
    `LocalizedStringResource` rather than a recognised `t()` shape.
13. **AGENTS.md** now says "Watch App and all complications are free".

## Needs a real device

- Interactive widgets: Start shift and Focus +1/stop run in the app process
  (`LiveActivityIntent` / deep links); simulator rendering cannot prove the
  intents fire from the Home Screen and Control Center.
- Lock Screen and Live Activity time against the system clock (the 3.2.3 drift
  fix in #322).
- Watch complications on a real face, including the corner and inline
  families, and refresh after the iPhone changes the schedule.
- Apple UI terms in the how-to-add steps for Arabic, Vietnamese and Marathi
  (Edit, Add Widget, Customize, Add a Control, Complications) should match the
  system's own wording.
- Widget refresh when leaving the app: `publishWidgets` runs when the last
  scene backgrounds and writes only files whose content changed.

## Outside this branch

- Xcode Cloud: the workflow's test destination "iPhone Duo" does not exist, so
  #322's Xcode Cloud run fails before tests. Change the destination in App
  Store Connect › Xcode Cloud › workflow › Test action.
