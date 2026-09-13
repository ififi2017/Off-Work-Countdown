import Foundation
import Testing
@testable import App

@MainActor
@Suite("Presentation text without an application or shift")
struct AppTextTests {
    @Test("Language and salary visibility follow the shared committed preferences")
    func languageAndPrivacy() throws {
        let suite = "AppText.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = RecordCoordinator.inMemory()
        let preferences = PreferencesStore(defaults: defaults, records: records)
        let text = AppText(preferences: preferences)
        preferences.applyPreferences { $0.languageOverride = "en" }
        let english = text.t("tomorrow")
        #expect(text.moneyText(23000) == "23,000.00")
        preferences.hideEarnings = true
        #expect(text.moneyText(23000) == "••••")
        preferences.applyPreferences { $0.languageOverride = "de" }
        #expect(text.t("tomorrow") != english)
        #expect(text.moneyText(23000) == "••••")
        preferences.hideEarnings = false
        #expect(text.moneyText(23000) == "23.000,00")
        #expect(records.state.syncedPreferences == nil)
        #expect(records.state.periods.isEmpty)
    }

    @Test("Relative day labels use the caller's clock, including midnight boundaries")
    func suppliedClock() throws {
        let suite = "AppTextClock.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults, records: .inMemory())
        let text = AppText(preferences: preferences)
        let calendar = Calendar.current
        let start = try #require(calendar.date(from:
            DateComponents(year: 2001, month: 1, day: 15, hour: 23, minute: 59)))
        let nextDay = start.addingTimeInterval(120)
        #expect(text.relativeDayLabel(for: nextDay, from: start) == text.t("tomorrow"))
        #expect(text.relativeDayLabel(for: nextDay, from: nextDay) == text.weekdayName(for: nextDay))
    }
}
