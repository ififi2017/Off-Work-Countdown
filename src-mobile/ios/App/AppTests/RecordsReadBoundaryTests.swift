import Foundation
import Testing
@testable import App

@MainActor
@Suite("Records read boundaries")
struct RecordsReadBoundaryTests {
    @Test("Reading an empty archive never creates history", arguments: ["sync", "prepared", "display"])
    func emptyReadsDoNotWrite(query: String) async throws {
        let suite = "RecordsRead.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        store.preferences.onboardingComplete = true
        store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
        let day = try date(store)
        let before = store.records.state
        let revision = store.records.revision
        var dirty = 0
        store.records.onDirty = { dirty += 1 }
        switch query {
        case "sync": _ = store.queries.resolvedDays(from: day, through: day, now: day)
        case "prepared": _ = await store.queries.prepareResolvedDays(from: day, through: day, now: day)
        default: _ = await store.queries.prepareRecordsDisplayDays(from: day, through: day, now: day)
        }
        #expect(store.records.state == before)
        #expect(store.records.revision == revision)
        #expect(dirty == 0)
    }

    @Test("Reading an existing archive never silently repairs its schedule")
    func readsDoNotReconcile() async throws {
        let suite = "RecordsReadExisting.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        store.preferences.onboardingComplete = true
        store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
        let day = try date(store)
        store.records.ensureSeeded(hours: store.session.hoursConfiguration(at: day), at: day, timeZone: store.preferences.recordsTimeZone)
        store.preferences.applyPreferences { $0.startMinutes = 8 * 60 }
        let before = store.records.state
        let revision = store.records.revision
        _ = store.queries.resolvedDays(from: day, through: day, now: day)
        _ = await store.queries.prepareResolvedDays(from: day, through: day, now: day)
        _ = await store.queries.prepareRecordsDisplayDays(from: day, through: day, now: day)
        #expect(store.records.state == before)
        #expect(store.records.revision == revision)
        #expect(store.shifts.reconcileRecordSchedule(at: day).synchronousResult)
        #expect(store.records.state.snapshots != before.snapshots)
    }

    @Test("Lifecycle reconciliation seeds a fresh archive once", arguments: [false, true])
    func lifecycleSeedsOnce(inBatch: Bool) throws {
        let suite = "RecordsLifecycleSeed.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        store.preferences.onboardingComplete = true
        store.preferences.applyPreferences { $0.recordsTimeZoneIdentifier = "UTC" }
        let day = try date(store)
        var dirty = 0
        store.records.onDirty = { dirty += 1 }
        func reconcileTwice() {
            #expect(store.shifts.reconcileRecordSchedule(at: day).synchronousResult)
            #expect(!store.records.state.periods.isEmpty)
            #expect(!store.records.state.snapshots.isEmpty)
            let before = store.records.state
            #expect(!store.shifts.reconcileRecordSchedule(at: day).synchronousResult)
            #expect(store.records.state == before)
        }
        if inBatch {
            store.records.withBatchedWrites {
                reconcileTwice()
                #expect(dirty == 0)
            }
        } else {
            reconcileTwice()
        }
        #expect(dirty == 1)
    }

    private func date(_ store: AppRuntime) throws -> Date {
        try #require(store.preferences.recordsCalendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
    }
}
