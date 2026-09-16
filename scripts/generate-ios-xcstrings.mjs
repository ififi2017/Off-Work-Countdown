// Builds the iOS String Catalog from public/locales (plan 019 §3, L1).
//
// iOS used to read public/locales/<lang>/translation.json out of the app
// bundle at runtime. The catalog replaces that: Xcode compiles it into one
// Localizable.strings per .lproj, so the 19 JSON files no longer ship.
//
// public/locales stays the source of truth for now. This generator is the
// bridge, and `--check` fails the build when the catalog no longer matches it,
// the same way the schedule-rule fixtures fail when lib/ moves without Swift.
//
// Run: node scripts/generate-ios-xcstrings.mjs [--check]

import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { watchLocalizationKeys } from "./generate-watch-localizations.mjs";

export const iosStringCatalogPath =
  "src-mobile/ios/App/App/Localizable.xcstrings";

const LOCALES_DIRECTORY = "public/locales";
const SOURCE_LANGUAGE = "en";

/// Swift source scanned for the keys iOS actually asks for. The Watch is not
/// scanned: its keys are listed in generate-watch-localizations.mjs, which
/// reads them back out of this catalog.
const SWIFT_ROOTS = ["src-mobile/ios/App/App"];

/// Keys iOS builds at runtime instead of writing out, so no scan can see them.
/// Every prefix here is a deliberate entry, because a family that is missed
/// simply renders its own key name on screen.
///
/// - `focusIcon`: FocusModels.swift does `"focusIcon\(rawValue.capitalized)"`.
const INTERPOLATED_KEY_PREFIXES = ["focusIcon"];

const PLURAL_CATEGORIES = ["zero", "one", "two", "few", "many", "other"];
const PLURAL_SUFFIX = new RegExp(`_(${PLURAL_CATEGORIES.join("|")})$`);

const readTranslation = (locale) =>
  JSON.parse(
    readFileSync(join(LOCALES_DIRECTORY, locale, "translation.json"), "utf8")
  );

export const localeDirectories = () =>
  readdirSync(LOCALES_DIRECTORY, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

export const swiftFiles = (directory) =>
  readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(path);
    return entry.isFile() && entry.name.endsWith(".swift") ? [path] : [];
  });

/// Every string literal in the iOS sources that is also a translation key.
///
/// Matching against the translation file rather than against `t("...")` call
/// sites is what catches the keys held in `switch` bodies — `legendKey`,
/// `sourceKey`, `syncFailureKey` and the rest hand a literal to `t` from a
/// different line, and a call-site scan sees none of them.
export const referencedKeys = (translation) => {
  const known = new Set(Object.keys(translation));
  const found = new Set();
  for (const root of SWIFT_ROOTS) {
    for (const file of swiftFiles(root)) {
      const source = readFileSync(file, "utf8");
      for (const match of source.matchAll(/"([A-Za-z][A-Za-z0-9_]{1,60})"/g)) {
        if (known.has(match[1])) found.add(match[1]);
      }
    }
  }
  for (const key of known) {
    if (INTERPOLATED_KEY_PREFIXES.some((prefix) => key.startsWith(prefix))) {
      found.add(key);
    }
  }
  // No App source names these, but the Watch table is generated from here.
  for (const key of watchLocalizationKeys) {
    if (!known.has(key)) {
      throw new Error(`${key} is listed for the Watch but missing from ${LOCALES_DIRECTORY}.`);
    }
    found.add(key);
  }
  return [...found].sort();
};

const stringUnit = (value) => ({
  stringUnit: { state: "translated", value },
});

/// Foundation only picks a plural variation when the string is formatted with
/// a numeric specifier, so a plural entry has to carry `%lld` where the JSON
/// wrote `{{count}}`. Every other placeholder stays `{{name}}` and is still
/// substituted by the localizer, which is why only plural values go through
/// this. Plan 019 §3: iOS plurals move onto the system's CLDR rules.
const countFormat = (value) => value.replaceAll("{{count}}", "%lld");

/// One catalog entry per key: a plain string, a plural with the variations the
/// JSON actually carries, or one element of a message pool.
const buildEntry = (key, tables, locales, arrayIndex) => {
  const localizations = {};
  for (const locale of locales) {
    const table = tables[locale];
    const base = table[key];
    if (arrayIndex !== undefined) {
      const pool = table[key];
      if (!Array.isArray(pool) || typeof pool[arrayIndex] !== "string") continue;
      localizations[locale] = stringUnit(pool[arrayIndex]);
      continue;
    }
    const variations = {};
    for (const category of PLURAL_CATEGORIES) {
      const value = table[`${key}_${category}`];
      if (typeof value === "string") variations[category] = stringUnit(countFormat(value));
    }
    if (Object.keys(variations).length > 0) {
      // The unsuffixed key is i18next's `other`, and it has to stay that way:
      // only the categories the JSON spells out are emitted, so a locale whose
      // grammar has more forms falls back the way it does today rather than
      // silently gaining an untranslated one.
      if (typeof base === "string") variations.other = stringUnit(countFormat(base));
      localizations[locale] = { variations: { plural: variations } };
      continue;
    }
    if (typeof base === "string") localizations[locale] = stringUnit(base);
  }
  return { extractionState: "manual", localizations };
};

export const createIOSStringCatalog = () => {
  const locales = localeDirectories();
  if (!locales.includes(SOURCE_LANGUAGE)) {
    throw new Error(`${LOCALES_DIRECTORY} has no ${SOURCE_LANGUAGE} locale.`);
  }
  const tables = Object.fromEntries(
    locales.map((locale) => [locale, readTranslation(locale)])
  );
  const source = tables[SOURCE_LANGUAGE];
  const keys = referencedKeys(source);

  const strings = {};
  for (const key of keys) {
    if (PLURAL_SUFFIX.test(key)) continue; // carried as a variation of its base
    const value = source[key];
    if (Array.isArray(value)) {
      // A catalog has no array type. Message pools become numbered keys and
      // the localizer collects them back, so the lengths must agree across
      // locales or a language would quietly lose lines from its pool.
      for (const locale of locales) {
        const pool = tables[locale][key];
        if (!Array.isArray(pool) || pool.length !== value.length) {
          throw new Error(
            `${key} has ${value.length} entries in ${SOURCE_LANGUAGE} but ${
              Array.isArray(pool) ? pool.length : "none"
            } in ${locale}.`
          );
        }
      }
      value.forEach((_, index) => {
        strings[`${key}.${index + 1}`] = buildEntry(key, tables, locales, index);
      });
      continue;
    }
    if (typeof value !== "string") continue;
    strings[key] = buildEntry(key, tables, locales);
  }

  const ordered = Object.fromEntries(
    Object.keys(strings)
      .sort()
      .map((key) => [key, strings[key]])
  );
  return { sourceLanguage: SOURCE_LANGUAGE, strings: ordered, version: "1.0" };
};

export const serializeCatalog = (catalog) =>
  `${JSON.stringify(catalog, null, 2)}\n`;

/// `null` when the file on disk matches, otherwise the reason it does not.
export const checkIOSStringCatalog = (path, catalog) => {
  let existing;
  try {
    existing = readFileSync(path, "utf8");
  } catch {
    return `${path} is missing; run node scripts/generate-ios-xcstrings.mjs`;
  }
  return existing === serializeCatalog(catalog)
    ? null
    : `${path} is stale; run node scripts/generate-ios-xcstrings.mjs`;
};

const isEntryPoint = process.argv[1]?.endsWith("generate-ios-xcstrings.mjs");
if (isEntryPoint) {
  const catalog = createIOSStringCatalog();
  if (process.argv.includes("--check")) {
    const problem = checkIOSStringCatalog(iosStringCatalogPath, catalog);
    if (problem) {
      console.error(problem);
      process.exit(1);
    }
    console.log(
      `${iosStringCatalogPath} is current (${
        Object.keys(catalog.strings).length
      } entries).`
    );
  } else {
    writeFileSync(iosStringCatalogPath, serializeCatalog(catalog));
    console.log(
      `Wrote ${iosStringCatalogPath} with ${
        Object.keys(catalog.strings).length
      } entries across ${localeDirectories().length} locales.`
    );
  }
}
