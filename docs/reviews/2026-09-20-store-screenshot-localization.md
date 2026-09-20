# iOS 3.2.0 store screenshot localization

User-approved scope: 17 ASC locales × iPhone/iPad × 8 pages = 272 PNGs.
No ASC upload, release or commit is performed by the capture workflow.

## Artwork and copy

- Same device spans pages 1–2; approved iPhone position is preserved.
- Pages: countdown, countdown detail, free Apple Watch, calendar/holidays,
  Records (Plus year view), Focus (Plus), widgets, breaks.
- Logo stays to the left of the first brand line. Devices are upright except
  the opening spread; native widget fragments retain their approved angles.
- `creative-copy.mjs` contains editorial copy for every locale, intentional
  headline line breaks and first-page sizes. English, German and French use
  rewritten short headlines; other languages also have individual breaks.
- Arabic text uses RTL without reflecting the device frame or brand mark.
- `creative-copy-review.md` is the readable copy audit export.

## Real UI capture requirements

- Use the dedicated marketing simulators only. Never capture or seed a user's
  physical device. Back up existing demo archives; cloud sync remains disabled.
- Calendar samples use `holiday-demos.json`, each region's bundled 2026 dates,
  and local shift names. Saudi Arabia uses a Friday/Saturday weekend.
- Past calendar months require a 2025 career start and matching historical
  schedule snapshots with the region's holiday content. Extending the period
  alone leaves old all-week schedules visible and is not sufficient.
- Focus uses localized tasks and actual planning assignments. Task count,
  default time zone, persisted schedule zone and displayed daytime must agree.
- A surface marker alone does not prove the screen rendered: a cold launch can
  still display the launch screen. The capture script checks image variation;
  every final scene still needs visual review.
- Widget crop bounds are measured per language from native demo screenshot
  pixels, then visually reviewed. Chinese bounds cannot be reused blindly.

## Validation status

Copy review is complete. The 272 HTML layouts passed measured text bounds
with zero overflowing lines, including natural spacing for Arabic, Thai and
Hindi. Native widget bounds and German widget artwork were visually checked.

EN and Traditional Chinese smoke captures confirm daytime Focus labels and
actual assigned tasks. Taiwan June 19 is a rest day; US July 3 observed holiday
and July 4 are rest days, with ordinary weekdays/weekends also checked. Final
calendar and Focus captures use the completed physical-QA repair build.

All 17 Watch raw captures use the system's Shanghai zone, so the corner clock,
remaining countdown and night-shift end agree. The official 46 mm frame's
transparent aperture is x=72, y=192, width=416, height=496 in its 560×880 PNG;
actual screenshots are placed beneath this aperture, without invented UI.

All 272 formal PNGs are rendered and pass strict dimensions, opacity, locale,
order and source/HTML/PNG digest checks. All 34 review contact sheets have been
regenerated. The final 272-page geometry audit reports zero findings; ESLint
passes for the capture/composition tooling. All 34 locale/device contact
sheets were visually reviewed. A Turkish iPad calendar heading discrepancy
was resolved by an isolated calendar recapture and checked against its October
grid and Republic Day selection. Screenshot validation is not release approval.

Commands:

```sh
node scripts/marketing-shots/ios/creative-capture.mjs
python3 scripts/marketing-shots/ios/measure-widget-crops.py
node scripts/marketing-shots/ios/creative-compose.mjs
node scripts/marketing-shots/ios/creative-audit.mjs
node scripts/marketing-shots/ios/creative-validate.mjs
```

`IOS_SHOTS_LANGUAGE` selects app locale IDs; `IOS_SHOTS_PLATFORM` selects
comma-separated `iphone,ipad,watch` for capture, `iphone,ipad` for composition.
Layout-only previews are marked and rejected by formal validation.

`IOS_SHOTS_SCENES` can select `1,3,4,focus` while calendar/widget capture waits.
`IOS_CREATIVE_PAGES` selects individual page numbers for incremental rendering;
partial manifests never mark the full set complete. Final validation requires
all source hashes, locale/device/order mappings, HTML and opaque RGB PNGs.

Parallel Chrome rendering exposed a profile cleanup race (`ENOTEMPTY`) and
occasional 20-second cold-render timeouts. The shared helper now awaits the
Chrome exit event before removing its profile, uses bounded filesystem retries,
and allows 60 seconds for rendering. The composer permits one render retry;
a second failure stops the group. Independent profiles/output paths are used.
The text audit also checks title/subtitle vertical separation; iPad subtitles
and standard devices move down to preserve that separation without shrinking
text. The approved opening spread coordinates stay unchanged.

The user requested larger supporting copy and a review of commercial font
licenses. All final artwork has now been rendered with the licensed typography
below, and geometry was checked again. All Focus captures were refreshed with
the repaired current-time marker and French progress wording.

## Final typography revision (user feedback, 2026-09-20)

- English first-page supporting text increases from 25 to 32 logical px;
  footer from 18 to 24. iPad uses 36 / 27 respectively. Other pages' supporting
  copy increases from 20/24 to 24/28, with darker warm-gray ink for readability.
- English headline retains Charter's shape using the explicitly licensed open
  edition. Supporting copy uses Manrope. Non-Latin copy uses the matching Noto
  Serif/Sans family, with Source Serif 4 for Russian/Vietnamese headlines.
- Fonts are bundled locally with original notices, download URLs and SHA-256.
  See `scripts/marketing-shots/ios/fonts/README.md`. No proprietary system font
  files are embedded in poster HTML. Native screenshots retain real system UI.
- Title and subtitle now participate in one text flow. Device top follows the
  measured text height with deliberate spacing; Watch scales to fit its caption
  and footer. The first two panels retain their shared device coordinates.
- A Chrome actual-font audit of all 272 generated HTML pages reports no system
  fallback and no horizontal overflow or title/subtitle/device collision.
  Evidence: `docs/reviews/2026-09-20-store-font-audit.json`. This is typography
  evidence only; it does not certify the demo screenshot pixels.
- Russian and Vietnamese headline sizes are adjusted individually to their
  new metrics; no global shrinking of supporting text is used.
- All 272 PNGs were re-rendered. iPad source screenshots with notification
  dialogs or a Chinese system date in other languages were rejected and recaptured.

## Capture cleanup and final-review corrections

- iPad system language is switched alongside app language so status-bar dates
  match each locale. Notification dialogs are dismissed through real UI.
- Focus notification CLI strings were rejected: the production reader expects
  a real Boolean. The dedicated iPad’s native Focus settings now disable local
  notifications; a restarted German capture verified no permission warning.
- Japanese first-page supporting copy was shortened to avoid orphan glyphs;
  its licensed font subsets were regenerated to include the added character.
- Korean first-page footer preserves whole words. Hindi/Korean break timers
  were recaptured after review found animated digit transition frames.
- Widget geometry measures the union of rotated cards and fits it between
  the editorial text and footer, including iPad. Final audit checks all card
  boundaries against footer and canvas bounds.
- Final manifests bind each PNG to its actual HTML and native source hashes.
  HTML-only proofs and stale images cannot pass the formal validator.

## Final evidence

- Formal output: `scripts/marketing-shots/ios/out/creative-3.2.0/`.
- `manifest.json`: 272 current source/HTML/PNG SHA-256 triples.
- `layout-audit.json`: 272 pages, zero findings.
- `*-overview.png`: 34 review contact sheets; excluded from ASC asset counts.
- Final file validation: 272 ordered opaque RGB PNGs, exact iPhone/iPad sizes.
- All 17 languages received copy review and native screenshot visual review.
- No upload or release has been performed. Physical-device acceptance remains
  part of the primary release review, outside screenshot-file validation.
