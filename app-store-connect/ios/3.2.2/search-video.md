# iOS 3.2.2 · Search-results video (local, not uploaded)

ASC slot: Product page → Header and search results → search results asset
(`APP_STORE_SEARCH_RESULTS_ASSET`). 3.2.1 shipped search V4; this replaces it
for 3.2.2 because Records and Time off were redesigned.

## What changed from 3.2.1 V4

- Every scene is recaptured from one 3.2.2 Debug build (`origin/main` 963c4922
  plus the Debug-only `qaLeaveFrom` hook in `DebugLeavePlanner.swift`).
  Records shows the new month calendar; Time off shows the new plan screen.
- Layout follows the Art Safe Area of Apple's search template
  (`apple-creative-template-guides.json`, 1920-scale `418,382.5,1084×515`).
  V4 placed brand, copy and the phone across the whole canvas, which real
  devices crop. V5 (unfinished, 3.2.1) shrank V4 into the safe area, which made
  the UI too small. 3.2.2 drops the phone frame and shows a native crop of the
  region that carries each feature, so the subject fills most of the safe area.
  Only the background extends beyond it.
- Copy is unchanged from V4 (`creative-copy-3.2.1.mjs`). Outgoing lines leave
  before incoming ones arrive, since the copy blocks no longer share a height.

## Spec

1920×1280, 24 s, 30 fps (720 frames), H.264 yuv420p BT.709, no audio, loops.
Every frame is audited in the renderer: brand, rail, card (with shadow) and
each visible glyph must sit inside the safe area; settled frames must not
overlap the card; headline ≥ 34 px. A violation stops the render.

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

## Status (2026-10-12)

en and zh-CN rendered and self-reviewed for sign-off. Other 16 languages not
yet rendered. Nothing uploaded, bound or submitted.
