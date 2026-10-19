# iOS 3.2.3 · App Store Connect upload plan (media not applied)

Script: `scripts/app-store-connect/creative-3.2.3.mjs`. It is read-only by
default. The full dry-run output from 2026-10-19 is in `upload-dry-run.txt`.

## Version

iOS 3.2.3 was created on 2026-10-19 with `npm run asc:sync -- --config
app-store-connect/ios/3.2.3.json` (output: `asc-sync-apply.txt`). It is
`PREPARE_FOR_SUBMISSION` with no build selected. All 20 localizations read
back identical to the config, so the only change from 3.2.2 is What's New. The
new version inherited 3.2.2's screenshots and placements. The dry run against
the version itself (`upload-dry-run.txt`) matches the earlier preview against
3.2.2 line for line. No media has been uploaded.

## What --apply changes

| Asset | Locales | Change |
|---|---|---|
| iPhone 6.9″ set | 17 (all with screenshots; mr-IN has none) | Pages 3 and 4 are the new widget pages. The old Watch page (5) and widgets page (9) retire. Time off, Cycle report, Calendar, Records, Focus and Rest move to 5–10. |
| iPhone 6.9″ set | zh-Hans zh-Hant ja ko ru vi hi (all six moved pages), tr (Time off, Cycle report), th (Cycle report) | Moved pages are also swapped for their poster-font re-renders. |
| iPhone Duo set | zh-Hans zh-Hant ja ko ru vi hi (7 pages each), tr (2), th (1) | Poster-font re-renders are swapped in place. The order is unchanged. |
| Search-results video | 20 (en-GB reuses en; es-MX reuses es) | Placement replaced with the 3.2.3 widget video (27 s, 1920×1280). |
| Header video | zh-Hans zh-Hant ja ko ru mr-IN | Placement replaced with header V4 re-rendered in poster fonts (8 s, 3840×1646). |

Totals:

- 131 screenshot uploads and 131 deletions, across 26 sets.
- 24 videos uploaded to the asset library.
- 26 placements replaced.

Every set reads back with 10 iPhone and 9 Duo screenshots. Pages 1–2 and any
page without a re-render keep their current 3.2.1/3.2.2 uploads, including
the "nofree" Time off pages. Whatever a set does not keep is deleted from
that version only; earlier versions are not affected.

## Checks the script makes

- Local:
  - the 3.2.3 audit has no findings;
  - every PNG and MP4 matches its manifest hash;
  - PNGs are opaque, at the size their set requires;
  - videos meet Apple's current asset-library spec, read from the API (search: 3:2, 5–30 s; header: 3840×1646, 5–30 s; 30 fps; no audio).
- Remote:
  - every screenshot sits where it is expected (`-iphone-NN-` / `-duo-NN-` file names), or the run stops;
  - every target locale exists.
- Apply order, per set:
  1. delete the screenshots the set will not keep;
  2. upload the new ones and wait for `COMPLETE`;
  3. set the order and read it back.
- Videos: reserve, upload, wait for processing, replace the placement, then read back `ACTIVE`.
- The receipt (`asc-media-receipt.json`) makes a rerun resume rather than upload twice.
- The script never selects a build or submits for review.

## Copy review still open

- zh-CN and en were reviewed.
- The other 15 locales' widget-page and search lines were written for 3.2.3 (`screenshots.md`, `search-video.md`).
- No caption uses price wording (Guideline 2.3.7).
