# Artwork scope and permissions

The following is a path inventory, not a blanket restriction on `assets/`
or on user interfaces. It excludes the listed DoneAt-owned artwork from
**new MPL grants**. Copyright notices already present remain authoritative;
the existing project notice identifies ififi2017. Third-party owners retain
their own rights. No ownership of Apple/Microsoft/Google artwork is asserted.

| Artwork | Locations |
| --- | --- |
| Open Day logo and app icon, including layers/Icon Composer | `assets/brand/` artwork files (SVG/PNG and `AppIcon.icon/` design data) |
| Web/PWA app icons | `app/icon.png`, `app/apple-icon.png`, `app/favicon.ico`, `public/icon-192x192.png`, `public/icon-512x512.png`, `public/icon-maskable-512x512.png` |
| Desktop/tray and extension icons | image files in `src-tauri/icons/` and `src-extension/icons/` |
| iOS brand images | image files in `src-mobile/ios/App/App/Assets.xcassets/BrandIcon.imageset/` and `BrandMark.imageset/` |
| Android launcher/launch artwork | `src-mobile/android/app/src/main/res/drawable/ic_launcher_*.xml`, `drawable/launch_brand.xml`, `mipmap-anydpi/ic_launcher*.xml` under the same `res/` directory |
| Screenshots, recordings and social/marketing artwork | image/video files in `readme_image/`, `public/showcase/`, and `scripts/marketing-shots/` (third-party exceptions below) |
| Embedded representations of the same Open Day logo | logo drawing data in `scripts/marketing-shots/brand.mjs`, `src-mobile/ios/App/App/Native/Views/OWCBrandMark.swift`, `CelebratingBrandMark.swift`, and `src-mobile/android/core/designsystem/src/main/kotlin/com/rainif/doneat/core/designsystem/DoneAtBrandMark.kt` |

The rendering, animation, interaction and generation **code** remains MPL;
the depicted logo is covered by this artwork notice and TRADEMARKS.md.
BrandTapSequence, tests, reusable UI components and ordinary layout/color
code are not reserved artwork. Unlisted project source/documentation follows
LICENSING.md. Imported third-party artwork always follows its original terms.

For the listed artwork, all rights reserved **except** the permissions in
[TRADEMARKS.md](TRADEMARKS.md), any separately documented permission, existing
license grants, and rights supplied by law. Private builds, contribution
previews and truthful references/reviews are permitted as described there.
Independent products should supply their own branding and store imagery.

## Historical grants are preserved

This notice cannot withdraw MIT or other rights already granted for any
version of an image, vector path, recording or embedded logo. Existing files
were distributed with the historical repository license; do not assume that
adding this notice makes their previous copyright permissions disappear.
Consult the file's provenance and historical notices. New artwork or new
copyrightable additions offered only under this policy are not newly offered
under MPL. Separate trademark rights and misleading conduct require their
own analysis; this is not a retroactive claim against compliant MIT users.

## Third-party material

Apple frames remain subject to
`scripts/marketing-shots/ios/frames/Apple Design Resources License.rtf`.
Geist and marketing fonts retain their bundled OFL/other font licenses.
Official store badges, platform symbols and other third-party material are
not DoneAt-owned artwork; retain their original terms and provenance.
A composite screenshot does not give us rights to relicense its third-party
parts. This document does not claim exclusive rights to a general color,
layout, software feature or independently created interface.
