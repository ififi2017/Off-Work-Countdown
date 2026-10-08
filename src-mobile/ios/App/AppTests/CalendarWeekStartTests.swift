import Foundation
import Observation
import Synchronization
import Testing
@testable import App

@MainActor
@Suite("Device calendar week start")
struct CalendarWeekStartTests {
    @Test("Without a selection, all calendars follow the app locale", arguments: ["en", "de"])
    func followsLocale(languageCode: String) throws {
        let suite = "CalendarWeekStartLocale.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        defaults.set(languageCode, forKey: "ios.native.languageOverride")
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        let expected = languageCode == "de" ? 2 : 1
        #expect(runtime.preferences.calendarFirstWeekday == nil)
        #expect(runtime.preferences.recordsCalendar.firstWeekday == expected)
        #expect(runtime.queries.recordsGridCalendar.firstWeekday == expected)
        #expect(runtime.preferences.recordsCalendar.timeZone.identifier == "GMT")
        let otherLanguage = languageCode == "de" ? "en" : "de"
        runtime.preferences.applyPreferences { $0.languageOverride = otherLanguage }
        #expect(runtime.preferences.recordsCalendar.firstWeekday == (otherLanguage == "de" ? 2 : 1))
        #expect(runtime.queries.recordsGridCalendar.firstWeekday == runtime.preferences.recordsCalendar.firstWeekday)
    }

    @Test("Sunday and Monday update records, schedule and leave layouts and survive reopening",
          arguments: ["en", "de"], [1, 2])
    func selectionPersists(languageCode: String, weekday: Int) throws {
        let suite = "CalendarWeekStartSelection.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Asia/Shanghai", forKey: "ios.native.recordsTimeZone")
        defaults.set(languageCode, forKey: "ios.native.languageOverride")
        let records = RecordCoordinator.inMemory()
        let runtime = AppRuntime(defaults: defaults, records: records)
        let archiveBefore = records.state
        let queries = runtime.queries
        // Warm the existing query/calendar cache before changing the setting.
        _ = queries.recordsGridCalendar
        let invalidated = Mutex(false)
        withObservationTracking {
            _ = queries.recordsGridCalendar
        } onChange: {
            invalidated.withLock { $0 = true }
        }
        runtime.preferences.setCalendarFirstWeekday(weekday)
        #expect(invalidated.withLock { $0 })
        let calendar = runtime.preferences.recordsCalendar
        #expect(calendar.firstWeekday == weekday)
        #expect(queries.recordsGridCalendar.firstWeekday == weekday)
        #expect(calendar.timeZone.identifier == "Asia/Shanghai")
        let october = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        // Records and the schedule editor share this same leading-cell query.
        #expect(queries.recordsGridLeadingBlanks(before: october) == (weekday == 1 ? 4 : 3))
        #expect(queries.recordsWeekdayGridSymbols().first == calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
        let day = try #require(ExtendedScheduleResolver.dayNumber(dayKey: "2026-10-01"))
        let leave = LeavePlanCalendarPage(containing: day, firstWeekday: calendar.firstWeekday)
        #expect(leave.days.first == ExtendedScheduleResolver.dayNumber(dayKey: weekday == 1 ? "2026-09-27" : "2026-09-28"))
        let week = queries.recordsWindow(for: .week, anchor: october)
        #expect(RecordJSON.dayKey(week.0, calendar: calendar) == (weekday == 1 ? "2026-09-27" : "2026-09-28"))
        #expect(queries.reportPeriod(.week, containing: october).startDayKey == (weekday == 1 ? "2026-09-27" : "2026-09-28"))
        #expect(records.state == archiveBefore)
        let reopened = AppRuntime(defaults: defaults, records: records)
        #expect(reopened.preferences.calendarFirstWeekday == weekday)
        #expect(reopened.queries.recordsGridCalendar.firstWeekday == weekday)
        reopened.preferences.applyPreferences { $0.languageOverride = languageCode == "de" ? "en" : "de" }
        reopened.preferences.reloadFromArchive()
        #expect(reopened.preferences.recordsCalendar.firstWeekday == weekday)
        #expect(reopened.queries.recordsGridCalendar.firstWeekday == weekday)
        #expect(defaults.integer(forKey: "ios.native.calendarFirstWeekday") == weekday)
    }

    @Test("Invalid stored week starts fall back, and invalid edits preserve the selection", arguments: [0, 3, 7, -1])
    func invalidSelection(stored: Int) throws {
        let suite = "CalendarWeekStartInvalid.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("de", forKey: "ios.native.languageOverride")
        defaults.set(stored, forKey: "ios.native.calendarFirstWeekday")
        let preferences = PreferencesStore(defaults: defaults, records: .inMemory())
        #expect(preferences.calendarFirstWeekday == nil)
        #expect(preferences.recordsCalendar.firstWeekday == 2)
        preferences.setCalendarFirstWeekday(1)
        preferences.setCalendarFirstWeekday(stored)
        #expect(preferences.calendarFirstWeekday == 1)
        #expect(defaults.integer(forKey: "ios.native.calendarFirstWeekday") == 1)
    }

    @Test("Changing week start reschedules future weekly report notifications")
    func weeklyNotifications() throws {
        let suite = "CalendarWeekStartNotifications.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        defaults.set("de", forKey: "ios.native.languageOverride")
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        runtime.plus.debugSetAuthorized(true)
        runtime.preferences.applyPreferences { $0.cycleEndSummaryNotificationEnabled = true }
        let calendar = runtime.preferences.recordsCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10)))
        runtime.preferences.setCalendarFirstWeekday(1)
        let sundaySignal = ServiceScheduleSignal(shifts: runtime.shifts)
        let sunday = try #require(runtime.shifts.cycleReportNotifications(at: now).first)
        runtime.preferences.setCalendarFirstWeekday(2)
        let monday = try #require(runtime.shifts.cycleReportNotifications(at: now).first)
        #expect(ServiceScheduleSignal(shifts: runtime.shifts) != sundaySignal)
        #expect(sunday.period.startDayKey == "2026-09-27")
        #expect(monday.period.startDayKey == "2026-09-28")
        #expect(RecordJSON.dayKey(sunday.fireDate, calendar: calendar) == "2026-10-04")
        #expect(RecordJSON.dayKey(monday.fireDate, calendar: calendar) == "2026-10-05")
    }
}
