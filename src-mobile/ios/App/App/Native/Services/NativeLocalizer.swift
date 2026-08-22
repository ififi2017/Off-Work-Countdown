import Foundation

struct NativeLanguage: Identifiable, Hashable {
    let id: String
    let name: String
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

    func string(_ key: String, locale: String, values: [String: String] = [:]) -> String {
        let value = table(for: locale)[key] as? String
            ?? table(for: "en")[key] as? String
            ?? key
        return values.reduce(value) { result, pair in
            result.replacingOccurrences(of: "{{\(pair.key)}}", with: pair.value)
        }
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
