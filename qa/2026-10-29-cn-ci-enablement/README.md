# CN CI enablement and 3.2.3 source integration — 2026-10-29

## Live configuration and CI

Owner requested enablement. Environment `android-cn-release` has required reviewer `ififi2017`, self-review allowed, and exactly one deployment branch `main`. Four independent CN signing secrets and the repository public verification key variable are configured. Original local signer certificate and public-key fingerprint matched the existing pinned production identities before upload through stdin. Secret values and signing material are not included here. Actual unauthenticated protection preflight passes; see the sanitized environment receipts.

PR345 enabled only CI/tooling on main. PR346 fixed setup-android's obsolete default `tools` package. These changes do not match Play's automatic release paths. First run 40800062473 failed at SDK setup; run [40800770044](https://github.com/ififi2017/Off-Work-Countdown/actions/runs/40800770044) completed successfully. Its downloaded candidate passed independent SDK manifest/unsigned/checksum/source verification. The retained JSON receipts describe **historical 3.2.1 source, code 8**, not the new 3.2.3 source. No tag, signature, Release, Play upload or domestic hosting change was created. CI signing credentials have not been exercised in a signing run; that still requires the owner's environment approval.

## New source validation

Integrated only CN channel/authorization/update behavior from public `android-cn-v3.2.1-7` (`6c87cb6f`), not unrelated local dirty work or historical holiday/leave edits. Preserve current Play implementations in channel source sets and share current widgets, acknowledgement collapse and other 3.2.3 UI. CN retains activation codes, encrypted no-backup receipt storage, original public trust, registration notice and channel-specific links. New CN content remains in PR344 for review, not main/released source.

- Play: 802 tests (468 domain, 97 data, 13 design system, 224 app), zero failures/errors/skips; Debug and Release lint, APK and R8 AAB pass.
- CN: 790 tests (same shared suites, 212 app), zero failures/errors/skips; both lint variants, Debug and unsigned Release APK/AAB pass. Release identity is `com.rainif.doneat.cn`, 3.2.3/code8; no Play Billing/Review dependencies or debug components. Missing production trust rejects preReleaseBuild.
- Lint has zero errors: Play Debug/Release 75/69 warnings, CN Debug/Release 74/68 warnings, four hints each. Full warning counts are retained rather than reported as a clean lint run.
- Shared npm 580 tests, Android string generation check, 34 CN helper tests, version consistency and headless iOS Simulator build pass. Fixed iOS reference remains `ffd91597`; baseline drift command returned 69 historical commits, no new shared-rule commits since this task's pinned reference. No iOS manual visual testing.
- Regression fixes revalidate CN proof when Focus writes, reports load/play/read, widget controls run, and paid notifications deliver; tests exercise expired proof with a stale authorized UI flow. Play's previous authorization behavior is preserved. Independent read-only review confirmed these fixes.

## Physical device scope

Pixel 10 Pro / Android 17, isolated Debug `com.rainif.doneat.cn.ciqa`. The real membership screen and expanded activation form display without clipping (English/dark). Screenshots exclude the system status bar. No activation code entered, trial started, purchase performed or server grant requested. This is UI evidence only, not production activation/renewal or upgrade acceptance. Temporary package removed after inspection; existing Play/CN/Widget QA applications and data preserved. Full 19-language, real activation/renewal and signed upgrade acceptance remain separate release checks.
