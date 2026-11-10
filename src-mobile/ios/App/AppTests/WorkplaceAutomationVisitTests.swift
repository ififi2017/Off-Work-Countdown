import Foundation
import Testing
@testable import App

/// Plan 021 P1: early and off-shift visits, unreturned exits, the status
/// question, days away from the office and the three notification slots.
@MainActor
@Suite("Workplace automation visits and questions")
struct WorkplaceAutomationVisitTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday 9 November 2026 unless another day is given.
    private static func at(_ hour: Int, _ minute: Int = 0, day: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private static func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1_000 }

    /// 09:00–17:00 with lunch 12:00–13:00, matching `hours()`.
    private static func shift(day: Int = 9) -> AutomationShift {
        let key = "2026-11-\(String(format: "%02d", day))"
        return AutomationShift(
            shiftKey: "\(key)#day", anchorDayKey: key,
            plannedStart: at(9, day: day), plannedEnd: at(17, day: day),
            segments: [
                NativeShiftSegment(startAtMs: ms(at(9, day: day)), endAtMs: ms(at(12, day: day))),
                NativeShiftSegment(startAtMs: ms(at(13, day: day)), endAtMs: ms(at(17, day: day))),
            ]
        )
    }

    private static func hours() -> ScheduleHoursConfiguration {
        .init(startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
            schedule: .init(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil,
                singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
            breakStartTime: "12:00", breakDurationMinutes: 60)
    }

    @MainActor
    private final class Harness {
        let suite = "WorkplaceAutomationVisits.\(UUID())"
        let defaults: UserDefaults
        let records = RecordCoordinator.inMemory()
        let plus: PlusEntitlement
        let actions: RecordsActions
        let coordinator: WorkplaceAutomationCoordinator
        var workplace: SavedWorkplace!

        init(applies: Bool = false) {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
            let preferences = PreferencesStore(defaults: defaults, records: records)
            plus = PlusEntitlement(defaults: defaults)
            plus.debugSetAuthorized(true)
            actions = RecordsActions(records: records, preferences: preferences, plus: plus,
                text: AppText(preferences: preferences), currentHours: { _ in WorkplaceAutomationVisitTests.hours() })
            coordinator = WorkplaceAutomationCoordinator(actions: actions, loaded: .missing) { _ in }
            coordinator.update { state in
                state.settings.isMonitoringEnabled = true
                state.settings.appliesDetectedTimesAutomatically = applies
                self.workplace = try! state.addWorkplace(name: "Office", latitude: 31, longitude: 121)
            }
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        @discardableResult
        func receive(_ type: AutomationEventType, at time: Date, shifts: [AutomationShift]? = nil) async -> AutomationCommandOutcome {
            let event = AutomationEvent(
                id: UUID(), source: .nativeGeofence, type: type, workplaceID: workplace.id,
                registrationGeneration: workplace.registrationGeneration,
                observedAt: time, receivedAt: time, timestampBasis: .systemObservation
            )
            return await coordinator.receive(event, shifts: shifts ?? [WorkplaceAutomationVisitTests.shift()], now: time)
        }

        func day(_ key: String) -> DayOverride? { records.state.overrides.first { $0.dayKey == key } }

        func prompts(now: Date, shifts: [AutomationShift]? = nil) -> [AutomationPrompt] {
            WorkplaceAutomationNotificationPlan.prompts(
                state: coordinator.state, shifts: shifts ?? [WorkplaceAutomationVisitTests.shift()],
                canCollect: plus.canCollectAutomation, now: now
            )
        }
    }

    private func segment(_ from: Date, _ to: Date) -> NativeShiftSegment {
        NativeShiftSegment(startAtMs: Self.ms(from), endAtMs: Self.ms(to))
    }

    // MARK: Back after the clock-out (P0 day 2)

    @Test("Back within two hours of the recorded clock-out: the day runs to the final exit")
    func returnAfterClockOut() async throws {
        let harness = Harness(applies: true)
        #expect(await harness.receive(.enterInner, at: Self.at(8, 55)) == .applied)
        #expect(await harness.receive(.exitOuter, at: Self.at(17, 15)) == .applied)
        let back = AutomationEvent(
            id: UUID(), source: .nativeGeofence, type: .enterInner, workplaceID: harness.workplace.id,
            registrationGeneration: harness.workplace.registrationGeneration,
            observedAt: Self.at(18, 30), receivedAt: Self.at(18, 30), timestampBasis: .systemObservation
        )
        let outcome = await harness.coordinator.receive(back, shifts: [Self.shift()], now: Self.at(18, 30))
        #expect(outcome == .recordedForReview)
        // Not an off-shift visit to ask about: overtime simply goes on.
        #expect(harness.coordinator.state.openVisit == nil)
        #expect(harness.coordinator.state.awayStretches(dayKey: "2026-11-09").map(\.leftAt) == [Self.at(17, 15)])
        #expect(WorkplaceArrivalNotice.make(for: back, outcome: outcome, state: harness.coordinator.state)?.bodyKey
            == WorkplaceArrivalNotice.backAtWorkKey)

        #expect(await harness.receive(.exitOuter, at: Self.at(20, 30)) == .applied)
        let day = try #require(harness.day("2026-11-09"))
        #expect(day.segments.map(\.endAtMs).max() == Self.ms(Self.at(20, 30)))
    }

    @Test("Back more than two hours later is a new visit to ask about, not overtime")
    func lateReturnIsAVisit() async {
        let harness = Harness(applies: true)
        _ = await harness.receive(.enterInner, at: Self.at(8, 55))
        _ = await harness.receive(.exitOuter, at: Self.at(17, 15))
        #expect(await harness.receive(.enterInner, at: Self.at(19, 30)) == .recordedForReview)
        #expect(harness.coordinator.state.awayStretches(dayKey: "2026-11-09").isEmpty)
        #expect(harness.coordinator.state.openVisit != nil)
    }

    @Test("Only learning you are there after the start asks you to check, instead of being dropped")
    func firstKnownAfterStart() async throws {
        let harness = Harness(applies: true)
        func initial(at time: Date) -> AutomationEvent {
            AutomationEvent(
                id: UUID(), source: .nativeGeofence, type: .enterInner, workplaceID: harness.workplace.id,
                registrationGeneration: harness.workplace.registrationGeneration,
                observedAt: time, receivedAt: time, timestampBasis: .systemObservation, isInitialState: true
            )
        }
        // Already there before the start: just where the person is.
        #expect(await harness.coordinator.receive(initial(at: Self.at(8, 40)), shifts: [Self.shift()], now: Self.at(8, 40))
            == .ignored)
        let late = initial(at: Self.at(10, 32))
        #expect(await harness.coordinator.receive(late, shifts: [Self.shift()], now: Self.at(10, 32)) == .recordedForReview)
        let pending = try #require(harness.coordinator.state.pendingProposals.first)
        #expect(pending.boundary == .start)
        #expect(pending.reasons.contains(.arrivalTimeUncertain))
        #expect(harness.records.state.overrides.isEmpty)
    }

    // MARK: Early arrival

    @Test("An early arrival asks once; started work counts from the arrival")
    func earlyStarted() async throws {
        let harness = Harness(applies: true)
        #expect(await harness.receive(.enterInner, at: Self.at(8, 10)) == .recordedForReview)
        let visit = try #require(harness.coordinator.state.openVisit)
        #expect(visit.promptAt == Self.at(8, 40))
        #expect(harness.prompts(now: Self.at(8, 15)).contains { $0.kind == .earlyVisit(visitID: visit.id) })

        #expect(await harness.coordinator.answerVisit(visit.id, startedWork: true, now: Self.at(8, 41)) == .applied)
        let day = try #require(harness.day("2026-11-09"))
        #expect(day.segments.first?.startAtMs == Self.ms(Self.at(8, 10)))
        // A second tap changes nothing.
        #expect(await harness.coordinator.answerVisit(visit.id, startedWork: true) == .alreadyApplied)
    }

    @Test("\"Just arrived early\" keeps the arrival and writes nothing")
    func earlyDeclined() async throws {
        let harness = Harness(applies: true)
        await harness.receive(.enterInner, at: Self.at(8, 10))
        let visit = try #require(harness.coordinator.state.openVisit)
        #expect(await harness.coordinator.answerVisit(visit.id, startedWork: false) == .applied)
        #expect(harness.coordinator.state.pendingProposals.isEmpty)
        #expect(harness.records.state.overrides.isEmpty)
        #expect(!harness.prompts(now: Self.at(8, 15)).contains { $0.visitID == visit.id })
    }

    @Test("An on-time arrival asks nothing about early work")
    func punctualNoVisit() async {
        let harness = Harness()
        await harness.receive(.enterInner, at: Self.at(8, 45))
        #expect(harness.coordinator.state.visits.isEmpty)
    }

    // MARK: Off-shift visits

    @Test("Extra work after the shift runs from arrival to leaving and keeps the day's plan")
    func offShiftConfirmed() async throws {
        let harness = Harness()
        // After the 17:00 end there is no shift to match.
        #expect(await harness.receive(.enterInner, at: Self.at(19)) == .recordedForReview)
        let visit = try #require(harness.coordinator.state.openVisit)
        guard case .offShift(let dayKey) = visit.kind else { Issue.record("expected an off-shift visit"); return }
        #expect(dayKey == "2026-11-09")
        #expect(harness.prompts(now: Self.at(19, 5)).contains { $0.kind == .offShiftVisit(visitID: visit.id) })

        #expect(await harness.coordinator.answerVisit(visit.id, startedWork: true, now: Self.at(19, 30)) == .recordedForReview)
        #expect(harness.records.state.overrides.isEmpty)
        await harness.receive(.exitOuter, at: Self.at(21))
        let day = try #require(harness.day("2026-11-09"))
        #expect(day.segments == [segment(Self.at(9), Self.at(12)), segment(Self.at(13), Self.at(17)),
                                 segment(Self.at(19), Self.at(21))])
    }

    @Test("Answering after leaving records the finished stretch on a rest day")
    func offShiftAnsweredLate() async throws {
        let harness = Harness()
        // Saturday: no shift at all.
        await harness.receive(.enterInner, at: Self.at(14, day: 14), shifts: [])
        let visit = try #require(harness.coordinator.state.openVisit)
        await harness.receive(.exitOuter, at: Self.at(16, day: 14), shifts: [])
        #expect(harness.coordinator.state.openVisit == nil)
        #expect(harness.prompts(now: Self.at(16, 5, day: 14), shifts: []).isEmpty)

        #expect(await harness.coordinator.answerVisit(visit.id, startedWork: true, now: Self.at(18, day: 14)) == .applied)
        #expect(harness.day("2026-11-14")?.segments == [segment(Self.at(14, day: 14), Self.at(16, day: 14))])
    }

    @Test("Saying no records nothing")
    func offShiftDeclined() async throws {
        let harness = Harness()
        await harness.receive(.enterInner, at: Self.at(19))
        let visit = try #require(harness.coordinator.state.openVisit)
        _ = await harness.coordinator.answerVisit(visit.id, startedWork: false)
        await harness.receive(.exitOuter, at: Self.at(21))
        #expect(harness.records.state.overrides.isEmpty)
    }

    @Test("A day off saved as a range ignores visits")
    func restRangeIgnoresVisit() async {
        let harness = Harness()
        harness.coordinator.update { $0.setContext(.rest, from: "2026-11-14", through: "2026-11-15") }
        #expect(await harness.receive(.enterInner, at: Self.at(14, day: 14), shifts: []) == .ignored)
        #expect(harness.coordinator.state.visits.isEmpty)
    }

    // MARK: Unreturned exits

    @Test("Leaving at lunch and coming back leaves no trace to review")
    func lunchReturn() async {
        let harness = Harness()
        await harness.receive(.enterInner, at: Self.at(8, 55))
        await harness.receive(.exitOuter, at: Self.at(12, 5))
        #expect(harness.coordinator.state.earlyExits["2026-11-09#day"] != nil)
        await harness.receive(.enterInner, at: Self.at(12, 50))
        #expect(harness.coordinator.state.earlyExits.isEmpty)
        harness.coordinator.surfaceUnreturnedExits(now: Self.at(18))
        #expect(!harness.coordinator.state.pendingProposals.contains { $0.boundary == .end })
    }

    @Test("Leaving early without returning becomes one review item after the shift")
    func unreturnedExit() async throws {
        let harness = Harness()
        await harness.receive(.enterInner, at: Self.at(8, 55))
        await harness.receive(.exitOuter, at: Self.at(15))
        harness.coordinator.surfaceUnreturnedExits(now: Self.at(16))
        #expect(!harness.coordinator.state.pendingProposals.contains { $0.boundary == .end })
        // The missing-end check comes half an hour after the planned end.
        let check = try #require(harness.prompts(now: Self.at(15, 30)).first { $0.kind == .missingEnd })
        #expect(check.fireAt == Self.at(17, 30))

        harness.coordinator.surfaceUnreturnedExits(now: Self.at(17, 1))
        let end = try #require(harness.coordinator.state.pendingProposals.first { $0.boundary == .end })
        #expect(end.proposedTime == Self.at(15))
        #expect(end.reasons.contains(.leftBeforePlannedEnd))
        #expect(!harness.prompts(now: Self.at(17, 2)).contains { $0.kind == .missingEnd })
    }

    @Test("Still inside after the plan: the check waits for the automatic window")
    func missingEndLate() async throws {
        let harness = Harness()
        await harness.receive(.enterInner, at: Self.at(8, 55))
        let check = try #require(harness.prompts(now: Self.at(10)).first { $0.kind == .missingEnd })
        #expect(check.fireAt == Self.at(23))
    }

    // MARK: Status question

    @Test("The next shift's question is planned 30 minutes after its start and goes once settled")
    func statusQuestion() async throws {
        let harness = Harness()
        let tomorrow = Self.shift(day: 10)
        let prompt = try #require(harness.prompts(now: Self.at(20), shifts: [Self.shift(), tomorrow]).first)
        #expect(prompt.kind == .status(.statusUnconfirmed))
        #expect(prompt.fireAt == Self.at(9, 30, day: 10))
        #expect(prompt.route == .workplaceAutomationStatus)

        #expect(await harness.coordinator.answerStatus(.continueRecording, for: tomorrow) == .applied)
        #expect(!harness.prompts(now: Self.at(20), shifts: [tomorrow]).contains { if case .status = $0.kind { true } else { false } })
    }

    @Test("A late arrival changes the question; an on-time one cancels it")
    func statusQuestionAfterArrival() async throws {
        let late = Harness()
        await late.receive(.enterInner, at: Self.at(9, 10))
        #expect(late.prompts(now: Self.at(9, 11)).first?.kind == .status(.lateArrival))

        let onTime = Harness()
        await onTime.receive(.enterInner, at: Self.at(8, 55))
        #expect(!onTime.prompts(now: Self.at(8, 56)).contains { if case .status = $0.kind { true } else { false } })
    }

    @Test("Taking today off marks the day; field work saves a one-day range")
    func statusAnswers() async {
        let rest = Harness()
        #expect(await rest.coordinator.answerStatus(.rest, for: Self.shift()) == .applied)
        #expect(rest.day("2026-11-09")?.kind == .notWorking)

        let field = Harness()
        #expect(await field.coordinator.answerStatus(.fieldwork, for: Self.shift()) == .applied)
        #expect(field.coordinator.state.context(for: "2026-11-09") == .fieldwork)
        #expect(field.coordinator.state.context(for: "2026-11-10") == .regular)
    }

    @Test("Away from the office, leaving it does not end the day")
    func fieldworkExit() async {
        let harness = Harness(applies: true)
        harness.coordinator.update { $0.setContext(.fieldwork, from: "2026-11-09", through: "2026-11-09") }
        await harness.receive(.enterInner, at: Self.at(9, 10))
        #expect(await harness.receive(.exitOuter, at: Self.at(18)) == .ignored)
        #expect(!harness.prompts(now: Self.at(18, 30)).contains { $0.kind == .missingEnd })
    }

    // MARK: Ranges

    @Test("A newer range replaces the days it covers and keeps the rest")
    func ranges() {
        var state = WorkplaceAutomationState()
        state.setContext(.businessTrip, from: "2026-11-10", through: "2026-11-20")
        state.setContext(.remote, from: "2026-11-14", through: "2026-11-15")
        #expect(state.context(for: "2026-11-13") == .businessTrip)
        #expect(state.context(for: "2026-11-14") == .remote)
        #expect(state.context(for: "2026-11-16") == .businessTrip)
        #expect(state.contexts.count == 3)
        state.setContext(.regular, from: "2026-11-01", through: "2026-11-30")
        #expect(state.contexts.isEmpty)
    }

    // MARK: Plus and storage

    @Test("Without Plus nothing is asked, but existing suggestions can still be adopted")
    func plusLapse() async throws {
        let harness = Harness()
        await harness.receive(.exitOuter, at: Self.at(18))
        let pending = try #require(harness.coordinator.state.pendingProposals.first)
        harness.plus.debugSetAuthorized(false)
        #expect(harness.prompts(now: Self.at(18, 1), shifts: [Self.shift(day: 10)]).isEmpty)
        #expect(await harness.receive(.enterInner, at: Self.at(19)) == .ignored)
        let results = await harness.coordinator.applyReviewed([pending.id], now: Self.at(18, 30))
        #expect(results[pending.id] == .applied)
        #expect(harness.day("2026-11-09")?.segments.last?.endAtMs == Self.ms(Self.at(18)))
    }

    @Test("Monitoring off reserves no slots and plans no questions")
    func monitoringOff() {
        let harness = Harness()
        harness.coordinator.update { $0.settings.isMonitoringEnabled = false }
        #expect(harness.prompts(now: Self.at(6)).isEmpty)
        #expect(WorkplaceAutomationNotificationPlan.shiftReminderBudget(isMonitoringEnabled: false)
            == WorkplaceAutomationNotificationPlan.shiftReminderBudget(isMonitoringEnabled: true) + 3)
        // Focus (2), alarm refresh (1), Live Activity fallback (1), reports and
        // automation stay within iOS's 64 pending requests.
        #expect(WorkplaceAutomationNotificationPlan.shiftReminderBudget(isMonitoringEnabled: true)
            + CycleReportNotificationPlan.reservedSlots + 3 + 4 <= 64)
    }

    @Test("A file from the first internal builds still opens")
    func decodesEarlierFile() throws {
        var state = WorkplaceAutomationState()
        state.settings.isMonitoringEnabled = true
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        for key in ["contexts", "settledShiftKeys", "visits", "earlyExits"] { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(
            WorkplaceAutomationState.self, from: JSONSerialization.data(withJSONObject: json)
        )
        #expect(decoded.settings.isMonitoringEnabled)
        #expect(decoded.visits.isEmpty)
    }

    @Test("Deleting automation data clears this device and keeps adopted hours")
    func eraseDeviceData() async throws {
        let harness = Harness(applies: true)
        harness.coordinator.update {
            $0.settings.visitPromptDelay = .sixtyMinutes
            $0.setContext(.remote, from: "2026-11-12", through: "2026-11-13")
        }
        #expect(await harness.receive(.enterInner, at: Self.at(9, 20)) == .applied)
        await harness.receive(.enterInner, at: Self.at(19))
        let adopted = try #require(harness.day("2026-11-09"))
        let generation = harness.coordinator.state.lastRegistrationGeneration
        #expect(harness.coordinator.state.hasDeviceData)

        #expect(harness.coordinator.eraseDeviceData())
        let state = harness.coordinator.state
        #expect(!state.hasDeviceData)
        #expect(state.workplaces.isEmpty && state.events.isEmpty && state.proposals.isEmpty)
        #expect(state.visits.isEmpty && state.contexts.isEmpty && state.insideWorkplaceIDs.isEmpty)
        #expect(!state.settings.isMonitoringEnabled)
        // Preferences survive; the generation keeps counting.
        #expect(state.settings.visitPromptDelay == .sixtyMinutes)
        #expect(state.lastRegistrationGeneration == generation)
        let next = try harness.coordinator.update { try $0.addWorkplace(name: "New", latitude: 31, longitude: 121) }
        #expect(next)
        #expect((harness.coordinator.state.workplaces.first?.registrationGeneration ?? 0) > generation)
        // Adopted hours are records, not automation data.
        #expect(harness.day("2026-11-09") == adopted)
        #expect(harness.prompts(now: Self.at(19, 5)).isEmpty)
    }

    // MARK: I2 follow-ups

    @Test("Coming from another workplace counts the move, from the earlier end")
    func movedBetweenWorkplaces() async throws {
        let harness = Harness()
        // Left the first workplace at 17:30, after the shift: an end to review.
        await harness.receive(.exitOuter, at: Self.at(17, 30))
        #expect(harness.coordinator.state.pendingProposals.contains { $0.boundary == .end })
        await harness.receive(.enterInner, at: Self.at(18))
        let visit = try #require(harness.coordinator.state.openVisit)
        #expect(await harness.coordinator.answerVisit(
            visit.id, startedWork: true, movedBetweenWorkplaces: true, now: Self.at(18, 30)
        ) == .recordedForReview)
        await harness.receive(.exitOuter, at: Self.at(20))
        #expect(harness.day("2026-11-09")?.segments == [segment(Self.at(9), Self.at(12)), segment(Self.at(13), Self.at(17)),
                                                         segment(Self.at(17, 30), Self.at(20))])
    }

    @Test("A move with no recent end, or one too long ago, counts from arrival")
    func movedWithoutRecentEnd() async throws {
        let harness = Harness()
        await harness.receive(.exitOuter, at: Self.at(17, 30))
        // 3 h later is more than a move.
        await harness.receive(.enterInner, at: Self.at(20, 30))
        let visit = try #require(harness.coordinator.state.openVisit)
        _ = await harness.coordinator.answerVisit(visit.id, startedWork: true, movedBetweenWorkplaces: true, now: Self.at(20, 40))
        await harness.receive(.exitOuter, at: Self.at(22))
        #expect(harness.day("2026-11-09")?.segments.last == segment(Self.at(20, 30), Self.at(22)))
    }

    @Test("Resuming a paused shift lets later crossings act on it again")
    func resumeAutomation() async throws {
        let harness = Harness(applies: true)
        let shift = Self.shift()
        harness.coordinator.update { $0.suppress(shiftKey: shift.shiftKey, at: Self.at(8)) }
        #expect(WorkplaceAutomationRules.resumableShifts(state: harness.coordinator.state, shifts: [shift], now: Self.at(8)) == [shift])
        #expect(await harness.receive(.enterInner, at: Self.at(9, 5)) == .ignored)

        #expect(harness.coordinator.resumeAutomation(shiftKey: shift.shiftKey))
        #expect(WorkplaceAutomationRules.resumableShifts(state: harness.coordinator.state, shifts: [shift], now: Self.at(9, 10)).isEmpty)
        #expect(await harness.receive(.enterInner, at: Self.at(9, 20)) == .applied)
    }

    @Test("A paused shift stops being offered once automation no longer matches it")
    func resumeWindow() {
        var state = WorkplaceAutomationState()
        let shift = Self.shift()
        state.suppress(shiftKey: shift.shiftKey, at: Self.at(8))
        #expect(WorkplaceAutomationRules.resumableShifts(state: state, shifts: [shift], now: Self.at(22, 59)) == [shift])
        #expect(WorkplaceAutomationRules.resumableShifts(state: state, shifts: [shift], now: Self.at(23)).isEmpty)
    }

    @Test("Arrival and departure notices say what changed and never repeat")
    func arrivalNotices() async throws {
        let harness = Harness(applies: true)
        let arrival = AutomationEvent(
            id: UUID(), source: .nativeGeofence, type: .enterInner, workplaceID: harness.workplace.id,
            registrationGeneration: harness.workplace.registrationGeneration,
            observedAt: Self.at(8, 45), receivedAt: Self.at(8, 45), timestampBasis: .systemObservation
        )
        // 08:45 plus the 30-minute wait passes 09:00: on time, not early.
        let outcome = await harness.coordinator.receive(arrival, shifts: [Self.shift()], now: Self.at(8, 45))
        #expect(outcome == .applied)
        let notice = try #require(WorkplaceArrivalNotice.make(for: arrival, outcome: outcome, state: harness.coordinator.state))
        #expect(notice.bodyKey == "automationNoticeArrivedApplied")
        // On time: the planned start is what was adopted.
        #expect(notice.time == Self.at(9))
        #expect(notice.identifier.hasPrefix(WorkplaceArrivalNotice.identifierPrefix))
        #expect(!notice.identifier.hasPrefix(WorkplaceAutomationNotificationPlan.identifierPrefix))

        #expect(WorkplaceArrivalNotice.make(for: arrival, outcome: .alreadyApplied, state: harness.coordinator.state) == nil)
        #expect(WorkplaceArrivalNotice.make(for: arrival, outcome: .ignored, state: harness.coordinator.state) == nil)
        var departure = arrival
        departure.type = .exitOuter
        #expect(WorkplaceArrivalNotice.make(for: departure, outcome: .recordedForReview, state: harness.coordinator.state)?.bodyKey
            == "automationNoticeLeftRecorded")
        var initial = arrival
        initial.isInitialState = true
        #expect(WorkplaceArrivalNotice.make(for: initial, outcome: .recordedForReview, state: harness.coordinator.state) == nil)
        var shortcut = arrival
        shortcut.source = .appIntentAutomation
        #expect(WorkplaceArrivalNotice.make(for: shortcut, outcome: .applied, state: harness.coordinator.state) == nil)

        // Leaving well after the end says how much overtime was recorded.
        let lateExit = AutomationEvent(
            id: UUID(), source: .nativeGeofence, type: .exitOuter, workplaceID: harness.workplace.id,
            registrationGeneration: harness.workplace.registrationGeneration,
            observedAt: Self.at(19, 20), receivedAt: Self.at(19, 20), timestampBasis: .systemObservation
        )
        let exitOutcome = await harness.coordinator.receive(lateExit, shifts: [Self.shift()], now: Self.at(19, 20))
        #expect(exitOutcome == .applied)
        let exitNotice = try #require(WorkplaceArrivalNotice.make(for: lateExit, outcome: exitOutcome, state: harness.coordinator.state))
        #expect(exitNotice.bodyKey == "automationNoticeLeftAppliedOvertime")
        #expect(exitNotice.overtime.map { abs($0 - 140 * 60) < 0.001 } == true)

        harness.coordinator.update { $0.settings.notifiesArrivalsAndDepartures = false }
        #expect(WorkplaceArrivalNotice.make(for: departure, outcome: .applied, state: harness.coordinator.state) == nil)
    }

    @Test("Settings saved before the notice switch existed keep notices on")
    func settingsDecodeDefault() throws {
        let json = #"{"isMonitoringEnabled":true,"appliesDetectedTimesAutomatically":false,"visitPromptDelay":30}"#
        let settings = try JSONDecoder().decode(WorkplaceAutomationSettings.self, from: Data(json.utf8))
        #expect(settings.isMonitoringEnabled)
        #expect(settings.notifiesArrivalsAndDepartures)
    }
}
