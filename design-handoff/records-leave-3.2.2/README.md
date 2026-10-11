# Records + Leave redesign (3.2.2) — design handoff

Approved by rain on the design canvas https://claude.ai/artifact/KeHHz3y8yESjsrmCxFAmW6 (page "选定方案").

- `Final.dc.html` — Records: calendar A (week / month / year / life) + summary cards B, Chinese.
- `FinalEN.dc.html` — same screens in English.
- `Leave.dc.html` — Leave panel: home, plan setup, results, all plans, available dates, details.
- `canvas.json` — board layout plus the sticky notes (`notes.pick`, `notes.en`, `notes.leave`) that explain each design decision and the states covered.

Each `.dc.html` is HTML + a `renderVals()` script holding the demo data and state logic; open the canvas link to see them rendered and interactive.
This folder is reference material for implementation only; it is not meant to be merged to main.
