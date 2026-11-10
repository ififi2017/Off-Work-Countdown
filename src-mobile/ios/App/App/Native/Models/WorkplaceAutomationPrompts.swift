import Foundation
import UserNotifications

// Plan 021 §0.3 notification budget: the three questions automation may
// have waiting in the system queue. Planned from the device-only state on
// every reschedule, so a question whose reason went away is never left
// behind. Bodies never name a workplace, address or pay (§3.8).

nonisolated struct AutomationPrompt: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case status(AutomationStatusPrompt)
        case earlyVisit(visitID: UUID)
        case offShiftVisit(visitID: UUID)
        case missingEnd
    }

    var identifier: String
    var kind: Kind
    var fireAt: Date

    var bodyKey: String {
        switch kind {
        case .status(.lateArrival): "automationPromptLateArrival"
        case .status: "automationPromptStatusUnconfirmed"
        case .earlyVisit: "automationPromptEarlyVisit"
        case .offShiftVisit: "automationPromptExtraVisit"
        case .missingEnd: "automationPromptMissingEnd"
        }
    }

    /// Visits are answered right from the notification; the others open a page.
    var categoryIdentifier: String? {
        switch kind {
        case .earlyVisit: WorkplaceAutomationNotificationPlan.earlyVisitCategory
        case .offShiftVisit: WorkplaceAutomationNotificationPlan.offShiftVisitCategory
        case .status, .missingEnd: nil
        }
    }

    var route: AppRoute {
        switch kind {
        case .status: .workplaceAutomationStatus
        case .earlyVisit, .offShiftVisit, .missingEnd: .workplaceAutomationReview
        }
    }

    var visitID: UUID? {
        switch kind {
        case .earlyVisit(let id), .offShiftVisit(let id): id
        case .status, .missingEnd: nil
        }
    }
}

nonisolated extension WorkplaceAutomationNotificationPlan {
    static let earlyVisitCategory = "owc.automation.earlyVisit"
    static let offShiftVisitCategory = "owc.automation.offShiftVisit"
    static let startedWorkAction = "owc.automation.startedWork"
    static let notWorkingAction = "owc.automation.notWorking"
    /// Off-shift only: came here from work elsewhere, so the move counts (§3.10).
    static let movedHereAction = "owc.automation.movedHere"
    static let visitIDKey = "automationVisitID"

    /// Visit questions can be answered without opening the app. Titles
    /// follow the system language, like other system surfaces.
    @MainActor static func categories(localizer: NativeLocalizer, locale: String) -> Set<UNNotificationCategory> {
        func category(_ id: String, startedKey: String, notKey: String, movedKey: String? = nil) -> UNNotificationCategory {
            var actions = [
                UNNotificationAction(identifier: startedWorkAction, title: localizer.string(startedKey, locale: locale)),
            ]
            if let movedKey {
                actions.append(UNNotificationAction(identifier: movedHereAction, title: localizer.string(movedKey, locale: locale)))
            }
            actions.append(UNNotificationAction(identifier: notWorkingAction, title: localizer.string(notKey, locale: locale)))
            return UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [])
        }
        return [
            category(earlyVisitCategory, startedKey: "automationActionStartedWork", notKey: "automationActionJustEarly"),
            category(offShiftVisitCategory, startedKey: "automationActionRecordExtra", notKey: "automationActionNotWorking",
                     movedKey: "automationActionMovedHere"),
        ]
    }

    /// At most one of each kind, so the three reserved slots always suffice.
    static func prompts(
        state: WorkplaceAutomationState,
        shifts: [AutomationShift],
        canCollect: Bool,
        now: Date
    ) -> [AutomationPrompt] {
        guard canCollect, state.settings.isMonitoringEnabled else { return [] }
        return [statusPrompt(state: state, shifts: shifts, now: now),
                visitPrompt(state: state, now: now),
                missingEndPrompt(state: state, shifts: shifts, now: now)].compactMap { $0 }
    }

    /// The next shift's question, judged as of when it would fire.
    private static func statusPrompt(state: WorkplaceAutomationState, shifts: [AutomationShift], now: Date) -> AutomationPrompt? {
        guard let shift = shifts
            .filter({ WorkplaceAutomationRules.statusPromptDate(for: $0) > now })
            .min(by: { $0.plannedStart < $1.plannedStart })
        else { return nil }
        let fireAt = WorkplaceAutomationRules.statusPromptDate(for: shift)
        let prompt = WorkplaceAutomationRules.statusPrompt(
            for: shift,
            knownArrival: knownStart(of: shift, in: state),
            workConfirmed: state.statusAnswer(shiftKey: shift.shiftKey) != nil
                || state.adoptedTime(shiftKey: shift.shiftKey, boundary: .start) != nil,
            context: state.context(for: shift.anchorDayKey),
            isFullDayLeave: false,
            now: fireAt
        )
        guard prompt != .none, !state.isSuppressed(shift.shiftKey) else { return nil }
        return AutomationPrompt(identifier: statusPromptIdentifier(shiftKey: shift.shiftKey),
                                kind: .status(prompt), fireAt: fireAt)
    }

    /// The open visit's question, if the person is still there when it is due.
    private static func visitPrompt(state: WorkplaceAutomationState, now: Date) -> AutomationPrompt? {
        guard let visit = state.openVisit, visit.status == .waiting, visit.promptAt > now else { return nil }
        let kind: AutomationPrompt.Kind
        switch visit.kind {
        case .early(let proposalID):
            // Already answered in the review list: nothing left to ask.
            guard state.proposal(proposalID)?.status == .pendingReview else { return nil }
            kind = .earlyVisit(visitID: visit.id)
        case .offShift:
            kind = .offShiftVisit(visitID: visit.id)
        }
        return AutomationPrompt(identifier: visitPromptIdentifier(visitID: visit.id), kind: kind, fireAt: visit.promptAt)
    }

    /// One neutral check for a shift that started but has no end: soon after
    /// the planned end when the person left early and did not return, else
    /// when automation stops matching exits to it.
    private static func missingEndPrompt(state: WorkplaceAutomationState, shifts: [AutomationShift], now: Date) -> AutomationPrompt? {
        let candidates: [(AutomationShift, Date)] = shifts.compactMap { shift in
            guard knownStart(of: shift, in: state) != nil, !hasEnd(shift, in: state),
                  state.context(for: shift.anchorDayKey) == .regular,
                  !state.isSuppressed(shift.shiftKey) else { return nil }
            let fireAt = state.earlyExits[shift.shiftKey] != nil
                ? shift.plannedEnd.addingTimeInterval(WorkplaceAutomation.statusPromptDelay)
                : shift.plannedEnd.addingTimeInterval(WorkplaceAutomation.maximumAutomaticExtension)
            return fireAt > now ? (shift, fireAt) : nil
        }
        guard let (shift, fireAt) = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        return AutomationPrompt(identifier: missingEndIdentifier(shiftKey: shift.shiftKey), kind: .missingEnd, fireAt: fireAt)
    }

    /// An arrival known for this shift: adopted, waiting for review, or dismissed
    /// ("just arrived early" still means the person arrived).
    private static func knownStart(of shift: AutomationShift, in state: WorkplaceAutomationState) -> Date? {
        state.proposals
            .filter { $0.shiftKey == shift.shiftKey && $0.boundary == .start && $0.status != .superseded }
            .map(\.proposedTime)
            .min()
    }

    private static func hasEnd(_ shift: AutomationShift, in state: WorkplaceAutomationState) -> Bool {
        state.proposals.contains {
            $0.shiftKey == shift.shiftKey && $0.boundary == .end && $0.status != .superseded && $0.status != .dismissed
        }
    }
}

/// Plan 021 §3.8: the short notice after a workplace arrival or departure.
/// It says whether hours changed or only a record was kept, never names a
/// workplace, an address or pay, and is only a submission: iOS may still
/// hold it back under Focus or notification settings.
nonisolated struct WorkplaceArrivalNotice: Equatable, Sendable {
    static let identifierPrefix = "owc.automationNotice."

    var identifier: String
    var bodyKey: String
    var time: Date
    /// The overtime an applied clock-out recorded, once past the grace period.
    var overtime: TimeInterval? = nil
    /// Opens the review list only when something there waits for the person;
    /// a notice about a time already recorded must not read as a doubt.
    var needsReview = false

    static var backAtWorkKey: String { "automationNoticeBackAtWork" }

    static func bodyKey(arrived: Bool, applied: Bool, withOvertime: Bool = false) -> String {
        switch (arrived, applied) {
        case (true, true): "automationNoticeArrivedApplied"
        case (false, true): withOvertime ? "automationNoticeLeftAppliedOvertime" : "automationNoticeLeftApplied"
        case (true, false): "automationNoticeArrivedRecorded"
        case (false, false): "automationNoticeLeftRecorded"
        }
    }

    /// Nothing for ignored, repeated or unavailable outcomes, or when the
    /// person turned these notices off.
    static func make(
        for event: AutomationEvent,
        outcome: AutomationCommandOutcome,
        state: WorkplaceAutomationState
    ) -> WorkplaceArrivalNotice? {
        guard event.source == .nativeGeofence, state.settings.notifiesArrivalsAndDepartures,
              !event.isInitialState else { return nil }
        let applied: Bool
        switch outcome {
        case .applied: applied = true
        case .recordedForReview, .needsReview: applied = false
        case .alreadyApplied, .ignored, .temporarilyUnavailable: return nil
        }
        // Back after the recorded clock-out: overtime simply goes on.
        if event.type == .enterInner, state.awayStretches.contains(where: { $0.returnEventID == event.id }) {
            return WorkplaceArrivalNotice(
                identifier: identifierPrefix + event.id.uuidString,
                bodyKey: backAtWorkKey,
                time: event.proposedTime
            )
        }
        // An on-time arrival adopts the planned start, not the crossing.
        let proposal = state.proposals.last { $0.sourceEventIDs.contains(event.id) }
        let overtime = proposal.flatMap { proposal -> TimeInterval? in
            guard applied, proposal.boundary == .end else { return nil }
            let past = proposal.proposedTime.timeIntervalSince(proposal.shift.plannedEnd)
            return past >= WorkplacePresence.overtimeGrace ? past : nil
        }
        return WorkplaceArrivalNotice(
            identifier: identifierPrefix + event.id.uuidString,
            bodyKey: bodyKey(arrived: event.type == .enterInner, applied: applied, withOvertime: overtime != nil),
            time: outcome == .applied ? proposal?.proposedTime ?? event.proposedTime : event.proposedTime,
            overtime: overtime,
            needsReview: !applied
        )
    }
}
