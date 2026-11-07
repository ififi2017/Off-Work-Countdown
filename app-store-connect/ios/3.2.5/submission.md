# iOS 3.2.5 App Store submission (2026-11-07)

- App Store Connect had iOS 3.2.4 `READY_FOR_SALE`, so What's New covers only changes after 3.2.4: monthly-schedule daily pay, overtime pay choices, overtime start/rest and counted hours, Records overtime, mainland China's official 2027 holidays, and the Apple Watch complication refresh fix (#356). The 3.2.4 widget layout fixes are not repeated.
- Descriptions, keywords, URLs and promotional text were checked against an export of live 3.2.4: identical, so only What's New changed. `asc:sync` created version 3.2.5 (`PREPARE_FOR_SUBMISSION`, release type `MANUAL`) in 20 locales; a follow-up `asc:plan` showed no differences. en-GB, es-MX and mr-IN have no screenshots, as on live 3.2.4.
- Build 3.2.5 (297), Xcode Cloud run 297 from `81afb512` (main before the Android-only #365): `VALID`, not expired, `usesNonExemptEncryption: false`. Attached to the version.
- Review submission `6f8e2028-188b-4b1b-bf13-638074a04469` submitted 2026-11-07T15:34:24Z; version state `WAITING_FOR_REVIEW`. Release is manual after approval.
- Known gaps at submission: iOS AppTests had not executed cases in the 2027-holiday run, and the Watch complication fix had not been confirmed on a real Watch through TestFlight.
