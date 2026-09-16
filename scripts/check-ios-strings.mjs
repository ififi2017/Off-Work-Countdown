// Checks on the iOS String Catalog (plan 019 §3, L2a).
//
// Three things the catalog has to keep true however it comes to be edited:
//
// 1. Every entry carries all 19 locales, translated, with English's
//    placeholders — the catalog-side twin of lib/locales.test.ts.
// 2. A key Web and Desktop also ship reads the same in both places, unless
//    the difference is listed in INTENTIONAL_DIVERGENCE (2026-09-13 decision:
//    report every difference so a person decides whether it is deliberate).
// 3. Every key the Swift code asks for by name exists. This is the check that
//    would have stopped `ok`, `recordsConflictKeepCurrent` and
//    `recordsConflictUseOther` from rendering their own names on screen: the
//    generator only carries keys the locale files define, so a key they lack
//    was silently left out instead of reported.
//
// While the catalog is still generated from public/locales, 1 and 2 hold by
// construction. They are in place for L2b, when the catalog becomes the source
// of the iOS copy and nothing else would notice them breaking.
//
// Run: node scripts/check-ios-strings.mjs

import { readFileSync } from "node:fs";
import { join, relative } from "node:path";
import {
  checkIOSStringCatalog,
  createIOSStringCatalog,
  iosStringCatalogPath,
  localeDirectories,
  swiftFiles,
} from "./generate-ios-xcstrings.mjs";
import { watchLocalizationKeys } from "./generate-watch-localizations.mjs";

/// Keys whose iOS wording may differ from Web and Desktop, mapped to the
/// locales that differ ("*" for all). Give each one a reason in a comment.
/// An entry that no longer differs fails the check, so the list cannot rot.
export const INTENTIONAL_DIVERGENCE = {};

const APP_SOURCES = ["src-mobile/ios/App/App"];
const WATCH_SOURCES = ["src-mobile/ios/WatchApp", "src-mobile/ios/WatchWidgets"];
const COUNT_FORMAT = "%lld";
const POOL_KEY = /^(.+)\.(\d+)$/;

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

const isSharedWithWeb = (tables, key) => {
  const pool = key.match(POOL_KEY);
  return pool ? Array.isArray(tables.en?.[pool[1]]) : typeof tables.en?.[key] === "string";
};

const webValue = (tables, locale, key, unitName) => {
  const table = tables[locale] ?? {};
  const pool = key.match(POOL_KEY);
  if (pool) return table[pool[1]]?.[Number(pool[2]) - 1];
  if (unitName && unitName !== "other") return table[`${key}_${unitName}`];
  return table[key];
};

/// 2. Keys Web and Desktop ship too: same wording, or listed as deliberate.
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
        const listed = allowlist[key];
        if (listed === "*" || (Array.isArray(listed) && listed.includes(locale))) continue;
        problems.push(
          `${key} (${locale}${unit.name ? `, ${unit.name}` : ""}): iOS reads ${JSON.stringify(ios)} ` +
            `but Web/Desktop read ${JSON.stringify(web)}. Align them, or list the key in ` +
            "INTENTIONAL_DIVERGENCE if the difference is deliberate."
        );
      }
    }
  }
  for (const [key, listed] of Object.entries(allowlist)) {
    const locales = differing.get(key) ?? new Set();
    const stale = listed === "*"
      ? (locales.size === 0 ? ["*"] : [])
      : listed.filter((locale) => !locales.has(locale));
    for (const locale of stale) {
      problems.push(`INTENTIONAL_DIVERGENCE lists ${key} (${locale}), which no longer differs; remove it.`);
    }
  }
  return problems;
};

const lineOf = (source, index) => source.slice(0, index).split("\n").length;

/// Keys the code names outright, with where it names them.
export const namedKeys = (roots, pattern) => {
  const found = [];
  for (const root of roots) {
    for (const file of swiftFiles(root)) {
      const source = readFileSync(file, "utf8");
      for (const match of source.matchAll(pattern)) {
        // Point at the key itself: in a call spread over lines, the line with
        // `t(` is not the one anyone needs to edit.
        const keyIndex = match.index + match[0].lastIndexOf(`"${match.groups.key}"`);
        found.push({
          key: match.groups.key,
          pool: Boolean(match.groups.pool),
          where: `${relative(process.cwd(), file)}:${lineOf(source, keyIndex)}`,
        });
      }
    }
  }
  return found;
};

/// `t("key"`, `.string("key"` and `strings("key"`, arguments spread over lines
/// included. A key that is chosen by a ternary or a `switch` is not a direct
/// argument and is not seen here; those are what the generator's literal scan
/// is for.
const APP_KEY_CALL =
  /(?:\bt|\.string|\b(?<pool>strings))\(\s*"(?<key>[A-Za-z][A-Za-z0-9_]*)"/g;
const WATCH_KEY_CALL = /WatchLocalizations\.text\(\s*"(?<key>[A-Za-z][A-Za-z0-9_]*)"/g;

/// 3. Every key the code asks for by name exists.
export const missingNamedKeys = (
  catalog,
  { appSources = APP_SOURCES, watchSources = WATCH_SOURCES, watchKeys = watchLocalizationKeys } = {}
) => {
  const problems = [];
  for (const { key, pool, where } of namedKeys(appSources, APP_KEY_CALL)) {
    const present = pool ? `${key}.1` in catalog.strings : key in catalog.strings;
    if (!present) problems.push(`${where} asks for "${key}", which Localizable.xcstrings does not have.`);
  }
  // The Watch reads a generated table, not the catalog, so a key has to be
  // in that table's list as well.
  for (const { key, where } of namedKeys(watchSources, WATCH_KEY_CALL)) {
    if (!watchKeys.includes(key)) {
      problems.push(`${where} asks for "${key}", which scripts/generate-watch-localizations.mjs does not list.`);
    } else if (!(key in catalog.strings)) {
      problems.push(`${where} asks for "${key}", which Localizable.xcstrings does not have.`);
    }
  }
  return problems;
};

export const readLocaleTables = (locales) =>
  Object.fromEntries(
    locales.map((locale) => [
      locale,
      JSON.parse(readFileSync(join("public/locales", locale, "translation.json"), "utf8")),
    ])
  );

export const iosStringProblems = () => {
  const stale = checkIOSStringCatalog(iosStringCatalogPath, createIOSStringCatalog());
  if (stale) return [stale];
  const catalog = JSON.parse(readFileSync(iosStringCatalogPath, "utf8"));
  const locales = localeDirectories();
  return [
    ...catalogProblems(catalog, locales),
    ...sharedKeyProblems(catalog, readLocaleTables(locales)),
    ...missingNamedKeys(catalog),
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
  console.log(`${iosStringCatalogPath} is current, complete and covers every key the code names.`);
}
