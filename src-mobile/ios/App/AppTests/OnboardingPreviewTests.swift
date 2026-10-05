import Foundation
import Testing
@testable import App

@MainActor
@Suite("Onboarding schedule preview")
struct OnboardingPreviewTests {
    @Test("First-run preview follows the selected holiday calendar without saving it",
          arguments: ["CN", ""])
    func holidayDraftMatchesCompletion(region: String) throws {
        let suite = "OnboardingPreview.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Asia/Shanghai", forKey: "ios.native.recordsTimeZone")
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        _ = runtime.preferences.applyPreferences {
            $0.scheduleMode = .classic
            $0.workdays = [1, 2, 3, 4, 5]
            $0.startMinutes = 540
            $0.endMinutes = 1020
            $0.lunchEnabled = true
            $0.lunchStartMinutes = 720
            $0.lunchDurationMinutes = 60
            $0.microBreakEnabled = true
            $0.microBreakIntervalMinutes = 60
        }.synchronousResult
        let calendar = runtime.preferences.recordsCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 0)))
        let scene = SceneState()
        scene.onboardingHolidayRegionIdentifier = region
        let revision = runtime.records.revision
        let preview = try #require(scene.setupPreview(at: now, using: runtime.shifts))
        let start = try #require(preview.upcoming.first { $0.id == "shift-start" }?.date)
        let end = try #require(preview.upcoming.first { $0.id == "shift-end" }?.date)
        let health = try #require(preview.upcoming.first { $0.id == "micro-break" }?.date)
        #expect(calendar.component(.day, from: start) == (region == "CN" ? 8 : 5))
        #expect(calendar.isDate(health, inSameDayAs: start))
        #expect(calendar.component(.hour, from: health) == 10)
        if region == "CN" {
            #expect(preview.upcoming.first { $0.id == "shift-end" }?.detail == nil)
        }
        #expect(preview.upcoming.compactMap(\.date).allSatisfy { $0 >= start && $0 <= end })
        #expect(runtime.records.revision == revision)
        #expect(!runtime.preferences.onboardingComplete)

        _ = runtime.shifts.completeSetup(holidayRegionIdentifier: region, at: now).synchronousResult
        let saved = try #require(runtime.shifts.session.snapshot(at: now))
        #expect(start == (saved.isWorkday ? saved.startDate : saved.nextShiftStartDate))
        #expect(end == (saved.isWorkday ? saved.endDate : saved.nextShiftEndDate))
        // Replaying welcome must keep the saved plan even if a draft differs.
        scene.onboardingHolidayRegionIdentifier = region == "CN" ? "" : "CN"
        let replay = try #require(scene.setupPreview(at: now, using: runtime.shifts))
        #expect(replay.upcoming.first { $0.id == "shift-start" }?.date == start)
    }

    @Test("Completed shifts advance the preview; an overnight shift in progress stays put")
    func previewResolvesAfterEndAndOvernight() throws {
        let suite = "OnboardingAfterEnd.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Asia/Shanghai", forKey: "ios.native.recordsTimeZone")
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        _ = runtime.preferences.applyPreferences {
            $0.scheduleMode = .classic
            $0.workdays = [1, 2, 3, 4, 5]
            $0.startMinutes = 540
            $0.endMinutes = 1020
            $0.lunchEnabled = false
        }.synchronousResult
        let scene = SceneState()
        scene.onboardingHolidayRegionIdentifier = ""
        let calendar = runtime.preferences.recordsCalendar
        func date(_ day: Int, _ hour: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)))
        }
        let evening = try date(5, 19)
        let next = try #require(scene.setupProjection(at: evening, using: runtime.shifts))
        #expect(next.snapshot.startDate == (try date(6, 9)))
        _ = runtime.preferences.applyPreferences {
            $0.startMinutes = 22 * 60
            $0.endMinutes = 6 * 60
        }.synchronousResult
        let overnight = try #require(scene.setupProjection(at: date(6, 2), using: runtime.shifts))
        #expect(overnight.snapshot.startDate == (try date(5, 22)))
        #expect(overnight.snapshot.endDate == (try date(6, 6)))
    }

    @Test("Manual timing has no invented upcoming shift")
    func manualTimingHasNoPreview() throws {
        let suite = "OnboardingManualPreview.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        _ = runtime.preferences.applyPreferences { $0.scheduleMode = .off }.synchronousResult
        #expect(SceneState().setupPreview(using: runtime.shifts) == nil)
    }
}
