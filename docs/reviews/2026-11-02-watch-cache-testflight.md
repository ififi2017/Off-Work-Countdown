# Watch complication cache recovery — TestFlight candidate

## Problem and change

A Watch app can display a newly received schedule while its complication keeps
showing “Waiting for iPhone”. The publisher sends schedule schema 6 and the wire
decoder accepts it, but the disk-cache reader only accepted schemas 1–5. The app
uses the accepted in-memory package; a widget reopening the same durable file
therefore received `incompatible` and projected a nil package as `waiting`.
This affects ordinary schedules too, without an adopted leave day.

- Share the supported schema ranges across encoding, decoding, validation,
  ordering and disk restoration. Existing schema 6 cache bytes become readable
  without clearing data, rewriting the file or receiving another phone package.
- Define the five Watch widget kinds once. Every widget configuration uses that
  definition; after persistence, cache restoration or foreground recovery, the
  receiver requests reloads for every kind and relevance updates for Countdown
  and Coming up. Duplicate deliveries still do not trigger repeated reloads.
- Cover schemas 1–6 across actual disk reopen, V1-to-current-schema upgrade,
  unsupported versions, late downgrade rejection and offline receiver restore.

The fix does not change the wire format, schedule calculations, Plus access,
timeline entry generation, refresh intervals or local user data. It does not
depend on `transferCurrentComplicationUserInfo`.

## Validation

- [x] `npm run check:ios` and `npm run check:version` (3.2.5).
- [x] Xcode MCP App scheme build-for-testing; iPhone 18 Pro / iOS 27.0 destination,
  Xcode 27.1 SDK. Includes the embedded Watch app and widget extension.
- [x] Focused iOS Watch contract/cache/publisher/projection tests: 72 declarations,
  98 executions including parameter cases, all passed on iPhone 18 Pro / iOS 27.0.
- [x] Watch tests: 26 declarations, 27 executions including schema 2/6 receiver
  upgrades, all passed on Apple Watch SE 3 (40mm) / watchOS 27.0. The iPhone
  simulator was shut down first. Both original `.xcresult` summaries report Passed.
- [x] `npm run check:ios-strings` and `git diff --check`. Xcode's unrelated
  automatic string-catalog extraction was discarded.
- [x] Unsigned Release build for `generic/platform=iOS`, including the embedded
  Watch app and widget extension, with Xcode 27.1 (27A9275). Existing
  `secondsThresholdMs` actor-isolation warnings in the countdown provider and
  `UNUserNotificationCenter` sendability warnings remain on unchanged code.
  No signed archive or upload was produced.
- [ ] TestFlight installation and affected user's real Watch confirmation.

No simulator visual inspection or real-device WatchConnectivity verification
has been performed. Automated cache reopen tests do not establish WidgetKit's
actual scheduling or presentation behavior on the affected Watch.

Release validation command (local build only):

```sh
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/doneat-watch-release-20261102 \
  CODE_SIGNING_ALLOWED=NO SWIFT_EMIT_LOC_STRINGS=NO build
```

## TestFlight handoff

Use the candidate source commit from this PR. The base is main
`b0cb2b99a9e1b7f8441dbcc0dbc5ccfbf1c2c95e`, already at marketing version 3.2.5.
No marketing/build number is changed here. Xcode Cloud assigns a new build
number; a manual upload must use a fresh build number for all shipping targets.
Record the uploaded version/build against the immutable source commit according
to `SOURCE.md`. This record is not an upload or distribution receipt.

1. Update both iPhone and Watch to this TestFlight build; keep the existing
   installation, schedule and complication in place for the initial check.
2. Open DoneAt on the Watch once, then return to the same watch face. A valid
   already-saved schema 6 package should now restore and request widget reloads.
   If the Watch app itself has no schedule, open DoneAt's timer on iPhone and
   let the Watch app receive it first.
3. Compare the app and complication during a shift. If using the schedule
   complications, check them after a schedule edit and a completed Watch sync.
4. On the developer's device, also check a Watch app cold launch with iPhone
   unreachable after one successful sync. The saved schedule should remain
   usable without pairing again.
5. If the complication still fails, collect the two installed build numbers,
   watchOS version, exact complication type and screenshots of the Watch app
   and face. Record whether it remains waiting, shows a different notice or
   turns black, and whether it recovers only after removing/readding it.

Keep the App Store response pending until the affected user verifies the result.
