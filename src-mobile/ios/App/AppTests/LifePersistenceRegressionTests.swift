import Foundation
import Testing
import Observation
import Synchronization
@testable import App

@MainActor
struct LifePersistenceRegressionTests {
    private func profile() -> LifeProfile {
        LifeProfile(
            birthYear: 1990, retirementAge: 60,
            bornOn: .yearOnly(1990), workStartedPartial: .yearOnly(2012),
            retirementOn: .yearOnly(2050), workHistoryMode: .detailed,
            roughCurrentSalary: LifeSalary(amount: 10_000, cadence: .monthly),
            employmentPeriods: [
                LifeEmploymentPeriod(id: UUID(), startsOn: .exact(year: 2012, month: 1, day: 1)!,
                    endsOn: .exact(year: 2020, month: 1, day: 1)!,
                    salary: LifeSalary(amount: 5_000, cadence: .monthly)),
                LifeEmploymentPeriod(id: UUID(), startsOn: .exact(year: 2020, month: 1, day: 1)!,
                    endsOn: nil, salary: LifeSalary(amount: 10_000, cadence: .monthly))
            ], editedAt: .now, editCount: 1, editTieBreaker: UUID()
        )
    }

    @Test("Salary and bonus edits preserve career history through a cold reload")
    func salaryDoesNotReplaceHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "archive.json")
        let suite = "life.salary.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = RecordCoordinator(fileURL: url)
        let store = OffWorkStore(defaults: defaults, records: records)
        store.onboardingComplete = true
        records.updateLifeProfile(profile())
        let original = try #require(records.state.lifeProfile)
        store.salaryAmount = "14000"
        store.annualBonusEnabled = true
        store.annualBonusMonths = 3
        #expect(records.state.lifeProfile == original)
        let reloaded = RecordCoordinator(fileURL: url)
        #expect(reloaded.state.lifeProfile?.employmentPeriods == original.employmentPeriods)
        #expect(reloaded.state.lifeProfile?.roughCurrentSalary == original.roughCurrentSalary)
        #expect(reloaded.state.lifeProfile?.workHistoryMode == original.workHistoryMode)
    }

    @Test("An older device omitting career fields cannot clear saved history")
    func legacySyncPreservesHistory() throws {
        let records = RecordCoordinator.inMemory()
        records.updateLifeProfile(profile())
        let original = try #require(records.state.lifeProfile)
        var server = original
        server.retirementAge = 65
        server.retirementOn = .yearOnly(2055)
        server.editCount += 5
        server.editedAt = .now.addingTimeInterval(100)
        let data = try JSONEncoder().encode(LifeProfileDTO(server, calendar: Calendar(identifier: .gregorian)))
        var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["employmentPeriods", "workHistoryMode", "roughCurrentSalary", "futureIncomeDecline"] {
            fields.removeValue(forKey: key)
        }
        records.applyRemotePayload(type: .lifeProfile, key: LifeProfile.profileID.uuidString,
            payload: try JSONSerialization.data(withJSONObject: fields), editCount: server.editCount,
            editTieBreaker: server.editTieBreaker.uuidString, systemFields: nil, generation: 1)
        #expect(records.state.lifeProfile?.employmentPeriods == original.employmentPeriods)
        #expect(records.state.lifeProfile?.workHistoryMode == .detailed)
        #expect(records.state.lifeProfile?.retirementAge == 65)
    }

    @Test("Remote history clearing is recoverable and requires a known baseline", arguments: [true, false])
    func replacementRetainsCopy(hasBaseline: Bool) throws {
        let records = RecordCoordinator.inMemory()
        records.updateLifeProfile(profile())
        let original = try #require(records.state.lifeProfile)
        let baselineData = try JSONEncoder().encode(LifeProfileDTO(original, calendar: Calendar(identifier: .gregorian)))
        if hasBaseline {
            records.applyRemotePayload(type: .lifeProfile, key: LifeProfile.profileID.uuidString,
                payload: baselineData, editCount: original.editCount, editTieBreaker: original.editTieBreaker.uuidString,
                systemFields: nil, generation: 1)
        }
        var server = original
        server.employmentPeriods = []
        server.editCount += 5
        server.editedAt = .now.addingTimeInterval(100)
        let data = try JSONEncoder().encode(LifeProfileDTO(server, calendar: Calendar(identifier: .gregorian)))
        records.applyRemotePayload(type: .lifeProfile, key: LifeProfile.profileID.uuidString,
            payload: data, editCount: server.editCount, editTieBreaker: server.editTieBreaker.uuidString,
            systemFields: nil, generation: 1)
        let copy = try #require(records.state.sync.conflicts.first { $0.entityType == .lifeProfile })
        if hasBaseline {
            #expect(records.restoreConflict(copy))
        }
        #expect(records.state.lifeProfile?.employmentPeriods == original.employmentPeriods)
    }

    @Test("Current salary and bonus update the forecast without changing career history")
    func bonusRefreshesOnlyFutureIncome() async throws {
        let suite = "life.bonus.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OffWorkStore(defaults: defaults, records: .inMemory())
        store.records.updateLifeProfile(profile())
        let original = store.records.state.lifeProfile
        store.salaryEnabled = true
        store.salaryType = .monthly
        store.salaryAmount = "10000"
        let now = Date(timeIntervalSince1970: 1_788_739_200)
        let first = try #require(await store.prepareLifeViewModel(now: now))
        store.annualBonusMonths = 3
        store.annualBonusEnabled = true
        let bonus = try #require(await store.prepareLifeViewModel(now: now))
        #expect(bonus.income?.historicalGross == first.income?.historicalGross)
        let previous = try #require(first.income?.projectedGross)
        #expect(abs((try #require(bonus.income?.projectedGross)) / previous - 1.25) < 0.000001)
        #expect(bonus.allocation == first.allocation)
        #expect(store.records.state.lifeProfile == original)
        store.annualBonusEnabled = false
        let restored = await store.prepareLifeViewModel(now: now)
        #expect(restored?.income == first.income)
    }

    @Test("Life summary disk cache restores across stores and refreshes after an edit")
    func lifeCacheSurvivesReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "archive.json")
        let suite = "life.cache.disk.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OffWorkStore(defaults: defaults, records: RecordCoordinator(fileURL: url))
        store.records.updateLifeProfile(profile())
        store.preferredRecordsScale = .life
        let now = Date(timeIntervalSince1970: 1_788_739_200)
        let published = Mutex(false)
        withObservationTracking {
            _ = store.cachedLifeViewModel
        } onChange: {
            published.withLock { $0 = true }
        }
        await store.refreshLifeSummary(now: now)
        #expect(published.withLock { $0 })
        var first = try #require(store.cachedLifeViewModel)
        // A recognizable valid cached result proves reload does not secretly
        // recompute an equal projection before returning it.
        first.workShare = 0.123456
        await LifeSummaryCache.write(.init(key: store.lifeViewModelCacheKey(now: now), model: first),
            to: try #require(store.records.lifeSummaryCacheURL))
        let second = OffWorkStore(defaults: defaults, records: RecordCoordinator(fileURL: url))
        #expect(second.preferredRecordsScale == .life)
        await second.refreshLifeSummary(now: now)
        #expect(second.cachedLifeViewModel == first)
        var edited = try #require(second.records.state.lifeProfile)
        edited.retirementOn = .yearOnly(2055)
        second.records.updateLifeProfile(edited)
        #expect(second.cachedLifeViewModel == first)
        await second.refreshLifeSummary(now: now)
        #expect(second.cachedLifeViewModel != first)
        second.records.erase(.lifeProfile, key: LifeProfile.profileID.uuidString)
        await second.refreshLifeSummary(now: now)
        #expect(second.cachedLifeViewModel == nil)
        #expect(!FileManager.default.fileExists(atPath: try #require(second.records.lifeSummaryCacheURL).path))
    }
}
