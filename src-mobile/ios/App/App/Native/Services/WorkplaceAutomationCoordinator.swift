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
    /// Called after every saved change; the runtime reschedules questions.
    @ObservationIgnored var onChange: (() -> Void)?

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

    /// Deletes everything automation keeps on this device. Returns false
    /// when the file could not be written, so nothing claims it was deleted.
    @discardableResult
    func eraseDeviceData() -> Bool {
        update { $0.eraseDeviceData() }
    }

    // MARK: Events

    /// Records one automation event and acts on it (§3.4).
    ///
    /// `shifts` are the planned shifts around the event, resolved by the
    /// existing schedule rules; this layer never derives a schedule.
    func receive(
        _ event: AutomationEvent,
        shifts: [AutomationShift],
        context explicitContext: WorkDayContext? = nil,
        now: Date = .now
    ) async -> AutomationCommandOutcome {
        guard isAvailable else { return .temporarilyUnavailable }
        if let receipt = state.receipt(for: event.id) { return receipt.outcome }

        let insideBefore = state.insideWorkplaceIDs
        var next = state
        next.record(event)
        // The envelope is durable before any record changes.
        guard commit(next) else { return .temporarilyUnavailable }

        let leavesWork = event.type == .exitOuter && WorkplaceAutomationRules.leavesAllWorkplaces(
            exitingWorkplace: event.workplaceID, inside: insideBefore
        )
        if leavesWork, event.source != .userConfirmation, let visit = state.openVisit {
            await close(visit, leftAt: event.proposedTime, now: now)
            // Leaving after extra work ends that stretch, not the shift that
            // was already over before it (§3.9: the gap stays a gap).
            if case .offShift = visit.kind { return finish(event.id, .ignored, now: now) }
        }
        if event.type == .enterInner {
            // Back during a shift: an earlier exit was a break, not the end.
            let running = shifts.filter { $0.plannedStart <= event.proposedTime && event.proposedTime < $0.plannedEnd }
            if running.contains(where: { state.earlyExits[$0.shiftKey] != nil }) {
                var cleared = state
                for shift in running { cleared.clearEarlyExit(shiftKey: shift.shiftKey) }
                _ = commit(cleared)
            }
        }

        let match: AutomationShiftMatch
        switch event.type {
        case .enterInner:
            match = WorkplaceAutomationRules.matchArrival(at: event.proposedTime, among: shifts)
        case .exitOuter:
            // A person saying they finished is not a location report: being
            // inside a saved workplace does not overrule them.
            guard event.source == .userConfirmation || leavesWork else { return finish(event.id, .ignored, now: now) }
            match = WorkplaceAutomationRules.matchExit(at: event.proposedTime, among: shifts)
        }
        guard case .matched(let shift) = match else {
            // Back after automation recorded the clock-out: overtime goes on
            // to the final exit, with the time away kept for the timeline.
            if case .noShift = match, event.type == .enterInner, !event.isInitialState,
               event.source == .nativeGeofence || event.source == .appIntentAutomation,
               let back = WorkplaceAutomationRules.returnAfterClockOut(
                   arrivedAt: event.proposedTime, among: shifts, state: state
               ) {
                var resumed = state
                resumed.recordAway(AutomationAwayStretch(
                    shiftKey: back.shift.shiftKey, dayKey: back.shift.anchorDayKey,
                    leftAt: back.leftAt, returnedAt: event.proposedTime, returnEventID: event.id
                ))
                guard commit(resumed) else { return .temporarilyUnavailable }
                return finish(event.id, .recordedForReview, now: now)
            }
            // An arrival with no shift may be extra work; only the person
            // can say so (§3.9).
            if case .noShift = match, event.type == .enterInner,
               !shifts.contains(where: { $0.plannedStart <= event.proposedTime && event.proposedTime < $0.plannedEnd }) {
                return startOffShiftVisit(for: event, shifts: shifts, now: now)
            }
            return finish(event.id, .ignored, now: now)
        }
        // A return during a shift that already has a start is not a new start.
        if event.type == .enterInner, event.source != .userConfirmation,
           event.proposedTime > shift.plannedStart,
           state.proposals.contains(where: {
               $0.shiftKey == shift.shiftKey && $0.boundary == .start && ($0.isAdopted || $0.status == .pendingReview)
           }) {
            return finish(event.id, .ignored, now: now)
        }
        let context = explicitContext ?? state.context(for: shift.anchorDayKey)
        // Away from the office, leaving it does not end the day (§3.10).
        if context != .regular, context != .rest, event.type == .exitOuter, event.source != .userConfirmation {
            return finish(event.id, .ignored, now: now)
        }

        let disposition = WorkplaceAutomationRules.disposition(
            for: event,
            now: now,
            currentGeneration: event.workplaceID.flatMap { state.workplace($0)?.registrationGeneration },
            settings: state.settings,
            canCollect: actions.plus.canCollectAutomation,
            canAutoApply: actions.plus.canAutoApplyAutomation,
            isManuallySuppressed: state.isSuppressed(shift.shiftKey),
            context: context,
            firstKnownAfterStart: event.type == .enterInner && event.proposedTime > shift.plannedStart
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
                // Only a trace for now; it waits for a return (§3.9).
                var traced = state
                traced.recordEarlyExit(WorkTimeProposal(
                    id: UUID(), shift: shift, boundary: .end, proposedTime: event.proposedTime,
                    sourceEventIDs: [event.id], status: .pendingReview, reasons: [.leftBeforePlannedEnd], createdAt: now
                ))
                guard commit(traced) else { return .temporarilyUnavailable }
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
            let outcome = keepForReview(proposal, commandID: event.id, outcome: .recordedForReview, now: now)
            if reasons.contains(.earlyStartNeedsConfirmation),
               case .early(let promptAt) = WorkplaceAutomationRules.assessArrival(
                   at: event.proposedTime, for: shift, promptDelay: state.settings.visitPromptDelay
               ) {
                var visiting = state
                visiting.upsert(AutomationVisit(
                    id: UUID(), kind: .early(proposalID: proposal.id), workplaceID: event.workplaceID,
                    arrivalEventID: event.id, arrivedAt: event.proposedTime, promptAt: promptAt
                ))
                _ = commit(visiting)
            }
            return outcome
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
            expectedEditCount: editCount,
            provenance: receipt.provenanceWrite
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

    // MARK: Visits and status

    /// The person's answer to an early or off-shift arrival question.
    /// "Started work" counts from the detected arrival, not from the tap (§3.9).
    func answerVisit(
        _ id: UUID,
        startedWork: Bool,
        movedBetweenWorkplaces: Bool = false,
        now: Date = .now
    ) async -> AutomationCommandOutcome {
        guard isAvailable else { return .temporarilyUnavailable }
        guard var visit = state.visit(id), visit.status == .waiting else { return .alreadyApplied }
        if startedWork, movedBetweenWorkplaces, case .offShift = visit.kind {
            visit.countsFrom = WorkplaceAutomationRules.transferStart(arrivedAt: visit.arrivedAt, state: state)
        }
        guard startedWork else {
            visit.status = .declined
            var next = state
            next.upsert(visit)
            if case .early(let proposalID) = visit.kind, var proposal = next.proposal(proposalID),
               proposal.status == .pendingReview {
                // "Just arrived early": the arrival stays, as a dismissed reference.
                proposal.status = .dismissed
                proposal.resolvedAt = now
                next.upsert(proposal)
            }
            return commit(next) ? .applied : .temporarilyUnavailable
        }
        switch visit.kind {
        case .early(let proposalID):
            visit.status = .closed
            var next = state
            next.upsert(visit)
            guard commit(next) else { return .temporarilyUnavailable }
            return await applyReviewed([proposalID], now: now)[proposalID] ?? .ignored
        case .offShift:
            if let leftAt = visit.leftAt {
                // Answered after leaving: record the finished stretch.
                return await recordExtraWork(visit, until: leftAt, now: now)
            }
            visit.status = .working
            var next = state
            next.upsert(visit)
            return commit(next) ? .recordedForReview : .temporarilyUnavailable
        }
    }

    /// "Resume automation" for a shift the person paused by correcting or
    /// undoing it (§3.6). Later crossings may act on it again; nothing
    /// earlier is replayed.
    @discardableResult
    func resumeAutomation(shiftKey: String) -> Bool {
        update { $0.resumeAutomation(shiftKey: shiftKey) }
    }

    /// Settles a shift's status question. "Keep recording" approves nothing
    /// else; a context applies to that day only (§3.10).
    func answerStatus(_ answer: WorkdayStatusAnswer, for shift: AutomationShift, now: Date = .now) async -> AutomationCommandOutcome {
        guard isAvailable else { return .temporarilyUnavailable }
        if answer == .rest {
            guard await actions.markDayNotWorking(dayKey: shift.anchorDayKey).value else { return .temporarilyUnavailable }
        }
        var next = state
        next.settleStatus(shiftKey: shift.shiftKey, answer: answer)
        let context: WorkDayContext? = switch answer {
        case .fieldwork: .fieldwork
        case .businessTrip: .businessTrip
        case .remote: .remote
        case .rest, .continueRecording: nil
        }
        if let context { next.setContext(context, from: shift.anchorDayKey, through: shift.anchorDayKey) }
        return commit(next) ? .applied : .temporarilyUnavailable
    }

    /// Turns exits nobody came back from into review items once their shift
    /// is over, unless an end was already recorded (§3.9).
    func surfaceUnreturnedExits(now: Date = .now) {
        let due = state.earlyExits.values.filter { $0.shift.plannedEnd <= now }
        guard !due.isEmpty else { return }
        var next = state
        for candidate in due {
            next.clearEarlyExit(shiftKey: candidate.shiftKey)
            let hasEnd = next.proposals.contains {
                $0.shiftKey == candidate.shiftKey && $0.boundary == .end
                    && ($0.isAdopted || $0.status == .pendingReview)
            }
            if !hasEnd { next.upsert(candidate) }
        }
        _ = commit(next)
    }

    private func startOffShiftVisit(
        for event: AutomationEvent,
        shifts: [AutomationShift],
        now: Date
    ) -> AutomationCommandOutcome {
        guard event.source != .userConfirmation, actions.plus.canCollectAutomation,
              event.source != .nativeGeofence || (state.settings.isMonitoringEnabled
                  && event.workplaceID.flatMap { state.workplace($0)?.registrationGeneration } == event.registrationGeneration),
              !event.isInitialState, state.openVisit == nil
        else { return finish(event.id, .ignored, now: now) }
        let dayKey = RecordJSON.dayKey(event.proposedTime, calendar: actions.preferences.recordsCalendar)
        guard state.context(for: dayKey) != .rest else { return finish(event.id, .ignored, now: now) }
        var next = state
        next.upsert(AutomationVisit(
            id: UUID(), kind: .offShift(dayKey: dayKey), workplaceID: event.workplaceID,
            arrivalEventID: event.id, arrivedAt: event.proposedTime,
            promptAt: event.proposedTime.addingTimeInterval(state.settings.visitPromptDelay.interval),
            plannedSegments: shifts.first { $0.anchorDayKey == dayKey }?.segments ?? []
        ))
        guard commit(next) else { return .temporarilyUnavailable }
        return finish(event.id, .recordedForReview, now: now)
    }

    private func close(_ visit: AutomationVisit, leftAt: Date, now: Date) async {
        var closed = visit
        closed.leftAt = leftAt
        if visit.status == .working {
            _ = await recordExtraWork(closed, until: leftAt, now: now)
            return
        }
        var next = state
        next.upsert(closed)
        _ = commit(next)
    }

    /// Adds a confirmed extra stretch to its day, keeping what the day
    /// already holds. Overlaps merge; gaps stay gaps (§3.9).
    private func recordExtraWork(_ visit: AutomationVisit, until end: Date, now: Date) async -> AutomationCommandOutcome {
        guard case .offShift(let dayKey) = visit.kind, end > visit.workStart else {
            var next = state
            var closed = visit
            closed.status = .closed
            next.upsert(closed)
            return commit(next) ? .ignored : .temporarilyUnavailable
        }
        let extra = NativeShiftSegment(
            startAtMs: visit.workStart.timeIntervalSince1970 * 1_000,
            endAtMs: end.timeIntervalSince1970 * 1_000
        )
        let current = actions.records.state.overrides.first { $0.dayKey == dayKey }
        let base = current?.kind == .customSegments ? current?.segments ?? [] : visit.plannedSegments
        let result = await actions.writeAutomationSegments(
            dayKey: dayKey,
            segments: WorkplaceAutomationRules.union(base + [extra]),
            expectedEditCount: state.adoptedEditCount(dayKey: dayKey),
            // The person asked for this stretch; their own edits are kept.
            replacingPersonEdits: true
        ).value
        var next = state
        var closed = visit
        closed.status = .closed
        closed.leftAt = end
        next.upsert(closed)
        switch result {
        case .written(_, let editCount, _), .unchanged(let editCount):
            next.setAdoptedEditCount(editCount, dayKey: dayKey)
            return commit(next) ? .applied : .temporarilyUnavailable
        case .conflict, .unavailable:
            // Keep it answerable later rather than losing the answer.
            closed.status = .working
            next.upsert(closed)
            _ = commit(next)
            return .temporarilyUnavailable
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

        // The minimal summary is copied now, with the write, so it never
        // depends on this device's event log later (§3.7).
        let provenance = WorkTimeProvenance.Boundary(
            adopting: adopted,
            event: proposal.sourceEventIDs.first.flatMap { state.event($0) },
            appliedBy: status == .manuallyApplied ? .reviewed : .automatic,
            appliedAt: now
        )
        // A reviewed adoption is the person's explicit choice and may replace
        // their own edit; an automatic one never does.
        let result = await actions.writeAutomationSegments(
            dayKey: shift.anchorDayKey,
            segments: segments,
            expectedEditCount: state.adoptedEditCount(dayKey: shift.anchorDayKey),
            replacingPersonEdits: status == .manuallyApplied,
            provenance: provenance
        ).value

        var next = state
        switch result {
        case .written(let previous, let editCount, let provenanceWrite):
            next.supersedePending(shiftKey: shift.shiftKey, boundary: proposal.boundary, at: now)
            next.upsert(adopted)
            next.setAdoptedEditCount(editCount, dayKey: shift.anchorDayKey)
            next.recordReceipt(.init(
                commandID: commandID, outcome: .applied, completedAt: now, batchID: batchID,
                dayKey: shift.anchorDayKey, shiftKey: shift.shiftKey,
                previousOverride: previous, writtenEditCount: editCount,
                provenanceWrite: provenanceWrite
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
            onChange?()
            return true
        } catch {
            return false
        }
    }
}

extension WorkTimeProvenance.Boundary {
    /// The summary copied from an adopted suggestion and its source event.
    /// Only these fields leave the device; the event's workplace and
    /// registration stay behind.
    nonisolated init(
        adopting proposal: WorkTimeProposal,
        event: AutomationEvent?,
        appliedBy: WorkTimeProvenance.AppliedBy,
        appliedAt: Date
    ) {
        let source: WorkTimeProvenance.Source
        switch event?.source {
        case .nativeGeofence: source = .nativeGeofence
        case .appIntentAutomation: source = .appIntentAutomation
        case .userConfirmation, nil: source = .userConfirmation
        }
        let evidence: WorkTimeProvenance.EvidenceLevel
        switch (event?.source, event?.timestampBasis) {
        case (.nativeGeofence, .systemObservation): evidence = .systemObservation
        case (.nativeGeofence, _): evidence = .callbackReceipt
        case (.appIntentAutomation, _): evidence = .externalAction
        default: evidence = .personStatement
        }
        self.init(
            boundary: proposal.boundary,
            time: proposal.proposedTime,
            source: source,
            observedAt: event?.observedAt,
            receivedAt: event?.receivedAt ?? proposal.createdAt,
            appliedAt: appliedAt,
            appliedBy: appliedBy,
            batchID: proposal.batchID,
            rulesVersion: proposal.rulesVersion,
            evidenceLevel: evidence,
            reasons: proposal.reasons.map(\.rawValue)
        )
    }
}
