# Records and Time off redesign (3.2.2): simulator check

Design: the approved canvas "选定方案" (Records calendar A + summary cards B,
and the six Time off screens), handed off on `claude/project-thread-9drz9t`
under `design-handoff/records-leave-3.2.2/`.

Checked on the iPhone 18 Pro simulator (iOS 27), DEBUG build, sample records
from `debugSeedSampleRecords`, mainland China holidays through
`-ios.native.qaHolidayRegion CN`, and the leave planner's deterministic QA search
(`-ios.native.qaLeavePlanner YES`, `-ios.native.qaLeaveScreen setup|plans|dates|detail`).

| Sheet | What it shows |
|---|---|
| [records-light.jpg](2026-10-12-records-leave-322/records-light.jpg) | Plus, light: week (National Day week), month, year, life |
| [records-light-cards.jpg](2026-10-12-records-leave-322/records-light-cards.jpg) | Summary cards for month, year, life, and the pay cards |
| [records-dark.jpg](2026-10-12-records-leave-322/records-dark.jpg) | Plus, dark |
| [records-free.jpg](2026-10-12-records-leave-322/records-free.jpg) | Free: greyed days with one way into Plus, blurred year and life |
| [records-english.jpg](2026-10-12-records-leave-322/records-english.jpg) | English month and cards |
| [leave-light.jpg](2026-10-12-records-leave-322/leave-light.jpg) | Time off home, plan setup, options, all plans, available dates, details |
| [leave-dark.jpg](2026-10-12-records-leave-322/leave-dark.jpg) | The same screens, dark |
| [leave-free.jpg](2026-10-12-records-leave-322/leave-free.jpg) | Free: home and plan setup with the remaining free searches |

The pay cards were rendered with `ImageRenderer` (sample records carry no salary
and the simulator has no Face ID to unlock salary settings).

Known gaps, not in this change:
- Mainland holiday names have no English in the bundled dataset, so English
  shows the Chinese name (existing behaviour).
- The deduction card on the details screen only appears for real balances; the
  QA planner uses synthetic budgets.
