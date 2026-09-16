import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  appKeyReferences,
  catalogProblems,
  englishProblems,
  iosStringProblems,
  namedKeyProblems,
  sharedKeyProblems,
  widgetKeyProblems,
  widgetKeyReferences,
} from "./check-ios-strings.mjs";

const LOCALES = ["de", "en"];
const unit = (value, state = "translated") => ({ stringUnit: { state, value } });
const plural = (one, other) => ({
  variations: { plural: { one: unit(one), other: unit(other) } },
});
const entry = (localizations) => ({ extractionState: "manual", localizations });
const catalogOf = (strings) => ({ sourceLanguage: "en", strings, version: "1.0" });

const good = () =>
  catalogOf({
    greeting: entry({ en: unit("Hi {{name}}"), de: unit("Hallo {{name}}") }),
    workdays: entry({
      en: plural("%lld workday", "%lld workdays"),
      de: plural("%lld Arbeitstag", "%lld Arbeitstage"),
    }),
    "tips.1": entry({ en: unit("Drink"), de: unit("Trinken") }),
    "tips.2": entry({ en: unit("Walk"), de: unit("Gehen") }),
  });

/// public/locales after L2b: only what Web and Desktop use.
const tables = () => ({
  en: { greeting: "Hi {{name}}", tips: ["Drink", "Walk"] },
  de: { greeting: "Hallo {{name}}", tips: ["Trinken", "Gehen"] },
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

  describe("copy left in English", () => {
    const withIosOnly = (de) => {
      const catalog = good();
      catalog.strings.brand = entry({ en: unit("DoneAt Plus"), de: unit(de) });
      return catalog;
    };

    it("reports iOS-only copy that another locale still shows in English", () => {
      expect(englishProblems(withIosOnly("DoneAt Plus"), tables(), {})).toEqual([
        'brand (de): still reads the English "DoneAt Plus". Translate it, or list it in ' +
          "SAME_AS_ENGLISH_ON_PURPOSE if English is right in that language.",
      ]);
    });

    it("accepts a listed exception and flags the listing once it is stale", () => {
      expect(englishProblems(withIosOnly("DoneAt Plus"), tables(), { brand: ["de"] })).toEqual([]);
      expect(englishProblems(withIosOnly("DoneAt Plus"), tables(), { brand: "*" })).toEqual([]);
      expect(englishProblems(withIosOnly("DoneAt Plus DE"), tables(), { brand: ["de"] })).toEqual([
        "SAME_AS_ENGLISH_ON_PURPOSE lists brand (de), which no longer matches English; remove it.",
      ]);
      expect(englishProblems(good(), tables(), { gone: "*" })).toEqual([
        "SAME_AS_ENGLISH_ON_PURPOSE lists gone, which the catalog does not have; remove it.",
      ]);
    });

    it("leaves shared keys to lib/locales.test.ts", () => {
      const catalog = good();
      catalog.strings.greeting.localizations.de = unit("Hi {{name}}");
      expect(englishProblems(catalog, tables(), {})).toEqual([]);
      expect(englishProblems(good(), tables(), { greeting: ["de"] })).toEqual([
        "SAME_AS_ENGLISH_ON_PURPOSE lists greeting, which Web and Desktop share; list it in lib/locales.test.ts instead.",
      ]);
    });

    it("requires a real singular exactly where the language inflects", () => {
      const catalog = good();
      catalog.strings.workdays.localizations.de = plural("%lld Arbeitstage", "%lld Arbeitstage");
      expect(englishProblems(catalog, tables(), {})).toEqual([
        'workdays (de): the "one" form repeats "other"',
      ]);

      const chinese = catalogOf({
        workdays: entry({
          en: plural("%lld workday", "%lld workdays"),
          "zh-CN": plural("%lld 个工作日", "%lld 个工作日"),
          ja: plural("%lld 日", "%lld 日間"),
          ru: { variations: { plural: { other: unit("%lld дней") } } },
        }),
      });
      expect(englishProblems(chinese, tables(), {})).toEqual([
        'workdays (ja): the "one" form differs from "other", but ja uses one form for every count',
        'workdays (ru): needs a "one" form',
      ]);
    });
  });

  describe("keys shared with Web and Desktop", () => {
    it("accept identical wording, pools included", () => {
      expect(sharedKeyProblems(good(), tables(), {})).toEqual([]);
    });

    it("report a difference nobody declared", () => {
      const catalog = good();
      catalog.strings.greeting.localizations.de = unit("Servus {{name}}");
      catalog.strings["tips.2"].localizations.de = unit("Laufen");
      const problems = sharedKeyProblems(catalog, tables(), {});
      expect(problems).toHaveLength(2);
      expect(problems[0]).toContain('greeting (de): iOS reads "Servus {{name}}" but Web/Desktop read "Hallo {{name}}"');
      expect(problems[1]).toContain('tips.2 (de): iOS reads "Laufen" but Web/Desktop read "Gehen"');
    });

    it("compare a plural against the JSON's suffixed forms", () => {
      const shared = {
        en: { workdays: "{{count}} workdays", workdays_one: "{{count}} workday" },
        de: { workdays: "{{count}} Arbeitstage", workdays_one: "{{count}} Tag" },
      };
      const problems = sharedKeyProblems(good(), shared, {});
      expect(problems).toHaveLength(1);
      expect(problems[0]).toContain('workdays (de, one): iOS reads "{{count}} Arbeitstag"');
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
  });

  describe("keys the code asks for", () => {
    const keysIn = (source) => appKeyReferences(source).map(({ key }) => key);

    it("find keys named in a call, across lines", () => {
      expect(keysIn('Text(text.t(\n    "greeting",\n    values: ["name": name]\n))')).toEqual(["greeting"]);
      expect(keysIn('let pool = text.strings("tips")')).toEqual(["tips"]);
      expect(keysIn('localizer.string("workdays", locale: "de", count: 2)')).toEqual(["workdays"]);
    });

    it("find both branches of a ternary in the key argument only", () => {
      expect(keysIn('text.t(conflict.source == "import" ? "keepIncoming" : "keepCloud")'))
        .toEqual(["keepIncoming", "keepCloud"]);
      expect(keysIn('text.t("greeting", values: ["name": isPad ? "iPad" : "iPhone"])'))
        .toEqual(["greeting"]);
    });

    it("find what a …Key property or function returns, and nothing it compares", () => {
      const source = [
        "var titleKey: String {",
        "    switch self {",
        '    case .work: "recordsWork"',
        '    case .rest: isLong ? "recordsLongRest" : "recordsRest"',
        "    }",
        "}",
        "private func syncFailureKey(_ reason: String) -> String {",
        "    switch reason {",
        '    case "plus": "syncNeedsPlus"',
        '    default: reason == "quota" ? "syncQuota" : "syncFailed"',
        "    }",
        "}",
        'var nameKey: String? { biometry == .faceID ? "biometryFaceID" : nil }',
        'func cacheKey() -> CacheKey { CacheKey(label: "notCopy") }',
      ].join("\n");
      expect(keysIn(source)).toEqual([
        "recordsWork", "recordsLongRest", "recordsRest",
        "syncNeedsPlus", "syncQuota", "syncFailed",
        "biometryFaceID",
      ]);
    });

    it("find …Key: arguments and (key: String) tables, but not defaults keys", () => {
      const source = [
        'Row(titleKey: "plusBenefitCharts", icon: "chart")',
        'defaults.set(true, forKey: "onboardingDone")',
        'Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")',
        "private let samples: [(key: String, icon: FocusTaskIcon)] = [",
        '    ("focusDemoWriting", .writing),',
        '    ("focusDemoLearning", .study)',
        "]",
      ].join("\n");
      expect(keysIn(source)).toEqual(["plusBenefitCharts", "focusDemoWriting", "focusDemoLearning"]);
    });

    it("expand an interpolated family from the enum's declared cases", () => {
      const source = [
        "enum FocusTaskIcon: String {",
        "    case focus",
        "    case work, communication",
        "    var systemName: String {",
        '        switch self { case .focus: "stopwatch" default: "circle" }',
        "    }",
        '    var titleKey: String { "focusIcon\\(rawValue.capitalized)" }',
        "}",
      ].join("\n");
      expect(keysIn(source)).toEqual(["focusIconFocus", "focusIconWork", "focusIconCommunication"]);
    });

    it("find what a …Key constant is assigned, but not a static identifier", () => {
      const source = [
        "let titleKey = switch kind {",
        'case .day: "recordsLockedDay"',
        'case .scale: "recordsLockedScale"',
        "}",
        "let sleepKey = profile?.source == .health",
        '    ? "recordsSleepFromHealth"',
        '    : "recordsSleepEstimated"',
        'let unrelated = "notCopy"',
        'static let logicalKey = "preferences"',
        "var sleepSourceKey: String",
        'var label = "notCopyEither"',
      ].join("\n");
      expect(keysIn(source)).toEqual([
        "recordsLockedDay", "recordsLockedScale", "recordsSleepFromHealth", "recordsSleepEstimated",
      ]);
    });

    it("find a …Key: argument's expression, across lines", () => {
      const source = [
        "Cell(",
        "    sourceKey: input.rulesFailed",
        '        ? "recordsSourceNone"',
        "        : input.source.titleKey,",
        '    anchorDayKey: nil',
        ")",
      ].join("\n");
      expect(keysIn(source)).toEqual(["recordsSourceNone"]);
    });

    it("find the key element of a tuple built in a getter, appends included", () => {
      const source = [
        "private var items: [(symbol: String, key: String)] {",
        "    var rows = [",
        '        ("square.fill", "recordsLegendRecorded"),',
        '        ("pencil", "recordsLegendCorrected"),',
        "    ]",
        '    if includesLock { rows.append(("lock.fill", "recordsLegendLocked")) }',
        "    return rows",
        "}",
        'func row(key: String, icon: String) -> some View { Text("notATuple") }',
      ].join("\n");
      expect(keysIn(source)).toEqual([
        "recordsLegendRecorded", "recordsLegendCorrected", "recordsLegendLocked",
      ]);
    });

    it("find what a same-file helper is handed in its …Key parameter", () => {
      const source = [
        'metric(forecastOnly ? "recordsForecastHours" : "recordsWorkedTime", value)',
        'metric("recordsForecastIncome", money, subtitle: "notCopy")',
        'feature("applewatch", "whatsNewWatchTitle", "whatsNewWatchBody")',
        "private func metric(_ titleKey: String, _ value: String, subtitle: String? = nil) -> some View {",
        "    Text(value)",
        "}",
        "private func feature(_ symbol: String, _ titleKey: String, _ bodyKey: String) -> some View {",
        "    EmptyView()",
        "}",
        'lastError = localize("plusPurchaseUnverified")',
      ].join("\n");
      expect(keysIn(source).sort()).toEqual([
        "plusPurchaseUnverified",
        "recordsForecastHours", "recordsForecastIncome", "recordsWorkedTime",
        "whatsNewWatchBody", "whatsNewWatchTitle",
      ]);
    });

    it("report a key the catalog lacks, with its line, for the App and the Watch", () => {
      const root = mkdtempSync(join(tmpdir(), "ios-strings-"));
      mkdirSync(join(root, "app"));
      mkdirSync(join(root, "watch"));
      writeFileSync(
        join(root, "app", "View.swift"),
        [
          'Text(text.t("greeting", values: ["name": name]))',
          "Button(text.t(",
          '    "missingKey"',
          "))",
          'let pool = text.strings("tips")',
          'let lost = text.strings("gone")',
        ].join("\n")
      );
      writeFileSync(
        join(root, "watch", "Face.swift"),
        ['Text(WatchLocalizations.text("watchListed"))', 'Text(WatchLocalizations.text("watchUnlisted"))'].join("\n")
      );
      const catalog = good();
      catalog.strings.watchListed = catalog.strings.greeting;
      const problems = namedKeyProblems(catalog, {
        appSources: [join(root, "app")],
        watchSources: [join(root, "watch")],
        watchKeys: ["watchListed"],
      }).map((problem) => problem.replace(/^.*\/(\w+\.swift)/, "$1"));
      expect(problems).toEqual([
        'View.swift:3 asks for "missingKey", which Localizable.xcstrings does not have.',
        'View.swift:6 asks for "gone", which Localizable.xcstrings does not have.',
        'Face.swift:2 asks for "watchUnlisted", which scripts/generate-watch-localizations.mjs does not list.',
        "workdays is in Localizable.xcstrings, but no code asks for it in a shape this check can see. " +
          'Delete it if nothing uses it; otherwise ask for it through t("…"), a …Key property, ' +
          "constant or argument, or a key-labelled tuple.",
      ]);
    });

    it("accept a key listed as seen elsewhere, and flag the listing once it is stale", () => {
      const root = mkdtempSync(join(tmpdir(), "ios-strings-"));
      writeFileSync(join(root, "View.swift"), 'text.t("greeting"); text.strings("tips")');
      const options = { appSources: [root], watchSources: [], watchKeys: [] };
      expect(namedKeyProblems(good(), { ...options, unseenOnPurpose: { workdays: "used by …" } })).toEqual([]);
      expect(namedKeyProblems(good(), { ...options, unseenOnPurpose: { workdays: "…", greeting: "…", gone: "…" } })).toEqual([
        "UNSEEN_ON_PURPOSE lists greeting, which is now seen; remove it.",
        "UNSEEN_ON_PURPOSE lists gone, which is not in the catalog; remove it.",
      ]);
    });
  });

  describe("keys the iOS widget renders", () => {
    it("find WidgetCopy lookups, entry labels, label loops and the label mapping", () => {
      const source = [
        'Text(WidgetCopy.text("comingUp", locale: locale))',
        "Text(WidgetCopy.text(entry.labelKey, locale: locale))",
        'entries.append(entry(date: now, label: "offWorkToday", kind: .none))',
        "for (start, end, label) in [",
        '    (a, b, "widgetWorking"),',
        '    (b, c, "overtime"),',
        "] where start < end { }",
        "private func status(_ entry: Entry) -> (symbol: String, labelKey: String)? {",
        "    switch entry.labelKey {",
        '    case "widgetRestDay": ("bed.double.fill", "recordsRestDay")',
        "    default: nil",
        "    }",
        "}",
        "func entry(date: Int64, label: String) -> Entry { Entry(labelKey: label) }",
      ].join("\n");
      expect([...new Set(widgetKeyReferences(source).map(({ key }) => key))].sort()).toEqual([
        "comingUp", "offWorkToday", "overtime", "recordsRestDay", "widgetRestDay", "widgetWorking",
      ]);
    });

    it("report a widget key public/locales no longer has", () => {
      const root = mkdtempSync(join(tmpdir(), "ios-widget-"));
      writeFileSync(join(root, "Widget.swift"), 'Text(WidgetCopy.text("greeting", locale: l))\nText(WidgetCopy.text("iosOnly", locale: l))');
      const problems = widgetKeyProblems(tables(), { sources: [root] })
        .map((problem) => problem.replace(/^.*\/(\w+\.swift)/, "$1"));
      expect(problems).toEqual([
        'Widget.swift:2 gives the widget "iosOnly", which public/locales does not have. ' +
          "The iOS widget reads public/locales through WidgetCopy, so keep the key there.",
      ]);
    });
  });
});
