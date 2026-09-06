import Foundation
import Testing
@testable import App

@MainActor
@Test("Employment timeline sorts newest first and links every earlier end")
func employmentTimelineLinksEndsWithoutReplacingRows() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let salary = LifeSalary(amount: 12_345, cadence: .monthly)
    let olderID = UUID()
    let middleID = UUID()
    let currentID = UUID()
    let periods = [
        LifeEmploymentPeriod(
            id: middleID,
            startsOn: try #require(.exact(year: 2022, month: 2, day: 1)),
            endsOn: try #require(.exact(year: 2024, month: 4, day: 1)),
            salary: LifeSalary(amount: 8_000, cadence: .monthly)
        ),
        LifeEmploymentPeriod(
            id: currentID,
            startsOn: try #require(.exact(year: 2024, month: 5, day: 1)),
            endsOn: try #require(.exact(year: 2025, month: 1, day: 1)),
            salary: salary
        ),
        LifeEmploymentPeriod(
            id: olderID,
            startsOn: try #require(.exact(year: 2019, month: 3, day: 1)),
            endsOn: try #require(.exact(year: 2020, month: 1, day: 1)),
            salary: LifeSalary(amount: 6_000, cadence: .monthly)
        ),
    ]
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))

    let linked = try #require(LifeEmploymentTimeline.linkedPeriods(
        periods,
        calendar: calendar,
        now: now
    ))

    #expect(linked.map(\.id) == [currentID, middleID, olderID])
    #expect(linked.map(\.salary) == [salary, periods[0].salary, periods[2].salary])
    #expect(linked[0].endsOn == nil)
    #expect(linked[1].endsOn == linked[0].startsOn)
    #expect(linked[2].endsOn == linked[1].startsOn)
}

@MainActor
@Test("Legacy detailed history starts the current job at the latest prior end")
func employmentTimelineInfersLegacyCurrentStart() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let expected = try #require(calendar.date(from: DateComponents(year: 2024, month: 5, day: 1)))
    let salary = LifeSalary(amount: 10_000, cadence: .monthly)
    var profile = LifeProfile(
        workStartedPartial: try #require(.exact(year: 2018, month: 1, day: 1)),
        editedAt: .distantPast,
        editCount: 1,
        editTieBreaker: UUID()
    )
    profile.employmentPeriods = [
        LifeEmploymentPeriod(
            id: UUID(),
            startsOn: try #require(.exact(year: 2020, month: 1, day: 1)),
            endsOn: try #require(.exact(year: 2022, month: 1, day: 1)),
            salary: salary
        ),
        LifeEmploymentPeriod(
            id: UUID(),
            startsOn: try #require(.exact(year: 2022, month: 1, day: 1)),
            endsOn: try #require(.exact(year: 2024, month: 5, day: 1)),
            salary: salary
        ),
    ]
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))

    #expect(LifeEmploymentTimeline.inferredCurrentStart(
        profile: profile,
        calendar: calendar,
        now: now
    ) == expected)
}

@MainActor
@Test("Employment timeline rejects a future current start")
func employmentTimelineRejectsFutureCurrentStart() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let salary = LifeSalary(amount: 10_000, cadence: .monthly)
    let start = try #require(PartialCivilDate.exact(year: 2027, month: 1, day: 1))
    let periods = [LifeEmploymentPeriod(id: UUID(), startsOn: start, endsOn: nil, salary: salary)]
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))

    #expect(LifeEmploymentTimeline.linkedPeriods(periods, calendar: calendar, now: now) == nil)
}

@MainActor
@Test("Employment timeline rejects duplicate starts")
func employmentTimelineRejectsDuplicateStarts() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let salary = LifeSalary(amount: 10_000, cadence: .monthly)
    let start = try #require(PartialCivilDate.exact(year: 2025, month: 1, day: 1))
    let periods = [
        LifeEmploymentPeriod(id: UUID(), startsOn: start, endsOn: nil, salary: salary),
        LifeEmploymentPeriod(id: UUID(), startsOn: start, endsOn: nil, salary: salary),
    ]
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))

    #expect(LifeEmploymentTimeline.linkedPeriods(periods, calendar: calendar, now: now) == nil)
}
