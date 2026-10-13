# iOS 3.2.2 · Records and Time off screenshots

3.2.2 redesigned Records and Time off, so only those pages of the 3.2.1 sets
were retaken; every other screenshot, the iPad and Watch sets and each set's
order are unchanged.

| Set | Positions replaced |
|---|---|
| iPhone 6.9″ (`APP_IPHONE_67`, 1320×2868) | 3 Time off, 7 Records |
| iPhone Duo inner (`APP_IPHONE_DUO`, 2007×2853) | 2 Time off, 6 Records |

17 store locales carry their own sets and were replaced (68 screenshots).
en-GB, es-MX and mr-IN have no sets of their own in 3.2.2 and fall back to the
primary locale's, so nothing was created for them.

## Capture

- One Debug build of this branch, with the two fixes below. Every capture
  starts from the 3.2.1 marketing demo archive so the pages match the rest of
  each set.
- Records: the year view, which matches the reviewed 3.2.1 headline and label
  ("Year view with DoneAt Plus"). The month view depends on the capture day
  and reads sparse.
- Time off: the planner's top proposal from each storefront's holiday month
  (`holiday-demos.json`). Mainland China shows the 2027 predicted-holiday
  notice, as the app does.
- Headlines and sublines are the reviewed 3.2.1 copy (`creative-copy-3.2.1.mjs`);
  compositions are the approved 3.2.1 layouts.

Fixed while capturing:
- Records hung on its loading skeleton on the Duo inner display in French,
  Indonesian and Hindi (about 100% CPU): the canvas width that sizes the
  conclusion column cycled by fractions of a point. It is now rounded.
- A break starting on the last day of a week drew its length on a one-day
  band ("连休 1…"). The length is now written on the break's widest week.

## Reproduce

Duo must be booted alone with its inner display open and portrait in Device
Hub before the Duo capture.

```sh
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath /private/tmp/owc-322-shots-build CODE_SIGNING_ALLOWED=NO build
node scripts/marketing-shots/ios/creative-capture-shots-3.2.2.mjs
IOS_SHOTS_PLATFORM=duo-inner node scripts/marketing-shots/ios/creative-capture-shots-3.2.2.mjs
node scripts/marketing-shots/ios/creative-compose-shots-3.2.2.mjs
source ~/.config/doneat/asc.env
node scripts/app-store-connect/creative-shots-3.2.2.mjs            # dry run
node scripts/app-store-connect/creative-shots-3.2.2.mjs --apply
```

The capture needs `raw/3.2.2/shots/demo-archive.json` (the 3.2.1 iPhone
`before-capture-archive.json`) and the iPhone 18 Pro Max and Duo inner
portrait frames in `frames/`. Raw captures and compositions are ignored;
the upload receipt is `asc-screenshots-receipt.json` in this folder.

## Status (2026-10-13)

Uploaded to the iOS 3.2.2 draft. A set holds at most ten screenshots, so each
old one is deleted, the new one uploaded and put back at the same position.
Read back: every iPhone set has 10 and every Duo set 9 screenshots in their
original order, all `COMPLETE`. No build selected, nothing submitted.
