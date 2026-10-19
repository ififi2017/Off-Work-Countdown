# iOS 3.2.3 · Poster font fallback fix (local, not uploaded)

## Problem

The poster fonts in `scripts/marketing-shots/ios/fonts/` are Google Fonts
text subsets. They only contain the characters of the copy that was
reviewed when they were downloaded (3.2.0). Later copy (3.2.1 pages and
tours, the 3.2.2 search lines, the 3.2.3 lines) added characters, which
Chrome then set in system fonts next to the poster serif: PingFang SC, Apple
SD Gothic Neo, Thonburi or Kohinoor. The user spotted two fonts mixed in the
zh-CN headlines.

Chrome's per-character check of every reviewed string (all 18 locales)
found missing glyphs in zh-CN, zh-TW, ja, ko, ru, tr, vi, th, hi-IN and
mr-IN. A scan of the rendered 3.2.0 and 3.2.1 HTML confirmed which published
assets were affected:

| Asset | Locales with fallback text |
|---|---|
| iPhone 6.9″ pages (3.2.1/3.2.2) | Time off: hi-IN ja ko ru tr vi zh-CN zh-TW · Cycle report: + th · Calendar, Records, Focus, Widgets, Rest: hi-IN ja ko ru vi zh-CN zh-TW |
| iPhone Duo pages | the same pages and locales |
| Header video V4 | ja ko mr-IN ru zh-CN zh-TW |
| Search videos (3.2.1 V4/V5, 3.2.2) | hi-IN ja ko mr-IN ru th tr vi zh-CN zh-TW (replaced by the 3.2.3 video) |
| iPad pages (3.2.0) | none |

## Fix

- Every poster subset was refreshed with the union of all reviewed copy
  (`creative-fonts-refresh.mjs`). The per-character check now finds no
  fallback in any locale.
- Every renderer used for 3.2.3 now fails when Chrome reports a non-poster
  font for headline, label or note text (`assertPosterFonts`). The families
  actually used are recorded as `fontsUsed` in each manifest.
- Re-rendered locally (`out/creative-3.2.3/`):
  - `header/`: header V4 for the 6 affected locales
    (`creative-video-locales-3.2.1.mjs`, `IOS_SHOTS_VIDEO_KINDS=header`).
  - `pages/`: every affected iPhone and Duo page
    (`creative-compose-locales-3.2.1.mjs`). Time off and
    Records use new captures of the 3.2.2 redesign
    (`creative-capture-pages-3.2.3.mjs`, raw `raw/3.2.3/pages`), because the
    3.2.2 captures were not kept.
  - `search/`: the new 3.2.3 search video for all 18 locales.

## Result

97 pages (iPhone: 45 — Time off 8, Cycle report 9, Calendar, Records, Focus
and Rest 7 each; Duo: 52 — Time off 8, Cycle report 9, Calendar, Records,
Focus, Widgets and Rest 7 each) and 6 header videos re-rendered. `creative-audit-3.2.3.mjs` finds
no issues. File names follow the 3.2.1/3.2.2 page numbering; in the 3.2.3
iPhone order, Time off is page 5, Cycle report 6, Calendar 7, Records 8,
Focus 9 and Rest 10.

Duo Time off and Records were captured on the iPhone Duo simulator's inner
display (2007×2853 portrait), which the owner opened in Device Hub; headless,
the Duo exposes no displays.

## Not done

- Nothing has been uploaded. Replacing a live asset is a separate step and
  needs the owner's yes.
