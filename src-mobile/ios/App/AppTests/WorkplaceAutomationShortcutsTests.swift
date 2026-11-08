import Foundation
import Testing
@testable import App

/// Plan 021 I1: planned shifts from the real schedule, and the Shortcuts
/// actions' outcomes.
@MainActor
@Suite("Workplace automation Shortcuts")
struct WorkplaceAutomationShortcutsTests {
    private static func hours() -> ScheduleHoursConfiguration {
        .init(startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: "12:00", breakDurationMinutes: 60)
    }

    @MainActor
    private final class Harness {
        let suite = "WorkplaceAutomationShortcuts.\(UUID())"
        let defaults: UserDefaults
        let records = RecordCoordinator.inMemory()
        let actions: RecordsActions
        let queries: RecordsQueries

        init() {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
            let preferences = PreferencesStore(defaults: defaults, records: records)
            let plus = PlusEntitlement(defaults: defaults)
            plus.debugSetAuthorized(true)
            actions = RecordsActions(records: records, preferences: preferences, plus: plus,
                text: AppText(preferences: preferences), currentHours: { _ in WorkplaceAutomationShortcutsTests.hours() })
            queries = RecordsQueries(records: records, plus: plus, localizer: actions.text.localizer,
                sources: .init(calendar: { preferences.recordsCalendar }, hours: { _ in WorkplaceAutomationShortcutsTests.hours() },
                    rules: { _, _ in nil }, snapshot: { _ in nil }, isCounting: { false },
                    salaryIsVisible: { false }, salaryType: { nil }, language: { "en" }))
            let records = records
            let calendar = preferences.recordsCalendar
            let zone = preferences.recordsTimeZone
            _ = records.submitCommand {
                records.ensureSeeded(
                    hours: WorkplaceAutomationShortcutsTests.hours(),
                    at: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
                    timeZone: zone
                )
            }
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        var calendar: Calendar { actions.preferences.recordsCalendar }

        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
    }

    // MARK: Shift adapter

    @Test("A weekday yields its planned shift with lunch, a weekend none")
    func plannedShifts() throws {
        let harness = Harness()
        // Monday 9 November 2026.
        let shifts = harness.queries.automationShifts(around: harness.at(9, 10))
        let monday = try #require(shifts.first { $0.anchorDayKey == "2026-11-09" })
        #expect(monday.plannedStart == harness.at(9, 9))
        #expect(monday.plannedEnd == harness.at(9, 17))
        #expect(monday.segments.count == 2)
        #expect(monday.shiftKey.hasPrefix("2026-11-09#"))
        // Sunday 8 November is a rest day.
        #expect(!shifts.contains { $0.anchorDayKey == "2026-11-08" })
        #expect(shifts.contains { $0.anchorDayKey == "2026-11-10" })
    }

    @Test("A holiday or a day marked not working has no shift to match")
    func restDays() {
        let harness = Harness()
        #expect(harness.actions.markCalendarException(dayKey: "2026-11-10", effect: .rest).synchronousResult)
        #expect(harness.actions.markDayNotWorking(dayKey: "2026-11-11").synchronousResult)
        let tuesday = harness.queries.automationShifts(around: harness.at(10, 10))
        #expect(!tuesday.contains { $0.anchorDayKey == "2026-11-10" })
        let wednesday = harness.queries.automationShifts(around: harness.at(11, 10))
        #expect(!wednesday.contains { $0.anchorDayKey == "2026-11-11" })
        #expect(wednesday.contains { $0.anchorDayKey == "2026-11-12" })
    }

    @Test("Adopted times do not move the plan they are compared against")
    func overrideIsNotThePlan() throws {
        let harness = Harness()
        #expect(harness.actions.saveCustomHours(dayKey: "2026-11-09", startMinutes: 10 * 60, endMinutes: 19 * 60).synchronousResult)
        let monday = try #require(harness.queries.automationShifts(around: harness.at(9, 10)).first { $0.anchorDayKey == "2026-11-09" })
        #expect(monday.plannedStart == harness.at(9, 9))
        #expect(monday.plannedEnd == harness.at(9, 17))
    }

    // MARK: Actions

    @Test("Confirming work finished applies even before the planned end or inside a workplace")
    func confirmFinished() async throws {
        let harness = Harness()
        let coordinator = WorkplaceAutomationCoordinator(actions: harness.actions, loaded: .missing) { _ in }
        var workplace: SavedWorkplace!
        coordinator.update { state in
            state.settings.isMonitoringEnabled = true
            workplace = try! state.addWorkplace(name: "Office", latitude: 31, longitude: 121)
        }
        let shifts = harness.queries.automationShifts(around: harness.at(9, 10))
        let arrival = AutomationEvent(
            id: UUID(), source: .nativeGeofence, type: .enterInner, workplaceID: workplace.id,
            registrationGeneration: workplace.registrationGeneration, observedAt: harness.at(9, 8, 55),
            receivedAt: harness.at(9, 8, 55), timestampBasis: .systemObservation
        )
        _ = await coordinator.receive(arrival, shifts: shifts, now: harness.at(9, 8, 55))
        #expect(coordinator.state.insideWorkplaceIDs == [workplace.id])

        let finished = AutomationEvent(
            id: UUID(), source: .userConfirmation, type: .exitOuter, workplaceID: nil,
            registrationGeneration: 0, observedAt: harness.at(9, 15, 30), receivedAt: harness.at(9, 15, 30),
            timestampBasis: .userAction
        )
        #expect(await coordinator.receive(finished, shifts: shifts, now: harness.at(9, 15, 30)) == .applied)
        let day = try #require(harness.records.state.overrides.first { $0.dayKey == "2026-11-09" })
        #expect(day.segments.last?.endAtMs == harness.at(9, 15, 30).timeIntervalSince1970 * 1_000)
    }

    @Test("A Shortcuts report of an early departure stays a trace")
    func reportedEarlyDeparture() async {
        let harness = Harness()
        let coordinator = WorkplaceAutomationCoordinator(actions: harness.actions, loaded: .missing) { _ in }
        coordinator.update { $0.settings.appliesDetectedTimesAutomatically = true }
        let shifts = harness.queries.automationShifts(around: harness.at(9, 10))
        let report = AutomationEvent(
            id: UUID(), source: .appIntentAutomation, type: .exitOuter, workplaceID: nil,
            registrationGeneration: 0, observedAt: harness.at(9, 15), receivedAt: harness.at(9, 15),
            timestampBasis: .callbackReceipt
        )
        #expect(await coordinator.receive(report, shifts: shifts, now: harness.at(9, 15)) == .ignored)
        #expect(harness.records.state.overrides.isEmpty)
    }

    @Test("Each outcome has its own message, and review never claims hours changed")
    func messages() {
        let outcomes: [AutomationCommandOutcome] = [
            .applied, .alreadyApplied, .recordedForReview, .needsReview, .ignored, .temporarilyUnavailable,
        ]
        let keys = outcomes.map(WorkplaceAutomationIntentRunner.messageKey(for:))
        #expect(Set(keys).count == outcomes.count)
        #expect(WorkplaceAutomationIntentRunner.messageKey(for: .recordedForReview) == "automationResultRecorded")
        let localizer = NativeLocalizer()
        for key in keys + ["automationResultNeedsPlus", "automationConfirmStartPrompt", "automationConfirmEndPrompt"] {
            #expect(localizer.string(key, locale: "en") != key)
        }
    }
}
