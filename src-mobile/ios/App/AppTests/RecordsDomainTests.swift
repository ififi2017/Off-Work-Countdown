import Foundation
import Testing
@testable import App

@MainActor
@Suite("Records and Life domains without the application")
struct RecordsDomainTests {
    private func calendar() throws -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = try #require(TimeZone(identifier: "UTC"))
        return value
    }

    private func hours() -> ScheduleHoursConfiguration {
        .init(startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: nil, breakDurationMinutes: 0)
    }

    private func queries(records: RecordCoordinator, defaults: UserDefaults,
                         calendar: Calendar, hours: @escaping () -> ScheduleHoursConfiguration) -> RecordsQueries {
        let plus = PlusEntitlement(defaults: defaults)
        plus.debugSetAuthorized(true)
        return RecordsQueries(records: records, plus: plus, localizer: NativeLocalizer(), sources: .init(
            calendar: { calendar }, hours: { _ in hours() }, rules: { _, _ in nil },
            snapshot: { _ in nil }, isCounting: { false }, salaryIsVisible: { false },
            salaryType: { nil }, language: { "en" }))
    }

    private func life(queries: RecordsQueries, hours: ScheduleHoursConfiguration) -> LifeSummaryModel {
        let model = LifeSummaryModel(queries: queries, readPreferences: { _ in
            LifeSummaryPreferences(hours: hours, salary: .init(amount: "", enabled: false,
                type: "monthly", workingDays: 22, bonusMonths: 0))
        })
        model.saveLifeProfileV2(bornOn: .yearOnly(1990), schoolStartedOn: nil,
            workStartedOn: .yearOnly(2025), retirementOn: .yearOnly(2028), sleepHours: 8)
        return model
    }

    @Test("Records reads and Life estimates work independently and never seed history")
    func independentReadAndProjection() async throws {
        let suite = "RecordsDomain.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = try calendar()
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        let hours = hours()
        let records = RecordCoordinator.inMemory()
        let queries = queries(records: records, defaults: defaults, calendar: calendar, hours: { hours })
        let life = life(queries: queries, hours: hours)
        let before = records.state
        let revision = records.revision
        #expect(queries.recordDayIndex().isEmpty)
        #expect(queries.resolvedDays(from: date, through: date, now: date).first?.segments.isEmpty == true)
        let projected = await queries.prepareRecordsDisplayDays(from: date, through: date, now: date)
        let expected = try CountdownRules.shared.expandScheduleRange(configuration: hours,
            from: calendar.startOfDay(for: date), through: calendar.startOfDay(for: date), timeZone: calendar.timeZone)
        #expect(projected.first?.segments == expected.first?.segments)
        let summary = try #require(await life.prepareLifeViewModel(now: date))
        #expect(life.lifeViewModel(now: date) == summary)
        #expect(records.state == before)
        #expect(records.revision == revision)
        #expect(records.state.periods.isEmpty)
        #expect(records.state.snapshots.isEmpty)
    }

    @Test("A pending Records estimate follows changed schedule inputs without an archive edit")
    func scheduleChangesDuringPreparation() async throws {
        let suite = "RecordsDomainPreparation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = try calendar()
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        var currentHours = hours()
        let records = RecordCoordinator.inMemory()
        let queries = queries(records: records, defaults: defaults, calendar: calendar, hours: { currentHours })
        _ = life(queries: queries, hours: currentHours)
        let before = records.state
        let loading = Task.immediate {
            await queries.prepareRecordsDisplayDays(from: date, through: date, now: date)
        }
        currentHours.endTime = "19:00"
        let projected = await loading.value
        let expected = try CountdownRules.shared.expandScheduleRange(configuration: currentHours,
            from: calendar.startOfDay(for: date), through: calendar.startOfDay(for: date), timeZone: calendar.timeZone)
        #expect(projected.first?.segments == expected.first?.segments)
        #expect(records.state == before)
    }

    @Test("A late Life refresh cannot replace a newer day's published result")
    func newestLifeRefreshWins() async throws {
        let suite = "LifeDomainRefresh.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = try calendar()
        let earlier = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        let later = try #require(calendar.date(byAdding: .day, value: 14, to: earlier))
        let hours = hours()
        let records = RecordCoordinator.inMemory()
        let queries = queries(records: records, defaults: defaults, calendar: calendar, hours: { hours })
        let life = life(queries: queries, hours: hours)
        let earlierWeeks = try #require(life.lifeViewModel(now: earlier)).workedWeeks
        let expected = try #require(life.lifeViewModel(now: later))
        #expect(earlierWeeks != expected.workedWeeks)
        let oldRefresh = Task.immediate { await life.refreshLifeSummary(now: earlier) }
        await life.refreshLifeSummary(now: later)
        #expect(life.cachedLifeViewModel?.workedWeeks == expected.workedWeeks)
        await oldRefresh.value
        #expect(life.cachedLifeViewModel?.workedWeeks == expected.workedWeeks)
    }

    @Test("Unchanged profile edits preserve sleep provenance and the archive revision")
    func profileNoOp() throws {
        let suite = "LifeDomainProfile.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = try calendar()
        let hours = hours()
        let records = RecordCoordinator.inMemory()
        let queries = queries(records: records, defaults: defaults, calendar: calendar, hours: { hours })
        let life = life(queries: queries, hours: hours)
        let before = records.state
        let revision = records.revision
        let original = try #require(before.lifeProfile?.sleepSourceUpdatedAt)
        life.applyProfileEdit(at: original.addingTimeInterval(60)) {
            $0.averageSleepHours = 8
            $0.averageSleepMinutes = 480
            $0.sleepSource = .manual
        }
        #expect(records.state == before)
        #expect(records.revision == revision)
        let changedAt = original.addingTimeInterval(120)
        life.applyProfileEdit(at: changedAt) {
            $0.averageSleepHours = 7
            $0.averageSleepMinutes = 420
        }
        #expect(records.state.lifeProfile?.sleepSourceUpdatedAt == changedAt)
        #expect(records.revision == revision + 1)
    }
}
