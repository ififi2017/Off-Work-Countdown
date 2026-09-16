import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  catalogProblems,
  iosStringProblems,
  missingNamedKeys,
  sharedKeyProblems,
} from "./check-ios-strings.mjs";

const LOCALES = ["de", "en"];
const unit = (value, state = "translated") => ({ stringUnit: { state, value } });
const plural = (one, other) => ({
  variations: { plural: { one: unit(one), other: unit(other) } },
});
const catalogOf = (strings) => ({ sourceLanguage: "en", strings, version: "1.0" });

const good = () =>
  catalogOf({
    greeting: {
      extractionState: "manual",
      localizations: { en: unit("Hi {{name}}"), de: unit("Hallo {{name}}") },
    },
    workdays: {
      extractionState: "manual",
      localizations: {
        en: plural("%lld workday", "%lld workdays"),
        de: plural("%lld Arbeitstag", "%lld Arbeitstage"),
      },
    },
    "tips.1": { extractionState: "manual", localizations: { en: unit("Drink"), de: unit("Trinken") } },
    "tips.2": { extractionState: "manual", localizations: { en: unit("Walk"), de: unit("Gehen") } },
  });

const tables = () => ({
  en: {
    greeting: "Hi {{name}}",
    workdays: "{{count}} workdays",
    workdays_one: "{{count}} workday",
    tips: ["Drink", "Walk"],
  },
  de: {
    greeting: "Hallo {{name}}",
    workdays: "{{count}} Arbeitstage",
    workdays_one: "{{count}} Arbeitstag",
    tips: ["Trinken", "Gehen"],
  },
});

describe("iOS string catalog checks", () => {
  // The real thing, end to end: `npm test` fails whenever it would.
  it("pass on the shipped catalog", () => {
    expect(iosStringProblems()).toEqual([]);
  }, 60_000);

  describe("completeness", () => {
    it("accepts a complete catalog", () => {
      expect(catalogProblems(good(), LOCALES)).toEqual([]);
    });

    it("reports a missing locale, an empty value and an untranslated state", () => {
      const catalog = good();
      delete catalog.strings.greeting.localizations.de;
      catalog.strings["tips.1"].localizations.de = unit("  ");
      catalog.strings["tips.2"].localizations.de = unit("Gehen", "needs_review");
      expect(catalogProblems(catalog, LOCALES)).toEqual([
        "greeting: missing de",
        "tips.1 (de): is empty",
        "tips.2 (de): state is needs_review, not translated",
      ]);
    });

    it("reports a placeholder that no longer matches English", () => {
      const catalog = good();
      catalog.strings.greeting.localizations.de = unit("Hallo {{user}}");
      expect(catalogProblems(catalog, LOCALES)).toEqual([
        "greeting (de): placeholders {{user}} differ from English {{name}}",
      ]);
    });

    it("reports a plural that lost its count or its other form", () => {
      const catalog = good();
      catalog.strings.workdays.localizations.de = {
        variations: { plural: { one: unit("ein Arbeitstag") } },
      };
      expect(catalogProblems(catalog, LOCALES)).toEqual([
        'workdays: de has no "other" form',
        "workdays (de, one): a plural form needs %lld for Foundation to pick it",
      ]);
    });

    it("reports a gap in a message pool", () => {
      const catalog = good();
      catalog.strings["tips.3"] = catalog.strings["tips.2"];
      delete catalog.strings["tips.2"];
      expect(catalogProblems(catalog, LOCALES)).toEqual(["tips: pool numbers 1,3 are not 1…2"]);
    });

    it("reports a locale the app does not ship", () => {
      const catalog = good();
      catalog.strings.greeting.localizations.xx = unit("?");
      expect(catalogProblems(catalog, LOCALES)).toEqual(["greeting: unexpected locale xx"]);
    });
  });

  describe("keys shared with Web and Desktop", () => {
    it("accept identical wording, including plurals and pools", () => {
      expect(sharedKeyProblems(good(), tables(), {})).toEqual([]);
    });

    it("report a difference nobody declared", () => {
      const catalog = good();
      catalog.strings.greeting.localizations.de = unit("Servus {{name}}");
      catalog.strings.workdays.localizations.de = plural("%lld Tag", "%lld Arbeitstage");
      catalog.strings["tips.2"].localizations.de = unit("Laufen");
      const problems = sharedKeyProblems(catalog, tables(), {});
      expect(problems).toHaveLength(3);
      expect(problems[0]).toContain('greeting (de): iOS reads "Servus {{name}}" but Web/Desktop read "Hallo {{name}}"');
      expect(problems[1]).toContain('workdays (de, one): iOS reads "{{count}} Tag"');
      expect(problems[2]).toContain('tips.2 (de): iOS reads "Laufen" but Web/Desktop read "Gehen"');
    });

    it("accept a declared difference and flag the declaration once it is gone", () => {
      const catalog = good();
      catalog.strings.greeting.localizations.de = unit("Servus {{name}}");
      expect(sharedKeyProblems(catalog, tables(), { greeting: ["de"] })).toEqual([]);
      expect(sharedKeyProblems(good(), tables(), { greeting: ["de"] })).toEqual([
        "INTENTIONAL_DIVERGENCE lists greeting (de), which no longer differs; remove it.",
      ]);
      expect(sharedKeyProblems(good(), tables(), { greeting: "*" })).toEqual([
        "INTENTIONAL_DIVERGENCE lists greeting (*), which no longer differs; remove it.",
      ]);
    });

    it("ignore keys Web and Desktop do not have", () => {
      const catalog = good();
      catalog.strings.iosOnly = {
        extractionState: "manual",
        localizations: { en: unit("Only here"), de: unit("Nur hier") },
      };
      expect(sharedKeyProblems(catalog, tables(), {})).toEqual([]);
    });
  });

  describe("keys the code names", () => {
    const sources = () => {
      const root = mkdtempSync(join(tmpdir(), "ios-strings-"));
      mkdirSync(join(root, "app"));
      mkdirSync(join(root, "watch"));
      writeFileSync(
        join(root, "app", "View.swift"),
        [
          'Text(text.t("greeting", values: ["name": name]))',
          'Button(text.t(',
          '    "missingKey"',
          "))",
          'let pool = text.strings("tips")',
          'let lost = text.strings("gone")',
          'let other = localizer.string("workdays", locale: "de", count: 2)',
          'let chosen = text.t(isPad ? "notSeenHere" : "norThis")',
        ].join("\n")
      );
      writeFileSync(
        join(root, "watch", "Face.swift"),
        [
          'Text(WatchLocalizations.text("watchListed"))',
          'Text(WatchLocalizations.text("watchUnlisted"))',
        ].join("\n")
      );
      return root;
    };

    it("report a named key the catalog lacks, across lines, pools and the Watch", () => {
      const root = sources();
      const catalog = good();
      catalog.strings.watchListed = catalog.strings.greeting;
      const problems = missingNamedKeys(catalog, {
        appSources: [join(root, "app")],
        watchSources: [join(root, "watch")],
        watchKeys: ["watchListed"],
      }).map((problem) => problem.replace(/^.*\/(\w+\.swift)/, "$1"));
      expect(problems).toEqual([
        'View.swift:3 asks for "missingKey", which Localizable.xcstrings does not have.',
        'View.swift:6 asks for "gone", which Localizable.xcstrings does not have.',
        'Face.swift:2 asks for "watchUnlisted", which scripts/generate-watch-localizations.mjs does not list.',
      ]);
    });
  });
});
