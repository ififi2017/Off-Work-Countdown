# Android 3.2.5 overtime and monthly pay — Pixel check (2026-11-07)

Device: Pixel 10 Pro (USB). Separate debug package `com.rainif.doneat.ot325` (Play source set, Plus debug switch on), so the installed Play, CN and `.cn.debug` apps were not touched. Fresh setup: Mon–Sat 09:00–21:00, test monthly salary 21,000.

| Check | Result |
|---|---|
| Overtime dialog: Until / For how long, rest 30 m, summary 21:30–22:45 · 1 h 15 m | Pass |
| Custom multiplier stepper 1.2×; note follows | Pass |
| Running overtime: "Overtime worked" counts from after the rest; 1.2× note | Pass |
| Adjust reopens with rest and multiplier kept | Pass |
| Unpaid: earnings stay 913.04; 70.44/h, 7.4% lower | Pass |
| Salary: "By monthly schedule · 23" (Nov, US holidays 11/26 excluded), 913.04/workday | Pass |
| Daily pay by month: calendar (Sunday start), Dec 26 / Jan 24 / Feb 23 workdays | Pass |
| Overtime default: Custom stepper, Unpaid | Pass |
| Records: day overtime loads declaration, Save disabled until changed, counted 1 h kept, Count by period shown | Pass |
| Light and dark dialog | Pass after fixes |

Fixed during the check: "This overtime" wrapped mid-word in the dialog (choice now goes under the title when narrow or at large text); dialog cards were invisible in light mode (now `surface` inside the dialog). Not checked: 200% font, other locales, CN-flavour build on device.
