# DoneAt licensing

## Software

Except for the identified artwork and third-party exceptions below, the
project's software source, tests, build/configuration files, translations and
accompanying project documentation in this revision are offered under the
[Mozilla Public License 2.0](LICENSE) (SPDX: `MPL-2.0`). This includes Web,
Chrome extension, Tauri/Desktop, iOS/iPadOS/Watch, Android and
`services/billing-api`. Commercial use and independent store distribution
are allowed under the applicable licenses.

This Source Code Form is subject to the terms of the Mozilla Public License,
v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at https://mozilla.org/MPL/2.0/.

This repository-level notice applies to the covered files without individual
headers as permitted by Exhibit A. Preserve existing notices; use SPDX
headers for new source files as described in [CONTRIBUTING.md](CONTRIBUTING.md).
The unmodified license text in LICENSE controls; this document is a scope
and transition guide, not additional conditions on MPL-covered software.

## Transition and existing MIT grants

This licensing transition was prepared on **2026-10-04**, based on commit
[`8ef6dbc5f69af79739000a047072d1fcbe1685d0`](https://github.com/ififi2017/Off-Work-Countdown/tree/8ef6dbc5f69af79739000a047072d1fcbe1685d0).
That is an immutable pre-transition reference, not a claim that all branches
or all files were MIT, or that no later MIT revisions exist. The transition
is identified by the commit introducing this document and the MPL LICENSE;
publication of that revision offers its covered source under MPL. Existing
store binaries retain the licensing applicable to the source they used.

[LICENSE-MIT-LEGACY](LICENSE-MIT-LEGACY) preserves the previous MIT notice
verbatim. Rights already granted under MIT remain available, including for
previously licensed code or artwork still present in this revision. The
change does not revoke those grants or retroactively impose MPL obligations
on an independent derivative of an MIT revision. Conversely, the historical
MIT notice does not offer new MPL-only contributions under MIT.

Retain this MIT notice for retained MIT material, together with original
third-party copyright and license notices. Repository ownership and merge
authority do not transfer contributors' copyright.

## Artwork, brand and third parties

- [ASSETS.md](ASSETS.md) identifies artwork excluded from new MPL grants,
  its limited permissions and the continuing effect of historical licenses.
- [TRADEMARKS.md](TRADEMARKS.md) explains official identity and independent
  forks. It does not restrict commercial use of the covered source.
- Third-party files retain their own terms, even when inside otherwise
  MPL-covered directories. See `THIRD_PARTY_LICENSES/`, `app/fonts/LICENSE.txt`,
  `scripts/marketing-shots/ios/fonts/` and the Apple Design Resources license
  in `scripts/marketing-shots/ios/frames/`.
- Android Backdrop and Shapes retain Apache-2.0, including required notices
  for adapted example code; see `src-mobile/android/app/src/main/assets/licenses/`.
  Dependency licenses and notices are not replaced by the top-level license.

## Source availability and distribution

When distributing covered software, comply with MPL sections 3.1–3.4,
including providing the covered source and telling recipients how to obtain
it. MPL does not require a pull request to this project or disclosure of
independent files containing no MPL-covered code. Merely running the billing
service on a server does not create a network-source-disclosure obligation.
See [SOURCE.md](SOURCE.md) for source locations and release responsibilities.

Moving code to a private repository does not cancel existing grants or give
the maintainer additional rights in other contributors' work. Contributions
are not subject to copyright assignment or a broad proprietary-relicensing
CLA merely by being accepted here.
