import Foundation

// Plan 021 P1: the decisions workplace automation makes, as pure functions.
//
// Nothing here reads location, files or the clock. A geofence callback, a
// Shortcuts action and a notification answer all arrive as an
// `AutomationEvent`; these rules say what that event means for one planned
// shift. Applying a result goes through the existing record commands, and the
// adopted times live in `DayOverride.customSegments` (plan §0.3).

nonisolated enum WorkplaceAutomation {
    /// The settings entry stays in development builds, and the internal
    /// TestFlight probe build (`WORKPLACE_PROBE`), until P0 device results
    /// approve release; Shortcuts actions work without it.
#if DEBUG || WORKPLACE_PROBE
    static let showsSettingsEntry = true
#else
    static let showsSettingsEntry = false
#endif

    /// Saved workplaces, disabled ones included (§3.10).
    static let maximumWorkplaces = 5
    /// The single status question after the planned start (§3.10).
    static let statusPromptDelay: TimeInterval = 30 * 60
    /// An arrival matches a shift from 120 minutes before its start
    /// (implementation default, §3.1).
    static let arrivalLeadWindow: TimeInterval = 120 * 60
    /// …to 180 minutes after it (implementation default, §3.1).
    static let arrivalLagWindow: TimeInterval = 180 * 60
    /// An exit later than this after the planned end is reviewed, never
    /// applied silently (implementation default, §3.1).
    static let maximumAutomaticExtension: TimeInterval = 6 * 60 * 60
    /// An exit up to this long after the planned end still belongs to the
    /// shift, for review: a long night at work must not vanish just because
    /// it is too long to apply on its own. Later than this, or once a later
    /// shift has started, it says nothing about the shift.
    static let maximumReviewableExtension: TimeInterval = 18 * 60 * 60
    /// Older events are only offered for review (implementation default, §3.5).
    static let maximumAutomaticEventAge: TimeInterval = 15 * 60
    /// Unadopted references and their readable details (§3.7).
    static let unadoptedRetention: TimeInterval = 90 * 24 * 60 * 60
    /// Raw diagnostics: at most 7 days and 200 entries (implementation default, §3.7).
    static let diagnosticRetention: TimeInterval = 7 * 24 * 60 * 60
    static let maximumDiagnostics = 200
    /// Default circle sizes; P0 measures them on devices (§3.1).
    static let defaultInnerRadius: Double = 200
    static let defaultOuterRadiusMargin: Double = 100
    /// How long a move between workplaces may take and still be counted as
    /// work when the person says so (implementation default, §3.10).
    static let maximumTransferGap: TimeInterval = 2 * 60 * 60
    /// Bumped whenever a decision below changes meaning. Provenance records it.
    static let rulesVersion = 1
}

/// How long a visit outside a shift, or an early arrival, waits before asking.
nonisolated enum WorkplaceVisitPromptDelay: Int, Codable, CaseIterable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case sixtyMinutes = 60

    var interval: TimeInterval { TimeInterval(rawValue * 60) }
}

/// The day's working arrangement. There is deliberately no home address (§3.10).
nonisolated enum WorkDayContext: String, Codable, CaseIterable, Sendable {
    case regular
    case fieldwork
    case businessTrip
    case remote
    case rest
}

/// Device settings. Both switches start off and never turn on by migration,
/// restore, sync or install on another device (§3.1).
nonisolated struct WorkplaceAutomationSettings: Codable, Equatable, Sendable {
    var isMonitoringEnabled = false
    /// `applyAutomationTimesAutomatically`. Off keeps results for review only.
    var appliesDetectedTimesAutomatically = false
    var visitPromptDelay: WorkplaceVisitPromptDelay = .thirtyMinutes
    /// A short local notification when an arrival or departure is recorded
    /// or applied (§3.8). Detection does not depend on it.
    var notifiesArrivalsAndDepartures = true
}

nonisolated extension WorkplaceAutomationSettings {
    private enum CodingKeys: String, CodingKey {
        case isMonitoringEnabled, appliesDetectedTimesAutomatically, visitPromptDelay, notifiesArrivalsAndDepartures
    }

    /// Settings added later decode with their defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        isMonitoringEnabled = try container.decode(Bool.self, forKey: .isMonitoringEnabled)
        appliesDetectedTimesAutomatically = try container.decode(Bool.self, forKey: .appliesDetectedTimesAutomatically)
        visitPromptDelay = try container.decode(WorkplaceVisitPromptDelay.self, forKey: .visitPromptDelay)
        notifiesArrivalsAndDepartures = try container.decodeIfPresent(Bool.self, forKey: .notifiesArrivalsAndDepartures) ?? true
    }
}

/// One planned shift as the schedule rules resolved it. The automation never
/// derives its own schedule; callers build this from the existing snapshot.
nonisolated struct AutomationShift: Codable, Equatable, Sendable {
    /// Stable identity: anchor day plus plan identity (§3.2).
    var shiftKey: String
    /// The records day the shift belongs to (its start day, `YYYY-MM-DD`).
    var anchorDayKey: String
    var plannedStart: Date
    var plannedEnd: Date
    /// Effective working segments, breaks already removed.
    var segments: [NativeShiftSegment]
}

nonisolated enum AutomationEventType: String, Codable, Sendable {
    case enterInner
    case exitOuter
}

nonisolated enum AutomationEventSource: String, Codable, Sendable {
    case nativeGeofence
    case appIntentAutomation
    case userConfirmation
}

nonisolated enum AutomationTimestampBasis: String, Codable, Sendable {
    /// The system reported when it observed the crossing.
    case systemObservation
    /// Only the time the app received the callback is known.
    case callbackReceipt
    case userAction
}

/// A system observation or user statement. Stays on this device (§3.7).
nonisolated struct AutomationEvent: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var source: AutomationEventSource
    var type: AutomationEventType
    /// Nil for a Shortcuts report, which names no saved workplace.
    var workplaceID: UUID?
    var registrationGeneration: Int
    /// When the system observed it. Unknown stays nil; never back-filled.
    var observedAt: Date?
    var receivedAt: Date
    var timestampBasis: AutomationTimestampBasis
    /// The first state after registering, re-authorizing or restoring.
    var isInitialState = false

    /// The time a proposal starts from. Receipt time only stands in, with a
    /// review reason, when the observation time is unknown.
    var proposedTime: Date { observedAt ?? receivedAt }
}

// MARK: - Shift matching

nonisolated enum AutomationShiftMatch: Equatable, Sendable {
    case matched(AutomationShift)
    case noShift
    /// More than one shift could own the event; nothing starts (§3.2).
    case ambiguous
}

// MARK: - Arrival

nonisolated enum ArrivalAssessment: Equatable, Sendable {
    /// Early: recorded now, asked about at `promptAt` (§3.9).
    case early(promptAt: Date)
    /// Arrived early, but the question would come at or after the planned
    /// start: record only, no early question, no early overtime (§3.9).
    case punctual
    case late
}

// MARK: - Exit

nonisolated enum ExitAssessment: Equatable, Sendable {
    /// Before the planned end, lunch included: a trace only (§3.10).
    case temporaryAbsence
    /// At or after the planned end. `overtime` is zero for an on-time exit.
    case shiftEnded(overtime: TimeInterval)
    case needsReview(AutomationReviewReason)
}

// MARK: - Status question

nonisolated enum AutomationStatusPrompt: Equatable, Sendable {
    case none
    /// "Recorded a later arrival — record today as usual?"
    case lateArrival
    /// Nothing known yet. Never claims the person is not at work (§3.10).
    case statusUnconfirmed
}

// MARK: - Disposition

nonisolated enum AutomationReviewReason: String, Codable, Sendable {
    case automaticApplyOff
    case notEntitled
    case unknownObservationTime
    case staleEvent
    case beyondAutomaticWindow
    case earlyStartNeedsConfirmation
    case leftBeforePlannedEnd
    /// The person changed the day after automation last wrote it.
    case recordChangedByPerson
    /// Records are locked or damaged; nothing was written.
    case recordsUnavailable
}

nonisolated enum AutomationIgnoreReason: String, Codable, Sendable {
    case monitoringOff
    case staleRegistration
    case baselineOnly
    case manualOverride
    case otherWorkplaceStillInside
    case noShift
    case ambiguousShift
    case restDayContext
    /// Leaving before the planned end is only a trace (§3.10).
    case temporaryAbsence
}

nonisolated enum AutomationDisposition: Equatable, Sendable {
    case apply
    case recordForReview(AutomationReviewReason)
    case ignore(AutomationIgnoreReason)
}

// MARK: - Rules

nonisolated enum WorkplaceAutomationRules {
    /// The one shift an arrival at `time` belongs to. The window only finds
    /// the shift; it never makes an early arrival count as work (§3.1).
    static func matchArrival(at time: Date, among shifts: [AutomationShift]) -> AutomationShiftMatch {
        let candidates = shifts.filter { shift in
            time >= shift.plannedStart.addingTimeInterval(-WorkplaceAutomation.arrivalLeadWindow)
                && time <= shift.plannedStart.addingTimeInterval(WorkplaceAutomation.arrivalLagWindow)
                && time < shift.plannedEnd
        }
        switch candidates.count {
        case 0: return .noShift
        case 1: return .matched(candidates[0])
        default: return .ambiguous
        }
    }

    /// The shift an exit at `time` can close: the one running, or the most
    /// recent one that ended within the reviewable window. An overnight
    /// 22:00–06:00 exit belongs to the shift that started the evening before.
    /// Past the automatic window `assessExit` sends it to review.
    static func matchExit(at time: Date, among shifts: [AutomationShift]) -> AutomationShiftMatch {
        let candidates = shifts.filter { shift in
            time > shift.plannedStart
                && time <= shift.plannedEnd.addingTimeInterval(WorkplaceAutomation.maximumReviewableExtension)
        }
        guard let latest = candidates.max(by: { $0.plannedStart < $1.plannedStart }) else {
            return .noShift
        }
        // An exit far past one shift's end but before the next one starts
        // belongs to the first; a later shift that started takes it.
        // A later shift that already started wins; an earlier one still
        // inside its extension window cannot be closed by the same exit.
        let running = candidates.filter { time < $0.plannedEnd }
        if running.count > 1 { return .ambiguous }
        return .matched(running.first ?? latest)
    }

    static func assessArrival(
        at arrival: Date,
        for shift: AutomationShift,
        promptDelay: WorkplaceVisitPromptDelay
    ) -> ArrivalAssessment {
        if arrival > shift.plannedStart { return .late }
        let promptAt = arrival.addingTimeInterval(promptDelay.interval)
        return promptAt < shift.plannedStart ? .early(promptAt: promptAt) : .punctual
    }

    /// Late arrival keeps the planned end; it never shifts the day (§3.2).
    static func assessExit(at exit: Date, for shift: AutomationShift) -> ExitAssessment {
        if exit < shift.plannedEnd { return .temporaryAbsence }
        let overtime = exit.timeIntervalSince(shift.plannedEnd)
        if overtime > WorkplaceAutomation.maximumAutomaticExtension {
            return .needsReview(.beyondAutomaticWindow)
        }
        return .shiftEnded(overtime: overtime)
    }

    /// When the once-per-shift status question is due.
    static func statusPromptDate(for shift: AutomationShift) -> Date {
        shift.plannedStart.addingTimeInterval(WorkplaceAutomation.statusPromptDelay)
    }

    /// What the status question says at `now`, from what is known by then.
    /// Pending review items alone never trigger it (§3.10).
    static func statusPrompt(
        for shift: AutomationShift,
        knownArrival: Date?,
        workConfirmed: Bool,
        context: WorkDayContext,
        isFullDayLeave: Bool,
        now: Date
    ) -> AutomationStatusPrompt {
        guard context == .regular, !isFullDayLeave, !workConfirmed else { return .none }
        guard now >= statusPromptDate(for: shift) else { return .none }
        guard let knownArrival, knownArrival <= now else { return .statusUnconfirmed }
        return knownArrival > shift.plannedStart ? .lateArrival : .none
    }

    /// Whether an exit leaves every saved workplace. Leaving A while still
    /// inside B is not leaving work (§3.10).
    static func leavesAllWorkplaces(
        exitingWorkplace: UUID?,
        inside: Set<UUID>
    ) -> Bool {
        guard let exitingWorkplace else { return inside.isEmpty }
        return inside.subtracting([exitingWorkplace]).isEmpty
    }

    /// Whether an event may change the record by itself, must wait for
    /// review, or does nothing. Checks run from structural to policy so the
    /// reason shown is the most fundamental one.
    static func disposition(
        for event: AutomationEvent,
        now: Date,
        currentGeneration: Int?,
        settings: WorkplaceAutomationSettings,
        canCollect: Bool,
        canAutoApply: Bool,
        isManuallySuppressed: Bool,
        context: WorkDayContext = .regular
    ) -> AutomationDisposition {
        if event.source == .nativeGeofence {
            guard settings.isMonitoringEnabled else { return .ignore(.monitoringOff) }
            guard event.registrationGeneration == currentGeneration else {
                return .ignore(.staleRegistration)
            }
        }
        guard canCollect else { return .ignore(.monitoringOff) }
        if event.isInitialState { return .ignore(.baselineOnly) }
        if isManuallySuppressed { return .ignore(.manualOverride) }
        if context == .rest { return .ignore(.restDayContext) }
        // A person's own confirmation is the authorization; the switch does
        // not gate it (§3.1).
        if event.source == .userConfirmation { return .apply }
        guard let observedAt = event.observedAt else {
            return .recordForReview(.unknownObservationTime)
        }
        if now.timeIntervalSince(observedAt) > WorkplaceAutomation.maximumAutomaticEventAge {
            return .recordForReview(.staleEvent)
        }
        guard canAutoApply else { return .recordForReview(.notEntitled) }
        guard settings.appliesDetectedTimesAutomatically else {
            return .recordForReview(.automaticApplyOff)
        }
        return .apply
    }

    /// The working segments a proposal would adopt: the planned segments
    /// clipped to the adopted start, and, after the planned end, one overtime
    /// span to the adopted end. Real gaps such as lunch are kept (§3.9).
    static func proposedSegments(
        for shift: AutomationShift,
        start: Date,
        end: Date
    ) -> [NativeShiftSegment] {
        let startMs = start.timeIntervalSince1970 * 1_000
        let endMs = end.timeIntervalSince1970 * 1_000
        let plannedEndMs = shift.plannedEnd.timeIntervalSince1970 * 1_000
        let regularEndMs = min(endMs, plannedEndMs)
        var segments: [NativeShiftSegment] = []
        // An early start the person confirmed runs up to the first segment.
        if let first = shift.segments.first, startMs < first.startAtMs {
            segments.append(NativeShiftSegment(startAtMs: startMs, endAtMs: min(first.startAtMs, regularEndMs)))
        }
        for segment in shift.segments {
            let clippedStart = max(segment.startAtMs, startMs)
            let clippedEnd = min(segment.endAtMs, regularEndMs)
            if clippedEnd > clippedStart {
                segments.append(NativeShiftSegment(startAtMs: clippedStart, endAtMs: clippedEnd))
            }
        }
        if endMs > plannedEndMs {
            let overtimeStart = max(plannedEndMs, startMs)
            if let last = segments.last, last.endAtMs == overtimeStart {
                segments[segments.count - 1] = NativeShiftSegment(startAtMs: last.startAtMs, endAtMs: endMs)
            } else if endMs > overtimeStart {
                segments.append(NativeShiftSegment(startAtMs: overtimeStart, endAtMs: endMs))
            }
        }
        return mergeTouching(segments.filter { $0.endAtMs > $0.startAtMs })
    }

    /// Where work resumes when the person says an off-shift arrival was a
    /// move between workplaces (§3.10): the latest recorded end of work
    /// before the arrival, if it is close enough. Without one, the arrival.
    /// A gap is only counted because the person said so; it is never guessed.
    static func transferStart(arrivedAt: Date, state: WorkplaceAutomationState) -> Date? {
        let ends = state.proposals
            .filter { $0.boundary == .end && ($0.isAdopted || $0.status == .pendingReview) }
            .map(\.proposedTime)
            + state.visits.filter { $0.status == .closed }.compactMap(\.leftAt)
        return ends
            .filter { $0 <= arrivedAt && arrivedAt.timeIntervalSince($0) <= WorkplaceAutomation.maximumTransferGap }
            .max()
    }

    /// Shifts the person paused automation for by correcting them, while a
    /// resume can still matter: until automation stops matching their exits.
    static func resumableShifts(
        state: WorkplaceAutomationState,
        shifts: [AutomationShift],
        now: Date
    ) -> [AutomationShift] {
        shifts
            .filter { state.isSuppressed($0.shiftKey)
                && now < $0.plannedEnd.addingTimeInterval(WorkplaceAutomation.maximumAutomaticExtension) }
            .sorted { $0.plannedStart < $1.plannedStart }
    }

    /// Joins overlapping or touching segments after sorting them.
    static func union(_ segments: [NativeShiftSegment]) -> [NativeShiftSegment] {
        mergeTouching(segments.filter { $0.endAtMs > $0.startAtMs }.sorted { $0.startAtMs < $1.startAtMs })
    }

    private static func mergeTouching(_ segments: [NativeShiftSegment]) -> [NativeShiftSegment] {
        var merged: [NativeShiftSegment] = []
        for segment in segments.sorted(by: { $0.startAtMs < $1.startAtMs }) {
            if let last = merged.last, segment.startAtMs <= last.endAtMs {
                merged[merged.count - 1] = NativeShiftSegment(
                    startAtMs: last.startAtMs,
                    endAtMs: max(last.endAtMs, segment.endAtMs)
                )
            } else {
                merged.append(segment)
            }
        }
        return merged
    }
}

// MARK: - Notification budget

/// The pending notifications workplace automation may hold (plan §0.3).
///
/// iOS keeps 64. Focus timers (2), the alarm refresh (1) and the Live
/// Activity end fallback sit outside the shift budget; cycle reports reserve
/// theirs. Automation holds three only while monitoring is on, so people who
/// never turn it on keep every shift reminder they have today.
nonisolated enum WorkplaceAutomationNotificationPlan {
    static let identifierPrefix = "owc.automation."

    static func reservedSlots(isMonitoringEnabled: Bool) -> Int {
        isMonitoringEnabled ? 3 : 0
    }

    static func shiftReminderBudget(isMonitoringEnabled: Bool) -> Int {
        60 - CycleReportNotificationPlan.reservedSlots - reservedSlots(isMonitoringEnabled: isMonitoringEnabled)
    }

    /// Slot 1: the next shift's status question, rolled forward each wake.
    static func statusPromptIdentifier(shiftKey: String) -> String {
        "\(identifierPrefix)status.\(shiftKey)"
    }

    /// Slot 2: early-arrival or off-shift visit question; one per visit.
    static func visitPromptIdentifier(visitID: UUID) -> String {
        "\(identifierPrefix)visit.\(visitID.uuidString)"
    }

    /// Slot 3: the single neutral missing-end check (§3.9).
    static func missingEndIdentifier(shiftKey: String) -> String {
        "\(identifierPrefix)missingEnd.\(shiftKey)"
    }
}
