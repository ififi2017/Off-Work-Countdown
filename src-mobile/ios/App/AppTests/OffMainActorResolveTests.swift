import Foundation
import Testing

@testable import App

/// The Records and Life builds moved off the main actor by splitting the
/// schedule expansion (which owns a JavaScriptCore context and has to stay on
/// the main actor) from the day walk (which is pure Swift over value types).
/// The split is only safe while both halves still agree, and no other test
/// compares them: `lifeViewModel` and `prepareLifeViewModel` are separately
/// asserted to be correct, never asserted to be the same answer.
@MainActor
@Suite("Off-main-actor resolve agrees with the inline build")
struct OffMainActorResolveTests {
    private func seededStore(
        suite: String
    ) throws -> (store: OffWorkStore, defaults: UserDefaults, calendar: Calendar) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        let records = RecordCoordinator.inMemory()
        let store = OffWorkStore(defaults: defaults, records: records)
        store.plus.debugSetAuthorized(true)
        store.onboardingComplete = true
        store.scheduleMode = .classic
        store.workdays = [1, 2, 3, 4, 5]
        store.startMinutes = 9 * 60
        store.endMinutes = 17 * 60
        store.lunchEnabled = true
        store.lunchStartMinutes = 12 * 60
        store.lunchDurationMinutes = 60
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.recordsTimeZone
        return (store, defaults, calendar)
    }

    @Test("Life builds agree, including edits during loading", arguments: [false, true])
    func lifeModelSurvivesTheActorHop(editsDuringLoad: Bool) async throws {
        // Two stores rather than two calls on one: `prepareLifeViewModel`
        // fills `lifeViewModelCache`, so a follow-up `lifeViewModel` on the
        // same store would hand the async result back to itself and compare
        // nothing. Identical seeds make the comparison real again.
        let asyncSuite = "OffMainActorResolveTests.life.async.\(UUID().uuidString)"
        let inlineSuite = "OffMainActorResolveTests.life.inline.\(UUID().uuidString)"
        let (asyncStore, asyncDefaults, calendar) = try seededStore(suite: asyncSuite)
        let (inlineStore, inlineDefaults, _) = try seededStore(suite: inlineSuite)
        defer {
            asyncDefaults.removePersistentDomain(forName: asyncSuite)
            inlineDefaults.removePersistentDomain(forName: inlineSuite)
        }
        for store in [asyncStore, inlineStore] {
            store.saveLifeProfile(
                birthYear: 1990,
                workStartedYear: 2012,
                retirementAge: 60,
                sleepHours: 8,
                hidesExactAges: false
            )
        }
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 31, hour: 12
        )))

        let loading = Task.immediate { await asyncStore.prepareLifeViewModel(now: now) }
        if editsDuringLoad {
            for store in [asyncStore, inlineStore] {
                store.saveLifeProfile(
                    birthYear: 1990, workStartedYear: 2012, retirementAge: 65,
                    sleepHours: 7, hidesExactAges: false
                )
            }
        }
        let offMainActor = try #require(await loading.value)
        let inline = try #require(inlineStore.lifeViewModel(now: now))

        // Equality covers every week cell, both shares and the whole time
        // allocation, so a day walk that drifted across the hop would fail
        // here rather than quietly print a different life percentage.
        #expect(offMainActor == inline)
        #expect(!offMainActor.cells.isEmpty)
        #expect(offMainActor.workShare > 0)
    }

    @Test("Adding an annual bonus reuses the life projection, while profile edits invalidate it")
    func annualBonusKeepsLifeProjection() async throws {
        let suite = "OffMainActorResolveTests.bonus.\(UUID().uuidString)"
        let (store, defaults, calendar) = try seededStore(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.saveLifeProfile(
            birthYear: 1990, workStartedYear: 2012, retirementAge: 60,
            sleepHours: 8, hidesExactAges: false
        )
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 8, hour: 12
        )))
        let clock = ContinuousClock()
        let started = clock.now
        let original = try #require(await store.prepareLifeViewModel(now: now))
        let coldDuration = started.duration(to: clock.now)
        let key = store.lifeViewModelCacheKey(now: now)
        let revision = store.records.revision
        let salary = store.salaryAmount
        store.annualBonusEnabled = true
        store.annualBonusMonths = 2
        #expect(store.records.revision > revision)
        #expect(store.salaryAmount == salary)
        #expect(store.lifeViewModelCacheKey(now: now) == key)
        let updatedRevision = store.records.revision
        let refreshStarted = clock.now
        let refreshed = await store.prepareLifeViewModel(now: now)
        print("Life projection: cold=\(coldDuration), bonus refresh=\(refreshStarted.duration(to: clock.now))")
        #expect(refreshed == original)
        #expect(store.records.revision == updatedRevision)
        store.saveLifeProfile(
            birthYear: 1990, workStartedYear: 2012, retirementAge: 65,
            sleepHours: 7, hidesExactAges: false
        )
        #expect(store.lifeViewModelCacheKey(now: now) != key)
        let changed = try #require(await store.prepareLifeViewModel(now: now))
        #expect(changed != original)
    }

    @Test("The async day walk matches the inline walk day for day")
    func projectedDaysSurviveTheActorHop() async throws {
        let suite = "OffMainActorResolveTests.days.\(UUID().uuidString)"
        let (store, defaults, calendar) = try seededStore(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 31, hour: 12
        )))
        // From `now` forward: `ensureSeeded` opens the archive at `now`, so a
        // window ending before it resolves to no workdays at all and would
        // compare two empty walks.
        let from = calendar.startOfDay(for: now)
        let through = try #require(calendar.date(byAdding: .day, value: 29, to: from))

        let inline = store.resolvedDays(from: from, through: through, now: now)
        // One store, not two: `DayResolution` carries the period and snapshot
        // ids, which are freshly generated per store, so two separately seeded
        // stores never compare equal however identical their schedules. The
        // shared resolved-days cache is keyed on the archive revision, and an
        // observation bumps it without touching the resolve chain — which
        // reads periods, snapshots, exceptions and overrides, never
        // observations. That invalidates the cache and changes no answer.
        store.records.recordObservation(
            kind: .countdownStarted,
            eventID: UUID(),
            shiftAnchorDate: try #require(calendar.date(byAdding: .year, value: -1, to: now)),
            occurredAt: try #require(calendar.date(byAdding: .year, value: -1, to: now)),
            snapshotID: UUID(),
            timeZoneIdentifier: store.recordsTimeZone.identifier
        )
        let offMainActor = await store.prepareResolvedDays(from: from, through: through, now: now)

        #expect(offMainActor == inline)
        #expect(offMainActor.count == 30)
        #expect(offMainActor.contains { $0.isScheduledWorkday && !$0.segments.isEmpty })
    }
}
