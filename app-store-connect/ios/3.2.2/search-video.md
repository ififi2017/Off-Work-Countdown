# iOS 3.2.2 · Search-results video (local, not uploaded)

ASC slot: Product page → Header and search results → search results asset
(`APP_STORE_SEARCH_RESULTS_ASSET`). 3.2.1 shipped search V4; this replaces it
for 3.2.2 because Records and Time off were redesigned.

## What changed from 3.2.1 V4

- Four beats of six seconds: countdown → widget → records → time off. Focus
  and the cycle report are dropped; each beat is one line of copy (from the
  reviewed V4 lines) and one native hero. No wordmark, eyebrow, subline or
  progress dots; "Illustrative data" appears once, small, in the corner.
- Recaptured from one 3.2.2 Debug build (`origin/main` 963c4922 plus the
  Debug-only `qaLeaveFrom` hook in `DebugLeavePlanner.swift`).
- Layout follows the Art Safe Area of Apple's search template
  (`apple-creative-template-guides.json`, 1920-scale `418,382.5,1084×515`).
  Headline and hero stay inside it; the native surface around the hero (timer
  screen, wallpaper, calendar) bleeds past it so the full 3:2 frame reads as
  full. V4 spread everything across the canvas and was cropped on devices;
  the unfinished 3.2.1 V5 shrank V4 into the safe area and the UI got too small.
- Heroes are native pixels at or below capture resolution (no upscaling):
  live ticking countdown and widget recordings, the 3.2.2 month calendar
  (two weeks, recorded days fill in order) and the 3.2.2 plan screen (plan
  result, then the run's days light up one by one).
- Demo data is identical in every language: no holiday region, so there are
  no localized or truncated holiday names ("Colum…", "9 days…").
- Transitions: copy leaves before the next line arrives; the hero fades out,
  the next fades in (no ghosted digits); a slow 2 % push carries each beat.
  The countdown keeps ticking across the loop point.

## Spec

1920×1280, 24 s, 30 fps (720 frames), H.264 yuv420p BT.709, no audio, loops.
Every frame is audited in the renderer: headline glyphs and hero inside the
safe area, no clipped text, settled copy clear of every visible surface,
headline ≥ 56 px. A violation stops the render.

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
  composed from native pixels: masks over the recorded bars and the run's
  leave days are removed in order. Coordinates are in `SCENES`.

## Status (2026-10-12)

en and zh-CN rendered and self-reviewed for sign-off. Other 16 languages not
yet rendered. Nothing uploaded, bound or submitted.
