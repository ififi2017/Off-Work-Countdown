# Optional repository skills

Read when selecting, using or installing a repository skill. Skills advise;
`AGENTS.md` and its applicable guides govern architecture/parity, validation,
19 locales and releases. Skills run with full agent permissions; read the
relevant `SKILL.md` before first use.

Skills live in `.agents/skills/`, symlinked from `.claude/skills/`, and are
recorded in `skills-lock.json`. All three paths are git-excluded and absent in
CI, Xcode Cloud and fresh clones. No rule, plan or script may require them.
Install with `npx skills add <owner>/<repo> --agent claude-code`, never `--all`
(which creates an untracked root `agent/skills/` copy for all supported agents).

Choose only relevant playbooks:

| Task | Skill |
|---|---|
| Write/migrate Swift; values, Swift 6 concurrency, `some` vs `any`, ARC, Swift Testing | `write-swift` |
| Write/refactor SwiftUI; Instruments `.trace` hangs/view-update storms | `swiftui-expert-skill` |
| Review SwiftUI APIs, invalidation, data flow, navigation, HIG, accessibility, performance, hygiene | `swiftui-pro` |
| Build motion using existing `OWCMotion` curves/durations | `animate` |
| Review motion in a diff | `review-animations` |
| Read-only motion audit/implementation plans (plan 001), no fixes | `improve-animations` |
| UI/component polish within project UI rules | `emil-design-eng` |
| Pressure-test plans/designs before writing (as in plans 007/008) | `grill-me` |
| Reduce over-engineering: YAGNI, stdlib/native first, delete before adding | `ponytail` and `-review`, `-audit`, `-debt`, `-gain`, `-help` |

The app already adopts Liquid Glass; `swiftui-expert-skill`'s default caution
does not apply. `ponytail` is persistent, with project-specific overrides:

- Its runnable check belongs in `AppTests/*.swift` (Swift Testing; synchronized
  folder) or a colocated Vitest file, never an assert-based `__main__` block.
- Its three-short-lines limit does not apply to commit messages or PR bodies;
  explain non-obvious platform work's user-visible reason.
- `ponytail:` shortcut comments must state the ceiling and upgrade path in
  plain language understandable without the skill.
