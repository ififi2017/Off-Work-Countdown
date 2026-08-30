import Foundation
import Testing
@testable import App

@MainActor
@Test("Life view weeks run to retirement, not a fixed 52-week year")
func lifeViewUsesContinuousWeeks() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let profile = LifeProfile(
        birthYear: 1990,
        workStartedOn: calendar.date(from: DateComponents(year: 2012, month: 1, day: 1)),
        retirementAge: 60,
        averageSleepHours: 8,
        hidesExactAges: false,
        editedAt: Date(timeIntervalSince1970: 0),
        editCount: 1,
        editTieBreaker: UUID()
    )
    let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
    let model = LifeViewCalculator.build(
        profile: profile,
        periods: [],
        overrideDays: [],
        outsideZoneDays: [],
        now: now,
        calendar: calendar
    )
    #expect(!model.cells.isEmpty)
    #expect(model.cells.contains { $0.kind == .workEstimated || $0.kind == .workProjected })
    #expect(model.cells.last?.year == 2050)
}
