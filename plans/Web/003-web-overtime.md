# Web overtime — 2026-11-05

## Scope

Expose the existing PC overtime workflow on off.rainif.com. The DoneAt brand site is unchanged. Keep `lib/countdown.ts` as the source of truth: extend the last effective segment, preserve planned end and original hourly pay, and reuse all 19 existing UI translations.

- [x] Web overtime entry, shared dialog, adjustment and minute selection.
- [x] Versioned local overtime snapshot, refresh/locale restoration, explicit reset and expiry.
- [x] URL-specific sessions isolated in sessionStorage; own session remains in localStorage. No salary fields in the snapshot or share URL.
- [x] Reminder re-arm and pending old celebration reset when extending.
- [x] Responsive wrapping and distinct accessible time selectors.
- [x] 41 new persistence/rule integration tests; existing countdown and sharing rules reused unchanged.
- [x] macOS in-app browser: own and shared OT, reload, language switch preserving query, isolation, return/reset, ended shift reactivated, daily earnings above original daily amount.
- [x] Browser layout: 19 locales at 390×844 dark; Arabic and long labels at 320×700 light; English desktop at 1280×800. No horizontal overflow in measured pages/dialogs. Screenshot inspection of HK/TW/English; automated DOM geometry for remaining languages, not native-language review.
- [x] Final lint, full tests (59 files / 720 tests), Web build/output and Desktop export/output checks after the overnight-start fix.
- [x] GitHub PR #357 and initial Vercel preview verification (2958bd60): HK add overtime and refresh restoration.
- [x] Updated preview verification after the overnight-start fix (bb74ca8a): ended overnight shift, add overtime and reload.
- [ ] Merge and production verification.

- [x] Opening 22:00–06:00 at 07:00 selects the just-ended overnight shift, including shared URLs, so overtime can be added. Day shifts before their start retain the existing validation. Nine regression cases cover this orchestration using existing shared rules.

## Persistence behavior

Only an explicitly extended Web shift resumes automatically. The snapshot keeps absolute segments and original configured clock times. A completed same-day result stays adjustable until local midnight following its planned end; overtime crossing that boundary remains recoverable until its actual end. Invalid, mismatched or expired snapshots are discarded. Storage denial falls back to the in-memory countdown. URL runs are scoped by original shift times and do not overwrite the visitor’s own OT session. Returning clears the current source only. Ordinary Web timer behavior is preserved.

## Validation limits

Cross-midnight and clock rollback are deterministic unit tests; no device clock was changed. Mobile layout was tested in a desktop browser viewport, not on physical iOS/Android devices. No native business rules or translation catalogs changed; no native app release is included.


## Overtime context requested before release

- [x] Below the estimate note, show effective overtime elapsed (seconds included), stopping at the selected overtime end.
- [x] Preserve paid income at the original hourly rate. A separate, explicitly conditional unpaid-overtime comparison shows fixed planned daily pay divided by elapsed effective hours, with the percentage decrease from the original rate.
- [x] Hide salary-derived comparison values with the existing privacy toggle; elapsed overtime remains visible. No salary configured also shows elapsed only.
- [x] Two new Web-only strings translated across all 19 locales. GPT-6.1 Sol High implemented the UI/tests; GPT-6 Luna XHigh supplied translations; the primary agent reviewed and integrated both.
- [x] Added 14 regressions for non-decreasing income when extending/adjusting, independent unpaid comparison, lunch, overnight, end clamping, invalid/zero salary and privacy.
- [x] Local browser proof: extending 02:00 to 03:00 lowered progress about 60.7% → 45.6%, while income continued 179.40 → 179.56. New strings present without raw placeholders or horizontal overflow in all 19 locales at 320×700; HK light/dark at 390×844 visually inspected. Hidden amount removes the rate sentence while retaining elapsed overtime.
- [x] Xcode MCP headless iOS simulator build succeeded (70.4 seconds, no errors); the automatically rewritten unrelated iOS catalog was restored and `check:ios-strings` passed. No iOS visual testing or native release.
- [x] Final Desktop export and output check after the overtime-context additions.
- [ ] Updated cloud preview/release verification for these additions.
