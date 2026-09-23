# Android instructions

Read with the root `AGENTS.md` when planning, changing, building or testing
Android (`src-mobile/android`, `docs/android`, `plans/Android`). Root privacy,
locale and validation rules apply.

## Status and sources

- Android is a planned native port; no Gradle project exists until task T03.
  The plan is `plans/Android/DoneAt_Android_Handoff_v1_1/` (package 1.2; the
  folder keeps its 1.1 name so links survive). Start at `00_START_HERE.md`.
- `docs/android/progress.md` is the only task-status record. `tasks.json`
  defines dependencies, scope and acceptance, not status.
- Behaviour is ported from the pinned iOS baseline recorded in
  `docs/android/baseline.md`, not from `main`. At each milestone run the drift
  command in `progress.md`, log the result, then decide whether to advance the
  baseline. Never follow `main` silently.
- Decisions live in the package's `decisions.json`; do not reopen approved
  ones. First release excludes T21 (server purchase verification), T22 (Drive
  sync) and T27 (Wear OS). Deferred is neither failed nor done.

## Architecture

- Kotlin, Jetpack Compose, Room, java.time. No WebView, Capacitor, Flutter,
  React Native or runtime JavaScript. `:core:domain` is pure JVM: no
  `android.*`, Room, Compose or Billing, and no hidden `Instant.now()`.
- Release uses stable Compose/Material3 only (D-12). Expressive styling comes
  from DoneAt shape/motion/colour tokens in `:core:designsystem`; no alpha or
  experimental Material3 APIs.
- Four main destinations match iOS `AppTab`: timer, focus, records, settings.

## Rules parity

- Shared rules (`lib/countdown.ts`, `lib/reminders.ts`, `lib/summary.ts`)
  reach Kotlin through JSON fixtures generated from the TypeScript oracle
  (T06). iOS-only rules (extended schedules, record resolution, focus) reach
  Kotlin through JSON exported by Swift tests; Swift and Kotlin tests read the
  same file with a stale check (T08). Decide which side is correct before
  regenerating; never regenerate to hide a failure.
- Once `src-mobile/android/core/domain` exists, a shared or iOS-only rule
  change must update Kotlin in the same change, and the root validation table
  gains an Android row. Add that row when T07 lands.
- Focus session IDs use the source SHA-256 truncation, not Java
  `nameUUIDFromBytes` or random UUIDs.

## Data, purchases and privacy

- User backups are `RecordJSON` schemaVersion 6, accepting 1–6. Room, fixture
  and any future sync versions are independent numbers.
- Android Auto Backup and device transfer include the business database (as
  iOS includes its main store in iCloud device backup). Exclude purchase
  caches, pending-acknowledge markers, Keystore material, tokens and debug
  settings. After a restore, re-query Play and system permissions; never trust
  restored entitlements or grants.
- First release uses client-only Play Billing (D-08), mirroring iOS StoreKit:
  entitlements come only from `queryPurchasesAsync` plus Play public-key
  signature checks, never from backups, imports or local booleans. Acknowledge
  on the client and retry within the three-day window.
- First release requests no Google sign-in or OAuth. Salary never appears in
  widgets, notifications, share cards/links, logs or analytics.

## Environment

- SDK: `~/Library/Android/sdk` (no `cmdline-tools`; install from Android
  Studio's SDK Manager if needed). Point `sdk.dir` in untracked
  `src-mobile/android/local.properties` at it.
- JDK: the system Temurin 21 is x86_64 and fails on this Mac. Use Android
  Studio's JBR: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`.
- Do not commit `local.properties`, `build/`, `.gradle/`, keystores or
  signing passwords.

## Validation

Until T03 records real commands in `docs/android/environment-lock.md`, report
Android checks as NOT_RUN. Expected shape, from `src-mobile/android`:

```bash
./gradlew :core:domain:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```

Cover every module's tests before calling a suite complete; device-only
behaviour (alarms, widgets, backup restore, purchases) needs device evidence.
