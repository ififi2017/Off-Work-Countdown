import Foundation

struct NativeLanguage: Identifiable, Hashable {
    let id: String
    let name: String
}

/// CLDR plural categories, spelled the way i18next suffixes a key:
/// `recordsMonthWorkdays_one` sits beside `recordsMonthWorkdays`, and the
/// unsuffixed key stays the `other` form so untouched keys keep working.
///
/// Web reads these categories from `Intl.PluralRules`; iOS exposes no
/// equivalent, so the cardinal rules for the 19 shipped locales are written
/// out here. This is a rendering rule with no counterpart in `lib/` — it is
/// not a schedule, summary or salary rule being ported into Swift.
enum NativePluralCategory: String {
    case zero, one, two, few, many, other

    static func of(count: Int, locale: String) -> NativePluralCategory {
        let n = abs(count)
        switch locale {
        // One nominal form for every count.
        case "id", "ja", "ko", "th", "vi", "zh-CN", "zh-HK", "zh-TW":
            return .other
        // Zero takes the singular too: "0 jour travaillé", not "0 jours".
        case "fr", "pt", "hi-IN", "mr-IN":
            return n == 0 || n == 1 ? .one : .other
        case "ru":
            if n % 10 == 1, n % 100 != 11 { return .one }
            if (2...4).contains(n % 10), !(12...14).contains(n % 100) { return .few }
            return .many
        case "ar":
            if n == 0 { return .zero }
            if n == 1 { return .one }
            if n == 2 { return .two }
            if (3...10).contains(n % 100) { return .few }
            if (11...99).contains(n % 100) { return .many }
            return .other
        // de, en, es, it, tr, and any locale added without its own rule.
        default:
            return n == 1 ? .one : .other
        }
    }
}

final class NativeLocalizer {
    static let supportedLanguages: [NativeLanguage] = [
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

    private var tables: [String: [String: Any]] = [:]

    /// `count` is the quantity the sentence is about, not the text that gets
    /// interpolated: it only selects which variant of `key` to read. Pass nil
    /// for keys that carry no quantity.
    func string(
        _ key: String,
        locale: String,
        count: Int? = nil,
        values: [String: String] = [:]
    ) -> String {
        let value = resolve(key, locale: locale, count: count)
            ?? resolve(key, locale: "en", count: count)
            ?? key
        return values.reduce(value) { result, pair in
            result.replacingOccurrences(of: "{{\(pair.key)}}", with: pair.value)
        }
    }

    /// i18next's lookup order, narrowed to what the shared JSON carries: the
    /// category variant, then an explicit `_other`, then the bare key. Because
    /// the bare key is already the `other` form, a locale only needs a
    /// suffixed entry where its grammar actually differs — and the English
    /// fallback re-picks the category, since English does not count like the
    /// locale that missed the key.
    private func resolve(_ key: String, locale: String, count: Int?) -> String? {
        let table = table(for: locale)
        if let count {
            let category = NativePluralCategory.of(count: count, locale: locale)
            if let variant = table["\(key)_\(category.rawValue)"] as? String { return variant }
            if let other = table["\(key)_other"] as? String { return other }
        }
        return table[key] as? String
    }

    func strings(_ key: String, locale: String) -> [String] {
        table(for: locale)[key] as? [String]
            ?? table(for: "en")[key] as? [String]
            ?? []
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

    private func table(for locale: String) -> [String: Any] {
        if let cached = tables[locale] { return cached }
        guard let url = Bundle.main.url(
            forResource: "translation",
            withExtension: "json",
            subdirectory: "locales/\(locale)"
        ),
        let data = try? Data(contentsOf: url),
        let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            tables[locale] = [:]
            return [:]
        }
        tables[locale] = dictionary
        return dictionary
    }
}
