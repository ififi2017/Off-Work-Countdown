import Foundation

nonisolated struct NativeLanguage: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// Reads the app's copy out of `Localizable.xcstrings` (plan 019 §3).
///
/// iOS used to parse `public/locales/<lang>/translation.json` from the bundle.
/// The catalog replaces that: Xcode compiles it into one `Localizable.strings`
/// per `.lproj`, so the JSON no longer ships in the app. Since plan 019 L2b the
/// catalog is the source of the iOS copy, and `npm run check:ios-strings`
/// keeps it complete and in step with the keys the code asks for.
///
/// The language is looked up per call rather than through `Bundle.main`,
/// because the app has its own language picker: `Bundle.main` follows the
/// **system** language and would ignore a user who set the app to Japanese on
/// an English phone.
final class NativeLocalizer {
    nonisolated static let supportedLanguages: [NativeLanguage] = [
        .init(id: "en", name: "English"),
        .init(id: "en-GB", name: "English (UK)"),
        .init(id: "zh-CN", name: "简体中文"),
        .init(id: "zh-HK", name: "繁體中文（香港）"),
        .init(id: "zh-TW", name: "繁體中文（台灣）"),
        .init(id: "ja", name: "日本語"),
        .init(id: "ko", name: "한국어"),
        .init(id: "de", name: "Deutsch"),
        .init(id: "es", name: "Español"),
        .init(id: "es-MX", name: "Español (Latinoamérica)"),
        .init(id: "fr", name: "Français"),
        .init(id: "it", name: "Italiano"),
        .init(id: "pt", name: "Português"),
        .init(id: "ru", name: "Русский"),
        .init(id: "ar", name: "العربية"),
        .init(id: "hi-IN", name: "हिन्दी"),
        .init(id: "mr-IN", name: "मराठी"),
        .init(id: "id", name: "Bahasa Indonesia"),
        .init(id: "th", name: "ไทย"),
        .init(id: "tr", name: "Türkçe"),
        .init(id: "vi", name: "Tiếng Việt"),
    ]

    /// A sentinel no translation can equal, so a missing key is distinguishable
    /// from one whose value happens to be its own name.
    private static let missing = "\u{0}owc.missing"

    private var bundles: [String: Bundle] = [:]

    /// `count` is the quantity the sentence is about, not the text that gets
    /// interpolated: it selects which plural variation of `key` to read, and
    /// the caller still passes the displayed number in `values`.
    func string(
        _ key: String,
        locale: String,
        count: Int? = nil,
        values: [String: String] = [:]
    ) -> String {
        let parent = Self.parentLanguage(for: locale)
        var value = lookup(key, locale: locale)
            ?? parent.flatMap { lookup(key, locale: $0) }
            ?? lookup(key, locale: "en")
            ?? key
        if Self.takesACount(value) {
            // A plural entry arrives as the catalog's format token — Foundation
            // hands back `%#@value@`, not the chosen variation — so this call
            // is what resolves it against the locale's CLDR rules.
            //
            // The number can also come in as `values["count"]` with no `count:`
            // of its own, which is how the callers that format the figure
            // themselves ask for it. Before the catalog those callers got the
            // plural template with `{{count}}` substituted; without this they
            // would get the raw format token on screen instead.
            if let resolved = count ?? values["count"].flatMap({ Int($0) }) {
                value = String(format: value, locale: Locale(identifier: locale), resolved)
            }
        }
        return values.reduce(value) { result, pair in
            result.replacingOccurrences(of: "{{\(pair.key)}}", with: pair.value)
        }
    }

    /// A message pool. The catalog has no array type, so the generator writes
    /// `key.1`, `key.2`, … and they are collected back here. A regional
    /// variant fills each missing line from its parent (`en-GB` → `en`,
    /// `es-MX` → `es`) so a partial pool is not cut short. A locale with no
    /// pool at all falls back to English whole.
    func strings(_ key: String, locale: String) -> [String] {
        let localized = pool(key, locale: locale)
        return localized.isEmpty && locale != "en" ? pool(key, locale: "en") : localized
    }

    func languageName(for locale: String) -> String {
        Self.supportedLanguages.first(where: { $0.id == locale })?.name ?? locale
    }

    /// The language the UI should use for these BCP 47 tags, most preferred first.
    ///
    /// `Locale.preferredLanguages` is read before `Bundle.preferredLocalizations`.
    /// The bundle collapses `en-AU` to `en` and `es-AR` to `es` once those
    /// `.lproj` folders exist, which would hide the regional variant.
    ///
    /// English with no region, or US, CA, PH, LR and the US territories, stays
    /// on `en` (American spelling). Any other English region (GB, IE, AU, NZ,
    /// IN, ZA, …) uses `en-GB`. Spanish whose CLDR parent is `es-419` — MX, AR,
    /// CO, CL, PE, US, 419 itself, and the rest of that list — uses `es-MX`.
    /// `es`, `es-ES`, `es-GQ` and `es-PH` stay on `es`. The region sets match
    /// `scripts/regional-variants.mjs`.
    static func resolve(_ candidates: [String]) -> String {
        for raw in candidates {
            let normalized = raw.replacingOccurrences(of: "_", with: "-")
            if let exact = supportedLanguages.first(where: { $0.id.caseInsensitiveCompare(normalized) == .orderedSame }) {
                return exact.id
            }
            let lower = normalized.lowercased()
            if lower.hasPrefix("zh-hant-hk") || lower.hasPrefix("zh-hk") { return "zh-HK" }
            if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw") { return "zh-TW" }
            if lower.hasPrefix("zh") { return "zh-CN" }
            if lower == "en" || lower.hasPrefix("en-") { return isAmericanEnglish(lower) ? "en" : "en-GB" }
            if lower == "es" || lower.hasPrefix("es-") { return isLatinAmerican(lower) ? "es-MX" : "es" }
            if let language = supportedLanguages.first(where: {
                lower.hasPrefix($0.id.lowercased() + "-") || $0.id.lowercased().hasPrefix(lower + "-")
            }) {
                return language.id
            }
        }
        return "en"
    }

    static func systemLanguage() -> String {
        resolve(Locale.preferredLanguages + Bundle.main.preferredLocalizations)
    }

    /// `en-GB` falls back to `en`, `es-MX` to `es`, then both to `en`.
    static func parentLanguage(for locale: String) -> String? {
        switch locale {
        case "en-GB": return "en"
        case "es-MX": return "es"
        default: return nil
        }
    }

    /// Regions whose English spelling follows the United States, not Britain.
    private static let americanEnglishRegions: Set<String> = [
        "US", "CA", "PH", "LR", "PR", "GU", "AS", "VI", "UM", "MP",
    ]

    /// Spanish regions whose CLDR parent is `es-419`, including `es-US`.
    private static let latinAmericanRegions: Set<String> = [
        "419", "MX", "AR", "BO", "BR", "BZ", "CL", "CO", "CR", "CU", "DO", "EC", "GT", "HN",
        "NI", "PA", "PE", "PR", "PY", "SV", "US", "UY", "VE",
    ]

    private static func regionCode(_ tag: String) -> String? {
        let parts = tag.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return nil }
        var index = 1
        if parts[index].count == 4, parts[index].allSatisfy(\.isLetter) {
            index += 1
            guard index < parts.count else { return nil }
        }
        let region = parts[index]
        let letters = region.count == 2 && region.allSatisfy(\.isLetter)
        let digits = region.count == 3 && region.allSatisfy(\.isNumber)
        return (letters || digits) ? region.uppercased() : nil
    }

    private static func isAmericanEnglish(_ tag: String) -> Bool {
        guard let region = regionCode(tag) else { return true }
        return americanEnglishRegions.contains(region)
    }

    private static func isLatinAmerican(_ tag: String) -> Bool {
        guard let region = regionCode(tag) else { return false }
        return latinAmericanRegions.contains(region)
    }

    /// Whether this string is a format the count belongs to.
    ///
    /// Testing for a bare `%` is not good enough: 38 shipped strings end in a
    /// literal "(%)" — "Income after adjustment (%)" — and handing one of those
    /// to `String(format:)` reads the percent sign as a broken specifier. Only
    /// the generator's own `%lld` and the plural token Foundation returns for a
    /// variation entry count.
    private static func takesACount(_ value: String) -> Bool {
        value.contains("%lld") || value.contains("%#@")
    }

    private func pool(_ key: String, locale: String) -> [String] {
        let parent = Self.parentLanguage(for: locale)
        var result: [String] = []
        var index = 1
        while true {
            let itemKey = "\(key).\(index)"
            if let value = lookup(itemKey, locale: locale) {
                result.append(value)
            } else if let parent, let value = lookup(itemKey, locale: parent) {
                result.append(value)
            } else {
                break
            }
            index += 1
        }
        return result
    }

    /// `nil` when this language does not define the key, so the caller can fall
    /// back to English itself.
    private func lookup(_ key: String, locale: String) -> String? {
        guard let bundle = bundle(for: locale) else { return nil }
        let value = bundle.localizedString(forKey: key, value: Self.missing, table: nil)
        return value == Self.missing ? nil : value
    }

    private func bundle(for locale: String) -> Bundle? {
        if let cached = bundles[locale] { return cached }
        guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        bundles[locale] = bundle
        return bundle
    }
}
