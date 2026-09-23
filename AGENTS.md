# Off Work Countdown Agent Guide

## Scope and task-specific instructions

One product, three targets: Web (Next.js 15 App Router, React 19, TypeScript,
Tailwind, Serwist); Desktop (the exported React frontend in Tauri v2 with
Rust/AppKit); iOS (native SwiftUI + WidgetKit in `src-mobile/ios`). iOS has no
WebView, Next.js pages or Capacitor; `cap`, `CapApp-SPM` and
`capacitor.config` references are stale. Web/Desktop share a React tree;
iOS shares business behaviour and translations, never markup.

The following tracked documents continue this guide. Read the relevant one
when its trigger applies; unrelated tasks do not require them. Skills remain
optional and cannot override this guide's architecture, checks, locales or
release gates. No rule, plan or script may depend on locally installed skills.

| Task | Required instructions |
|---|---|
| Change, build or test iOS; change rules/locales consumed by iOS | [iOS](docs/agent-guides/ios.md) |
| Desktop channels, signing, packaging, versions, release CI, store listings/media or release download counts | [Releases](docs/agent-guides/releases.md) |
| Plan, change, build or test Android (`src-mobile/android`, `docs/android`, `plans/Android`) | [Android](docs/agent-guides/android.md) |
| Select, use or install a repository skill | [Skills](docs/agent-guides/skills.md) |

## Privacy and product boundaries

- Local-first: hours, salary and preferences stay on-device by default.
  The approved 2026-09-05 plan 015 exception permits preferences and career
  salary history in opt-in private CloudKit sync and user-triggered backups.
  No product accounts; no salary in widgets, URLs, analytics or share metadata.
- Share URLs encode only start/end times. Analytics are anonymous aggregate
  event counters: no cookies, identifiers, IP/User-Agent storage or histories.
- Desktop networking is limited to updates, external links and user-triggered
  sharing. The automatic launch version check sends no account, salary or
  usage data; installer downloads require the user's request. A change to this
  balance also requires updating the official About page at doneat.app.

## Shared rules and architecture

- TypeScript is the specification: `lib/countdown.ts` owns shifts and salary
  helpers; `lib/reminders.ts` owns reminder timing/copy and absolute triggers;
  `lib/summary.ts` owns summaries. `lib/reminders.test.ts` is every consumer's
  acceptance spec. Never duplicate a formula for a figure the rules produce.
- Rust only maintains frontend-prepared absolute snapshots while the WebView
  is hidden, compares trigger times and sums/compares absolute segments.
  Never derive schedules, milestones, lunch boundaries or micro-breaks there.
  It may switch only to a supplied `nextShift`; discard one crossed entirely
  during sleep without backfilled notifications. iOS schedules the same
  reminder list up front rather than polling every second.
- A running shift is `segments + plannedEndAtMs + overtimeEndAtMs`.
  Remaining time, progress, earnings, lunch gaps and micro-breaks use effective
  segments, never `end - now` or a standalone start/end range. Overtime extends
  the original hourly rate linearly: progress may use extended duration;
  salary uses elapsed effective time / planned effective duration.
- iOS implements shared rules in `src-mobile/ios/App/App/Native/Models/`:
  `ScheduleRules.swift` owns current/next shifts, snapshots, rest days, Widget
  shifts, Watch projection, range expansion, break validation, the reminder
  list (via `ReminderRules.swift`) and whether schedule edits ask about today.
  `SummaryRules.swift` owns period summaries, Records income/forecast, monthly
  salary equivalent and lifetime income. Shared behaviour changes must update
  `lib/` and the matching Swift implementation together, with regenerated
  fixtures and the checks below. Decide which side is correct before
  regenerating; never regenerate merely to hide a Swift failure.
- iOS-only rules are written/tested in Swift. `ExtendedScheduleRules.swift`
  resolves civil days to the existing start/end/break/workday tuple and passes
  it to `CivilZone`; no second scheduling algorithm, and plan-free inputs keep
  the existing path. Snapshots store shift types/rules in `extendedContent`,
  never hand-set days, which stay live. Read `ScheduleSnapshot.configurationData`
  through `RecordCoordinator.expandableHours(for:)` to overlay the live roster.
  Frozen historical assignments also overlay fixed snapshots; legacy rows
  without frozen hours retain their pre-extended-schedule boundary. Direct
  decoding silently loses these overlays.
- Watch V2 compiles the same salary-free Swift scheduling core from
  `src-mobile/ios/Shared/` into iPhone, Watch App and Watch widgets. Cached
  configuration resolves later shifts offline; do not implement another
  recurrence algorithm or impose a rolling snapshot expiry. Transport never
  includes salary, career income or the record archive. Watch App and both
  complications are free; entitlement fields exist only for V1 cache reading.
- No JavaScriptCore runtime rules bundle: do not restore `CountdownRules.js`
  (`check:ios` rejects it).
- `BUILD_TARGET` separates Web and Desktop. Web builds retain middleware and
  Route Handlers; Desktop statically exports to `out/` without Web-only APIs. Keep standard
  `route.ts` filenames for Vercel tracing; exclude Desktop APIs in build config.
- macOS Mini Timer: native `src-tauri/native-mini/NativeMiniTimer.m`, linked by
  `src-tauri/build.rs`; `NSGlassEffectView` on macOS 26, Vibrancy earlier.
  Never replace it with WebView/CSS glass. The optional standard/woodfish
  WebView floating timer has a separate lifecycle; neither appears
  automatically in release builds. Windows intentionally uses `/[lang]/mini`
  and programmatic Tauri window creation.

## UI and copy

- Default to restrained, platform-native UI; emphasis must earn its place.
  Size/space by surface, density, conventions, usage frequency and hierarchy,
  not universal numbers or importance alone. Keep settings, toggles, tools,
  legends, info, expand/collapse and source labels out of the visual centre.
- Use ordinary icon metaphors: SF Symbols on iOS/macOS, existing `lucide-react`
  on Web/Desktop, or standard symbols. Custom marks retain familiar silhouette,
  proportions and meaning. Prefer position, grouping, subtle colour, dividers,
  state feedback, hover/tooltips over oversized elements, heavy blocks, radii,
  borders, shadows, decorative gradients or marketing layouts.
- Compare new UI with its whole screen; reduce excess weight/size or lost
  density before hand-off. Preserve settled conventions: shared orange accent,
  iOS `OWCDesign` 22 pt cards / 14 pt controls. Extend `OWCMotion` for curves and
  durations rather than inlining numbers; the app already adopts Liquid Glass.
- Desktop is a compact, non-resizable 420–450 px tool: single-line title, fixed
  footer, settings subpage. Salary stays in the existing summary card; updater
  state stays inline/in a toast, with no added window height. Dropdowns stay
  above the footer and scroll internally. Disable shell/Mini Timer text
  selection; inputs opt back in via `.select-none input`.
- macOS Mini Timer is a non-draggable menu-bar panel. Windows Mini Timer is
  draggable, remembers position, supports always-on-top and stays off taskbar.
  Main window and both Mini Timers share the store's `hideEarnings`; no local
  reveal state. Eye icons show the click's action, not current state.
- Woodfish count/sound preference stay local; first tap is silent. Do not add
  bundled or downloaded audio assets.
- Desktop UI verification covers light/dark, long English labels and the
  longest translated option within each fixed-width select trigger.
- Debugging Windows on macOS: `open --env OWC_FORCE_WINDOWS_MINI=1 <app>` uses
  the Windows Mini Timer; keep it behind `debug_assertions`, absent in release.
  Plain `open` loses the variable; direct binary launch loses bundle identity.
  With `npm run dev:desktop`, `?platform=windows` (also `macos` or `other`)
  forces `desktopPlatform`; compile this override out of release. Windows calls
  `set_decorations(false)` at runtime; keep macOS decorations for traffic lights
  since `tauri.conf.json` has one cross-platform value.
- Copy serves the user: lead with benefit, acknowledge their situation, offer
  a clear next step, and stay warm/respectful/peer-level. No judging, lecturing,
  correcting, scolding, defensive comparisons or implying a wrong choice.
  Keep implementation trivia out of marketing and operational burden off the
  user. Technical/privacy/security caveats are neutral, specific, actionable.
  Review loading, empty, error, download and permission copy in context; avoid
  condescending, bureaucratic or maintainer-facing language.

## Localization

- All user-facing app keys need translations in all 19 locales wherever stored,
  preserving English placeholders. iOS edits
  `src-mobile/ios/App/App/Localizable.xcstrings` directly; it is not generated.
  `scripts/generate-watch-localizations.mjs` generates the Watch table from it.
  Web/Desktop use `public/locales/*`, containing their keys plus all widget
  keys. Shared keys deliberately live in both homes, not a shared runtime.
- `WidgetCopy` (shared with Mac) reads `translation.json` from the widget
  extension bundle. Copy `public/locales` into that extension only, not the App.
- `npm run check:ios-strings` (also in `npm test` and Xcode Cloud) requires every
  referenced Swift key, no unused catalog keys, all widget keys in
  `public/locales`, and matching shared wording unless `INTENTIONAL_DIVERGENCE`
  permits otherwise. iOS-only English requires `SAME_AS_ENGLISH_ON_PURPOSE`.
  Use recognized key shapes: `t("…")`, `.string("…")`, `strings("…")`,
  `localize("…")`; `…Key` property/function returns or constants; `…Key:`
  arguments or same-file helper `…Key` parameters; key-labelled tuples; or
  `focusIcon<Case>`. Other shapes are reported as unused.
- Long-form pages only support English/Simplified Chinese through
  `lib/content-locales.ts`; do not create unreviewed 19-locale copies. Chinese
  UI variants link to Simplified Chinese content; others to English.
- Desktop starts in the OS locale until a user persists an in-app language.
  OS surfaces always follow system language: Finder/Dock/Launchpad/macOS menu
  app names via localized `CFBundleName`/`CFBundleDisplayName`; tray/application
  menus and About via `getFixedT(systemLocale)`. The desktop-menu effect must
  not depend on `lang` (`docs/PLAN-MSSTORE.md` 9.7).

## Work and validation

- Preserve unrelated worktree changes. Normal flow: feature branch → PR → main;
  no long-lived Desktop branch. Use focused commits; explain non-obvious
  platform work's user-visible reason in PRs. PR titles use Conventional
  Commits `type(scope): summary` (optional `!`): `feat`/`perf` → `enhancement`,
  `fix` → `bug`, `docs` → `documentation`; other types remain unlabelled/Other
  Changes. `.github/workflows/label-pr.yml` reads titles, not commit bodies;
  `.github/release.yml` groups only by those labels.
- When supported, sub-agents may handle useful independent subtasks. The
  primary agent plans, coordinates, reviews and integrates. Use an appropriate
  lower-tier model for sub-agents, never the highest tier available.
- Do not commit `.next`, `out`, `src-tauri/target`, service-worker output,
  installers, local environment files, updater private keys, passwords or
  signing certificates. Only the updater public key belongs in the repository.
- Keep `docs/PLAN-MSSTORE.md` and `docs/PLAN-MOBILE.md` aligned with material
  architecture/milestones; remove stale TODOs when verified.
- Stop `next dev` before a build: it shares `.next` with `next build`.

Setup: `npm install`. Common checks: `npm run lint`, `npm test`,
`npm run check:version`. Complete the applicable gates before code hand-off:

| Change | Required validation |
|---|---|
| Any code | Checks proportional to scope |
| Shared rendering, routes, locales or build config | Lint, unit tests, Web build + `check:build:web`, Desktop export + `check:build:desktop` |
| Desktop Rust | Also `cargo fmt --check`, `cargo test`, release build; keep macOS/Windows PR CI (`fmt`, `clippy -- -D warnings`, tests) green |
| Anything in `lib/`, `public/locales` or `src-mobile/` | Also local headless iOS simulator build |
| Anything in `src-mobile/ios` | Also `npm run check:ios` |
| Shared rules, including `lib/countdown.ts`, `lib/reminders.ts`, `lib/summary.ts` | Update matching Swift, `npm run generate:ios-rule-fixtures`, `npm test`, simulator build and passing `ScheduleRuleFixtureTests` |
| UI | Real visual inspection on affected OS; iOS exception below |
| Any packaging | `npm run check:version`; release guide |

**iOS simulator visual testing requires an explicit user request.** Implementing
or fixing iOS UI is not that request. Do not proactively boot/open a simulator,
launch for inspection or capture screenshots (including `qa:ios-shots`).
Headless builds and automated XCTest/Swift Testing, including required simulator
startup, may proceed without asking. Do not extend them into manual/visual QA.
Without a visual-testing request, complete applicable automated checks, state
that visual inspection was not performed, and hand off; do not block or ask
solely to satisfy visual QA.

| Target | Development | Build and validation |
|---|---|---|
| Web | `npm run dev` (localhost:3000) | `npm run build`, `npm run check:build:web` |
| Desktop | `npm run tauri:dev` | `npm run build:desktop`, `npm run check:build:desktop`, `npm run tauri:build` (GitHub bundle) |
| Rust | | `cargo test --manifest-path src-tauri/Cargo.toml` |
| iOS | Open `src-mobile/ios/App/App.xcodeproj`; no generation/sync prerequisite except changed fixtures | See iOS guide for headless build and test-runner pitfalls |
