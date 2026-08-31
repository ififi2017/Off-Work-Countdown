import Foundation
import Testing

@testable import App

/// Timing harness for the Records surfaces. It is not a wall-clock assertion
/// suite — CI machines vary too much for that. It exists so the cost of opening
/// the Year chart and the Life grid is a number someone can read, because "the
/// Records tab freezes on device" is otherwise diagnosed by guessing.
@MainActor
@Suite("Records surface cost")
struct RecordsPerformanceTests {
    /// Roughly two years of a normal shift: clock-in and clock-out every day.
    private func seededStore(days: Int) -> OffWorkStore {
        let defaults = UserDefaults(suiteName: "owc.perf.\(UUID().uuidString)")!
        let store = OffWorkStore(defaults: defaults, records: .inMemory())
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.startOfDay(for: .now)

        let snapshotID = UUID()
        for offset in 0..<days {
            guard let anchor = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for (kind, at) in [
                (WorkObservationKind.countdownStarted, anchor.addingTimeInterval(9 * 3600)),
                (WorkObservationKind.countdownStopped, anchor.addingTimeInterval(18 * 3600)),
            ] {
                store.records.recordObservation(
                    kind: kind,
                    eventID: UUID(),
                    shiftAnchorDate: anchor,
                    occurredAt: at,
                    snapshotID: snapshotID,
                    timeZoneIdentifier: zone.identifier
                )
            }
        }
        return store
    }

    /// `print` from a test bundle running in the simulator does not reach
    /// `xcodebuild`'s stdout, so the numbers went nowhere. Report them where
    /// they can actually be read back.
    private func milliseconds(_ label: String, _ body: () -> Void) -> Double {
        let started = Date()
        body()
        let elapsed = Date().timeIntervalSince(started) * 1_000
        let line = "[perf] \(label): \(String(format: "%.1f", elapsed)) ms"
        print(line)
        Self.report(line)
        return elapsed
    }

    private func milliseconds(_ label: String, _ body: () async -> Void) async -> Double {
        let started = Date()
        await body()
        let elapsed = Date().timeIntervalSince(started) * 1_000
        let line = "[perf] \(label): \(String(format: "%.1f", elapsed)) ms"
        print(line)
        Self.report(line)
        return elapsed
    }

    private static let reportURL = URL(fileURLWithPath: "/tmp/owc-records-perf.txt")

    private static func report(_ line: String) {
        let text = line + "\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: reportURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: reportURL)
        }
    }

    @Test("reports what one pass over the Records surfaces costs")
    func surfaceCost() async {
        let store = seededStore(days: 520)
        // Warm the JavaScriptCore bundle and any lazily-built caches so the
        // numbers describe the steady state a user actually pays.
        let window = store.recordsChartWindow(for: .year)
        _ = store.resolvedDays(from: window.0, through: window.1)

        _ = milliseconds("recordedWorkDays (Records list)") { _ = store.recordedWorkDays() }
        _ = milliseconds("exportRecordsFile (on demand)") { _ = try? store.exportRecordsFile() }

        var year: [DayResolution] = []
        let yearMs = milliseconds("resolvedDays, one year (cached)") {
            year = store.resolvedDays(from: window.0, through: window.1)
        }
        _ = milliseconds("recordsMetrics, one year") { _ = store.recordsMetrics(for: year) }
        _ = milliseconds("observations(on:) once per day for a year") {
            for day in year { _ = store.observations(on: day.shiftAnchorDate) }
        }

        store.saveLifeProfile(
            birthYear: 1992,
            workStartedYear: 2014,
            retirementAge: 65,
            sleepHours: 8,
            hidesExactAges: false
        )
        let lifePrepareMs = await milliseconds("prepareLifeViewModel (background expansion)") {
            _ = await store.prepareLifeViewModel()
        }
        let lifeMs = milliseconds("lifeViewModel (cached main-actor assembly)") {
            _ = store.lifeViewModel()
        }

        #expect(store.recordedWorkDays().count == 520)
        #expect(year.count >= 365)
        #expect(yearMs < 15_000)
        #expect(lifePrepareMs < 20_000)
        #expect(lifeMs < 20_000)
    }
}
