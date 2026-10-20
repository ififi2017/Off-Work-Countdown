# iOS 3.2.3 · iPad 13″ screenshots (local, not uploaded)

ASC set: `APP_IPAD_PRO_3GEN_129` (2064×2752), 17 store locales. The iPad
equivalents of the 3.2.3 iPhone widget pages 3 and 4 (`screenshots.md`),
with the same reviewed copy (`creative-copy-3.2.3.mjs`, `PAGES`). Nothing
was uploaded, bound or submitted.

## Order

The set keeps 8 pages:

| New | Page | Source |
|---|---|---|
| 1 | Countdown (hero) | kept |
| 2 | Countdown detail | kept |
| 3 | **Home Screen widgets** | new |
| 4 | **Lock Screen · Apple Watch** | new |
| 5 | Calendar | kept (was 4) |
| 6 | Records | kept (was 5) |
| 7 | Focus | kept (was 6) |
| 8 | Breaks | kept (was 8) |

Two pages retire:
- 3 (Apple Watch), which page 4 now covers;
- 7 (Dynamic Island · Lock Screen · widgets), replaced by real 3.2.3 widgets.

The kept pages are the live 3.2.3 draft's files, read back with
`scripts/app-store-connect/ipad-shots-fetch-3.2.3.mjs` (read-only). Their
copy has no price wording: the 3.2.2 Guideline 2.3.7 fix already removed it
from the iPad Watch page, which now retires.

## Layout

- Approved 3.2.0 iPad layout (`creative-compose.mjs`, `pad`):
  - 1032×1376 at 2×;
  - label at 58 px;
  - headline at 1.16× the iPhone size;
  - iPad Pro M5 frame at 866 px, starting below the copy and cropped at the bottom.
- **Page 3** shows a real iPad Home Screen of DoneAt widgets:
  - classic countdown, ring and big digits;
  - shifts (medium), this week and year;
  - Countdown & up next (extra large);
  - this month and Progress (medium).
- **Page 4** shows the whole iPad at 660 px, because the 866 px crop would cut off the Lock Screen widgets near the bottom of the display.
  - On a 13″ display those widgets are small, so the real widget row is also shown enlarged just above itself: a crop of the same capture, like the 3.2.0 widget page's crops.
  - The Watch (the iPhone 3.2.3 Watch fixture) stands beside it on the wallpaper.
  - Arabic mirrors the iPad and the Watch.

## Capture

- **Device and build:** iPad Pro 13-inch (M5) simulator (6F5E631B…), Debug build of `claude/ipad-3-2-3`. That branch carries the fixes for:
  - the extra large ring's off-centre countdown (#333);
  - the Progress widget's truncated labels (#334).
- **Seeding and simulator settings:** demo data, system language and widget payloads per locale, as on iPhone (`search-video.md`, Capture), with these settings:
  - Full Screen Apps;
  - the dock's App Library and suggested/recent apps turned off.
  - The status bar shows the real time in a zone where it was mid-afternoon.
- **Home Screen:**
  - written to SpringBoard's `IconState.plist` while shut down;
  - the dock holds Safari, DoneAt, Messages and Calendar.
- **Lock Screen** (arranged by hand):
  - rectangular countdown, ring and week circulars;
  - the inline "until the weekend" line.
  - iPad Lock Screens have no control slots, so the Start shift control isn't shown. The shared subline still mentions it: the control exists on iPad in Control Center.
- **Per locale**, after the reboot:
  1. Lock Screen › Customize › Done redraws the widgets, which come back blank.
  2. Page to Today View and back so every Home Screen widget redraws together.
  3. Capture the Home Screen.
  4. Relaunch the app, then capture the Lock Screen.
- The Arabic system calendar is Hijri (ar_SA), as on iPhone.

## Checks

- `creative-compose-ipad-3.2.3.mjs`:
  - layout audit: no overflow, art below the copy, nothing outside the canvas, Watch fully visible;
  - Chrome's actual fonts: poster fonts only, no system fallback. That covers the Chinese poster-font fix.
  - Headlines are 67–88 px.
- `creative-audit-3.2.3.mjs` has no findings (`audit.json`). It now also checks:
  - iPad page size, opacity and hashes;
  - unchanged sources;
  - captions free of price or "free" wording in all 17 languages.
- Manifest: `ipad-screenshot-manifest.json`. Review sheets: `ipad-review/`.
  - the 34 new pages;
  - the en and zh-CN proposed 8-page order;
  - every locale's order sheet in `scripts/marketing-shots/ios/out/creative-3.2.3/ipad-review/`.

## Reproduce

```sh
set -a; source ~/.config/doneat/asc.env; set +a
node scripts/app-store-connect/ipad-shots-fetch-3.2.3.mjs   # read-only
# Home/Lock Screen arranged as above, per locale:
IOS_SHOTS_SIMULATOR=6F5E631B-982F-4911-928B-A28B8C63BD81 \
  node scripts/marketing-shots/ios/creative-capture-widgets-3.2.3.mjs en-ipad-home 1
IOS_SHOTS_SIMULATOR=6F5E631B-982F-4911-928B-A28B8C63BD81 \
  node scripts/marketing-shots/ios/creative-capture-widgets-3.2.3.mjs en-ipad-lock 1
node scripts/marketing-shots/ios/creative-compose-ipad-3.2.3.mjs
node scripts/marketing-shots/ios/creative-audit-3.2.3.mjs
```

## Upload (not done)

Nothing is uploaded until the owner approves these pages. An upload would:
1. Swap iPad positions 3 and 7 for the new pages.
2. Reorder the set as above, in the 3.2.3 draft only.

It would use a dry run first, like `creative-3.2.3.mjs`.
