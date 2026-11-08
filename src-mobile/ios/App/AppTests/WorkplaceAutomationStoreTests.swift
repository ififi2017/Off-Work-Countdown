import Foundation
import Testing
@testable import App

/// Plan 021 §0.3: the device-only automation store.
@Suite("Workplace automation store")
struct WorkplaceAutomationStoreTests {
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)

    private static func event(
        _ type: AutomationEventType,
        workplace: SavedWorkplace,
        receivedAt: Date = now
    ) -> AutomationEvent {
        AutomationEvent(
            id: UUID(),
            source: .nativeGeofence,
            type: type,
            workplaceID: workplace.id,
            registrationGeneration: workplace.registrationGeneration,
            observedAt: receivedAt,
            receivedAt: receivedAt,
            timestampBasis: .systemObservation
        )
    }

    @Test("Five workplaces fit, a sixth is refused, and disabled ones still count")
    func workplaceLimit() throws {
        var state = WorkplaceAutomationState()
        for index in 0..<5 {
            try state.addWorkplace(name: "Office \(index)", latitude: 31, longitude: 121)
        }
        try state.updateWorkplace(state.workplaces[0].id, isEnabled: false)
        #expect(!state.canAddWorkplace)
        #expect(throws: WorkplaceAutomationError.workplaceLimitReached) {
            try state.addWorkplace(name: "Sixth", latitude: 31, longitude: 121)
        }
        state.removeWorkplace(state.workplaces[0].id)
        #expect(state.canAddWorkplace)
    }

    @Test("Default circles are 200 m inside and 300 m outside")
    func defaultRadii() throws {
        var state = WorkplaceAutomationState()
        let workplace = try state.addWorkplace(name: "Office", latitude: 31, longitude: 121)
        #expect(workplace.innerRadius == 200)
        #expect(workplace.outerRadius == 300)
    }

    @Test("Moving a workplace retires its registration; renaming does not")
    func registrationGeneration() throws {
        var state = WorkplaceAutomationState()
        let workplace = try state.addWorkplace(name: "Office", latitude: 31, longitude: 121)
        try state.updateWorkplace(workplace.id, name: "HQ")
        #expect(state.workplace(workplace.id)?.registrationGeneration == workplace.registrationGeneration)
        try state.updateWorkplace(workplace.id, latitude: 31.001)
        let moved = try #require(state.workplace(workplace.id))
        #expect(moved.registrationGeneration > workplace.registrationGeneration)

        // An event from the old registration does not change presence.
        state.record(Self.event(.enterInner, workplace: workplace))
        #expect(state.insideWorkplaceIDs.isEmpty)
        state.record(Self.event(.enterInner, workplace: moved))
        #expect(state.insideWorkplaceIDs == [workplace.id])
    }

    @Test("Generations never repeat after a delete")
    func generationsAreMonotonic() throws {
        var state = WorkplaceAutomationState()
        let first = try state.addWorkplace(name: "A", latitude: 0, longitude: 0)
        state.removeWorkplace(first.id)
        let second = try state.addWorkplace(name: "B", latitude: 0, longitude: 0)
        #expect(second.registrationGeneration > first.registrationGeneration)
    }

    @Test("A redelivered event is stored once")
    func eventIdempotence() throws {
        var state = WorkplaceAutomationState()
        let workplace = try state.addWorkplace(name: "Office", latitude: 31, longitude: 121)
        let arrival = Self.event(.enterInner, workplace: workplace)
        let first = state.record(arrival)
        let second = state.record(arrival)
        #expect(first)
        #expect(!second)
        #expect(state.events.count == 1)
    }

    @Test("A retried command gets its first receipt back")
    func receiptIdempotence() {
        var state = WorkplaceAutomationState()
        let command = UUID()
        let first = state.recordReceipt(.init(commandID: command, outcome: .applied, completedAt: Self.now))
        let retry = state.recordReceipt(.init(
            commandID: command, outcome: .alreadyApplied, completedAt: Self.now.addingTimeInterval(60)
        ))
        #expect(retry == first)
        #expect(state.receipts.count == 1)
    }

    @Test("Manual suppression holds by shift identity until resumed")
    func suppression() {
        var state = WorkplaceAutomationState()
        state.suppress(shiftKey: "2026-11-09#day", at: Self.now)
        #expect(state.isSuppressed("2026-11-09#day"))
        #expect(!state.isSuppressed("2026-11-10#day"))
        state.resumeAutomation(shiftKey: "2026-11-09#day")
        #expect(!state.isSuppressed("2026-11-09#day"))
    }

    @Test("Unadopted references expire after 90 days with their events")
    func retention() throws {
        var state = WorkplaceAutomationState()
        let workplace = try state.addWorkplace(name: "Office", latitude: 31, longitude: 121)
        let old = Self.now.addingTimeInterval(-91 * 24 * 60 * 60)
        let recent = Self.now.addingTimeInterval(-89 * 24 * 60 * 60)
        let oldEvent = Self.event(.enterInner, workplace: workplace, receivedAt: old)
        let recentEvent = Self.event(.exitOuter, workplace: workplace, receivedAt: recent)
        state.record(oldEvent)
        state.record(recentEvent)
        state.upsert(WorkTimeProposal(
            id: UUID(), shiftKey: "old", sourceEventIDs: [oldEvent.id], proposedStart: old,
            proposedEnd: nil, status: .pendingReview, reasons: [.automaticApplyOff], createdAt: old
        ))
        state.upsert(WorkTimeProposal(
            id: UUID(), shiftKey: "recent", sourceEventIDs: [recentEvent.id], proposedStart: nil,
            proposedEnd: recent, status: .pendingReview, reasons: [.automaticApplyOff], createdAt: recent
        ))
        state.prune(now: Self.now)
        #expect(state.proposals.map(\.shiftKey) == ["recent"])
        #expect(state.events.map(\.id) == [recentEvent.id])
    }

    @Test("The file round-trips, is excluded from backup, and a newer file is left alone")
    func archive() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WorkplaceAutomationStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "WorkplaceAutomation/state.json")
        #expect(WorkplaceAutomationArchive.load(from: url) == .missing)

        var state = WorkplaceAutomationState()
        state.settings.isMonitoringEnabled = true
        try state.addWorkplace(name: "Office", latitude: 31.2, longitude: 121.5)
        try WorkplaceAutomationArchive.save(state, to: url)
        #expect(WorkplaceAutomationArchive.load(from: url) == .loaded(state))

        let fileValues = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(fileValues.isExcludedFromBackup == true)
        let folderValues = try url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(folderValues.isExcludedFromBackup == true)

        state.version = WorkplaceAutomationState.currentVersion + 1
        try WorkplaceAutomationArchive.save(state, to: url)
        #expect(WorkplaceAutomationArchive.load(from: url) == .unreadable)

        try Data("not json".utf8).write(to: url)
        #expect(WorkplaceAutomationArchive.load(from: url) == .unreadable)
    }

    @Test("Automation is Plus only, while review stays open after Plus ends")
    @MainActor
    func entitlement() {
        #expect(PlusEntitlementDecision.collectsAutomation(authorization: .authorized(.lifetime)))
        #expect(!PlusEntitlementDecision.collectsAutomation(authorization: .unauthorized))
        #expect(!PlusEntitlementDecision.collectsAutomation(authorization: .pendingAskToBuy))
    }
}
