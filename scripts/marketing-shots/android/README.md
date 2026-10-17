# Google Play screenshots

Play screenshots follow the ASC 3.2.1/3.2.2 iPhone set: the same captions (`../ios/creative-copy-3.2.1.mjs`), cream background, Charter/Manrope and Noto typography, orange emphasis and opening two-image composition, with real Android captures in a neutral phone outline. ASC's ten scenes become Play's eight (Play allows at most eight) by leaving out the Apple Watch and the Dynamic Island / Lock Screen widget scenes:

1. `01-countdown` and `02-countdown-detail`: one timer capture across two images
2. `03-leave`: the time-off planner's top plan for the storefront's holiday region
3. `04-report`: September monthly report, "Time worked" (Plus)
4. `05-calendar`: Hours & schedule with the region's public holidays
5. `06-records`: Records Year view (Plus)
6. `07-focus`: a running focus block in a planned day (Plus)
7. `08-breaks`: the timer during the lunch break

19 app languages are captured; en-GB and es-419 reuse the en and es sets, as ASC's en-GB and es-MX fall back to en-US and es-ES. zh-HK captions use the app's Hong Kong wording (`play-copy.mjs`) and need a native reader.

## 1. Capture on a Pixel

Use an isolated Debug install, never the Play-installed app:

```sh
cd src-mobile/android
./gradlew :app:assembleDebug -PdoneatDebugApplicationIdSuffix=.shots
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Record the phone's settings first and restore them afterwards. Turn on System UI demo mode (100% battery, full signal, hidden notifications) and Do Not Disturb. `pixel-capture.mjs` sets the demo clock to the real time of each capture, so it matches the app.

```sh
ANDROID_SERIAL=<serial> ANDROID_SHOTS_DEMO_ARCHIVE=<iOS raw/3.2.2/shots/demo-archive.json> \
  ANDROID_SHOTS_LANGUAGE=en,zh-CN ANDROID_SHOTS_SCENES=records,report,calendar,leave \
  node scripts/marketing-shots/android/pixel-capture.mjs
```

- Writes only to `com.rainif.doneat.shots`, through `run-as`: the synthetic archive (`pixel-seed.mjs`, the iOS marketing demo history reseeded per scene), device settings, the Debug-only Plus switch and the release-notes marker. It refuses any package without the `.shots` suffix.
- Changes language with per-app locales (`cmd locale set-app-locales`), never the system locale.
- `timer` and `focus` need working hours in Asia/Shanghai (09:00–11:55 or 13:05–17:50); `breaks` needs 12:05–12:55. Records, report, calendar and leave work any time.
- Output: `build/play-store-media/raw/<lang>-<scene>.png` (1280 × 2856) and `capture-manifest.json`.

## 2. Compose

```sh
PLAY_IMAGE_DIR=play-store/images node scripts/marketing-shots/android/compose.mjs
node scripts/marketing-shots/android/feature-graphic.mjs build/play-store-media play-store/images
```

- `screenshots/<lang>/NN-*.png`: 1080 × 1920, opaque RGB, under 8 MB, checked on every render.
- `overview-<lang>.png`: review contact sheet, not an upload.
- The phone's own notification, VPN, ringer and Do Not Disturb icons are not part of the app, and this Pixel's demo mode does not hide them. The composer fills the status bar between the clock and the battery with its own background colour; app content is untouched.
- `PLAY_IMAGE_DIR` replaces each Play language's `phoneScreenshots/`. The feature graphic goes to `en-US/featureGraphic.png` only; other languages fall back to it.

Then check and preview the listing with `npm run play:listing:check` and `npm run play:listing:plan`, both with `--config play-store/3.2.2.json` (see `docs/PLAY-STORE-LISTING-SYNC.md`).
