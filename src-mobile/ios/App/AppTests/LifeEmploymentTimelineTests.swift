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
            startsOn: .exact(year: 2022, month: 2, day: 1)!,
            endsOn: .exact(year: 2024, month: 4, day: 1)!,
            salary: LifeSalary(amount: 8_000, cadence: .monthly)
        ),
        LifeEmploymentPeriod(
            id: currentID,
            startsOn: .exact(year: 2024, month: 5, day: 1)!,
            endsOn: .exact(year: 2025, month: 1, day: 1)!,
            salary: salary
        ),
        LifeEmploymentPeriod(
            id: olderID,
            startsOn: .exact(year: 2019, month: 3, day: 1)!,
            endsOn: .exact(year: 2020, month: 1, day: 1)!,
            salary: LifeSalary(amount: 6_000, cadence: .monthly)
        ),
    ]
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))

    let linked = try #require(LifeEmploymentTimeline.linkedPeriods(
        periods,
        calendar: calendar,
        now: now,
        linkingEndsFor: Set(periods.map(\.id))
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
        workStartedPartial: .exact(year: 2018, month: 1, day: 1)!,
        editedAt: .distantPast,
        editCount: 1,
        editTieBreaker: UUID()
    )
    profile.employmentPeriods = [
        LifeEmploymentPeriod(
            id: UUID(),
            startsOn: .exact(year: 2020, month: 1, day: 1)!,
            endsOn: .exact(year: 2022, month: 1, day: 1)!,
            salary: salary
        ),
        LifeEmploymentPeriod(
            id: UUID(),
            startsOn: .exact(year: 2022, month: 1, day: 1)!,
            endsOn: .exact(year: 2024, month: 5, day: 1)!,
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
    let start = PartialCivilDate.exact(year: 2027, month: 1, day: 1)!
    let periods = [LifeEmploymentPeriod(id: UUID(), startsOn: start, endsOn: nil, salary: salary)]
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))

    #expect(LifeEmploymentTimeline.linkedPeriods(periods, calendar: calendar, now: now, linkingEndsFor: Set(periods.map(\.id))) == nil)
}

@MainActor
@Test("Employment timeline rejects duplicate starts")
func employmentTimelineRejectsDuplicateStarts() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let salary = LifeSalary(amount: 10_000, cadence: .monthly)
    let start = PartialCivilDate.exact(year: 2025, month: 1, day: 1)!
    let periods = [
        LifeEmploymentPeriod(id: UUID(), startsOn: start, endsOn: nil, salary: salary),
        LifeEmploymentPeriod(id: UUID(), startsOn: start, endsOn: nil, salary: salary),
    ]
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))

    #expect(LifeEmploymentTimeline.linkedPeriods(periods, calendar: calendar, now: now, linkingEndsFor: Set(periods.map(\.id))) == nil)
}


@MainActor
@Test("Editing salary keeps historical employment gaps and end dates")
func employmentTimelinePreservesStoredGaps() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))
    let current = LifeEmploymentPeriod(id: UUID(), startsOn: .exact(year: 2024, month: 5, day: 1)!, endsOn: nil, salary: LifeSalary(amount: 12_000, cadence: .monthly))
    let older = LifeEmploymentPeriod(id: UUID(), startsOn: .exact(year: 2020, month: 1, day: 1)!, endsOn: .exact(year: 2022, month: 1, day: 1)!, salary: LifeSalary(amount: 8_000, cadence: .monthly))
    let periods = [current, older]
    let linkedIDs = LifeEmploymentTimeline.linkedEndIDs(in: periods, calendar: calendar)
    var edited = periods
    edited[0].salary.amount = 15_000
    let saved = try #require(LifeEmploymentTimeline.linkedPeriods(edited, calendar: calendar, now: now, linkingEndsFor: linkedIDs))
    #expect(saved == edited)
    #expect(saved[1].endsOn == older.endsOn)
}

@MainActor
@Test("Invalid stored employment ends cannot be silently relinked", arguments: [2025, 2019, nil] as [Int?])
func employmentTimelineRejectsStoredInvalidEnds(endYear: Int?) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))
    let salary = LifeSalary(amount: 10_000, cadence: .monthly)
    let periods = [
        LifeEmploymentPeriod(id: UUID(), startsOn: .exact(year: 2024, month: 5, day: 1)!, endsOn: nil, salary: salary),
        LifeEmploymentPeriod(id: UUID(), startsOn: .exact(year: 2020, month: 1, day: 1)!, endsOn: endYear.flatMap { .exact(year: $0, month: 1, day: 1) }, salary: salary),
    ]
    let linkedIDs = LifeEmploymentTimeline.linkedEndIDs(in: periods, calendar: calendar)
    #expect(LifeEmploymentTimeline.linkedPeriods(periods, calendar: calendar, now: now, linkingEndsFor: linkedIDs) == nil)
    #expect(LifeEmploymentTimeline.linkedPeriods([periods[0]], calendar: calendar, now: now, linkingEndsFor: linkedIDs) != nil)
}

@MainActor
@Test("Adjacent employment boundaries still follow an edited start")
func employmentTimelineKeepsAdjacentEndsLinked() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))
    let salary = LifeSalary(amount: 10_000, cadence: .monthly)
    let start = PartialCivilDate.exact(year: 2024, month: 5, day: 1)!
    let periods = [
        LifeEmploymentPeriod(id: UUID(), startsOn: start, endsOn: nil, salary: salary),
        LifeEmploymentPeriod(id: UUID(), startsOn: .exact(year: 2020, month: 1, day: 1)!, endsOn: start, salary: salary),
    ]
    let linkedIDs = LifeEmploymentTimeline.linkedEndIDs(in: periods, calendar: calendar)
    var edited = periods
    edited[0].startsOn = .exact(year: 2024, month: 6, day: 1)!
    let saved = try #require(LifeEmploymentTimeline.linkedPeriods(edited, calendar: calendar, now: now, linkingEndsFor: linkedIDs))
    #expect(saved[1].endsOn == edited[0].startsOn)
}
