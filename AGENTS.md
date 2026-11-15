# Off Work Countdown Agent Guide

## Scope and task-specific instructions

One product: Web (Next.js 15 App Router, React 19, TypeScript,
Tailwind, Serwist); Desktop (the exported React frontend in Tauri v2 with
Rust/AppKit); native iOS, Watch and Android apps. Web/Desktop share a React
tree. From 4.0 the native apps live in a private repository that pins this
one as a submodule; their 3.x source stays here at tag `ios-v3.3.0`. Never add
native app source back here.

The native apps consume, read-only, from this repository: the rules in `lib/`
(`countdown`, `reminders`, `summary`, `watch-projection`, `extended-schedule`),
widget keys in `public/locales`, the widget UI in `src-tauri/macos-widget`,
`assets/brand/AppIcon.icon` and `data/holidays/`. Changing behaviour or
removing/renaming anything there also needs a matching native change after the
submodule moves; say so in the PR.

Chrome extension (`src-extension`) is a Manifest V3 toolbar popup. Its React
entry reuses PC components and `lib/` rules, bundled by esbuild rather than
Next export. Fonts and all 19 UI locales are local. Keep the popup offline,
with no host permissions, content scripts, analytics or background polling.
`npm run build:extension` writes `build/chrome-extension` and checks its CSP,
capabilities and assets. See [Chrome extension](docs/CHROME-EXTENSION.md).

The following tracked documents continue this guide. Read the relevant one
when its trigger applies; unrelated tasks do not require them. Skills remain
optional and cannot override this guide's architecture, checks, locales or
release gates. No rule, plan or script may depend on locally installed skills.

| Task | Required instructions |
|---|---|
| Desktop channels, signing, packaging, versions, release CI, store listings/media or release download counts | [Releases](docs/agent-guides/releases.md) |
| Select, use or install a repository skill | [Skills](docs/agent-guides/skills.md) |

## Privacy and product boundaries

- Local-first: hours, salary and preferences stay on-device by default.
  The approved 2026-09-05 plan 015 exception permits preferences and career
  salary history in opt-in private CloudKit sync and user-triggered backups.
  No product accounts; no salary in widgets, URLs, analytics or share metadata.
- The approved 2026-10-04 Android exception permits Play purchase tokens and
  product IDs to reach `api.doneat.app` (Cloudflare Worker/D1) for Google
  verification. Store only hashed tokens and entitlement state; no salary,
  schedules, records or product accounts. Keep secrets out of Git/APKs and
  signed receipts out of backups. Activation requires the service runbook
  and matching published privacy disclosures.
- The approved 2026-10-16 review-access exception separately permits an
  optional reusable review credential, a random installation public key and its
  hash, renewal-secret hash, challenge proof and grant timing/revision/revocation
  metadata at the existing `api.doneat.app` Worker/D1 service. Use these only
  for review authentication and abuse prevention, never analytics, advertising
  or linkage to Play orders. No Google sign-in, Gmail, hardware IDs, salary,
  schedules, records or product accounts. Keep raw credentials, private keys,
  renewal secrets and grant bodies out of database/logs/backups. Signed grants
  last at most 24 hours; daily cleanup removes expired challenges and installation
  sessions seven days after their last renewal. Reusable credential hashes remain
  until owner rotation/revocation; the seven-day limit does not expire the code.
  Review authorization is distinct from Play purchases. Production activation
  requires isolated validation and matching published privacy/Data safety
  disclosures; design approval does not authorize deployment or publication.
- The approved 2026-10-18 plan 021 exception permits opt-in Plus background
  location for up to 5 user-saved workplaces. Coordinates, SSIDs, geofence
  state, raw events and pending proposals stay on-device and out of backups.
  Only the minimal provenance of adopted work times may join opt-in private
  CloudKit sync and backups. No tracks, Siri/widget location data or new
  servers. Shipping requires the App Store label and official privacy page.
- Share URLs encode only start/end times. Analytics are anonymous aggregate
  event counters: no cookies, identifiers, IP/User-Agent storage or histories.
- The approved 2026-11-12 exception permits Google AdSense (auto ads plus the
  `AdSenseUnit` slot) on the Web build in a browser tab, timer included:
  never `/mini`, an installed PWA, Desktop, the extension or native apps.
  Google's own consent message covers the EEA/UK/CH; hours and salary are never
  passed to ads. Changing this needs the doneat.app privacy/FAQ/About copy.
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
  during sleep without backfilled notifications.
- A running shift is `segments + plannedEndAtMs + overtimeEndAtMs`.
  Remaining time, progress, earnings, lunch gaps and micro-breaks use effective
  segments, never `end - now` or a standalone start/end range. Overtime extends
  the original hourly rate linearly: progress may use extended duration;
  salary uses elapsed effective time / planned effective duration.
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
  density before hand-off. Preserve settled conventions: the shared orange
  accent.
- Desktop is a compact, non-resizable 420–450 px tool: the Web title block
  (brand, localized function line below, each one truncated line), fixed
  footer, settings subpage. Main window and Windows Mini Timer share Web's
  Geist font and `RollingText` digits; the native macOS Mini Timer mirrors it
  in `OWCRollingLabel`. Salary stays in the existing summary card; updater
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

- All user-facing app keys need translations in all 19 locales, preserving
  English placeholders. Web/Desktop use `public/locales/*`, which also holds
  every widget key the macOS and native widgets read (`WidgetCopy` reads
  `translation.json` from the widget extension bundle). Do not drop or rename a
  widget key without the matching native change.
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
- Keep `docs/PLAN-MSSTORE.md` aligned with material
  architecture/milestones; remove stale TODOs when verified.
- Stop `next dev` before a build: it shares `.next` with `next build`.
- In the user's local macOS environment, prefer Xcode MCP when available for
  the macOS widget and other Apple-platform builds; use documented CLI commands
  when MCP is unavailable or unsuitable.

Setup: `npm install`. Common checks: `npm run lint`, `npm test`,
`npm run check:version`. Complete the applicable gates before code hand-off:

| Change | Required validation |
|---|---|
| Any code | Checks proportional to scope |
| Shared rendering, routes, locales or build config | Lint, unit tests, Web build + `check:build:web`, Desktop export + `check:build:desktop` |
| Desktop Rust | Also `cargo fmt --check`, `cargo test`, release build; keep macOS/Windows PR CI (`fmt`, `clippy -- -D warnings`, tests) green |
| Shared rules (`lib/`), widget keys, `src-tauri/macos-widget`, brand icon or `data/holidays` | Also note the native impact in the PR; the native repository verifies it when its submodule moves |
| UI | Real visual inspection on affected OS |
| Any packaging | `npm run check:version`; release guide |

| Target | Development | Build and validation |
|---|---|---|
| Web | `npm run dev` (localhost:3000) | `npm run build`, `npm run check:build:web` |
| Desktop | `npm run tauri:dev` | `npm run build:desktop`, `npm run check:build:desktop`, `npm run tauri:build` (GitHub bundle) |
| Rust | | `cargo test --manifest-path src-tauri/Cargo.toml` |
