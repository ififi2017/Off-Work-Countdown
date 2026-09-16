import { describe, expect, it } from "vitest";
import {
  checkIOSStringCatalog,
  createIOSStringCatalog,
  iosStringCatalogPath,
  localeDirectories,
  referencedKeys,
} from "./generate-ios-xcstrings.mjs";
import { readFileSync } from "node:fs";

const english = JSON.parse(
  readFileSync("public/locales/en/translation.json", "utf8")
);

describe("iOS string catalog", () => {
  // A copy change in public/locales must reach the catalog, or iOS keeps
  // rendering the old wording with nothing to show for it.
  it("matches the current locale files", () => {
    expect(
      checkIOSStringCatalog(iosStringCatalogPath, createIOSStringCatalog())
    ).toBeNull();
  }, 60_000);

  it("carries every locale for a key iOS uses", () => {
    const catalog = createIOSStringCatalog();
    const entry = catalog.strings.aboutProject;
    expect(entry).toBeDefined();
    expect(Object.keys(entry.localizations).sort()).toEqual(localeDirectories());
  });

  // The keys that never appear as a literal: a switch hands them to t() from
  // somewhere else, and a call-site scan would ship the app without them.
  it("includes keys only reachable through a switch or interpolation", () => {
    const catalog = createIOSStringCatalog();
    for (const key of [
      "recordsSourceSchedule", // RecordsCanvasViews.sourceKey
      "lifeLegendChildhood", // LifeView.legendKey
      "syncNeedsPlus", // RecordsSyncSettingsView.syncFailureKey
      "moodHappy", // ShareMood.labelKey
      "focusIconWork", // built as "focusIcon\(rawValue.capitalized)"
    ]) {
      expect(catalog.strings[key], key).toBeDefined();
    }
  });

  it("keeps the plural as variations rather than a suffixed key", () => {
    const catalog = createIOSStringCatalog();
    const germanJSON = JSON.parse(
      readFileSync("public/locales/de/translation.json", "utf8")
    );
    expect(catalog.strings.recordsMonthWorkdays_one).toBeUndefined();
    const german =
      catalog.strings.recordsMonthWorkdays.localizations.de.variations.plural;
    // "1 Arbeitstag" against "%lld Arbeitstage": the singular is the whole
    // reason this key has variations at all. `{{count}}` becomes `%lld` so
    // Foundation can pick the variation; every other placeholder stays as is.
    expect(german.one.stringUnit.value).toBe(
      germanJSON.recordsMonthWorkdays_one.replaceAll("{{count}}", "%lld")
    );
    expect(german.other.stringUnit.value).toBe(
      germanJSON.recordsMonthWorkdays.replaceAll("{{count}}", "%lld")
    );
    expect(german.one.stringUnit.value).toContain("%lld");
    expect(german.one.stringUnit.value).not.toContain("{{count}}");
    expect(german.one.stringUnit.value).not.toBe(german.other.stringUnit.value);
  });

  it("leaves {{placeholders}} alone outside plural variations", () => {
    const catalog = createIOSStringCatalog();
    const value =
      catalog.strings["microBreakMessages.1"].localizations.en.stringUnit.value;
    expect(value).toContain("{{minutes}}");
    expect(value).not.toContain("%lld");
  });

  // A catalog cannot hold an array, so the pools become numbered keys. Losing
  // one line would just shorten the rotation with nothing to notice it.
  it("expands message pools into numbered keys", () => {
    const catalog = createIOSStringCatalog();
    expect(catalog.strings["microBreakMessages.1"]).toBeDefined();
    expect(catalog.strings["microBreakMessages.4"]).toBeDefined();
    expect(catalog.strings["microBreakMessages.5"]).toBeUndefined();
    expect(catalog.strings.microBreakMessages).toBeUndefined();
    // The other pool belongs to the Web timer alone, so it stays out: the
    // catalog carries what iOS asks for, not everything that is an array.
    expect(catalog.strings["notificationToneMessages.1"]).toBeUndefined();
  });

  it("leaves Web-only copy out of the catalog", () => {
    const catalog = createIOSStringCatalog();
    // Landing-page and desktop-tray copy iOS never asks for.
    expect(catalog.strings.landingFeature1Body).toBeUndefined();
    expect(catalog.strings.trayShowApp).toBeUndefined();
  });

  it("only reports keys that exist in the locale files", () => {
    const keys = referencedKeys(english);
    expect(keys.length).toBeGreaterThan(700);
    for (const key of keys) expect(english[key]).toBeDefined();
  });
});
