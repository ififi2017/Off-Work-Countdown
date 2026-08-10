# Off Work Countdown Agent Guide

## Project overview

Off Work Countdown is one product with two delivery targets:

- Web: Next.js 15 App Router, React 19, TypeScript, Tailwind CSS and Serwist.
- Desktop: Tauri v2 using the same exported frontend plus a small Rust/AppKit shell.

The product is local-first. Work hours, salary and preferences stay on the
user's device. Do not add accounts, upload salary data, or place salary values
in URLs, analytics payloads or share metadata.

## Important architecture boundaries

- `lib/countdown.ts` is the source of truth for shift calculations. Rust only
  keeps an absolute running snapshot alive when the WebView is hidden; do not
  create a second implementation of schedule rules in Rust.
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
- Windows uses the lightweight `/[lang]/mini` Desktop page and programmatic
  Tauri window creation. Platform-specific implementations are intentional.

## UI rules

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
- `OWC_FORCE_WINDOWS_MINI=1` runs the Windows Mini Timer on macOS so it can be
  reviewed without a Windows machine; it is gated on `debug_assertions` and is
  absent from release builds. Launch with
  `open --env OWC_FORCE_WINDOWS_MINI=1 <app>` — plain `open` drops the
  variable, and running the binary directly loses the bundle identity.
- Verify both light and dark modes and long English labels before considering a
  Desktop UI change complete.

## Internationalization and content

- The application UI supports all 19 locales in `public/locales/*`.
  User-facing UI keys must be added to every locale.
- Long-form content pages intentionally support only English and Simplified
  Chinese through `lib/content-locales.ts`. Do not create unreviewed copies for
  all 19 locales.
- Chinese UI variants link to Simplified Chinese content; other locales link to
  English content.
- Desktop startup language follows the OS locale until the user explicitly
  selects and persists a language. Tray menu labels must update with it.

## Privacy and analytics

- Share URLs encode only start and end times. Never include salary.
- Analytics are anonymous aggregate event counters. Do not add cookies,
  identifiers, IP/User-Agent storage or individual histories.
- Keep the desktop client local-only except for update traffic, external links
  and user-triggered sharing. The version check runs automatically at launch
  and carries no account, salary or usage data; the installer itself downloads
  only after the user asks. Changing that balance means updating the About
  page copy in `public/locales/{en,zh-CN}/content.json`, which states it.

## Development commands

```bash
npm install
npm run dev
npm run tauri:dev
npm run lint
npm test
npm run build
npm run check:build:web
npm run build:desktop
npm run check:build:desktop
npm run check:version
cargo test --manifest-path src-tauri/Cargo.toml
```

`next dev` and `next build` share `.next`. Stop the dev server before running a
build, otherwise the dev server may reference chunks replaced by the build.

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

## Version and release rules

- Product versions must match in `package.json`, `package-lock.json`,
  `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock` and
  `src-tauri/tauri.conf.json`. Run `npm run check:version`.
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
- macOS uses ad-hoc signing because the project deliberately does not purchase
  platform code-signing certificates. Installation documentation must explain
  Gatekeeper and Windows SmartScreen accurately.

## Repository hygiene

- Preserve unrelated user changes in a dirty worktree.
- Do not commit generated `.next`, `out`, `src-tauri/target`, service-worker
  output, installers or local environment files.
- Keep `docs/PLAN-3.0.md` and `docs/PLAN-M5-TAURI.md` aligned with material
  architecture or milestone changes. Remove stale TODOs when work is verified.
- Use focused commits and describe the user-visible reason for non-obvious
  platform work in the pull request.
