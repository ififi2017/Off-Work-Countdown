import Foundation
import Testing
@testable import App

/// One recorded workday used to render as "1 workdays" / "1 Arbeitstage":
/// `recordsMonthWorkdays` was a hard-coded plural and `t(_:values:)` had no
/// way to ask for another form. These tests read the `public/locales` files
/// as they are bundled into the app, so a locale that loses its `_one` entry
/// fails here instead of on a screenshot.

@MainActor
private func workdays(_ count: Int, _ locale: String) -> String {
    NativeLocalizer().string(
        "recordsMonthWorkdays",
        locale: locale,
        count: count,
        values: ["count": "\(count)"]
    )
}

/// The raw template, uninterpolated, straight out of the locale's own file —
/// no English fallback, so a missing key is visible as nil.
private func template(_ key: String, _ locale: String) -> String? {
    guard let url = Bundle.main.url(
        forResource: "translation",
        withExtension: "json",
        subdirectory: "locales/\(locale)"
    ),
    let data = try? Data(contentsOf: url),
    let table = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return table[key] as? String
}

@MainActor
@Test("One workday reads as a singular in the locales that inflect")
func oneWorkdayUsesTheSingularForm() {
    #expect(workdays(1, "en") == "1 workday")
    #expect(workdays(1, "de") == "1 Arbeitstag")
    #expect(workdays(1, "es") == "1 día trabajado")
    #expect(workdays(1, "fr") == "1 jour travaillé")
    #expect(workdays(1, "it") == "1 giorno lavorato")
    #expect(workdays(1, "pt") == "1 dia trabalhado")
    #expect(workdays(1, "ru") == "1 рабочий день")
    #expect(workdays(1, "hi-IN") == "1 काम का दिन")
    #expect(workdays(1, "mr-IN") == "1 कामाचा दिवस")
}

/// Zero is the count a bare `count == 1` check gets wrong: English takes the
/// plural, French and Hindi take the singular, and Russian takes a third form
/// that English has no name for.
@MainActor
@Test("Zero workdays follows each locale's own rule, not English's")
func zeroWorkdaysFollowsTheLocaleRule() {
    #expect(workdays(0, "en") == "0 workdays")
    #expect(workdays(0, "de") == "0 Arbeitstage")
    #expect(workdays(0, "fr") == "0 jour travaillé")
    #expect(workdays(0, "pt") == "0 dia trabalhado")
    #expect(workdays(0, "hi-IN") == "0 काम का दिन")
    #expect(workdays(0, "ru") == "0 рабочих дней")
}

@MainActor
@Test("Locales with one nominal form read the same at every count")
func uninflectedLocalesAreUnchanged() {
    for locale in ["zh-CN", "zh-HK", "zh-TW", "ja", "ko", "th", "vi", "id", "tr", "ar"] {
        let base = template("recordsMonthWorkdays", locale)
        #expect(base != nil, "\(locale) is missing recordsMonthWorkdays")
        for count in [0, 1, 7] {
            let expected = base?.replacingOccurrences(of: "{{count}}", with: "\(count)")
            #expect(workdays(count, locale) == expected, "\(locale) \(count)")
        }
    }
}

/// Parity, checked against the bundle rather than the repository: a locale
/// missing `_one` would otherwise fall back to English and read "1 workday"
/// inside a German screen. `lib/locales.test.ts` guards the same thing from
/// the JSON side, before the files are ever copied in.
@MainActor
@Test("Every shipped locale bundles the singular variant")
func everyLocaleBundlesTheSingular() {
    for language in NativeLocalizer.supportedLanguages {
        let singular = template("recordsMonthWorkdays_one", language.id)
        #expect(singular != nil, "\(language.id) is missing recordsMonthWorkdays_one")
        #expect(singular?.contains("{{count}}") == true, "\(language.id)")
    }
}

@MainActor
@Test("A key without a count keeps the plain lookup")
func countlessLookupIsUnchanged() {
    let localizer = NativeLocalizer()
    #expect(localizer.string("recordsByMonth", locale: "de") == "Nach Monat")
    #expect(
        localizer.string("recordsMonthWorkdays", locale: "de", values: ["count": "3"])
            == "3 Arbeitstage"
    )
}

/// The categories past `one` have no entries in the JSON yet, so Russian 2–4
/// still reads the `other` form. Pinning the categories here means the change
/// that adds "2 рабочих дня" only has to add the string.
@MainActor
@Test("Plural categories follow CLDR for the locales that need more than two")
func pluralCategoriesFollowCLDR() {
    #expect(NativePluralCategory.of(count: 1, locale: "ru") == .one)
    #expect(NativePluralCategory.of(count: 21, locale: "ru") == .one)
    #expect(NativePluralCategory.of(count: 11, locale: "ru") == .many)
    #expect(NativePluralCategory.of(count: 3, locale: "ru") == .few)
    #expect(NativePluralCategory.of(count: 5, locale: "ru") == .many)
    #expect(NativePluralCategory.of(count: 0, locale: "ru") == .many)

    #expect(NativePluralCategory.of(count: 0, locale: "ar") == .zero)
    #expect(NativePluralCategory.of(count: 1, locale: "ar") == .one)
    #expect(NativePluralCategory.of(count: 2, locale: "ar") == .two)
    #expect(NativePluralCategory.of(count: 3, locale: "ar") == .few)
    #expect(NativePluralCategory.of(count: 11, locale: "ar") == .many)
    #expect(NativePluralCategory.of(count: 100, locale: "ar") == .other)

    #expect(NativePluralCategory.of(count: 0, locale: "en") == .other)
    #expect(NativePluralCategory.of(count: 0, locale: "fr") == .one)
    #expect(NativePluralCategory.of(count: 1, locale: "ja") == .other)
}
