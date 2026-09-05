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
    private func seededStore(days: Int) throws -> OffWorkStore {
        let defaults = UserDefaults(suiteName: "owc.perf.\(UUID().uuidString)")!
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.startOfDay(for: .now)

        let records = RecordCoordinator.inMemory()
        let firstDay = try #require(calendar.date(byAdding: .day, value: -(days - 1), to: today))
        records.ensureSeeded(
            hours: ScheduleHoursConfiguration(
                startTime: "22:00", endTime: "06:00", workdays: Array(0...6),
                schedule: NativeWorkSchedule(
                    mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                    singleWeekendWorkday: nil, rotationAnchorMs: nil,
                    rotationWorkDays: nil, rotationRestDays: nil
                ),
                breakStartTime: "02:00", breakDurationMinutes: 60
            ),
            at: firstDay, timeZone: zone
        )
        let store = OffWorkStore(defaults: defaults, records: records)
        store.onboardingComplete = true
        store.plus.debugSetAuthorized(true)
        store.recordsTimeZoneIdentifier = zone.identifier
        let snapshotID = try #require(records.state.snapshots.first?.id)
        for offset in 0..<days {
            guard let anchor = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for (kind, at) in [
                (WorkObservationKind.countdownStarted, anchor.addingTimeInterval(22 * 3600)),
                (WorkObservationKind.countdownStopped, anchor.addingTimeInterval(30 * 3600)),
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
    func surfaceCost() async throws {
        let store = try seededStore(days: 520)
        // Warm the JavaScriptCore bundle and any lazily-built caches so the
        // numbers describe the steady state a user actually pays.
        let window = store.recordsWindow(for: .year, anchor: .now)
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

        // A month of cells is what the calendar draws on every load, and each
        // one now also intersects the night before. This is the regression
        // gate for that: a screen recording cannot catch it getting slower.
        let calendar = store.recordsCalendar
        let today = calendar.startOfDay(for: .now)
        let end = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let start = try #require(calendar.date(byAdding: .day, value: -32, to: today))
        let month = store.resolvedDays(from: start, through: end)
        var monthCells: [RecordsDayCell] = []
        let cellsMs = milliseconds("recordsDayCell with adjacent shifts, one month") {
            monthCells = month.enumerated().dropFirst().map { index, day in
                store.recordsDayCell(
                    for: day,
                    previous: index > 0 ? month[index - 1] : nil,
                    includesLifeProjection: true
                )
            }
        }
        let dayKey = try #require(month.last?.dayKey)
        var canvas: RecordsDayCanvasModel?
        let canvasMs = await milliseconds("recordsDayCanvas (one day, both shifts)") {
            canvas = await store.recordsDayCanvas(dayKey: dayKey)
        }
        let rendered = try #require(canvas)
        #expect(!rendered.isLocked)
        #expect(rendered.allocation.workMs > 0)
        #expect(Set(rendered.intervals.compactMap(\.anchorDayKey)).count >= 2)
        #expect(monthCells.allSatisfy { $0.appearance != .locked && $0.workMs > 0 })

        store.saveLifeProfile(
            birthYear: 1992,
            workStartedYear: 2014,
            retirementAge: 65,
            sleepHours: 8,
            hidesExactAges: false
        )
        // Cold, then warm. The first line is what a user pays once, after an
        // edit or on the first visit; the second is what returning to the tab
        // costs now that the model is cached, and used to cost the first line
        // every single time.
        let lifePrepareMs = await milliseconds("prepareLifeViewModel (cold, whole career)") {
            _ = await store.prepareLifeViewModel()
        }
        let lifeMs = milliseconds("lifeViewModel (warm, cached)") {
            _ = store.lifeViewModel()
        }

        #expect(store.recordedWorkDays().count == 520)
        #expect(year.count >= 365)
        #expect(monthCells.count == 31)
        #expect(yearMs < 15_000)
        #expect(cellsMs < 5_000)
        #expect(canvasMs < 5_000)
        #expect(lifePrepareMs < 20_000)
        #expect(lifeMs < 20_000)
    }
}
