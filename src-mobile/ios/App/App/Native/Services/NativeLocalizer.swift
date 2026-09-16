import Foundation

nonisolated struct NativeLanguage: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// Reads the app's copy out of `Localizable.xcstrings` (plan 019 §3).
///
/// iOS used to parse `public/locales/<lang>/translation.json` from the bundle.
/// The catalog replaces that: Xcode compiles it into one `Localizable.strings`
/// per `.lproj`, so the JSON no longer ships. `scripts/generate-ios-xcstrings.mjs`
/// builds the catalog from those same files, which stay the source of truth,
/// and `npm test` fails while the two disagree.
///
/// The language is looked up per call rather than through `Bundle.main`,
/// because the app has its own language picker: `Bundle.main` follows the
/// **system** language and would ignore a user who set the app to Japanese on
/// an English phone.
final class NativeLocalizer {
    nonisolated static let supportedLanguages: [NativeLanguage] = [
        .init(id: "en", name: "English"),
        .init(id: "zh-CN", name: "简体中文"),
        .init(id: "zh-HK", name: "繁體中文（香港）"),
        .init(id: "zh-TW", name: "繁體中文（台灣）"),
        .init(id: "ja", name: "日本語"),
        .init(id: "ko", name: "한국어"),
        .init(id: "de", name: "Deutsch"),
        .init(id: "es", name: "Español"),
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
        var value = lookup(key, locale: locale) ?? lookup(key, locale: "en") ?? key
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
    /// `key.1`, `key.2`, … and they are collected back here. A locale with no
    /// pool of its own falls back to English whole rather than line by line.
    func strings(_ key: String, locale: String) -> [String] {
        let localized = pool(key, locale: locale)
        return localized.isEmpty ? pool(key, locale: "en") : localized
    }

    func languageName(for locale: String) -> String {
        Self.supportedLanguages.first(where: { $0.id == locale })?.name ?? locale
    }

    static func systemLanguage() -> String {
        let preferred = Bundle.main.preferredLocalizations + Locale.preferredLanguages
        for raw in preferred {
            let normalized = raw.replacingOccurrences(of: "_", with: "-")
            if supportedLanguages.contains(where: { $0.id.caseInsensitiveCompare(normalized) == .orderedSame }) {
                return supportedLanguages.first(where: { $0.id.caseInsensitiveCompare(normalized) == .orderedSame })!.id
            }
            if normalized.lowercased().hasPrefix("zh-hant-hk") { return "zh-HK" }
            if normalized.lowercased().hasPrefix("zh-hant") { return "zh-TW" }
            if normalized.lowercased().hasPrefix("zh") { return "zh-CN" }
            if let language = supportedLanguages.first(where: {
                normalized.lowercased().hasPrefix($0.id.lowercased() + "-")
                    || $0.id.lowercased().hasPrefix(normalized.lowercased() + "-")
            }) {
                return language.id
            }
        }
        return "en"
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
        var result: [String] = []
        while let value = lookup("\(key).\(result.count + 1)", locale: locale) {
            result.append(value)
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
