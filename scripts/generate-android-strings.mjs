import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Android task T05. Android reads its copy through the resource system, so the
// iOS catalog is converted at development time into native strings, arrays and
// plurals for all 19 locales; no catalog or translation engine ships in the APK.
// Android-only copy lives in src-mobile/android/app/i18n/android-strings.json.
//
// Conversions, each checked here rather than trusted:
// - `{{name}}` becomes a positional `%N$s`, numbered by first appearance in
//   English, so a translation that reorders its placeholders keeps them apart;
//   every occurrence is replaced, as NativeLocalizer does.
// - `key.1`, `key.2`, … (the catalog's message pools) become one string-array.
//   Pool items keep `{{name}}` verbatim: the shared rules substitute it
//   themselves (e.g. `microBreakMessages` in ReminderRules).
// - Plural variations become <plurals>; `%lld`/`%@` become `%d`/`%s`, with
//   exactly the locale's CLDR categories (missing ones filled from `other`).
// - A key that is not a valid resource name (a Java or Kotlin keyword) gets a
//   trailing underscore; key-map.json records every mapping so it is reversible.

export const catalogPath = "src-mobile/ios/App/App/Localizable.xcstrings";
export const androidOnlyPath = "src-mobile/android/app/i18n/android-strings.json";
const resRoot = "src-mobile/android/app/src/main/res";
const keyMapPath = "src-mobile/android/app/i18n/key-map.json";
const accessorPath = "src-mobile/android/app/src/main/kotlin/com/rainif/doneat/l10n/Strings.kt";
const resourceFile = "strings_catalog.xml";

/** Catalog locale → Android resource directory and the BCP 47 tag for locales_config. */
export const LOCALES = [
  { id: "en", dir: "values", tag: "en" },
  { id: "ar", dir: "values-ar", tag: "ar" },
  { id: "de", dir: "values-de", tag: "de" },
  { id: "es", dir: "values-es", tag: "es" },
  { id: "fr", dir: "values-fr", tag: "fr" },
  { id: "hi-IN", dir: "values-b+hi+IN", tag: "hi-IN" },
  // Android keeps Indonesian under its legacy code `in`, for resources and locales_config alike.
  { id: "id", dir: "values-in", tag: "in" },
  { id: "it", dir: "values-it", tag: "it" },
  { id: "ja", dir: "values-ja", tag: "ja" },
  { id: "ko", dir: "values-ko", tag: "ko" },
  { id: "mr-IN", dir: "values-b+mr+IN", tag: "mr-IN" },
  // Portuguese stays `pt`: the catalog is not a pt-BR translation.
  { id: "pt", dir: "values-pt", tag: "pt" },
  { id: "ru", dir: "values-ru", tag: "ru" },
  { id: "th", dir: "values-th", tag: "th" },
  { id: "tr", dir: "values-tr", tag: "tr" },
  { id: "vi", dir: "values-vi", tag: "vi" },
  { id: "zh-CN", dir: "values-b+zh+Hans+CN", tag: "zh-Hans-CN" },
  // Hong Kong and Taiwan keep their own wording; they are never merged into one zh-Hant.
  { id: "zh-HK", dir: "values-b+zh+Hant+HK", tag: "zh-Hant-HK" },
  { id: "zh-TW", dir: "values-b+zh+Hant+TW", tag: "zh-Hant-TW" },
];

const RESERVED = new Set(
  (
    "abstract as assert boolean break byte case catch char class const continue default do double else enum " +
    "extends false final finally float for fun goto if implements import in instanceof int interface is long " +
    "native new null object package private protected public return short static strictfp super switch " +
    "synchronized this throw throws transient true try typealias typeof val var void volatile when while"
  ).split(" ")
);

const PLACEHOLDER = /\{\{(\w+)\}\}/g;

class AndroidStringsError extends Error {}

function fail(message) {
  throw new AndroidStringsError(message);
}

function names(value) {
  return [...value.matchAll(PLACEHOLDER)].map((m) => m[1]);
}

function unique(list) {
  return [...new Set(list)];
}

/** Characters XML 1.0 cannot carry at all. */
function assertXmlSafe(value, where) {
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/.test(value)) fail(`${where}: contains a character XML cannot hold`);
}

/**
 * Android string-resource escaping: backslash, both quotes, newline and tab are
 * backslash escapes; &, < and > are entities; a leading @ or ? would be read as
 * a reference; and aapt2 collapses runs of spaces and trims the ends, so those
 * spaces are written as \u0020.
 */
export function escapeResource(value) {
  let text = value
    .replace(/\\/g, "\\\\")
    .replace(/'/g, "\\'")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\t/g, "\\t")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  text = text.replace(/^ +| +$| {2,}/g, (spaces) => "\\u0020".repeat(spaces.length));
  if (/^[@?]/.test(text)) text = `\\${text}`;
  return text;
}

/** A catalog string with named placeholders as a positional Android format string. */
export function formatString(value, params) {
  let text = escapeResource(value);
  if (params.length === 0) return text;
  text = text.replace(/%/g, "%%");
  return text.replace(PLACEHOLDER, (_, name) => `%${params.indexOf(name) + 1}$s`);
}

function pluralFormat(value, where) {
  const converted = value.replace(/%(\d+\$)?lld/g, "%$1d").replace(/%(\d+\$)?@/g, "%$1s");
  const tokens = converted.match(/%(\d+\$)?[ds]/g) ?? [];
  if (/%(?!(\d+\$)?[ds])/.test(converted)) fail(`${where}: unsupported format token in "${value}"`);
  return { text: escapeResource(converted), tokens };
}

export function resourceName(key) {
  const name = RESERVED.has(key) ? `${key}_` : key;
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) fail(`"${key}" cannot become an Android resource name`);
  return name;
}

function unitValue(localization, where) {
  const unit = localization?.stringUnit;
  if (!unit || typeof unit.value !== "string") fail(`${where}: missing translation`);
  if (unit.state && unit.state !== "translated") fail(`${where}: state is "${unit.state}"`);
  if (unit.value.length === 0) fail(`${where}: empty translation`);
  return unit.value;
}

/** Reads both sources into one model: key → {kind, comment, values by locale}. */
export function readSources(catalog, androidOnly) {
  const entries = new Map();
  const add = (key, entry) => {
    if (entries.has(key)) fail(`"${key}" is defined twice`);
    entries.set(key, entry);
  };
  const pools = new Map();
  for (const [key, source] of Object.entries(catalog.strings)) {
    const pool = /^(.+)\.(\d+)$/.exec(key);
    if (pool) {
      if (!pools.has(pool[1])) pools.set(pool[1], []);
      pools.get(pool[1]).push({ index: Number(pool[2]), source, key });
      continue;
    }
    const en = source.localizations?.en;
    if (en?.variations) {
      if (!en.variations.plural) fail(`${key}: only plural variations are supported`);
      const values = {};
      for (const { id } of LOCALES) {
        const plural = source.localizations?.[id]?.variations?.plural;
        if (!plural?.other) fail(`${key} (${id}): missing plural "other"`);
        values[id] = Object.fromEntries(Object.entries(plural).map(([category, loc]) => [category, unitValue(loc, `${key} (${id}, ${category})`)]));
      }
      add(key, { kind: "plural", values });
    } else {
      const values = Object.fromEntries(LOCALES.map(({ id }) => [id, unitValue(source.localizations?.[id], `${key} (${id})`)]));
      add(key, { kind: "string", values });
    }
  }
  for (const [key, items] of pools) {
    if (entries.has(key)) fail(`"${key}" is both a string and a message pool`);
    items.sort((a, b) => a.index - b.index);
    items.forEach((item, i) => {
      if (item.index !== i + 1) fail(`${key}: pool is not numbered 1…n (found .${item.index})`);
    });
    const values = Object.fromEntries(
      LOCALES.map(({ id }) => [id, items.map((item) => unitValue(item.source.localizations?.[id], `${item.key} (${id})`))])
    );
    add(key, { kind: "array", values, sourceKeys: items.map((item) => item.key) });
  }
  for (const [key, source] of Object.entries(androidOnly.strings)) {
    if (entries.has(key)) fail(`Android-only "${key}" repeats a catalog key`);
    const values = {};
    for (const { id } of LOCALES) {
      if (typeof source[id] !== "string" || source[id].length === 0) fail(`Android-only ${key} (${id}): missing translation`);
      values[id] = source[id];
    }
    add(key, { kind: "string", values, androidOnly: true, comment: source.comment });
  }
  return entries;
}

/** Placeholders must match English in every locale: same names, none added or lost. */
function paramsFor(key, entry) {
  if (entry.kind === "string") {
    const params = unique(names(entry.values.en));
    for (const { id } of LOCALES) {
      const found = unique(names(entry.values[id]));
      const missing = params.filter((p) => !found.includes(p));
      const extra = found.filter((p) => !params.includes(p));
      if (missing.length || extra.length) {
        fail(`${key} (${id}): placeholders differ from English (missing: ${missing.join(", ") || "none"}; extra: ${extra.join(", ") || "none"})`);
      }
    }
    return params;
  }
  if (entry.kind === "array") {
    const params = unique(entry.values.en.flatMap(names));
    for (const { id } of LOCALES) {
      const extra = unique(entry.values[id].flatMap(names)).filter((p) => !params.includes(p));
      if (extra.length) fail(`${key} (${id}): placeholders English does not have: ${extra.join(", ")}`);
    }
    return params;
  }
  return ["count"];
}

function pluralCategories(tag) {
  return new Intl.PluralRules(tag).resolvedOptions().pluralCategories;
}

const PLURAL_ORDER = ["zero", "one", "two", "few", "many", "other"];

export function buildAndroidStrings(catalog, androidOnly) {
  const entries = readSources(catalog, androidOnly);
  const keys = [...entries.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const resources = new Map();
  const keyMap = {};
  const byName = new Map();
  for (const key of keys) {
    const entry = entries.get(key);
    const name = resourceName(key);
    if (byName.has(name)) fail(`"${key}" and "${byName.get(name)}" map to the same resource "${name}"`);
    byName.set(name, key);
    const params = paramsFor(key, entry);
    keyMap[key] = {
      resource: `${entry.kind === "plural" ? "plurals" : entry.kind === "array" ? "array" : "string"}/${name}`,
      ...(entry.kind === "string" && params.length ? { params } : {}),
      ...(entry.kind === "array" ? { sourceKeys: entry.sourceKeys, ...(params.length ? { verbatimPlaceholders: params } : {}) } : {}),
      ...(entry.androidOnly ? { androidOnly: true } : {}),
    };
    resources.set(key, { entry, name, params });
  }

  const files = new Map();
  for (const locale of LOCALES) {
    const lines = [];
    for (const key of keys) {
      const { entry, name, params } = resources.get(key);
      const where = `${key} (${locale.id})`;
      if (entry.kind === "string") {
        const value = entry.values[locale.id];
        assertXmlSafe(value, where);
        // A string without arguments is read verbatim, so a literal % is not a format.
        const unformatted = params.length === 0 && value.includes("%") ? ' formatted="false"' : "";
        lines.push(`    <string name="${name}"${unformatted}>${formatString(value, params)}</string>`);
      } else if (entry.kind === "array") {
        lines.push(`    <string-array name="${name}">`);
        for (const item of entry.values[locale.id]) {
          assertXmlSafe(item, where);
          lines.push(`        <item>${escapeResource(item)}</item>`);
        }
        lines.push("    </string-array>");
      } else {
        const values = entry.values[locale.id];
        const english = pluralFormat(entry.values.en.other, `${key} (en)`).tokens.length;
        // Exactly the locale's CLDR categories: one the language never selects
        // (Japanese "one") is dropped, one the catalog omits is filled from "other".
        const categories = [...pluralCategories(locale.id)].sort((a, b) => PLURAL_ORDER.indexOf(a) - PLURAL_ORDER.indexOf(b));
        lines.push(`    <plurals name="${name}">`);
        for (const category of categories) {
          const source = values[category] ?? values.other;
          assertXmlSafe(source, where);
          const { text, tokens } = pluralFormat(source, `${where}, ${category}`);
          if (tokens.length !== english) fail(`${where}, ${category}: ${tokens.length} arguments, English has ${english}`);
          lines.push(`        <item quantity="${category}">${text}</item>`);
        }
        lines.push("    </plurals>");
      }
    }
    const localeAttr = locale.dir === "values" ? ' tools:locale="en"' : "";
    files.set(
      `${resRoot}/${locale.dir}/${resourceFile}`,
      `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by scripts/generate-android-strings.mjs from Localizable.xcstrings and app/i18n/android-strings.json. Do not edit. -->
<resources xmlns:tools="http://schemas.android.com/tools"${localeAttr} tools:ignore="UnusedResources,Typos">
${lines.join("\n")}
</resources>
`
    );
  }

  files.set(
    `${resRoot}/xml/locales_config.xml`,
    `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by scripts/generate-android-strings.mjs. The app's 19 languages, for per-app language settings. -->
<locale-config xmlns:android="http://schemas.android.com/apk/res/android">
${LOCALES.map(({ tag }) => `    <locale android:name="${tag}" />`).join("\n")}
</locale-config>
`
  );

  files.set(keyMapPath, `${JSON.stringify({ generator: "scripts/generate-android-strings.mjs", locales: LOCALES, keys: keyMap }, null, 2)}\n`);
  files.set(accessorPath, accessors(keys.map((key) => resources.get(key))));
  return files;
}

function accessors(resources) {
  const functions = [];
  for (const { entry, name, params } of resources) {
    if (entry.kind === "string" && params.length) {
      for (const p of params) if (RESERVED.has(p)) fail(`${name}: placeholder "${p}" is a Kotlin keyword`);
      const signature = params.map((p) => `${p}: String`).join(", ");
      functions.push(`    fun ${name}(res: Resources, ${signature}): String = res.getString(R.string.${name}, ${params.join(", ")})`);
    } else if (entry.kind === "plural") {
      functions.push(`    fun ${name}(res: Resources, count: Int): String = res.getQuantityString(R.plurals.${name}, count, count)`);
    }
  }
  return `// Generated by scripts/generate-android-strings.mjs. Do not edit.
package com.rainif.doneat.l10n

import android.content.res.Resources
import com.rainif.doneat.R

/**
 * Catalog strings that take arguments. Each parameter keeps its catalog
 * placeholder name, so arguments cannot be passed in the wrong order; plain
 * strings and message pools are read through \`R.string\` and \`R.array\`.
 */
@Suppress("unused", "FunctionName")
object Strings {
${functions.join("\n")}
}
`;
}

function readInputs(root) {
  return [
    JSON.parse(readFileSync(resolve(root, catalogPath), "utf8")),
    JSON.parse(readFileSync(resolve(root, androidOnlyPath), "utf8")),
  ];
}

/** Null when every generated file matches; otherwise what is stale. */
export function checkAndroidStrings(root = ".", files = buildAndroidStrings(...readInputs(root))) {
  const stale = [];
  for (const [path, content] of files) {
    let existing = null;
    try {
      existing = readFileSync(resolve(root, path), "utf8");
    } catch {
      // missing counts as stale
    }
    if (existing !== content) stale.push(path);
  }
  // A locale directory the generator no longer writes must not keep old copy.
  for (const dir of readdirSync(resolve(root, resRoot))) {
    const path = `${resRoot}/${dir}/${resourceFile}`;
    if (!files.has(path)) {
      try {
        readFileSync(resolve(root, path));
        stale.push(`${path} (no longer generated)`);
      } catch {
        // not ours
      }
    }
  }
  const manifest = readFileSync(resolve(root, "src-mobile/android/app/src/main/AndroidManifest.xml"), "utf8");
  if (!manifest.includes('android:localeConfig="@xml/locales_config"')) stale.push("AndroidManifest.xml lacks android:localeConfig");
  return stale.length ? `Android strings are stale. Run: npm run generate:android-strings\n${stale.join("\n")}` : null;
}

export function writeAndroidStrings(root = ".") {
  const files = buildAndroidStrings(...readInputs(root));
  for (const [path, content] of files) {
    mkdirSync(dirname(resolve(root, path)), { recursive: true });
    writeFileSync(resolve(root, path), content);
  }
  return files;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.includes("--check")) {
      const problem = checkAndroidStrings();
      if (problem) {
        console.error(problem);
        process.exit(1);
      }
      console.log("Android strings are up to date.");
    } else {
      const files = writeAndroidStrings();
      console.log(`Wrote ${files.size} files.`);
    }
  } catch (error) {
    if (error instanceof AndroidStringsError) {
      console.error(error.message);
      process.exit(1);
    }
    throw error;
  }
}
