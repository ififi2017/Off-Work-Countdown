import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  LOCALES,
  buildAndroidStrings,
  catalogPath,
  checkAndroidStrings,
  escapeResource,
  formatString,
  resourceName,
} from "./generate-android-strings.mjs";

const res = "src-mobile/android/app/src/main/res";
const file = (dir) => `${res}/${dir}/strings_catalog.xml`;
const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
const generated = buildAndroidStrings(catalog, { strings: {} });

/** A catalog with every locale set to `value(id)`. */
function synthetic(entries) {
  const strings = {};
  for (const [key, value] of Object.entries(entries)) {
    strings[key] = {
      localizations: Object.fromEntries(
        LOCALES.map(({ id }) => [id, { stringUnit: { state: "translated", value: typeof value === "function" ? value(id) : value } }])
      ),
    };
  }
  return { sourceLanguage: "en", version: "1.0", strings };
}

function line(xml, name) {
  return xml.split("\n").find((l) => l.includes(`name="${name}"`));
}

describe("Android strings", () => {
  // The iOS catalog is the source; after editing it, run npm run generate:android-strings.
  it("are generated from the current catalog", () => {
    expect(checkAndroidStrings()).toBeNull();
  });

  it("report a hand edit as stale", () => {
    const files = buildAndroidStrings(catalog, JSON.parse(readFileSync("src-mobile/android/app/i18n/android-strings.json", "utf8")));
    files.set(file("values-de"), `${files.get(file("values-de"))}<!-- edited -->`);
    expect(checkAndroidStrings(".", files)).toMatch(/stale[\s\S]*values-de/);
  });

  it("keep the three Chinese variants apart", () => {
    const dirs = ["values-b+zh+Hans+CN", "values-b+zh+Hant+HK", "values-b+zh+Hant+TW"];
    for (const dir of dirs) expect(generated.has(file(dir))).toBe(true);
    const [cn, hk, tw] = dirs.map((dir) => line(generated.get(file(dir)), "liveActivityScheduleNote"));
    expect(new Set([cn, hk, tw]).size).toBe(3);
    expect(hk).toContain("我哋");
    expect(generated.get(`${res}/xml/locales_config.xml`)).toContain('"zh-Hant-HK"');
  });

  it("write the Indic locales under their region and keep Devanagari intact", () => {
    const hi = generated.get(file("values-b+hi+IN"));
    const mr = generated.get(file("values-b+mr+IN"));
    expect(line(hi, "shiftReminders")).toContain("शिफ़्ट रिमाइंडर");
    expect(line(mr, "shiftReminders")).toContain("शिफ्ट स्मरणपत्रे");
  });

  it("give Arabic every plural category it selects and Japanese only the one it has", () => {
    const quantities = (dir) => [...generated.get(file(dir)).split('<plurals name="recordsMonthWorkdays">')[1].split("</plurals>")[0].matchAll(/quantity="(\w+)"/g)].map((m) => m[1]);
    expect(quantities("values-ar")).toEqual(["zero", "one", "two", "few", "many", "other"]);
    expect(quantities("values-ru")).toEqual(["one", "few", "many", "other"]);
    expect(quantities("values-ja")).toEqual(["other"]);
    expect(generated.get(file("values-ar"))).toMatch(/quantity="few">%d /);
  });

  it("number placeholders by English order so reordered translations stay correct", () => {
    const de = line(generated.get(file("values-de")), "cycleEndSummaryNotificationBody");
    expect(de).toMatch(/%1\$s Arbeitstage, %2\$s .* %3\$s /);
    const reordered = buildAndroidStrings(
      synthetic({ span: (id) => (id === "de" ? "Bis {{end}}, ab {{start}} – {{end}}" : "From {{start}} to {{end}}") }),
      { strings: {} }
    );
    expect(line(reordered.get(file("values")), "span")).toContain("From %1$s to %2$s");
    expect(line(reordered.get(file("values-de")), "span")).toContain("Bis %2$s, ab %1$s – %2$s");
    expect(reordered.get("src-mobile/android/app/src/main/kotlin/com/rainif/doneat/l10n/Strings.kt")).toContain(
      "fun span(res: Resources, start: String, end: String): String = res.getString(R.string.span, start, end)"
    );
  });

  it("keep message pools as arrays with their placeholders for the shared rules", () => {
    const en = generated.get(file("values"));
    expect(en).toMatch(/<string-array name="microBreakMessages">\n(\s+<item>[^<]*\{\{minutes\}\}[^<]*<\/item>\n){4}/);
  });

  it("rename keywords reversibly", () => {
    expect(resourceName("continue")).toBe("continue_");
    expect(resourceName("focusTitle")).toBe("focusTitle");
    const map = JSON.parse(generated.get("src-mobile/android/app/i18n/key-map.json"));
    expect(map.keys.continue.resource).toBe("string/continue_");
    expect(map.keys.microBreakMessages.sourceKeys).toEqual(["microBreakMessages.1", "microBreakMessages.2", "microBreakMessages.3", "microBreakMessages.4"]);
    expect(Object.keys(map.keys)).toHaveLength(Object.keys(catalog.strings).length - 3);
  });

  it("escape what Android resources would otherwise misread", () => {
    expect(escapeResource(`It's "done" & <ok>`)).toBe(`It\\'s \\"done\\" &amp; &lt;ok&gt;`);
    expect(escapeResource("@home")).toBe("\\@home");
    expect(escapeResource("?why")).toBe("\\?why");
    expect(escapeResource(" a  b ")).toBe("\\u0020a\\u0020\\u0020b\\u0020");
    expect(escapeResource("a\\b\nc")).toBe("a\\\\b\\nc");
    expect(formatString("{{percent}}% left", ["percent"])).toBe("%1$s%% left");
    const plain = buildAndroidStrings(synthetic({ ratio: "Ratio (%)" }), { strings: {} });
    expect(line(plain.get(file("values")), "ratio")).toBe('    <string name="ratio" formatted="false">Ratio (%)</string>');
  });

  it("refuse a translation whose placeholders differ from English", () => {
    const lost = synthetic({ greet: (id) => (id === "fr" ? "Bonjour" : "Hello {{name}}") });
    expect(() => buildAndroidStrings(lost, { strings: {} })).toThrow(/greet \(fr\): placeholders differ.*missing: name/);
    const added = synthetic({ greet: (id) => (id === "ja" ? "{{name}} {{time}}" : "Hello {{name}}") });
    expect(() => buildAndroidStrings(added, { strings: {} })).toThrow(/extra: time/);
  });

  it("refuse missing locales, duplicate keys and keys Android cannot name", () => {
    const partial = synthetic({ ok: "OK" });
    delete partial.strings.ok.localizations.th;
    expect(() => buildAndroidStrings(partial, { strings: {} })).toThrow(/ok \(th\): missing translation/);
    const onlyEnglish = Object.fromEntries(LOCALES.map(({ id }) => [id, "x"]));
    expect(() => buildAndroidStrings(synthetic({ ok: "OK" }), { strings: { ok: onlyEnglish } })).toThrow(/repeats a catalog key/);
    const incomplete = { ...onlyEnglish };
    delete incomplete.vi;
    expect(() => buildAndroidStrings(synthetic({}), { strings: { newKey: incomplete } })).toThrow(/newKey \(vi\): missing translation/);
    expect(() => buildAndroidStrings(synthetic({ "bad-key": "x" }), { strings: {} })).toThrow(/cannot become an Android resource name/);
  });

  it("write the Android-only copy for every locale", () => {
    const files = buildAndroidStrings(catalog, JSON.parse(readFileSync("src-mobile/android/app/i18n/android-strings.json", "utf8")));
    for (const { dir } of LOCALES) expect(line(files.get(file(dir)), "allowExactReminders")).toBeTruthy();
    expect(line(files.get(file("values-b+zh+Hant+HK")), "remindersMayBeLate")).toContain("遲幾分鐘");
  });
});
