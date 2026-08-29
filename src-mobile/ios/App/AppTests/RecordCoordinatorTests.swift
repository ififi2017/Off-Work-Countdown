import Foundation
import Testing
@testable import App

@MainActor
@Test("A retry reuses eventID and a second click is a new observation")
func observationEventIDIsIdempotentPerWrite() {
    let records = RecordCoordinator.inMemory()
    let day = startOf(2026, 8, 24)
    let snapshotID = UUID()
    let firstID = UUID()
    records.recordObservation(
        kind: .countdownStarted,
        eventID: firstID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: snapshotID
    )
    records.recordObservation(
        kind: .countdownStarted,
        eventID: firstID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: snapshotID
    )
    records.recordObservation(
        kind: .countdownStarted,
        eventID: UUID(),
        shiftAnchorDate: day,
        occurredAt: day.addingTimeInterval(1),
        snapshotID: snapshotID
    )
    #expect(records.state.observations.count == 2)
}

@MainActor
@Test("First-seen is once per shift day; start/stop/overtime stay distinct")
func observationKindsStayDistinct() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .off
    let monday = date(2026, 8, 24, 9)
    store.noteTimerSurfaceVisible(at: monday)
    store.noteTimerSurfaceVisible(at: monday.addingTimeInterval(60))
    store.startCountdown(at: monday)
    store.stopCountdown(at: monday.addingTimeInterval(30))
    store.startCountdown(at: monday.addingTimeInterval(45))
    store.applyOvertime(date: monday.addingTimeInterval(90))

    let kinds = store.records.state.observations.map(\.kind)
    #expect(kinds.filter { $0 == .timerSurfaceFirstSeen }.count == 1)
    #expect(kinds.filter { $0 == .countdownStarted }.count == 2)
    #expect(kinds.filter { $0 == .countdownStopped }.count == 1)
    #expect(kinds.filter { $0 == .overtimeDeclared }.count == 1)
}

@MainActor
@Test("Reconcile reconnects without writing another start")
func reconcileDoesNotRecordStart() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    let monday = date(2026, 8, 24, 10)
    store.startCountdown(at: monday)
    let afterStart = store.records.state.observations.filter { $0.kind == .countdownStarted }.count
    _ = store.reconcileCountdownSession(at: monday.addingTimeInterval(60))
    let afterReconcile = store.records.state.observations.filter { $0.kind == .countdownStarted }.count
    #expect(afterStart == 1)
    #expect(afterReconcile == 1)
}

@MainActor
@Test("Overnight first-seen keys the shift start day")
func overnightObservationKeysStartDay() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.startMinutes = 22 * 60
    store.endMinutes = 6 * 60
    store.workdays = [5]
    store.scheduleMode = .classic
    let saturdayMorning = date(2026, 8, 29, 1)
    store.noteTimerSurfaceVisible(at: saturdayMorning)
    let observation = store.records.state.observations.first { $0.kind == .timerSurfaceFirstSeen }
    #expect(observation != nil)
    #expect(OffWorkStore.dayKey(for: observation!.shiftAnchorDate) == "2026-08-28")
}

@MainActor
@Test("Deleted observations are not rebuilt from the same eventID")
func erasedObservationIsNotRecreated() {
    let records = RecordCoordinator.inMemory()
    let eventID = UUID()
    let day = startOf(2026, 8, 24)
    records.recordObservation(
        kind: .countdownStarted,
        eventID: eventID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: UUID()
    )
    records.erase(.workObservation, key: eventID.uuidString, at: day)
    records.recordObservation(
        kind: .countdownStarted,
        eventID: eventID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: UUID()
    )
    #expect(records.state.observations.isEmpty)
}

@MainActor
@Test("A seeded store can resolve a week of schedule days")
func resolvedDaysUseTheSeededSnapshot() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    let from = startOf(2026, 8, 24)
    let through = startOf(2026, 8, 30)
    let days = store.resolvedDays(from: from, through: through)
    #expect(days.count == 7)
    #expect(days.filter(\.isScheduledWorkday).count == 5)
    #expect(days[0].layer == .schedule)
    #expect(days[5].isScheduledWorkday == false)
}

@MainActor
@Test("Coordinator export then import after erase still skips")
func coordinatorImportHonorsErasedIDs() throws {
    let records = RecordCoordinator.inMemory()
    let hours = ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
    records.ensureSeeded(hours: hours, at: startOf(2026, 8, 24))
    let periodID = records.state.periods[0].id
    let data = try records.exportJSON(exportedAt: startOf(2026, 8, 24), timeZone: TimeZone(secondsFromGMT: 0)!)
    records.erase(.careerPeriod, key: periodID.uuidString, at: startOf(2026, 8, 25))
    let report = try records.import(data, mode: .skipErased)
    #expect(report.skippedErased[.careerPeriod] == 1)
    #expect(records.state.periods.isEmpty)
}

@MainActor
private func isolatedRecordDefaults() -> UserDefaults {
    let suite = "RecordCoordinatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func startOf(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
}

@MainActor
private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
}
