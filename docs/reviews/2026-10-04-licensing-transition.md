# 2026-10-04 — MPL and brand licensing transition

Approved scope: commercial independent forks are allowed; no impersonation of
DoneAt; distributors must meet applicable covered-source and notice duties.
Website source in `ififi2017/doneat.app` stays MIT and its product-license
statements/brand policy are updated in a coordinated PR.

- [x] Standard Mozilla MPL-2.0 in LICENSE, byte-identical to
  `https://www.mozilla.org/media/MPL/2.0/index.txt` (SHA-256
  `3f3d9e0024b1921b067d6f7f88deb4a60cbe7a78e76c64e3f1d7fc3b779b9d04`).
- [x] Previous MIT notice preserved verbatim; baseline is
  `8ef6dbc5f69af79739000a047072d1fcbe1685d0`, not a claim to revoke rights
  or identify the final MIT commit on every branch.
- [x] LICENSING / ASSETS / TRADEMARKS / CONTRIBUTING / SOURCE distinguish
  software, designated artwork, historical grants, third parties and brand
  identity. No noncommercial clause, source-disclosure-on-network-use clause,
  copyright assignment or proprietary-relicensing CLA was added.
- [x] Existing history includes one commit authored by Alexandre Zollinger
  Chohfi (`f5d5f79e`, a CI revert), alongside maintainer/agent commits. This is
  not a sole-authorship assumption or a full rights audit; retained MIT
  material keeps its notices. No contributor's copyright is assigned here.
- [x] Third-party notice files and dependency graph unchanged. Backdrop/Shapes,
  holiday data, fonts, official badges and Apple frames retain their terms.
- [x] Root/billing npm metadata, Cargo metadata, README translations, Web
  structured data, existing 19-locale software-license copy and Windows
  listing source updated. No store listing is submitted by this PR.
- [x] Web/Desktop/extension build notices include source SHA/archive location.
  Middleware serves extensionless licenses without adding a locale prefix;
  three regression cases cover this. Dirty local builds identify their base
  instead of claiming an exact clean source match.
- [x] `npm run lint`, `npm test` (50 files, 547 tests), `check:version`,
  `check:ios`, Web build/check, Desktop export/check and extension build/check
  passed locally. Headless iOS simulator build passed; no simulator visual
  testing, signed native packaging or store submission was performed.
- [ ] Product [PR #298](https://github.com/ififi2017/Off-Work-Countdown/pull/298) merged before website [PR #31](https://github.com/ififi2017/doneat.app/pull/31).

Future releases must follow SOURCE.md and the release guide: preserve an
immutable source reference per distributed platform/version/build, including
store-only iOS/macOS builds. Existing store binaries are not retroactively
relicensed. Trademark registration/ownership review is separate; this PR
makes no claim that the brand is registered in any jurisdiction.
