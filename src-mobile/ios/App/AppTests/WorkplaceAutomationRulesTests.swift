import Foundation
import Testing
@testable import App

/// Plan 021 P1: pure workplace automation decisions (§3.1–§3.10).
@Suite("Workplace automation rules")
struct WorkplaceAutomationRulesTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private static func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1_000 }

    /// 09:00–18:00 with lunch 12:00–13:00.
    private static func dayShift(_ day: Int = 9) -> AutomationShift {
        AutomationShift(
            shiftKey: "2026-11-\(String(format: "%02d", day))#day",
            plannedStart: at(day, 9),
            plannedEnd: at(day, 18),
            segments: [
                NativeShiftSegment(startAtMs: ms(at(day, 9)), endAtMs: ms(at(day, 12))),
                NativeShiftSegment(startAtMs: ms(at(day, 13)), endAtMs: ms(at(day, 18))),
            ]
        )
    }

    /// Overnight 22:00–06:00 anchored on the evening it starts.
    private static func nightShift(_ day: Int = 9) -> AutomationShift {
        AutomationShift(
            shiftKey: "2026-11-\(String(format: "%02d", day))#night",
            plannedStart: at(day, 22),
            plannedEnd: at(day + 1, 6),
            segments: [NativeShiftSegment(startAtMs: ms(at(day, 22)), endAtMs: ms(at(day + 1, 6)))]
        )
    }

    private static func event(
        _ type: AutomationEventType = .enterInner,
        source: AutomationEventSource = .nativeGeofence,
        observedAt: Date?,
        receivedAt: Date? = nil,
        generation: Int = 1,
        initial: Bool = false
    ) -> AutomationEvent {
        AutomationEvent(
            id: UUID(),
            source: source,
            type: type,
            workplaceID: UUID(),
            registrationGeneration: generation,
            observedAt: observedAt,
            receivedAt: receivedAt ?? observedAt ?? at(9, 9),
            timestampBasis: observedAt == nil ? .callbackReceipt : .systemObservation,
            isInitialState: initial
        )
    }

    private static let applying = WorkplaceAutomationSettings(
        isMonitoringEnabled: true,
        appliesDetectedTimesAutomatically: true
    )

    // MARK: Matching

    @Test("An arrival matches one shift inside 120 minutes before to 180 after its start")
    func arrivalWindow() {
        let shift = Self.dayShift()
        #expect(WorkplaceAutomationRules.matchArrival(at: Self.at(9, 7), among: [shift]) == .matched(shift))
        #expect(WorkplaceAutomationRules.matchArrival(at: Self.at(9, 6, 59), among: [shift]) == .noShift)
        #expect(WorkplaceAutomationRules.matchArrival(at: Self.at(9, 12), among: [shift]) == .matched(shift))
        #expect(WorkplaceAutomationRules.matchArrival(at: Self.at(9, 12, 1), among: [shift]) == .noShift)
    }

    @Test("Two shifts that could both own an arrival start nothing")
    func ambiguousArrival() {
        let early = AutomationShift(
            shiftKey: "a", plannedStart: Self.at(9, 8), plannedEnd: Self.at(9, 12), segments: []
        )
        let late = AutomationShift(
            shiftKey: "b", plannedStart: Self.at(9, 9), plannedEnd: Self.at(9, 17), segments: []
        )
        #expect(WorkplaceAutomationRules.matchArrival(at: Self.at(9, 8, 30), among: [early, late]) == .ambiguous)
    }

    @Test("An exit at 06:30 belongs to the overnight shift that began the evening before")
    func overnightExit() {
        let night = Self.nightShift(9)
        let nextDay = Self.dayShift(10)
        let match = WorkplaceAutomationRules.matchExit(at: Self.at(10, 6, 30), among: [night, nextDay])
        #expect(match == .matched(night))
    }

    // MARK: Early, punctual, late

    @Test("08:20, 08:30 and 08:50 arrivals for 09:00 with a 30 minute wait (§8.2)")
    func earlyArrivalBoundaries() {
        let shift = Self.dayShift()
        #expect(
            WorkplaceAutomationRules.assessArrival(at: Self.at(9, 8, 20), for: shift, promptDelay: .thirtyMinutes)
                == .early(promptAt: Self.at(9, 8, 50))
        )
        // The question would land exactly at the start: record only.
        #expect(
            WorkplaceAutomationRules.assessArrival(at: Self.at(9, 8, 30), for: shift, promptDelay: .thirtyMinutes)
                == .punctual
        )
        #expect(
            WorkplaceAutomationRules.assessArrival(at: Self.at(9, 8, 50), for: shift, promptDelay: .thirtyMinutes)
                == .punctual
        )
        #expect(
            WorkplaceAutomationRules.assessArrival(at: Self.at(9, 9, 10), for: shift, promptDelay: .thirtyMinutes)
                == .late
        )
    }

    @Test("A shorter wait asks earlier arrivals sooner")
    func waitSetting() {
        let shift = Self.dayShift()
        #expect(
            WorkplaceAutomationRules.assessArrival(at: Self.at(9, 8, 30), for: shift, promptDelay: .fifteenMinutes)
                == .early(promptAt: Self.at(9, 8, 45))
        )
    }

    // MARK: Exits

    @Test("Leaving before the planned end, lunch included, is only a temporary absence")
    func temporaryAbsence() {
        let shift = Self.dayShift()
        #expect(WorkplaceAutomationRules.assessExit(at: Self.at(9, 12, 5), for: shift) == .temporaryAbsence)
        #expect(WorkplaceAutomationRules.assessExit(at: Self.at(9, 17, 59), for: shift) == .temporaryAbsence)
    }

    @Test("A late exit yields overtime, and past six hours it is reviewed instead")
    func lateExit() {
        let shift = Self.dayShift()
        #expect(WorkplaceAutomationRules.assessExit(at: Self.at(9, 18), for: shift) == .shiftEnded(overtime: 0))
        #expect(
            WorkplaceAutomationRules.assessExit(at: Self.at(9, 19, 30), for: shift)
                == .shiftEnded(overtime: 90 * 60)
        )
        #expect(
            WorkplaceAutomationRules.assessExit(at: Self.at(10, 0, 1), for: shift)
                == .needsReview(.beyondAutomaticWindow)
        )
    }

    // MARK: Status question

    @Test("The status question is due 30 minutes after the planned start and asked once")
    func statusPrompt() {
        let shift = Self.dayShift()
        let due = Self.at(9, 9, 30)
        #expect(WorkplaceAutomationRules.statusPromptDate(for: shift) == due)
        let ask = { (arrival: Date?, confirmed: Bool, context: WorkDayContext, now: Date) in
            WorkplaceAutomationRules.statusPrompt(
                for: shift, knownArrival: arrival, workConfirmed: confirmed,
                context: context, isFullDayLeave: false, now: now
            )
        }
        #expect(ask(nil, false, .regular, Self.at(9, 9, 29)) == .none)
        #expect(ask(nil, false, .regular, due) == .statusUnconfirmed)
        #expect(ask(Self.at(9, 8, 55), false, .regular, due) == .none)
        #expect(ask(Self.at(9, 9, 10), false, .regular, due) == .lateArrival)
        #expect(ask(Self.at(9, 9, 10), true, .regular, due) == .none)
        #expect(ask(nil, false, .remote, due) == .none)
        #expect(ask(nil, false, .fieldwork, due) == .none)
        // An arrival reported after the question time is not known yet.
        #expect(ask(Self.at(9, 9, 40), false, .regular, due) == .statusUnconfirmed)
        #expect(
            WorkplaceAutomationRules.statusPrompt(
                for: shift, knownArrival: nil, workConfirmed: false,
                context: .regular, isFullDayLeave: true, now: due
            ) == .none
        )
    }

    // MARK: Several workplaces

    @Test("Leaving one workplace while inside another is not leaving work")
    func multipleWorkplaces() {
        let a = UUID(), b = UUID()
        #expect(!WorkplaceAutomationRules.leavesAllWorkplaces(exitingWorkplace: a, inside: [a, b]))
        #expect(WorkplaceAutomationRules.leavesAllWorkplaces(exitingWorkplace: a, inside: [a]))
        #expect(WorkplaceAutomationRules.leavesAllWorkplaces(exitingWorkplace: a, inside: []))
    }

    // MARK: Disposition

    @Test("Automatic apply is off by default, so fresh events wait for review")
    func reviewByDefault() {
        let now = Self.at(9, 9)
        var settings = WorkplaceAutomationSettings()
        settings.isMonitoringEnabled = true
        let result = WorkplaceAutomationRules.disposition(
            for: Self.event(observedAt: now), now: now, currentGeneration: 1,
            settings: settings, canCollect: true, canAutoApply: true, isManuallySuppressed: false
        )
        #expect(result == .recordForReview(.automaticApplyOff))
    }

    @Test("Only a fresh, observed, entitled event applies by itself")
    func applyConditions() {
        let now = Self.at(9, 9)
        let fresh = Self.event(observedAt: now.addingTimeInterval(-5 * 60))
        func run(
            _ event: AutomationEvent,
            generation: Int? = 1,
            settings: WorkplaceAutomationSettings = Self.applying,
            collect: Bool = true,
            autoApply: Bool = true,
            suppressed: Bool = false,
            context: WorkDayContext = .regular
        ) -> AutomationDisposition {
            WorkplaceAutomationRules.disposition(
                for: event, now: now, currentGeneration: generation, settings: settings,
                canCollect: collect, canAutoApply: autoApply, isManuallySuppressed: suppressed,
                context: context
            )
        }
        #expect(run(fresh) == .apply)
        #expect(run(Self.event(observedAt: now.addingTimeInterval(-16 * 60))) == .recordForReview(.staleEvent))
        #expect(run(Self.event(observedAt: nil, receivedAt: now)) == .recordForReview(.unknownObservationTime))
        #expect(run(fresh, autoApply: false) == .recordForReview(.notEntitled))
        #expect(run(fresh, generation: 2) == .ignore(.staleRegistration))
        #expect(run(fresh, settings: WorkplaceAutomationSettings()) == .ignore(.monitoringOff))
        #expect(run(fresh, collect: false) == .ignore(.monitoringOff))
        #expect(run(fresh, suppressed: true) == .ignore(.manualOverride))
        #expect(run(fresh, context: .rest) == .ignore(.restDayContext))
        #expect(run(Self.event(observedAt: now, initial: true)) == .ignore(.baselineOnly))
    }

    @Test("A person's own confirmation applies even with automatic apply off")
    func confirmationIsAuthorization() {
        let now = Self.at(9, 9)
        let confirmation = Self.event(source: .userConfirmation, observedAt: nil, receivedAt: now)
        var settings = WorkplaceAutomationSettings()
        settings.isMonitoringEnabled = false
        let result = WorkplaceAutomationRules.disposition(
            for: confirmation, now: now, currentGeneration: nil, settings: settings,
            canCollect: true, canAutoApply: false, isManuallySuppressed: false
        )
        #expect(result == .apply)
    }

    @Test("A Shortcuts report is not tied to a geofence registration")
    func shortcutsReport() {
        let now = Self.at(9, 9)
        let report = Self.event(source: .appIntentAutomation, observedAt: now, generation: 0)
        let result = WorkplaceAutomationRules.disposition(
            for: report, now: now, currentGeneration: nil, settings: Self.applying,
            canCollect: true, canAutoApply: true, isManuallySuppressed: false
        )
        #expect(result == .apply)
    }

    // MARK: Segments

    @Test("A late arrival keeps lunch and the planned end")
    func lateArrivalSegments() {
        let shift = Self.dayShift()
        let segments = WorkplaceAutomationRules.proposedSegments(
            for: shift, start: Self.at(9, 9, 10), end: Self.at(9, 18)
        )
        #expect(segments == [
            NativeShiftSegment(startAtMs: Self.ms(Self.at(9, 9, 10)), endAtMs: Self.ms(Self.at(9, 12))),
            NativeShiftSegment(startAtMs: Self.ms(Self.at(9, 13)), endAtMs: Self.ms(Self.at(9, 18))),
        ])
    }

    @Test("Overtime extends the last segment to the exit")
    func overtimeSegments() {
        let shift = Self.dayShift()
        let segments = WorkplaceAutomationRules.proposedSegments(
            for: shift, start: Self.at(9, 9), end: Self.at(9, 19, 30)
        )
        #expect(segments.last == NativeShiftSegment(
            startAtMs: Self.ms(Self.at(9, 13)), endAtMs: Self.ms(Self.at(9, 19, 30))
        ))
        #expect(segments.count == 2)
    }

    @Test("A confirmed early start adds the time before the first segment")
    func confirmedEarlyStart() {
        let shift = Self.dayShift()
        let segments = WorkplaceAutomationRules.proposedSegments(
            for: shift, start: Self.at(9, 8, 20), end: Self.at(9, 18)
        )
        #expect(segments.first == NativeShiftSegment(
            startAtMs: Self.ms(Self.at(9, 8, 20)), endAtMs: Self.ms(Self.at(9, 12))
        ))
    }

    // MARK: Notifications

    @Test("Shift reminders keep today's budget until monitoring is on")
    func notificationBudget() {
        #expect(WorkplaceAutomationNotificationPlan.shiftReminderBudget(isMonitoringEnabled: false)
            == 60 - CycleReportNotificationPlan.reservedSlots)
        #expect(WorkplaceAutomationNotificationPlan.shiftReminderBudget(isMonitoringEnabled: true)
            == 60 - CycleReportNotificationPlan.reservedSlots - 3)
        // Focus timers (2), alarm refresh (1), Live Activity fallback (1)
        // and every reserved slot still fit iOS's 64 pending requests.
        let total = WorkplaceAutomationNotificationPlan.shiftReminderBudget(isMonitoringEnabled: true)
            + CycleReportNotificationPlan.reservedSlots
            + WorkplaceAutomationNotificationPlan.reservedSlots(isMonitoringEnabled: true)
            + 2 + 1 + 1
        #expect(total <= 64)
    }
}
