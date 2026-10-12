# iOS 3.2.2 · Search-results video (local, not uploaded)

ASC slot: Product page → Header and search results → search results asset
(`APP_STORE_SEARCH_RESULTS_ASSET`). 3.2.1 shipped search V4; this replaces it
for 3.2.2 because Records and Time off were redesigned.

## What changed from 3.2.1 V4

- Eight beats of three seconds, cut in 0.3 s, so a viewer gets about three
  seconds of each before the next: countdown → widget → focus → records →
  cycle report → time off → Apple Watch → life. The countdown is on screen,
  ticking, from the first frame.
- Each beat is one headline and one native hero. No wordmark, eyebrow,
  subline or progress dots; "Illustrative data" sits small in the corner, with
  "DoneAt Plus" added on the focus and cycle-report beats.
- Headlines reuse the reviewed V4 tour lines. Written for this video (other
  16 locales need translations before they render; a missing line fails):
  en countdown "Know when you're done." and en report "Your month, in
  review." (the V4 lines shrank to ~70 %), Watch (en "On your wrist. Closer
  to done.", zh from the 3.2.1 Watch page) and life ("Work, in the bigger
  picture." / 把工作，放回人生里。, from the 3.1.9 App Preview). Any headline
  below 85 % of full size is logged and stored as `shrinkFlagged`.
- Recaptured from one 3.2.2 Debug build (`origin/main` 963c4922 plus the
  Debug-only `qaLeaveFrom` hook). Apple Watch is recorded fresh from the Watch
  app's Debug review fixture (`-owcWatchReviewState working`) on a Watch
  simulator, in a time zone that puts "off at" near 5 PM like the iPhone
  beats; it is cropped below the status bar, whose clock cannot be overridden.
- Layout follows the Art Safe Area of Apple's search template
  (`apple-creative-template-guides.json`, 1920-scale `418,382.5,1084×515`).
  Headline and hero stay inside it; the native surface around each hero
  bleeds past it so the full 3:2 frame reads as full. Heroes are native
  pixels at or below capture resolution; Records, Leave, Focus and the report
  fill the safe-area width, the Watch shows at its native 1:1.
- Records: month header joined to last week (regular days, overtime on two
  days, a day of leave shown as a day off, weekend rest); recorded days fill
  in order. Time off: both rows of the nine-day run with its label; each day
  lights up in order. Report: the month's hours counting up live.
- Demo data is identical in every language: no holiday region (so no
  truncated holiday names) and Monday-first weeks (the app's week-start
  setting), which keep the Saturday–Sunday run on two rows.
- Shift alarms was tried for the last beat and dropped: without a configured
  alarm the screen is a single "off" toggle and does not read in three seconds.

## Spec

1920×1280, 24 s, 30 fps (720 frames), H.264 yuv420p BT.709, no audio, loops.
Every frame is audited in the renderer: headline glyphs and hero inside the
safe area, no clipped text, settled copy clear of every visible surface,
headline ≥ 56 px. A violation stops the render.

The countdown, widget, focus, report and Watch clips are recorded live and
wrap across the loop point, so the digits keep counting from 23.9 s into 0 s.

## Reproduce

```sh
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath /private/tmp/owc-322-creative-build CODE_SIGNING_ALLOWED=NO build
IOS_SHOTS_LANGUAGE=en,zh-CN node scripts/marketing-shots/ios/creative-capture-search-3.2.2.mjs
IOS_SHOTS_LANGUAGE=en,zh-CN node scripts/marketing-shots/ios/creative-search-3.2.2.mjs
```

Raw captures land in `scripts/marketing-shots/ios/raw/3.2.2/search/`, videos
and the manifest in `scripts/marketing-shots/ios/out/creative-3.2.2/search/`
(both ignored). Review frames and the manifest copy are in this folder.

Capture notes:
- `ReleaseNotes.current` is still 3.2.1, so `releaseNotesSeen` stays 3.2.1;
  anything else puts the What's New sheet over the timer, focus and records.
- Onboarding chooses its holiday template from the locale region. On a US
  public holiday (Columbus Day, the capture day) the en widget preview read
  "Next shift in". The en widget scene uses `en_001` so it counts down the
  live shift; every other scene keeps `en_US`.
- Records and leave screens are static once settled, so their animation is
  composed from native pixels: `creative-marks.py` finds the calendar cells
  that carry marks in the capture, and masks over them are removed in reading
  order. Row bands are in `SCENES`.
- Records are seeded relative to the capture week (the two weeks before it),
  so the visible dates follow the capture day; capture every language on the
  same day.

## Status (2026-10-12)

en and zh-CN rendered and self-reviewed for sign-off. Other 16 languages not
yet rendered. Nothing uploaded, bound or submitted.
