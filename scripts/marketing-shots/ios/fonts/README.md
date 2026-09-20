# Licensed typography for the 3.2.0 App Store artwork

Reviewed 2026-09-20. These files are used only by the local poster compositor;
they are not installed on the system or added to the app bundle. Rendering is
offline. Font files, copyright notices and licenses stay together in this folder.

| Use | Font | License |
| --- | --- | --- |
| Latin headlines, including English | Charter Bold, open Bitstream/X Consortium edition repackaged by Matthew Butterick | Bitstream Charter license, `charter-LICENSE.txt` |
| Russian / Vietnamese headlines and explicitly licensed headline fallback | Source Serif 4 | SIL OFL 1.1, `sourceserif4-OFL.txt` |
| Latin / Cyrillic supporting copy, logo wordmark and device captions | Manrope | SIL OFL 1.1, `manrope-OFL.txt` |
| Simplified / Traditional Chinese, Japanese, Korean headlines | Noto Serif SC / TC / JP / KR | Respective `notoserif*-OFL.txt` |
| Chinese, Japanese, Korean supporting copy | Noto Sans SC / TC / JP / KR | Respective `notosans*-OFL.txt` |
| Arabic headline / supporting copy | Noto Naskh Arabic / Noto Sans Arabic | Respective OFL files |
| Hindi headline / supporting copy | Noto Serif Devanagari / Noto Sans Devanagari | Respective OFL files |
| Thai headline / supporting copy | Noto Serif Thai / Noto Sans Thai | Respective OFL files |

Charter's original notice permits use, modification and redistribution for any
purpose while retaining the notice. This is the open edition, not a commercial
Charter BT font copied out of a system installation. BITSTREAM CHARTER is a
registered trademark of Bitstream Inc.

The other listed fonts permit commercial design and redistribution under the
SIL Open Font License 1.1. The finished poster is not required to use the OFL;
redistributed font files retain their respective notices and license. No fonts
are sold separately or modified by this project. Google Fonts supplied the
text subsets; their downloaded bytes are retained unchanged. A `.ttf` extension
identifies the actual TrueType format returned by the service.

`manifest.json` records each downloaded font's original URL, license source,
SHA-256 and Google Fonts CSS request. The request includes this edition's
character subset. If marketing copy adds characters, obtain updated subsets
and repeat the browser's actual-font check; never silently use a system fallback.
The `Poster Charter` name in CSS is an alias, not a modification of font metadata.

Sources checked:

- Charter package and original license: https://practicaltypography.com/charter.html
- Google Fonts font-specific OFL notices: URLs in `manifest.json`
- OFL FAQ, sections 1.1–1.1.2 (commercial artwork, ownership, no required poster credit): https://openfontlicense.org/ofl-faq/

## Native screenshots

Text inside the phone, iPad, Watch and widget images is the actual app UI. Its
system fonts are rendered by Apple's OS and remain part of the screenshot;
no Apple font binaries are copied into this folder or embedded in poster HTML.
Apple's SF / SF Compact terms permit depictions and screenshots of software
running on the corresponding Apple platforms. This does not make those fonts
available for arbitrary marketing typesetting. All text outside native images
uses the explicitly licensed fonts above.

Apple source: https://developer.apple.com/fonts/ (SF section 2.A and SF Compact
section 2.A). These findings establish the intended commercial screenshot use;
they are not a blanket guarantee about unrelated uses or future license changes.
