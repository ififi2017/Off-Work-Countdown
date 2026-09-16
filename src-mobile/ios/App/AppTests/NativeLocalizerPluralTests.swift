import Foundation
import Testing
@testable import App

/// One recorded workday used to render as "1 workdays" / "1 Arbeitstage":
/// `recordsMonthWorkdays` was a hard-coded plural and `t(_:values:)` had no way
/// to ask for another form.
///
/// Since plan 019 §3 the copy lives in `Localizable.xcstrings` and the plural
/// is a catalog variation resolved by Foundation's own CLDR rules, instead of
/// an `_one` key picked by a table written out in Swift. These tests read the
/// compiled `.lproj` bundles, so a locale that loses its singular — or a
/// language whose `.lproj` never made it into the app — fails here rather than
/// on a screenshot.

@MainActor
private func workdays(_ count: Int, _ locale: String) -> String {
    NativeLocalizer().string(
        "recordsMonthWorkdays",
        locale: locale,
        count: count,
        values: ["count": "\(count)"]
    )
}

/// The value straight out of one language's own compiled catalog — no English
/// fallback, so a missing key or a missing `.lproj` is visible as nil.
private func bundleValue(_ key: String, _ locale: String) -> String? {
    guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else { return nil }
    let missing = "\u{0}owc.test.missing"
    let value = bundle.localizedString(forKey: key, value: missing, table: nil)
    return value == missing ? nil : value
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
///
/// This is also where a difference between the old hand-written table and
/// Foundation's CLDR rules would surface first.
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

/// Languages whose JSON carries no singular of its own: every count has to keep
/// rendering the one form, differing only by the number in it.
@MainActor
@Test("Locales with one nominal form read the same at every count")
func uninflectedLocalesAreUnchanged() {
    for locale in ["zh-CN", "zh-HK", "zh-TW", "ja", "ko", "th", "vi", "id", "tr", "ar"] {
        let seven = workdays(7, locale)
        #expect(seven.isEmpty == false, "\(locale)")
        for count in [0, 1] {
            let expected = seven.replacingOccurrences(of: "7", with: "\(count)")
            #expect(workdays(count, locale) == expected, "\(locale) \(count)")
        }
    }
}

/// Parity, checked against the bundle rather than the repository: a language
/// whose catalog entry never shipped would fall back to English and read
/// "1 workday" inside a German screen. `lib/locales.test.ts` guards the same
/// thing from the JSON side, and `scripts/generate-ios-xcstrings.test.mjs`
/// guards the catalog the generator produces.
@MainActor
@Test("Every shipped language bundles its own copy")
func everyLanguageBundlesItsOwnCopy() {
    for language in NativeLocalizer.supportedLanguages {
        #expect(
            bundleValue("recordsMonthWorkdays", language.id) != nil,
            "\(language.id) is missing recordsMonthWorkdays"
        )
        #expect(
            bundleValue("aboutProject", language.id) != nil,
            "\(language.id) is missing aboutProject"
        )
    }
}

@MainActor
@Test("A key without a count keeps the plain lookup")
func countlessLookupIsUnchanged() {
    let localizer = NativeLocalizer()
    #expect(localizer.string("aboutProject", locale: "de") == "Über dieses Projekt")
    #expect(
        localizer.string("recordsMonthWorkdays", locale: "de", values: ["count": "3"])
            == "3 Arbeitstage"
    )
}

/// A string ending in a literal "(%)" must never be handed to a formatter.
@MainActor
@Test("A percent sign in ordinary copy survives a counted lookup")
func literalPercentIsNotAFormatSpecifier() {
    let value = NativeLocalizer().string("lifeIncomeRetirementRatio", locale: "en", count: 3)
    #expect(value.contains("%"))
    #expect(value.contains("(null)") == false)
}

/// The catalog has no array type, so message pools ship as `key.1`, `key.2`, …
/// and are collected back. A pool that came back short would quietly shrink the
/// rotation instead of failing.
@MainActor
@Test("Message pools are collected back out of the numbered keys")
func messagePoolsSurviveTheCatalog() {
    let localizer = NativeLocalizer()
    #expect(localizer.strings("microBreakMessages", locale: "en").count == 4)
    #expect(localizer.strings("microBreakMessages", locale: "zh-CN").count == 4)
    #expect(localizer.strings("microBreakMessages", locale: "en").allSatisfy { !$0.isEmpty })
    // A key that is not a pool has none, rather than a one-element list.
    #expect(localizer.strings("aboutProject", locale: "en").isEmpty)
}

/// The app's own language picker, not the device's: `Bundle.main` would follow
/// the simulator's language and ignore the choice entirely.
@MainActor
@Test("A language the device is not set to still resolves")
func inAppLanguageChoiceIsHonoured() {
    let localizer = NativeLocalizer()
    let japanese = localizer.string("aboutProject", locale: "ja")
    let english = localizer.string("aboutProject", locale: "en")
    #expect(japanese != english)
    #expect(japanese.isEmpty == false)
}
