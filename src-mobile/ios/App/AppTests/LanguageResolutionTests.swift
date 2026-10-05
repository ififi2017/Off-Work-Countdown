import Testing
@testable import App

/// Region tables shared with Android `AppLanguages.resolve` and the Watch
/// generator. `Bundle.preferredLocalizations` is not used here: it collapses
/// `en-AU` to `en` and `es-AR` to `es` once those `.lproj` folders exist.
@Test("System language regions pick British English and Latin American Spanish")
func languageRegionsResolveBeforeTheGenericPrefix() {
    #expect(NativeLocalizer.resolve(["en-GB"]) == "en-GB")
    #expect(NativeLocalizer.resolve(["en-AU"]) == "en-GB")
    #expect(NativeLocalizer.resolve(["en-IE"]) == "en-GB")
    #expect(NativeLocalizer.resolve(["en-NZ"]) == "en-GB")
    #expect(NativeLocalizer.resolve(["en-IN"]) == "en-GB")
    #expect(NativeLocalizer.resolve(["en-ZA"]) == "en-GB")
    #expect(NativeLocalizer.resolve(["en"]) == "en")
    #expect(NativeLocalizer.resolve(["en-US"]) == "en")
    #expect(NativeLocalizer.resolve(["en-CA"]) == "en")
    #expect(NativeLocalizer.resolve(["en-PH"]) == "en")
    #expect(NativeLocalizer.resolve(["es-MX"]) == "es-MX")
    #expect(NativeLocalizer.resolve(["es-419"]) == "es-MX")
    #expect(NativeLocalizer.resolve(["es-AR"]) == "es-MX")
    #expect(NativeLocalizer.resolve(["es-CO"]) == "es-MX")
    #expect(NativeLocalizer.resolve(["es-CL"]) == "es-MX")
    #expect(NativeLocalizer.resolve(["es-PE"]) == "es-MX")
    #expect(NativeLocalizer.resolve(["es-US"]) == "es-MX")
    #expect(NativeLocalizer.resolve(["es"]) == "es")
    #expect(NativeLocalizer.resolve(["es-ES"]) == "es")
    #expect(NativeLocalizer.resolve(["es-GQ"]) == "es")
    #expect(NativeLocalizer.resolve(["zh-Hant-HK"]) == "zh-HK")
    #expect(NativeLocalizer.resolve(["de-AT"]) == "de")
    #expect(NativeLocalizer.resolve(["sv-SE", "fr-CA"]) == "fr")
    #expect(NativeLocalizer.resolve(["sv-SE"]) == "en")
    #expect(NativeLocalizer.parentLanguage(for: "en-GB") == "en")
    #expect(NativeLocalizer.parentLanguage(for: "es-MX") == "es")
    #expect(NativeLocalizer.parentLanguage(for: "ja") == nil)
}
