# Web overtime — 2026-11-05

## Scope

Expose the existing PC overtime workflow on off.rainif.com. The DoneAt brand site is unchanged. Keep `lib/countdown.ts` as the source of truth: extend the last effective segment, preserve planned end and original hourly pay, and reuse all 19 existing UI translations.

- [x] Web overtime entry, shared dialog, adjustment and minute selection.
- [x] Versioned local overtime snapshot, refresh/locale restoration, explicit reset and expiry.
- [x] URL-specific sessions isolated in sessionStorage; own session remains in localStorage. No salary fields in the snapshot or share URL.
- [x] Reminder re-arm and pending old celebration reset when extending.
- [x] Responsive wrapping and distinct accessible time selectors.
- [x] 18 new persistence/rule integration tests; existing countdown and sharing rules reused unchanged.
- [x] macOS in-app browser: own and shared OT, reload, language switch preserving query, isolation, return/reset, ended shift reactivated, daily earnings above original daily amount.
- [x] Browser layout: 19 locales at 390×844 dark; Arabic and long labels at 320×700 light; English desktop at 1280×800. No horizontal overflow in measured pages/dialogs. Screenshot inspection of HK/TW/English; automated DOM geometry for remaining languages, not native-language review.
- [x] Final lint, full tests (57 files / 697 tests), Web build/output and Desktop export/output checks passed using Node 24.
- [ ] GitHub PR and Vercel preview verification.
- [ ] Merge and production verification.

## Persistence behavior

Only an explicitly extended Web shift resumes automatically. The snapshot keeps absolute segments and original configured clock times. A completed same-day result stays adjustable until local midnight following its planned end; overtime crossing that boundary remains recoverable until its actual end. Invalid, mismatched or expired snapshots are discarded. Storage denial falls back to the in-memory countdown. URL runs are scoped by original shift times and do not overwrite the visitor’s own OT session. Returning clears the current source only. Ordinary Web timer behavior is preserved.

## Validation limits

Cross-midnight and clock rollback are deterministic unit tests; no device clock was changed. Mobile layout was tested in a desktop browser viewport, not on physical iOS/Android devices. No native business rules or translation catalogs changed; no native app release is included.
