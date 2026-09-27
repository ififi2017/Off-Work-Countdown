# Chrome Web Store listing

The Chrome Web Store API cannot edit the listing, so the description, screenshots
and privacy answers are entered in the Developer Dashboard by hand.
`npm run shots:chrome-web-store` writes one folder per store language, and each
folder holds everything that language needs:

```text
scripts/marketing-shots/chrome-web-store/out/
  <store language>/01-countdown.png … 04-countdown-dark.png
  <store language>/description.txt      paste as-is: plain text, • bullets
  icon-128.png  promo-small-440x280.png  promo-marquee-1400x560.png
```

Every claim in the listing must stay true of the popup: no permissions, no
network requests, no background work, data only in this browser's
`localStorage`. Update the copy in the same change that alters any of them.

## Store listing

**Category:** Productivity → Workflow & Planning. English is the default
listing; add the other 17 languages below as localized listings.

| Store language | Folder | App language |
|---|---|---|
| English (default) | `en` | `en` |
| Chinese (Simplified) | `zh_CN` | `zh-CN` |
| Chinese (Traditional) | `zh_TW` | `zh-TW` |
| Japanese | `ja` | `ja` |
| Korean | `ko` | `ko` |
| German | `de` | `de` |
| French | `fr` | `fr` |
| Spanish | `es` | `es` |
| Italian | `it` | `it` |
| Portuguese (Brazil) | `pt_BR` | `pt` |
| Russian | `ru` | `ru` |
| Hindi | `hi` | `hi-IN` |
| Marathi | `mr` | `mr-IN` |
| Turkish | `tr` | `tr` |
| Arabic | `ar` | `ar` |
| Thai | `th` | `th` |
| Indonesian | `id` | `id` |
| Vietnamese | `vi` | `vi` |

Hong Kong Chinese has no store language of its own; Chrome shows it the
Traditional Chinese listing.

The copy lives in `scripts/marketing-shots/chrome-web-store/listing-copy.mjs`:
four screenshot captions and the description per language, in each language's
existing store voice (German Sie, French vous, Turkish siz, Indonesian Anda),
quoting the app's own button and theme names.

The store title and the summary under it come from the package, not from the
dashboard: the manifest's `name` and `description` read `extensionName` and
`extensionSummary` from `src-extension/copy.json` in every locale. Titles follow
the iOS App Store names (`DoneAt - 下班倒计时`); `short_name` and the toolbar
tooltip stay `DoneAt`. The build rejects titles over 75 characters and summaries
over 132.

## Privacy practices

The dashboard's privacy tab is answered in English.

**Single purpose**

```text
DoneAt shows a countdown to the end of the user's workday in the toolbar popup, with optional estimates of the day's earnings. Everything is calculated locally from the schedule the user enters.
```

**Permission justification:** none. The manifest requests no permissions, host
permissions, content scripts or background worker.

**Remote code:** No, I am not using remote code. All scripts, styles, fonts and
translations are packaged; the CSP limits scripts to the extension itself.

**Data usage:** tick none of the data categories. Schedule, salary and
preferences are kept in the extension's own `localStorage` and never leave the
device; uninstalling removes them. Then certify the three statements (no sale to
third parties, no use unrelated to the single purpose, no use for credit or
lending).

**Privacy policy URL:** `https://doneat.app/en/privacy`. Before the first
submission, confirm that page covers the Chrome extension: it should say the
extension stores data only in the browser and makes no network requests.
