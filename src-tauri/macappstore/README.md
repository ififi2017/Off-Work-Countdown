# macOS App Store channel

This directory contains inputs exclusive to the `macappstore` build channel.
The GitHub-distributed macOS app continues to use the default Tauri
configuration, updater, and signing path.

The store channel uses the separate host identifier
`com.rainif.offworkcountdown.macappstore`. This allows the two channels to
coexist without sharing salary or preference storage. The Widget bundle id is
`com.rainif.offworkcountdown.macappstore.widget`. The App Group *name* is the
same iOS-style identifier the iPhone app uses,
`group.com.rainif.offworkcountdown.macappstore`; ad-hoc local packages strip App
Groups entirely, while `automatic` and `distribution` builds prefix it with
`OWC_APPLE_TEAM_ID` (for example
`3GSK5B9S3T.group.com.rainif.offworkcountdown.macappstore`). Mac App Store
validation rejects the unprefixed `group.` form on macOS (409). Do not copy the
iOS entitlement onto the Mac host.

`--no-default-features` is mandatory for the store channel. It removes the
GitHub updater, process plugin, LaunchAgent autostart path, and
`macos-private-api` from the Rust dependency graph. Omitting it produces a
non-store build even if the Tauri config selects `macappstore`.

## Local builds

Build and ad-hoc sign only the Universal Widget extension:

```bash
npm run build:widget
```

Build the complete local-test `.app`, including the extension under
`Contents/PlugIns`:

```bash
npm run tauri:build:macappstore
```

The default `adhoc` mode is for local UI and bundle testing. App Groups cannot
authorize an ad-hoc signature: on macOS 15+ the host and extension are rejected
by `containermanagerd` and trigger an "other App data" prompt. The local package
therefore keeps App Sandbox, omits only App Group, and grants a narrow temporary
file exception for the salary-free snapshot in Application Support. This keeps
the extension discoverable by WidgetKit while making its gallery, timeline and 19-locale rendering
testable without a paid developer identity; it is not the configuration sent
to Apple.

`automatic` mode is the production architecture. It keeps App Sandbox, gives
the host outgoing network permission required by WKWebView, gives the
network-free Widget the same App Group, and writes the snapshot through that
group container.

The temporary file exception exists only in local ad-hoc output. It must not be
used as the App Store sharing design or copied into automatic-signing profiles.

Compile without applying the extension signature when diagnosing Xcode output:

```bash
OWC_WIDGET_SIGNING_MODE=none npm run build:widget
```

Xcode automatic signing for the extension can be exercised with an explicit
team:

```bash
OWC_WIDGET_SIGNING_MODE=automatic \
OWC_APPLE_TEAM_ID=YOUR_TEAM_ID \
npm run build:widget
```

The host and extension must ultimately use profiles that grant the same App
Group. Set `OWC_WIDGET_SIGNING_MODE=automatic` on the **full Tauri build**, not
only `npm run build:widget`, so Rust, the Xcode extension and bundle entitlements
all select App Group mode. Full Apple Distribution signing and `.pkg` upload
remain MAS-P2 work.

`OWC_APPLE_TEAM_ID` is enough to get the macOS form: both `build.rs` and
`scripts/build-macos-widget.sh` prefix a `group.*` identifier automatically.
You can still override the whole string:

```bash
OWC_APP_GROUP_IDENTIFIER=3GSK5B9S3T.group.example.offworkcountdown \
OWC_WIDGET_BUNDLE_IDENTIFIER=com.example.offworkcountdown.widget \
npm run build:widget
```

The Rust host uses the resolved identifier at compile time, so pass the same
`OWC_APPLE_TEAM_ID` / `OWC_APP_GROUP_IDENTIFIER` to a full Tauri build. A
distribution build that still signs `group.*` without a Team ID prefix is
rejected locally by `embed-macos-profile.mjs` and `pack-macappstore.sh`, and by
App Store Connect with 409.

## Contract and ownership

The Xcode project is at
`../macos-widget/OffWorkCountdownWidget.xcodeproj`. The same Swift sources also
form a package so the JSON contract can be tested without signing:

```bash
npm run test:widget-contract
```

The frontend remains the owner of schedule calculations and writes a
versioned, salary-free `WidgetSnapshot`. The native host only validates and
atomically stores that projection in the App Group, then asks WidgetKit to
reload. The extension selects precomputed timeline entries and renders them; it
does not implement work schedules itself.
