# Play Console preparation for Android Plus

The Android client is ready to build without a Play Console connection. Billing remains unavailable until the real Play values below are supplied. This file records the local implementation and the remaining Console and device work; it is not a Play approval or purchase test result.

## Public build configuration

Supply these Gradle properties for a Play-configured build, for example in a local, untracked `~/.gradle/gradle.properties` or protected CI build variables. The app packages their values in `BuildConfig`; they are **public identifiers and a public verification key**, never a signing secret.

| Gradle property | Source in Play Console |
|---|---|
| `doneatPlusSubscriptionProduct` | Created Plus subscription product ID |
| `doneatPlusMonthlyBasePlan` | Monthly base plan ID under that product |
| `doneatPlusYearlyBasePlan` | Yearly base plan ID under that product |
| `doneatPlusLifetimeProduct` | Non-consumable one-time product ID |
| `doneatPlayBillingPublicKey` | App-specific Base64 public licensing/billing key |

All five must be nonempty; the two products and two base plans must differ. No Play IDs, prices or public key are checked into the repository. The client queries Play `ProductDetails` for localized prices. The first release presents **base-plan offers only**; introductory trials and targeted offers remain disabled until their eligibility, pricing phases and localized disclosure are configured and tested in Play Console. The approved model is monthly, yearly and lifetime (D-01), with client verification (D-08).

## Local artifacts and checks possible before Console

- The APK/AAB can compile with empty properties. The Plus page then says purchases are unavailable and shows no buying control.
- Unit tests cover entitlement state transitions, the three-day acknowledgement boundary, the free/lapsed observation policy, and RSA signature acceptance and rejection. These tests use generated local proofs, not Play-issued purchases.
- The client queries subscriptions and one-time purchases separately. It accepts only a Play-signed `PURCHASED` item for the app package and configured product; pending or suspended items grant nothing. It preserves verified offline access after a failed query and clears access after a successful empty query. A local signed proof and acknowledgement timing marker are kept under `noBackupFilesDir`, excluded from Auto Backup and device transfer.
- WorkManager retries Billing query and client acknowledgement with a network constraint. It does not call a DoneAt server.

## Console and device evidence still required

1. Create the exact products/base plans and set active regional prices. Confirm any intended introductory offer separately; the current client does not sell one.
2. Set up a Play license tester and install the app through a Play test track under the final package/signing identity. Confirm ProductDetails returns each configured offer and localized prices.
3. Test monthly, yearly and lifetime purchases; pending completion and cancellation; restore after reinstall/device transfer; subscription cancellation while still active; grace period; suspended/expired subscription; refund/revocation; and offline return. Check that access changes only after a successful Play query and that an existing verified grant survives a transient failure.
4. Test acknowledgement of each new token, including a simulated network failure followed by WorkManager retry within Play's three-day window. Check the actual signed purchase JSON fields against the local verifier.
5. Review Play Console Data safety, subscription disclosures, review testing and production review requirements using real Console screens and SDK documentation. A successful local build is not evidence that Google approved the listing or billing behavior.

## Data and network map

| Component | Data handled locally | Network destination / trigger |
|---|---|---|
| Play Billing Library | Configured product IDs, Play-returned localized prices/offers, signed purchase JSON, purchase token and acknowledgement state | Google Play billing service on Plus refresh, restore, purchase, app resume and acknowledgement retry |
| Signed proof cache | Play-signed JSON and signature, token, first observed purchased time and a historical-purchase marker | None; app-private `noBackupFilesDir`, never included in RecordJSON or backup |
| WorkManager | Schedules a network-constrained Billing retry, with no salary or archive data | Invokes the same Play Billing APIs when retrying; no DoneAt endpoint |
| Play In-App Review | Review eligibility is local; the SDK may ask Play to show a review dialog | Google Play, after a locally eligible shift and only while the app is resumed |
| Android system backup and device transfer | `records/` and `device/settings.json` only. The archive can contain schedules, salary settings/history, records, Life details and Focus plans; settings can contain an unfinished setup draft with salary | The Android/Google backup or transfer service when enabled in system settings; no DoneAt server |

The Billing and Review integrations do not pass salary, work history or backup documents to Google Play. Android system backup is separate: its named files can contain salary and work history. The app has no DoneAt analytics endpoint. A Play review can collect a rating or text through Google Play; the app receives no completion result, while a published review may be visible to the developer. Google Play SDK behavior and Data safety declarations must be checked against current SDK guidance and the final Play-installed artifact when the Console entry is prepared.

### Final local release evidence and Data safety worksheet

The merged **release** manifest under `app/build/intermediates/merged_manifests/release/` identifies `com.rainif.doneat`, versionCode `1`, versionName `3.2.0`, minSdk 26 and targetSdk 36. It enables Android backup with the two include-list XML files and disables cleartext traffic. Its permissions include Play Billing, Internet, network state, wake lock, biometric/fingerprint, boot completion, notifications and exact alarms. It does **not** request a location or advertising-ID permission. The release SDK dependency inventory includes Play Billing `9.1.0`, In-App Review `2.0.2`, WorkManager `2.10.5` and transitive Google Play services, including `play-services-location`; a transitive artifact alone does not establish that location is accessed or collected. Recheck the merged output after any dependency or manifest change.

| Console topic | Local evidence to carry into the form | Final check |
|---|---|---|
| Accounts and app access | No DoneAt sign-in or account; free timer/setup works without Plus. Paid screens use a Play purchase. | Supply working license-test access and exact reviewer steps for the Play-installed candidate. |
| Purchases and financial information | Google Play handles checkout. The app keeps a signed purchase proof/token in `noBackupFilesDir`; no payment card fields enter DoneAt storage. | Review Play Billing's current SDK Data safety guidance and the actual Console categories. |
| User content and backup | `records/` and `device/settings.json` are included in cloud backup/device transfer. Both can contain salary; settings may hold a salary-bearing setup draft. No DoneAt server receives these files. | Confirm Android/Google backup handling in the applicable Data safety questions and published privacy page. Do not describe this as automatic Drive sync. |
| Reviews | The app requests Play's prompt after local eligibility and receives no submission result. Play may collect the user's rating/review and publish it or share a closed-test review with the developer. | Use Play Review's SDK disclosure; avoid claiming that the developer can never see a review. |
| Ads, analytics and location | No ads/analytics integration, `AD_ID` permission or location permission appears in the inspected release artifact. | Recheck final dependency inventory, merged manifest and runtime behavior before answering the Console forms. |

Device-only data is generally outside Play's definition of data “collected” by the developer, but Android system backup and Google SDK processing need their own category review. This worksheet is evidence for the owner, not prefilled Data safety answers. See [Play Data safety guidance](https://support.google.com/googleplay/answer/11416267), [Play Review SDK disclosures](https://developer.android.com/guide/playcore/in-app-review) and [Android backup guidance](https://support.google.com/android/answer/12461238).

Official references: [Billing integration](https://developer.android.com/google/play/billing/integrate), [Billing releases](https://developer.android.com/google/play/billing/release-notes), [Play subscription policies](https://support.google.com/googleplay/android-developer/answer/9900533), [In-app review](https://developer.android.com/guide/playcore/in-app-review/kotlin-java).

## Draft Play review access instructions

Use the following as the basis for Play Console's App access/review instructions after the Play-installed candidate has been tested. The free core needs **no DoneAt account, sign-in, purchase or code**.

1. Open DoneAt and finish setup with a working day and a shift that spans the current time. On Timer, inspect the effective-time countdown and progress. Change the schedule in Settings to inspect a break or a different working day.
2. Open Records to inspect a recent day. Choose Year, Life, an older locked day or Focus to reach the Plus offer screen. The screen shows the local Play price only after Play returns configured products; Restore purchases queries the current Play account.
3. For paid capabilities, use a Play license-test account whose subscription or lifetime test purchase is configured in the Console. After Play confirms the purchase, open Focus, the unlocked record/chart or Life editor, and the optional cycle-end summary switch. The reviewer should use Play's normal purchase flow; the release build has no hidden unlock code.
4. In Settings → Records & Data, import a test RecordJSON file or export/delete test data. Add the Android widget from the launcher to inspect its salary-free time display. Notification permission and exact timing are optional system permissions and can be declined while the timer still works.
5. Return to Plus to restore purchases or open Google Play subscription management. If Play does not expose the configured products to the review account, the paid path cannot be verified; resolve the Console/test-track setup before submitting, rather than presenting a fake price or entitlement.

Replace this draft with the exact navigation labels and any Console-supported tester access details confirmed on the final Play-installed build. Do not place a tester password, purchase token or private signing key in this repository.

## Release sign-off and upload runbook

**Local engineering evidence**

- Run `npm run check:version` before packaging, then Android's required Gradle test, lint, Debug and Release build gates. Keep the resulting test report, merged manifest, dependency inventory and output hashes tied to the commit and Android `versionCode`.
- A local `assembleRelease` result proves only that code and resources compile and shrink; this repository has no production Android signing configuration. An unsigned local APK is not a Play-submittable release and does not verify billing, backup restoration or Play review behavior.
- Verify the final release bundle uses stable Compose/Material3 dependencies, the intended candidate package ID, a monotonic `versionCode`, and no debug Plus override. Inspect the merged manifest for permissions, including `SCHEDULE_EXACT_ALARM` and `POST_NOTIFICATIONS`, against the actual user-facing behavior.
- Keep the 19 app UI locales and generated Android resources in sync. Store listing text is reviewed separately in [store-listing.md](store-listing.md); use real Android phone/tablet screenshots and synthetic personal data.

**Console and owner evidence before any upload or submission**

- Confirm the actual developer account type, identity tasks, production access and country eligibility in Play Console. The app ID `com.rainif.doneat` is still the D-10 candidate; freeze it against Console availability before the first upload. If the account is a personal one created after 13 November 2023, check the current closed-test/production-access requirement in that account; Google currently describes at least 12 opted-in testers for 14 continuous days before applying for production access ([official account testing help](https://support.google.com/googleplay/android-developer/answer/14151465)).
- Create products/base plans and tester access, then record actual license-test purchases and lifecycle results listed above. Check the final public key and ProductDetails against the production application ID. Revisit any trial/offer decision with its exact phases and eligible accounts before enabling it in the client or store copy.
- Prepare Play App Signing/upload key and protected signing environment. Build an Android App Bundle for the chosen test track, verify its SHA-256 and inspect Play's processed artifact, warnings and pre-launch report. Do not treat a local unsigned build as an uploaded or approved release.
- Check the listing's title/description limits, support email, category, regions, pricing model, real phone/tablet screenshots, icon and feature graphic. Complete the Console's current Data safety, content rating, target audience, ads, App access and permission declarations from observed app and SDK behavior. Submit review access instructions that work on the Play-installed candidate.
- **Update the official [privacy page](https://doneat.app/privacy) before submission.** Its current text describes iPhone/iPad/Mac/Windows and StoreKit but does not yet describe Android Auto Backup/device transfer, Play Billing proof storage, Google Play purchase processing or Android deletion. The support URL exists; its current scope is incomplete for the Android listing.
- Have the owner review the final signed bundle, Console declarations, regional prices, subscription terms and test evidence before starting a rollout. A Console form or local draft is not a sign-off or proof of approval.

Official references: [create and set up an app](https://support.google.com/googleplay/android-developer/answer/9859152), [prepare for review](https://support.google.com/googleplay/android-developer/answer/9859455), [release rollout](https://support.google.com/googleplay/android-developer/answer/9859348), [subscriptions policy](https://support.google.com/googleplay/android-developer/answer/9900533).
