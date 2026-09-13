import Foundation
import Observation
import Testing
@testable import App

@MainActor
@Suite("Process service coordination", .timeLimit(.minutes(1)))
struct ServiceCoordinatorTests {
    @Test("Recovery from an unrelated archive error does not republish the shift")
    func unrelatedPersistenceFailure() async {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        defer { coordinator.stop() }
        coordinator.start()
        await fixture.publications.next()
        fixture.input.persistenceFailed = true
        await coordinator.flush()
        fixture.input.persistenceFailed = false
        await coordinator.flush()
        #expect(fixture.publishedSignatures == ["initial"])
    }

    @Test("Foreground reconciliation publishes its settled result once")
    func reconciliationCoalescesEdits() async {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        defer { coordinator.stop() }
        let scene = UUID()
        coordinator.sceneChanged(scene, phase: .active)
        await fixture.publications.next()
        coordinator.sceneChanged(scene, phase: .background)
        fixture.suspendActivation = true
        coordinator.sceneChanged(scene, phase: .active)
        await fixture.activationEntered.next()
        fixture.input.schedule = .init(focusPlanningRevision: 1, scheduleSignature: "reconciled", focusRuntimeRevision: 1)
        await coordinator.flush()
        #expect(fixture.publishedSignatures == ["initial"])
        fixture.releaseActivation.send()
        await fixture.publications.next()
        await coordinator.flush()
        #expect(fixture.publishedSignatures == ["initial", "reconciled"])
    }

    @Test("Repeated startup publishes once without constructing a scene or application")
    func startsWithoutScene() async {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        defer { coordinator.stop() }
        coordinator.start()
        coordinator.start()
        await fixture.publications.next()
        await coordinator.flush()
        #expect(fixture.prepareCount == 1)
        #expect(fixture.beginCount == 1)
        #expect(fixture.activations == [false])
        #expect(fixture.publishedSignatures == ["initial"])
    }

    @Test("Edits coalesce while any scene remains active")
    func multipleScenes() async {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        defer { coordinator.stop() }
        let first = UUID(), second = UUID()
        coordinator.sceneChanged(first, phase: .active)
        coordinator.sceneChanged(second, phase: .active)
        await fixture.publications.next()
        fixture.changeSchedule("edited")
        await coordinator.flush()
        coordinator.sceneChanged(first, phase: .background)
        await coordinator.flush()
        #expect(fixture.publishedSignatures == ["initial"])
        coordinator.sceneChanged(second, phase: .inactive)
        await fixture.publications.next()
        #expect(fixture.publishedSignatures == ["initial", "edited"])
        coordinator.sceneChanged(second, phase: .background)
        await coordinator.flush()
        #expect(fixture.publishedSignatures.count == 2)
    }

    @Test("An entitlement change publishes immediately, including revocation")
    func entitlementIsIndependent() async {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        defer { coordinator.stop() }
        coordinator.sceneChanged(UUID(), phase: .active)
        await fixture.publications.next()
        fixture.input.authorized = true
        await fixture.publications.next()
        fixture.input.authorized = false
        await fixture.publications.next()
        #expect(fixture.syncResumes == 1)
        #expect(fixture.publishedAuthorization == [false, true, false])
    }

    @Test("Watch-only entitlement evidence publishes immediately while a scene is active")
    func watchEvidenceIsIndependent() async {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        defer { coordinator.stop() }
        coordinator.sceneChanged(UUID(), phase: .active)
        await fixture.publications.next()
        let expiry = Date(timeIntervalSince1970: 2_000_000)
        fixture.input.watchEvidence = .init(
            authorization: .authorized(.inGracePeriod(graceExpiresAt: expiry)), verifiedAt: Date(timeIntervalSince1970: 100))
        await fixture.publications.next()
        fixture.input.watchEvidence = .init(
            authorization: .authorized(.inGracePeriod(graceExpiresAt: expiry)), verifiedAt: Date(timeIntervalSince1970: 200))
        await fixture.publications.next()
        await coordinator.flush()
        #expect(fixture.publishedSignatures == ["initial", "initial", "initial"])
        #expect(fixture.publishedAuthorization == [false, false, false])
        #expect(fixture.syncResumes == 0)
    }

    @Test("A delayed archive flush cannot publish the replaced input")
    func replacementDuringFlush() async {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        defer { coordinator.stop() }
        fixture.suspendFlush = true
        coordinator.start()
        await fixture.flushEntered.next()
        fixture.changeSchedule("replacement")
        fixture.releaseFlush.send()
        await fixture.publications.next()
        await coordinator.flush()
        #expect(fixture.publishedSignatures == ["replacement"])
    }

    @Test("Saving after a failure republishes the pending state")
    func persistenceRetry() async {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.makeCoordinator()
        defer { coordinator.stop() }
        fixture.failFlush = true
        coordinator.start()
        await fixture.flushEntered.next()
        await coordinator.flush()
        #expect(fixture.publishedSignatures.isEmpty)
        fixture.failFlush = false
        fixture.input.persistenceFailed = false
        await fixture.publications.next()
        #expect(fixture.publishedSignatures == ["initial"])
    }
}

@MainActor
@Observable
private final class CoordinatorFixture {
    var input = ServiceCoordinator.Input(
        onboardingComplete: true, authorized: false,
        watchEvidence: .init(authorization: nil, verifiedAt: nil),
        countdownStarted: true, debugToken: "", schedule: .init(focusPlanningRevision: 0, scheduleSignature: "initial", focusRuntimeRevision: 0),
        persistenceFailed: false
    )
    @ObservationIgnored var prepareCount = 0
    @ObservationIgnored var beginCount = 0
    @ObservationIgnored var activations: [Bool] = []
    @ObservationIgnored var syncResumes = 0
    @ObservationIgnored var publishedSignatures: [String] = []
    @ObservationIgnored var publishedAuthorization: [Bool] = []
    @ObservationIgnored var failFlush = false
    @ObservationIgnored var suspendFlush = false
    @ObservationIgnored var suspendActivation = false
    let publications = CoordinatorSignal()
    let flushEntered = CoordinatorSignal()
    let releaseFlush = CoordinatorSignal()
    let activationEntered = CoordinatorSignal()
    let releaseActivation = CoordinatorSignal()

    func changeSchedule(_ signature: String) {
        input.schedule = .init(focusPlanningRevision: 0, scheduleSignature: signature, focusRuntimeRevision: 0)
    }

    func makeCoordinator() -> ServiceCoordinator {
        ServiceCoordinator(operations: .init(
            input: { self.input },
            prepare: { self.prepareCount += 1 },
            begin: { self.beginCount += 1 },
            activate: {
                self.activations.append($0)
                if self.suspendActivation {
                    self.suspendActivation = false
                    self.activationEntered.send()
                    await self.releaseActivation.next()
                }
            },
            resumeSync: { self.syncResumes += 1 },
            flush: {
                self.flushEntered.send()
                if self.suspendFlush {
                    self.suspendFlush = false
                    await self.releaseFlush.next()
                }
                if self.failFlush {
                    self.input.persistenceFailed = true
                    throw CocoaError(.fileWriteUnknown)
                }
            },
            publish: {
                self.publishedSignatures.append(self.input.schedule.scheduleSignature)
                self.publishedAuthorization.append(self.input.authorized)
                self.publications.send()
            }
        ))
    }
}

@MainActor
private final class CoordinatorSignal {
    private let stream = AsyncStream<Void>.makeStream()
    func send() { stream.continuation.yield(()) }
    func next() async {
        var iterator = stream.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
}
