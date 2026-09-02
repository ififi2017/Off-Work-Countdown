# Off Work Countdown Agent Guide

## Project overview

Off Work Countdown is one product with three delivery targets:

- Web: Next.js 15 App Router, React 19, TypeScript, Tailwind CSS and Serwist.
- Desktop: Tauri v2 using the same exported frontend plus a small Rust/AppKit shell.
- iOS: a native SwiftUI app in `src-mobile/ios`, with a WidgetKit extension.
  It does **not** embed a WebView and does not render any Next.js page. The
  Capacitor shell it replaced is gone; anything still mentioning `cap`,
  `CapApp-SPM` or `capacitor.config` is stale.

The three targets share business rules and translations, never markup. Web and
Desktop share the React tree; iOS reimplements the surface natively and
consumes the same rules through a generated bundle (see below).

The product is local-first. Work hours, salary and preferences stay on the
user's device. Do not add accounts, upload salary data, or place salary values
in URLs, analytics payloads or share metadata.

## Important architecture boundaries

- `lib/countdown.ts` is the source of truth for shift calculations. Rust only
  keeps an absolute running snapshot alive when the WebView is hidden; do not
  create a second implementation of schedule rules in Rust.
- `lib/reminders.ts` is the source of truth for reminder timing and copy. It
  turns a shift into absolute trigger times; Rust only compares them against
  the clock. Do not move milestone, lunch-boundary or micro-break derivation
  back into Rust — that is what the 3.1.6 refactor removed. iOS schedules the
  same list up front, because a phone cannot poll every second.
  `lib/reminders.test.ts` is the acceptance spec for every consumer.
- iOS reaches those rules through `src-mobile/ios/App/App/Resources/CountdownRules.js`,
  generated from `lib/countdown.ts`, `lib/reminders.ts` and `lib/summary.ts` by
  `npm run build:ios-native-rules` and evaluated in JavaScriptCore. Swift only
  feeds it inputs and renders what comes back. **Do not port a rule into Swift**
  — a schedule, summary or salary calculation written twice is two answers, and
  the "This week" row has already shipped disagreeing values that way. If Swift
  needs a value the bundle does not expose, extend the bundle. A port is not
  forbidden forever, but it is gated: `plans/002-records-life-focus.md` sets the
  bar as a measurement, not an expectation, and any port must arrive with the
  TS-generated differential fixtures and an update to this rule in the same
  change. Until that measurement exists, extend the bundle.
- The generated bundle is a build artifact, not source. It is regenerated from
  the TypeScript, so never hand-edit it, and never let a Swift change depend on
  a bundle that was not rebuilt from the current `lib/`.
- Since 3.1, a running shift is `segments + plannedEndAtMs + overtimeEndAtMs`.
  Remaining time, progress and earnings must use effective segment duration;
  never reintroduce `end - now` or a standalone start/end range. Rust may only
  compare and sum the absolute segments prepared by the frontend.
- Web and Desktop are separate build targets selected by `BUILD_TARGET`.
  `npm run build` must preserve middleware and Route Handlers; `npm run
  build:desktop` must produce a static export in `out/` without Web-only APIs.
- Keep standard Next.js Route Handler filenames such as `route.ts`. Vercel's
  output tracing relies on them. Desktop exclusion belongs in the build target
  configuration, not in renamed route files.
- macOS Mini Timer is native AppKit in
  `src-tauri/native-mini/NativeMiniTimer.m`, linked by `src-tauri/build.rs`.
  macOS 26 uses `NSGlassEffectView`; older macOS uses Vibrancy. Do not replace
  it with a WebView or CSS glass effect.
- macOS 3.1 also has an optional WebView floating timer for the standard and
  woodfish skins. It is a separate window from the native menu-bar panel; do
  not merge their window lifecycle or make either one appear automatically in
  release builds.
- Windows uses the lightweight `/[lang]/mini` Desktop page and programmatic
  Tauri window creation. Platform-specific implementations are intentional.

## UI rules

These first six are the default for every target. The platform-specific rules
below them are exceptions that were argued for, not licence to restyle.

- **Default to restraint.** New UI should first look unremarkable for its
  platform, then earn any emphasis it gets. Visual weight is paid for by
  everything else on the screen, so nothing receives it without a reason.
- **Sizing and spacing are judgements, not a spec.** Decide them from the
  surface type, the information density, the platform convention, how often the
  control is used and where it sits in the hierarchy. Do not carry one set of
  numbers across surfaces, and do not enlarge something because it is
  important.
- **Secondary entry points stay out of the visual centre.** Settings, toggles,
  tool buttons, legends, info buttons, expand/collapse and source labels are
  support. They must not compete with the countdown, the calendar or a screen's
  main conclusion.
- **Use the ordinary metaphor for an ordinary function.** Prefer SF Symbols on
  iOS/macOS, the existing `lucide-react` set on Web and Desktop, or the
  industry-standard symbol — never invent an icon for differentiation. A custom
  mark still has to keep the common silhouette, proportion and meaning.
- **Express hierarchy with the cheap tools first:** position, grouping, a
  slight colour shift, a divider, state feedback, and — on pointer devices —
  hover and tooltips. Exaggerated sizes, heavy colour blocks, large radii,
  thick borders, strong shadows, decorative gradients and marketing-page
  layouts are not hierarchy.
- **Compare against the rest of the screen before calling it done.** If the new
  element looks out of place, too large, too heavy, or thins out the
  information density around it, pull it back rather than waiting for review.

These are defaults for new work, not a reason to reopen the design systems
already in place: the Desktop 420-450 px window, the iOS `OWCDesign` 22 pt card
and 14 pt control radii, and the shared orange accent are settled conventions.

- The Desktop main window is a compact tool, not the Web page squeezed into a
  small viewport. Preserve its 420-450 px sizing range, single-line title,
  fixed footer and settings subpage.
- Avoid changes that increase window height when salary or update state is
  shown. Salary belongs in the existing summary card; transient updater state
  belongs inline or in a toast.
- Desktop dropdowns must stay above the fixed footer and scroll internally.
- The macOS Mini Timer is a non-draggable menu-bar panel. The Windows Mini
  Timer remains draggable, remembers position, can stay on top and does not
  occupy the taskbar.
- Both Mini Timers and the main window share one `hideEarnings` value in the
  store. Neither Mini Timer may keep its own local reveal state, and the eye
  icon everywhere shows what the click will do, not the current state.
- Lunch gaps and micro-break schedules are measured only from effective
  `segments`. Overtime pay is a linear extension of the original hourly rate:
  UI progress may use the extended duration, while salary uses elapsed
  effective time divided by the planned effective duration.
- Rust may switch only to a frontend-supplied `nextShift` snapshot. A stale
  next shift crossed entirely during sleep must be discarded without
  backfilled notifications.
- The woodfish tap count and sound preference stay local. The first woodfish
  tap is always silent; do not add bundled or downloaded audio assets.
- `OWC_FORCE_WINDOWS_MINI=1` runs the Windows Mini Timer on macOS so it can be
  reviewed without a Windows machine; it is gated on `debug_assertions` and is
  absent from release builds. Launch with
  `open --env OWC_FORCE_WINDOWS_MINI=1 <app>` — plain `open` drops the
  variable, and running the binary directly loses the bundle identity.
- `?platform=windows` (also `macos`, `other`) on the main window forces
  `desktopPlatform`, so the Windows title bar can be reviewed on macOS with
  `npm run dev:desktop`. Dev builds only — the branch is compiled out of
  release bundles. Windows drops its native title bar at runtime
  (`set_decorations(false)`), because `decorations` is one value for every
  platform in `tauri.conf.json` and macOS needs it for the traffic lights.
- The main window is not resizable. Text selection is off across the app shell
  and the Mini Timer; inputs opt back in through `.select-none input`.
- Verify both light and dark modes and long English labels before considering a
  Desktop UI change complete. Select triggers have fixed widths — the longest
  translated option must fit, not just the English one.

## Internationalization and content

- Product copy must sound like it is serving the user, not judging, lecturing
  or correcting them. Lead with the benefit, acknowledge the user's situation
  and offer a clear next step; keep the tone warm, respectful and peer-level.
- Do not expose implementation trivia as marketing copy or make the user carry
  the product's operational burden. Technical, privacy and security caveats
  should be neutral, specific and actionable. Avoid scolding phrases such as
  "if that matters to you", defensive comparisons, and language that implies
  the user chose incorrectly.
- Review user-facing copy in context, including loading, empty, error, download
  and permission states. A technically accurate sentence is not finished if it
  feels condescending, bureaucratic or written for maintainers instead of the
  person using the product.
- The application UI supports all 19 locales in `public/locales/*`.
  User-facing UI keys must be added to every locale.
- Long-form content pages intentionally support only English and Simplified
  Chinese through `lib/content-locales.ts`. Do not create unreviewed copies for
  all 19 locales.
- Chinese UI variants link to Simplified Chinese content; other locales link to
  English content.
- Desktop startup language follows the OS locale until the user explicitly
  selects and persists a language. That choice governs the in-app UI only.
- OS-level surfaces follow the **system** language, not the in-app choice: the
  app name in Finder/Dock/Launchpad and the macOS menu bar (localized
  `CFBundleName` / `CFBundleDisplayName`), plus the tray menu, macOS application
  menu and About panel (sent from the frontend with `getFixedT(systemLocale)`).
  They belong to the OS shell and should speak the same language as the rest of
  it, so the desktop-menu effect deliberately does not depend on `lang`.
  See `docs/PLAN-MSSTORE.md` 9.7.

## Privacy and analytics

- Share URLs encode only start and end times. Never include salary.
- Analytics are anonymous aggregate event counters. Do not add cookies,
  identifiers, IP/User-Agent storage or individual histories.
- Keep the desktop client local-only except for update traffic, external links
  and user-triggered sharing. The version check runs automatically at launch
  and carries no account, salary or usage data; the installer itself downloads
  only after the user asks. Changing that balance means updating the About
  page copy on the official About page at doneat.app, which states it.

## Agent collaboration

- When the environment supports sub-agents, they may be configured and used
  for concrete, independent subtasks where delegation or parallel work is
  useful. The primary agent remains responsible for planning, coordination,
  reviewing the results and integrating the final change.
- Do not assign the highest-tier model available in the environment to a
  sub-agent. Choose a lower-tier model appropriate to the subtask's complexity.

## Skills

Skills are optional playbooks an agent loads mid-task. They live in
`.agents/skills/` with symlinks in `.claude/skills/`, are recorded in
`skills-lock.json`, and are installed with
`npx skills add <owner>/<repo> --agent claude-code`.

- **All three paths are excluded from git**, so skills exist on one machine
  only. CI, Xcode Cloud and a fresh clone have none of them. Never write a rule
  in this file, in a plan, or in a script that depends on a skill being
  installed.
- **This file wins.** A skill advises; it does not amend the boundaries above.
  The checks a change owes before hand-off, the ban on porting schedule,
  summary or salary rules into Swift, the 19-locale requirement and the release
  gates are not negotiable by a loaded skill.
- Skills run with full agent permissions. Read a `SKILL.md` before its first
  use, and install with `--agent claude-code` rather than `--all` — `--all`
  expands to every supported agent and writes an untracked `agent/skills/`
  copy into the repository root.

| Skill | Reach for it when |
|---|---|
| `write-swift` | Writing or migrating Swift: value types, Swift 6 concurrency and data-race safety, `some` vs `any`, ARC, Swift Testing |
| `swiftui-expert-skill` | Writing or refactoring SwiftUI, and for Instruments `.trace` analysis of hangs and view-update storms. Its default caution about Liquid Glass does not apply here — this app already adopts it |
| `swiftui-pro` | A structured review pass over SwiftUI: deprecated API, view invalidation, data flow, navigation, HIG, accessibility, performance, hygiene |
| `animate` | Building a new animation, in the order that decides whether it feels right. `OWCMotion` already holds this app's curves and durations — extend it rather than inlining new numbers |
| `review-animations` | Judging the motion in a diff |
| `improve-animations` | Auditing motion across a target and producing a plan; read-only, it does not apply fixes. Pairs with plan 001 |
| `emil-design-eng` | UI polish and component-level design judgement, alongside the UI rules above |
| `grill-me` | Pressure-testing a plan or a design decision before it is written down. Plans 007 and 008 were locked that way |
| `ponytail` (+ `-review`, `-audit`, `-debt`, `-gain`, `-help`) | Cutting over-engineering: YAGNI, stdlib before custom code, native before dependencies, deletion before addition |

`ponytail` is a persistent mode, and three of its rules need a local
translation before they fit this repository:

- Its "one runnable check" rule is written for scripts. Here that check belongs
  in `AppTests/*.swift` as Swift Testing — dropping the file in the directory
  is enough, because `AppTests` is a synchronized folder — or in a vitest file
  beside the module. Never an `assert`-based `__main__` block.
- Its "at most three short lines" output rule does not govern commit messages
  or pull request bodies. Those are deliberately long enough here to explain
  the user-visible reason for non-obvious platform work.
- A `ponytail:` comment marking a deliberate shortcut must name the ceiling and
  the upgrade path in plain language, so it still reads correctly to someone
  who has never heard of the skill.

## Development commands

Shared across every target:

```bash
npm install
npm run lint
npm test
npm run check:version
```

`next dev` and `next build` share `.next`. Stop the dev server before running a
build, otherwise the dev server may reference chunks replaced by the build.

## Building each target

`npm run check:version` gates all three: `package.json`, `src-tauri/Cargo.toml`,
`src-tauri/Cargo.lock`, `src-tauri/tauri.conf.json`, the macOS widget project
and the iOS project (`MARKETING_VERSION`, all four build configurations) must
carry the same product version. Run it before any packaging step.

### Web

```bash
npm run dev                 # localhost:3000
npm run build               # keeps middleware and Route Handlers
npm run check:build:web
```

Release is a push to `main`, which triggers CI and the connected deployment.
`npm run deploy:web` is an owner convenience that validates and pushes an
already-committed local `main`; prefer the pull request flow.

### Desktop (Tauri)

```bash
npm run tauri:dev                     # dev shell against the dev server
npm run build:desktop                 # static export into out/
npm run check:build:desktop           # validates that export
npm run tauri:build                   # GitHub-channel bundle
cargo test --manifest-path src-tauri/Cargo.toml
```

Three channels, and the channel is chosen at build time — a bundle built for
one is not valid for another:

| Channel | Frontend | Bundle |
|---|---|---|
| `github` (default) | `npm run build:desktop` | `npm run tauri:build` |
| Microsoft Store | `npm run build:desktop:msstore` | `npm run pack:msix` |
| Mac App Store | `npm run build:desktop:macappstore` | `npm run tauri:build:macappstore` then `npm run pack:macappstore` |

Store channels compile out the updater and the restart plugin; the GitHub
channel compiles out the desktop widget (`docs/PLAN-MSSTORE.md` 9.9 — this is a
product decision, not a gap). macOS GitHub builds are ad-hoc signed on purpose.

Release: `npm run release:desktop -- [version]` requires a clean `main` exactly
equal to `origin/main`, validates, and pushes `desktop-v<version>`. That tag
drives `.github/workflows/release-desktop.yml`, which builds macOS Apple
Silicon, macOS Intel, Windows x64 and Windows ARM64 into a Draft Release.
Inspect the assets, `latest.json` and `latest-cn.json` before publishing.

### Mac App Store (Tauri + WidgetKit)

The store `.app` shares an App Store Connect record and bundle id with iOS
(`com.rainif.offworkcountdown.macappstore`) through Universal Purchase. It is
still a Tauri shell plus a nested WidgetKit `.appex`, not an iOS build.
`npm run tauri:build:macappstore` already passes `--no-default-features`;
omitting that flag produces a GitHub-channel binary even with the store config.

**App Group.** iOS signs `group.com.rainif.offworkcountdown.macappstore`. macOS
App Store validation rejects that string (409). With `OWC_APPLE_TEAM_ID` set,
`build.rs` and `scripts/build-macos-widget.sh` prefix it automatically, so the
signed value is `3GSK5B9S3T.group.com.rainif.offworkcountdown.macappstore`.
Do not copy the iOS entitlements file onto the Mac host. Ad-hoc local packages
strip App Groups entirely (`src-tauri/macappstore/README.md`).

**Profiles.** Widget `distribution` signing needs an explicit Mac App Store
`.provisionprofile`. The host profile can be omitted: `embed-macos-profile.mjs`
then searches `~/Library/Developer/Xcode/UserData/Provisioning Profiles`.
Current owner copies:

| Role | File |
|---|---|
| Host | `~/Downloads/Off_Work_Countdown_macOS_App_Store.provisionprofile` |
| Widget | `~/Downloads/Off_Work_Countdown_Widget_App_Store.provisionprofile` |

Do not use iOS `.mobileprovision` files. The app is signed with **Apple
Distribution**; look up the identity with
`security find-identity -v -p codesigning`. The `.pkg` is signed separately
with **Mac Installer Distribution** (`3rd Party Mac Developer Installer` in
the keychain). `pack:macappstore` must not re-sign the `.app`.

```bash
OWC_WIDGET_SIGNING_MODE=distribution \
OWC_APPLE_TEAM_ID=3GSK5B9S3T \
OWC_WIDGET_PROVISION_PROFILE="$HOME/Downloads/Off_Work_Countdown_Widget_App_Store.provisionprofile" \
OWC_MACOS_PROVISION_PROFILE="$HOME/Downloads/Off_Work_Countdown_macOS_App_Store.provisionprofile" \
APPLE_SIGNING_IDENTITY="Apple Distribution: … (3GSK5B9S3T)" \
npm run tauri:build:macappstore

npm run pack:macappstore
```

After signing, the host entitlement must be the Team ID-prefixed group, not
`group.com.rainif…`:

```bash
codesign -d --entitlements - --xml DoneAt.app \
  | plutil -extract 'com.apple.security.application-groups' xml1 -o - -
```

`embed-macos-profile.mjs` and `pack-macappstore.sh` reject an iOS-style
`group.*` locally. Past upload rejects and the profile/App Group pitfalls are
in `docs/PLAN-MSSTORE.md` 9.11–9.12.

### iOS (native SwiftUI)

**Generate the rules bundle first.** It is not committed, so a fresh clone has
no `CountdownRules.js` and the app fails at runtime with `missingResource`:

```bash
npm run build:ios-native-rules
```

Rerun it after any change to `lib/countdown.ts`, `lib/reminders.ts` or
`lib/summary.ts`. Open the project directly — there is no Capacitor sync step
any more:

```bash
open src-mobile/ios/App/App.xcodeproj
```

Two targets share one App Store Connect record with the macOS build, through
Universal Purchase:

| Target | Scheme | Bundle id |
|---|---|---|
| App | `App` | `com.rainif.offworkcountdown.macappstore` |
| Widget extension | `OffWorkCountdownWidgetsExtension` | `…macappstore.widget` |

Both sign into App Group `group.com.rainif.offworkcountdown.macappstore`, which
carries the salary-free `WidgetSnapshot` projection and nothing else. That
`group.` identifier is iOS-only; the Mac App Store build uses the Team ID
prefix described above.

`App/Native` and `AppTests` are **synchronized folders**
(`PBXFileSystemSynchronizedRootGroup`, project `objectVersion = 77`): Xcode
takes their membership from the file system, so a new Swift file is compiled
as soon as it lands in the directory, and `project.pbxproj` does not change.
Create files in the subfolder that matches their kind — `Native/DesignSystem`,
`Native/Models`, `Native/Services`, `Native/Views` — and do not hand-write
`PBXFileReference` or `PBXBuildFile` entries for anything under them. The
corollary is that a stray file in those directories now builds: a scratch or
backup copy left beside real source will be compiled, not ignored.

Everything else in the project is still an explicit reference, and must be
registered by hand: `AppDelegate.swift`, the localized `InfoPlist.strings`,
`Assets.xcassets`, `Resources/CountdownRules.js`, the `public/locales` folder
reference, `WidgetExtension/`, and the two widget sources shared from
`src-tauri/macos-widget`. One file crosses targets —
`Native/Models/LiveActivityAttributes.swift` is compiled into the widget as
well, through the single `PBXFileSystemSynchronizedBuildFileExceptionSet` in
the project. Anything else that needs to be shared with the widget goes in
that same exception set.

`npm run check:ios` guards the shipping configuration of that project — bundle
ids against Universal Purchase, the SwiftUI entry point, iPhone/iPad
orientations, the App Group both targets share, the embedded widget, Live
Activity support, and the alpha-free 1024×1024 icon. It reads the working tree
directly, so it needs no build and runs on a clean clone. Run it after any
change under `src-mobile/ios`.

Test build on the simulator, headless:

```bash
npm run build:ios-native-rules
npm run check:ios
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

`xcrun simctl list devices available` lists the installed simulators. Install
and launch a built `.app` with `xcrun simctl install <udid> <path>` and
`xcrun simctl launch <udid> com.rainif.offworkcountdown.macappstore`.

TestFlight and App Store builds are archived, not `build`. Bump
`CURRENT_PROJECT_VERSION` (the build number) for every upload — App Store
Connect rejects a repeated build number for the same `MARKETING_VERSION`:

```bash
npm run check:version
npm run build:ios-native-rules
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath build/OffWorkCountdown.xcarchive archive
```

Then distribute from Xcode's Organizer. There is no `ExportOptions.plist` and
no fastlane in the repository, so the export half is deliberately manual — do
not invent an automated path without agreeing on the signing setup first.

GitHub Actions still has no iOS job. The repository is prepared for Xcode Cloud
through `src-mobile/ios/App/ci_scripts/ci_post_clone.sh`, which installs the
Node.js toolchain, generates `CountdownRules.js` and runs `npm run check:ios`
before Xcode builds. The App Store Connect workflow owns branch/path triggers,
the Release archive action and TestFlight distribution; keep
`docs/XCODE-CLOUD.md` aligned with that configuration. Any change touching
`lib/`, `public/locales` or `src-mobile/` must still be built for the simulator
locally before hand-off.

CI compiles Rust for macOS and Windows on every pull request (`cargo fmt
--check`, `cargo clippy -- -D warnings`, `cargo test`). Before that job
existed, a platform-specific Rust break stayed invisible until a release tag
triggered the four-platform build. Keep it green rather than deferring to the
release; the desktop shell is full of per-platform branches that a macOS-only
local check cannot exercise.

Before handing off a code change, run checks proportional to its scope. Any
change touching shared rendering, routes, locales or build configuration must
pass lint, unit tests, Web build validation and Desktop export validation.
Desktop Rust changes must also pass `cargo fmt --check`, `cargo test` and a
release build. UI changes require real visual inspection on the affected OS.

A change to `lib/countdown.ts`, `lib/reminders.ts` or `lib/summary.ts` reaches
all three targets. It must pass `npm test`, and it must be rebuilt into the iOS
bundle (`npm run build:ios-native-rules`) and compiled for the simulator —
otherwise iOS keeps running the previous rules and the divergence surfaces as a
wrong number on a screen rather than as a build failure.

## Version and release rules

- Product versions must match in `package.json`, `package-lock.json`,
  `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, `src-tauri/tauri.conf.json`,
  the macOS widget project and `src-mobile/ios/App/App.xcodeproj`
  (`MARKETING_VERSION`, every build configuration of both targets). Run
  `npm run check:version`.
- `CURRENT_PROJECT_VERSION` in the iOS project is the build number and is
  deliberately **not** tied to the product version. Bump it for every
  TestFlight or App Store upload; App Store Connect rejects a repeated build
  number under the same `MARKETING_VERSION`.
- iOS ships through App Store Connect only — there is no GitHub channel and no
  tag-driven workflow for it. Universal Purchase means iOS and the Mac App
  Store build share one record and one bundle id, so an iOS submission is a
  release of that shared product, not an independent one.
- Store listing media is generated by `scripts/marketing-shots/` and synced
  with `npm run asc:sync` (`docs/APP-STORE-CONNECT-SYNC.md`). Upload
  screenshots and App Previews only for `en-US`, `zh-Hans` and `zh-Hant`; the
  other App Store locales inherit English. Do not upload all 17 locales.
- 1320×2868 iPhone shots use API display type `APP_IPHONE_67` — there is no
  `APP_IPHONE_69`. After replacing shots, delete leftover sets on unused
  display types such as `APP_IPHONE_65`. The Connect UI prefers those leftovers,
  so one locale can look stale while another already shows the new set.
- App Info (name, subtitle, privacy URLs) is shared with the Mac listing. When
  either platform version is in review, App Info is locked; `asc:sync` skips
  those fields. Version-level screenshots and previews on an editable iOS
  version still apply.
- Compose official Apple frames the same way as the site DeviceHero: the frame
  PNG sizes the box, the capture sits in the hole, the frame stacks on top.
  Do not punch bezels or redraw the Dynamic Island. App Previews are
  `IPHONE_67` 886×1920 portrait and must include an audio track (silent stereo
  is fine).
- Normal work uses `feature branch -> pull request -> main`. Do not maintain a
  long-lived Desktop branch.
- Pull request titles must be Conventional Commits: `type(scope): summary`,
  with an optional `!`. `.github/workflows/label-pr.yml` derives the label
  from the prefix — `feat`/`perf` to `enhancement`, `fix` to `bug`, `docs` to
  `documentation` — and `.github/release.yml` groups the changelog by those
  labels and nothing else. Any other prefix (`ci`, `chore`, `refactor`,
  `test`) is deliberately left unlabelled and groups under Other Changes.
  Only the title is read; commit message bodies do not affect grouping, so a
  missing or wrong prefix silently misfiles the entry in the release notes.
- `npm run deploy:web` is an owner convenience command for an already committed
  local `main`. It validates and pushes `main`, triggering CI and the connected
  Web deployment. Prefer the PR flow for ordinary changes.
- `npm run release:desktop -- [version]` requires a clean `main` exactly equal
  to `origin/main`, validates the release and pushes `desktop-v<version>`.
- Desktop tags trigger `.github/workflows/release-desktop.yml`, which builds
  macOS Apple Silicon, macOS Intel, Windows x64 and Windows ARM64 and creates a
  Draft Release. Inspect assets, `latest.json` and `latest-cn.json` before
  publishing it. `latest-cn.json` is the mirror manifest built by the
  `mirror-manifest` job: same signatures, asset URLs rewritten through a
  reverse proxy, used only after a direct download fails. Its absence, or a
  copy whose URLs were not rewritten, silently disables the fallback.
- Never commit updater private keys, passwords, signing certificates or local
  environment files. Only the updater public key belongs in the repository.
- GitHub-channel macOS builds use ad-hoc signing because the project
  deliberately does not purchase Developer ID certificates. Installation
  documentation must explain Gatekeeper and Windows SmartScreen accurately.
  The Mac App Store channel is the exception: it uses Apple Distribution and
  Mac Installer Distribution, as described above.

## Repository hygiene

- Preserve unrelated user changes in a dirty worktree.
- Do not commit generated `.next`, `out`, `src-tauri/target`, service-worker
  output, installers or local environment files.
- Keep `docs/PLAN-MSSTORE.md` and `docs/PLAN-MOBILE.md`
  aligned with material architecture or milestone changes. Remove stale TODOs
  when work is verified.
- The `mirror-manifest` job downloads every release asset to compute its
  SHA-256, so each new Release starts at one download per asset (two for
  `latest.json`). Subtract that before reading the counts as demand.
- Use focused commits and describe the user-visible reason for non-obvious
  platform work in the pull request.
