// Checks on the iOS String Catalog (plan 019 §3).
//
// Since L2b, src-mobile/ios/App/App/Localizable.xcstrings is the source of the
// iOS app's copy. It is edited directly — in Xcode's String Catalog editor or
// as JSON — and nothing regenerates it; public/locales keeps only the copy Web
// and Desktop use. These checks are what stands between an edit and a key name
// or an untranslated English string on someone's screen:
//
// 1. Every entry carries all 19 locales, translated, with English's
//    placeholders; plurals and message pools keep the shape the localizer
//    reads.
// 2. Copy only iOS has is not left in English (the catalog-side twin of
//    lib/locales.test.ts, with its own SAME_AS_ENGLISH_ON_PURPOSE), and a
//    plural's singular really differs where the language inflects.
// 3. A key Web and Desktop also ship reads the same in both places, unless
//    INTENTIONAL_DIVERGENCE says the difference is deliberate (2026-09-13
//    decision: report every difference and let a person decide).
// 4. Every key the Swift code asks for exists: named in a call, returned from a
//    `…Key` property or function, passed as a `…Key:` argument, chosen by a
//    ternary inside `t(…)`, listed in a `(key: String, …)` table, or built as
//    `focusIcon<Case>` from the enum that declares the cases. A catalog key
//    no code asks for in one of those shapes is reported too, so dead copy and
//    unsupported shapes both surface.
// 5. Every key the iOS widget renders is still in public/locales: the widget UI
//    shared with the Mac build reads that folder through WidgetCopy.
//
// Run: node scripts/check-ios-strings.mjs

import { readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import { watchLocalizationKeys } from "./generate-watch-localizations.mjs";

export const iosStringCatalogPath = "src-mobile/ios/App/App/Localizable.xcstrings";

/// Keys whose iOS wording may differ from Web and Desktop, mapped to the
/// locales that differ ("*" for all). Give each one a reason in a comment.
/// An entry that no longer differs fails the check, so the list cannot rot.
export const INTENTIONAL_DIVERGENCE = {};

/// iOS-only strings that are meant to read exactly like English in some
/// locales. Shared keys are listed in lib/locales.test.ts instead. Moved here
/// from there in plan 019 L2b, reasons included.
export const SAME_AS_ENGLISH_ON_PURPOSE = {
  // Brand, product and platform names
  plusSection: "*",
  plusSettings: "*",
  plusStatusSubscribed: "*",
  biometryFaceID: "*",
  biometryTouchID: "*",
  biometryOpticID: "*",
  // Layout templates that are only separators and placeholders
  lunchWindow: "*",
  weekdayRange: ["ar", "de", "es", "fr", "hi-IN", "id", "it", "ko", "mr-IN", "pt", "ru", "th", "tr", "vi"],
  daysShort: ["es", "pt"],
  focusPomodoroSummary: ["es", "fr", "it", "pt"],
  // English words these languages use as they are
  focusTitle: ["fr", "it"],
  focusStart: ["de"],
  plusStatus: ["de", "id"],
  notificationCapability: ["de", "id", "pt"],
  // "OK" is the standard affirmative button in these languages; Apple's own
  // localizations use it too
  okAction: ["de", "es", "fr", "id", "it", "ja", "pt", "vi"],
  // "3 × 25 min": these languages abbreviate minutes the way English does
  focusEstimateDetail: ["es", "fr", "it", "pt"],
  // In German a name is a Name
  focusUsualDayName: ["de"],
  // Spanish spells colour the English way
  extendedColor: ["es"],
};

/// Catalog keys that no code asks for in a shape `appKeyReferences` sees, each
/// with where it is really used. Prefer reshaping the code to listing a key.
export const UNSEEN_ON_PURPOSE = {};

/// Languages whose singular differs from the plural. Everyone else has one
/// nominal form, so a separate "one" there would be an invented word.
export const INFLECTS_FOR_ONE = ["en", "de", "es", "fr", "it", "pt", "ru", "hi-IN", "mr-IN"];

const LOCALES_DIRECTORY = "public/locales";
const APP_SOURCES = ["src-mobile/ios/App/App"];
const WATCH_SOURCES = ["src-mobile/ios/WatchApp", "src-mobile/ios/WatchWidgets"];
const WIDGET_SOURCES = [
  "src-tauri/macos-widget/Sources/OffWorkCountdownWidgetUI",
  "src-mobile/ios/App/App/Native/Services/WidgetSnapshotPublisher.swift",
];
const COUNT_FORMAT = "%lld";
const POOL_KEY = /^(.+)\.(\d+)$/;
const KEY = "[A-Za-z][A-Za-z0-9_]*";

/// iOS ships the same 19 languages as Web and Desktop.
export const localeDirectories = () =>
  readdirSync(LOCALES_DIRECTORY, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

export const readLocaleTables = (locales) =>
  Object.fromEntries(
    locales.map((locale) => [
      locale,
      JSON.parse(readFileSync(join(LOCALES_DIRECTORY, locale, "translation.json"), "utf8")),
    ])
  );

const swiftFiles = (directory) =>
  readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(path);
    return entry.isFile() && entry.name.endsWith(".swift") ? [path] : [];
  });

const placeholders = (value) =>
  [...value.matchAll(/{{(\w+)}}/g)].map((match) => match[1]).sort().join(",");

/// A localization's strings: one unnamed unit, or one per plural category.
const units = (localization) => {
  if (localization?.stringUnit) return [{ name: null, ...localization.stringUnit }];
  const plural = localization?.variations?.plural;
  if (!plural) return [];
  return Object.entries(plural).map(([name, variation]) => ({
    name,
    ...(variation?.stringUnit ?? {}),
  }));
};

const isListed = (listed, locale) =>
  listed === "*" || (Array.isArray(listed) && listed.includes(locale));

const staleLocales = (listed, found = new Set()) =>
  listed === "*" ? (found.size === 0 ? ["*"] : []) : listed.filter((locale) => !found.has(locale));

const isSharedWithWeb = (tables, key) => {
  const pool = key.match(POOL_KEY);
  return pool ? Array.isArray(tables.en?.[pool[1]]) : typeof tables.en?.[key] === "string";
};

/// 1. Completeness, state and placeholders, entry by entry.
export const catalogProblems = (catalog, locales) => {
  const problems = [];
  if (catalog.sourceLanguage !== "en") {
    problems.push(`sourceLanguage is ${catalog.sourceLanguage}, expected en`);
  }
  const pools = new Map();
  for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
    const pool = key.match(POOL_KEY);
    if (pool) pools.set(pool[1], [...(pools.get(pool[1]) ?? []), Number(pool[2])]);

    const localizations = entry.localizations ?? {};
    for (const locale of Object.keys(localizations)) {
      if (!locales.includes(locale)) problems.push(`${key}: unexpected locale ${locale}`);
    }
    const plural = Boolean(localizations.en?.variations?.plural);
    const reference = units(localizations.en).find(
      (unit) => unit.name === null || unit.name === "other"
    );
    if (typeof reference?.value !== "string") {
      problems.push(`${key}: has no English value`);
      continue;
    }
    const expected = placeholders(reference.value);

    for (const locale of locales) {
      const found = units(localizations[locale]);
      if (found.length === 0) {
        problems.push(`${key}: missing ${locale}`);
        continue;
      }
      if (plural !== Boolean(localizations[locale]?.variations?.plural)) {
        problems.push(`${key}: ${locale} ${plural ? "is not" : "is"} a plural, unlike English`);
      }
      if (plural && !found.some((unit) => unit.name === "other")) {
        problems.push(`${key}: ${locale} has no "other" form`);
      }
      for (const unit of found) {
        const label = `${key} (${locale}${unit.name ? `, ${unit.name}` : ""})`;
        if (unit.state !== "translated") {
          problems.push(`${label}: state is ${unit.state ?? "missing"}, not translated`);
        }
        if (typeof unit.value !== "string" || unit.value.trim() === "") {
          problems.push(`${label}: is empty`);
          continue;
        }
        const actual = placeholders(unit.value);
        if (actual !== expected) {
          problems.push(`${label}: placeholders {{${actual}}} differ from English {{${expected}}}`);
        }
        if (plural && !unit.value.includes(COUNT_FORMAT)) {
          problems.push(`${label}: a plural form needs ${COUNT_FORMAT} for Foundation to pick it`);
        }
      }
    }
  }
  // Message pools are collected back until the first missing number, so a
  // gap silently truncates the rotation.
  for (const [base, numbers] of pools) {
    const sorted = [...numbers].sort((a, b) => a - b);
    if (sorted.some((number, index) => number !== index + 1)) {
      problems.push(`${base}: pool numbers ${sorted.join(",")} are not 1…${sorted.length}`);
    }
  }
  return problems;
};

/// 2. iOS-only copy left in English, and plurals that do not inflect.
export const englishProblems = (catalog, tables, allowlist = SAME_AS_ENGLISH_ON_PURPOSE) => {
  const problems = [];
  const matching = new Map();
  const strings = catalog.strings ?? {};
  for (const [key, entry] of Object.entries(strings)) {
    // lib/locales.test.ts already holds the copy Web and Desktop share.
    if (isSharedWithWeb(tables, key)) continue;
    const localizations = entry.localizations ?? {};
    const english = new Map(units(localizations.en).map((unit) => [unit.name, unit.value]));
    for (const [locale, localization] of Object.entries(localizations)) {
      if (locale === "en") continue;
      for (const unit of units(localization)) {
        if (typeof unit.value !== "string" || unit.value !== english.get(unit.name)) continue;
        matching.set(key, new Set([...(matching.get(key) ?? []), locale]));
        if (isListed(allowlist[key], locale)) continue;
        problems.push(
          `${key} (${locale}${unit.name ? `, ${unit.name}` : ""}): still reads the English ` +
            `${JSON.stringify(unit.value)}. Translate it, or list it in SAME_AS_ENGLISH_ON_PURPOSE ` +
            "if English is right in that language."
        );
      }
      // "1 Arbeitstage" is what a plural without a real singular renders.
      const plural = localization?.variations?.plural;
      if (!plural || !localizations.en?.variations?.plural) continue;
      const one = plural.one?.stringUnit?.value;
      const other = plural.other?.stringUnit?.value;
      const inflects = INFLECTS_FOR_ONE.includes(locale);
      if (inflects && one === undefined) {
        problems.push(`${key} (${locale}): needs a "one" form`);
      } else if (one !== undefined && (one !== other) !== inflects) {
        problems.push(
          inflects
            ? `${key} (${locale}): the "one" form repeats "other"`
            : `${key} (${locale}): the "one" form differs from "other", but ${locale} uses one form for every count`
        );
      }
    }
  }
  for (const [key, listed] of Object.entries(allowlist)) {
    if (!(key in strings)) {
      problems.push(`SAME_AS_ENGLISH_ON_PURPOSE lists ${key}, which the catalog does not have; remove it.`);
    } else if (isSharedWithWeb(tables, key)) {
      problems.push(`SAME_AS_ENGLISH_ON_PURPOSE lists ${key}, which Web and Desktop share; list it in lib/locales.test.ts instead.`);
    } else {
      for (const locale of staleLocales(listed, matching.get(key))) {
        problems.push(`SAME_AS_ENGLISH_ON_PURPOSE lists ${key} (${locale}), which no longer matches English; remove it.`);
      }
    }
  }
  return problems;
};

const webValue = (tables, locale, key, unitName) => {
  const table = tables[locale] ?? {};
  const pool = key.match(POOL_KEY);
  if (pool) return table[pool[1]]?.[Number(pool[2]) - 1];
  if (unitName && unitName !== "other") return table[`${key}_${unitName}`];
  return table[key];
};

/// 3. Keys Web and Desktop ship too: same wording, or listed as deliberate.
export const sharedKeyProblems = (catalog, tables, allowlist = INTENTIONAL_DIVERGENCE) => {
  const problems = [];
  const differing = new Map();
  for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
    if (!isSharedWithWeb(tables, key)) continue;
    for (const [locale, localization] of Object.entries(entry.localizations ?? {})) {
      for (const unit of units(localization)) {
        // The catalog spells a plural's count as %lld; the JSON as {{count}}.
        const ios = typeof unit.value === "string"
          ? unit.value.replaceAll(COUNT_FORMAT, "{{count}}")
          : unit.value;
        const web = webValue(tables, locale, key, unit.name);
        if (web === undefined || ios === web) continue;
        differing.set(key, new Set([...(differing.get(key) ?? []), locale]));
        if (isListed(allowlist[key], locale)) continue;
        problems.push(
          `${key} (${locale}${unit.name ? `, ${unit.name}` : ""}): iOS reads ${JSON.stringify(ios)} ` +
            `but Web/Desktop read ${JSON.stringify(web)}. Align them, or list the key in ` +
            "INTENTIONAL_DIVERGENCE if the difference is deliberate."
        );
      }
    }
  }
  for (const [key, listed] of Object.entries(allowlist)) {
    for (const locale of staleLocales(listed, differing.get(key))) {
      problems.push(`INTENTIONAL_DIVERGENCE lists ${key} (${locale}), which no longer differs; remove it.`);
    }
  }
  return problems;
};

/// The index of the bracket that closes the one opened just before `start`,
/// or of the first top-level comma when `stopAtComma`. String literals —
/// interpolations included — are skipped.
const scanTo = (source, start, stopAtComma) => {
  let depth = 0;
  let inString = false;
  for (let index = start; index < source.length; index++) {
    const char = source[index];
    if (inString) {
      if (char === "\\") index++;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') inString = true;
    else if ("([{".includes(char)) depth++;
    else if (")]}".includes(char)) {
      if (depth === 0) return index;
      depth--;
    } else if (char === "," && depth === 0 && stopAtComma) return index;
  }
  return source.length;
};

/// The top-level, comma-separated parts of a bracket's contents.
const splitTopLevel = (text) => {
  const parts = [];
  let from = 0;
  for (;;) {
    const end = scanTo(text, from, true);
    parts.push(text.slice(from, end));
    if (end >= text.length || text[end] !== ",") return parts;
    from = end + 1;
  }
};

const LITERAL = new RegExp(`^\\s*"(${KEY})"\\s*$`);

/// What an expression can evaluate to: every identifier-shaped literal in it
/// except `case` patterns, comparison operands and dictionary keys. A colon
/// after a literal ends a pattern or a key — unless the literal is the first
/// branch of a ternary.
const resultLiterals = (text, offset) => {
  const found = [];
  for (const literal of text.matchAll(new RegExp(`"(${KEY})"`, "g"))) {
    const before = text.slice(0, literal.index);
    const after = text.slice(literal.index + literal[0].length);
    if (/\bcase\s+$/.test(before) || /[=!]=\s*$/.test(before)) continue;
    if (/^\s*:/.test(after) && !/\?\s*$/.test(before)) continue;
    found.push({ key: literal[1], index: offset + literal.index });
  }
  return found;
};

const firstArgument = (source, start) => source.slice(start, scanTo(source, start, true));
const block = (source, start) => source.slice(start, scanTo(source, start, false));

/// Tuples in `body` with `arity` elements whose element at `position` is a literal.
const tupleLiterals = (body, offset, arity, position) => {
  const found = [];
  for (let index = 0; index < body.length; index++) {
    if (body[index] !== "(") continue;
    const parts = splitTopLevel(body.slice(index + 1, scanTo(body, index + 1, false)));
    const literal = parts.length === arity ? parts[position].match(LITERAL) : null;
    if (literal) found.push({ key: literal[1], index: offset + index });
  }
  return found;
};

/// A tuple type with a key-named element — `[(key: String, icon: …)] = [`,
/// `var items: [(symbol: String, key: String)] {`, `-> (symbol: String, labelKey: String)? {`
/// — and the literals its initializer or body puts in that element. The
/// bracket must not follow a name, so parameter lists are not tuple types.
const keyedTuples = (source, isKeyName) => {
  const found = [];
  for (const match of source.matchAll(/(?<![\w)])\(([^()]*\w+:\s*String[^()]*)\)\]?\??\s*(?:\{|=\s*\[)/g)) {
    const names = match[1].split(",").map((part) => part.trim().split(/\s*:/)[0].split(/\s+/).pop());
    const position = names.findIndex(isKeyName);
    if (names.length < 2 || position < 0) continue;
    const start = match.index + match[0].length;
    found.push(...tupleLiterals(block(source, start), start, names.length, position));
  }
  // `for (start, end, label) in [ … ]`: the destructured name says which element.
  for (const match of source.matchAll(/\bfor\s+\(([^()]*)\)\s+in\s+\[/g)) {
    const names = match[1].split(",").map((part) => part.trim());
    const position = names.findIndex(isKeyName);
    if (names.length < 2 || position < 0) continue;
    const start = match.index + match[0].length;
    found.push(...tupleLiterals(block(source, start), start, names.length, position));
  }
  return found;
};

const isKeyName = (name) => /^(key|\w*Key)$/.test(name);
const capitalized = (name) => name[0].toUpperCase() + name.slice(1).toLowerCase();

/// Every localization key a Swift source in the App asks for, with the offset
/// it asks at.
export const appKeyReferences = (source) => {
  const found = [];

  // The first argument of `t(…)`, `.string(…)` and `localize(…)`: a literal, or
  // the branches of a ternary. `strings("…")` names a message pool.
  for (const match of source.matchAll(/(?:\bt|\.string|\blocalize)\(/g)) {
    const start = match.index + match[0].length;
    found.push(...resultLiterals(firstArgument(source, start), start));
  }
  for (const match of source.matchAll(new RegExp(`\\bstrings\\(\\s*"(${KEY})"`, "g"))) {
    found.push({ key: match[1], index: match.index, pool: true });
  }

  // Returned from a `…Key` property or function typed String.
  for (const match of source.matchAll(
    /\b(?:var|func)\s+\w*Key\b(?:\s*:\s*String\??|\s*\([^)]*\)\s*->\s*String\??)\s*\{/g
  )) {
    const start = match.index + match[0].length;
    found.push(...resultLiterals(block(source, start), start));
  }

  // Assigned to a `…Key` constant: a `switch` or `if` expression, or a line —
  // with the lines that continue its ternary. A `static` constant names a
  // record or a defaults entry (`logicalKey = "preferences"`), not copy.
  for (const match of source.matchAll(/(?<!\bstatic\s+)\b(?:let|var)\s+\w*Key\b\s*(?::\s*String\??)?\s*=\s*/g)) {
    const start = match.index + match[0].length;
    let end;
    if (/^(?:switch|if)\b/.test(source.slice(start))) {
      end = scanTo(source, source.indexOf("{", start) + 1, false);
    } else {
      end = source.indexOf("\n", start);
      while (end >= 0) {
        const next = source.indexOf("\n", end + 1);
        if (!/^\s*[?:]/.test(source.slice(end + 1, next < 0 ? undefined : next))) break;
        end = next;
      }
      if (end < 0) end = source.length;
    }
    found.push(...resultLiterals(source.slice(start, end), start));
  }

  // Passed as a `…Key:` argument. `forKey:` and friends name defaults and
  // Info.plist entries, and a `var`/`let` is a declaration, not an argument.
  for (const match of source.matchAll(/(?<!\b(?:var|let)\s+)\b(?!for[A-Z])[a-z]\w*Key:\s*/g)) {
    const start = match.index + match[0].length;
    found.push(...resultLiterals(firstArgument(source, start), start));
  }

  // Tables and loops whose element is named `key` or `…Key`.
  found.push(...keyedTuples(source, isKeyName));

  // Helpers in the same file whose parameter is a `…Key: String`, such as
  // `metric(_ titleKey: String, …)`: the argument at that place in every call.
  for (const declaration of source.matchAll(/\bfunc\s+(\w+)\s*\(/g)) {
    const paramsStart = declaration.index + declaration[0].length;
    const keyed = splitTopLevel(block(source, paramsStart)).flatMap((param, position) => {
      const parsed = param.trim().match(/^(?:(\w+)\s+)?(\w+)\s*:\s*String\b/);
      if (!parsed || !isKeyName(parsed[2])) return [];
      return [{ position, label: parsed[1] === "_" ? null : (parsed[1] ?? parsed[2]) }];
    });
    if (keyed.length === 0) continue;
    for (const call of source.matchAll(new RegExp(`(?<!func\\s+)\\b${declaration[1]}\\(`, "g"))) {
      const argsStart = call.index + call[0].length;
      const args = splitTopLevel(block(source, argsStart));
      for (const { position, label } of keyed) {
        const labelled = label && new RegExp(`^\\s*${label}\\s*:`);
        const argument = labelled ? args.find((arg) => labelled.test(arg))?.replace(labelled, "") : args[position];
        if (argument === undefined || (!labelled && /^\s*\w+\s*:(?!:)/.test(argument))) continue;
        found.push(...resultLiterals(argument, argsStart));
      }
    }
  }

  // Built from a case name: `"prefix\(rawValue.capitalized)"` inside the enum
  // that declares those cases.
  for (const match of source.matchAll(/"([A-Za-z][A-Za-z0-9_]*)\\\(rawValue\.capitalized\)"/g)) {
    const declaration = source.slice(source.lastIndexOf("enum ", match.index), match.index);
    for (const cases of declaration.matchAll(/^\s*case\s+([a-z]\w*(?:\s*,\s*[a-z]\w*)*)\s*$/gm)) {
      for (const name of cases[1].split(/\s*,\s*/)) found.push({ key: match[1] + capitalized(name), index: match.index });
    }
  }
  return found;
};

/// Keys the iOS widget can render. They are looked up by `WidgetCopy` in the UI
/// shared with the Mac build, which reads public/locales from the widget's own
/// bundle — so these have to stay in public/locales, not in the catalog.
export const widgetKeyReferences = (source) => {
  const found = [];
  for (const match of source.matchAll(/\bWidgetCopy\.text\(/g)) {
    const start = match.index + match[0].length;
    found.push(...resultLiterals(firstArgument(source, start), start));
  }
  // The label the publisher attaches to a timeline entry, and the labels a
  // widget maps it to.
  for (const match of source.matchAll(/\blabel(?:Key)?:\s*(?!String\b)/g)) {
    const start = match.index + match[0].length;
    found.push(...resultLiterals(firstArgument(source, start), start));
  }
  found.push(...keyedTuples(source, (name) => /^(label|labelKey)$/.test(name)));
  for (const match of source.matchAll(/\bswitch\s+[\w.]*labelKey\s*\{/g)) {
    const start = match.index + match[0].length;
    for (const pattern of block(source, start).matchAll(new RegExp(`\\bcase\\s+"(${KEY})"\\s*:`, "g"))) {
      found.push({ key: pattern[1], index: start + pattern.index });
    }
  }
  return found;
};

const lineOf = (source, index) => source.slice(0, index).split("\n").length;

const referencesIn = (roots, extract) =>
  roots.flatMap((root) =>
    (root.endsWith(".swift") ? [root] : swiftFiles(root)).flatMap((file) => {
      const source = readFileSync(file, "utf8");
      return extract(source).map((reference) => ({
        ...reference,
        where: `${relative(process.cwd(), file)}:${lineOf(source, reference.index)}`,
      }));
    })
  );

/// 4. Every key the code asks for exists, and nothing sits in the catalog that
/// no code asks for.
export const namedKeyProblems = (
  catalog,
  {
    appSources = APP_SOURCES,
    watchSources = WATCH_SOURCES,
    watchKeys = watchLocalizationKeys,
    unseenOnPurpose = UNSEEN_ON_PURPOSE,
  } = {}
) => {
  const strings = catalog.strings ?? {};
  const problems = new Set();
  const asked = new Set(watchKeys);
  for (const { key, pool, where } of referencesIn(appSources, appKeyReferences)) {
    asked.add(key);
    if (pool ? `${key}.1` in strings : key in strings) continue;
    problems.add(`${where} asks for "${key}", which Localizable.xcstrings does not have.`);
  }
  // The Watch reads a table generated from the catalog, so a key has to be on
  // that table's list as well.
  const watchCall = new RegExp(`WatchLocalizations\\.text\\(\\s*"(${KEY})"`, "g");
  const watchReferences = referencesIn(watchSources, (source) =>
    [...source.matchAll(watchCall)].map((match) => ({ key: match[1], index: match.index }))
  );
  for (const { key, where } of watchReferences) {
    if (!watchKeys.includes(key)) {
      problems.add(`${where} asks for "${key}", which scripts/generate-watch-localizations.mjs does not list.`);
    } else if (!(key in strings)) {
      problems.add(`${where} asks for "${key}", which Localizable.xcstrings does not have.`);
    }
  }
  for (const key of new Set(Object.keys(strings).map((name) => name.replace(POOL_KEY, "$1")))) {
    if (asked.has(key) || key in unseenOnPurpose) continue;
    problems.add(
      `${key} is in Localizable.xcstrings, but no code asks for it in a shape this check can see. ` +
        "Delete it if nothing uses it; otherwise ask for it through t(\"…\"), a …Key property, " +
        "constant or argument, or a key-labelled tuple."
    );
  }
  for (const key of Object.keys(unseenOnPurpose)) {
    if (!(key in strings) || asked.has(key)) {
      problems.add(`UNSEEN_ON_PURPOSE lists ${key}, which is ${key in strings ? "now seen" : "not in the catalog"}; remove it.`);
    }
  }
  return [...problems];
};

/// 5. Keys the iOS widget renders exist in public/locales.
export const widgetKeyProblems = (tables, { sources = WIDGET_SOURCES } = {}) => {
  const problems = new Set();
  for (const { key, where } of referencesIn(sources, widgetKeyReferences)) {
    if (typeof tables.en?.[key] === "string") continue;
    problems.add(
      `${where} gives the widget "${key}", which public/locales does not have. ` +
        "The iOS widget reads public/locales through WidgetCopy, so keep the key there."
    );
  }
  return [...problems];
};

export const iosStringProblems = () => {
  let catalog;
  try {
    catalog = JSON.parse(readFileSync(iosStringCatalogPath, "utf8"));
  } catch (error) {
    return [`${iosStringCatalogPath} cannot be read: ${error.message}`];
  }
  const locales = localeDirectories();
  const tables = readLocaleTables(locales);
  return [
    ...catalogProblems(catalog, locales),
    ...englishProblems(catalog, tables),
    ...sharedKeyProblems(catalog, tables),
    ...namedKeyProblems(catalog),
    ...widgetKeyProblems(tables),
  ];
};

const isEntryPoint = process.argv[1]?.endsWith("check-ios-strings.mjs");
if (isEntryPoint) {
  const problems = iosStringProblems();
  if (problems.length > 0) {
    console.error(problems.join("\n"));
    console.error(`\n${problems.length} problem(s) in the iOS string catalog.`);
    process.exit(1);
  }
  console.log(`${iosStringCatalogPath} is complete, translated and covers every key the code asks for.`);
}
