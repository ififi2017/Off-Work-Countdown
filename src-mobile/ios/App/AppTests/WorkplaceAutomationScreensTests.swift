import CoreLocation
import Foundation
import Testing
@testable import App

/// Plan 021 U1: what the settings and review screens show, and the batch
/// preview matching what adoption writes.
@MainActor
@Suite("Workplace automation screens")
struct WorkplaceAutomationScreensTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private static func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1_000 }

    private static func shift(day: Int) -> AutomationShift {
        let key = "2026-11-\(String(format: "%02d", day))"
        return AutomationShift(
            shiftKey: "\(key)#day", anchorDayKey: key, plannedStart: at(day, 9), plannedEnd: at(day, 17),
            segments: [
                NativeShiftSegment(startAtMs: ms(at(day, 9)), endAtMs: ms(at(day, 12))),
                NativeShiftSegment(startAtMs: ms(at(day, 13)), endAtMs: ms(at(day, 17))),
            ]
        )
    }

    private static func hours() -> ScheduleHoursConfiguration {
        .init(startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: "12:00", breakDurationMinutes: 60)
    }

    @MainActor
    private final class Harness {
        let suite = "WorkplaceAutomationScreens.\(UUID())"
        let defaults: UserDefaults
        let records = RecordCoordinator.inMemory()
        let actions: RecordsActions
        let coordinator: WorkplaceAutomationCoordinator
        var workplace: SavedWorkplace!

        init() {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
            defaults.set("en", forKey: "ios.native.languageOverride")
            let preferences = PreferencesStore(defaults: defaults, records: records)
            let plus = PlusEntitlement(defaults: defaults)
            plus.debugSetAuthorized(true)
            actions = RecordsActions(records: records, preferences: preferences, plus: plus,
                text: AppText(preferences: preferences), currentHours: { _ in WorkplaceAutomationScreensTests.hours() })
            coordinator = WorkplaceAutomationCoordinator(actions: actions, loaded: .missing) { _ in }
            coordinator.update { state in
                state.settings.isMonitoringEnabled = true
                self.workplace = try! state.addWorkplace(name: "Office", latitude: 31, longitude: 121)
            }
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        var presenter: WorkplaceAutomationPresenter {
            WorkplaceAutomationPresenter(text: actions.text, timeZone: TimeZone(identifier: "UTC")!,
                                         locale: Locale(identifier: "en_GB"))
        }

        func receive(_ type: AutomationEventType, at time: Date, day: Int,
                     source: AutomationEventSource = .nativeGeofence) async -> AutomationCommandOutcome {
            let event = AutomationEvent(
                id: UUID(), source: source, type: type,
                workplaceID: source == .nativeGeofence ? workplace.id : nil,
                registrationGeneration: source == .nativeGeofence ? workplace.registrationGeneration : 0,
                observedAt: time, receivedAt: time,
                timestampBasis: source == .nativeGeofence ? .systemObservation : .callbackReceipt
            )
            return await coordinator.receive(event, shifts: [WorkplaceAutomationScreensTests.shift(day: day)], now: time)
        }
    }

    @Test("Suggestions list newest day first, start before end, with their reason and source")
    func reviewItems() async throws {
        let harness = Harness()
        _ = await harness.receive(.enterInner, at: Self.at(9, 9, 10), day: 9)
        _ = await harness.receive(.exitOuter, at: Self.at(9, 18), day: 9)
        _ = await harness.receive(.enterInner, at: Self.at(10, 8), day: 10, source: .appIntentAutomation)

        let items = harness.presenter.reviewItems(harness.coordinator.state)
        #expect(items.count == 3)
        let first = try #require(items.first)
        #expect(first.time == "08:00")
        #expect(first.planned == "09:00")
        #expect(first.source == .appIntentAutomation)
        #expect(first.note == harness.actions.text.t("automationUINoteEarlyStart"))
        #expect(items[1].boundary == .start)
        #expect(items[2].boundary == .end)
        #expect(items[1].dayTitle == items[2].dayTitle)
        #expect(items[1].dayTitle != first.dayTitle)
    }

    @Test("The preview shows the day as adoption will write it")
    func previewMatchesAdoption() async throws {
        let harness = Harness()
        _ = await harness.receive(.enterInner, at: Self.at(9, 9, 10), day: 9)
        _ = await harness.receive(.exitOuter, at: Self.at(9, 18), day: 9)
        let ids = harness.coordinator.state.pendingProposals.map(\.id)

        let preview = harness.coordinator.previewSegments(for: ids)
        let day = try #require(preview.first)
        #expect(preview.count == 1)
        let changes = harness.presenter.changes(preview) { _ in nil }
        #expect(changes.first?.before == "09:00–17:00")
        #expect(changes.first?.after == "09:10–18:00")

        _ = await harness.coordinator.applyReviewed(ids)
        let written = try #require(harness.records.state.overrides.first { $0.dayKey == "2026-11-09" })
        #expect(written.segments == day.segments)
    }

    @Test("Adopted times can be undone from the recent list until undone")
    func recentItems() async throws {
        let harness = Harness()
        _ = await harness.receive(.exitOuter, at: Self.at(9, 18), day: 9)
        let id = try #require(harness.coordinator.state.pendingProposals.first?.id)
        _ = await harness.coordinator.applyReviewed([id], now: Self.at(9, 19))

        let recent = harness.presenter.recentItems(harness.coordinator.state, now: Self.at(9, 20))
        #expect(recent.map(\.id) == [id])
        #expect(recent.first?.summary.contains("18:00") == true)
        #expect(harness.presenter.recentItems(harness.coordinator.state, now: Self.at(20, 20)).isEmpty)

        #expect(await harness.coordinator.undo(commandID: id, now: Self.at(9, 21)) == .applied)
        #expect(harness.presenter.recentItems(harness.coordinator.state, now: Self.at(9, 22)).isEmpty)
    }

    @Test("The most useful reason wins, and routine ones show nothing")
    func noteKeys() {
        #expect(WorkplaceAutomationPresenter.noteKey(for: [.automaticApplyOff]) == nil)
        #expect(WorkplaceAutomationPresenter.noteKey(for: [.automaticApplyOff, .earlyStartNeedsConfirmation])
            == "automationUINoteEarlyStart")
        #expect(WorkplaceAutomationPresenter.noteKey(for: [.earlyStartNeedsConfirmation, .recordChangedByPerson])
            == "automationUINoteChangedByYou")
        let localizer = NativeLocalizer()
        for reason in [AutomationReviewReason.staleEvent, .beyondAutomaticWindow, .leftBeforePlannedEnd, .recordsUnavailable] {
            let key = try? #require(WorkplaceAutomationPresenter.noteKey(for: [reason]))
            #expect(key.map { localizer.string($0, locale: "en") != $0 } == true)
        }
    }

    @Test("Location access maps to what the settings page explains")
    func locationAccess() {
        typealias Service = WorkplaceLocationService
        #expect(Service.access(status: .notDetermined, accuracy: .fullAccuracy) == .notRequested)
        #expect(Service.access(status: .denied, accuracy: .fullAccuracy) == .denied)
        #expect(Service.access(status: .restricted, accuracy: .fullAccuracy) == .denied)
        #expect(Service.access(status: .authorizedWhenInUse, accuracy: .reducedAccuracy) == .whenInUseOnly)
        #expect(Service.access(status: .authorizedAlways, accuracy: .reducedAccuracy) == .reducedAccuracy)
        #expect(Service.access(status: .authorizedAlways, accuracy: .fullAccuracy) == .always)
    }
}
