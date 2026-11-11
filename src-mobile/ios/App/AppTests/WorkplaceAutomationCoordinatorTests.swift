import Foundation
import Testing
@testable import App

/// Plan 021 P1: automation commands write adopted times through the record
/// command layer, once, and never over a person's own edit (§3.3–§3.6).
@MainActor
@Suite("Workplace automation commands")
struct WorkplaceAutomationCoordinatorTests {
    private static let dayKey = "2026-11-09"

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: hour, minute: minute))!
    }

    private static func segment(_ from: Date, _ to: Date) -> NativeShiftSegment {
        NativeShiftSegment(startAtMs: from.timeIntervalSince1970 * 1_000, endAtMs: to.timeIntervalSince1970 * 1_000)
    }

    /// 09:00–17:00 with lunch 12:00–13:00, matching `hours()`.
    private static let shift = AutomationShift(
        shiftKey: "\(dayKey)#day",
        anchorDayKey: dayKey,
        plannedStart: at(9),
        plannedEnd: at(17),
        segments: [segment(at(9), at(12)), segment(at(13), at(17))]
    )

    private static func hours() -> ScheduleHoursConfiguration {
        .init(startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: "12:00", breakDurationMinutes: 60)
    }

    /// Everything a test needs, with the automation file held in memory.
    @MainActor
    private final class Harness {
        let defaults: UserDefaults
        let suite: String
        let records = RecordCoordinator.inMemory()
        let actions: RecordsActions
        var coordinator: WorkplaceAutomationCoordinator!
        var saved: WorkplaceAutomationState?
        var saves = 0
        var failingSave: Int?
        var workplace: SavedWorkplace!

        init(plus: Bool = true, applies: Bool = false, loaded: WorkplaceAutomationArchive.LoadResult = .missing) {
            suite = "WorkplaceAutomationCoordinator.\(UUID())"
            defaults = UserDefaults(suiteName: suite)!
            defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
            let preferences = PreferencesStore(defaults: defaults, records: records)
            let entitlement = PlusEntitlement(defaults: defaults)
            entitlement.debugSetAuthorized(plus)
            actions = RecordsActions(records: records, preferences: preferences, plus: entitlement,
                text: AppText(preferences: preferences), currentHours: { _ in WorkplaceAutomationCoordinatorTests.hours() })
            coordinator = WorkplaceAutomationCoordinator(actions: actions, loaded: loaded) { [unowned self] state in
                saves += 1
                if saves == failingSave { throw CocoaError(.fileWriteUnknown) }
                saved = state
            }
            coordinator.update { state in
                state.settings.isMonitoringEnabled = true
                state.settings.appliesDetectedTimesAutomatically = applies
                self.workplace = try! state.addWorkplace(name: "Office", latitude: 31, longitude: 121)
            }
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        func event(_ type: AutomationEventType, at time: Date, source: AutomationEventSource = .nativeGeofence) -> AutomationEvent {
            AutomationEvent(
                id: UUID(), source: source, type: type, workplaceID: source == .nativeGeofence ? workplace.id : nil,
                registrationGeneration: workplace.registrationGeneration, observedAt: time, receivedAt: time,
                timestampBasis: .systemObservation
            )
        }

        func receive(_ type: AutomationEventType, at time: Date) async -> AutomationCommandOutcome {
            await coordinator.receive(event(type, at: time), shifts: [WorkplaceAutomationCoordinatorTests.shift], now: time)
        }

        var override: DayOverride? {
            records.state.overrides.first { $0.dayKey == WorkplaceAutomationCoordinatorTests.dayKey }
        }

        var provenance: WorkTimeProvenance? {
            records.state.workTimeProvenance.first { $0.dayKey == WorkplaceAutomationCoordinatorTests.dayKey }
        }
    }

    // MARK: Review by default

    @Test("With automatic apply off, a late arrival is kept for review and the day is untouched")
    func reviewOnly() async {
        let harness = Harness()
        let arrival = harness.event(.enterInner, at: Self.at(9, 10))
        let first = await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 10))
        #expect(first == .recordedForReview)
        #expect(harness.override == nil)
        #expect(harness.coordinator.state.pendingProposals.count == 1)
        #expect(harness.coordinator.state.pendingProposals.first?.reasons == [.automaticApplyOff])

        // Redelivery returns the first result and adds nothing.
        let again = await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 11))
        #expect(again == .recordedForReview)
        #expect(harness.coordinator.state.pendingProposals.count == 1)
        #expect(harness.coordinator.state.events.count == 1)
    }

    @Test("Without Plus nothing new is collected")
    func notEntitled() async {
        let harness = Harness(plus: false, applies: true)
        #expect(await harness.receive(.enterInner, at: Self.at(9, 10)) == .ignored)
        #expect(harness.coordinator.state.proposals.isEmpty)
        #expect(harness.override == nil)
    }

    // MARK: Automatic apply

    @Test("Late arrival and late exit become the day's segments, lunch kept")
    func lateArrivalAndOvertime() async {
        let harness = Harness(applies: true)
        #expect(await harness.receive(.enterInner, at: Self.at(9, 10)) == .applied)
        #expect(harness.override?.segments == [Self.segment(Self.at(9, 10), Self.at(12)), Self.segment(Self.at(13), Self.at(17))])

        #expect(await harness.receive(.exitOuter, at: Self.at(18, 30)) == .applied)
        #expect(harness.override?.kind == .customSegments)
        #expect(harness.override?.segments == [Self.segment(Self.at(9, 10), Self.at(12)), Self.segment(Self.at(13), Self.at(18, 30))])
    }

    @Test("An on-time day writes no record")
    func plannedDayWritesNothing() async {
        let harness = Harness(applies: true)
        #expect(await harness.receive(.enterInner, at: Self.at(8, 45)) == .applied)
        #expect(await harness.receive(.exitOuter, at: Self.at(17)) == .applied)
        #expect(harness.override == nil)
    }

    @Test("Going out for lunch only leaves a trace")
    func lunchExit() async {
        let harness = Harness(applies: true)
        _ = await harness.receive(.enterInner, at: Self.at(8, 55))
        #expect(await harness.receive(.exitOuter, at: Self.at(12, 5)) == .ignored)
        #expect(harness.override == nil)
        #expect(harness.coordinator.state.pendingProposals.isEmpty)
    }

    @Test("An early arrival waits for the person even with automatic apply on")
    func earlyArrivalNeedsConfirmation() async throws {
        let harness = Harness(applies: true)
        #expect(await harness.receive(.enterInner, at: Self.at(8)) == .recordedForReview)
        #expect(harness.override == nil)
        let pending = try #require(harness.coordinator.state.pendingProposals.first)
        #expect(pending.reasons == [.earlyStartNeedsConfirmation])

        let batch = UUID()
        let results = await harness.coordinator.applyReviewed([pending.id], batchID: batch, now: Self.at(8, 40))
        #expect(results[pending.id] == .applied)
        #expect(harness.override?.segments.first == Self.segment(Self.at(8), Self.at(12)))
        #expect(harness.coordinator.state.receipt(for: pending.id)?.batchID == batch)

        // A second tap on the same suggestion does not apply it again.
        let again = await harness.coordinator.applyReviewed([pending.id], now: Self.at(8, 41))
        #expect(again[pending.id] == .applied)
        #expect(harness.override?.editCount == 1)
    }

    // MARK: Manual priority

    @Test("A person's edit wins: a later exit is kept for review and the shift is held")
    func personEditWins() async throws {
        let harness = Harness(applies: true)
        #expect(await harness.receive(.enterInner, at: Self.at(9, 10)) == .applied)
        #expect(harness.actions.saveCustomHours(dayKey: Self.dayKey, startMinutes: 9 * 60 + 30, endMinutes: 17 * 60).synchronousResult)
        let edited = harness.override

        #expect(await harness.receive(.exitOuter, at: Self.at(18)) == .needsReview)
        #expect(harness.override == edited)
        #expect(harness.coordinator.state.isSuppressed(Self.shift.shiftKey))
        let pending = try #require(harness.coordinator.state.pendingProposals.first)
        #expect(pending.reasons.contains(.recordChangedByPerson))

        // Later automatic events for that shift change nothing.
        #expect(await harness.receive(.exitOuter, at: Self.at(18, 5)) == .ignored)
        #expect(harness.override == edited)

        // Adopting it from the review list is the person's explicit choice.
        let results = await harness.coordinator.applyReviewed([pending.id], now: Self.at(19))
        #expect(results[pending.id] == .applied)
        #expect(harness.override?.segments.last == Self.segment(Self.at(13), Self.at(18)))
    }

    @Test("Undo restores the day while it is still automation's, then holds the shift")
    func undo() async throws {
        let harness = Harness(applies: true)
        let arrival = harness.event(.enterInner, at: Self.at(9, 10))
        #expect(await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 10)) == .applied)
        #expect(harness.override?.kind == .customSegments)

        #expect(await harness.coordinator.undo(commandID: arrival.id, now: Self.at(9, 20)) == .applied)
        #expect(harness.override?.kind == .cleared)
        #expect(harness.coordinator.state.isSuppressed(Self.shift.shiftKey))
        #expect(await harness.coordinator.undo(commandID: arrival.id, now: Self.at(9, 21)) == .alreadyApplied)
    }

    @Test("Undo never reverts a day the person changed afterwards")
    func undoAfterPersonEdit() async {
        let harness = Harness(applies: true)
        let arrival = harness.event(.enterInner, at: Self.at(9, 10))
        _ = await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 10))
        #expect(harness.actions.saveCustomHours(dayKey: Self.dayKey, startMinutes: 9 * 60 + 30, endMinutes: 17 * 60).synchronousResult)
        let edited = harness.override
        #expect(await harness.coordinator.undo(commandID: arrival.id, now: Self.at(9, 40)) == .needsReview)
        #expect(harness.override == edited)
    }

    // MARK: Durability

    @Test("If the event cannot be saved first, records are not touched")
    func envelopeFirst() async {
        let harness = Harness(applies: true)
        harness.failingSave = harness.saves + 1
        #expect(await harness.receive(.enterInner, at: Self.at(9, 10)) == .temporarilyUnavailable)
        #expect(harness.override == nil)
        #expect(harness.coordinator.state.events.isEmpty)
    }

    @Test("A retry after stopping between the record write and the receipt applies once")
    func crashWindow() async {
        let harness = Harness(applies: true)
        let arrival = harness.event(.enterInner, at: Self.at(9, 10))
        // Save 1 is the envelope, save 2 the receipt that is lost.
        harness.failingSave = harness.saves + 2
        #expect(await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 10)) == .applied)
        #expect(harness.coordinator.state.receipt(for: arrival.id) == nil)
        let editCount = harness.override?.editCount

        #expect(await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 11)) == .alreadyApplied)
        #expect(harness.override?.editCount == editCount)

        // The day stays automation's, so the exit still extends it.
        #expect(await harness.receive(.exitOuter, at: Self.at(17, 30)) == .applied)
        #expect(harness.override?.segments.last == Self.segment(Self.at(13), Self.at(17, 30)))
    }

    @Test("An unreadable automation file is never replaced")
    func unreadableStore() async {
        let harness = Harness(applies: true, loaded: .unreadable)
        #expect(!harness.coordinator.isAvailable)
        #expect(harness.saves == 0)
        let event = AutomationEvent(
            id: UUID(), source: .appIntentAutomation, type: .enterInner, workplaceID: nil,
            registrationGeneration: 0, observedAt: Self.at(9, 10), receivedAt: Self.at(9, 10),
            timestampBasis: .systemObservation
        )
        #expect(await harness.coordinator.receive(event, shifts: [Self.shift], now: Self.at(9, 10)) == .temporarilyUnavailable)
        #expect(harness.saves == 0)
        #expect(harness.override == nil)
    }

    @Test("Leaving one workplace while inside another does not end the day")
    func otherWorkplace() async {
        let harness = Harness(applies: true)
        var second: SavedWorkplace!
        harness.coordinator.update { second = try! $0.addWorkplace(name: "Lab", latitude: 31.01, longitude: 121.01) }
        _ = await harness.receive(.enterInner, at: Self.at(8, 55))
        let enterLab = AutomationEvent(
            id: UUID(), source: .nativeGeofence, type: .enterInner, workplaceID: second.id,
            registrationGeneration: second.registrationGeneration, observedAt: Self.at(17, 10),
            receivedAt: Self.at(17, 10), timestampBasis: .systemObservation
        )
        _ = await harness.coordinator.receive(enterLab, shifts: [Self.shift], now: Self.at(17, 10))
        #expect(await harness.receive(.exitOuter, at: Self.at(17, 20)) == .ignored)
        #expect(harness.override == nil)
    }

    // MARK: Provenance (C1)

    @Test("Each adopted boundary saves its minimal summary with the day, nothing about the place")
    func provenanceWrittenWithTheDay() async throws {
        let harness = Harness(applies: true)
        #expect(await harness.receive(.enterInner, at: Self.at(9, 10)) == .applied)
        #expect(await harness.receive(.exitOuter, at: Self.at(18, 30)) == .applied)

        let row = try #require(harness.provenance)
        #expect(row.boundaries.map(\.boundary) == [.start, .end])
        let start = try #require(row.boundary(.start))
        #expect(start.time == Self.at(9, 10))
        #expect(start.source == .nativeGeofence)
        #expect(start.observedAt == Self.at(9, 10))
        #expect(start.receivedAt == Self.at(9, 10))
        #expect(start.appliedAt == Self.at(9, 10))
        #expect(start.appliedBy == .automatic)
        #expect(start.batchID == nil)
        #expect(start.rulesVersion == WorkplaceAutomation.rulesVersion)
        #expect(start.evidenceLevel == .systemObservation)
        #expect(start.reasons.isEmpty)
        #expect(row.boundary(.end)?.time == Self.at(18, 30))
        #expect(harness.records.state.sync.rows.values.contains { $0.entityType == .workTimeProvenance && $0.dirty })

        let verification = WorkTimeProvenance.verification(of: .start, provenance: row, override: harness.override)
        #expect(verification == .verified(start))

        // What leaves the device names no workplace, place or coordinates.
        let payload = try #require(RecordsSyncPayload.encode(type: .workTimeProvenance, key: Self.dayKey, from: harness.records.state))
        let text = String(decoding: payload, as: UTF8.self)
        #expect(!text.contains(harness.workplace.id.uuidString))
        #expect(!text.contains("Office"))
        // Compare parsed values, not substrings: the payload also carries the
        // real edit time in milliseconds and a random tie-breaker UUID, either
        // of which can contain "121" by chance.
        var keys: [String] = []
        var numbers: [Double] = []
        func collect(_ value: Any) {
            switch value {
            case let object as [String: Any]:
                keys += object.keys
                object.values.forEach(collect)
            case let array as [Any]: array.forEach(collect)
            case let number as NSNumber: numbers.append(number.doubleValue)
            default: break
            }
        }
        collect(try JSONSerialization.jsonObject(with: payload))
        #expect(!keys.contains { ["lat", "lon", "coordinate", "workplace"].contains(where: $0.lowercased().contains) })
        #expect(!numbers.contains { $0 == 31 || $0 == 121 })
    }

    @Test("A reviewed adoption records how and in which batch, and keeps the reasons")
    func provenanceForReviewedAdoption() async throws {
        let harness = Harness(applies: true)
        #expect(await harness.receive(.enterInner, at: Self.at(8)) == .recordedForReview)
        #expect(harness.provenance == nil)
        let pending = try #require(harness.coordinator.state.pendingProposals.first)
        let batch = UUID()
        _ = await harness.coordinator.applyReviewed([pending.id], batchID: batch, now: Self.at(20))

        let start = try #require(harness.provenance?.boundary(.start))
        #expect(start.time == Self.at(8))
        #expect(start.appliedAt == Self.at(20))
        #expect(start.appliedBy == .reviewed)
        #expect(start.batchID == batch)
        #expect(start.source == .nativeGeofence)
        #expect(start.reasons == [AutomationReviewReason.earlyStartNeedsConfirmation.rawValue])
    }

    @Test("A later manual edit leaves the summary alone and verification lapses on display")
    func manualEditKeepsProvenance() async throws {
        let harness = Harness(applies: true)
        _ = await harness.receive(.enterInner, at: Self.at(9, 10))
        let before = try #require(harness.provenance)
        #expect(harness.actions.saveCustomHours(dayKey: Self.dayKey, startMinutes: 9 * 60, endMinutes: 17 * 60).synchronousResult)
        #expect(harness.provenance == before)
        let start = try #require(before.boundary(.start))
        #expect(WorkTimeProvenance.verification(of: .start, provenance: before, override: harness.override)
            == .adjustedAfterDetection(start))
        #expect(WorkTimeProvenance.verification(of: .end, provenance: before, override: harness.override) == .none)

        // Clearing the day keeps the summary too; it simply no longer matches.
        #expect(harness.actions.clearDayOverride(dayKey: Self.dayKey).synchronousResult)
        #expect(harness.provenance == before)
        #expect(WorkTimeProvenance.verification(of: .start, provenance: before, override: harness.override)
            == .adjustedAfterDetection(start))
    }

    @Test("Undo puts the summary back with the day: erased when there was none")
    func undoRestoresProvenance() async throws {
        let harness = Harness(applies: true)
        let arrival = harness.event(.enterInner, at: Self.at(9, 10))
        _ = await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 10))
        let afterStart = try #require(harness.provenance)
        let exit = harness.event(.exitOuter, at: Self.at(18))
        _ = await harness.coordinator.receive(exit, shifts: [Self.shift], now: Self.at(18))
        #expect(harness.provenance?.boundaries.count == 2)

        // Undoing the exit returns to the start-only summary.
        #expect(await harness.coordinator.undo(commandID: exit.id, now: Self.at(18, 5)) == .applied)
        #expect(harness.provenance?.boundaries == afterStart.boundaries)
    }

    @Test("Undoing the only adoption deletes the summary with a tombstone")
    func undoErasesProvenance() async throws {
        let harness = Harness(applies: true)
        let arrival = harness.event(.enterInner, at: Self.at(9, 10))
        _ = await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 10))
        #expect(harness.provenance != nil)
        #expect(await harness.coordinator.undo(commandID: arrival.id, now: Self.at(9, 20)) == .applied)
        #expect(harness.provenance == nil)
        #expect(harness.records.state.isErased(.workTimeProvenance, key: Self.dayKey))
    }

    @Test("Deleting the evidence leaves a tombstone and keeps the adopted times")
    func deleteEvidence() async throws {
        let harness = Harness(applies: true)
        _ = await harness.receive(.enterInner, at: Self.at(9, 10))
        let override = harness.override
        #expect(harness.actions.deleteWorkTimeProvenance(dayKey: Self.dayKey).synchronousResult)
        #expect(harness.provenance == nil)
        #expect(harness.records.state.isErased(.workTimeProvenance, key: Self.dayKey))
        #expect(harness.records.state.sync.rows.values.contains { $0.entityType == .workTimeProvenance && $0.pendingErase })
        #expect(harness.override == override)
        #expect(!harness.actions.deleteWorkTimeProvenance(dayKey: Self.dayKey).synchronousResult)

        // A later adoption on that day records it again above the tombstone.
        _ = await harness.receive(.exitOuter, at: Self.at(18))
        #expect(harness.provenance?.boundary(.end)?.time == Self.at(18))
        #expect(!harness.records.state.isErased(.workTimeProvenance, key: Self.dayKey))
    }

    @Test("A retry after the receipt was lost writes the summary once")
    func provenanceSurvivesCrashWindow() async throws {
        let harness = Harness(applies: true)
        let arrival = harness.event(.enterInner, at: Self.at(9, 10))
        harness.failingSave = harness.saves + 2
        _ = await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 10))
        let first = try #require(harness.provenance)
        #expect(await harness.coordinator.receive(arrival, shifts: [Self.shift], now: Self.at(9, 11)) == .alreadyApplied)
        #expect(harness.provenance == first)
    }
}
