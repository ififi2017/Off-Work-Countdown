import Testing
@testable import DoneAtWatchApp

@MainActor
@Test("Watch app state can be injected without starting connectivity")
func watchAppStateInjection() {
    let model = WatchAppModel()
    #expect(model.package == nil)
    #expect(model.connectionState == .waiting)
    model.publish(nil, connectionState: .persistenceFailed)
    #expect(model.connectionState == .persistenceFailed)
    _ = WatchRootView(model: model)
}

@Test("Watch localization resolves scripts, regions, and regional language tables")
func watchLocalizationResolution() {
    #expect(WatchLocalizations.resolveLocale(["zh-Hant-TW"]) == "zh-TW")
    #expect(WatchLocalizations.resolveLocale(["zh-Hant-HK"]) == "zh-HK")
    #expect(WatchLocalizations.resolveLocale(["zh-Hans-CN"]) == "zh-CN")
    #expect(WatchLocalizations.resolveLocale(["hi"]) == "hi-IN")
    #expect(WatchLocalizations.resolveLocale(["mr"]) == "mr-IN")
    #expect(WatchLocalizations.resolveLocale(["xx", "fr-FR"]) == "fr")
    #expect(WatchLocalizations.resolveLocale(["xx"]) == "en")
    #expect(WatchLocalizations.resolveLocale(["en-AU"]) == "en-GB")
    #expect(WatchLocalizations.resolveLocale(["en-GB"]) == "en-GB")
    #expect(WatchLocalizations.resolveLocale(["en-US"]) == "en")
    #expect(WatchLocalizations.resolveLocale(["en-CA"]) == "en")
    #expect(WatchLocalizations.resolveLocale(["es-AR"]) == "es-MX")
    #expect(WatchLocalizations.resolveLocale(["es-419"]) == "es-MX")
    #expect(WatchLocalizations.resolveLocale(["es-MX"]) == "es-MX")
    #expect(WatchLocalizations.resolveLocale(["es-ES"]) == "es")
    #expect(WatchLocalizations.resolveLocale(["es-US"]) == "es-MX")
}
