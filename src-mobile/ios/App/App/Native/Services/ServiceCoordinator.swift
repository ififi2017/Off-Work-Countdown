import Foundation
import Observation

/// Owns process-lifetime reconciliation and publication. A scene reports its
/// visibility; it never owns a notification, widget or ActivityKit work queue.
@MainActor
@Observable
final class ServiceCoordinator {
    enum Phase { case active, inactive, background }

    struct Input: Equatable, Sendable {
        var onboardingComplete: Bool
        var authorized: Bool
        var watchEvidence: PlusWatchEvidence
        var countdownStarted: Bool
        var debugToken: String
        var schedule: ServiceScheduleSignal
        var persistenceFailed: Bool
    }

    /// The coordinator can be exercised without SwiftUI, StoreKit, or a whole
    /// application. Concrete feature and platform dependencies are assembled
    /// once by AppRuntime.
    struct Operations {
        var input: () -> Input
        var prepare: () async -> Void
        var begin: () -> Void
        var activate: (_ completingOnboarding: Bool) async -> Void
        var resumeSync: () async -> Void
        var flush: () async throws -> Void
        var publish: () async -> Void
    }

    private(set) var isLaunching = true
    private let operations: Operations
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var calendarTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var publicationTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var previousInput: Input?
    @ObservationIgnored private var pendingReschedule = false
    @ObservationIgnored private var isReconciling = false
    @ObservationIgnored private var needsDurablePublication = false
    @ObservationIgnored private var scenes: [UUID: Phase] = [:]

    init(operations: Operations) {
        self.operations = operations
    }

    /// Also used by background/system entry points, before any view exists.
    func start() {
        guard observationTask == nil else { return }
        let operations = operations
        observationTask = Task { [weak self] in
            await operations.prepare()
            guard !Task.isCancelled else { return }
            let inputs = Observations { operations.input() }
            for await input in inputs {
                guard !Task.isCancelled else { return }
                await self?.receive(input)
            }
        }
        calendarTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged).map({ _ in () }) {
                guard !Task.isCancelled else { return }
                self?.calendarDayChanged()
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        calendarTask?.cancel()
        calendarTask = nil
        activationTask?.cancel()
        activationTask = nil
        isReconciling = false
        invalidatePublication()
        previousInput = nil
        pendingReschedule = false
        needsDurablePublication = false
        scenes.removeAll()
        isLaunching = true
    }

    func sceneChanged(_ id: UUID, phase: Phase) {
        let wasActive = hasActiveScene
        scenes[id] = phase
        start()
        guard !isLaunching else { return }
        if !wasActive, hasActiveScene {
            activate()
        } else if wasActive, !hasActiveScene, pendingReschedule {
            requestPublication()
        }
    }

    func sceneDisconnected(_ id: UUID) {
        let wasActive = hasActiveScene
        scenes[id] = nil
        if wasActive, !hasActiveScene, pendingReschedule { requestPublication() }
    }

    func calendarDayChanged() {
        guard !isLaunching, operations.input().onboardingComplete else { return }
        activate()
    }

    private var hasActiveScene: Bool { scenes.values.contains { $0 == .active } }

    private func receive(_ input: Input) async {
        let previous = previousInput
        previousInput = input
        guard input.onboardingComplete else {
            isLaunching = false
            activationTask?.cancel()
            isReconciling = false
            invalidatePublication()
            return
        }
        if previous?.onboardingComplete != true {
            isLaunching = true
            operations.begin()
            await operations.activate(previous != nil)
            guard !Task.isCancelled, operations.input().onboardingComplete else { return }
            isLaunching = false
            // Reconciliation may itself commit a new shift or Focus plan.
            // Publish that settled state; do not replay its observation as a
            // second startup event.
            previousInput = operations.input()
            requestPublication()
            return
        }
        guard let previous, previous != input else { return }
        if !previous.authorized, input.authorized {
            await operations.resumeSync()
            guard !Task.isCancelled, operations.input() == input else { return }
        }
        let urgent = previous.countdownStarted != input.countdownStarted
            || previous.authorized != input.authorized
            || previous.watchEvidence != input.watchEvidence
            || previous.debugToken != input.debugToken
            || previous.schedule.focusRuntimeRevision != input.schedule.focusRuntimeRevision
            || previous.schedule.focusPlanningRevision != input.schedule.focusPlanningRevision
            || (needsDurablePublication && previous.persistenceFailed && !input.persistenceFailed)
        if urgent || (!hasActiveScene && previous.schedule != input.schedule) {
            requestPublication()
        } else if previous.schedule != input.schedule {
            // Editing in the foreground keeps immediate memory feedback. The
            // expensive system work is coalesced until the final scene leaves.
            pendingReschedule = true
        }
    }

    private func activate() {
        activationTask?.cancel()
        isReconciling = true
        invalidatePublication()
        activationTask = Task { [weak self, operations] in
            guard operations.input().onboardingComplete else {
                self?.isReconciling = false
                return
            }
            await operations.activate(false)
            guard !Task.isCancelled else { return }
            self?.isReconciling = false
            self?.requestPublication()
        }
    }

    private func invalidatePublication() {
        generation &+= 1
        publicationTask?.cancel()
        publicationTask = nil
    }

    private func requestPublication() {
        guard !isLaunching, operations.input().onboardingComplete else { return }
        guard !isReconciling else {
            pendingReschedule = true
            return
        }
        invalidatePublication()
        pendingReschedule = false
        let requestedGeneration = generation
        let expected = operations.input()
        publicationTask = Task { [weak self, operations] in
            do { try await operations.flush() }
            catch {
                if self?.generation == requestedGeneration { self?.needsDurablePublication = true }
                return
            }
            guard !Task.isCancelled, self?.generation == requestedGeneration,
                  operations.input() == expected else { return }
            self?.needsDurablePublication = false
            await operations.publish()
        }
    }

    /// Wait for work already admitted, including a replacement queued while
    /// an earlier publication was suspended. No scene lifecycle is required.
    func flush() async {
        if observationTask != nil, !isLaunching { await receive(operations.input()) }
        while let task = publicationTask {
            let expectedGeneration = generation
            await task.value
            if expectedGeneration == generation { return }
        }
    }
}
