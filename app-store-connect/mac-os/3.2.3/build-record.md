# macOS App Store 3.2.3 · build record

Release record required by `SOURCE.md` for store-only builds.

| Field | Value |
|---|---|
| Platform | macOS (Mac App Store, universal arm64 + x86_64) |
| Version / build | 3.2.3 (3.2.30) — host and widget `CFBundleVersion` match |
| Minimum macOS | 13.0 |
| Source commit | [`b1fc3800`](https://github.com/ififi2017/Off-Work-Countdown/tree/b1fc3800cfa36770654109816cf0c83e871abc3c) (main, merge of #331) |
| Source archive | https://github.com/ififi2017/Off-Work-Countdown/archive/b1fc3800cfa36770654109816cf0c83e871abc3c.tar.gz |
| Package | `DoneAt-3.2.3-macappstore.pkg`, 18,049,739 bytes, SHA-256 `4d13cdc05795f1e094ff34e875f022b11c2ca02bfc45043abf48d0a1006976d6` |
| Built | 2026-10-20, clean tree, Rust 1.99.1, Xcode 27.1 (27A9275) |

## Checks on the bundle

- Host `com.rainif.offworkcountdown.macappstore` and widget
  `com.rainif.offworkcountdown.macappstore.widget` signed with Apple
  Distribution (team 3GSK5B9S3T); `codesign --verify --deep --strict` passes.
- Both sandboxed, both with App Group
  `3GSK5B9S3T.group.com.rainif.offworkcountdown.macappstore`; App Store
  provisioning profiles embedded in both.
- Store channel: no updater code in the host binary.
- Widget kinds: classic, `bigdigits`, `ring`, `timeline`, `detail`.
- Embedded source notice names the clean commit above (no "uncommitted
  changes" marker).
- `.pkg` signed with 3rd Party Mac Developer Installer.

## Toolchain note

Rust 1.97.1 with Xcode 27.1's linker (ld-27037.1) writes broken proc-macro
dylibs whenever `MACOSX_DEPLOYMENT_TARGET` is set (12.0 or higher; Tauri sets
13.0 from `minimumSystemVersion`). Builds fail with `E0463 can't find crate for
…_derive/…_impl` or `mis-aligned LINKEDIT string pool`. Rust 1.99.1 links them
correctly; this build used `RUSTUP_TOOLCHAIN=1.99.1`.

## Build number

The first 3.2.3 package (build 3.2.3, from `b225491f`) failed Apple's
validation with 90061: a macOS `CFBundleVersion` must be higher than every
earlier upload, and 3.2.1 shipped as build 3.2.10. This package was rebuilt
from `b1fc3800` as build **3.2.30**; the product version stays 3.2.3. Since
`b225491f`, main changed only the iOS-only extra large layout of the shared
"Countdown and coming up" widget, so the Mac app is unchanged. The build number
was set with:

```bash
OWC_WIDGET_BUILD_NUMBER=3.2.30 RUSTUP_TOOLCHAIN=1.99.1 … \
  npx tauri build --config src-tauri/tauri.macappstore.conf.json \
  --config '{"bundle":{"macOS":{"bundleVersion":"3.2.30"}}}' \
  --target universal-apple-darwin --bundles app -- --no-default-features
node scripts/embed-macos-profile.mjs && npm run pack:macappstore
```

## Upload (2026-10-20, owner-approved)

- `altool --validate-app`: no errors.
- `altool --upload-package`: succeeded, delivery `8dc466dc-885b-4e5c-b6e7-98ca074d227d`; build 3.2.3 (3.2.30) processed as `VALID`.
- `asc:sync --apply --config app-store-connect/mac-os/3.2.3.json` created
  macOS 3.2.3 (`PREPARE_FOR_SUBMISSION`) and its 20 localizations. A fresh
  plan has no changes. The 3.2.1 screenshots carried over, 6 per locale; mr-IN
  has none, as on the live 3.2.1.
- No build selected, nothing submitted.

Not yet done: TestFlight install on a Mac, confirming the tested-device line
in `review-notes.txt`, selecting the build and submitting.
