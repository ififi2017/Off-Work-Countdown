# Google Play screenshots

English Play screenshots reuse the ASC 3.2.0 copy, fonts, colors and opening two-image composition. The app content is captured from Android; the frame is a simple neutral outline. Apple Watch, Dynamic Island and iCloud are omitted.

## Render

Place five **real Android** screenshots in `<output>/raw/`, each 1080 × 2400:

- `en-timer.png`: current working shift, with earnings hidden.
- `en-calendar.png`: Hours & schedule monthly calendar.
- `en-records.png`: Records Year view with synthetic history.
- `en-focus.png`: active Focus task with a populated schedule.
- `en-breaks.png`: timer during the configured lunch break.

Use an isolated test installation and synthetic data, preferably on a physical Android device. Wait for the app to finish launching before capture. When using Android System UI demo mode, keep its status-bar clock consistent with the app clock. Plus scenes may use the existing Debug-only entitlement switch; they are not purchase verification. Never use a personal device archive or simulated purchase prices.

```sh
node scripts/marketing-shots/android/compose.mjs [output-directory]
```

The default output directory is `build/android-play-internal/store-listing/asc-style`.

- `screenshots/`: six English PNGs, numbered for upload, 1080 × 1920, opaque RGB, under 8 MB each.
- `overview.png`: review contact sheet, not an upload screenshot.
- `manifest.json`: source and output hashes, dimensions, order and capture disclosure.
- HTML files: editable rendered layouts, using the same locally licensed fonts as ASC.

The script checks dimensions, opacity and file size on every render. Inspect the overview and full-size outputs before uploading. Screenshot 1 and 2 form a continuous composition. Do not upload the overview, raw captures, JSON or HTML files.

Source copy: `app-store-connect/ios/3.2.0.json`. Android listing text: `docs/android/store-listing.md`. Rendering uses the existing Chrome helper; no app build or remote store mutation is performed.

## Feature graphic

Run `node scripts/marketing-shots/android/feature-graphic.mjs [store-listing-directory]` after capturing `asc-style/raw/en-timer.png`. It produces `feature-graphic-en-1024x500.png`, editable HTML and a source/output hash manifest. The graphic shares ASC typography and colors, with an unretouched crop of the real Android timer. The renderer checks size, opacity and file size. This replaces the earlier purple logo-only draft.
