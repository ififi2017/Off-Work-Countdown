# macOS App Store 3.2.3 · build record

Release record required by `SOURCE.md` for store-only builds.

| Field | Value |
|---|---|
| Platform | macOS (Mac App Store, universal arm64 + x86_64) |
| Version / build | 3.2.3 (3.2.3) — host and widget `CFBundleVersion` match |
| Minimum macOS | 13.0 |
| Source commit | [`b225491f`](https://github.com/ififi2017/Off-Work-Countdown/tree/b225491fe79df0e7c35dece7c2f686d942309873) (main, merge of #330) |
| Source archive | https://github.com/ififi2017/Off-Work-Countdown/archive/b225491fe79df0e7c35dece7c2f686d942309873.tar.gz |
| Package | `DoneAt-3.2.3-macappstore.pkg`, 18,069,297 bytes, SHA-256 `632327185f953b24b9d29ae3b721d2968ad44adf205701105758c697bf6f29a9` |
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

Not yet done: upload, TestFlight install on a Mac, App Store Connect version.
