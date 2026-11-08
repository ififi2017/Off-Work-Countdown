import Foundation
import Observation

/// Plan 021 P1: the single entry point that turns automation events and
/// review answers into record writes (§3.3).
///
/// A geofence callback, a Shortcuts action and a tap in the review list all
/// call these commands; none of them edits records directly. Every command:
/// 1. stores the event on this device before touching records,
/// 2. decides with `WorkplaceAutomationRules`,
/// 3. writes adopted times through `RecordsActions` (one `DayOverride` per day),
/// 4. stores a receipt keyed by a stable command ID, so a retry after a crash
///    or a second delivery returns the first result instead of applying twice.
///
/// The automation file is saved before and after the record write. If the
/// app dies in between, the retry finds the day already holding the same
/// segments and reports `alreadyApplied`.
@MainActor
@Observable
final class WorkplaceAutomationCoordinator {
    private(set) var state: WorkplaceAutomationState
    /// False when the automation file exists but cannot be read. Nothing is
    /// written then, so the file is never replaced by an empty one.
    @ObservationIgnored let isAvailable: Bool
    @ObservationIgnored private let actions: RecordsActions
    @ObservationIgnored private let persist: (WorkplaceAutomationState) throws -> Void

    init(
        actions: RecordsActions,
        loaded: WorkplaceAutomationArchive.LoadResult,
        persist: @escaping (WorkplaceAutomationState) throws -> Void
    ) {
        self.actions = actions
        self.persist = persist
        switch loaded {
        case .missing:
            state = WorkplaceAutomationState()
            isAvailable = true
        case .loaded(let saved):
            state = saved
            isAvailable = true
        case .unreadable:
            state = WorkplaceAutomationState()
            isAvailable = false
        }
    }

    static func live(actions: RecordsActions) -> WorkplaceAutomationCoordinator {
        WorkplaceAutomationCoordinator(
            actions: actions,
            loaded: WorkplaceAutomationArchive.load(),
            persist: { try WorkplaceAutomationArchive.save($0) }
        )
    }

    // MARK: Settings and workplaces

    /// Applies a settings or workplace change. Returns false when nothing was saved.
    @discardableResult
    func update(_ change: (inout WorkplaceAutomationState) throws -> Void) rethrows -> Bool {
        guard isAvailable else { return false }
        var next = state
        try change(&next)
        return commit(next)
    }

    // MARK: Events

    /// Records one automation event and acts on it (§3.4).
    ///
    /// `shifts` are the planned shifts around the event, resolved by the
    /// existing schedule rules; this layer never derives a schedule.
    func receive(
        _ event: AutomationEvent,
        shifts: [AutomationShift],
        context: WorkDayContext = .regular,
        now: Date = .now
    ) async -> AutomationCommandOutcome {
        guard isAvailable else { return .temporarilyUnavailable }
        if let receipt = state.receipt(for: event.id) { return receipt.outcome }

        let insideBefore = state.insideWorkplaceIDs
        var next = state
        next.record(event)
        // The envelope is durable before any record changes.
        guard commit(next) else { return .temporarilyUnavailable }

        let match: AutomationShiftMatch
        switch event.type {
        case .enterInner:
            match = WorkplaceAutomationRules.matchArrival(at: event.proposedTime, among: shifts)
        case .exitOuter:
            // A person saying they finished is not a location report: being
            // inside a saved workplace does not overrule them.
            guard event.source == .userConfirmation || WorkplaceAutomationRules.leavesAllWorkplaces(
                exitingWorkplace: event.workplaceID, inside: insideBefore
            ) else { return finish(event.id, .ignored, now: now) }
            match = WorkplaceAutomationRules.matchExit(at: event.proposedTime, among: shifts)
        }
        guard case .matched(let shift) = match else { return finish(event.id, .ignored, now: now) }

        let disposition = WorkplaceAutomationRules.disposition(
            for: event,
            now: now,
            currentGeneration: event.workplaceID.flatMap { state.workplace($0)?.registrationGeneration },
            settings: state.settings,
            canCollect: actions.plus.canCollectAutomation,
            canAutoApply: actions.plus.canAutoApplyAutomation,
            isManuallySuppressed: state.isSuppressed(shift.shiftKey),
            context: context
        )
        if case .ignore = disposition { return finish(event.id, .ignored, now: now) }

        let boundary: WorkTimeBoundary
        let time: Date
        var reasons: [AutomationReviewReason] = []
        if case .recordForReview(let reason) = disposition { reasons.append(reason) }

        switch event.type {
        case .enterInner:
            boundary = .start
            switch WorkplaceAutomationRules.assessArrival(
                at: event.proposedTime, for: shift, promptDelay: state.settings.visitPromptDelay
            ) {
            case .early:
                // Only the person can turn an early arrival into early work.
                time = event.proposedTime
                if event.source != .userConfirmation { reasons.append(.earlyStartNeedsConfirmation) }
            case .punctual:
                time = shift.plannedStart
            case .late:
                time = event.proposedTime
            }
        case .exitOuter:
            boundary = .end
            switch WorkplaceAutomationRules.assessExit(at: event.proposedTime, for: shift) {
            case .temporaryAbsence where event.source == .userConfirmation:
                // Ending early is the person's call (§3.1), never a sensor's.
                time = event.proposedTime
            case .temporaryAbsence:
                return finish(event.id, .ignored, now: now)
            case .needsReview(let reason):
                time = event.proposedTime
                reasons.append(reason)
            case .shiftEnded:
                time = event.proposedTime
            }
        }

        var proposal = WorkTimeProposal(
            id: UUID(),
            shift: shift,
            boundary: boundary,
            proposedTime: time,
            sourceEventIDs: [event.id],
            status: .pendingReview,
            reasons: reasons,
            createdAt: now
        )
        if !reasons.isEmpty {
            return keepForReview(proposal, commandID: event.id, outcome: .recordedForReview, now: now)
        }
        proposal.status = .autoApplied
        return await adopt(proposal, commandID: event.id, appliedBy: .autoApplied, batchID: nil, now: now)
    }

    // MARK: Review

    /// Adopts reviewed suggestions one by one (§3.12). Each keeps its own
    /// receipt under the shared batch ID; a retry never applies one twice,
    /// and a partial failure is reported per suggestion.
    func applyReviewed(
        _ proposalIDs: [UUID],
        batchID: UUID = UUID(),
        now: Date = .now
    ) async -> [UUID: AutomationCommandOutcome] {
        var results: [UUID: AutomationCommandOutcome] = [:]
        for id in proposalIDs {
            guard isAvailable else { results[id] = .temporarilyUnavailable; continue }
            if let receipt = state.receipt(for: id) { results[id] = receipt.outcome; continue }
            guard var proposal = state.proposal(id), proposal.status == .pendingReview else {
                results[id] = .ignored
                continue
            }
            proposal.status = .manuallyApplied
            proposal.batchID = batchID
            // An explicit choice also clears the hold a person's earlier edit set.
            var next = state
            next.resumeAutomation(shiftKey: proposal.shiftKey)
            guard commit(next) else { results[id] = .temporarilyUnavailable; continue }
            results[id] = await adopt(proposal, commandID: id, appliedBy: .manuallyApplied, batchID: batchID, now: now)
        }
        return results
    }

    /// Keeps suggestions as references without adopting them.
    func dismiss(_ proposalIDs: [UUID], now: Date = .now) {
        _ = update { state in
            for id in proposalIDs {
                guard var proposal = state.proposal(id), proposal.status == .pendingReview else { continue }
                proposal.status = .dismissed
                proposal.resolvedAt = now
                state.upsert(proposal)
            }
        }
    }

    /// Undoes one write while the day is still what automation left (§3.6),
    /// then holds automation for that shift until the person resumes it.
    func undo(commandID: UUID, now: Date = .now) async -> AutomationCommandOutcome {
        guard isAvailable else { return .temporarilyUnavailable }
        guard let receipt = state.receipt(for: commandID),
              let dayKey = receipt.dayKey,
              let editCount = receipt.writtenEditCount
        else { return .ignored }
        if receipt.undoneAt != nil { return .alreadyApplied }
        let result = await actions.restoreAutomationOverride(
            dayKey: dayKey,
            previous: receipt.previousOverride,
            expectedEditCount: editCount
        ).value
        switch result {
        case .written:
            var next = state
            next.markUndone(commandID: commandID, at: now)
            next.setAdoptedEditCount(nil, dayKey: dayKey)
            if let shiftKey = receipt.shiftKey { next.suppress(shiftKey: shiftKey, at: now) }
            for proposal in next.proposals where proposal.sourceEventIDs.contains(commandID) || proposal.id == commandID {
                var undone = proposal
                undone.status = .dismissed
                undone.resolvedAt = now
                next.upsert(undone)
            }
            _ = commit(next)
            return .applied
        case .unchanged:
            return .alreadyApplied
        case .conflict:
            return .needsReview
        case .unavailable:
            return .temporarilyUnavailable
        }
    }

    /// A person edited, ended or cleared this shift by hand: later automatic
    /// events stop changing it (§3.1 manual priority).
    func holdForManualChange(shiftKey: String, now: Date = .now) {
        _ = update { $0.suppress(shiftKey: shiftKey, at: now) }
    }

    /// What each day would hold after adopting these suggestions, in the
    /// order they were given (§3.12 preview). Uses the same rule as adoption.
    func previewSegments(for proposalIDs: [UUID]) -> [(shift: AutomationShift, segments: [NativeShiftSegment])] {
        var order: [String] = []
        var byShift: [String: [WorkTimeProposal]] = [:]
        for id in proposalIDs {
            guard let proposal = state.proposal(id), proposal.status == .pendingReview else { continue }
            if byShift[proposal.shiftKey] == nil { order.append(proposal.shiftKey) }
            byShift[proposal.shiftKey, default: []].append(proposal)
        }
        return order.compactMap { key in
            guard let proposals = byShift[key], let shift = proposals.first?.shift else { return nil }
            return (shift, Self.segments(for: shift, adopting: proposals, state: state))
        }
    }

    // MARK: Private

    /// A boundary comes from the suggestion being adopted, else from what
    /// automation already adopted for this shift, else from the plan.
    private static func segments(
        for shift: AutomationShift,
        adopting proposals: [WorkTimeProposal],
        state: WorkplaceAutomationState
    ) -> [NativeShiftSegment] {
        func time(_ boundary: WorkTimeBoundary, planned: Date) -> Date {
            proposals.last { $0.boundary == boundary }?.proposedTime
                ?? state.adoptedTime(shiftKey: shift.shiftKey, boundary: boundary)
                ?? planned
        }
        return WorkplaceAutomationRules.proposedSegments(
            for: shift, start: time(.start, planned: shift.plannedStart), end: time(.end, planned: shift.plannedEnd)
        )
    }


    private func adopt(
        _ proposal: WorkTimeProposal,
        commandID: UUID,
        appliedBy status: WorkTimeProposalStatus,
        batchID: UUID?,
        now: Date
    ) async -> AutomationCommandOutcome {
        let shift = proposal.shift
        let segments = Self.segments(for: shift, adopting: [proposal], state: state)

        var adopted = proposal
        adopted.status = status
        adopted.resolvedAt = now

        // Planned times need no record: the schedule already says so.
        if segments == shift.segments, state.adoptedEditCount(dayKey: shift.anchorDayKey) == nil {
            var next = state
            next.supersedePending(shiftKey: shift.shiftKey, boundary: proposal.boundary, at: now)
            next.upsert(adopted)
            next.recordReceipt(.init(commandID: commandID, outcome: .applied, completedAt: now, batchID: batchID))
            return commit(next) ? .applied : .temporarilyUnavailable
        }

        // A reviewed adoption is the person's explicit choice and may replace
        // their own edit; an automatic one never does.
        let result = await actions.writeAutomationSegments(
            dayKey: shift.anchorDayKey,
            segments: segments,
            expectedEditCount: state.adoptedEditCount(dayKey: shift.anchorDayKey),
            replacingPersonEdits: status == .manuallyApplied
        ).value

        var next = state
        switch result {
        case .written(let previous, let editCount):
            next.supersedePending(shiftKey: shift.shiftKey, boundary: proposal.boundary, at: now)
            next.upsert(adopted)
            next.setAdoptedEditCount(editCount, dayKey: shift.anchorDayKey)
            next.recordReceipt(.init(
                commandID: commandID, outcome: .applied, completedAt: now, batchID: batchID,
                dayKey: shift.anchorDayKey, shiftKey: shift.shiftKey,
                previousOverride: previous, writtenEditCount: editCount
            ))
            _ = commit(next)
            return .applied
        case .unchanged(let editCount):
            // Already there, e.g. a retry after the app stopped between the
            // record write and this receipt.
            next.supersedePending(shiftKey: shift.shiftKey, boundary: proposal.boundary, at: now)
            next.upsert(adopted)
            next.setAdoptedEditCount(editCount, dayKey: shift.anchorDayKey)
            next.recordReceipt(.init(commandID: commandID, outcome: .alreadyApplied, completedAt: now, batchID: batchID))
            _ = commit(next)
            return .alreadyApplied
        case .conflict:
            // The person's version wins; keep ours as a reference.
            var reference = proposal
            reference.reasons.append(.recordChangedByPerson)
            return keepForReview(reference, commandID: commandID, outcome: .needsReview, now: now, holdShift: true)
        case .unavailable:
            var reference = proposal
            reference.status = .pendingReview
            reference.reasons.append(.recordsUnavailable)
            // No receipt: a later retry may still succeed.
            next.supersedePending(shiftKey: shift.shiftKey, boundary: proposal.boundary, at: now)
            next.upsert(reference)
            _ = commit(next)
            return .temporarilyUnavailable
        }
    }

    private func keepForReview(
        _ proposal: WorkTimeProposal,
        commandID: UUID,
        outcome: AutomationCommandOutcome,
        now: Date,
        holdShift: Bool = false
    ) -> AutomationCommandOutcome {
        var next = state
        if holdShift { next.suppress(shiftKey: proposal.shiftKey, at: now) }
        next.supersedePending(shiftKey: proposal.shiftKey, boundary: proposal.boundary, at: now)
        var pending = proposal
        pending.status = .pendingReview
        next.upsert(pending)
        next.recordReceipt(.init(commandID: commandID, outcome: outcome, completedAt: now))
        return commit(next) ? outcome : .temporarilyUnavailable
    }

    private func finish(_ commandID: UUID, _ outcome: AutomationCommandOutcome, now: Date) -> AutomationCommandOutcome {
        var next = state
        next.recordReceipt(.init(commandID: commandID, outcome: outcome, completedAt: now))
        return commit(next) ? outcome : .temporarilyUnavailable
    }

    /// Saves first and only then exposes the new state.
    private func commit(_ next: WorkplaceAutomationState) -> Bool {
        do {
            try persist(next)
            state = next
            return true
        } catch {
            return false
        }
    }
}
